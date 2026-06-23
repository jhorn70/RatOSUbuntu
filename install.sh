#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The harness intentionally keeps each install phase in its own script. That
# makes the first install simple, but also lets you rerun only the phase you are
# debugging on a live Ubuntu box.
usage() {
  cat <<EOF
Usage: sudo ./install.sh [step ...]

Run with no step names to execute the full RatOS Ubuntu install flow.

Available steps:
  00-base
  10-node
  20-klipper
  30-moonraker
  40-ratos
  50-mainsail
  60-extras
  90-enable

Examples:
  sudo ./install.sh
  sudo ./install.sh 20-klipper 30-moonraker
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "This installer needs root privileges. Run: sudo ./install.sh" >&2
  exit 1
fi

source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"

# Only check for tools that should exist on a minimal Ubuntu Server install.
# Later steps install their own app-specific dependencies before using them.
require_ubuntu_like
require_commands apt-get dpkg-query systemctl

DEFAULT_STEPS=(
  00-base
  10-node
  20-klipper
  30-moonraker
  40-ratos
  50-mainsail
  60-extras
  90-enable
)

if [[ "$#" -gt 0 ]]; then
  STEPS=("$@")
else
  STEPS=("${DEFAULT_STEPS[@]}")
fi

for step in "${STEPS[@]}"; do
  script="${ROOT_DIR}/steps/${step}.sh"
  if [[ ! -f "${script}" ]]; then
    echo "Unknown step: ${step}" >&2
    usage >&2
    exit 1
  fi
  log "Running ${step}"
  bash "${script}"
done

log "RatOS Ubuntu install flow finished."
