# Research: CI/CD Pipeline & Local k3s Deployment

**Feature**: [spec.md](./spec.md) | **Date**: 2026-09-02

Purpose: resolve every open technical decision needed before design (Phase 1) so `plan.md`'s
Technical Context has no `NEEDS CLARIFICATION` markers left.

## 1. Placeholder values for `<app-name>` and `<domain-name>`

- **Decision**: `<app-name>` = `sample-app` (matches the repository directory name).
  `<domain-name>` = `accelerator.test`. Full app URL: `https://sample-app.accelerator.test`.
- **Rationale**: `.test` is an IANA-reserved TLD (RFC 2606) guaranteed to never resolve on the
  public internet, so it's safe for a local-only hosts-file entry with no risk of colliding with
  or leaking to a real domain. Using the actual repo/app name keeps the URL self-explanatory.
- **Alternatives considered**: `.local` — rejected, it's reserved for mDNS/Bonjour and can behave
  unpredictably on some OSes; a made-up `.dev`/`.app` TLD — rejected, both are real, publicly
  routable, HSTS-preloaded TLDs owned by Google, so a typo'd real request could hit unexpected
  behavior.
- Both values are read from workflow/manifest variables, not hardcoded in multiple places, so a
  different environment can override them without editing pipeline logic.

## 2. Production container images (none exist yet)

- **Decision**: Add two new **production** Dockerfiles — `apps/backend/Dockerfile` and
  `apps/frontend/Dockerfile` — separate from the existing `Dockerfile.dev` files (which stay
  dev-only, per `docs/adr/ADR-001`). Both are multi-stage: a `node:22-slim` build stage running
  `npm ci` + the workspace's existing `build` script, then a minimal runtime stage.
  - Backend runtime stage: `node:22-slim`, copies `dist/`, `generated/prisma`, and production
    `node_modules`; keeps the existing `docker-entrypoint.sh` (auto `prisma migrate deploy` +
    idempotent seed) as its entrypoint, unchanged, so Principle IV (idempotent data ops) keeps
    holding in production the same way it already does in the dev Compose stack.
  - Frontend runtime stage: `nginx:alpine` serving the static `vite build` output from `dist/`.
    This is a **different nginx** from the "nginx VM" in FR-014/FR-015 — this one only serves
    static files inside its own container; the nginx VM is the external reverse proxy in front of
    the whole cluster (see §6). Naming this distinction explicitly avoids confusing the two in
    later implementation.
- **Rationale**: `Dockerfile.dev` images install full dev dependencies and run via `nest
  start --watch` / `vite --host` — unsuitable and oversized for a scanned, published, deployed
  image. A separate prod Dockerfile keeps the dev workflow (ADR-001) completely untouched.
- **Alternatives considered**: reusing `Dockerfile.dev` with a build-arg switch — rejected, it
  would couple the dev hot-reload flow to production concerns and complicate the Trivy scan
  surface with dev-only tooling (compilers, `ts-node`, etc.) that doesn't belong in a shipped
  image.

## 3. SAST tool choice

