# CI/CD & Local k3s Deployment — Setup

This documents the **one-time, manual** setup this feature depends on. None of it is created by
the pipeline itself — it's prerequisite configuration a repo admin/operator sets up once. See
[`specs/001-cicd-k3s-deploy/`](../specs/001-cicd-k3s-deploy/) for the full spec, plan, and design
decisions (`research.md` sections referenced below).

## 1. GitHub repository configuration

| Setting | Where | Value |
|---|---|---|
| Repository variable `APP_NAME` | Settings → Secrets and variables → Actions → Variables | `sample-app` |
| Repository variable `DOMAIN_NAME` | Settings → Secrets and variables → Actions → Variables | `accelerator.test` |
| Workflow permissions | Settings → Actions → General → Workflow permissions | "Read and write permissions" (needed so `GITHUB_TOKEN` can push to GHCR — `.github/workflows/ci.yml`'s `publish` job) |
| Secret `KUBECONFIG` | Settings → Secrets and variables → Actions → Secrets | base64-encoded kubeconfig for the local k3s cluster (used by `.github/workflows/deploy.yml`) |

`APP_NAME`/`DOMAIN_NAME` are referenced consistently across the CI workflow (image tagging), the
deploy workflow, `deploy/k8s/*.yaml`, and `infra/nginx-vm/` — see `research.md` §1 for why these
specific values were chosen.

To produce the `KUBECONFIG` secret value from an existing kubeconfig file on the self-hosted
runner's machine (`.github/workflows/deploy.yml` base64-decodes it back at deploy time):

```bash
base64 -w0 /path/to/your/kubeconfig | pbcopy   # then paste as the KUBECONFIG secret's value
```

## 2. Self-hosted runner

Register a self-hosted GitHub Actions runner (Settings → Actions → Runners → New self-hosted
runner) on a machine with direct network access to the local k3s cluster, with the label
`k3s-local`. `.github/workflows/deploy.yml` targets `runs-on: [self-hosted, k3s-local]` — see
`research.md` §6 for why only the deploy job (not CI) needs a self-hosted runner.

## 3. Cluster-side prerequisites

Before the first deploy, create the following in the cluster (namespace of your choice, referred
to below as the default namespace):

```bash
kubectl create secret generic app-secrets \
  --from-literal=DATABASE_URL='postgresql://accelerator:<choose-a-password>@postgres:5432/accelerator?schema=public' \
  --from-literal=POSTGRES_USER=accelerator \
  --from-literal=POSTGRES_PASSWORD='<choose-a-password>' \
  --from-literal=POSTGRES_DB=accelerator \
  --from-literal=JWT_ACCESS_SECRET="$(openssl rand -base64 32)"
```

This `app-secrets` Secret is referenced by name from `deploy/k8s/backend-deployment.yaml` and
`deploy/k8s/postgres-deployment.yaml` (see `data-model.md` §4) — it is created out-of-band and is
**never** committed to this repository (Constitution Principle IV).

`deploy/k8s/app-config.yaml` (the non-secret `ConfigMap`) **is** committed, since it holds no
credentials.

## 4. nginx VM (external reverse proxy)

The local k3s cluster and the "nginx VM" that fronts it are assumed to already exist (per the
feature spec's Assumptions) — this repo does not provision either. See
[`infra/nginx-vm/`](../infra/nginx-vm/) for the reference nginx config and certificate-trust
instructions to apply on that VM.

## Everything else

Runtime deploy mechanics (what the pipeline actually does once the above is in place) are
documented in `specs/001-cicd-k3s-deploy/quickstart.md`, which is the validation guide for all
three user stories end-to-end.
