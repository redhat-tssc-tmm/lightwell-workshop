# AO Path 2 — operator docs

These notes describe **Automation Orchestrator (AO) Path 2** on a provisioned
tenant: EDA → AO canvas → AAP / OpenCode / SNOW / TPA, plus the shared
post-merge CI/CD spine. They are **not** Showroom student content and are not
about Path 1 (Renovate) except where Path 1 shares CI/CD.

| Doc | Use when you need… |
|-----|--------------------|
| [DEMO-FLOW.md](DEMO-FLOW.md) | The intended AO story: who talks to whom, Path 1 vs Path 2, current canvas sequence, demo gotchas |
| [architecture.md](architecture.md) | Per-tenant wiring diagrams (namespaces, shared platform, sequence) for the AO-enabled lab |
| [DEMO-FLOW-INVESTIGATION.md](DEMO-FLOW-INVESTIGATION.md) | A dated **live cluster** snapshot vs charts — readiness, gaps, HTTP probes, job outcomes |

Scripts that fire and reset Path 2 live one directory up:
[../README.md](../README.md).