- **Decision**: [Semgrep](https://semgrep.dev) OSS CLI via `semgrep/semgrep-action`, run with the
  `p/ci` and `p/owasp-top-ten` rulesets against `apps/backend/src` and `apps/frontend/src`.
- **Rationale**: Runs on any repo without requiring GitHub Advanced Security licensing (unlike
  CodeQL's default setup on private repos), has first-class TypeScript/React/NestJS rule support,
  and produces SARIF that can still be uploaded to the GitHub Security tab for visibility.
- **Alternatives considered**: CodeQL — rejected as the default choice because it needs GHAS
  entitlement on private repositories to run in Actions, which cannot be assumed here; ESLint
  security plugins only — rejected as insufficient, that's lint-adjacent pattern matching, not a
  dedicated SAST engine, and the spec (FR-002/FR-003) already separates lint and SAST as distinct
  gates.

## 4. Trivy severity gate (block CRITICAL, report HIGH+) — how to implement with one tool

- **Decision**: Run `aquasecurity/trivy-action` twice against the built image in the same job:
  1. **Report pass** (no `exit-code`): full `--severity CRITICAL,HIGH,MEDIUM` scan, output SARIF,
     uploaded via `github/codeql-action/upload-sarif` so all findings stay visible regardless of
     outcome (satisfies FR-007).
  2. **Gate pass**: `--severity CRITICAL --exit-code 1` — fails the job (and thus blocks the
     publish step that follows) only when a CRITICAL finding exists (satisfies FR-006).
- **Rationale**: Trivy's `--exit-code` applies to whichever `--severity` list is passed in that
  invocation; running it twice cleanly separates "always report" from "sometimes block" without
  needing to post-process JSON output by hand.
- **Alternatives considered**: single invocation parsing JSON output with a shell script to decide
  pass/fail — rejected as more custom logic than necessary for the same outcome the two-pass
  approach gets for free.

## 5. GHCR authentication & image tagging

- **Decision**: Authenticate to `ghcr.io` using the workflow's built-in `GITHUB_TOKEN` (with
  `packages: write` permission granted in the workflow), not a separate PAT. Tag scheme:
  `ghcr.io/<owner>/sample-app-backend:<git-sha>` and `ghcr.io/<owner>/sample-app-frontend:<git-sha>`,
  plus a moving `:main` tag re-pointed only on pushes to the default branch (never on PR builds).
- **Rationale**: `GITHUB_TOKEN` scoped to the repository is sufficient for GHCR under the same
  owner and avoids managing/rotating a long-lived PAT secret. Per-commit SHA tags give the
  deployment step (§7) an unambiguous, immutable reference to roll out, while `:main` remains a
  convenient human-readable pointer to "whatever is currently deployed."
- **Alternatives considered**: Docker Hub — rejected, GHCR was explicitly requested; a single
  combined image for both apps — rejected, backend and frontend have unrelated runtimes/ports and
  scale/restart independently, matching how they're already split in `docker-compose.yml`.

## 6. Self-hosted runner scope & cluster credentials

- **Decision**: A single self-hosted runner, labeled `[self-hosted, k3s-local]`, is registered
  against this repository and used **only** for the deploy job — the CI job (lint/SAST/build/scan/
  push) stays on GitHub-hosted `ubuntu-latest` runners. The deploy job authenticates to the
  cluster via a `KUBECONFIG` GitHub Actions secret (the kubeconfig content, base64-encoded),
  written to a runner-local temp file at job start and referenced only for that job's duration.
- **Rationale**: A GitHub-hosted runner has no network path to a "local" cluster, so only the
  deploy job needs self-hosted capacity — keeping CI on hosted runners avoids consuming
  self-hosted capacity for work that doesn't need it and keeps the fast lint/SAST/build feedback
  loop unaffected by self-hosted runner availability. Storing kubeconfig as a secret (rather than
  pre-installed on the runner) keeps cluster credentials under GitHub's secret rotation/audit
  trail instead of static runner-disk state.
- **Constitution check**: this directly implements Principle IV (`.env`/secrets MUST NOT be
  committed) — the kubeconfig is a GitHub encrypted secret, never a repo file.

## 7. Kubernetes deployment mechanism

- **Decision**: Plain Kubernetes manifests (`Deployment`, `Service`, `Secret` refs, `ConfigMap`)
  under a `deploy/k8s/` directory, applied with `kubectl apply -f` after substituting the new
  image tag via `kustomize edit set image` (a lightweight `kustomization.yaml` wrapping the
  manifests) — not a full Helm chart.
- **Rationale**: One sample app, one environment, no multi-environment templating need — a Helm
  chart would add a templating layer and a release-management concept this feature doesn't need.
  This matches the constitution's simplicity stance (no abstraction beyond what the task
  requires).
- **Alternatives considered**: Helm — rejected as unnecessary complexity for a single-environment
  demo deployment; raw `kubectl set image` with no manifests under version control — rejected,
  it would leave the cluster's desired state undocumented and unreproducible from the repo.

## 8. Deployment strategy — exactly one live version (FR-012 / SC-005)

- **Decision**: Backend and frontend `Deployment` objects use `strategy: Recreate`, not the
  Kubernetes default `RollingUpdate`.
- **Rationale**: `RollingUpdate` intentionally runs old and new pods simultaneously during
  rollout, which directly conflicts with SC-005 ("at no point are two different versions
  simultaneously reachable"). `Recreate` terminates the old pod before starting the new one,
  guaranteeing exactly one version is ever live, at the cost of a few seconds of downtime per
  deploy — acceptable for a local/demo environment that isn't a production SLA-bound service.
- **Alternatives considered**: `RollingUpdate` with `maxUnavailable: 0, maxSurge: 1` — rejected,
  still briefly runs two versions concurrently; blue/green or canary via a service mesh — rejected
  as significant infrastructure this feature's scope (a training/demo app) doesn't justify.

## 9. Local access path: nginx VM → k3s → app

- **Decision**: Expose each app's `Service` inside k3s as `NodePort` (not `LoadBalancer`/
  `ClusterIP`). The external nginx VM's config gets one `server` block per app subdomain
  (`sample-app.accelerator.test`), each `proxy_pass`-ing to `https://<k3s-node-ip>:<nodePort>`... 
  actually plain `http://<k3s-node-ip>:<nodePort>` internally, since TLS is terminated at the
  nginx VM (self-signed cert covering `accelerator.test` + `sample-app.accelerator.test` as SANs)
  and the hop from the VM to the cluster stays on the trusted local network unencrypted, matching
  FR-016.
