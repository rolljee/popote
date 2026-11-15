import '@fontsource/atkinson-hyperlegible-next/400.css';
import '@fontsource/atkinson-hyperlegible-next/700.css';
import '@fontsource/fraunces/600.css';
import '@fontsource/fraunces/800.css';
import './styles.css';
import { Elm } from './Main.elm';
import { createSync } from './sync.js';

const KEY = 'popote.v1';

const read = () => {
	try {
		const raw = localStorage.getItem(KEY);
		return raw ? JSON.parse(raw) : null;
	} catch {
		return null;
	}
};

// Jour courant en nombre de jours depuis le 1970-01-01, à l'heure locale
const now = new Date();
const today = Math.floor((now.getTime() - now.getTimezoneOffset() * 60000) / 86400000);

let app;
const sync = createSync({
	stateKey: KEY,
	onRemote: (state) => app.ports.remoteState.send(state),
	onStatus: (text) => app?.ports.syncStatus.send(text),
});

app = Elm.Main.init({
	node: document.getElementById('app'),
	flags: { today, saved: read(), sync: sync.initialStatus() },
});

app.ports.save.subscribe((state) => {
	try {
		localStorage.setItem(KEY, JSON.stringify(state));
	} catch {
		/* stockage indisponible : l'export JSON reste possible */
	}
	sync.changed(state);
});

sync.start();
