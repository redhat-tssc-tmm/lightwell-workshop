# agent-sandbox (cluster)

Installs the Red Hat build of Agent Sandbox from OperatorHub. The CSV is
AllNamespaces, so the Subscription is created in `openshift-operators`, next
to the global OperatorGroup. The operator runs the controller and the sandbox
router there and owns the `agents.x-k8s.io` / `extensions.agents.x-k8s.io`
CRDs.

This is Technology Preview (`preview-0.9`, CSV `v0.9.0`). The v0.9.0 Sandbox
CRD has `operatingMode` and `shutdownPolicy`. It does not have
`failedPodPolicy`.

| Value | Purpose |
|-------|---------|
| `channel` / `startingCSV` | Catalog channel and the CSV this chart was tested with |
| `namespace` | Subscription namespace. Must be `openshift-operators` on a cluster whose only global OperatorGroup is there |
| `metrics.serviceMonitor.enabled` | Scrape controller `:8080/metrics` |

Wired from `bootstrap-infra` as child Application `agent-sandbox` (sync-wave `2`).
