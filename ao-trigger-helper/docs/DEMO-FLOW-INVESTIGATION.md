# Demo flow — live cluster investigation (AO Path 2)

Dated snapshot of what is actually running vs what the charts expect for an
**AO-enabled** tenant (EDA activation, AO canvas, Nexus entry, Path 1/2
readiness). Companion narrative: [DEMO-FLOW.md](DEMO-FLOW.md). Wiring:
[architecture.md](architecture.md). Index: [README.md](README.md).

Secrets and passwords are intentionally omitted from this document.

**Latest re-run:** 2026-10-16 — admin on `cluster-5trcs` / guid `cng2l`.
Re-run and rewrite §0 when probing a new cluster; keep older sections as history.

---

## 0. Current lab — `5trcs` / guid `cng2l` (2026-10-16)

| Field | Value |
|-------|-------|
| **Cluster** | `api.cluster-5trcs.dyn.redhatworkshops.io` |
| **Domain** | `apps.cluster-5trcs.dyn.redhatworkshops.io` |
| **Identity** | `admin` (cluster-admin) |
| **Console** | `https://console-openshift-console.apps.cluster-5trcs.dyn.redhatworkshops.io` |
| **Infra guid (parent Helm)** | `5trcs-1` |
| **Local workspace** | `sshaaf/lightwell-workshop` @ `b06b131` (`main`, **1 commit ahead of origin**) |
| **Upstream / fork `main`** | `3bcf35d` (`rhpds` and `sshaaf` tip identical) |

### Namespaces (tenant)

`build-cng2l`, `lightwell-nexus-cng2l`, `lightwell-tenant-cng2l`, `sdlc-cng2l`, `sdlc-sandboxes-cng2l`, `snow-cng2l`, `tpa-cng2l`, `user-cng2l-app`, `user-cng2l-enterprise`, `user-cng2l-renovate`, `user-cng2l-showroom`.

### GitOps

| Application | Sync / Health | Source |
|-------------|---------------|--------|
| `lb1815-lightwell` (parent) | Synced / Healthy | `rhpds/lightwell-workshop` @ `3bcf35d` → `bootstrap-infra` |
| Shared children (`aap`, `ao`, `gitlab`, `keycloak`, `cnpg`, `quay`, `rhads`, `opencode-image`) | Synced / Healthy | same parent rev |
| `renovate-operator` | Synced / Healthy | OCI `ghcr.io/mogenius/helm-charts` `6.4.0` |
| `lightwell-tenant-cng2l` | **OutOfSync** / Healthy | fork `sshaaf/lightwell-workshop` @ `main` → `bootstrap-tenant` |
| `tpa-cng2l` | Synced / Healthy | `https://charts.openshift.io/` `3.1.1` |

**OutOfSync detail:** only `ConfigMap/ao-bootstrap-source` differs from fork `main` (`3bcf35d`). Live CM **matches local unpushed** `b06b131` (snow URL bake for classify/iter/finalize). Argo wants to revert toward older git until the fork is pushed / synced.

Repos registered: `rhpds/lightwell-workshop`, `sshaaf/lightwell-workshop`.

### Bootstrap Jobs

| Job | NS | Outcome |
|-----|-----|---------|
| `create-gitlab-tenant` | `lightwell-tenant-cng2l` | Complete — group `acme-cng2l`; 3 apps seeded + policies; MR webhook on wire-transfer → EDA route; PaC push hooks on apps |
| `create-aap-tenant` | same | Complete — org/user `user-cng2l` |
| `ao-bootstrap` | same | Complete — project `lightwell-cng2l`; start `lightwell-remediation-start-cng2l` |
| `ao-bootstrap-snowfix` | same | Complete — **re-published AO workflow version 3** (baked `snow_url`) |
| `eda-bootstrap` | same | Complete — rulebook `sdlc-remediation.yml`, AO_ENABLED; activation **running** |
| `sync-gitlab-pat` | same | Complete — `gitlab-root-pat` in `sdlc-cng2l` |
| `nexus-reconcile` | `lightwell-nexus-cng2l` | Complete — hosted Lightwell + OCI OK; **SKIP** LW Network proxies + **SKIP webhooks** |

### HTTP probes

| Endpoint | Code |
|----------|------|
| Nexus UI (`nexus-lightwell-nexus-cng2l`) | 200 |
| Nexus short (`nexus-cng2l`) | (present) |
| Nexus OCI (`nexus-oci-cng2l` `/v2/`) | 401 (auth — expected) |
| Wrong OCI hostname `nexus-oci-lightwell-nexus-cng2l` | **503** (not the real Route) |
| SNOW mock | 200 |
| GitLab | 302 |
| AAP | 200 |
| AO | 200 |
| Renovate operator UI | 200 |
| Argo CD | 200 |
| TPA | 200 |
| SSO | 302 |
| OpenCode UI | 401 (basic auth — gate Ready) |
| EDA activation Route | **405** on GET (listener up; POST-only) |
| PaC controller | 200 |

