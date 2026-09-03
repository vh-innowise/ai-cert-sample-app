# Production image for the backend. Kept separate from Dockerfile.dev (which stays dev-only,
# per docs/adr/ADR-001) — this one compiles the app and ships a production start command instead
# of `nest start --watch`, and is what CI (User Story 1) builds, scans, and publishes to GHCR.

# ---- build: install deps, generate Prisma client, compile TypeScript ----
FROM node:22-slim AS build

# bcrypt/sharp native build toolchain + OpenSSL for Prisma's query engine (same as Dockerfile.dev)
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# npm workspaces: npm ci needs the root lockfile + every workspace's package.json.
COPY package.json package-lock.json ./
COPY apps/backend/package.json ./apps/backend/package.json
COPY apps/frontend/package.json ./apps/frontend/package.json

RUN npm ci

COPY apps/backend/prisma ./apps/backend/prisma
# Deliberately not copying prisma.config.ts here (matches Dockerfile.dev): its `env("DATABASE_URL")`
# helper validates the var eagerly at config-load time, but DATABASE_URL only exists at container
# runtime, not at image build time. Without the config file, `generate` falls back to Prisma's
# schema-path/migrations-path defaults, which already match this repo's layout.
# Run from apps/backend so engine paths are cwd-relative, matching native db:init/db:setup.
RUN cd apps/backend && npx prisma generate
# On this Prisma version (6.19.3), `prisma generate` emits ".ts"-extension relative
# imports/exports on Linux instead of ".js" — see apps/backend/Dockerfile.dev for the full
# explanation. Same fix applies here.
RUN find apps/backend/generated/prisma -type f -name '*.ts' ! -name '*.d.ts' -print0 \
  | xargs -0 sed -i -E "s/(from [\"'])([^\"']+)\.ts([\"'])/\1\2.js\3/g"

COPY apps/backend/src ./apps/backend/src
COPY apps/backend/tsconfig.json apps/backend/tsconfig.build.json ./apps/backend/
COPY apps/backend/nest-cli.json ./apps/backend/nest-cli.json

RUN npm run build --workspace apps/backend

# ---- runtime: what actually ships ----
FROM node:22-slim AS runtime

# openssl/ca-certificates for Prisma's query engine at runtime; kept minimal (no compiler
# toolchain) since we're not building any native modules in this stage.
RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV NODE_ENV=production

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json /app/package-lock.json ./
COPY --from=build /app/apps/backend/package.json ./apps/backend/package.json
COPY --from=build /app/apps/backend/dist ./apps/backend/dist
COPY --from=build /app/apps/backend/generated ./apps/backend/generated
COPY --from=build /app/apps/backend/prisma ./apps/backend/prisma
COPY apps/backend/docker-entrypoint.prod.sh ./apps/backend/docker-entrypoint.prod.sh
RUN chmod +x ./apps/backend/docker-entrypoint.prod.sh

EXPOSE 3000
ENTRYPOINT ["bash", "./apps/backend/docker-entrypoint.prod.sh"]
