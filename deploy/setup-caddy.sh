#!/usr/bin/env bash
# lastcallgame.fun on the squaduck server, where Caddy (Docker) owns ports 80/443.
# Run as root in the Hetzner web console:
#   curl -fsSL raw.githubusercontent.com/DmytryAntonyuk/lastcallgame/main/deploy/setup-caddy.sh -o c.sh
#   bash c.sh
# What it does:
#   - clones the public repo to /opt/lastcallgame and pulls it every 2 minutes;
#   - runs a small nginx container "lastcall-web" on Caddy's Docker network that serves the site;
#   - appends one site block for lastcallgame.fun to the existing Caddyfile, validates it
#     (rolls back on error) and reloads Caddy without restarting it. Caddy issues HTTPS itself.
# Other sites in the Caddyfile are not touched. Safe to re-run.
set -euo pipefail

DOMAIN="lastcallgame.fun"
REPO="https://github.com/DmytryAntonyuk/lastcallgame.git"
SRC="/opt/lastcallgame"
WEB="lastcall-web"

say(){ printf '\n== %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

say "1/6 Find Caddy"
CADDY="$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /^caddy/ {print $1; exit}')"
[ -n "$CADDY" ] || { echo "No running Caddy container found. Nothing changed."; exit 2; }
read -r CFG_IN CFG_HOST NET < <(docker inspect "$CADDY" | python3 -c '
import json, sys
c = json.load(sys.stdin)[0]
args = c.get("Args") or []
cfg = "/etc/caddy/Caddyfile"
for i, a in enumerate(args):
    if a == "--config" and i + 1 < len(args):
        cfg = args[i + 1]
host, best = "", ""
for m in c.get("Mounts", []):
    d = m["Destination"].rstrip("/")
    if cfg == d or cfg.startswith(d + "/"):
        if len(d) > len(best):
            best, host = d, m["Source"] + cfg[len(d):]
nets = list(((c.get("NetworkSettings") or {}).get("Networks") or {}).keys())
print(cfg, host or "-", nets[0] if nets else "-")
')
echo "container: $CADDY"
echo "config:    $CFG_IN (on host: $CFG_HOST)"
echo "network:   $NET"
if [ "$CFG_HOST" = "-" ] || [ ! -f "$CFG_HOST" ] || [ "$NET" = "-" ]; then
  echo "Caddyfile is not mounted from the host or no network found. Nothing changed. Send this output to Claude."
  exit 2
fi
case "$CFG_IN" in *.json) echo "Caddy uses a JSON config. Nothing changed. Send this output to Claude."; exit 2;; esac

say "2/6 git"
command -v git >/dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git; }

say "3/6 Site files + auto-update"
if [ -d "$SRC/.git" ]; then git -C "$SRC" pull --ff-only -q; else rm -rf "$SRC"; git clone -q --depth 1 "$REPO" "$SRC"; fi
ls -l "$SRC/public/index.html"
cat > /etc/systemd/system/lastcall-pull.service <<UNIT
[Unit]
Description=Update lastcallgame.fun from GitHub
[Service]
Type=oneshot
ExecStart=/usr/bin/git -C $SRC pull --ff-only -q
UNIT
cat > /etc/systemd/system/lastcall-pull.timer <<UNIT
[Unit]
Description=Update lastcallgame.fun from GitHub every 2 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now lastcall-pull.timer >/dev/null
echo "auto-update every 2 minutes: on"

say "4/6 Web container $WEB"
docker rm -f "$WEB" >/dev/null 2>&1 || true
docker run -d --name "$WEB" --restart unless-stopped --network "$NET" \
  -v "$SRC/public:/usr/share/nginx/html:ro" nginx:1.27-alpine >/dev/null
sleep 2
docker ps --filter "name=^${WEB}$" --format '{{.Names}}  {{.Status}}'

say "5/6 Caddyfile"
if grep -q "^$DOMAIN" "$CFG_HOST"; then
  echo "Block for $DOMAIN already present."
else
  BK="$CFG_HOST.bak.lastcall.$(date +%s)"
  cp -p "$CFG_HOST" "$BK"
  printf '\n# lastcallgame.fun (added by lastcallgame deploy/setup-caddy.sh)\n%s, www.%s {\n\tencode zstd gzip\n\treverse_proxy %s:80\n}\n' "$DOMAIN" "$DOMAIN" "$WEB" >> "$CFG_HOST"
  if ! docker exec "$CADDY" caddy validate --config "$CFG_IN" --adapter caddyfile >/tmp/lastcall-validate.log 2>&1; then
    tail -n 20 /tmp/lastcall-validate.log
    cat "$BK" > "$CFG_HOST"
    echo "Caddy rejected the config. Rolled back. Send this output to Claude."
    exit 1
  fi
  echo "Backup: $BK"
fi
docker exec "$CADDY" caddy reload --config "$CFG_IN" --adapter caddyfile
echo "Caddy reloaded"

say "6/6 Check"
for i in $(seq 1 12); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" || true)"
  [ "$CODE" = "200" ] && break
  sleep 5
done
if [ "$CODE" = "200" ]; then
  echo "DONE: https://$DOMAIN"
else
  echo "HTTPS not ready yet (code $CODE). Caddy may still be getting the certificate. Last Caddy log lines:"
  docker logs --tail 15 "$CADDY" 2>&1 | grep -i -E "lastcall|error" || true
fi
echo
echo "NOTE: if the squadhub deploy rewrites this Caddyfile, add the same block to the Caddyfile in the squadhub repo:"
printf '  %s, www.%s {\n    encode zstd gzip\n    reverse_proxy %s:80\n  }\n' "$DOMAIN" "$DOMAIN" "$WEB"
