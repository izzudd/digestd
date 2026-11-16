#!/usr/bin/env bash
# List feeds grouped by category: id, name, url.
set -euo pipefail

: "${RPUB_URL:?set RPUB_URL}"
: "${RPUB_USER:?set RPUB_USER}"
: "${RPUB_PASS:?set RPUB_PASS}"

CATS_JSON=$(curl -fsS -u "$RPUB_USER:$RPUB_PASS" "$RPUB_URL/categories")
FEEDS_JSON=$(curl -fsS -u "$RPUB_USER:$RPUB_PASS" "$RPUB_URL/feeds")
export CATS_JSON FEEDS_JSON

python3 - <<'PY'
import json, os

cats = {c["id"]: c["name"] for c in json.loads(os.environ["CATS_JSON"])}
feeds = json.loads(os.environ["FEEDS_JSON"])

by_cat = {}
for f in feeds:
    by_cat.setdefault(f.get("category_id"), []).append(f)

order = sorted((k for k in by_cat if k is not None), key=lambda k: cats.get(k, "").lower())
if None in by_cat:
    order.append(None)

for cid in order:
    print("\n" + cats.get(cid, "uncategorised"))
    for f in sorted(by_cat[cid], key=lambda x: (x.get("name") or "").lower()):
        print("  %3d  %-28s %s" % (f["id"], f["name"] or "", f["url"]))

print("\n%d feeds in %d categories" % (len(feeds), len([c for c in order if c is not None])))
PY
