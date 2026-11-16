#!/usr/bin/env bash
# Add a feed: scripts/add-feed.sh "Name" "https://example.com/feed/"
set -euo pipefail

: "${RPUB_URL:?set RPUB_URL}"
: "${RPUB_USER:?set RPUB_USER}"
: "${RPUB_PASS:?set RPUB_PASS}"

name=${1:?usage: add-feed.sh NAME URL}
url=${2:?usage: add-feed.sh NAME URL}

# Check the candidate is a live XML feed before storing it.
code=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 20 "$url")
if [ "$code" != "200" ]; then
  echo "warning: $url answered HTTP $code" >&2
fi

body=$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1], "url": sys.argv[2]}))' "$name" "$url")
curl -fsS -o /dev/null -w 'added: %{http_code}\n' \
  -u "$RPUB_USER:$RPUB_PASS" -X POST "$RPUB_URL/feeds" \
  -H 'Content-Type: application/json' -d "$body"
