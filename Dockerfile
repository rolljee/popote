# syntax=docker/dockerfile:1

# --- Étape 1 : build du front (Elm + Vite) --------------------------------
# Image Debian complète, ni Alpine ni slim : le compilateur Elm est lié à la
# glibc, et télécharge ses paquets en HTTPS avec les certificats du système,
# absents de l'image slim. Cette étape ne finit pas dans l'image finale.
FROM node:24 AS front

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY elm.json index.html vite.config.js ./
COPY public ./public
COPY src ./src
RUN npm run build


# --- Étape 2 : dépendances du serveur -------------------------------------
FROM node:24-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev


# --- Étape 3 : runtime ----------------------------------------------------
FROM node:24-alpine

ENV NODE_ENV=production
ENV PORT=8080

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=front /app/dist ./dist
COPY package.json ./
COPY server ./server

# Utilisateur non privilégié fourni par l'image node.
USER node

EXPOSE 8080

# `node` directement, et non `npm start` : npm en PID 1 ne relaie pas SIGTERM.
#
# POPOTE_TOKEN et les clés S3 sont fournis à l'exécution
# (secret_environment_variables côté Scaleway) et ne sont jamais dans l'image.
CMD ["node", "server/index.js"]
