# Production image for the frontend. Kept separate from Dockerfile.dev (which stays dev-only,
# per docs/adr/ADR-001) — this one builds the static bundle and serves it via nginx instead of
# the Vite dev server, and is what CI (User Story 1) builds, scans, and publishes to GHCR.

# ---- build: compile the static bundle ----
FROM node:22-slim AS build

WORKDIR /app

COPY package.json package-lock.json ./
COPY apps/backend/package.json ./apps/backend/package.json
COPY apps/frontend/package.json ./apps/frontend/package.json

RUN npm ci

COPY apps/frontend ./apps/frontend

RUN npm run build --workspace apps/frontend

# ---- runtime: nginx serving the static build ----
FROM nginx:alpine AS runtime

COPY apps/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/apps/frontend/dist /usr/share/nginx/html

EXPOSE 80
