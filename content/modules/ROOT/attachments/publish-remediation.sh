#!/usr/bin/env bash
# Publish a Lightwell remediation to the tenant's Nexus and TPA.
# Reproduces the publication flow of the Lightwell Network:
#   1. Uploads a remediated Maven artifact to Nexus (lightwell-remediated repo)
#   2. Publishes OSV advisories to TPA so the base version shows vulnerabilities
#      that are resolved by the remediated version
#
# Usage: ./publish-remediation.sh <groupId:artifactId:version> <rhlw-suffix> [description]
#
# Example:
#   ./publish-remediation.sh com.fasterxml.jackson.core:jackson-databind:2.13.5 rhlw-00001 "Jackson Databind"

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <groupId:artifactId:version> <rhlw-suffix> [description]"
  echo ""
  echo "Example:"
  echo "  $0 com.fasterxml.jackson.core:jackson-databind:2.13.5 rhlw-00001 \"Jackson Databind\""
  exit 1
fi

GAV="$1"
RHLW_SUFFIX="$2"
DESCRIPTION="${3:-Lightwell-remediated build}"

# Parse GAV
GROUP_ID=$(echo "${GAV}" | cut -d: -f1)
ARTIFACT_ID=$(echo "${GAV}" | cut -d: -f2)
BASE_VERSION=$(echo "${GAV}" | cut -d: -f3)
RHLW_VERSION="${BASE_VERSION}.${RHLW_SUFFIX}"
GROUP_PATH=$(echo "${GROUP_ID}" | tr '.' '/')

echo "=== Publishing Lightwell Remediation ==="
echo ""
echo "  Package:     ${GROUP_ID}:${ARTIFACT_ID}"
echo "  Base version: ${BASE_VERSION}"
echo "  LW version:  ${RHLW_VERSION}"
echo "  Description: ${DESCRIPTION}"
echo ""

# Discover tenant GUID
GUID=$(oc whoami | sed 's/user-//')
USERNAME=$(oc whoami)

