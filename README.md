# La Popote

Planning des repas de la semaine pour la famille : un bouton tire les 14 repas
(midi + soir), chaque repas se change dans un accordéon.

Elm 0.19.3 + Vite, installable sur l'écran d'accueil (PWA) et utilisable hors
connexion. Un petit serveur Node sert le front et synchronise le planning entre
les téléphones du foyer.

```bash
npm install
npm run dev:server   # API sur :8080, données dans data/state.json (code du foyer : dev)
npm run dev          # http://localhost:5173/#foyer=dev
npm test
npm run format
```

## Synchronisation

- Chaque téléphone garde ses données dans son `localStorage` : l'app s'ouvre et
  se modifie sans réseau, le serveur n'est qu'un point de rendez-vous.
- Le **code du foyer** arrive par un lien `…/#foyer=CODE`, ouvert une fois par
  téléphone (`make popote-link` dans le dépôt Kompas). Le premier téléphone
  connecté envoie ses données ; les suivants **adoptent** celles du foyer.
- À chaque modification (et au retour dans l'app, et toutes les minutes), le
  client fusionne à trois voies (`src/merge.js`) : par plat, par repas, par
  idée écartée. Deux personnes qui changent des repas différents ne
  s'écrasent jamais ; sur le même repas, le téléphone en main gagne.
- Le serveur (`server/`) stocke un seul document `{ version, state }` sur
  Object Storage, avec écriture conditionnelle (409 si la version a bougé) et
  une copie par jour dans `backups/`.

## Déploiement

https://popote.rolljee.fr — Scaleway Serverless Container dans le namespace `kompas`, déclaré dans le
dépôt Kompas (`popote.tf`). Chaque push sur `main` publie
`ghcr.io/rolljee/popote:latest` et demande à Scaleway de redéployer. Ce dépôt
n'exécute jamais Terraform.

Variables d'environnement du serveur : `POPOTE_TOKEN` (obligatoire),
`S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_REGION`, `S3_ENDPOINT`.
Sans `S3_BUCKET`, stockage dans un fichier (`DATA_FILE`, par défaut
`data/state.json`).

## Règles du foyer (`src/Data.elm`)

- Dîners ×2 du dimanche, lundi et mercredi → boîte pour le midi du lendemain
  (lundi, mardi, jeudi). Ces dîners sont tirés parmi les plats « boîte ».
- Plats de saison (saison du jeudi de la semaine) ; pas de doublon dans la semaine ; un plat vu dans les ± 4 semaines a moins de
  chances de sortir (`src/Draw.elm`).
- Équilibre : chaque plat a un féculent, une protéine et un style ; un tirage
  pénalise fortement les répétitions dans la semaine (`src/Draw.elm`).
- Onglet Idées : suggestions (`ideas` dans `src/Data.elm`) à ajouter ou écarter.
- Au tirage, les repas verrouillés, les restes et les créneaux libres sont gardés.
