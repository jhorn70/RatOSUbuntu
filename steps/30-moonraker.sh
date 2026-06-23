#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Installing Moonraker"
ensure_user
ensure_dirs

# These are enough to clone Moonraker and let its own install script describe
# the rest of its apt dependencies.
ensure_apt_packages git curl python3-venv python3-dev
require_commands git

clone_or_update "${MOONRAKER_REPO}" "${MOONRAKER_BRANCH}" "${RATOS_HOME}/moonraker"

pushd "${RATOS_HOME}/moonraker" >/dev/null
if [[ -f ./scripts/install-moonraker.sh ]]; then
  tmp_pkg_file="$(mktemp)"

  # Follow CustomPIOS' approach: read Moonraker's upstream PACKAGES assignment
  # instead of hardcoding a stale dependency list in this repo.
  grep '^PACKAGES=' ./scripts/install-moonraker.sh > "${tmp_pkg_file}" || true
  if [[ -s "${tmp_pkg_file}" ]]; then
    # Upstream owns this package list; source only the generated assignment.
    # shellcheck disable=SC1090
    source "${tmp_pkg_file}"
    # shellcheck disable=SC2154
    ensure_apt_packages ${PACKAGES}
  fi
  rm -f "${tmp_pkg_file}"
else
  die "Moonraker install script is missing."
fi

# -z keeps the upstream script non-interactive; -x skips service start during
# install so the rest of the stack can be put in place first.
as_user ./scripts/install-moonraker.sh -z -x
as_user "${RATOS_HOME}/moonraker-env/bin/pip" install -r "${RATOS_HOME}/moonraker/scripts/moonraker-speedups.txt"
./scripts/set-policykit-rules.sh --root
popd >/dev/null

# The RatOS image replaces Moonraker's default config with a tiny file that
# includes RatOS/moonraker.conf from the RatOS configuration repo.
write_file "${RATOS_HOME}/printer_data/config/moonraker.conf" 0644 "${RATOS_USER}" "${RATOS_USER}" <<'EOF'
# Load the RatOS moonraker defaults
[include RatOS/moonraker.conf]

[authorization]
cors_domains:
    http://app.fluidd.xyz
    https://app.fluidd.xyz
    https://my.mainsail.xyz
    http://my.mainsail.xyz
    http://*.local
    http://*.lan
trusted_clients:
    127.0.0.1
    10.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    FE80::/10
    ::1/128
    FD00::/8
EOF

systemctl daemon-reload
systemctl enable moonraker.service
