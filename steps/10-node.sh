#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Installing Node.js 20 and pnpm"
ensure_apt_packages curl ca-certificates gnupg

# RatOS Configurator currently follows the CustomPIOS module and uses the
# NodeSource Node 20 repository rather than Ubuntu's stock nodejs package.
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get update
ensure_apt_packages nodejs

# pnpm is used by RatOS Configurator's setup/build scripts.
npm install -g pnpm
command -v pnpm >/dev/null || die "pnpm was not installed correctly."
