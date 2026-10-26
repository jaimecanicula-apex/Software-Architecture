#!/bin/bash
# In-network availability probe. Runs as a scheduled Container Apps job inside
# the VNet, requests the private site, and records the result in Application
# Insights as an availability result (same table as internet web tests).
set -u

cs="$APPLICATIONINSIGHTS_CONNECTION_STRING"
ikey=$(printf '%s' "$cs" | tr ';' '\n' | sed -n 's/^InstrumentationKey=//p')
ingest=$(printf '%s' "$cs" | tr ';' '\n' | sed -n 's/^IngestionEndpoint=//p')
ingest="${ingest%/}"

started=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
result=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time "${TIMEOUT_SECONDS:-30}" "$TARGET_URL") || result="000 ${TIMEOUT_SECONDS:-30}"
code="${result% *}"
seconds="${result#* }"

success=false
[ "$code" = "$EXPECTED_STATUS" ] && success=true

duration=$(awk -v s="$seconds" 'BEGIN { printf "0.00:00:%06.3f", s }')
id=$(cat /proc/sys/kernel/random/uuid)

body=$(printf '{"name":"Microsoft.ApplicationInsights.%s.Availability","time":"%s","iKey":"%s","data":{"baseType":"AvailabilityData","baseData":{"ver":2,"id":"%s","name":"%s","duration":"%s","success":%s,"runLocation":"%s","message":"HTTP %s from %s"}}}' \
  "${ikey//-/}" "$started" "$ikey" "$id" "$TEST_NAME" "$duration" "$success" "$PROBE_LOCATION" "$code" "$TARGET_URL")

curl -s -o /dev/null -w 'ingest %{http_code}\n' -X POST -H 'Content-Type: application/json' --data "$body" "$ingest/v2.1/track"
echo "probe $TEST_NAME: HTTP $code in ${seconds}s success=$success"
