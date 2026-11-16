#!/usr/bin/env bash
# Report endpoint health, catalog size and the newest digest.
set -euo pipefail

: "${RPUB_URL:?set RPUB_URL, e.g. https://feed.example.com}"
: "${RPUB_USER:?set RPUB_USER}"
: "${RPUB_PASS:?set RPUB_PASS}"

auth=(-u "$RPUB_USER:$RPUB_PASS")

version=$(curl -fsS "${auth[@]}" "$RPUB_URL/api/version" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','?'))")
echo "version:  $version"

entries=$(curl -fsS "$RPUB_URL/opds" | grep -c '<entry>' || true)
echo "catalog:  $entries digest(s) in /opds"

latest=$(curl -fsS "${auth[@]}" "$RPUB_URL/downloads" | tr -d '[]"' | cut -d, -f1)
if [ -z "$latest" ]; then
  echo "newest:   none yet"
else
  size=$(curl -fsSI "$RPUB_URL/epubs/$latest" | awk 'tolower($1)=="content-length:" {print $2}' | tr -d '\r')
  echo "newest:   $latest (${size:-?} bytes)"
fi

echo
curl -fsS "${auth[@]}" "$RPUB_URL/schedules"
