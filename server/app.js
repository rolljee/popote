// Serveur HTTP de La Popote : sert le front (dist/) et l'API de synchro.
//
//   GET  /api/state   → { version, state }
//   PUT  /api/state   { version, state } → 200 { version } | 409 { version, state }
//   GET  /health      → 200
//
// Écriture conditionnelle : le client renvoie la version qu'il a lue. Si elle
// ne correspond plus, 409 avec l'état courant, et le client refusionne. Les
// écritures sont sérialisées dans le process ; le container est configuré avec
// max_scale = 1 pour que ce verrou suffise.

import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const MAX_BODY = 1024 * 1024;

const TYPES = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.css': 'text/css; charset=utf-8',
	'.json': 'application/json',
	'.webmanifest': 'application/manifest+json',
	'.png': 'image/png',
	'.svg': 'image/svg+xml',
	'.ico': 'image/x-icon',
	'.woff': 'font/woff',
	'.woff2': 'font/woff2',
};

const send = (res, status, body, headers = {}) => {
	const payload = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
	res.writeHead(status, {
		'Content-Type': 'application/json',
		'X-Content-Type-Options': 'nosniff',
		'Referrer-Policy': 'no-referrer',
		...headers,
	});
	res.end(payload);
};

const readBody = (req) =>
	new Promise((resolve, reject) => {
		const chunks = [];
		let size = 0;
		req.on('data', (chunk) => {
			size += chunk.length;
			if (size > MAX_BODY) {
				reject(Object.assign(new Error('trop gros'), { status: 413 }));
				req.destroy();
			} else chunks.push(chunk);
		});
		req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
		req.on('error', reject);
	});

const validState = (state) =>
	state && typeof state === 'object' && Array.isArray(state.dishes) && Array.isArray(state.weeks);

export function createApp({ store, token, staticDir, log = console }) {
	if (!token) throw new Error('POPOTE_TOKEN manquant');
	const expected = Buffer.from(`Bearer ${token}`);
	const authorized = (req) => {
		const got = Buffer.from(req.headers.authorization ?? '');
		return got.length === expected.length && timingSafeEqual(got, expected);
	};

	// Chaîne de promesses = verrou : une écriture à la fois.
	let queue = Promise.resolve();
	const exclusive = (fn) => {
		const run = queue.then(fn, fn);
		queue = run.catch(() => {});
		return run;
	};

	const api = async (req, res) => {
		if (!authorized(req)) return send(res, 401, { error: 'code du foyer invalide' });
		const noStore = { 'Cache-Control': 'no-store' };

		if (req.method === 'GET') {
			const doc = await store.load();
			return send(res, 200, { version: doc.version, state: doc.state }, noStore);
		}

		if (req.method === 'PUT') {
			let body;
			try {
				body = JSON.parse(await readBody(req));
			} catch (err) {
				return send(res, err.status ?? 400, { error: 'corps invalide' });
			}
			if (!Number.isInteger(body?.version) || !validState(body.state)) {
				return send(res, 400, { error: 'attendu : { version, state }' });
			}
			return exclusive(async () => {
				const current = await store.load();
				if (body.version !== current.version) {
					return send(res, 409, { version: current.version, state: current.state }, noStore);
				}
				const doc = { version: current.version + 1, updatedAt: new Date().toISOString(), state: body.state };
				await store.save(doc);
				return send(res, 200, { version: doc.version }, noStore);
			});
		}

		return send(res, 405, { error: 'méthode non permise' }, { Allow: 'GET, PUT' });
	};

	const files = async (req, res, pathname) => {
		if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, { error: 'méthode non permise' });
		const rel = normalize(decodeURIComponent(pathname)).replace(/^(\.\.[/\\])+/, '');
		let path = join(staticDir, rel);
		if (!path.startsWith(staticDir)) return send(res, 404, { error: 'introuvable' });
		if (pathname.endsWith('/')) path = join(path, 'index.html');

		let content;
		try {
			content = await readFile(path);
		} catch {
			// Application d'une seule page : toute adresse inconnue sert l'accueil.
			path = join(staticDir, 'index.html');
			content = await readFile(path);
		}
		// Les assets Vite portent un hash dans leur nom : cache permanent. Le
		// reste (index.html, sw.js, manifest) doit être revalidé à chaque fois,
		// sinon une nouvelle version ne serait jamais vue.
		const immutable = rel.startsWith('assets/') || rel.startsWith('/assets/');
		return send(res, 200, req.method === 'HEAD' ? '' : content, {
			'Content-Type': TYPES[extname(path)] ?? 'application/octet-stream',
			'Cache-Control': immutable ? 'public, max-age=31536000, immutable' : 'no-cache',
		});
	};

	return createServer(async (req, res) => {
		const { pathname } = new URL(req.url, 'http://localhost');
		try {
			if (pathname === '/health') return send(res, 200, { ok: true });
			if (pathname === '/api/state') return await api(req, res);
			if (pathname.startsWith('/api/')) return send(res, 404, { error: 'introuvable' });
			return await files(req, res, pathname);
		} catch (err) {
			log.error(err);
			if (!res.headersSent) send(res, 500, { error: 'erreur serveur' });
		}
	});
}
