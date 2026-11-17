# agent-sandbox (cluster)

Installs [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
core + extensions from a **pinned** release manifest.

| Value | Purpose |
|-------|---------|
| `version` | Upstream tag (must match vendored file) |
| `namespace` | Controller namespace. `values.namespace` must stay `agent-sandbox-system` because the vendored manifest hardcodes it. |
| `metrics.serviceMonitor.enabled` | Scrape controller `:8080/metrics` |

## Pin / upgrade

```bash
VERSION=v1.0.8
curl -fsSL \
  "https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/sandbox-with-extensions.yaml" \
  -o files/sandbox-with-extensions.yaml
# Update Chart.yaml appVersion + values.yaml version to match.
helm template test . >/dev/null
```

Wired from `bootstrap-infra` as child Application `agent-sandbox` (sync-wave `2`).
