# Quickstart: Validating CI/CD Pipeline & Local k3s Deployment

**Feature**: [spec.md](./spec.md) | **Contracts**: [contracts/](./contracts/)

This is a validation guide, not an implementation guide — it proves each user story works
end-to-end once the feature is implemented. See `data-model.md` and `contracts/` for the objects
referenced below; this file does not repeat their definitions.

## Prerequisites

- Repository has `packages: write` permission granted to `GITHUB_TOKEN` in workflow settings (no
  extra secret needed for GHCR — research.md §5).
- A self-hosted GitHub Actions runner is registered against this repo with the label
  `k3s-local`, running on a machine with network access to the local k3s cluster.
- The `KUBECONFIG` repository secret is set (base64-encoded kubeconfig for the local cluster).
- The `app-secrets` Kubernetes Secret and `app-config` ConfigMap already exist in the cluster
  (created out-of-band, per `contracts/deployment-access-contract.md` — not part of this
  quickstart).
- The local k3s cluster and the nginx VM already exist and are reachable (per spec Assumptions).
- You know the nginx VM's IP address (`<nginx-vm-ip>` below).

## Validate User Story 1 — Automated Quality & Security Gate (P1)

1. Create a branch with a deliberate lint violation (e.g. an unused variable) and open a PR
   against the default branch.
   - **Expected**: the `lint` check fails on the PR; `build-and-scan` and `publish` do not run
     (contracts/ci-pipeline-contract.md).
2. On a separate clean branch, open a PR with a trivial, valid change.
   - **Expected**: `lint` and `sast` both pass; `build-and-scan` builds both images and produces a
     Trivy report (visible in the PR checks / Security tab) without blocking, assuming no CRITICAL
     findings.
3. Merge the clean PR to the default branch.
   - **Expected**: the `publish` job runs and pushes `ghcr.io/<owner>/sample-app-backend:<sha>`
     and `ghcr.io/<owner>/sample-app-frontend:<sha>` (verify via `gh api
     /orgs/<owner>/packages` or the GHCR UI).

## Validate User Story 2 — Automated Deployment to the Local Cluster (P2)

Prerequisite: User Story 1's merge step has already produced a published image.

1. Watch the deploy workflow run (triggered by the CI workflow's success on the default branch).
   - **Expected**: it runs on the `k3s-local`-labeled self-hosted runner, not a hosted runner.
2. After it completes, run `kubectl get pods -l app=sample-app` against the cluster.
   - **Expected**: exactly one backend pod and one frontend pod are `Running`/`Ready`, and their
     image field matches the `<sha>` just published — no old-version pod left behind (FR-012).
3. Simulate two distinct failure modes (FR-013), then restart/reconnect the runner afterward:
   - **Runner online, cluster unreachable** (e.g. block the runner's network route to the
     cluster, or point `KUBECONFIG` at a bad context): the deploy job's "Verify cluster
     connectivity" step fails explicitly, and the run is marked **failed** with that error — not
     silently successful.
   - **Runner itself offline** (stop the self-hosted runner service entirely), then push another
     passing change: GitHub Actions cannot start the job at all, so it shows as **Queued**
     indefinitely in the Actions UI rather than "failed" — this is a GitHub Actions platform
     limitation for self-hosted runners (no workflow-level setting bounds queue time), not
     something `deploy.yml` can override. It is still clearly visible as stuck/incomplete, not a
     false "success".

## Validate User Story 3 — Reach the App Locally over HTTPS (P3)

Prerequisite: User Story 2 has successfully deployed at least once.

1. Add the hosts-file entry from `contracts/deployment-access-contract.md`:
   ```
   <nginx-vm-ip> accelerator.test sample-app.accelerator.test
   ```
2. Trust the nginx VM's self-signed certificate locally (one-time per machine) — e.g. import it
   into the OS/browser trust store.
3. Browse to `https://sample-app.accelerator.test`.
   - **Expected**: the sample app's login page loads with no browser security warning.
4. Browse to `https://accelerator.test` (bare domain, no subdomain).
   - **Expected**: this does **not** load the sample app (FR-017) — e.g. a default nginx page or
     404, confirming the bare domain isn't accidentally routed to it.

## End-to-end (all three stories together)

1. Push a normal, passing change to the default branch.
2. Confirm CI → publish → deploy all complete without manual intervention (SC-001, SC-003).
3. Refresh `https://sample-app.accelerator.test` in a browser already open on the app.
   - **Expected**: the page continues to work (no downtime observation is required — `Recreate`
     causes brief unavailability during the swap, which is expected, not a failure) and now
     reflects the new deployment once it completes.
