#!/usr/bin/env bash
set -euo pipefail

# Minimal login env (Docker often omits USER)
export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/root}"

# 1. Create Nginx basic auth file
mkdir -p /etc/nginx/conf.d
htpasswd -Bbn "${VNC_USERNAME}" "${VNC_PASSWORD}" > /etc/nginx/.htpasswd

# 2. One framebuffer: Xvfb :99 for Chrome; x11vnc RFB on 5900; websockify on 5901 -> 5900
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
Xvfb :99 -screen 0 1920x1080x24 &
for _ in $(seq 1 100); do
  [[ -S /tmp/.X11-unix/X99 ]] && break
  sleep 0.05
done
export DISPLAY=:99
x11vnc -display :99 -rfbport 5900 -forever -shared -nopw -localhost &
websockify --web=/usr/share/novnc/ 5901 localhost:5900 &

# 3. Start Nginx with Basic Auth on port 6080
cat > /etc/nginx/conf.d/novnc.conf << 'EOF'
server {
    listen 6080;
    auth_basic "Restricted - bun-browser VNC";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        root /usr/share/novnc;
        index vnc.html;
        try_files $uri $uri/ =404;
    }

    location /websockify {
        proxy_pass http://localhost:5901;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
    }
}
EOF

nginx -g 'daemon off;' &

sleep 2

# 4. Start clash-for-linux proxy (Mihomo mixed-port default 7890)
CLASH_DIR=/opt/clash-for-linux
# clash-for-linux: mixed-port=7890 (HTTP), socks-port=7891 (SOCKS5)
PROXY_SERVER="${PROXY_SERVER:-socks5://127.0.0.1:7891}"

if [[ -n "${SUBSCRIPTION:-}" ]]; then
  if ! clashctl ls 2>/dev/null | grep -q .; then
    clashctl add "$SUBSCRIPTION" default
  fi
fi

if ! clashctl on; then
  echo "WARNING: clashctl on failed — Chrome will use proxy but traffic may not route until clash is healthy" >&2
fi

proxy_ready=0
for _ in $(seq 1 60); do
  if ss -tln 2>/dev/null | grep -qE ':789[01] '; then
    proxy_ready=1
    break
  fi
  sleep 0.5
done
if [[ "${proxy_ready}" -eq 0 ]]; then
  echo "WARNING: Mihomo proxy ports (7890/7891) not ready — check clashctl status / clashctl doctor" >&2
fi

# 5. Start Chrome with proxy + bun-browser daemon
CHROME_USER_DATA="${CHROME_USER_DATA:-/chrome-profile}"
rm -f "${CHROME_USER_DATA}/SingletonLock" \
      "${CHROME_USER_DATA}/SingletonSocket" \
      "${CHROME_USER_DATA}/SingletonCookie" 2>/dev/null || true

# chrome://settings/content/images → Don't allow sites to show images (2 = block)
mkdir -p "${CHROME_USER_DATA}/Default"
bun -e '
import { existsSync, readFileSync, writeFileSync } from "fs";
const path = process.argv[1];
let prefs = {};
if (existsSync(path)) {
  try { prefs = JSON.parse(readFileSync(path, "utf8")); } catch {}
}
prefs.profile ??= {};
prefs.profile.default_content_setting_values ??= {};
prefs.profile.default_content_setting_values.images = 2;
writeFileSync(path, JSON.stringify(prefs));
' "${CHROME_USER_DATA}/Default/Preferences"

google-chrome \
    --no-sandbox \
    --disable-setuid-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --blink-settings=imagesEnabled=false \
    --remote-debugging-port=9222 \
    --user-data-dir="${CHROME_USER_DATA}" \
    --proxy-server="${PROXY_SERVER}" \
    --start-maximized \
    --no-first-run &

sleep 6
export BUN_BROWSER_CDP_URL=http://127.0.0.1:9222
exec bun /app/dist/daemon.js --host 0.0.0.0 --cdp-port 9222
