#!/usr/bin/env bash
# One-time setup of lastcallgame.fun on the squaduck server.
# Run on the server:  sudo bash setup-server.sh
# Safe to re-run. Touches only lastcallgame.fun files, the deploy user and its SSH key.
set -euo pipefail

DOMAIN="lastcallgame.fun"
ROOT="/var/www/$DOMAIN"
DEPLOY_USER="${DEPLOY_USER:-lastcall-deploy}"
EMAIL="${EMAIL:-}"

say(){ printf '\n\033[1;31m==\033[0m %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || { echo "Запустите через sudo: sudo bash $0"; exit 1; }

say "1/6 Проверяю веб-сервер"
if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx на этом сервере не найден. Скорее всего, трафик принимает Docker (Traefik, Caddy и т. п.)."
  echo "Кто слушает порты 80 и 443:"
  (ss -ltnp 2>/dev/null | grep -E ':(80|443)\b') || true
  (docker ps --format '{{.Names}}  {{.Image}}  {{.Ports}}' 2>/dev/null) || true
  echo
  echo "Ничего не изменено. Пришлите этот вывод Claude, и он подготовит настройку под вашу схему."
  exit 2
fi
nginx -v
if [ -d /etc/nginx/sites-available ]; then
  CONF="/etc/nginx/sites-available/$DOMAIN"; LINK="/etc/nginx/sites-enabled/$DOMAIN"
else
  CONF="/etc/nginx/conf.d/$DOMAIN.conf"; LINK=""
fi

say "2/6 Ставлю rsync и certbot (если их нет)"
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  NEED=""
  command -v rsync >/dev/null || NEED="$NEED rsync"
  command -v certbot >/dev/null || NEED="$NEED certbot python3-certbot-nginx"
  dpkg -s python3-certbot-nginx >/dev/null 2>&1 || NEED="$NEED python3-certbot-nginx"
  if [ -n "$NEED" ]; then apt-get update -qq && apt-get install -y -qq $NEED; fi
else
  command -v rsync >/dev/null && command -v certbot >/dev/null || { echo "Установите rsync и certbot (с плагином nginx) вручную и запустите скрипт снова."; exit 1; }
fi

say "3/6 Пользователь для деплоя и папка сайта"
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$DEPLOY_USER"
mkdir -p "$ROOT"
if [ ! -f "$ROOT/index.html" ]; then
  echo '<!doctype html><meta charset="utf-8"><title>Last Call</title><p style="font-family:sans-serif;padding:40px">Last Call — сайт скоро появится.</p>' > "$ROOT/index.html"
fi
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$ROOT"

say "4/6 Конфиг nginx для $DOMAIN"
if [ -f "$CONF" ] && grep -q "managed-by: lastcall" "$CONF" && grep -q "ssl_certificate" "$CONF"; then
  echo "Конфиг уже настроен с HTTPS — оставляю как есть."
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
    echo "Проверка nginx не прошла — откатываю свои изменения."
    [ -n "$LINK" ] && rm -f "$LINK"
    if [ -n "$BACKUP" ]; then mv "$BACKUP" "$CONF"; else rm -f "$CONF"; fi
    exit 1
  fi
  systemctl reload nginx
fi

say "5/6 HTTPS-сертификат"
if [ -n "$EMAIL" ]; then MAIL=(-m "$EMAIL"); else MAIL=(--register-unsafely-without-email); fi
certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --redirect "${MAIL[@]}" || {
  echo "certbot не смог выпустить сертификат. Сайт уже доступен по http://$DOMAIN — пришлите этот вывод Claude."
}
nginx -t && systemctl reload nginx

say "6/6 SSH-ключ для GitHub Actions"
HOME_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$HOME_DIR/.ssh"
KEYTMP="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N "" -C "github-actions@lastcallgame" -f "$KEYTMP/key"
cat "$KEYTMP/key.pub" >> "$HOME_DIR/.ssh/authorized_keys"
chown "$DEPLOY_USER":"$DEPLOY_USER" "$HOME_DIR/.ssh/authorized_keys"; chmod 600 "$HOME_DIR/.ssh/authorized_keys"

echo
echo "Готово. Добавьте в GitHub → lastcallgame → Settings → Secrets and variables → Actions:"
echo
echo "  DEPLOY_HOST     = $(curl -fsS -4 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
echo "  DEPLOY_USER     = $DEPLOY_USER"
echo "  DEPLOY_SSH_KEY  = весь текст ниже, включая строки BEGIN и END:"
echo
cat "$KEYTMP/key"
rm -rf "$KEYTMP"
echo
echo "Ключ показан один раз и на сервере не сохранён. Потом запустите в GitHub Actions «Deploy to lastcallgame.fun»."
