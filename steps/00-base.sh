#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Preparing Ubuntu base system"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y

# Install only the common base tools here. Application-specific dependencies
# live in their own steps so those steps can be rerun independently.
ensure_apt_packages_from_words "${BASE_APT_DEPS}"

ensure_user
ensure_dirs

# Match the CustomPIOS image's assumption that the printer user can run setup
# commands without an interactive sudo password prompt.
echo "${RATOS_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/010_${RATOS_USER}-nopasswd"
chmod 0440 "/etc/sudoers.d/010_${RATOS_USER}-nopasswd"

# Avahi gives the machine a .local name, similar to ratos.local on the image.
systemctl enable avahi-daemon
