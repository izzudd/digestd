# digestd

Feeds in, one EPUB issue out, every morning.

I built this so I could read my RSS and other feeds on a Xteink X4 Pro running [CrossPoint](https://crosspointreader.com) instead of on my phone. Nothing in it is specific to that reader: the output is a plain EPUB served over OPDS, so anything that speaks OPDS can pull the same issues — KOReader, a Kobo, an Android reader app, another e-ink device.

The reader can't fetch feeds by itself. CrossPoint keeps background Wi-Fi and an RSS feature out of scope (single-core ESP32-S3, deep sleep), so nothing on the device can poll on a schedule. So the digest is built on a server: [RSSPub](https://github.com/harshit181/RSSPub) runs in a container, rebuilds one newspaper every morning, and the reader downloads it as a catalog entry.

```
feeds (RSS/Atom)
      │  fetch + readability extraction + image downscale
      ▼
RSSPub  ──  /opds          Atom catalog the reader browses
        ──  /epubs/*.epub  one digest per day, pruned after 7 days
        ──  /              feed CRUD dashboard (basic auth)
      │
      ▼
reader: add <host>/opds as an OPDS catalog
```

Live instance: <https://feed.izzudd.my.id> (dashboard requires basic auth; `/opds` and the EPUBs are public).

## What this repo is, and what it is not

This is the **deployment**, not a fork of the generator: pinned container image, compose file, runbook, operational scripts, and the CrossPoint catalog plugin I use on my own reader. The EPUB engine, dashboard and OPDS server are RSSPub's work — MIT, by [@harshit181](https://github.com/harshit181). If you want to change the generator itself, fork upstream.

## Deploy

The instance this repo describes runs on [Coolify](https://coolify.io) as a Docker-image application. Any Docker host works the same way:

```bash
cp .env.example .env      # set the dashboard credentials
docker compose up -d      # dashboard on :3000
```

Then, in the dashboard (`http://<host>:3000`), add feeds and one schedule. Two settings live under **General config**:

| Setting | Value used here | Why |
|---|---|---|
| `fetch_since_hours` | `30` | Default window for ad-hoc runs. Each scheduled category overrides it (see the rotation below), because a window must be wider than that category's run interval — with a weekly schedule and a 24 h window, an article published between runs never appears in any issue. |
| `cleanup_after_hours` | `168` | Keep a week of digests, then delete. Also keeps the OPDS list short. |

`docs/coolify.md` has the Coolify-specific steps, including the two failures that cost the most time: the image has no `curl`/`wget` (so a Coolify health check rolls the deploy back as unhealthy), and Let's Encrypt cannot issue a certificate behind a proxied Cloudflare record until the challenge is answered by the origin.

## Reading it

Any OPDS client: point it at `https://<host>/opds`. The URL must include `/opds` — pointing at the bare host gives "failed to parse feed".

**CrossPoint (what I use).** Two ways:

- *OPDS, no files to install.* Settings → Connectivity → OPDS Servers → add `https://<host>/opds`, then browse from File Transfer → OPDS Browser.
- *SD plugin, a one-tap list under Home → Plugins.* Copy `plugin/daily-digest/` to `/.crosspoint/plugins/daily-digest/` on the card (`/plugins` and `/.plugins` also work), then enable Settings → Connectivity → Plugins. Downloads land in `/Digest`; the firmware is told to read the Atom feed with its `xml` catalog mode instead of expecting JSON.

## The feeds, and how they're grouped

RSSPub lets you file each feed under a category, which is what keeps a 17-feed digest readable: the issue is built per feed, and a category is what a second schedule would select from later.

| Category | Feeds |
|---|---|
| Engineering | Cloudflare Blog, Google Research, Meta Engineering, Netflix Tech Blog, Stripe Engineering, Shopify Engineering |
| AI & Research | Hugging Face daily papers (via the worker below) |
| Personal Blogs | Simon Willison, Pragmatic Engineer, Human Who Codes, Invasikode |
| Community | Hacker News (200+ points), dev.to |
| Design | Sidebar |
| Podcast | Syntax.fm |
| Hardware | Liliputing, Xteink News |

When adding a feed later, give it a category in the same request: the dashboard has the dropdown, and `scripts/add-feed.sh` takes an optional category id as its third argument. An uncategorised feed still works, it just has no home in the list.

## The rotation: one category per day

A 47-article issue a day is not a newspaper, it's homework. So each category gets its own weekly slot — one small issue arrives every morning at 05:00 WIB and the reader never holds more than one category at a time.

| Arrives | Category | Window |
|---|---|---|
| Mon | Engineering | 168 h |
| Tue | AI & Research | 48 h |
| Wed | Community | 24 h |
| Thu | Personal Blogs | 168 h |
| Fri | Design | 72 h |
| Sat | Hardware | 168 h |
| Sun | Podcast | 168 h |

Windows follow each category's cadence: a weekly slot needs a week's window or posts fall between runs; Community is a firehose (Hacker News plus dev.to) so it samples the last 24 h only — that is the deliberate trade for keeping the issue small, and it's why HN is pinned to 200+ points.

Creating them is fiddly because of one conversion quirk (see below), so this is the exact call per slot:

```bash
# one schedule per category; hour/minute are converted by RSSPub, day_of_week is not what you'd expect
curl -u "$RPUB_USER:$RPUB_PASS" -X POST "$RPUB_URL/schedules" -H 'Content-Type: application/json' -d '{
  "hour": 15, "minute": 0, "timezone": "UTC", "schedule_type": "rss", "frequency": "weekly",
  "day_of_week": 6, "category_ids": [1], "fetch_since_hours_override": 168
}'
```

**The quirk:** RSSPub takes your `hour`/`minute`/`day_of_week` in the timezone you name, converts them to the container's local time, and stores *that* as a cron — which `tokio-cron-scheduler` then fires in UTC. With `TZ=Asia/Jakarta` that is +7 h and +1 day on the stored cron. `hour: 15` becomes `22:00` (correct: 05:00 WIB), but the weekday also lands one day late, so the input day is `arrival - 2` (mod 7). Always read `cron_expression` back and trust only that: `0 0 22 * * 0` is "Sunday night UTC, arrives Monday".

### A feed that doesn't exist yet: Hugging Face papers

[Hugging Face daily papers](https://huggingface.co/papers) has no RSS. The API is JSON (`/api/daily_papers`), `/papers/rss` answers 401, and the community RSS mirrors I tried were days stale. `workers/hf-papers.js` turns that JSON into Atom, keeps only papers submitted in the last N days and sorts by upvotes, so the digest gets the popular papers of the day instead of the firehose.

```bash
npx wrangler deploy workers/hf-papers.js --name hf-papers --compatibility-date 2025-09-01
# add as a feed: https://<worker>.<your-subdomain>.workers.dev/?limit=12&days=2
```

Params: `limit` (1-30, default 8), `days` (default 2), `min_upvotes`. Upstream rejects `limit > 100` with a 400, which is why the worker fetches 100 and filters locally.

## Daily operation

```bash
scripts/health.sh                     # endpoint + catalog + newest digest
scripts/list-feeds.sh                 # id, name, url
scripts/add-feed.sh "Name" "https://example.com/feed/"
scripts/regenerate.sh                 # build an issue now (the 05:00 run does this itself)
```

All scripts read `RPUB_URL`, `RPUB_USER` and `RPUB_PASS` from the environment (or a `.env` in the working directory).

Two things that are easy to get wrong:

- **The schedule is stored in UTC.** RSSPub converts the hour/minute you enter from the timezone you picked into the container's local time, but `tokio-cron-scheduler` fires the stored cron in UTC. Read `cron_expression` back from `GET /schedules` and trust that, not the `time` field. `0 0 22 * * *` is 05:00 WIB.
- **There is no delete endpoint for a generated EPUB.** Files age out via `cleanup_after_hours`. To drop one now, run `rm` inside the container (on Coolify: a scheduled task with `rm -f /app/epubs/<file>`, executed once, then deleted).

Upgrading is a tag bump: RSSPub publishes versioned images, so change the tag, redeploy, and re-read the two settings above (config lives in the SQLite volume, but a version that changes defaults is worth checking).

## Layout

```
docker-compose.yml        RSSPub container, pinned tag, volumes for db + epubs
.env.example              dashboard credentials
plugin/daily-digest/      CrossPoint SD plugin (device.json + manifest + README)
scripts/                  health, feed management, on-demand generation
workers/hf-papers.js      Cloudflare Worker: Hugging Face daily papers -> Atom
docs/coolify.md           Coolify deploy runbook and its two traps
```

## License

MIT for everything in this repository (see `LICENSE`). The container image is [RSSPub](https://github.com/harshit181/RSSPub), MIT © its authors.
