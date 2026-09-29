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
Скопируйте скрипт на сервер и запустите его:
```bash
scp deploy/setup-server.sh <you>@178.105.88.206:~
ssh <you>@178.105.88.206 'sudo bash ~/setup-server.sh'
```
Скрипт создаёт папку `/var/www/lastcallgame.fun` и пользователя `lastcall-deploy`, подключает конфиг nginx и проверяет его (при ошибке откатывает свои изменения), выпускает HTTPS-сертификат и один раз печатает SSH-ключ для секретов GitHub. Настройки других сайтов на сервере он не трогает.

### 3. Секреты GitHub (Settings → Secrets and variables → Actions)
- `DEPLOY_HOST` — `178.105.88.206`
- `DEPLOY_USER` — `lastcall-deploy`
- `DEPLOY_SSH_KEY` — ключ, который напечатал `setup-server.sh`
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