### Nexus repositories

Present: `lightwell-remediated`, `lightwell-validated` (hosted maven), `oci` (docker), plus default maven/nuget set.

**Missing:** `redhat-packages-validated-cng2l`, `redhat-packages-remediated-cng2l` (LW Network creds empty — username/password length 0).

Hosted Lightwell component counts: **0** (no `.rhlw` uploads; Path 2 uses [`trigger-nexus-webhook.sh`](../trigger-nexus-webhook.sh)).

`NEXUS_WEBHOOK_REPOSITORIES` still points at the missing proxy repo names → reconcile correctly **SKIP webhooks**.

### GitLab Acme apps (after `reset-demo-repos.sh`)

| App | Policy | Dep on `main` | Open MRs / `update-artifact-*` | Hooks |
|-----|--------|---------------|--------------------------------|-------|
| `wire-transfer-svc` | `ao` / `needs_approval` | h2 **1.4.200** | 0 / none | EDA MR + PaC push |
| `benefits-mgmt-app` | `ao` / `auto_approve` | flyway-core **4.1.2** | 0 / none | PaC push only |
| `report-generator-app` | `renovate` | h2 present (BOM, no pinned version in pom) | 0 / none | PaC push only |

### EDA / AAP / OpenCode

| Item | Live |
|------|------|
| Activation | `sdlc-remediation-cng2l` **running** / enabled |
| Rulebook | `sdlc-remediation.yml` — Nexus `.rhlw` → Start Orchestrator **only** (no MR-open → Resume; intentional) |
| EDA project SCM | `rhpds/lw-sdlc-opencode` @ `71aabde` |
| Controller project SCM | same URL @ **`79aa547`** (**drift** vs EDA import hash) |
| Job templates | 11 SDLC JTs (Start/Resume, TPA, Classify, Impact, Verifier, Merge, SNOW ×4) |
| OpenCode image | `lightwell-images/sdlc-opencode:sha-6fe8264` Ready 1/1 |
| UI gate | Ready 1 |
| `renovate-token` | Present in `user-cng2l-renovate` (key `RENOVATE_TOKEN`) |
| `RenovateJob` CRs | **None** |

### PaC / Pipelines (`build-cng2l`)

Repository CRs for all three Acme apps. Recent PipelineRuns: several **Succeeded** (~5–6m ago); two earlier **Failed** at `maven-build` (`pzqmx`, `knnts`).

### ServiceNow (demo tickets)

| Incident | State | Comments | Notes |
|----------|-------|----------|-------|
| INC0023249 | Resolved | 3 | h2 run (earlier) — classify → merged wire-transfer → finalize |
| INC0023250 | New | 0 | orphan create (failed comment era / abandoned) |
| INC0023251 | New | 0 | orphan create (flyway; abandoned) |
| INC0023252 | Resolved | 3 | h2 Path 2 E2E after AO v3 — wire-transfer merged |
| INC0023253 | Resolved | 3 | flyway trigger — **mis-classified wire-transfer** (`already_current`), not benefits |

Short descriptions still read `Lightwell remediation arrived — unknown <gav>` (`cve_id=unknown` from showcase payload).

### Path readiness on this tenant

| Path | Ready? | Blocker / next |
|------|--------|----------------|
| Path 1 (Renovate) | Partial | Hosted repos + `renovate-token` exist; **no RenovateJob**; no `.rhlw` in Nexus; LW Network proxies absent (lab can still use hosted `lightwell-remediated` if student Job points there) |
| Path 2 (AO/AI) | **Demo-ready via showcase script** | Natural Nexus→EDA webhooks **absent** (empty LW Network + webhook list tied to proxy repos). Use `trigger-nexus-webhook.sh`. AO v3 + EDA + OpenCode + SNOW proven for needs-approval |
| Shared CI/CD | Partial | PaC wired; some maven-build failures observed; AO does not orchestrate build/sign/deploy |

### Recent AAP job health (Path 2)

After AO v3 republish: Start → Create SNOW → Query TPA → Classify → Impact → Verifier → Merge → SNOW iter/finalize all **successful** (0 new failures). Pre-fix failures: Create SNOW #7, SNOW Comment #38/#48 (empty `snow_url`).

---

## 0b. AO as top-level orchestrator — gap analysis (2026-10-16, `cng2l`)

Source of truth: live AO workflow **v3** (from `ao-bootstrap-snowfix`) + local `bootstrap-ao-tenant.py` @ `b06b131` + EDA rulebook `sdlc-remediation.yml` @ `71aabde`.

