// Deux « téléphones » simulés contre le vrai serveur.
import assert from 'node:assert/strict';
import { mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { createApp } from '../server/app.js';
import { fileStore } from '../server/store.js';

let server;
let origin;
const realFetch = globalThis.fetch;

before(async () => {
	const dir = await mkdtemp(join(tmpdir(), 'popote-sync-'));
	server = createApp({ store: fileStore(join(dir, 'state.json')), token: 'foyer', staticDir: dir });
	await new Promise((resolve) => server.listen(0, resolve));
	origin = `http://localhost:${server.address().port}/`;
	globalThis.document = { visibilityState: 'hidden', addEventListener() {} };
	globalThis.addEventListener = () => {};
	globalThis.history = { replaceState() {} };
	globalThis.fetch = (url, init) => realFetch(new URL(url, origin), init);
});

after(() => {
	globalThis.fetch = realFetch;
	server.close();
});

// Chaque import avec un paramètre différent donne une instance isolée du module.
const phone = async (name, initial) => {
	const storage = new Map(initial ? [['popote.v1', JSON.stringify(initial)]] : []);
	globalThis.localStorage = {
		getItem: (k) => storage.get(k) ?? null,
		setItem: (k, v) => storage.set(k, v),
	};
	globalThis.location = { hash: '#foyer=foyer', pathname: '/', search: '' };
	const { createSync } = await import(`../src/sync.js?${name}`);
	const statuses = [];
	const sync = createSync({ stateKey: 'popote.v1', onRemote() {}, onStatus: (s) => statuses.push(s) });
	const use = () => (globalThis.localStorage = { getItem: (k) => storage.get(k) ?? null, setItem: (k, v) => storage.set(k, v) });
	return {
		statuses,
		async run() {
			use();
			await sync.now();
			assert.match(statuses.at(-1), /^Synchronisé/);
		},
		get: () => JSON.parse(storage.get('popote.v1')),
		set: (s) => storage.set('popote.v1', JSON.stringify(s)),
	};
};

const dish = (id) => ({ id, name: id, url: '', boite: true, seasons: [], starch: '', protein: '', style: '' });
const st = (dishes, meals = []) => ({ version: 3, dismissed: [], seeded: 5, dishes: dishes.map(dish), weeks: meals.length ? [{ monday: 100, meals }] : [] });
const meal = (slot, id) => ({ slot, locked: false, kind: 'dish', dish: id });

test('le second téléphone adopte le foyer, puis les modifications se croisent', async () => {
	const a = await phone('a', st(['a', 'b'], [meal(0, 'a')]));
	await a.run();

	const b = await phone('b', st(['seed']));
	await b.run();
	assert.deepEqual(b.get(), a.get(), 'B rejoint le foyer avec les données de A');

	a.set(st(['a', 'b'], [meal(0, 'a'), meal(1, 'b')]));
	b.set(st(['a', 'b', 'c'], [meal(0, 'a')]));
	await a.run();
	await b.run();
	await a.run();

	assert.deepEqual(a.get(), b.get());
	assert.deepEqual(
		a.get().dishes.map((d) => d.id),
		['a', 'b', 'c'],
	);
	assert.deepEqual(a.get().weeks[0].meals, [meal(0, 'a'), meal(1, 'b')]);
});
