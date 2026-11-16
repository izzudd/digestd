#!/usr/bin/env bash
# List configured feeds: id, name, url.
set -euo pipefail

: "${RPUB_URL:?set RPUB_URL}"
: "${RPUB_USER:?set RPUB_USER}"
: "${RPUB_PASS:?set RPUB_PASS}"

curl -fsS -u "$RPUB_USER:$RPUB_PASS" "$RPUB_URL/feeds" | python3 -c "
import json, sys
for f in json.load(sys.stdin):
    print('%3d  %-28s %s' % (f['id'], f['name'] or '', f['url']))
"