### What AO owns today

```
start_trigger (EDA / Nexus-shaped webhook)
  → Create SNOW
  → Query TPA
  → Classify (policy.json → ao_apps)
  → SNOW classify comment
  → for_each ao_apps:
        Impact Analyzer
          → if already_current → SNOW iter
          → else Verifier
               → if verifier_pass:
                    if auto_approve → Merge
                    else Approval → Merge | reject iter
               → else SNOW iter (verifier_fail)
  → SNOW finalize
```

Single canvas run (no separate Resume leg). EDA is sensor-only for Nexus start.

### Coordination reported into AO vs not

| Event / step | Reported into AO? | How today |
|--------------|-------------------|-----------|
| Nexus / showcase `.rhlw` CREATED | Yes (entry) | EDA → Start Orchestrator → AO start webhook |
| SNOW create / classify comment / iter / finalize | Yes | AO nodes → AAP JTs |
| Query TPA | Yes | AO node + artifacts |
| Multi-app classify (`ao_apps`) | Yes | Classify JT + for_each |
| Impact / Verifier / Merge | Yes | In-loop AO nodes |
| Human approval (`needs_approval`) | Yes | AO `approval` node |
| Auto-approve branch | Yes | condition on `verifier.artifacts.approval` |
| `already_current` short-circuit | Yes | condition on Impact artifacts |
| GitLab MR opened (EDA Resume) | **No (by design)** | Removed to stop dual-Verifier race |
| Tekton / PaC / Chains / Argo deploy / post-build SBOM | **No** | Outside AO (shared CI/CD spine) |
| Natural Nexus repository webhooks | **No on this tenant** | Reconcile SKIP — no proxy repos |

### Gaps / anomalies found this re-run

1. **Nexus→EDA entry still synthetic** — empty LW Network creds ⇒ no proxy repos ⇒ no webhooks. Showcase script is the reliable Path 2 trigger (ADR-031).
2. **TPA blast-radius mis-hit on flyway** — Classify job 72 returned only `wire-transfer-svc` for `org.flywaydb:flyway-core` (`match_reason=sbom_label_and_dependency_coordinate`). Benefits (`auto_approve`) never entered the loop; run short-circuited as `already_current` on wire-transfer (INC0023253). **Path 2 dual-app demo is not trustworthy until TPA SBOMs / query matching are fixed.**
3. **Git / Argo drift** — live `ao-bootstrap-source` = local `b06b131` (unpushed); fork + upstream `main` still `3bcf35d`; tenant App OutOfSync. Risk: Argo sync would overwrite the snow-bake CM and regress Comment nodes.
4. **AAP SCM drift** — EDA project import `71aabde` vs Controller playbooks `79aa547` on the same `lw-sdlc-opencode` URL. Rulebook vs playbook tip can diverge silently.
5. **SNOW title quality** — `cve_id=unknown` from showcase/EDA payload → “arrived — unknown \<gav\>”.
6. **Orphan SNOW tickets** — INC0023250/3251 left New with 0 comments from the pre-v3 failure window.
7. **Path 1 incomplete** — no student `RenovateJob`; hosted repos empty; report-generator h2 unpinned in pom (Renovate still possible once Job exists).
8. **PaC flake** — intermittent `maven-build` StepFailed on push-to-main runs.
9. **CD still scenery for AO** — build/sign/deploy/SBOM remain outside the canvas (acceptable per shared-spine design, but Showroom “AO coordinates everything” overclaims if taken literally).
10. **Webhook target list chart smell** — `NEXUS_WEBHOOK_REPOSITORIES` only lists LW Network proxy names; even with creds, hosted `lightwell-*` never get webhooks unless that list (or reconcile logic) changes.

### Verdict

On `cng2l`, AO **does** own the multi-app remediation loop including SNOW and approval — a clear advance over the 2026-10-15 single-app canvas (§0d). Path 2 **needs-approval** is E2E-proven via the showcase webhook. Remaining demo blockers: **natural Nexus webhooks**, **TPA→benefits routing for flyway/auto-approve**, and **pushing/syncing the AO bake commit** so GitOps matches the live workflow.

---

## 0c. Prior tenant — `62b79` / guid `t8s2n` (2026-10-15)

| Field | Value |
|-------|-------|
| **Cluster** | `api.cluster-62b79.dyn.redhatworkshops.io` |
| **Domain** | `apps.cluster-62b79.dyn.redhatworkshops.io` |
| **Identity** | `user-t8s2n` (tenant — **not** cluster-admin) |
| **Console** | `https://console-openshift-console.apps.cluster-62b79.dyn.redhatworkshops.io` |

### Accessible namespaces

