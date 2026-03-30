#!/usr/bin/env bash
set -euo pipefail

# 1. Create Nginx basic auth file
mkdir -p /etc/nginx/conf.d
htpasswd -Bbn "${VNC_USERNAME}" "${VNC_PASSWORD}" > /etc/nginx/.htpasswd

# 2. Start virtual display + VNC + websockify (internal)
Xvfb :99 -screen 0 1920x1080x24 &
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
export DISPLAY=:99
google-chrome \
    --no-sandbox \
    --disable-setuid-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --remote-debugging-port=9222 \
    --load-extension=/app/extension \
    --user-data-dir=/chrome-profile \
    --start-maximized \
    --no-first-run &

sleep 6
exec bun-browser daemon --host 0.0.0.0
