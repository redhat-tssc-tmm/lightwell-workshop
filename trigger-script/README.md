# AO Nexus webhook trigger (showcase)

Posts a Nexus-shaped `component CREATED` payload to the tenant EDA route so
Automation Orchestrator runs the Lightwell Remediation canvas — without
uploading a real artifact to Nexus.

## Prerequisites

- `oc`, `curl`, `python3` on `PATH`
- Kube context that can read `lightwell-tenant-<guid>` (and AAP if using `--watch`)
- Tenant already bootstrapped (`eda-bootstrap` / AO path enabled)

## Trigger

```bash
cd trigger-script

# Human-gated app (wire-transfer-svc → needs_approval)
./trigger-nexus-webhook.sh <guid> needs-approval

# Auto-merge app (benefits-mgmt-app → auto_approve)
./trigger-nexus-webhook.sh <guid> auto-approve

# Both, sequentially (~90s pause between)
./trigger-nexus-webhook.sh <guid> both --watch
```

| Case | Default GAV | Expected app / policy |
|------|-------------|------------------------|
| `needs-approval` | `com.h2database:h2:2.2.224` | `acme-<guid>/wire-transfer-svc` / `needs_approval` |
| `auto-approve` | `org.flywaydb:flyway-core:4.1.2` | `acme-<guid>/benefits-mgmt-app` / `auto_approve` |

Useful flags: `--dry-run`, `--watch`, `--version <full.rhlw-…>`.

Overrides: `EDA_WEBHOOK_ROUTE_URL`, `NEEDS_APPROVAL_GAV`, `AUTO_APPROVE_GAV`
(`group:artifact:baseVersion`).

## Notes

- Each run stamps a unique `.rhlw-HHMMSS` so Impact does not treat the fix as
  `already_current` after a prior merge.
- Do not fire within ~1 minute of a tenant Argo sync (EDA activation restart).
- Auto-approve only loops benefits if TPA’s SBOM lists that GAV; otherwise
  override `AUTO_APPROVE_GAV` or seed the SBOM.
- This bypasses Nexus upload; production path is artifact → Nexus webhook → EDA.