`lightwell-nexus-t8s2n`, `lightwell-tenant-t8s2n`, `snow-t8s2n`, `user-t8s2n-app`, `user-t8s2n-enterprise`.

**Forbidden** from this login: `openshift-gitops`, `sdlc-t8s2n`, `tpa-t8s2n`, `build-t8s2n`, `sdlc-sandboxes-t8s2n`, cluster-scoped NS list. (Matches HANDOFF: tenant user is Forbidden on `sdlc-<guid>`.)

### Bootstrap Jobs (`lightwell-tenant-t8s2n`) — all Complete

| Job | Outcome (high level) |
|-----|----------------------|
| `create-gitlab-tenant` | Group `acme-t8s2n`; seeded `wire-transfer-svc`, `benefits-mgmt-app`, `report-generator-app`; `renovate-bot` + `renovate-token` → `sdlc-t8s2n`; MR webhook on wire-transfer → `https://sdlc-remediation-t8s2n-aap.<domain>/` |
| `create-aap-tenant` | Org + user `user-t8s2n` |
| `ao-bootstrap` | AO project `lightwell-t8s2n`; AAP integration + published Lightwell Remediation workflow; paths `lightwell-remediation-start-t8s2n` / `…-resume-t8s2n` |
| `eda-bootstrap` | Rulebook `sdlc-remediation.yml`, AO_ENABLED; activation **running**; listener `http://sdlc-remediation-t8s2n.aap.svc.cluster.local:5000/` |
| `sync-gitlab-pat` | `gitlab-root-pat` in `sdlc-t8s2n` |
| `nexus-reconcile` | EULA OK; OCI + hosted `lightwell-remediated` / `lightwell-validated`; `maven-public` updated; **SKIP** proxy repos + **SKIP webhooks** (empty LW Network creds) |

### HTTP probes

| Endpoint | Code |
|----------|------|
| Nexus short / long UI | 200 |
| Nexus OCI `/v2/` | 401 (expected — auth) |
| SNOW mock | 200 |
| GitLab / AAP / AO / Renovate / Argo / TPA | 302 or 200 |
| SSO | 302 |
| OpenCode UI | 401 (basic auth — pod exists) |

### Nexus repositories present

`lightwell-remediated`, `lightwell-validated` (hosted), `oci` (docker hosted), plus default maven/nuget. **No** `redhat-packages-*-t8s2n` proxies.

Secret `redhat-packages-credentials` exists with keys `username`/`password` both **length 0**.

### Path readiness on this tenant

| Path | Ready? | Blocker / next |
|------|--------|----------------|
| Path 1 (Renovate) | Mostly | Hosted Lightwell repos + renovate-token exist. Still need student `RenovateJob` + upload `.rhlw` into `lightwell-remediated`. Cannot list `sdlc-t8s2n` as tenant user. |
| Path 2 (AO/AI) | Entry blocked | No Nexus→EDA webhooks until LW Network creds filled **or** webhooks attached to hosted repos. EDA activation + AO workflow are otherwise up. |

### No admin context

Kubeconfig has **no** admin entry for `62b79` — cannot re-run Argo inventory or inspect `sdlc-t8s2n` pods without elevating.

---

## 0d. AO gap analysis — superseded snapshot (2026-10-15)

> Superseded by §0b on `cng2l`. Kept for comparison.

Source of truth (at the time): `bootstrap-tenant/files/bootstrap-ao-tenant.py` (`remediation_workflow_definition`) + `rhpds/lw-sdlc-opencode` rulebooks/playbooks.

### What AO actually owns today

```
start_trigger (EDA/Nexus)
  → Query TPA (AAP JT)
  → condition (job_status == successful)
  → Impact Analyzer (AAP JT → OpenCode prompt_async)
resume_trigger (EDA/GitLab MR opened)
  → MR Verifier (AAP JT → OpenCode Job)
```

That is the **entire** published `Lightwell Remediation` canvas. No ServiceNow nodes, no Wait/Approval node, no Tekton/Argo nodes, no ticket close.

### Coordination reported into AO vs not

