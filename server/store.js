// Stockage du document du foyer : un seul objet JSON { version, updatedAt, state }.
//
// En production, un objet sur Object Storage Scaleway (API S3). En local, sans
// configuration S3, un simple fichier.

import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { AwsClient } from 'aws4fetch';

const EMPTY = { version: 0, updatedAt: null, state: null };

export function s3Store({ endpoint, region, bucket, accessKeyId, secretAccessKey, key = 'state.json' }) {
	const client = new AwsClient({ accessKeyId, secretAccessKey, service: 's3', region });
	const url = (name) => `${endpoint.replace(/\/$/, '')}/${bucket}/${name}`;

	const put = async (name, body) => {
		const res = await client.fetch(url(name), {
			method: 'PUT',
			headers: { 'Content-Type': 'application/json' },
			body,
		});
		if (!res.ok) throw new Error(`S3 PUT ${name} : ${res.status} ${await res.text()}`);
	};

	return {
		async load() {
			const res = await client.fetch(url(key));
			if (res.status === 404) return EMPTY;
			if (!res.ok) throw new Error(`S3 GET ${key} : ${res.status} ${await res.text()}`);
			return res.json();
		},
		async save(doc) {
			const body = JSON.stringify(doc);
			await put(key, body);
			// Une copie par jour, écrasée à chaque écriture de la journée : de quoi
			// revenir en arrière après une fausse manipulation (~20 Ko par jour).
			await put(`backups/${doc.updatedAt.slice(0, 10)}.json`, body);
		},
	};
}

export function fileStore(path) {
	return {
		async load() {
			try {
				return JSON.parse(await readFile(path, 'utf8'));
			} catch (err) {
				if (err.code === 'ENOENT') return EMPTY;
				throw err;
			}
		},
		async save(doc) {
			await mkdir(dirname(path), { recursive: true });
			await writeFile(`${path}.tmp`, JSON.stringify(doc));
			await rename(`${path}.tmp`, path);
		},
	};
}
