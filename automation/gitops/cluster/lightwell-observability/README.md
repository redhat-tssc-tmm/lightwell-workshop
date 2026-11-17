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

Orchestrator/lane pods should export OTLP to:

`http://lightwell-collector-collector.lightwell-observability.svc:4318`

(exact Service name follows the OpenTelemetry Operator convention — confirm after first sync).