| Event / step | Reported into AO? | How today |
|--------------|-------------------|-----------|
| Nexus `.rhlw` CREATED | Yes (entry) | EDA → JT Start Orchestrator → AO start webhook |
| Query TPA running/done | Yes | AO node; AAP job status + `set_stats` artifacts |
| Blast-radius multi-app list | **Partial / unused** | Query TPA `set_stats` exports `affected_repos`, but Impact node **rebuilds** inputs from start trigger for **one** `remediation_app_gitlab_path` (Demo A) |
| `tpa_results` EDA callback | **No (orphaned in AO mode)** | `query-tpa.yml` POSTs to EDA; AO rulebook has **no** rule for `tpa_results` (legacy chain used it) |
| Impact Analyzer *started* | Yes | AO node succeeds when AAP JT succeeds |
| Impact Analyzer *finished* / MR content | **No** | `opencode-prompt-async.yml` — fire-and-forget; green JT ≠ agent done |
| Risk auto-approve vs human gate | **No** | Not an AO condition; agent/GitLab behaviour only (Showroom narrative ahead of canvas) |
| ServiceNow open/update/close | **No** | SNOW mock deployed; **zero** refs in AO workflow or lw-sdlc-opencode playbooks |
| GitLab MR opened | Yes (resume entry) | EDA rule: MR `open` + branch `update-artifact-*` → Resume → MR Verifier |
| GitLab MR merged / approved | **No** | Resume is on **open**, not merge |
| MR Verifier Job done | Partial | AO sees AAP JT status only |
| Tekton / PaC build | **No** | GitLab→PaC outside AO |
| Chains / sign / Nexus OCI push | **No** | Outside AO |
| ArgoCD deploy | **No** | Outside AO |
| TPA SBOM upload after build | **No** | Outside AO |

### Structural gaps (Ansible/AO backing)

1. **EDA is still a co-orchestrator**, not a dumb sensor only — it maps events → Start/Resume JTs; AO never sees raw Nexus/GitLab payloads except what those playbooks forward.
2. **Two disconnected AO legs** (start→Impact and resume→Verifier) instead of one run with Wait/Approval after Impact (resume playbook comments say Wait is the preferred long-term design).
3. **Async OpenCode** breaks AO’s claim to “coordinate until remediation is done.”
4. **Demo A single-app hardcoding** conflicts with Showroom multi-app Path 2 (wire-transfer + benefits).
5. **ITSM and CD are scenery** relative to AO — deployed for the lab story, not on the canvas.
6. **Query TPA→EDA callback** is dead code on the AO path — leftover from legacy rulebook ownership.

### Verdict

If the requirement is “AO is the top-level orchestrator and every coordination after Nexus webhook is reported into AO,” **today’s implementation does not meet that**. AO orchestrates only **Query TPA → Impact launch** and, on a separate trigger, **MR Verifier launch**. Everything else (agent completion, SNOW, human approval semantics, build/sign/deploy) happens **outside** AO with no callback into the canvas.

---

## 1. Infra-only cluster — `j88nz` (prior)

| Field | Value |
|-------|-------|
| **Date** | 2026-10-15 |
| **Cluster** | `api.cluster-j88nz.dyn.redhatworkshops.io` |
| **Ingress domain** | `apps.cluster-j88nz.dyn.redhatworkshops.io` |
| **Infra guid (bootstrap)** | `j88nz-1` |
| **Argo parent app** | `lb1815-lightwell` |
| **Git revision synced** | `f4aa81e` (`Merge pull request #11 … feat/add-pac`) |
| **Repo tracked by apps** | `https://github.com/rhpds/lightwell-workshop.git` @ `main` |
| **Local / fork HEAD** | Same SHA (`sshaaf/lightwell-workshop` `main` / `demo-update`) |
| **Tenants provisioned** | **None** |

### GitOps connection (what we did on j88nz)

#### Argo CD CLI

OpenShift GitOps does not expose a working admin gRPC login from outside without
`--grpc-web` prompts. Use **core mode** against the kubeconfig:

```bash
export ARGOCD_OPTS="--core"
kubectl config set-context --current --namespace=openshift-gitops
argocd app list
argocd repo list
```

### Repositories registered

| Name | URL | Status |
|------|-----|--------|
| `rhpds-lightwell-workshop` | `https://github.com/rhpds/lightwell-workshop.git` | Successful |
| `sshaaf-lightwell-workshop` | `https://github.com/sshaaf/lightwell-workshop.git` | Successful |

Apps were **not** retargeted to the fork. Parent + children already sync
`rhpds/lightwell-workshop@main` at the same commit as this workspace. The fork
is registered so you can point an Application at `sshaaf` / `demo-update` for
experiments without changing the shared lab apps.

### Applications (Synced / Healthy)

| Application | Namespace | Chart path / source | Resources |
|-------------|-----------|---------------------|-----------|
| `lb1815-lightwell` | `openshift-gitops` | `automation/gitops/bootstrap-infra` (app-of-apps) | 12 |
| `aap` | `aap` | `cluster/aap` | 9 |
| `ao` | `automation-orchestrator` | `cluster/ao` | 16 |
| `cnpg` | `cloudnative-pg` | `cluster/cnpg` | 3 |
| `gitlab` | `gitlab` | `cluster/gitlab` | 21 |
| `keycloak` | `keycloak` | `cluster/keycloak` | 4 |
| `opencode-image` | `lightwell-images` | `cluster/opencode-image` | 8 |
| `quay` | `lightwell-quay` | `cluster/quay` | 8 |
| `rhads` | `trusted-artifact-signer` | `cluster/rhads` (Pipelines + TAS + TPA OIDC clients) | 16 |
| `renovate-operator` | `renovate-operator` | OCI `ghcr.io/mogenius/helm-charts` chart `renovate-operator` `6.4.0` | 9 |

