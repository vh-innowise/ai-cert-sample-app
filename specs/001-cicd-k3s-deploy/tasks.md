---

description: "Task list template for feature implementation"
---

# Tasks: CI/CD Pipeline & Local k3s Deployment

**Input**: Design documents from `/specs/001-cicd-k3s-deploy/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: The feature specification does not request automated contract/integration tests (this
is infrastructure, not application code with a test framework). Static validation (`actionlint`,
`kubeconform`) and the manual `quickstart.md` scenarios serve as this feature's verification —
included below as their own tasks rather than a separate TDD test phase.

**Organization**: Tasks are grouped by user story (from `spec.md`, priorities P1/P2/P3) to enable
independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Web app layout per `plan.md`: `.github/workflows/` (pipelines), `apps/backend/` + `apps/frontend/`
(existing app, new production Dockerfiles only), `deploy/k8s/` (cluster manifests), `infra/nginx-vm/`
(reference config for the existing external VM).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repo-level tooling scaffolding used by later phases

- [X] T001 [P] Create `.dockerignore` at repo root excluding `node_modules`, `.git`, `dist`,
      test files, and docs from the Docker build context, for use by the production Dockerfiles
      added in User Story 1 (`research.md` §2).
- [X] T002 [P] Create a Semgrep config/ignore file (`.semgrepignore` at repo root) scoping SAST to
      `apps/backend/src` and `apps/frontend/src` and excluding `apps/backend/generated/prisma`
      and test fixtures, for use by the `sast` job added in User Story 1 (`research.md` §3).
- [X] T003 [P] Create an empty `.trivyignore` at repo root as the documented location for future
      vulnerability-exception entries, referenced by the Trivy steps added in User Story 1
      (`research.md` §4).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared configuration and setup documentation that every user story's workflow/manifests reference

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create `deploy/README.md` documenting the one-time manual setup shared across all
      three user stories: GitHub Actions repository variables `APP_NAME=sample-app` and
      `DOMAIN_NAME=accelerator.test` (Settings → Actions → Variables), workflow permission
      "Read and write permissions" for the default `GITHUB_TOKEN` (Settings → Actions → General),
      the `KUBECONFIG` repository secret, self-hosted runner registration with label
      `k3s-local`, and the cluster-side `app-secrets` Secret / `app-config` ConfigMap
      prerequisites (`data-model.md` §4, `contracts/deployment-access-contract.md`).

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - Automated Quality & Security Gate on Every Change (Priority: P1) 🎯 MVP

**Goal**: Every push/PR automatically runs lint + SAST, then (if both pass) builds the sample
app's backend and frontend container images, scans them with Trivy, blocks on any CRITICAL
finding, and — on the default branch — publishes the images to GHCR.

**Independent Test**: Open a PR with a deliberate lint violation and confirm the pipeline blocks
it; open a clean PR and confirm lint, SAST, build, and the Trivy report all run and a merge to the
default branch results in a published GHCR image — with no deployment automation existing yet.

### Implementation for User Story 1

- [X] T005 [P] [US1] Create `apps/backend/Dockerfile`: multi-stage build (`node:22-slim` build
      stage running `npm ci` + `npm run build --workspace apps/backend`, slim runtime stage
      copying `dist/`, `generated/prisma`, prod `node_modules`, keeping the existing
      `docker-entrypoint.sh` as `ENTRYPOINT` unchanged) — `Dockerfile.dev` stays untouched
      (`research.md` §2).
- [X] T006 [P] [US1] Create `apps/frontend/Dockerfile`: multi-stage build (`node:22-slim` build
      stage running `npm ci` + `npm run build --workspace apps/frontend`, `nginx:alpine` runtime
      stage serving the built `dist/` static files) — `Dockerfile.dev` stays untouched
      (`research.md` §2).
- [X] T007 [US1] Create `.github/workflows/ci.yml` with a `lint` job (`ubuntu-latest`) that runs
      `npm run lint:backend` and `npm run lint:frontend`, triggered on `pull_request` and `push`
      to the default branch (`contracts/ci-pipeline-contract.md`).
- [X] T008 [US1] Add a `sast` job to `.github/workflows/ci.yml` running Semgrep
      (`semgrep/semgrep-action`) with the `p/ci` and `p/owasp-top-ten` rulesets against
      `apps/backend/src` and `apps/frontend/src` (`research.md` §3).
- [X] T009 [US1] Add a `build-and-scan` job to `.github/workflows/ci.yml` that builds
      `apps/backend/Dockerfile` and `apps/frontend/Dockerfile` via `docker/build-push-action`
      (build only, no push yet), gated on `lint` and `sast` both succeeding (FR-004).
- [X] T010 [US1] Add a Trivy full-severity report step (`aquasecurity/trivy-action`,
      `--severity CRITICAL,HIGH,MEDIUM`, SARIF output) to the `build-and-scan` job in
      `.github/workflows/ci.yml`, uploaded via `github/codeql-action/upload-sarif`, running
      unconditionally regardless of later gate outcome (`research.md` §4, FR-007).
- [X] T011 [US1] Add a second Trivy step to the `build-and-scan` job in
      `.github/workflows/ci.yml` gating on CRITICAL only (`--severity CRITICAL --exit-code 1`),
      after the report step from T010 (`research.md` §4, FR-006).
- [X] T012 [US1] Add a `publish` job to `.github/workflows/ci.yml` that logs into `ghcr.io` with
      `GITHUB_TOKEN` and pushes `ghcr.io/<owner>/sample-app-backend:<sha>` +
      `ghcr.io/<owner>/sample-app-backend:main` and the frontend equivalents, gated on
      `build-and-scan` succeeding, restricted to `push` events on the default branch from the
      same repository (not forks) (FR-008, FR-009, `contracts/ci-pipeline-contract.md`).
- [X] T013 [US1] Add an `actionlint` step (or lightweight job) to `.github/workflows/ci.yml`
      validating `.github/workflows/*.yml` syntax (`research.md` §12).
- [ ] T014 [US1] Validate User Story 1 end-to-end by following the "Validate User Story 1"
      section of `quickstart.md`: a lint-breaking PR is blocked, a clean PR passes lint/SAST/scan
      with a visible Trivy report, and merging to the default branch publishes both images to
      GHCR.

**Checkpoint**: User Story 1 is fully functional and independently testable — CI gate + GHCR
publish work with no deployment automation yet.

---

## Phase 4: User Story 2 - Automated Deployment to the Local Cluster (Priority: P2)

**Goal**: A self-hosted runner with network access to the local k3s cluster automatically updates
the running sample app workload to the newly published image, using a `Recreate` rollout so
exactly one version is ever live.

**Independent Test**: With a previous version already running, publish a new passing image (via
User Story 1) and confirm the deploy workflow updates the cluster workload with no manual
commands, using only the self-hosted runner, and that a stopped/offline runner produces a clear
failed run rather than hanging.

### Implementation for User Story 2

- [X] T015 [P] [US2] Create `deploy/k8s/app-config.yaml`: `ConfigMap` with non-secret backend env
      (e.g. DB host/port) (`data-model.md` §4).
- [X] T016 [P] [US2] Create `deploy/k8s/postgres-pvc.yaml`: `PersistentVolumeClaim` on k3s's
      default `local-path` StorageClass (`research.md` §11).
- [X] T017 [P] [US2] Create `deploy/k8s/postgres-deployment.yaml`: single-replica PostgreSQL 16
      `Deployment` referencing the `app-secrets` Secret (credentials) and the PVC from T016
      (`research.md` §11).
- [X] T018 [P] [US2] Create `deploy/k8s/postgres-service.yaml`: `ClusterIP` `Service` for
      Postgres, reachable only inside the cluster (`data-model.md` §4).
- [X] T019 [P] [US2] Create `deploy/k8s/backend-deployment.yaml`: backend `Deployment`,
      `strategy: Recreate`, env from `app-secrets` + `app-config`, image
      `ghcr.io/<owner>/sample-app-backend` with a placeholder tag for Kustomize to set
      (`research.md` §8).
- [X] T020 [P] [US2] Create `deploy/k8s/backend-service.yaml`: `NodePort` `Service` targeting the
      backend Deployment's pods (`data-model.md` §4).
- [X] T021 [P] [US2] Create `deploy/k8s/frontend-deployment.yaml`: frontend `Deployment`,
      `strategy: Recreate`, image `ghcr.io/<owner>/sample-app-frontend` with a placeholder tag
      (`research.md` §8).
- [X] T022 [P] [US2] Create `deploy/k8s/frontend-service.yaml`: `NodePort` `Service` targeting the
      frontend Deployment's pods (nginx container proxying `/api` internally to the `backend`
      Service, mirroring `vite.config.ts`'s dev proxy split) (`data-model.md` §4).
- [X] T023 [US2] Create `deploy/k8s/kustomization.yaml` wrapping the manifests from T015–T022, so
      `kustomize edit set image` can retarget the backend/frontend image tags (`research.md` §7).
- [X] T024 [US2] Add a `kubeconform` validation step to `.github/workflows/ci.yml` checking
      `deploy/k8s/*.yaml` against Kubernetes schemas (`research.md` §12).
- [X] T025 [US2] Create `.github/workflows/deploy.yml`: triggered by `workflow_run` on the CI
      workflow's success for the default branch, runs on a `[self-hosted, k3s-local]`-labeled
      runner, writes the `KUBECONFIG` secret to a runner-local temp file for the job's duration
      (`contracts/deployment-access-contract.md`).
- [X] T026 [US2] Add `kustomize edit set image` (backend + frontend to the new `<commit_sha>`
      tags) and `kubectl apply -f deploy/k8s/` steps to `.github/workflows/deploy.yml`
      (`research.md` §7, FR-011).
- [X] T027 [US2] Add failure handling to `.github/workflows/deploy.yml` so an unreachable cluster
      or offline self-hosted runner surfaces as a clearly failed run instead of hanging or
      silently succeeding (FR-013).
- [X] T028 [US2] Update `deploy/README.md` (from T004) with the concrete one-time commands to
      create the `app-secrets` Secret and to register the self-hosted runner with label
      `k3s-local` against this repository.
- [ ] T029 [US2] Validate User Story 2 end-to-end by following the "Validate User Story 2"
      section of `quickstart.md`: confirm exactly one backend and one frontend pod are
      `Ready` after a deploy with the correct image tag, and that stopping the runner then
      pushing a change produces a clearly failed deploy run.

**Checkpoint**: User Stories 1 AND 2 both work independently — new images are automatically
deployed to the cluster with exactly one version live.

---

## Phase 5: User Story 3 - Reach the Deployed App Locally over HTTPS by a Friendly Name (Priority: P3)

**Goal**: A developer can reach the deployed sample app at `https://sample-app.accelerator.test`
after a one-time local hosts-file entry and certificate trust step, with the bare
`accelerator.test` domain not serving the app.

**Independent Test**: With the app already deployed (User Story 2), add the documented hosts
entry, trust the nginx VM's certificate, browse to `https://sample-app.accelerator.test` and
confirm the app loads; browse to `https://accelerator.test` and confirm it does not.

### Implementation for User Story 3

- [X] T030 [P] [US3] Create `infra/nginx-vm/sample-app.conf`: reference nginx server-block config
      for the external VM — a `server` block for `sample-app.accelerator.test` (TLS termination,
      `proxy_pass` to the backend/frontend `NodePort`s) and a default/bare `accelerator.test`
      block that does not route to the sample app (`research.md` §9, `data-model.md` §5, FR-017).
- [X] T031 [P] [US3] Create `infra/nginx-vm/README.md` documenting self-signed certificate
      generation (SANs covering `accelerator.test` and `sample-app.accelerator.test`) and the
      one-time steps for a developer to trust that certificate locally (FR-016).
- [ ] T032 [US3] Validate User Story 3 end-to-end by following the "Validate User Story 3"
      section of `quickstart.md`: add the two-hostname hosts-file entry, trust the certificate,
      confirm `https://sample-app.accelerator.test` loads the app with no browser warning, and
      confirm `https://accelerator.test` does not serve the app.

**Checkpoint**: All three user stories are independently functional — the full CI → deploy →
locally-reachable-over-HTTPS flow works end-to-end.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and final acceptance checks spanning all three stories

- [X] T033 [P] Add a "CI/CD & Local k3s Deployment" section to root `README.md` linking to
      `deploy/README.md` and `specs/001-cicd-k3s-deploy/`.
- [X] T034 [P] Add an index entry for this feature's specs to `specs/MANIFEST.md`, per this
      repo's spec-indexing convention (`AGENTS.md`).
- [ ] T035 Run the full end-to-end scenario in `quickstart.md` ("all three stories together") to
      confirm SC-001, SC-003, and SC-005 from `spec.md` hold in practice.
- [X] T036 Review `deploy/k8s/*.yaml` and `.github/workflows/*.yml` to confirm no plaintext
      credentials were committed (only `Secret`/GitHub-secret references) — Constitution
      Principle IV.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends only on Foundational. No dependency on US2/US3.
- **User Story 2 (Phase 4)**: Depends on Foundational; in practice needs a published image from
  User Story 1 to deploy something real, but its manifests/workflow can be authored once
  Foundational is done.
- **User Story 3 (Phase 5)**: Depends on Foundational; its Independent Test assumes User Story 2
  has already deployed something to point the nginx VM config at.
- **Polish (Phase 6)**: Depends on all three user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: No dependencies on other stories — the true MVP slice.
- **User Story 2 (P2)**: Builds on User Story 1's published images; not independently
  *demonstrable* without US1 having published at least one image, but its own files (T015–T029)
  are authored independently of US1's files.
- **User Story 3 (P3)**: Builds on User Story 2's running deployment; same relationship — separate
  files, but its Independent Test requires US2 to have deployed already.

### Within Each User Story

- Dockerfiles/manifests (data files) before the workflow steps that reference them.
- `ci.yml` jobs (T007–T013, T024) are added incrementally to the same file — sequential, not
  parallel, even though later jobs don't logically block earlier ones' authorship.
- `deploy/k8s/kustomization.yaml` (T023) after all manifests it wraps (T015–T022).
- Validation task (last task in each story phase) after every other task in that phase.

### Parallel Opportunities

- All Setup tasks (T001–T003) in parallel.
- Within User Story 1: T005 and T006 (the two Dockerfiles) in parallel.
- Within User Story 2: T015–T022 (all `deploy/k8s/` manifests except `kustomization.yaml`) in
  parallel — eight independent files.
- Within User Story 3: T030 and T031 in parallel.
- Within Polish: T033 and T034 in parallel.

---

## Parallel Example: User Story 2

```bash
# Launch all independent deploy/k8s manifest files together:
Task: "Create deploy/k8s/app-config.yaml ConfigMap"
Task: "Create deploy/k8s/postgres-pvc.yaml PersistentVolumeClaim"
Task: "Create deploy/k8s/postgres-deployment.yaml Deployment"
Task: "Create deploy/k8s/postgres-service.yaml ClusterIP Service"
Task: "Create deploy/k8s/backend-deployment.yaml Deployment"
Task: "Create deploy/k8s/backend-service.yaml NodePort Service"
Task: "Create deploy/k8s/frontend-deployment.yaml Deployment"
Task: "Create deploy/k8s/frontend-service.yaml NodePort Service"
# Then, once all of the above exist:
Task: "Create deploy/k8s/kustomization.yaml wrapping all manifests above"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (`deploy/README.md`).
3. Complete Phase 3: User Story 1 (T005–T014).
4. **STOP and VALIDATE**: run the quickstart US1 scenario independently — lint/SAST/build/Trivy
   gate + GHCR publish all work with no deployment automation yet.
5. This is a legitimate, demoable MVP on its own: every change is now automatically vetted and
   published as a trustworthy image, even before anything auto-deploys.

### Incremental Delivery

1. Setup + Foundational → shared config/docs ready.
2. User Story 1 → validate independently → demo the quality/security gate (MVP).
3. User Story 2 → validate independently → demo automatic deployment on top of US1's images.
4. User Story 3 → validate independently → demo reaching the deployed app at a friendly local
   HTTPS URL.
5. Polish → documentation + final full end-to-end acceptance pass.

### Parallel Team Strategy

With multiple contributors, after Setup + Foundational:

- One contributor: User Story 1 (`.github/workflows/ci.yml` + both production Dockerfiles).
- Another: User Story 2's `deploy/k8s/` manifests (T015–T023), which don't depend on `ci.yml`
  existing — only `deploy.yml` (T025–T027) needs User Story 1's `ci.yml` to exist as a
  `workflow_run` trigger target.
- Another: User Story 3's `infra/nginx-vm/` reference config and docs, which reference hostnames
  from `research.md`/`data-model.md` directly and don't need US1/US2 code to exist to be authored
  (only to be *validated*).

---

## Notes

- [P] tasks touch different files with no authoring-order dependency.
- [Story] labels map each task to its user story for traceability back to `spec.md`.
- `.github/workflows/ci.yml` is shared across US1 (T007–T013) and US2 (T024) — those tasks are
  sequential edits to one file, not parallel, even though they're labeled with different stories.
- Every manifest/config task cites the `research.md` or `data-model.md` section it implements so
  implementation doesn't have to re-derive the decision.
- Commit after each task or logical group; stop at any checkpoint to validate a story
  independently before moving on.
