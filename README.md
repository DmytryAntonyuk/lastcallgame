# Last Call — сайт мода для Squad

Сайт **lastcallgame.fun**: суть режима, обновления, дорожная карта, сезоны с регистрацией на squaduck.fun и баг-репорты для Discord.

- `public/index.html` — весь сайт одним файлом.
- `deploy/nginx-lastcallgame.conf` — настройка веб-сервера.
- `deploy/setup-server.sh` — разовая настройка сервера. После неё сервер каждые 2 минуты сам забирает свежую версию из `main`.

Контент (новости, дорожная карта, сезоны, настройки) хранится в Supabase, в проекте **squadhub-prod**, в таблице `lastcall_site`. Администраторы меняют его на самом сайте: внизу страницы есть кнопка «Вход для администраторов», вход через Discord. Код для этого менять не нужно. Фото и видео хранятся в бакете `lastcall-media`.

## Первая настройка

### 1. DNS в IONOS
В управлении доменом lastcallgame.fun:
- A-запись `@` → `178.105.88.206`
- A-запись `www` → `178.105.88.206`
- удалить AAAA-записи и старые A-записи IONOS

### 2. Сервер (178.105.88.206)
Репозиторий должен быть публичным: сервер скачивает сайт без ключей. В веб-консоли Hetzner (или по SSH) под root:
```bash
curl -fsSL raw.githubusercontent.com/DmytryAntonyuk/lastcallgame/main/deploy/setup-server.sh -o s.sh
bash s.sh
```
Скрипт ставит git и certbot, клонирует репозиторий в `/opt/lastcallgame`, включает таймер `lastcall-pull.timer`, который раз в 2 минуты делает `git pull`, подключает конфиг nginx только для lastcallgame.fun (с проверкой и откатом) и выпускает HTTPS-сертификат. Настройки других сайтов на сервере он не трогает.

Обновить сайт вручную, не дожидаясь таймера: `systemctl start lastcall-pull.service`.

### 3. Supabase
Authentication → URL Configuration → Redirect URLs: добавить `https://lastcallgame.fun/**`.
Без этого вход через Discord на сайте не сработает.

## Администраторы
Новый администратор сначала один раз входит на сайт через Discord, потом его добавляют SQL-командой в squadhub-prod:
```sql
insert into public.lastcall_admins (user_id)
select id from auth.users where raw_user_meta_data->>'full_name' = '<ник в Discord>';
```