No `lightwell-tenant-*` Applications exist on this cluster yet.

---

## 2. Live vs expected (demo readiness)

| Demo piece | Chart location | Live on `j88nz`? | Notes |
|------------|----------------|------------------|-------|
| Shared GitLab | `cluster/gitlab` | Yes | Route 302; API requires auth |
| Shared AAP + EDA | `cluster/aap` | Yes | Controller 4.8.11; EDA 1.3.12 |
| Automation Orchestrator | `cluster/ao` | Yes | Ready; UI `https://ao.<domain>` |
| CNPG (AO Postgres) | `cluster/cnpg` + AO chart | Yes | `orchestrator-postgres` healthy |
| Keycloak SSO | `cluster/keycloak` | Yes | Realm `sso`; TPA OIDC secret present |
| Quay | `cluster/quay` | Yes | v3.18.1 Available |
| Renovate operator | bootstrap-infra child | Yes | No `RenovateJob` CRs (expected until tenant + student) |
| OpenCode image | `cluster/opencode-image` | Yes | IS `sdlc-opencode:sha-aad125a` built |
| Pipelines + PaC | `cluster/rhads` | Yes | PaC controller Route 200 |
| Tekton Chains → TAS | `cluster/rhads` | Yes | Fulcio/Rekor/TUF Ready; Chains → Fulcio/Rekor svc |
| **Per-tenant Nexus** | `bootstrap-tenant/nexus` | **No** | Needs tenant Application |
| **Per-tenant TPA** | `bootstrap-tenant/tpa` | **No** | |
| **OpenCode Deployment** | `bootstrap-tenant/sdlc` | **No** | |
| **EDA activation + Nexus webhooks** | `bootstrap-tenant/eda` + nexus reconcile | **No** | |
| **ServiceNow mock** | `bootstrap-tenant/snow` | **No** | |
| **PaC Repository CRs / build NS** | `bootstrap-tenant/build` | **No** | |
| **Acme GitLab group + apps** | `bootstrap-tenant/gitlab` | **No** | |
| **Renovate SA / token** | `bootstrap-tenant/renovate` + gitlab jobs | **No** | |

**Verdict (j88nz at time of write):** Shared platform up; no tenant yet. **Superseded** — tenant `cng2l` now exists on `cluster-5trcs` (see §0).

---

## 3. Live component I/O (shared infra — measured)

HTTP probes used `curl -sk` against public Routes (no credentials in this file).

| Component | Speaks to (live) | Inputs observed | Outputs observed |
|-----------|------------------|-----------------|------------------|
| **Argo CD** | GitHub `rhpds/lightwell-workshop`; cluster API | Git tree @ `f4aa81e`; Helm values (domain, storageClass, admin password from AgnosticV) | 9 child Applications + Renovate OCI app; continuous reconcile |
| **bootstrap-infra (parent)** | Child app charts under `cluster/*` | `deployer.domain`, `deployer.guid=j88nz-1`, `deployer.apiUrl`, gitlab/aap passwords | App-of-apps Applications only (no workloads in parent NS beyond those Apps) |
| **GitLab** | Students/agents (when tenant exists); init Job | Root password from Helm; empty `gitlab.repos: []` at infra | Route `gitlab-gitlab.<domain>` (302); Postgres+Redis; CE image `17.4.1` |
| **AAP Controller** | AO (allowlisted host); future EDA activations | Operator channel `stable-2.7`; manifest inject Job completed | Route `aap-aap.<domain>` (200); version 4.8.11 |
| **EDA** | Future Nexus/GitLab webhooks per tenant | Same AAP platform | `aap-eda` Successful; event-stream + activation workers Running; **zero tenant activations** |
| **Automation Orchestrator** | AAP Route host (integration allowlist); UI users | CNPG cluster; `APP_INTEGRATION_URL_ALLOWED_HOSTS=["aap-aap.<domain>"]` (Job succeeded) | Route `ao.<domain>` (200); backend/worker/UI Ready |
| **Keycloak** | TPA clients (cluster-level); TAS OIDC; console SSO | Realm import `sso`; Jobs `sso`, `tpa-keycloak-setup`, `rhtas-keycloak-setup` Completed | Route `sso.<domain>` (302); Secret `tpa-oidc-client-secret` |
| **Quay** | Optional image hosting (demo primarily uses Nexus OCI per tenant) | Operator channel `stable-3.18` | Registry Available @ `lightwell-quay-lightwell-quay.<domain>` (200) |
| **OpenCode ImageStream** | Future OpenCode Deployments | Build from `rhpds/lw-sdlc-opencode` gitRef `aad125a` | `image-registry…/lightwell-images/sdlc-opencode:sha-aad125a` (`sha256:75567418…`) |
| **Renovate operator** | Future `RenovateJob` in tenant `sdlc-{guid}` | Upstream Helm 6.4.0; SCC binding; UI Route | Route `renovate-operator-renovate-operator.<domain>` (200); CRDs installed; **0 RenovateJobs** |
| **OpenShift Pipelines / PaC** | Future GitLab push webhooks (`build-{guid}`) | Channel `pipelines-1.24` | PaC controller Route (200); pipelines + chains controllers Running |
| **Tekton Chains** | Fulcio + Rekor in `trusted-artifact-signer` | `signers.x509.fulcio.enabled=true`; issuer `https://kubernetes.default.svc`; audience patch for TAS | Signs OCI → storage `oci`; transparency → Rekor svc |
| **Trusted Artifact Signer** | Chains; cosign clients | SecureSign `securesign` Ready | Fulcio/Rekor/TUF/TSA Routes; Fulcio root `/` returns 404 (normal — API paths only) |
| **CNPG operator** | AO Postgres | Subscription in `cloudnative-pg` | Manages `orchestrator-postgres` |

