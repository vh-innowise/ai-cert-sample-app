# Feature Specification: CI/CD Pipeline & Local k3s Deployment

**Feature Branch**: `001-cicd-k3s-deploy`

**Created**: 2026-09-02

**Status**: Draft

**Input**: User description: "Using GitHub Actions, for the sample app: 1. Create pipelines for CI / lint / SAST, build the sample app Docker image, run a Trivy scan, and push to GitHub Container Registry 2. Set up a self-hosted runner to deploy the sample app to the local k3s cluster 3. Ensure the sample app is accessible locally via https://<app-name>.<domain-name> or https://<domain-name>/<app-name> – add <nginx-vm-ip> <domain-name> to local /etc/hosts"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated Quality & Security Gate on Every Change (Priority: P1)

A contributor pushes a commit or opens a pull request against the sample app. Before any code
can be merged or an image published, an automated pipeline checks the code for style/lint
violations and known security anti-patterns (SAST), then builds a container image and scans it
for known vulnerabilities. Only changes that pass these checks result in a published,
trustworthy image.

**Why this priority**: This is the foundation everything else depends on — without a reliable
build/lint/security gate, there is nothing safe to deploy. It also delivers immediate value on
its own (catching bugs and vulnerabilities before they reach `main`) even if deployment
automation doesn't exist yet.

**Independent Test**: Open a pull request with a deliberately introduced lint violation and,
separately, one with a clean change. Confirm the pipeline fails and blocks the first, and passes
and produces a container image for the second — without any deployment step existing yet.

**Acceptance Scenarios**:

1. **Given** a pull request is opened against the repository, **When** the pipeline runs,
   **Then** lint and static application security testing (SAST) both execute and their pass/fail
   status is visible on the pull request.
2. **Given** a change contains a lint violation, **When** the pipeline runs, **Then** the pipeline
   fails and the change is blocked from being treated as mergeable.
3. **Given** a change passes lint and SAST, **When** the pipeline continues, **Then** it builds a
   container image of the sample app and scans it for known vulnerabilities.
4. **Given** the vulnerability scan finds a CRITICAL-severity issue, **When** the pipeline
   evaluates the result, **Then** the pipeline fails and the image is **not** published.
5. **Given** the vulnerability scan finds only HIGH or lower-severity issues, **When** the
   pipeline evaluates the result, **Then** the findings are recorded and visible, and the
   pipeline proceeds to publish the image.
6. **Given** a change on the default branch passes every gate, **When** the pipeline completes,
   **Then** a container image tagged for that change is published to the project's container
   registry and is retrievable by tag.

---

### User Story 2 - Automated Deployment to the Local Cluster (Priority: P2)

Once a new image has passed the quality/security gate and been published, an operator wants the
running sample app on the local Kubernetes (k3s) cluster to be updated automatically, without
manually copying files or running commands on the cluster host.

**Why this priority**: Deployment automation is the next most valuable step after the build gate
exists — it turns "we have a trustworthy image" into "the environment actually reflects it" — but
it only makes sense once User Story 1 reliably produces that image.

**Independent Test**: With a previously deployed version already running on the cluster, publish
a new passing image and confirm the running workload on the cluster is updated to the new version
without manual intervention, using only the machine designated to perform deployments.

**Acceptance Scenarios**:

1. **Given** a new image has been published to the container registry after passing all gates,
   **When** the deployment automation runs, **Then** the workload running on the local k3s
   cluster is updated to the new image without a person manually running deployment commands.
2. **Given** the deployment automation is running, **When** it needs to reach the local cluster,
   **Then** it executes from a machine with direct network access to that cluster (rather than a
   cloud-hosted runner that cannot reach a private, local-only cluster).
3. **Given** a deployment completes, **When** the operator checks the cluster, **Then** exactly
   one version of the sample app is running (no leftover previous-version workloads left serving
   traffic).
4. **Given** the machine that performs deployments is unavailable or unreachable, **When** a
   new image is published, **Then** the pipeline clearly reports that the deployment step could
   not run, rather than silently succeeding or hanging indefinitely.

---

### User Story 3 - Reach the Deployed App Locally over HTTPS by a Friendly Name (Priority: P3)

