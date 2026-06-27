#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Installing Mainsail and nginx config"
ensure_user
ensure_dirs

# Mainsail itself is static files served by nginx. Moonraker and webcam traffic
# are proxied through nginx so the browser only needs port 80.
ensure_apt_packages_from_words "${MAINSAIL_APT_DEPS}"
require_commands wget unzip nginx git

# Always replace the static frontend with the selected release zip.
rm -rf "${RATOS_HOME}/mainsail"
as_user wget -q --show-progress -O "${RATOS_HOME}/mainsail.zip" "${MAINSAIL_URL}"
as_user unzip "${RATOS_HOME}/mainsail.zip" -d "${RATOS_HOME}/mainsail"
rm -f "${RATOS_HOME}/mainsail.zip"

clone_or_update "${MAINSAIL_CONFIG_REPO}" "${MAINSAIL_CONFIG_BRANCH}" "${RATOS_HOME}/mainsail-config"
as_user ln -sf "${RATOS_HOME}/mainsail-config/mainsail.cfg" "${RATOS_HOME}/printer_data/config/mainsail.cfg"

# nginx snippets copied from the RatOS/MainsailOS image, adjusted so the web
# root follows RATOS_HOME instead of being hardcoded to /home/pi.
write_file /etc/nginx/conf.d/common_vars.conf 0644 root root <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
EOF

write_file /etc/nginx/conf.d/upstreams.conf 0644 root root <<'EOF'
upstream apiserver {
    ip_hash;
    server 127.0.0.1:7125;
}

upstream mjpgstreamer1 {
    ip_hash;
    server 127.0.0.1:8080;
}

upstream mjpgstreamer2 {
    ip_hash;
    server 127.0.0.1:8081;
}

upstream mjpgstreamer3 {
    ip_hash;
    server 127.0.0.1:8082;
}

upstream mjpgstreamer4 {
    ip_hash;
    server 127.0.0.1:8083;
}

upstream configurator {
    ip_hash;
    server 127.0.0.1:3000;
}
EOF

write_file /etc/nginx/sites-available/mainsail 0644 root root <<EOF
server {
    listen 80 default_server;

    access_log /var/log/nginx/mainsail-access.log;
    error_log /var/log/nginx/mainsail-error.log;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_proxied expired no-cache no-store private auth;
    gzip_comp_level 4;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/x-javascript application/json application/xml;

    root ${RATOS_HOME}/mainsail;
    index index.html;
    server_name _;
    client_max_body_size 0;
    proxy_request_buffering off;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location = /index.html {
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    location /websocket {
        proxy_pass http://apiserver/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://apiserver\$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Scheme \$scheme;
    }

    location /webcam/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer1/;
    }

    location /webcam2/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer2/;
    }

    location /webcam3/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer3/;
    }

    location /webcam4/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer4/;
    }

    location /configure {
        proxy_pass http://configurator\$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Scheme \$scheme;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail

# Surface nginx logs inside Mainsail's normal logs folder.
ln -sf /var/log/nginx/mainsail-access.log "${RATOS_HOME}/printer_data/logs/mainsail-access.log" || true
ln -sf /var/log/nginx/mainsail-error.log "${RATOS_HOME}/printer_data/logs/mainsail-error.log" || true

nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx
