#!/usr/bin/env bash
# Inject a fake Lightwell remediation into the tenant's Nexus lightwell-remediated repo.
# Simulates a new remediated package arriving from the Lightwell Network.
#
# Usage: ./inject-remediation.sh <groupId:artifactId:version> <rhlw-version> [description]
#
# Example:
#   ./inject-remediation.sh org.springframework.cloud:spring-cloud-starter-netflix-hystrix:2.2.10.RELEASE rhlw-00001 "Netflix Hystrix"

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <groupId:artifactId:version> <rhlw-suffix> [description]"
  echo ""
  echo "Example:"
  echo "  $0 org.springframework.cloud:spring-cloud-starter-netflix-hystrix:2.2.10.RELEASE rhlw-00001 \"Netflix Hystrix\""
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

echo "=== Injecting Lightwell Remediation ==="
echo ""
echo "  Package:     ${GROUP_ID}:${ARTIFACT_ID}"
echo "  Base version: ${BASE_VERSION}"
echo "  LW version:  ${RHLW_VERSION}"
echo "  Description: ${DESCRIPTION}"
echo ""

# Discover Nexus host and credentials
echo "--- Discovering Nexus ---"
GUID=$(oc whoami | sed 's/user-//')
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
echo "--- Uploading to Nexus (${REPO}) ---"

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

# Cleanup temp files
rm -f "${POM_FILE}" "${JAR_FILE}" "${META_FILE}" /tmp/lw-placeholder.txt

echo ""
echo "=== Remediation injected ==="
echo ""
echo "  ${GROUP_ID}:${ARTIFACT_ID}:${RHLW_VERSION}"
echo "  is now available in https://${NEXUS_HOST}/repository/${REPO}"
echo ""
