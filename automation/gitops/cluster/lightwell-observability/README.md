# lightwell-observability (cluster)

Demo observability for the agent-sandbox remediation drive:

| Piece | Role |
|-------|------|
| Tempo Operator + `TempoMonolithic` | Trace store |
| OpenTelemetry Collector | OTLP ingest → Tempo |
| COO `UIPlugin` DistributedTracing | Observe → Traces |
| COO `UIPlugin` Monitoring + Perses | Observe → Dashboards (Perses) |
| `PersesDashboard/lightwell-remediation` | Skeleton rollup (panels filled in task 7.2) |

Operators install into `openshift-operators`. Workloads live in `lightwell-observability`.

`Sandbox/opencode` in each tenant exports OTLP here. AO, EDA, and AAP stay
as they are; this chart does not install them and it is not installed per tenant.

```
http://lightwell-collector.lightwell-observability.svc:4318
```

OpenCode appends `/v1/traces`. The collector Service name is `<otel.name>-collector`.
The collector forwards to the Tempo gateway (`tempo-<name>-gateway:4317`, TLS) with
`X-Scope-OrgID` and its ServiceAccount token. The gateway allows that write
only when the account can `create` the tenant resource named `traces`.
