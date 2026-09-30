#!/usr/bin/env bash
# One-time setup of lastcallgame.fun on the squaduck server (no SSH keys needed).
# Run on the server as root:
#   curl -fsSL raw.githubusercontent.com/DmytryAntonyuk/lastcallgame/main/deploy/setup-server.sh -o s.sh
#   bash s.sh
# The server then pulls the public repository every 2 minutes, so a push to main
# goes live on its own. Safe to re-run. Touches only lastcallgame.fun files.
set -euo pipefail

DOMAIN="lastcallgame.fun"
REPO="https://github.com/DmytryAntonyuk/lastcallgame.git"
SRC="/opt/lastcallgame"
ROOT="$SRC/public"
EMAIL="${EMAIL:-}"

say(){ printf '\n== %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

say "1/5 Web server"
if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx not found. Ports 80/443 are used by:"
  (ss -ltnp 2>/dev/null | grep -E ':(80|443)\b') || true
  (docker ps --format '{{.Names}}  {{.Image}}  {{.Ports}}' 2>/dev/null) || true
  echo "Nothing was changed. Send this output to Claude."
  exit 2
fi
nginx -v
if [ -d /etc/nginx/sites-available ]; then
  CONF="/etc/nginx/sites-available/$DOMAIN"; LINK="/etc/nginx/sites-enabled/$DOMAIN"
else
  CONF="/etc/nginx/conf.d/$DOMAIN.conf"; LINK=""
fi

say "2/5 Packages (git, certbot)"
export DEBIAN_FRONTEND=noninteractive
NEED=""
command -v git >/dev/null || NEED="$NEED git"
command -v certbot >/dev/null || NEED="$NEED certbot"
dpkg -s python3-certbot-nginx >/dev/null 2>&1 || NEED="$NEED python3-certbot-nginx"
if [ -n "$NEED" ]; then apt-get update -qq && apt-get install -y -qq $NEED; fi

say "3/5 Site files from GitHub"
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" pull --ff-only -q
else
  rm -rf "$SRC"
  git clone -q --depth 1 "$REPO" "$SRC"
fi
ls -l "$ROOT/index.html"

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
echo "Auto-update: every 2 minutes"

say "4/5 nginx config"
if [ -f "$CONF" ] && grep -q "managed-by: lastcall" "$CONF" && grep -q "ssl_certificate" "$CONF" && grep -q "root $ROOT;" "$CONF"; then
  echo "Already configured with HTTPS."
else
  BACKUP=""
  [ -f "$CONF" ] && { BACKUP="$CONF.bak.$(date +%s)"; cp "$CONF" "$BACKUP"; }
  cat > "$CONF" <<NGINX
# managed-by: lastcall (setup-server.sh)
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    root $ROOT;
    index index.html;

    location ~ /\.git { deny all; }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    location = /index.html {
        add_header Cache-Control "no-cache";
    }
}
NGINX
  [ -n "$LINK" ] && ln -sf "$CONF" "$LINK"
  if ! nginx -t; then
    echo "nginx config test failed. Rolling back my changes."
    [ -n "$LINK" ] && rm -f "$LINK"
    if [ -n "$BACKUP" ]; then mv "$BACKUP" "$CONF"; else rm -f "$CONF"; fi
    exit 1
  fi
  systemctl reload nginx
fi

say "5/5 HTTPS certificate"
if [ -n "$EMAIL" ]; then MAIL=(-m "$EMAIL"); else MAIL=(--register-unsafely-without-email); fi
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --redirect "${MAIL[@]}"; then
  nginx -t && systemctl reload nginx
  echo
  echo "DONE: https://$DOMAIN"
else
  echo
  echo "Site is up on http://$DOMAIN, but the certificate failed. Send this output to Claude."
fi
