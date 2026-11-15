import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { createApp } from '../server/app.js';
import { fileStore } from '../server/store.js';

let server;
let base;
const auth = { Authorization: 'Bearer secret', 'Content-Type': 'application/json' };
const state = { version: 3, dismissed: [], seeded: 1, dishes: [], weeks: [] };

before(async () => {
	const dir = await mkdtemp(join(tmpdir(), 'popote-'));
	await writeFile(join(dir, 'index.html'), '<h1>popote</h1>');
	server = createApp({ store: fileStore(join(dir, 'data', 'state.json')), token: 'secret', staticDir: dir });
	await new Promise((resolve) => server.listen(0, resolve));
	base = `http://localhost:${server.address().port}`;
});

after(() => server.close());

test('refuse sans le code du foyer', async () => {
	assert.equal((await fetch(`${base}/api/state`)).status, 401);
	assert.equal((await fetch(`${base}/api/state`, { headers: { Authorization: 'Bearer faux' } })).status, 401);
});

test('écriture conditionnelle : 200 puis 409 sur version périmée', async () => {
	assert.deepEqual(await (await fetch(`${base}/api/state`, { headers: auth })).json(), { version: 0, state: null });

	const put = (version, s) => fetch(`${base}/api/state`, { method: 'PUT', headers: auth, body: JSON.stringify({ version, state: s }) });

	const ok = await put(0, state);
	assert.equal(ok.status, 200);
	assert.deepEqual(await ok.json(), { version: 1 });

	const stale = await put(0, { ...state, seeded: 2 });
	assert.equal(stale.status, 409);
	assert.deepEqual(await stale.json(), { version: 1, state });

	assert.equal((await put(1, { nope: true })).status, 400);
});

test('sert le front et retombe sur index.html', async () => {
	const res = await fetch(`${base}/semaine`);
	assert.equal(res.status, 200);
	assert.match(await res.text(), /popote/);
	assert.equal((await fetch(`${base}/health`)).status, 200);
});