A developer or tester on the local network wants to open the sample app in a browser using a
memorable HTTPS address (a subdomain of a local domain name) instead of an IP address and port,
the same way they would reach any real deployed environment.

**Why this priority**: This makes the two prior stories actually usable end-to-end by a human,
but it is additive polish on top of a working build-and-deploy pipeline — the app could
technically be reached by raw IP/port before this exists.

**Independent Test**: With the app already deployed per User Story 2, add the documented host
entry to a machine's hosts file, browse to `https://<app-name>.<domain-name>`, and confirm the
sample app loads successfully over HTTPS.

**Acceptance Scenarios**:

1. **Given** the sample app is deployed to the local cluster, **When** a user browses to
   `https://<app-name>.<domain-name>`, **Then** the sample app's UI loads successfully.
2. **Given** a user has not yet configured local name resolution, **When** they are given setup
   instructions, **Then** those instructions tell them to add an entry mapping the ingress
   machine's IP address to `<domain-name>` in their local hosts file.
3. **Given** a user's browser has not been configured to trust the cluster's local certificate,
   **When** they first browse to the app over HTTPS, **Then** setup instructions explain how to
   trust that certificate so the browser does not show a security warning.
4. **Given** the domain name in the hosts file entry, **When** a user browses to
   `https://<domain-name>` directly (without the app subdomain), **Then** they do not
   land on the sample app (only the `<app-name>.<domain-name>` subdomain routes to it), avoiding
   ambiguity with other apps that may share the same base domain.

### Edge Cases

- What happens when the Trivy scan cannot complete (e.g., vulnerability database unreachable)?
  The pipeline MUST treat this as a failure rather than silently skipping the scan and publishing
  an unscanned image.
- What happens when two pipeline runs for the same branch overlap (e.g., two quick pushes in a
  row)? The deployment step MUST NOT apply an older run's image after a newer run's image has
  already been deployed.
- What happens when the self-hosted runner's k3s context/credentials are missing or expired?
  The deployment step MUST fail loudly with a clear error rather than silently no-op.
- What happens when a contributor's fork opens a pull request? Steps that require registry
  publish credentials or cluster access MUST NOT run (or MUST run without those credentials) for
  untrusted external contributions.
- What happens when the local hosts-file entry already maps `<domain-name>` to a different IP
  (e.g., from a prior, different local project)? Setup instructions MUST tell the user to update
  the existing entry rather than silently adding a duplicate/conflicting one.
- What happens when the ingress certificate expires or is regenerated? Users MUST be able to
  re-trust the new certificate using the same documented steps as the initial setup.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The CI pipeline MUST run automatically on every push and every pull request
  targeting the repository's default branch.
- **FR-002**: The CI pipeline MUST run a lint check over the sample app's source code and report
  pass/fail status.
- **FR-003**: The CI pipeline MUST run a static application security testing (SAST) check over
  the sample app's source code and report pass/fail status.
- **FR-004**: The CI pipeline MUST build a container image of the sample app only after lint and
  SAST both pass.
- **FR-005**: The CI pipeline MUST scan the built container image for known vulnerabilities using
  Trivy before the image is published anywhere.
- **FR-006**: The pipeline MUST fail and MUST NOT publish the image when the vulnerability scan
  finds any CRITICAL-severity vulnerability.
- **FR-007**: The pipeline MUST still publish the image when the vulnerability scan finds only
  HIGH-severity or lower findings, and those findings MUST remain visible (e.g., as a pipeline
  report/artifact) for follow-up.
- **FR-008**: On a successful run against the default branch, the pipeline MUST push the built,
  scanned image to GitHub Container Registry (GHCR) under the project's namespace, tagged in a
  way that uniquely identifies the source commit.
- **FR-009**: Registry publish credentials and cluster deployment access MUST NOT be exposed to
  pipeline runs triggered by pull requests from external (non-collaborator) forks.
- **FR-010**: A deployment workflow MUST run on a self-hosted GitHub Actions runner that has
  direct network access to the local k3s cluster (a cloud-hosted runner cannot reach it).
- **FR-011**: The deployment workflow MUST update the sample app workload on the local k3s
  cluster to the newly published image automatically, without a person manually running
  deployment commands on the cluster.
- **FR-012**: The deployment workflow MUST result in exactly one active version of the sample app
  serving traffic on the cluster after it completes (no old and new versions both live).
- **FR-013**: If the deployment step cannot reach the cluster or the self-hosted runner is
  unavailable, the workflow run MUST be marked failed with a clear, human-readable reason rather
  than hanging or silently succeeding.
- **FR-014**: The deployed sample app MUST be reachable from the local network at
  `https://<app-name>.<domain-name>` (subdomain form), routed through an ingress/reverse proxy
  running on a known local VM (the "nginx VM").
- **FR-015**: The system MUST document, as part of local setup, adding an entry mapping the
  nginx VM's IP address to `<domain-name>` in the local machine's hosts file, so that
  `<app-name>.<domain-name>` resolves without relying on public DNS.
- **FR-016**: The ingress MUST terminate HTTPS using a certificate for `<domain-name>` (and its
  `<app-name>` subdomain); the certificate MAY be self-signed, and setup documentation MUST
  explain how a developer trusts it locally so browsers do not show a security warning.
- **FR-017**: Only the `<app-name>.<domain-name>` subdomain MUST route to the sample app; the
  bare `<domain-name>` MUST NOT serve the sample app, so the same base domain can host other
  apps under their own subdomains without collision.

### Key Entities

- **Pipeline Run**: One execution of the CI workflow for a specific commit/pull request;
  attributes include trigger event, lint result, SAST result, build result, Trivy scan result and
  severity findings, and (if applicable) the published image reference.
- **Container Image**: The built artifact of the sample app, identified by a registry reference
  and a tag tied to its source commit; carries the outcome of its vulnerability scan.
- **Deployment**: One execution of the deploy workflow that updates the sample app workload on
  the k3s cluster to reference a specific Container Image; has a status (succeeded/failed) and a
  timestamp.
- **Local Access Configuration**: The combination of the hosts-file entry (`<nginx-vm-ip>
  <domain-name>`) and the locally trusted certificate that together let a developer's browser
  reach `https://<app-name>.<domain-name>` and treat it as secure.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of pushes and pull requests against the default branch automatically trigger
  the lint, SAST, build, and scan pipeline with no manual step required to start it.
- **SC-002**: A change containing a lint violation or a CRITICAL vulnerability is blocked from
  producing a published image in 100% of pipeline runs (verified by intentional test cases).
- **SC-003**: A passing change results in a new image published to the registry and deployed to
  the local cluster with zero manual commands run by a person, measured from merge to the app
  serving the new version.
- **SC-004**: After completing the documented local setup (hosts-file entry + certificate trust)
  once, a developer can open `https://<app-name>.<domain-name>` and reach the running sample app
  with no browser security warning and no manual IP/port lookup, on every subsequent visit.
- **SC-005**: At no point during normal operation are two different versions of the sample app
  simultaneously reachable through the deployed URL.

## Assumptions

- "The sample app" refers to the `accelerator-mini` application in this repository
  (`apps/backend` + `apps/frontend`); this feature covers pipelines and deployment for that app,
  not the `accelerator-core` agent tooling.
- A local k3s cluster and a designated "nginx VM" already exist and are reachable from the
  self-hosted runner and from developer machines on the local network; provisioning the cluster
  and VM themselves is out of scope for this feature.
- `<app-name>` and `<domain-name>` are placeholders to be filled in with concrete values during
  planning/implementation (e.g., an app name derived from the repository and an internal local
  domain name); no public DNS registration is required since resolution happens via local hosts
  file entries only.
- The sample app is reachable via subdomain routing only (`https://<app-name>.<domain-name>`);
  path-based routing (`https://<domain-name>/<app-name>`) is out of scope for this iteration.
- The ingress certificate is self-signed and trusted manually per developer machine; automated
  certificate issuance/rotation (e.g., via cert-manager or a public CA) is out of scope for this
  iteration.
- Trivy's severity gate blocks publishing only on CRITICAL findings; HIGH and lower findings are
  reported but non-blocking, since this is a sample/training app rather than a production service.
- "Self-hosted runner" refers to a single GitHub Actions runner registered against this
  repository/organization with network access to the local k3s cluster; high-availability or
  multiple redundant runners are out of scope.
- Rollback tooling (reverting to a previous image on deployment failure) is out of scope for this
  feature; FR-013 only requires that failures are surfaced clearly, not automatically remediated.
