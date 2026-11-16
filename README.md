# eink-feed

A daily RSS digest for an e-ink reader (Xteink X4 Pro running [CrossPoint](https://crosspointreader.com)), built from feeds on a server and pulled over OPDS.

The reader cannot do this itself: CrossPoint deliberately keeps background Wi-Fi and an RSS feature out of scope (single-core ESP32-S3, deep sleep), so nothing on the device can poll feeds on a schedule. Instead, [RSSPub](https://github.com/harshit181/RSSPub) runs in a container, rebuilds one EPUB newspaper every morning, and the reader downloads it as an OPDS catalog entry.

```
feeds (RSS/Atom)
      │  fetch + readability extraction + image downscale
      ▼
RSSPub  ──  /opds        Atom catalog the reader browses
        ──  /epubs/*.epub  one digest per day, pruned after 7 days
        ──  /             feed CRUD dashboard (basic auth)
      │
      ▼
CrossPoint: Settings → Connectivity → OPDS Servers → <host>/opds
```

Live instance: <https://feed.izzudd.my.id> (dashboard requires basic auth; `/opds` and the EPUBs are public).

## What this repo is, and what it is not

This is the **deployment**, not a fork of the generator: pinned container image, compose file, runbook, operational scripts, and the CrossPoint catalog plugin. The EPUB engine, dashboard and OPDS server are RSSPub's work — MIT, by [@harshit181](https://github.com/harshit181). If you want to change the generator itself, fork upstream.

## Deploy

The instance this repo describes runs on [Coolify](https://coolify.io) as a Docker-image application. Any Docker host works the same way:

```bash
cp .env.example .env      # set the dashboard credentials
docker compose up -d      # dashboard on :3000
```

Then, in the dashboard (`http://<host>:3000`), add feeds and one schedule. Two settings live under **General config**:

| Setting | Value used here | Why |
|---|---|---|
| `fetch_since_hours` | `30` | A window must be wider than the run interval. With a daily run and a strict 24 h window, an article published between two runs falls outside both windows and never appears in any issue. 30 h closes the gap; the ~6 h overlap can repeat one article across two issues. |
| `cleanup_after_hours` | `168` | Keep a week of digests, then delete. Also keeps the OPDS list short. |

`docs/coolify.md` has the Coolify-specific steps, including the two failures that cost the most time: the image has no `curl`/`wget` (so a Coolify health check rolls the deploy back as unhealthy), and Let's Encrypt cannot issue a certificate behind a proxied Cloudflare record until the challenge is answered by the origin.

## Reading it on the device

**OPDS (no files to install).** Settings → Connectivity → OPDS Servers → add `https://<host>/opds`, then browse from File Transfer → OPDS Browser. The URL must include `/opds` — pointing at the bare host gives "failed to parse feed".

**SD plugin (one-tap list under Home → Plugins).** Copy `plugin/daily-digest/` to `/.crosspoint/plugins/daily-digest/` on the card (`/plugins` and `/.plugins` also work), then enable Settings → Connectivity → Plugins. The list downloads into `/Digest`, and the firmware is told to read the Atom feed with its `xml` catalog mode rather than expecting JSON.

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
docs/coolify.md           Coolify deploy runbook and its two traps
```

## License

MIT for everything in this repository (see `LICENSE`). The container image is [RSSPub](https://github.com/harshit181/RSSPub), MIT © its authors.
