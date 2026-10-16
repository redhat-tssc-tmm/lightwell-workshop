#!/usr/bin/env bash
# Showcase: fire a Nexus-shaped component CREATED webhook at the tenant EDA
# listener to start the AO Lightwell Remediation canvas.
#
# Two policy demos (driven by which app TPA returns + .lightwell/policy.json):
#
#   needs-approval  → com.h2database:h2     → wire-transfer-svc (AO, human gate)
#   auto-approve    → org.flywaydb:flyway-core → benefits-mgmt-app (AO, merge)
#
# Usage:
#   ./trigger-nexus-webhook.sh <guid> needs-approval
#   ./trigger-nexus-webhook.sh <guid> auto-approve
#   ./trigger-nexus-webhook.sh <guid> both              # sequential; pause between
#
# Options:
#   --watch            Poll AAP Controller jobs until idle (requires admin)
#   --dry-run          Print payload + URL; do not POST
#   --version <ver>    Full Maven version including .rhlw-* (default: unique stamp)
#
# Overrides (optional):
#   EDA_WEBHOOK_ROUTE_URL   Skip discovery
#   NEEDS_APPROVAL_GAV      group:artifact:baseVersion  (default h2)
#   AUTO_APPROVE_GAV        group:artifact:baseVersion  (default flyway-core)
#
# Requires: oc, curl, python3; kube context with access to lightwell-tenant-<guid>.
# Note: a cached GAV cannot re-trigger Nexus itself — this script POSTs the
# webhook body directly (same shape Nexus would send). Use a fresh --version
# (or accept the default timestamp) so Impact does not short-circuit as
# already_current when the pom already carries that fix.

set -euo pipefail

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

GUID=""
CASE=""
WATCH=false
DRY_RUN=false
VERSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --watch) WATCH=true ;;
    --dry-run) DRY_RUN=true ;;
    --version)
      shift
      VERSION_OVERRIDE="${1:?--version requires a value}"
      ;;
    needs-approval|auto-approve|both)
      CASE="$1"
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *)
      if [[ -z "${GUID}" ]]; then
        GUID="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage 1
      fi
      ;;
  esac
  shift
done

if [[ -z "${GUID}" || -z "${CASE}" ]]; then
  echo "Usage: $0 <guid> {needs-approval|auto-approve|both} [--watch] [--dry-run] [--version VER]" >&2
  exit 1
fi

NS_TENANT="lightwell-tenant-${GUID}"
AAP_NS="${AAP_NAMESPACE:-aap}"
NEEDS_APPROVAL_GAV="${NEEDS_APPROVAL_GAV:-com.h2database:h2:2.2.224}"
AUTO_APPROVE_GAV="${AUTO_APPROVE_GAV:-org.flywaydb:flyway-core:4.1.2}"

cm_get() {
  oc get configmap tenant-integration -n "${NS_TENANT}" -o "jsonpath={.data.${1}}" 2>/dev/null || true
}

discover_eda_route() {
  if [[ -n "${EDA_WEBHOOK_ROUTE_URL:-}" ]]; then
    echo "${EDA_WEBHOOK_ROUTE_URL}"
    return
  fi
  local from_cm host
  from_cm="$(cm_get EDA_WEBHOOK_ROUTE_URL)"
  if [[ -n "${from_cm}" ]]; then
    echo "${from_cm}"
    return
  fi
  host="$(oc get route "sdlc-remediation-${GUID}" -n "${AAP_NS}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -z "${host}" ]]; then
    echo "ERROR: could not find EDA route sdlc-remediation-${GUID} in ${AAP_NS}" >&2
    echo "       Set EDA_WEBHOOK_ROUTE_URL or check tenant bootstrap." >&2
    exit 1
  fi
  echo "https://${host}/"
}

# Warn if EDA activation pod is younger than 60s (HANDOFF gotcha).
check_activation_age() {
  local age
  age="$(oc get pods -n "${AAP_NS}" -o json 2>/dev/null | python3 -c '
import json,sys
from datetime import datetime,timezone
pods=json.load(sys.stdin).get("items") or []
acts=[p for p in pods if p["metadata"]["name"].startswith("activation-job")]
if not acts:
  print("missing")
  raise SystemExit
ages=[]
for p in acts:
  cts=p["metadata"]["creationTimestamp"]
  age=(datetime.now(timezone.utc)-datetime.fromisoformat(cts.replace("Z","+00:00"))).total_seconds()
  ages.append(age)
print(int(min(ages)))
' 2>/dev/null || echo "unknown")"
  if [[ "${age}" == "missing" ]]; then
    echo "WARN: no activation-job-* pod in ${AAP_NS} — webhook may be dropped" >&2
  elif [[ "${age}" == "unknown" ]]; then
    echo "WARN: could not read activation pod age" >&2
  elif [[ "${age}" -lt 60 ]]; then
    echo "WARN: EDA activation pod age=${age}s (<60s). Waiting $((60 - age))s…" >&2
    sleep "$((60 - age))"
  fi
}

parse_gav() {
  # sets GROUP ARTIFACT BASE from group:artifact:baseVersion
  local gav="$1"
  GROUP="$(echo "${gav}" | cut -d: -f1)"
  ARTIFACT="$(echo "${gav}" | cut -d: -f2)"
  BASE="$(echo "${gav}" | cut -d: -f3-)"
  if [[ -z "${GROUP}" || -z "${ARTIFACT}" || -z "${BASE}" || "${BASE}" == "${gav}" ]]; then
    echo "ERROR: GAV must be group:artifact:baseVersion — got '${gav}'" >&2
    exit 1
  fi
}

