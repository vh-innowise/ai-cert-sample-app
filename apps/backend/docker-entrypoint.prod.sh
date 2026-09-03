#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "[entrypoint] Applying pending Prisma migrations..."
npm run db:init

# Not `npm run db:seed` (`prisma db seed` → `ts-node prisma/seed.ts`): Prisma picks ESM loader
# mode for the seed subprocess because tsconfig.json's top-level compilerOptions.module is
# "nodenext", and ts-node's ESM loader doesn't fall back from an extensionless/`.js` specifier to
# the sibling `.ts` source for the generated Prisma client here, so it fails with
# ERR_MODULE_NOT_FOUND regardless of the import's extension. The compiled dist/prisma/seed.js
# (built by `nest build`, same step that produces dist/main) requires its sibling
# generated/prisma/client via a plain CJS require, which resolves correctly under plain `node`.
echo "[entrypoint] Seeding database (idempotent upserts)..."
node dist/prisma/seed.js

echo "[entrypoint] Starting NestJS (production)..."
exec node dist/main