- **Rationale**: `NodePort` needs no additional in-cluster controller beyond what k3s ships with
  and gives the external nginx VM a stable `<node-ip>:<port>` target. Terminating TLS once, at the
  VM, means only one certificate to generate and trust locally (one moving part), rather than
  also configuring TLS inside the cluster's own ingress.
- **Alternatives considered**: k3s's built-in ServiceLB (Klipper) `LoadBalancer` type — rejected,
  adds a second layer of IP indirection with no benefit over NodePort for a single-node/local
  cluster the nginx VM already reaches directly; TLS termination inside the cluster (ingress-nginx
  + cert-manager) — rejected in the spec's own clarification (self-signed, manually trusted at a
  single point was the chosen TLS strategy), and terminating twice would need two certs trusted.

## 10. Hosts-file entry — correcting the literal instruction

- **Decision**: The hosts-file entry documented in `quickstart.md` maps **both** hostnames to the
  nginx VM's IP on one line: `<nginx-vm-ip> accelerator.test sample-app.accelerator.test`, not
  only the bare domain as literally written in the original request.
- **Rationale**: `/etc/hosts` performs exact hostname matching, not wildcard/subdomain matching —
  an entry for `accelerator.test` alone does **not** make `sample-app.accelerator.test` resolve.
  Since FR-014 requires the app to be reachable at the `sample-app.accelerator.test` subdomain
  specifically (and FR-017 requires the bare domain to *not* serve the app), the subdomain must be
  present in the hosts file itself for name resolution to work at all; the bare-domain entry is
  optional (kept here only so `accelerator.test` also resolves, to something other than the app,
  per FR-017) but the subdomain entry is not.
- This is a documentation correction, not a scope change — flagging it now so implementation
  doesn't propagate the original phrasing's literal (non-functional) form into `quickstart.md`.

## 11. Postgres for the deployed app

- **Decision**: Deploy PostgreSQL 16 in-cluster as its own single-replica `Deployment` + `PVC`
  (backed by k3s's default `local-path` storage class) + `Service`, with credentials in a
  Kubernetes `Secret` referenced by both Postgres and the backend `Deployment`'s env vars. No
  application code changes — the backend image's existing `docker-entrypoint.sh` already runs
  `prisma migrate deploy` then the idempotent seed on startup (Principle IV), so it behaves
  identically against this Postgres as it does against the dev Compose one.
- **Rationale**: The spec's assumption is that only the cluster and nginx VM themselves are
  pre-provisioned, not application datastores; a demo app deployment needs *some* Postgres to
  connect to, and standing one up in-cluster keeps the whole stack self-contained and reproducible
  from the manifests in `deploy/k8s/`, with no external dependency to separately document.
- **Alternatives considered**: pointing at an externally-managed Postgres instance — rejected, it
  would introduce an undocumented out-of-repo dependency for what is meant to be a self-contained
  local demo deployment.

## 12. Meta-validation of pipeline/manifest artifacts

- **Decision**: Add `actionlint` (workflow YAML syntax/semantics) and `kubeconform` (Kubernetes
  manifest schema validation) as lightweight checks in the CI job, run against
  `.github/workflows/*.yml` and `deploy/k8s/*.yaml` respectively.
- **Rationale**: Both are fast, dependency-free CLI checks that catch structural mistakes in the
  pipeline/manifests themselves before they reach the self-hosted runner or the cluster, cheap
  insurance for infrastructure code that has no other automated test coverage.
- **Alternatives considered**: no meta-validation, relying only on a real deploy to surface
  mistakes — rejected, that pushes feedback all the way to the self-hosted-runner/cluster stage
  for errors (e.g. a YAML typo) that are cheap to catch immediately in the hosted CI job.

## Summary of resolved unknowns

| Technical Context field | Resolution |
|---|---|
| Primary Dependencies | GitHub Actions, Docker Buildx, Semgrep, Trivy, GHCR, kubectl + Kustomize, k3s, nginx (VM) |
| Storage | PostgreSQL 16, deployed in-cluster (§11) |
| Testing (of this feature) | `actionlint` + `kubeconform` static checks; manual quickstart validation scenarios (§12) |
| Target Platform | GitHub-hosted `ubuntu-latest` (CI job) + self-hosted Linux runner with cluster network access (deploy job) + existing local k3s cluster + existing nginx VM |
| Project Type | Infra/DevOps addition to an existing web app (backend + frontend) |
| Constraints | No cluster/registry credentials on fork PRs (FR-009); exactly one live app version at a time (FR-012/SC-005 → §8) |
| Scale/Scope | Single sample app, single local/demo environment, one self-hosted runner |

No `NEEDS CLARIFICATION` markers remain.
