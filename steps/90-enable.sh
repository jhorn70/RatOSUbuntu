#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Enabling services"
systemctl daemon-reload

# Start/enable only the services that form the default web printer stack.
# Optional services are enabled by their own install blocks if present.
systemctl enable klipper.service moonraker.service nginx avahi-daemon

if systemctl list-unit-files | grep -q '^crowsnest.service'; then
  systemctl enable crowsnest.service
fi

log "Installer complete. Reboot, then open http://$(hostname -I | awk '{print $1}')/ or http://$(hostname).local/"
