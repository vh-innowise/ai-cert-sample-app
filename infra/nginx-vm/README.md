# nginx VM — Local HTTPS Access Setup

This is the reference config and one-time setup for the external "nginx VM" that fronts the
local k3s cluster (research.md §9), so the sample app is reachable at
`https://sample-app.accelerator.test` (User Story 3). The cluster and this VM are assumed to
already exist — see `deploy/README.md` for the rest of the one-time setup this feature needs.

## 1. Generate a self-signed certificate

Run on (or generate for) the nginx VM, covering both hostnames as Subject Alternative Names:

```bash
mkdir -p /etc/ssl/accelerator-test
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/ssl/accelerator-test/privkey.pem \
  -out /etc/ssl/accelerator-test/fullchain.pem \
  -days 825 \
  -subj "/CN=accelerator.test" \
  -addext "subjectAltName=DNS:accelerator.test,DNS:sample-app.accelerator.test"
```

## 2. Install the nginx config

Copy `sample-app.conf` from this directory to the VM (e.g.
`/etc/nginx/sites-available/sample-app.conf`, symlinked into `sites-enabled/`), filling in
`<K3S_NODE_IP>` (the k3s node's IP) and `<NODE_PORT>` (must match
`deploy/k8s/frontend-service.yaml`'s `nodePort`, `30080` by default). Reload nginx:

```bash
nginx -t && systemctl reload nginx
```

## 3. Point local machines at the nginx VM (FR-015)

On each developer machine that needs to reach the app, add **both** hostnames to `/etc/hosts` on
one line — a hosts-file entry is an exact match, not a wildcard, so listing only the bare domain
does not make the subdomain resolve (research.md §10 — this corrects the literal single-hostname
phrasing in the original request):

```
<nginx-vm-ip> accelerator.test sample-app.accelerator.test
```

## 4. Trust the certificate locally (FR-016)

One-time per developer machine, so the browser doesn't show a security warning:

- **macOS**: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain fullchain.pem` (copy `fullchain.pem` from the VM first)
- **Linux (Debian/Ubuntu)**: copy `fullchain.pem` to `/usr/local/share/ca-certificates/accelerator-test.crt`, then `sudo update-ca-certificates`
- **Windows**: import `fullchain.pem` into "Trusted Root Certification Authorities" via `certmgr.msc`

After this, `https://sample-app.accelerator.test` loads with no browser warning, and
`https://accelerator.test` (bare domain) returns 404 rather than the app (FR-017).

## Certificate renewal

When the certificate is regenerated (e.g. on expiry, `-days 825` from step 1), repeat step 4 on
each developer machine — the trust step is the same regardless of why the certificate changed.
