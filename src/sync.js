// Synchronisation avec le foyer, en arrière-plan.
//
// Le téléphone reste la source de vérité immédiate (localStorage) : l'app
// s'ouvre et se modifie hors connexion, le serveur n'est qu'un point de
// rendez-vous. À chaque synchro on fusionne (voir merge.js) puis on écrit avec
// le numéro de version lu ; si quelqu'un a écrit entre-temps, le serveur
// répond 409 avec son état et on refusionne.

import { merge3, same } from './merge.js';

const META_KEY = 'popote.sync';
const DEBOUNCE_MS = 1500;
const POLL_MS = 60_000;

const readJson = (key) => {
	try {
		const raw = localStorage.getItem(key);
		return raw ? JSON.parse(raw) : null;
	} catch {
		return null;
	}
};

const writeJson = (key, value) => {
	try {
		localStorage.setItem(key, JSON.stringify(value));
	} catch {
		/* stockage indisponible */
	}
};

// Le code du foyer arrive par un lien `…/#foyer=CODE`, ouvert une fois sur
// chaque téléphone. On le retire aussitôt de l'adresse pour qu'il ne reste ni
// dans l'historique ni dans une capture d'écran.
const tokenFromHash = () => {
	const match = location.hash.match(/foyer=([^&]+)/);
	if (!match) return null;
	history.replaceState(null, '', location.pathname + location.search);
	return decodeURIComponent(match[1]);
};

export function createSync({ stateKey, onRemote, onStatus }) {
	let meta = readJson(META_KEY) ?? { token: null, version: 0, base: null };
	const fromLink = tokenFromHash();
	if (fromLink && fromLink !== meta.token) {
		// Nouveau foyer : on repart de son état à lui.
		meta = { token: fromLink, version: 0, base: null };
		writeJson(META_KEY, meta);
	}

	let timer = null;
	let running = false;
	let again = false;

	const status = (text) => onStatus(text);
	const time = () => new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

	const api = async (method, body) => {
		const res = await fetch('api/state', {
			method,
			headers: { Authorization: `Bearer ${meta.token}`, 'Content-Type': 'application/json' },
			body: body && JSON.stringify(body),
			cache: 'no-store',
		});
		if (res.status === 401) throw Object.assign(new Error('unauthorized'), { code: 401 });
		if (res.status !== 200 && res.status !== 409) throw new Error(`HTTP ${res.status}`);
		return { status: res.status, doc: await res.json() };
	};

	const run = async () => {
		if (!meta.token) return;
		if (running) {
			again = true;
			return;
		}
		running = true;
		status('Synchronisation…');
		try {
			const start = readJson(stateKey);
			let { doc: remote } = await api('GET');

			let merged;
			for (let attempt = 0; ; attempt++) {
				merged =
					meta.base === null
						? // Première connexion : rejoindre le foyer, c'est adopter ses données.
							(remote.state ?? start)
						: merge3(meta.base, start, remote.state);
				if (!merged || same(merged, remote.state)) break;
				const { status: code, doc } = await api('PUT', { version: remote.version, state: merged });
				if (code === 200) {
					remote = { version: doc.version, state: merged };
					break;
				}
				if (attempt >= 3) throw new Error('conflit persistant');
				remote = doc;
			}

			meta = { ...meta, version: remote.version, base: merged };
			writeJson(META_KEY, meta);

			// Des modifications ont pu être faites pendant l'aller-retour : on les
			// rejoue par-dessus le résultat plutôt que de les écraser.
			const now = readJson(stateKey);
			const final = merge3(start, now, merged);
			if (final && !same(final, now)) {
				writeJson(stateKey, final);
				onRemote(final);
			}
			if (final && !same(final, merged)) again = true;
			status(`Synchronisé avec le foyer · ${time()}`);
		} catch (err) {
			status(
				err.code === 401
					? 'Code du foyer refusé : rouvre le lien de partage'
					: 'Hors connexion : synchro dès le retour du réseau',
			);
		} finally {
			running = false;
			if (again) {
				again = false;
				schedule(0);
			}
		}
	};

	const schedule = (delay = DEBOUNCE_MS) => {
		clearTimeout(timer);
		timer = setTimeout(run, delay);
	};

	return {
		enabled: () => Boolean(meta.token),
		initialStatus: () =>
			meta.token ? 'Synchronisation…' : "Pas de synchro : ouvre le lien du foyer pour partager la semaine.",
		start() {
			if (!meta.token) return;
			run();
			document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && run());
			addEventListener('online', run);
			setInterval(() => document.visibilityState === 'visible' && run(), POLL_MS);
		},
		now: run,
		// Appelé à chaque sauvegarde locale.
		changed(state) {
			if (meta.token && !same(state, meta.base)) schedule();
		},
	};
}
