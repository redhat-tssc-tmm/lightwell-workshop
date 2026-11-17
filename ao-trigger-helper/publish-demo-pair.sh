#!/usr/bin/env bash
# Publish both Path 2 remediations for a tenant with one rhlw suffix:
#   1) commons-text → benefits-mgmt-app (auto_approve)
#   2) h2           → wire-transfer-svc  (needs_approval)
#
# Usage:
#   GUID=<guid> ./publish-demo-pair.sh rhlw-00022
#   GUID=<guid> ./publish-demo-pair.sh 00022
#
# Waits for the benefits Impact Analyzer job to finish before publishing
# wire, so the two Starts do not overlap on OpenCode.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  echo "Usage: GUID=<guid> $0 <rhlw-NNNNN|NNNNN>" >&2
  echo "Example: GUID=f6rc7 $0 rhlw-00022" >&2
  exit 1
fi

RAW="$1"
case "${RAW}" in
  rhlw-*) RHLW_SUFFIX="${RAW}" ;;
  *)      RHLW_SUFFIX="rhlw-${RAW}" ;;
esac

if [[ ! "${RHLW_SUFFIX}" =~ ^rhlw-[0-9]+$ ]]; then
  echo "ERROR: suffix must look like rhlw-00022 (got '${RHLW_SUFFIX}')" >&2
  exit 1
fi

if [ -z "${GUID:-}" ]; then
  WHOAMI=$(oc whoami 2>/dev/null || true)
  case "${WHOAMI}" in
    user-*) GUID="${WHOAMI#user-}" ;;
    *)
      echo "ERROR: set GUID=<tenant> (or oc login as user-<guid>)" >&2
      exit 1
      ;;
  esac
fi

export GUID

BENEFITS_GAV="org.apache.commons:commons-text:1.9"
WIRE_GAV="com.h2database:h2:1.4.200"

echo "=== Path 2 demo pair ==="
echo "  GUID:   ${GUID}"
echo "  Suffix: ${RHLW_SUFFIX}"
echo "  1) ${BENEFITS_GAV}  → benefits-mgmt-app (auto_approve)"
echo "  2) ${WIRE_GAV}      → wire-transfer-svc (needs_approval)"
echo ""

aap_baseline_job_id() {
  local host pass
  host=$(oc get route aap -n aap -o jsonpath='{.spec.host}')
  pass=$(oc get secret aap-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d)
  python3 - "${host}" "${pass}" <<'PY'
import json, sys, urllib.request, ssl, base64
host, password = sys.argv[1], sys.argv[2]
ctx = ssl._create_unverified_context()
auth = base64.b64encode(f"admin:{password}".encode()).decode()
req = urllib.request.Request(
    f"https://{host}/api/controller/v2/jobs/?order_by=-id&page_size=1",
    headers={"Authorization": f"Basic {auth}"},
)
with urllib.request.urlopen(req, context=ctx, timeout=60) as r:
    print(json.load(r)["results"][0]["id"])
PY
}

wait_for_impact_after() {
  local before="$1" timeout_s="${2:-600}"
  local host pass
  host=$(oc get route aap -n aap -o jsonpath='{.spec.host}')
  pass=$(oc get secret aap-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d)
  echo "--- Waiting for SDLC Trigger Impact Analyzer (job id > ${before}) ---"
  python3 - "${host}" "${pass}" "${before}" "${timeout_s}" <<'PY'
import json, sys, time, urllib.request, ssl, base64
host, password, before, timeout_s = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
ctx = ssl._create_unverified_context()
auth = base64.b64encode(f"admin:{password}".encode()).decode()

def get(path):
    req = urllib.request.Request(
        f"https://{host}{path}",
        headers={"Authorization": f"Basic {auth}"},
    )
    with urllib.request.urlopen(req, context=ctx, timeout=90) as r:
        return json.load(r)

deadline = time.time() + timeout_s
while time.time() < deadline:
    jobs = get("/api/controller/v2/jobs/?order_by=-id&page_size=20")["results"]
    for j in jobs:
        if j["id"] <= before:
            continue
        if "Impact" not in j["name"]:
            continue
        status = j["status"]
        print(f"  Impact job {j['id']}: {status}", flush=True)
        if status in ("successful", "failed"):
            arts = get(f"/api/controller/v2/jobs/{j['id']}/").get("artifacts") or {}
            outcome = arts.get("iteration_outcome")
            iid = arts.get("merge_request_iid")
            path = arts.get("gitlab_path") or arts.get("project_path")
            print(
                f"  outcome={outcome} iid={iid} path={path}",
                flush=True,
            )
            # ADR-063: Impact JT stays successful on soft-fail; only mr_opened
            # means the demo pair should continue to the next publish.
            if status == "failed" or outcome != "mr_opened":
                sys.exit(
                    f"Impact job {j['id']} not demo-ready "
                    f"(status={status}, outcome={outcome}, iid={iid})"
                )
            sys.exit(0)
    time.sleep(5)
sys.exit(f"timed out after {timeout_s}s waiting for Impact > {before}")
PY
}

BEFORE=$(aap_baseline_job_id)
echo "AAP baseline job id: ${BEFORE}"
echo ""

echo "======== [1/2] benefits-mgmt-app ========"
GUID="${GUID}" bash "${ROOT}/publish-remediation.sh" \
  "${BENEFITS_GAV}" "${RHLW_SUFFIX}" "Commons Text demo pair"
wait_for_impact_after "${BEFORE}"

echo ""
echo "======== [2/2] wire-transfer-svc ========"
BEFORE=$(aap_baseline_job_id)
GUID="${GUID}" bash "${ROOT}/publish-remediation.sh" \
  "${WIRE_GAV}" "${RHLW_SUFFIX}" "H2 demo pair"
wait_for_impact_after "${BEFORE}"

echo ""
echo "=== Done ==="
echo "  Benefits: commons-text ${RHLW_SUFFIX} (auto_approve — expect merge)"
echo "  Wire:     h2 ${RHLW_SUFFIX} (needs_approval — MR left open)"
echo "  Re-run needs a new suffix; same GAV+suffix will not re-fire CREATED."
