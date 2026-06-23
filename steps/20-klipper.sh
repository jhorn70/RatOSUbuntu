#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Installing Klipper"
ensure_user
ensure_dirs

# Mirrors src/modules/klipper/config, plus the input-shaper packages from the
# is_req_preinstall module. Keeping this here makes 20-klipper runnable alone.
ensure_apt_packages_from_words "${KLIPPER_APT_DEPS}"
require_commands git virtualenv make gcc

clone_or_update "${KLIPPER_REPO}" "${KLIPPER_BRANCH}" "${RATOS_HOME}/klipper"

[[ -f "${RATOS_HOME}/klipper/scripts/klippy-requirements.txt" ]] || die "Klipper requirements file is missing."

# Klipper runs from its own Python virtualenv, just like the RatOS image.
if [[ ! -x "${RATOS_HOME}/klippy-env/bin/python" ]]; then
  as_user virtualenv -p python3 "${RATOS_HOME}/klippy-env"
fi

as_user "${RATOS_HOME}/klippy-env/bin/pip" install -r "${RATOS_HOME}/klipper/scripts/klippy-requirements.txt"

# numpy and matplotlib support input shaper and RatOS' analysis helpers.
as_user "${RATOS_HOME}/klippy-env/bin/pip" install 'numpy<=1.23.4' matplotlib
as_user "${RATOS_HOME}/klippy-env/bin/python" -m compileall "${RATOS_HOME}/klipper/klippy"
as_user "${RATOS_HOME}/klippy-env/bin/python" "${RATOS_HOME}/klipper/klippy/chelper/__init__.py"

# Keep Klipper arguments in printer_data/systemd so users can inspect or adjust
# the command without editing the service unit itself.
write_file "${RATOS_HOME}/printer_data/systemd/klipper.env" 0644 "${RATOS_USER}" "${RATOS_USER}" <<EOF
KLIPPER_ARGS="${RATOS_HOME}/klipper/klippy/klippy.py ${RATOS_HOME}/printer_data/config/printer.cfg -l ${RATOS_HOME}/printer_data/logs/klippy.log -I ${RATOS_HOME}/printer_data/comms/klippy.serial -a ${RATOS_HOME}/printer_data/comms/klippy.sock"
EOF

# This is the RatOS/MainsailOS-style service, but templated for RATOS_USER and
# RATOS_HOME so it can still be customized from config.env.
write_file /etc/systemd/system/klipper.service 0644 root root <<EOF
[Unit]
Description=Klipper 3D Printer Firmware
Documentation=https://www.klipper3d.org/
After=network-online.target
Before=moonraker.service
Wants=udev.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
User=${RATOS_USER}
RemainAfterExit=yes
WorkingDirectory=${RATOS_HOME}/klipper
EnvironmentFile=${RATOS_HOME}/printer_data/systemd/klipper.env
ExecStart=${RATOS_HOME}/klippy-env/bin/python \$KLIPPER_ARGS
Restart=always
RestartSec=10
EOF

systemctl daemon-reload
systemctl enable klipper.service
