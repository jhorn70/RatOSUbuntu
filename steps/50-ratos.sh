#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

log "Installing RatOS configuration, theme, and configurator"
ensure_user
ensure_dirs

# RatOS itself only adds a couple of apt packages in the CustomPIOS module.
# Node/pnpm comes from 10-node because the configurator owns most JS setup.
ensure_apt_packages_from_words "${RATOS_APT_DEPS}"
require_commands git npm curl

# These three repos are the core RatOS layer: printer config, Mainsail theme,
# and the web configurator.
if [[ -L "${RATOS_HOME}/printer_data/config/RatOS" && -d "${RATOS_HOME}/ratos-configurator/configuration" ]]; then
  log "Using configurator-managed RatOS configuration symlink"
else
  clone_or_update "${RATOS_CONFIG_REPO}" "${RATOS_CONFIG_BRANCH}" "${RATOS_HOME}/printer_data/config/RatOS"
fi
clone_or_update "${RATOS_THEME_REPO}" "${RATOS_THEME_BRANCH}" "${RATOS_HOME}/printer_data/config/.theme"
clone_or_update "${RATOS_CONFIGURATOR_REPO}" "${RATOS_CONFIGURATOR_BRANCH}" "${RATOS_HOME}/ratos-configurator"

pushd "${RATOS_HOME}" >/dev/null
as_user git config --global pull.ff only
popd >/dev/null
echo "RatOS Ubuntu" > /etc/ratos-release

rm -f /tmp/*ratos-configurator*
touch /usr/local/bin/ratos
pushd "${RATOS_HOME}/ratos-configurator/app" >/dev/null
as_user bash ./scripts/setup.sh
popd >/dev/null

# Some RatOS extension registration expects the configurator API to be alive.
# Start it only for the install phase, then stop it again afterward.
log "Starting RatOS Configurator temporarily for extension registration"
pushd "${RATOS_HOME}/ratos-configurator/app" >/dev/null
as_user npm run start &
CONFIGURATOR_PID="$!"
popd >/dev/null

for _ in $(seq 1 60); do
  http_code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ || true)"
  if [[ "${http_code}" != "000" ]]; then
    break
  fi
  sleep 5
done

ln -sfn ../templates "${RATOS_HOME}/printer_data/config/RatOS/scripts/templates"
ln -sfn ../boards "${RATOS_HOME}/printer_data/config/RatOS/scripts/boards"

if [[ "${INSTALL_TIMELAPSE}" == "1" ]]; then
  log "Preparing moonraker-timelapse for RatOS registration"
  ensure_apt_packages_from_words "${TIMELAPSE_APT_DEPS}"
  clone_or_update "${TIMELAPSE_REPO}" "${TIMELAPSE_BRANCH}" "${RATOS_HOME}/moonraker-timelapse"
  as_user ln -sf "${RATOS_HOME}/moonraker-timelapse/klipper_macro/timelapse.cfg" "${RATOS_HOME}/printer_data/config/timelapse.cfg"
fi

if [[ "${INSTALL_LINEAR_MOVEMENT_ANALYSIS}" == "1" ]]; then
  log "Preparing Klipper linear movement analysis for RatOS registration"

  # RatOS post-install verifies expected extension registrations, so this
  # extension must exist before ratos-post-install.sh runs.
  [[ -x "${RATOS_HOME}/klippy-env/bin/pip" ]] || die "Klipper venv not found. Run 20-klipper before 50-ratos when linear movement analysis is enabled."
  clone_or_update "${LINEAR_MOVEMENT_ANALYSIS_REPO}" "${LINEAR_MOVEMENT_ANALYSIS_BRANCH}" "${RATOS_HOME}/klipper_linear_movement_analysis"
  as_user "${RATOS_HOME}/klippy-env/bin/pip" install matplotlib
fi

# ratos-install.sh and ratos-post-install.sh are intentionally left in the
# RatOS-configuration repo; that keeps this Ubuntu installer from duplicating
# RatOS' internal installation logic.
as_user "${RATOS_HOME}/printer_data/config/RatOS/scripts/ratos-install.sh"
as_user "${RATOS_HOME}/printer_data/config/RatOS/scripts/ratos-post-install.sh"

curl -fsS 'http://127.0.0.1:3000/configure/api/trpc/kill' >/dev/null 2>&1 || true
sleep 2
if kill -0 "${CONFIGURATOR_PID}" >/dev/null 2>&1; then
  kill "${CONFIGURATOR_PID}" >/dev/null 2>&1 || true
fi
