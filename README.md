# Last Call — сайт мода для Squad

Сайт **lastcallgame.fun**: суть режима, обновления, дорожная карта, сезоны с регистрацией на squaduck.fun и баг-репорты для Discord.

- `public/index.html` — весь сайт одним файлом.
- `deploy/nginx-lastcallgame.conf` — настройка веб-сервера.
- `.github/workflows/deploy.yml` — при каждом пуше в `main` сайт копируется на сервер.

Контент (новости, дорожная карта, сезоны, настройки) хранится в Supabase, в проекте **squadhub-prod**, в таблице `lastcall_site`. Администраторы меняют его на самом сайте: внизу страницы есть кнопка «Вход для администраторов», вход через Discord. Код для этого менять не нужно. Фото и видео хранятся в бакете `lastcall-media`.

## Первая настройка

### 1. DNS в IONOS
В управлении доменом lastcallgame.fun:
- A-запись `@` → `178.105.88.206`
- A-запись `www` → `178.105.88.206`
- удалить AAAA-записи и старые A-записи IONOS

### 2. Сервер (178.105.88.206)
```bash
sudo mkdir -p /var/www/lastcallgame.fun
sudo chown <deploy-user>:<deploy-user> /var/www/lastcallgame.fun
sudo cp deploy/nginx-lastcallgame.conf /etc/nginx/sites-available/lastcallgame.fun
sudo ln -s /etc/nginx/sites-available/lastcallgame.fun /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d lastcallgame.fun -d www.lastcallgame.fun
```
Сертификат выпускается, когда DNS уже указывает на сервер.

### 3. Секреты GitHub (Settings → Secrets and variables → Actions)
- `DEPLOY_HOST` — `178.105.88.206`
- `DEPLOY_USER` — пользователь на сервере с правом записи в `/var/www/lastcallgame.fun`
- `DEPLOY_SSH_KEY` — приватный SSH-ключ этого пользователя. Публичную часть ключа добавьте в `~/.ssh/authorized_keys` на сервере
- `DEPLOY_PATH` — необязательно, по умолчанию `/var/www/lastcallgame.fun`

### 4. Supabase
Authentication → URL Configuration → Redirect URLs: добавить `https://lastcallgame.fun/**`.
Без этого вход через Discord на сайте не сработает.

## Администраторы
Новый администратор сначала один раз входит на сайт через Discord, потом его добавляют SQL-командой в squadhub-prod:
```sql
insert into public.lastcall_admins (user_id)
select id from auth.users where raw_user_meta_data->>'full_name' = '<ник в Discord>';
```
