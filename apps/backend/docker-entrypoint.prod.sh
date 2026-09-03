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
# (built by `nest build`, same step that produces dist/src/main.js) requires its sibling
# generated/prisma/client via a plain CJS require, which resolves correctly under plain `node`.
echo "[entrypoint] Seeding database (idempotent upserts)..."
node dist/prisma/seed.js

# dist/src/main.js, not dist/main.js: tsc's implicit rootDir is the common ancestor of every
# compiled file, and since generated/prisma and prisma/seed.ts (siblings of src/, both required
# for the app and the seed step above) are included in the same `nest build` compile, that
# ancestor is apps/backend/ itself, not apps/backend/src/ — so output mirrors that one level
# deeper than nest-cli.json's sourceRoot: "src" alone would suggest.
echo "[entrypoint] Starting NestJS (production)..."
exec node dist/src/main
