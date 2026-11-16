#!/usr/bin/env bash
# Build a digest now instead of waiting for the scheduled run.
set -euo pipefail

: "${RPUB_URL:?set RPUB_URL}"
: "${RPUB_USER:?set RPUB_USER}"
: "${RPUB_PASS:?set RPUB_PASS}"

auth=(-u "$RPUB_USER:$RPUB_PASS")

before=$(curl -fsS "${auth[@]}" "$RPUB_URL/downloads")
curl -fsS -o /dev/null -w 'request: %{http_code}\n' "${auth[@]}" \
  -X POST "$RPUB_URL/generate" -H 'Content-Type: application/json' -d '{"feeds":[]}'

echo -n 'waiting for a new file'
for _ in $(seq 1 60); do
  sleep 5
  now=$(curl -fsS "${auth[@]}" "$RPUB_URL/downloads")
  if [ "$now" != "$before" ]; then
    echo
    echo "done: $now"
    exit 0
  fi
  echo -n '.'
done

echo
echo "timed out after 5 minutes; check the container logs" >&2
exit 1
