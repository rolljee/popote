import { defineConfig } from 'vite';
import elm from 'vite-plugin-elm';
import { VitePWA } from 'vite-plugin-pwa';

// base relative : le build se sert tel quel, quelle que soit l'adresse du container.
export default defineConfig({
	base: './',
	plugins: [
		elm({ debug: false }),
		// App installable sur l'écran d'accueil, utilisable hors connexion (au
		// supermarché). Le service worker met en cache le front ; l'API, elle,
		// n'est jamais mise en cache : c'est sync.js qui gère l'absence de réseau.
		VitePWA({
			registerType: 'autoUpdate',
			includeAssets: ['apple-touch-icon.png'],
			manifest: {
				name: 'La Popote',
				short_name: 'Popote',
				description: 'Planning des repas de la semaine',
				lang: 'fr',
				start_url: './',
				scope: './',
				display: 'standalone',
				theme_color: '#e4572e',
				background_color: '#fbf5ec',
				icons: [
					{ src: 'pwa-192.png', sizes: '192x192', type: 'image/png' },
					{ src: 'pwa-512.png', sizes: '512x512', type: 'image/png' },
					{ src: 'pwa-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
				],
			},
			workbox: {
				// woff2 seulement : tous les navigateurs visés le lisent, inutile de
				// précharger aussi les .woff de repli.
				globPatterns: ['**/*.{js,css,html,woff2,png}'],
				navigateFallbackDenylist: [/^\/api\//, /^\/health/],
			},
		}),
	],
	build: { target: 'safari16', outDir: 'dist' },
	server: {
		proxy: { '/api': 'http://localhost:8080' },
	},
});
