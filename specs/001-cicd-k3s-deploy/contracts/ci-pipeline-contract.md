# Contract: CI Pipeline (GitHub Actions)

**Feature**: [../spec.md](../spec.md) | Governs: `.github/workflows/ci.yml`

This is the contract the CI workflow exposes to contributors and to the deploy pipeline — its
trigger conditions, required status checks, and published outputs. Downstream consumers (branch
protection rules, the deploy workflow) depend on these names staying stable.

## Triggers

| Event | Condition |
|---|---|
| `pull_request` | targeting the default branch |
| `push` | to the default branch |

## Jobs & required status checks (names are part of the contract)

| Job name | Runs on | Gate |
|---|---|---|
| `lint` | `ubuntu-latest` | must pass before `build` |
| `sast` | `ubuntu-latest` | must pass before `build` |
| `build-and-scan` | `ubuntu-latest` | builds both images; Trivy report always runs; Trivy CRITICAL gate must pass before `publish` |
| `publish` | `ubuntu-latest`, **only on `push` to default branch, and only for same-repo (non-fork) context** | pushes both images to GHCR |

## Inputs (repository configuration this workflow depends on)

| Name | Kind | Required for |
|---|---|---|
| `GITHUB_TOKEN` | built-in Actions token, `packages: write` permission | `publish` job's GHCR login |

No additional repository secrets are required for the CI workflow — GHCR auth uses the built-in
token (research.md §5).

## Outputs (what downstream automation may rely on)

| Output | Produced when | Consumed by |
|---|---|---|
| `ghcr.io/<owner>/sample-app-backend:<commit_sha>` | `publish` job succeeds on default-branch push | Deploy workflow (see `deployment-access-contract.md`) |
| `ghcr.io/<owner>/sample-app-frontend:<commit_sha>` | `publish` job succeeds on default-branch push | Deploy workflow |
| `ghcr.io/<owner>/sample-app-{backend,frontend}:main` | same as above | human/manual reference to "current default-branch image" |
| Trivy SARIF report | `build-and-scan` job, every run | GitHub Security tab (Code Scanning) |

## Guarantees

1. **No publish without passing gates**: `publish` only runs if `lint`, `sast`, and
   `build-and-scan` (including the CRITICAL Trivy gate) all succeeded on the same commit
   (FR-004, FR-006).
2. **Fork isolation**: `publish` (and any step requiring `GITHUB_TOKEN` write scope) does not run
   for `pull_request` events originating from forks (FR-009).
3. **Findings stay visible regardless of outcome**: the Trivy report step runs unconditionally
   within `build-and-scan`, independent of whether the gate step later fails (FR-007).
4. **Tag stability**: once pushed, a `<commit_sha>`-tagged image is never overwritten; only the
   `main` tag moves.
