#!/usr/bin/env bash
set -euo pipefail

# Minimal login env (Docker often omits USER; tightvnc needs it)
export USER="${USER:-$(id -un)}"
export HOME="${HOME:-/root}"

# 1. Create Nginx basic auth file
mkdir -p /etc/nginx/conf.d
htpasswd -Bbn "${VNC_USERNAME}" "${VNC_PASSWORD}" > /etc/nginx/.htpasswd

# 2. TightVNC provides :1 (what noVNC shows). Chrome must use the same DISPLAY — not a
#    separate Xvfb :99 or the browser runs "invisibly" while VNC shows an empty desktop.
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
tightvncserver :1 -geometry 1920x1080 -depth 24 &
websockify --web=/usr/share/novnc/ 5901 localhost:5901 &

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
sleep 3
export DISPLAY=:1

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