---

## 4. Chart-expected I/O (tenant — not live yet)

Derived from `automation/gitops/bootstrap-tenant` helpers + templates. Substitute `{guid}` and `{domain}`.

### Namespaces the tenant chart creates

| Namespace | Purpose |
|-----------|---------|
| `lightwell-tenant-{guid}` | Bootstrap Jobs / tenant-integration |
| `lightwell-nexus-{guid}` | Nexus STS + Routes (UI + OCI) |
| `sdlc-{guid}` | OpenCode, Renovate SA/token, EDA-related secrets |
| `sdlc-sandboxes-{guid}` | MR verifier Jobs |
| `tpa-{guid}` (+ RHDA NS if enabled) | Per-tenant TPA |
| `snow-{guid}` | ServiceNow mock |
| `build-{guid}` | PaC Repository CRs + pipeline runs |
| `{username}-app` (tenant helper) | Student app project NS (chart `tenant/`) |

### Per-component contract (inputs → outputs)

| Component | Inputs (from whom) | Outputs (to whom) |
|-----------|--------------------|-------------------|
| **Nexus** | Helm: image `3.96.4-ubi`, storage 50Gi, optional Lightwell Network creds / `existingSecret`; admin password | Maven group + hosted `lightwell-*` / proxy `redhat-packages-*`; OCI repo port 5000; Routes `nexus-lightwell-nexus-{guid}.{domain}`, `nexus-oci-…`; **webhook POST** → EDA activation URL when creds/repos exist |
| **nexus-reconcile Job** | Secrets: Nexus admin, EDA webhook URL, optional LW Network | Creates repos, OCI realm/EULA, webhooks idempotently |
| **EDA activation** | Rulebook from `sdlc.orchestrator.enabled` (`sdlc-remediation.yml` vs legacy); SCM `rhpds/lw-sdlc-opencode`; AO client secret | Listens for Nexus/GitLab; Start/Resume AO **or** direct JTs |
| **AO tenant project** | `ao-bootstrap`: project `lightwell-{guid}`, webhook paths, AAP integration | Canvas workflow: Query TPA → Impact → (resume) MR Verifier; ServiceNow steps |
| **OpenCode** | Env: `LIGHTWELL_GUID`, sandbox/ephemeral NS, Nexus NS/repos, GitLab URL/user/PAT, optional `OPENAI_API_KEY` + LiteLLM model | MR diffs to GitLab; transcripts on UI Route `opencode-ui` (basic auth); launched by AAP JTs |
| **TPA** | OIDC client secret copied from Keycloak; dataset Job; SBOM uploads from Tekton | Query API for blast radius; UI `https://tpa-{guid}.{domain}` |
| **PaC / Tekton** | GitLab push webhook → PaC; params: image-registry, tpa-url, issuer-url, Nexus Maven mirror | Image → Nexus OCI; SBOM → TPA; Chains signature |
| **Renovate** | `renovate-token` PAT; RenovateJob (student `oc apply`) with Nexus `hostRules` | MRs as `renovate-bot` into `acme-{guid}/…` |
| **ServiceNow mock** | HTTP from AO/playbooks | Ticket JSON lifecycle for Path 2 UI |
| **GitLab tenant seeding** | `appSeeds` list (3 Acme apps); group `acme-{guid}` | Repos + Maintainer for `user-{guid}`; MR webhooks to EDA / PaC |

