# Coolify runbook

The live instance runs on Coolify as a **Docker image** application (project `Main`), not a git build. Steps below are what produced a working deployment.

## 1. Create the application

- Type: **Docker Image**
- Image: `harshit181/rsspub`, tag pinned (e.g. `0.123.0`) — pin it, `latest` hides upgrades
- Exposed port: `3000`
- Domain: `https://feed.<your-domain>`

## 2. Environment

| Key | Value |
|---|---|
| `RPUB_USERNAME` | dashboard user |
| `RPUB_PASSWORD` | dashboard password (basic auth) |
| `SECURE_OPDS` | `false` — keeps `/opds` and `/epubs/*` readable by the device with no credentials. Set `true` only if you are willing to embed basic auth in the reader/plugin. |
| `RUST_LOG` | `info,html5ever=error` |

## 3. Persistent volumes

Both, or you lose data on every redeploy:

- `/app/db` — SQLite: feeds, schedules, settings
- `/app/epubs` — generated digests (`mimetype` + `OEBPS/`), served at `/epubs/<file>.epub`

## 4. Turn the health check OFF

The image is `debian:trixie-slim` + `ca-certificates`; there is no `curl` and no `wget`. Coolify's default HTTP health check therefore fails with `/bin/sh: 1: curl: not found`, the container is marked unhealthy and the deploy **rolls back** — while the app itself logged `Listening on http://0.0.0.0:3000` perfectly fine. Disable the health check, or supply a command health check that the image can actually run.

## 5. TLS behind Cloudflare

With the DNS record proxied (orange cloud) and the zone's SSL mode on **Full (strict)**, the first deploy serves Traefik's default certificate, so the edge answers **HTTP 526** and Let's Encrypt never completes: the ACME HTTP-01 challenge is answered by Cloudflare, not the origin.

Fix, in this order:

1. Set the record to DNS-only (`proxied: false`) for both A and AAAA.
2. Restart the proxy (Coolify → Server → Proxy → Restart). This re-runs ACME for every router; expect a few seconds of downtime for all routed apps.
3. Confirm the origin certificate: `openssl s_client -connect <origin-ip>:443 -servername <host> | openssl x509 -noout -issuer` should say Let's Encrypt, not `TRAEFIK DEFAULT CERT`.
4. Flip the record back to proxied.

## 6. Configure it

Faster over the API than clicking (basic auth):

```bash
RPUB_URL=https://feed.example.com
A=(-u "$RPUB_USER:$RPUB_PASS")

# feeds
curl "${A[@]}" -X POST "$RPUB_URL/feeds" -H 'Content-Type: application/json' \
  -d '{"name":"Hacker News","url":"https://hnrss.org/frontpage?points=100"}'

# window + retention
curl "${A[@]}" -X POST "$RPUB_URL/general-config" -H 'Content-Type: application/json' \
  -d '{"fetch_since_hours":30,"image_timeout_seconds":30,"cover_text_enabled":true,
       "cover_text_color":"white","cover_text_position":"bottom-right","cover_text_size":"small",
       "cleanup_after_hours":168,"user_agent":null}'

# daily run; read cron_expression back — it is the UTC schedule
curl "${A[@]}" -X POST "$RPUB_URL/schedules" -H 'Content-Type: application/json' \
  -d '{"hour":15,"minute":0,"timezone":"UTC","schedule_type":"rss","frequency":"daily"}'
# -> "cron_expression":"0 0 22 * * *"  == 22:00 UTC == 05:00 WIB
```

The `hour`/`minute` you post are interpreted in the timezone you name and converted to the container's local time; the scheduler then fires the stored cron in UTC. With `TZ=Asia/Jakarta` in effect, posting `hour: 15, timezone: "UTC"` is what lands a 22:00 UTC cron. Always verify by reading `cron_expression`, never the `time` field.

## 7. First real check

Do not trust the dashboard alone — confirm a real file exists and parses:

```bash
curl -fsS "$RPUB_URL/opds" | grep -c '<entry>'
curl -fsSI -u "$RPUB_USER:$RPUB_PASS" "$RPUB_URL/downloads"
curl -fsSL "$RPUB_URL/downloads/latest_rss.epub" -o /tmp/digest.epub
python3 -c "import zipfile; z=zipfile.ZipFile('/tmp/digest.epub'); print(z.read('mimetype'), len(z.namelist()))"
```
