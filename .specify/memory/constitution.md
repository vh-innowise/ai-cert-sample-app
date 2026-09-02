<!--
Sync Impact Report
- Version change: [TEMPLATE] → 1.0.0 (initial ratification)
- Modified principles: n/a (first fill of placeholder template)
- Added sections:
  - Core Principles: I. Layered Architecture, No Repository Layer
  - Core Principles: II. Guarded, Cookie-Based Auth
  - Core Principles: III. Test-Gated Completion
  - Core Principles: IV. Idempotent & Safe Data Operations
  - Core Principles: V. Verified Documentation
  - Technology Constraints
  - Development Workflow
  - Governance
- Removed sections: none (placeholder scaffold only)
- Templates requiring follow-up: none — dependent commands (plan/spec/tasks templates) read this
  file at runtime and are not modified by this command.
- Deferred placeholders: none remaining
-->

# accelerator-mini Constitution

## Core Principles

### I. Layered Architecture, No Repository Layer
Backend code MUST follow the existing per-module layering: `<module>.controller.ts` →
`<module>.service.ts` → `PrismaService` called directly. Services MUST call
`this.prisma.<model>.*` inline; a repository abstraction MUST NOT be introduced unless a task
explicitly requests one. New modules MUST live under `apps/backend/src/modules/<module>/`;
cross-cutting code MUST live in `apps/backend/src/shared/`.
Rationale: the codebase has already standardized on this pattern (see
`modules/users/user-admin.service.ts`); introducing a second, partial abstraction layer would
create inconsistent codepaths and make behavior harder to predict across modules.

### II. Guarded, Cookie-Based Auth
Authentication MUST remain cookie-based (httpOnly access/refresh/impersonation-session cookies),
never a client-attached bearer token. The global guard order — `JwtAuthGuard` → `RolesGuard` →
`ChildAccountGuard` → `ThrottlerGuard` — MUST be preserved, since `RolesGuard` depends on
`req.user` populated by `JwtAuthGuard`. Routes MUST use `@Public()` to bypass auth and
`@Roles(Role.X)` to restrict it, rather than ad hoc checks inside handlers. The `Role` enum is
`SUPER_ADMIN | TRAINER | COACH | PLAYER`; there is no `PARENT` role — parent/child accounts are
both `PLAYER`, linked via `User.parentUserId`.
Rationale: the guard chain and cookie flow are load-bearing for session refresh and
impersonation; reordering or bypassing them silently breaks auth for unrelated routes.

### III. Test-Gated Completion
A task MUST NOT be reported complete until tests and lint pass for every workspace touched
(`npm run test:backend` / `npm run test:frontend`, `npm run lint:backend` / `npm run
lint:frontend`). Pre-commit hooks MUST NOT be skipped (`--no-verify`), and force-push or hard
reset MUST NOT be used without explicit user consent. For UI-facing changes, the feature MUST be
exercised in a running browser before being called done; a claim of success MUST be scoped to
what was actually verified (tests vs. visual check).
Rationale: this repo's own `AGENTS.md` and `.claude/DOD.md` already enforce this at the agent
level — the constitution makes it a first-class project rule rather than tooling-only policy.

### IV. Idempotent & Safe Data Operations
`prisma/seed.ts` MUST remain idempotent (`upsert` keyed on unique fields, empty `update: {}`),
since the Docker entrypoint runs it on every container startup. Destructive operations (dropping
tables, `docker:reset-db`, force-push, hard reset) MUST NOT be run without explicit user consent.
`.env`/`.env.*` files and anything under `secrets/` MUST NOT be read, written, or edited by an
agent; env/Docker issues MUST be diagnosed from `docker-compose.yml` and the tracked
`.env.example`, with the user asked to change their real `.env` themselves.
Rationale: seed idempotency and env-file isolation are both safety properties that silently
protect local dev data and secrets — violating either has caused real breakage before.

### V. Verified Documentation
API routes, DTOs, and roles MUST NOT be documented or referenced in specs/docs without being
verified against the actual controllers (`grep` for `@Get`/`@Post`/etc.) and
`apps/backend/prisma/schema.prisma`. Specs MUST be indexed in `specs/MANIFEST.md`; skill/agent
output files MUST be prefixed `{skill-name}-{purpose}.md`; task docs MUST live in zero-padded
`tasks/TASK-{N}/` directories per `tasks/.task-counter`.
Rationale: this repo has already suffered a docs pass that fabricated a `/users` REST surface
and a nonexistent `PARENT` role — verified-against-source is the only way specs stay trustworthy.

## Technology Constraints

- Stack is fixed unless a task explicitly changes it: NestJS 11 + Prisma 6.19 + PostgreSQL 16
  (`apps/backend`), React 19 + Vite 8 + Tailwind v4 (`apps/frontend`), npm workspaces monorepo.
- Prisma client output is `apps/backend/generated/prisma`, not the default location — code MUST
  import from there, not `node_modules/.prisma`.
- Local dev runs natively (`npm run dev:backend` / `dev:frontend`) or via the Docker Compose
  stack (`npm run docker:up[:build]`); `POSTGRES_HOST_PORT` MUST stay `55432` by default to avoid
  colliding with a pre-existing local Postgres — it MUST NOT be "fixed" back to `5432`.
- `/uploads` is intentionally unauthenticated static Express middleware outside the Nest guard
  chain; nothing sensitive MUST be placed under `uploads/`.

## Development Workflow

- Backend tests are colocated `*.spec.ts` (Jest, `rootDir: src`); frontend tests are colocated
  `*.test.tsx` (Vitest). New code MUST include at least happy-path coverage colocated with the
  code it tests, matching this layout.
- Before marking any task done, apply the tier from `.claude/DOD.md` matching its scope (Minimum
  / Standard / Full) and record what was actually verified.
- Specs, task docs, and skill output follow the naming and location rules in `AGENTS.md`; that
  file is enforceable policy, not optional guidance, for any agent working in this repo.
- Style invariants (naming, TypeScript strictness, error handling, file/function length) follow
  `.claude/GOLDEN-PRINCIPLES.md` where that file exists.

## Governance

This constitution supersedes ad hoc conventions and prior undocumented practice for
`accelerator-mini`. Where it conflicts with a stale spec or doc (e.g. a spec claiming a
repository layer that Principle I forbids), the verified state of the code and this constitution
win, and the stale doc MUST be corrected rather than followed.

**Amendment procedure**: amendments are made only via the `/speckit-constitution` command, which
rewrites this file, prepends a Sync Impact Report, and bumps the version per the policy below.
Ad hoc hand-edits to this file outside that command SHOULD be avoided so the Sync Impact Report
stays accurate.

**Versioning policy** (semantic versioning):
- MAJOR: backward-incompatible principle removal or redefinition.
- MINOR: a new principle or materially expanded section added.
- PATCH: wording clarifications, typo fixes, non-semantic refinements.

**Compliance review**: substantive changes touching backend/frontend code SHOULD be checked
against the Core Principles above before being called complete, using the Full tier of
`.claude/DOD.md` as the concrete checklist. Any deviation from a principle MUST be justified in
the task's context summary, not silently introduced.

**Version**: 1.0.0 | **Ratified**: 2026-09-02 | **Last Amended**: 2026-09-02
