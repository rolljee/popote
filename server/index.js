import { resolve } from 'node:path';
import { createApp } from './app.js';
import { fileStore, s3Store } from './store.js';

const env = process.env;

const store = env.S3_BUCKET
	? s3Store({
			endpoint: env.S3_ENDPOINT ?? 'https://s3.fr-par.scw.cloud',
			region: env.S3_REGION ?? 'fr-par',
			bucket: env.S3_BUCKET,
			accessKeyId: env.S3_ACCESS_KEY,
			secretAccessKey: env.S3_SECRET_KEY,
		})
	: fileStore(resolve(env.DATA_FILE ?? 'data/state.json'));

const server = createApp({
	store,
	token: env.POPOTE_TOKEN,
	staticDir: resolve(env.STATIC_DIR ?? 'dist'),
});

const port = Number(env.PORT ?? 8080);
server.listen(port, '0.0.0.0', () => {
	console.log(`popote en écoute sur :${port} (stockage ${env.S3_BUCKET ? `s3://${env.S3_BUCKET}` : 'fichier local'})`);
});

// Scaleway envoie SIGTERM avant d'éteindre le container : on laisse finir une
// écriture en cours plutôt que de la couper.
process.on('SIGTERM', () => server.close(() => process.exit(0)));
