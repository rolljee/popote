import assert from 'node:assert/strict';
import { test } from 'node:test';
import { merge3, same } from '../src/merge.js';

const dish = (id, name = id) => ({ id, name, url: '', boite: true, seasons: [], starch: '', protein: '', style: '' });
const meal = (slot, id) => ({ slot, locked: false, kind: 'dish', dish: id });
const state = ({ dishes = [], meals = {}, dismissed = [] } = {}) => ({
	version: 3,
	dismissed,
	seeded: 5,
	dishes,
	weeks: Object.entries(meals).map(([monday, list]) => ({ monday: Number(monday), meals: list })),
});

const base = state({ dishes: [dish('a'), dish('b')], meals: { 100: [meal(0, 'a'), meal(1, 'b')] } });

test('deux modifications sur des repas différents sont conservées', () => {
	const local = state({ dishes: base.dishes, meals: { 100: [meal(0, 'b'), meal(1, 'b')] } });
	const remote = state({ dishes: base.dishes, meals: { 100: [meal(0, 'a'), meal(1, 'a')] } });
	const merged = merge3(base, local, remote);
	assert.deepEqual(merged.weeks[0].meals, [meal(0, 'b'), meal(1, 'a')]);
});

test('conflit sur le même repas : le local gagne', () => {
	const local = state({ dishes: base.dishes, meals: { 100: [meal(0, 'b'), meal(1, 'b')] } });
	const remote = state({ dishes: base.dishes, meals: { 100: [meal(0, 'c'), meal(1, 'b')] } });
	assert.equal(merge3(base, local, remote).weeks[0].meals[0].dish, 'b');
});

test("une suppression d'un côté l'emporte sur l'inchangé", () => {
	const local = state({ dishes: [dish('a')], meals: base.weeks.reduce((m, w) => ({ ...m, [w.monday]: w.meals }), {}) });
	const merged = merge3(base, local, base);
	assert.deepEqual(
		merged.dishes.map((d) => d.id),
		['a'],
	);
});

test('les ajouts des deux côtés sont réunis', () => {
	const local = state({ dishes: [...base.dishes, dish('c')], meals: { 100: base.weeks[0].meals } });
	const remote = state({ dishes: [...base.dishes, dish('d')], meals: { 100: base.weeks[0].meals, 107: [meal(0, 'd')] } });
	const merged = merge3(base, local, remote);
	assert.deepEqual(
		merged.dishes.map((d) => d.id),
		['a', 'b', 'd', 'c'],
	);
	assert.deepEqual(
		merged.weeks.map((w) => w.monday),
		[100, 107],
	);
});

test('idées écartées : ajout et retrait propagés', () => {
	const b = state({ dismissed: ['x', 'y'] });
	const merged = merge3(b, state({ dismissed: ['x', 'y', 'z'] }), state({ dismissed: ['x'] }));
	assert.deepEqual(merged.dismissed.sort(), ['x', 'z']);
});

test("same ignore l'ordre des clés et des listes", () => {
	const reordered = { ...base, dishes: [...base.dishes].reverse() };
	assert.ok(same(base, reordered));
	assert.ok(!same(base, state()));
});
