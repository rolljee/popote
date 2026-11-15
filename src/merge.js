// Fusion à trois voies de l'état encodé par `Data.encode` (format version 3).
//
// `base` est le dernier état connu commun aux deux côtés (la dernière synchro
// réussie). Pour chaque élément — un plat, un repas d'un créneau, une idée
// écartée — on regarde qui l'a changé depuis `base` :
//   - un seul côté l'a changé : sa version gagne (y compris une suppression) ;
//   - les deux l'ont changé différemment : `local` gagne, c'est le téléphone
//     qu'on a en main.
// Deux personnes qui modifient des repas différents ne s'écrasent donc jamais.

const keyed = (state) => {
	const dishes = new Map();
	const meals = new Map();
	for (const dish of state?.dishes ?? []) dishes.set(dish.id, dish);
	for (const week of state?.weeks ?? []) {
		for (const meal of week.meals ?? []) meals.set(`${week.monday}:${meal.slot}`, meal);
	}
	return { dishes, meals, dismissed: new Set(state?.dismissed ?? []) };
};

const json = (value) => (value === undefined ? undefined : JSON.stringify(canonObj(value)));

const pick = (b, l, r) => {
	const [jb, jl, jr] = [json(b), json(l), json(r)];
	if (jl === jr) return l;
	if (jl === jb) return r;
	return l;
};

const mergeMaps = (base, local, remote, order) => {
	const out = new Map();
	for (const key of order) {
		if (out.has(key)) continue;
		const value = pick(base.get(key), local.get(key), remote.get(key));
		if (value !== undefined) out.set(key, value);
	}
	return out;
};

export function merge3(base, local, remote) {
	if (!remote) return local;
	if (!local) return remote;
	const b = keyed(base);
	const l = keyed(local);
	const r = keyed(remote);

	// Ordre des plats : celui du distant, puis les nouveaux plats locaux.
	const dishes = mergeMaps(b.dishes, l.dishes, r.dishes, [...r.dishes.keys(), ...l.dishes.keys()]);
	const meals = mergeMaps(b.meals, l.meals, r.meals, [...r.meals.keys(), ...l.meals.keys(), ...b.meals.keys()]);

	const dismissed = [...new Set([...r.dismissed, ...l.dismissed])].filter((name) => {
		const inL = l.dismissed.has(name);
		const inR = r.dismissed.has(name);
		return b.dismissed.has(name) ? inL && inR : inL || inR;
	});

	const weeks = new Map();
	for (const [key, meal] of meals) {
		const monday = Number(key.split(':')[0]);
		if (!weeks.has(monday)) weeks.set(monday, []);
		weeks.get(monday).push(meal);
	}

	return {
		version: Math.max(local.version ?? 3, remote.version ?? 3),
		dismissed,
		seeded: Math.max(local.seeded ?? 1, remote.seeded ?? 1),
		dishes: [...dishes.values()],
		weeks: [...weeks.entries()]
			.sort(([a], [b2]) => a - b2)
			.map(([monday, list]) => ({ monday, meals: list.sort((x, y) => x.slot - y.slot) })),
	};
}

// Égalité indépendante de l'ordre des clés et des listes.
export function same(a, b) {
	const canon = (state) => {
		if (!state) return null;
		const k = keyed(state);
		const sorted = (map) => [...map.entries()].sort(([x], [y]) => (x < y ? -1 : x > y ? 1 : 0)).map(([key, v]) => [key, canonObj(v)]);
		return JSON.stringify([sorted(k.dishes), sorted(k.meals), [...k.dismissed].sort(), state.seeded ?? 1]);
	};
	return canon(a) === canon(b);
}

const canonObj = (value) =>
	value && typeof value === 'object' && !Array.isArray(value)
		? Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonObj(value[key])]))
		: value;
