# Data Model: CI/CD Pipeline & Local k3s Deployment

**Feature**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

This feature has no application database changes — it introduces *infrastructure configuration
objects* (workflows, images, cluster resources, and local access config). This document captures
those as entities in the same spirit as an application data model: what they are, their key
attributes, relationships, and lifecycle/state transitions.

## 1. CI Workflow Run
Represents one execution of the CI pipeline (spec's "Pipeline Run") for a single commit or PR.

| Attribute | Description |
|---|---|
| `trigger_event` | `push` (default branch) or `pull_request` |
| `commit_sha` | Git SHA the run is building |
| `lint_result` | pass / fail |
| `sast_result` | pass / fail (Semgrep `p/ci` + `p/owasp-top-ten`) |
| `build_result` | pass / fail (backend image, frontend image) |
| `trivy_report` | full-severity findings (always produced; §4 in research.md) |
| `trivy_gate_result` | pass / fail (CRITICAL-only gate) |
| `publish_result` | images pushed to GHCR, or skipped if any prior gate failed |
| `published_image_refs` | `ghcr.io/<owner>/sample-app-backend:<sha>`, `ghcr.io/<owner>/sample-app-frontend:<sha>` (only set when `publish_result` = success) |

**Relationships**: produces zero or two Container Images (backend + frontend) when it succeeds
through the publish stage.

**Lifecycle**: `triggered → linting → sast → building → scanning → (publishing | blocked)`.
Any stage failure short-circuits to `blocked` — later stages do not run (FR-004, FR-005, FR-006).

**Validation rules**:
- `publish_result` MUST be "skipped" unless `lint_result`, `sast_result`, `build_result` are all
  pass and `trivy_gate_result` is pass (FR-004, FR-006).
- For `trigger_event = pull_request` from a non-collaborator fork, no step may use registry-publish
  or cluster-deploy credentials (FR-009).

## 2. Container Image
One built, published artifact — either the backend or the frontend image.

| Attribute | Description |
|---|---|
| `component` | `backend` \| `frontend` |
| `registry_ref` | `ghcr.io/<owner>/sample-app-<component>` |
| `tag` | immutable per-commit tag = `commit_sha`; `main` is a second, moving tag re-pointed on default-branch success only |
| `vulnerability_findings` | list of {severity, package, id}, from the Trivy report pass |
| `gate_status` | pass (no CRITICAL) \| blocked (≥1 CRITICAL) |

**Relationships**: produced by exactly one CI Workflow Run; referenced by zero or one Deployment
Rollout (the one that deploys it).

**Validation rules**: an image with `gate_status = blocked` MUST NOT exist in the registry (the
publish step never runs for it — FR-006).

## 3. Deployment Rollout
One execution of the deploy workflow (spec's "Deployment") that updates the cluster's running
workloads to reference specific Container Images.

| Attribute | Description |
|---|---|
| `triggered_by` | the CI Workflow Run whose publish stage succeeded on the default branch |
| `target_images` | the backend + frontend `registry_ref:tag` being rolled out |
| `runner` | the self-hosted runner (label `[self-hosted, k3s-local]`) that executed it |
| `status` | succeeded \| failed |
| `failure_reason` | human-readable cause when `status = failed` (e.g. "runner offline", "cluster unreachable") — FR-013 |
| `strategy` | `Recreate` (research.md §8) |

**Relationships**: applies to exactly the backend and frontend Kubernetes Deployments; depends on
Postgres already being available in-cluster.

**Validation rules**: at every point in time, at most one Container Image per component is the
active target of a running pod (FR-012, SC-005) — enforced by the `Recreate` strategy, not by
this record itself.

## 4. Kubernetes Deployment (backend / frontend / postgres)
The declarative cluster objects under `deploy/k8s/`.

| Object | Purpose | Notes |
|---|---|---|
| `backend` Deployment | Runs the backend Container Image | `strategy: Recreate`; env from `app-secrets` Secret + `app-config` ConfigMap; entrypoint unchanged (`docker-entrypoint.sh` auto-migrates + idempotently seeds) |
| `frontend` Deployment | Runs the frontend Container Image (nginx serving static build) | `strategy: Recreate` |
| `postgres` Deployment | Single-replica PostgreSQL 16 | Backed by a `PersistentVolumeClaim` on k3s's default `local-path` StorageClass (research.md §11) |
| `backend` / `frontend` Service | `type: NodePort`, stable node port per component | Target for the nginx VM's `proxy_pass` (research.md §9) |
| `postgres` Service | `type: ClusterIP` | Only reachable inside the cluster, by the backend Deployment |
| `app-secrets` Secret | DB credentials, JWT secrets | Created out-of-band (not committed); referenced by name from the Deployments |
| `app-config` ConfigMap | Non-secret env (e.g. `DATABASE_URL` host/port, feature flags) | Committed under `deploy/k8s/` |

**Relationships**: `backend` Deployment depends on `postgres` Service being resolvable; both
`backend`/`frontend` Services are the entities the nginx VM's config points at.

## 5. Local Access Configuration
The spec's "Local Access Configuration" entity, concretized.

| Attribute | Description |
|---|---|
| `hosts_entry` | `<nginx-vm-ip> accelerator.test sample-app.accelerator.test` — both hostnames on one line (research.md §10, correcting the literal single-hostname instruction) |
| `nginx_vm_server_blocks` | one `server` block per hostname: `sample-app.accelerator.test` (`proxy_pass` → backend/frontend NodePorts) and a default/bare `accelerator.test` block that does **not** route to the app (FR-017) |
| `tls_cert` | self-signed cert issued for CN/SAN covering `accelerator.test` + `sample-app.accelerator.test`, terminated at the nginx VM |
| `trust_step` | one-time, per-developer-machine step to add `tls_cert` to the local OS/browser trust store |

**Relationships**: depends on a Deployment Rollout having succeeded (there must be something
running behind the NodePorts for the proxy to serve).

**Validation rules**: requests to the bare `accelerator.test` hostname MUST NOT be routed to the
sample app's Services (FR-017); requests to `sample-app.accelerator.test` MUST reach the frontend
Service (which itself calls the backend Service internally, mirroring the existing dev proxy
split in `vite.config.ts`).
