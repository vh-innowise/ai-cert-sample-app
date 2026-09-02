# Contract: Deployment & Local Access

**Feature**: [../spec.md](../spec.md) | Governs: `.github/workflows/deploy.yml`,
`deploy/k8s/*.yaml`, nginx VM config, local hosts-file setup

## Deploy workflow contract

| Aspect | Contract |
|---|---|
| Trigger | `workflow_run` on the CI workflow (`ci-pipeline-contract.md`) completing successfully for the default branch |
| Runner | must carry the `[self-hosted, k3s-local]` label; job MUST fail (not hang) if no such runner is online (FR-013) |
| Cluster credentials | `KUBECONFIG` GitHub Actions secret, written to a runner-local temp file for the job's duration only |
| Action taken | `kustomize edit set image` (backend + frontend to the new `<commit_sha>` tag) then `kubectl apply -f deploy/k8s/` |
| Rollout strategy | `Recreate` on both `backend` and `frontend` Deployments — old pod fully terminates before the new one starts (research.md §8) |
| Post-condition | exactly one pod per component is `Ready`, referencing the new image tag (FR-012) |
| Failure mode | job fails with the underlying `kubectl`/connectivity error surfaced in the run log — no silent success (FR-013) |

## Kubernetes object contract (`deploy/k8s/`)

| Object | Name | Exposes |
|---|---|---|
| `Service` | `backend` | `NodePort`, stable port, targets backend Deployment pods |
| `Service` | `frontend` | `NodePort`, stable port, targets frontend Deployment pods (nginx serving static build, proxying `/api` to `backend` Service internally — mirrors `vite.config.ts`'s dev proxy split) |
| `Service` | `postgres` | `ClusterIP` only — never exposed outside the cluster |
| `Secret` | `app-secrets` | DB credentials + JWT secrets; created out-of-band, never committed |
| `ConfigMap` | `app-config` | non-secret env vars (e.g. DB host/port) |

Any consumer (nginx VM config) MUST target the `backend`/`frontend` `NodePort` values, not pod IPs
directly — pod IPs are not stable across a `Recreate` rollout.

## Local access contract

| Aspect | Contract |
|---|---|
| Hostnames | `accelerator.test` (bare domain, does not serve the app) and `sample-app.accelerator.test` (serves the app) — FR-017 |
| Hosts-file entry | `<nginx-vm-ip> accelerator.test sample-app.accelerator.test` (research.md §10 — both hostnames required, not just the bare domain) |
| TLS | self-signed certificate terminated at the nginx VM, covering both hostnames as SANs; developers trust it once locally (FR-016) |
| Routing | nginx VM `proxy_pass`es `sample-app.accelerator.test` requests to the `frontend` Service's NodePort over plain HTTP on the trusted local network |

## Guarantees

1. A Deployment Rollout only ever targets an image that passed every CI gate (transitively, via
   the `workflow_run` trigger depending on CI success).
2. At any point after a rollout completes, browsing to `https://sample-app.accelerator.test`
   reaches exactly one version of the app (SC-005) — never a mix of old/new pods.
3. Browsing to `https://accelerator.test` (bare domain) never reaches the sample app, so the same
   domain can host other apps under other subdomains without collision (FR-017).
