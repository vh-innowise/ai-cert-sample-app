# Implementation Plan: CI/CD Pipeline & Local k3s Deployment

**Branch**: `001-cicd-k3s-deploy` | **Date**: 2026-09-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-cicd-k3s-deploy/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Add a GitHub Actions pipeline that lints, SAST-scans, builds, Trivy-scans, and publishes the
sample app's backend and frontend container images to GHCR on every push/PR, gated so a CRITICAL
vulnerability or a failing lint/SAST check blocks publishing (User Story 1). A second workflow,
running on a self-hosted runner with network access to the local k3s cluster, deploys the newly
published images with a `Recreate` rollout so exactly one version is ever live (User Story 2).
The deployed app is reachable locally at `https://sample-app.accelerator.test` through an
existing external nginx VM that terminates a self-signed TLS cert and reverse-proxies to the
app's `NodePort` Services, resolved locally via a corrected two-hostname `/etc/hosts` entry
(User Story 3). Technical approach and every open decision are recorded in `research.md`.

## Technical Context

**Language/Version**: Pipeline/infra code itself is YAML (GitHub Actions) + Kubernetes manifest
YAML + a small amount of shell; the app being packaged is unchanged (Node.js 22, TypeScript,
NestJS 11 backend / React 19 frontend, per `CLAUDE.md`).

**Primary Dependencies**: GitHub Actions, Docker Buildx, Semgrep (SAST, research.md §3),
`aquasecurity/trivy-action` (research.md §4), GHCR, `kubectl` + Kustomize (research.md §7), k3s
(existing cluster), nginx (existing external VM, research.md §9), `actionlint` +
`kubeconform` (research.md §12).

**Storage**: PostgreSQL 16, deployed in-cluster as its own `Deployment` + `PersistentVolumeClaim`
(research.md §11) — same engine/version already used in local dev (`docker-compose.yml`), no
schema changes.

**Testing (of this feature)**: `actionlint` against `.github/workflows/*.yml`; `kubeconform`
against `deploy/k8s/*.yaml`; manual end-to-end validation scenarios in `quickstart.md` (there is
no automated test framework for "does a GitHub Actions pipeline behave correctly" beyond these
static checks plus real runs).

**Target Platform**: GitHub-hosted `ubuntu-latest` runners for the CI job; a self-hosted Linux
runner (label `k3s-local`) with network access to the cluster for the deploy job; the existing
local k3s cluster; the existing external nginx VM.

**Project Type**: Infrastructure/DevOps addition to the existing `accelerator-mini` web app
(`apps/backend` + `apps/frontend`) — no application feature code changes.

**Performance Goals**: Not specified by the spec as a hard requirement; keeping the CI
lint/SAST/build/scan feedback loop reasonably fast (informal target: comparable to the existing
`npm run test:backend`/`test:frontend` local run time, well under the length of a coffee break)
is a soft engineering goal, not a contractual one.

**Constraints**: Registry-publish and cluster-deploy credentials MUST NOT be exposed to
fork-originated PR runs (FR-009); exactly one live version of each component at any time
(FR-012/SC-005, achieved via `Recreate` strategy — research.md §8); no secrets committed to the
repo (Constitution Principle IV) — kubeconfig and DB/JWT credentials live in GitHub Actions
secrets and a Kubernetes `Secret` respectively, never in `deploy/k8s/*.yaml`.

**Scale/Scope**: One sample app (two deployable components: backend, frontend), one local/demo
environment, one self-hosted runner, one k3s cluster, one external nginx VM.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Applies? | Assessment |
|---|---|---|
| I. Layered Architecture, No Repository Layer | No | This feature adds no backend module code — no controller/service/Prisma changes. |
| II. Guarded, Cookie-Based Auth | No | No auth flow or guard changes; the deployed app runs the existing auth code unmodified. |
| III. Test-Gated Completion | Yes | The new CI pipeline *enforces* this principle at the infrastructure level (lint + SAST gates before build/publish); implementation tasks for this feature must still pass `npm run lint:*`/`test:*` themselves before being called done. |
| IV. Idempotent & Safe Data Operations | Yes | Backend image reuses the existing idempotent `docker-entrypoint.sh` unchanged (research.md §2); kubeconfig and DB/JWT credentials are GitHub/Kubernetes secrets, never committed (research.md §6, §11); no destructive cluster operations are part of the deploy workflow. |
| V. Verified Documentation | Yes | `research.md` and `contracts/` were written by checking actual repo files (`docker-compose.yml`, `Dockerfile.dev`, `package.json` scripts, `vite.config.ts` proxy split) rather than assuming; §10 explicitly corrects an unverified/non-functional literal instruction from the original request instead of propagating it. |

**Result**: PASS — no violations, no entries needed in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-cicd-k3s-deploy/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── ci-pipeline-contract.md
│   └── deployment-access-contract.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── ci.yml            # lint, sast, build-and-scan, publish jobs (contracts/ci-pipeline-contract.md)
    └── deploy.yml        # deploy job, runs on self-hosted [k3s-local] runner

apps/backend/
├── Dockerfile            # NEW — production multi-stage build (research.md §2); Dockerfile.dev untouched
└── ...                   # existing NestJS source, unchanged

apps/frontend/
├── Dockerfile            # NEW — production multi-stage build, nginx:alpine runtime (research.md §2)
└── ...                   # existing React source, unchanged

deploy/
└── k8s/
    ├── kustomization.yaml     # wraps manifests below; image tag substituted by `kustomize edit set image`
    ├── backend-deployment.yaml
    ├── backend-service.yaml
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── postgres-deployment.yaml
    ├── postgres-service.yaml
    ├── postgres-pvc.yaml
    └── app-config.yaml         # ConfigMap only — app-secrets Secret is created out-of-band, not committed

infra/
└── nginx-vm/
    └── sample-app.conf   # reference nginx server-block config for the external VM (data-model.md §5) — documentation/reference, not applied by the pipeline itself
```

**Structure Decision**: This is the existing "web application" layout (`apps/backend` +
`apps/frontend`) with three additive, non-invasive directories: `.github/workflows/` (pipeline
definitions), `deploy/k8s/` (cluster manifests), and `infra/nginx-vm/` (reference config for the
already-existing external VM, since that VM's own config isn't managed by this repo's pipeline —
FR-014/FR-015 require documenting it, not automating its provisioning, per the spec's
Assumptions). No existing backend/frontend source directories are restructured; `Dockerfile.dev`
and `docker-compose.yml` (native/dev workflow, ADR-001) are unmodified.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations — table intentionally omitted.