unique_rhlw_version() {
  local base="$1"
  if [[ -n "${VERSION_OVERRIDE}" ]]; then
    echo "${VERSION_OVERRIDE}"
    return
  fi
  # Nexus / Impact treat identical fix versions as already_current after a merge.
  echo "${base}.rhlw-$(date +%H%M%S)"
}

build_payload() {
  local group="$1" name="$2" version="$3"
  python3 -c '
import json,sys
group,name,version=sys.argv[1:4]
print(json.dumps({
  "action": "CREATED",
  "component": {
    "repositoryName": "lightwell-remediated",
    "format": "maven2",
    "group": group,
    "name": name,
    "version": version,
  },
}))
' "${group}" "${name}" "${version}"
}

post_webhook() {
  local url="$1" body="$2"
  local code tmp
  tmp="$(mktemp)"
  code="$(curl -sk -o "${tmp}" -w "%{http_code}" -X POST "${url}" \
    -H "Content-Type: application/json" \
    -d "${body}")"
  echo "HTTP ${code}"
  if [[ -s "${tmp}" ]]; then
    head -c 200 "${tmp}"
    echo
  fi
  rm -f "${tmp}"
  if [[ "${code}" != "200" && "${code}" != "201" && "${code}" != "202" ]]; then
    echo "ERROR: EDA webhook rejected the payload (HTTP ${code})" >&2
    exit 1
  fi
}

watch_jobs() {
  local aap_url aap_pass
  aap_url="$(oc get route aap -n "${AAP_NS}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -z "${aap_url}" ]]; then
    echo "WARN: --watch skipped (no AAP route in ${AAP_NS})" >&2
    return
  fi
  aap_url="https://${aap_url}"
  aap_pass="$(oc get secret aap-admin-password -n "${AAP_NS}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
  if [[ -z "${aap_pass}" ]]; then
    echo "WARN: --watch skipped (cannot read aap-admin-password)" >&2
    return
  fi
  echo ""
  echo "=== Watching AAP jobs (org user-${GUID}) — Ctrl-C to stop ==="
  python3 - "${aap_url}" "${aap_pass}" <<'PY'
import json, sys, time, urllib.request, ssl, base64
base, password = sys.argv[1], sys.argv[2]
ctx = ssl._create_unverified_context()
auth = base64.b64encode(f"admin:{password}".encode()).decode()
idle = 0
for i in range(72):
    req = urllib.request.Request(
        base + "/api/controller/v2/jobs/?order_by=-id&page_size=12",
        headers={"Authorization": f"Basic {auth}"},
    )
    with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
        d = json.load(r)
    jobs = d.get("results") or []
    print(f"--- t={i*5}s ---")
    for j in jobs[:12]:
        print(f"  {j['id']} {j['status']:12} {j['name']}")
    running = any(j["status"] in ("pending", "waiting", "running") for j in jobs)
    idle = 0 if running else idle + 1
    if i > 2 and idle >= 6:
        print("idle — done")
        break
    time.sleep(5)
PY
}

fire_case() {
  local label="$1" gav="$2" expect_app="$3" expect_approval="$4"
  local group artifact base version payload

  parse_gav "${gav}"
  group="${GROUP}"
  artifact="${ARTIFACT}"
  base="${BASE}"
  version="$(unique_rhlw_version "${base}")"
  payload="$(build_payload "${group}" "${artifact}" "${version}")"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo " Case:     ${label}"
  echo " GAV:      ${group}:${artifact}:${version}"
  echo " Expect:   ${expect_app}  (approval=${expect_approval})"
  echo " Webhook:  ${EDA_URL}"
  echo "════════════════════════════════════════════════════════════"
  echo "${payload}" | python3 -m json.tool
  echo ""

  if [[ "${DRY_RUN}" == true ]]; then
    echo "(dry-run — not posted)"
    return
  fi

  check_activation_age
  post_webhook "${EDA_URL}" "${payload}"
  echo "Posted. AO canvas: Start → SNOW → TPA → classify → for-each → finalize"
  echo "  Watch: https://ao.$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo '<cluster-domain>')"
  echo "  SNOW:  $(cm_get SNOW_URL)"
}

EDA_URL="$(discover_eda_route)"
# normalize trailing slash
[[ "${EDA_URL}" == */ ]] || EDA_URL="${EDA_URL}/"

echo "Tenant guid:  ${GUID}"
echo "EDA route:    ${EDA_URL}"

case "${CASE}" in
  needs-approval)
    fire_case "needs-approval" "${NEEDS_APPROVAL_GAV}" \
      "acme-${GUID}/wire-transfer-svc" "needs_approval"
    ;;
  auto-approve)
    fire_case "auto-approve" "${AUTO_APPROVE_GAV}" \
      "acme-${GUID}/benefits-mgmt-app" "auto_approve"
    ;;
  both)
    fire_case "needs-approval" "${NEEDS_APPROVAL_GAV}" \
      "acme-${GUID}/wire-transfer-svc" "needs_approval"
    if [[ "${DRY_RUN}" != true ]]; then
      echo ""
      echo "Waiting 90s before auto-approve case (let the first AO run settle)…"
      sleep 90
    fi
    # fresh stamp for second fire
    VERSION_OVERRIDE=""
    fire_case "auto-approve" "${AUTO_APPROVE_GAV}" \
      "acme-${GUID}/benefits-mgmt-app" "auto_approve"
    ;;
esac

if [[ "${WATCH}" == true && "${DRY_RUN}" != true ]]; then
  watch_jobs
fi

echo ""
echo "Tip: if TPA returns no apps for the auto-approve GAV, seed/upload an SBOM"
echo "     for benefits-mgmt-app that includes ${AUTO_APPROVE_GAV%%:*} coordinates,"
echo "     or override AUTO_APPROVE_GAV to a purl present in that app's SBOM."