# ---------------------------------------------------------------------------
# Part 1: Nexus — upload remediated artifact
# ---------------------------------------------------------------------------
echo "--- Discovering Nexus ---"
NEXUS_NS="lightwell-nexus-${GUID}"
NEXUS_HOST=$(oc get route nexus -n "${NEXUS_NS}" -o jsonpath='{.spec.host}' 2>/dev/null || oc get route -n "${NEXUS_NS}" -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
NEXUS_PASS=$(oc get secret nexus-admin-secret -n "${NEXUS_NS}" -o jsonpath='{.data.password}' | base64 -d)
echo "  Nexus host: ${NEXUS_HOST}"
echo "  Nexus namespace: ${NEXUS_NS}"
echo ""

# Create POM
echo "--- Creating POM ---"
POM_FILE=$(mktemp)
cat > "${POM_FILE}" <<POMEOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <modelVersion>4.0.0</modelVersion>
    <groupId>${GROUP_ID}</groupId>
    <artifactId>${ARTIFACT_ID}</artifactId>
    <version>${RHLW_VERSION}</version>
    <name>${DESCRIPTION}</name>
    <description>Lightwell-remediated build of ${ARTIFACT_ID} ${BASE_VERSION}</description>
</project>
POMEOF
echo "  POM created"

# Create placeholder JAR
echo "--- Creating JAR ---"
JAR_FILE=$(mktemp)
echo "remediated-${RHLW_VERSION}" > /tmp/lw-placeholder.txt
jar cf "${JAR_FILE}" /tmp/lw-placeholder.txt 2>/dev/null || zip -j "${JAR_FILE}" /tmp/lw-placeholder.txt 2>/dev/null
echo "  JAR created"

# Create maven-metadata.xml
echo "--- Creating Maven metadata ---"
META_FILE=$(mktemp)
cat > "${META_FILE}" <<METAEOF
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>${GROUP_ID}</groupId>
  <artifactId>${ARTIFACT_ID}</artifactId>
  <versioning>
    <latest>${RHLW_VERSION}</latest>
    <release>${RHLW_VERSION}</release>
    <versions>
      <version>${RHLW_VERSION}</version>
    </versions>
  </versioning>
</metadata>
METAEOF
echo "  Metadata created"

# Upload to Nexus
REPO="lightwell-remediated"
BASE_URL="https://${NEXUS_HOST}/repository/${REPO}/${GROUP_PATH}/${ARTIFACT_ID}"

echo ""
echo "--- Publishing to Nexus (${REPO}) ---"

echo -n "  Uploading POM... "
HTTP=$(curl -sk -u "admin:${NEXUS_PASS}" -X PUT \
  "${BASE_URL}/${RHLW_VERSION}/${ARTIFACT_ID}-${RHLW_VERSION}.pom" \
  -H "Content-Type: application/xml" --data-binary @"${POM_FILE}" -o /dev/null -w "%{http_code}")
echo "HTTP ${HTTP}"

echo -n "  Uploading JAR... "
HTTP=$(curl -sk -u "admin:${NEXUS_PASS}" -X PUT \
  "${BASE_URL}/${RHLW_VERSION}/${ARTIFACT_ID}-${RHLW_VERSION}.jar" \
  -H "Content-Type: application/java-archive" --data-binary @"${JAR_FILE}" -o /dev/null -w "%{http_code}")
echo "HTTP ${HTTP}"

echo -n "  Uploading metadata... "
HTTP=$(curl -sk -u "admin:${NEXUS_PASS}" -X PUT \
  "${BASE_URL}/maven-metadata.xml" \
  -H "Content-Type: application/xml" --data-binary @"${META_FILE}" -o /dev/null -w "%{http_code}")
echo "HTTP ${HTTP}"

rm -f "${POM_FILE}" "${JAR_FILE}" "${META_FILE}" /tmp/lw-placeholder.txt

echo ""
echo "  ${GROUP_ID}:${ARTIFACT_ID}:${RHLW_VERSION}"
echo "  is now available in https://${NEXUS_HOST}/repository/${REPO}"

# ---------------------------------------------------------------------------
# Part 2: TPA — publish OSV advisories
# ---------------------------------------------------------------------------
echo ""
echo "--- Discovering TPA ---"
TPA_NS="tpa-${GUID}"
TPA_HOST=$(oc get route -n "${TPA_NS}" -l app.kubernetes.io/component=server -o jsonpath='{.items[0].spec.host}' 2>/dev/null \
  || oc get route tpa -n "${TPA_NS}" -o jsonpath='{.spec.host}' 2>/dev/null \
  || oc get route -n "${TPA_NS}" -o jsonpath='{.items[0].spec.host}' 2>/dev/null)
echo "  TPA host: ${TPA_HOST}"

OIDC_SECRET=$(oc get secret oidc-cli -n "${TPA_NS}" -o jsonpath='{.data.client-secret}' | base64 -d)
KC_HOST=$(oc get route -n keycloak keycloak -o jsonpath='{.spec.host}' 2>/dev/null \
  || oc get route -n sso keycloak -o jsonpath='{.spec.host}' 2>/dev/null)
echo "  Keycloak: ${KC_HOST}"

echo -n "  Acquiring token... "
TPA_TOKEN=$(curl -sk -X POST \
  "https://${KC_HOST}/realms/sso/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=tpa-cli" \
  -d "client_secret=${OIDC_SECRET}" \
  -d "scope=create:document read:document" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -z "${TPA_TOKEN}" ]; then
  echo "FAILED (skipping TPA advisories)"
  echo ""
  echo "=== Remediation published (Nexus only) ==="
  exit 0
fi
echo "OK"

# Generate deterministic advisory IDs from the GAV
GAV_HASH=$(echo -n "${GAV}" | sha256sum | cut -c1-10)
NUM1=$(printf "%d" "0x${GAV_HASH:0:5}")
NUM2=$((NUM1 + 1))
NUM3=$((NUM1 + 2))
YEAR=$(date +%Y)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Advisory templates — three realistic vulnerability classes
declare -a ADV_IDS=("RHLW-${YEAR}-${NUM1}" "RHLW-${YEAR}-${NUM2}" "RHLW-${YEAR}-${NUM3}")
declare -a ADV_TITLES=(
  "${DESCRIPTION}: Denial of service via deeply nested structure processing"
  "${DESCRIPTION}: Unsafe deserialization allows remote code execution"
  "${DESCRIPTION}: Input validation bypass leads to information disclosure"
)
declare -a ADV_DETAILS=(
  "${GROUP_ID}:${ARTIFACT_ID} before ${RHLW_VERSION} is vulnerable to a denial of service attack. Processing deeply nested input structures causes excessive stack consumption, crashing the application."
  "${GROUP_ID}:${ARTIFACT_ID} before ${RHLW_VERSION} contains an unsafe deserialization vulnerability. An attacker can craft malicious input that bypasses type validation, leading to arbitrary code execution."
  "${GROUP_ID}:${ARTIFACT_ID} before ${RHLW_VERSION} insufficiently validates input boundaries, allowing an attacker to access internal object state and disclose sensitive information."
)
declare -a ADV_CVSS=(
  "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H"
  "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"
  "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N"
)

echo ""
echo "--- Publishing OSV advisories to TPA ---"

for i in 0 1 2; do
  ADV_ID="${ADV_IDS[$i]}"
  OSV_FILE=$(mktemp)

  cat > "${OSV_FILE}" <<OSVEOF
{
  "schema_version": "1.6.8",
  "id": "${ADV_ID}",
  "published": "${NOW}",
  "modified": "${NOW}",
  "severity": [
    {
      "type": "CVSS_V3",
      "score": "${ADV_CVSS[$i]}"
    }
  ],
  "references": [
    {
      "url": "https://access.redhat.com/security/updates/lightwell",
      "type": "WEB"
    }
  ],
  "summary": "${ADV_TITLES[$i]}",
  "details": "${ADV_DETAILS[$i]}",
  "aliases": [],
  "affected": [
    {
      "package": {
        "ecosystem": "Maven",
        "name": "${GROUP_ID}:${ARTIFACT_ID}",
        "purl": "pkg:maven/${GROUP_ID}/${ARTIFACT_ID}@${RHLW_VERSION}"
      },
      "versions": [
        "${BASE_VERSION}"
      ],
      "ranges": [
        {
          "type": "ECOSYSTEM",
          "events": [
            {
              "introduced": "0"
            },
            {
              "fixed": "${RHLW_VERSION}"
            }
          ]
        }
      ]
    }
  ],
  "credits": [
    {
      "name": "Red Hat Lightwell",
      "type": "REMEDIATION_DEVELOPER"
    }
  ],
  "database_specific": {
    "lightwell": {
      "source": "pnc-build",
      "backport_base_version": "${BASE_VERSION}"
    }
  }
}
OSVEOF

  echo -n "  ${ADV_ID}: ${ADV_TITLES[$i]:0:60}... "
  HTTP=$(curl -sk -X POST "https://${TPA_HOST}/api/v3/advisory" \
    -H "Authorization: Bearer ${TPA_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @"${OSV_FILE}" -o /dev/null -w "%{http_code}")
  echo "HTTP ${HTTP}"

  rm -f "${OSV_FILE}"
done

echo ""
echo "=== Remediation published ==="
echo ""
echo "  Nexus:  ${GROUP_ID}:${ARTIFACT_ID}:${RHLW_VERSION}"
echo "          https://${NEXUS_HOST}/repository/${REPO}"
echo ""
echo "  TPA:    3 advisories published (${ADV_IDS[0]}, ${ADV_IDS[1]}, ${ADV_IDS[2]})"
echo "          https://${TPA_HOST}"
echo ""
echo "  The base version (${BASE_VERSION}) now shows vulnerabilities in TPA."
echo "  After building with ${RHLW_VERSION}, those vulnerabilities will be resolved."
echo ""
