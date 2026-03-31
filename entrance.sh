#!/usr/bin/env bash
set -euo pipefail

# Minimal login env (Docker often omits USER)
export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/root}"

# 1. Create Nginx basic auth file
mkdir -p /etc/nginx/conf.d
htpasswd -Bbn "${VNC_USERNAME}" "${VNC_PASSWORD}" > /etc/nginx/.htpasswd

# 2. One framebuffer: Xvfb :99 for Chrome; x11vnc RFB on 5900; websockify on 5901 -> 5900
#    (cannot bind x11vnc and websockify both on 5901). TightVNC was dropped — it prompts for
#    a password in Docker ("Password too short") and often never brings :1 up, so Chrome
#    then fails with Missing X server / $DISPLAY.
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

# 4. Start Chrome + bun-browser daemon
sleep 2

# Persisted user-data-dir keeps SingletonLock from the *previous* container hostname/PID.
# Chrome then refuses to start ("another computer"). Safe here: one container, one Chrome.
CHROME_USER_DATA="${CHROME_USER_DATA:-/chrome-profile}"
rm -f "${CHROME_USER_DATA}/SingletonLock" \
      "${CHROME_USER_DATA}/SingletonSocket" \
      "${CHROME_USER_DATA}/SingletonCookie" 2>/dev/null || true

google-chrome \
    --no-sandbox \
    --disable-setuid-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --remote-debugging-port=9222 \
    --load-extension=/app/extension \
    --user-data-dir="${CHROME_USER_DATA}" \
    --start-maximized \
    --no-first-run &

sleep 6
exec bun-browser daemon --host 0.0.0.0