### Default URLs / names (helpers)

| Thing | Default |
|-------|---------|
| GitLab group | `acme-{guid}` |
| AI remediation project | `acme-{guid}/wire-transfer-svc` |
| Nexus validated/remediated proxy repos | `redhat-packages-validated-{guid}`, `redhat-packages-remediated-{guid}` |
| EDA activation | `sdlc-remediation-{guid}` |
| EDA webhook (in-cluster) | `http://sdlc-remediation-{guid}.aap.svc.cluster.local:5000/` |
| EDA webhook (Route) | `https://sdlc-remediation-{guid}-aap.{domain}/` |
| OpenCode svc | `http://opencode.sdlc-{guid}.svc.cluster.local:4096` |
| OpenCode image | `lightwell-images/sdlc-opencode:sha-aad125a` |
| Ephemeral MR NS prefix | `pr-test-mr-{guid}` |

---

## 5. Path impact on this cluster right now

| Path | Can demo today? | Blocker |
|------|-----------------|---------|
| **Path 1 Renovate** | No | No Nexus hosted Lightwell repo, no `acme-*` GitLab apps, no `renovate-token`, no RenovateJob |
| **Path 2 AI / AO** | No | No Nexus webhook → EDA activation, no OpenCode pod, no TPA instance, no SNOW, no AO tenant project |
| **Shared CI/CD spine** | Partially | Pipelines + Chains + TAS + GitLab + Argo are up; nothing triggers them without tenant PaC repos + merges |

> **Note:** Table above is the **j88nz infra-only** snapshot. For current Path readiness see **§0** (`cluster-5trcs` / `cng2l`).

---

## 6. Parent Helm values shape (redacted)

`lb1815-lightwell` on `5trcs` receives (from AgnosticV):

```yaml
admin:
  password: <redacted>
deployer:
  apiUrl: https://api.cluster-5trcs.dyn.redhatworkshops.io:6443
  domain: apps.cluster-5trcs.dyn.redhatworkshops.io
  guid: 5trcs-1
gitlab:
  rootPassword: <redacted>
jenkins:
  password: <redacted>
```

(j88nz used the same shape with `guid: j88nz-1` and that cluster’s API/domain.)

Child apps also get `deployer.storageClass: ocs-external-storagecluster-ceph-rbd-immediate` and component toggles (e.g. AO `orchestrator.enabled: true`, Pipelines `pipelines-1.24`, RHTAS `stable-v1.4`, OpenCode image tag from the `opencode-image` chart).

---

## 7. Investigation notes / anomalies

1. **Current lab is `5trcs`/`cng2l`** — full tenant + shared infra; see §0 / §0b.
2. **Quay is live but demo narrative prefers per-tenant Nexus OCI** (ADR-019/020). Quay remains available as shared registry capacity.
3. **Fulcio Route `/` → 404** — not a failure; SecureSign reports Ready.
4. **TUF Route `/` → 403** — also consistent with Ready SecureSign.
5. **AO allowlist Job** set `APP_INTEGRATION_URL_ALLOWED_HOSTS` to the AAP Route host — required for AO↔AAP (ADR-008).
6. **Repo naming drift still open** (HANDOFF): chart helpers use `redhat-packages-{validated,remediated}-{guid}`; Showroom Module 2 still references `lightwell-java-remediated` in places — settle before seeding Jobs.
7. **Argo admin password login via public gRPC** timed out; `--core` + kubeconfig works. Prefer that for automation.
8. **Do not commit** AgnosticV passwords that appear in Application Helm values — treat Application YAML as sensitive.
9. **Push `b06b131` (or equivalent) before Argo sync** on `lightwell-tenant-cng2l`, or sync will regress AO snow URL baking.

---

## 8. Suggested next checks (current tenant)

```bash
export ARGOCD_OPTS="--core"
GUID=cng2l
DOMAIN=apps.cluster-5trcs.dyn.redhatworkshops.io

argocd app get lightwell-tenant-$GUID
oc get ns | grep -E "$GUID|sdlc-|nexus-|tpa-|snow-|build-"

# Path 2 entry (natural vs showcase)
oc logs -n lightwell-nexus-$GUID -l job-name=nexus-reconcile --tail=80
cd ao-trigger-helper && ./trigger-nexus-webhook.sh $GUID needs-approval --watch

# TPA routing (benefits vs wire-transfer)
# Inspect latest SDLC Classify Affected Apps artifacts.ao_apps

# Path 1
oc get renovatejob -A
oc get secret renovate-token -n user-$GUID-renovate

# Shared spine after merge
oc get pipelinerun -n build-$GUID
oc get pods -n sdlc-$GUID -l app=opencode
```
