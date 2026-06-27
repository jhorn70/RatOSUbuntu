#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config.env"
source "${ROOT_DIR}/lib/common.sh"
require_root

ensure_user
ensure_dirs

if [[ "${INSTALL_CROWSNEST}" == "1" ]]; then
  log "Installing Crowsnest"
  ensure_apt_packages git make
  clone_or_update "${CROWSNEST_REPO}" "${CROWSNEST_BRANCH}" "${RATOS_HOME}/crowsnest"
  if [[ -f "${RATOS_HOME}/crowsnest/tools/libs/pkglist-generic.sh" ]]; then
    tmp_pkg_file="$(mktemp)"

    # On Ubuntu, use Crowsnest's generic dependency list. The Raspberry Pi list
    # is intentionally avoided because it pulls in Pi-specific camera pieces.
    grep '^PKGLIST=' "${RATOS_HOME}/crowsnest/tools/libs/pkglist-generic.sh" > "${tmp_pkg_file}" || true
    if [[ -s "${tmp_pkg_file}" ]]; then
      # Upstream owns this package list; source only the generated assignment.
      # shellcheck disable=SC1090
      source "${tmp_pkg_file}"
      # shellcheck disable=SC2154
      ensure_apt_packages ${PKGLIST}
    fi
    rm -f "${tmp_pkg_file}"
  else
    warn "Crowsnest generic package list not found; relying on make install."
  fi
  BASE_USER="${RATOS_USER}" CROWSNEST_UNATTENDED=1 make -C "${RATOS_HOME}/crowsnest" install
  systemctl enable crowsnest.service
fi

if [[ "${INSTALL_TIMELAPSE}" == "1" ]]; then
  log "Installing moonraker-timelapse"
  ensure_apt_packages_from_words "${TIMELAPSE_APT_DEPS}"
  clone_or_update "${TIMELAPSE_REPO}" "${TIMELAPSE_BRANCH}" "${RATOS_HOME}/moonraker-timelapse"

  # RatOS links the Klipper macro into printer_data/config rather than copying
  # it, so updates to moonraker-timelapse can update the macro file in place.
  as_user ln -sf "${RATOS_HOME}/moonraker-timelapse/klipper_macro/timelapse.cfg" "${RATOS_HOME}/printer_data/config/timelapse.cfg"
  if command -v ratos >/dev/null && [[ -d "${RATOS_HOME}/moonraker/moonraker/components" ]]; then
    as_user ratos extensions register moonraker "timelapse" "${RATOS_HOME}/moonraker-timelapse/component/timelapse.py" || true
  fi
fi

if [[ "${INSTALL_LINEAR_MOVEMENT_ANALYSIS}" == "1" ]]; then
  log "Installing Klipper linear movement analysis"

  # This helper runs inside Klipper's Python environment, so fail clearly if
  # someone runs 60-extras before 20-klipper.
  [[ -x "${RATOS_HOME}/klippy-env/bin/pip" ]] || die "Klipper venv not found. Run 20-klipper before 60-extras."
  clone_or_update "${LINEAR_MOVEMENT_ANALYSIS_REPO}" "${LINEAR_MOVEMENT_ANALYSIS_BRANCH}" "${RATOS_HOME}/klipper_linear_movement_analysis"
  as_user "${RATOS_HOME}/klippy-env/bin/pip" install matplotlib
  if command -v ratos >/dev/null; then
    as_user ratos extensions register klipper "linear_movement_analysis" "${RATOS_HOME}/klipper_linear_movement_analysis/linear_movement_vibrations.py" || true
  fi
fi

if [[ "${INSTALL_KLIPPERSCREEN}" == "1" ]]; then
  log "Installing KlipperScreen"
  ensure_apt_packages_from_words "${KLIPPERSCREEN_APT_DEPS}"

  # KlipperScreen is optional because headless Ubuntu Server installs usually
  # do not have a directly attached display.
  if [[ -f /etc/X11/Xwrapper.config ]]; then
    grep -q '^needs_root_rights=yes' /etc/X11/Xwrapper.config || echo 'needs_root_rights=yes' >> /etc/X11/Xwrapper.config
  fi
  clone_or_update "${KLIPPERSCREEN_REPO}" "${KLIPPERSCREEN_BRANCH}" "${RATOS_HOME}/KlipperScreen"
  pushd "${RATOS_HOME}/KlipperScreen" >/dev/null
  as_user_env NETWORK="skipnetworkmanagerinstall" ./scripts/KlipperScreen-install.sh
  popd >/dev/null
  systemctl stop KlipperScreen || true
fi

if [[ "${INSTALL_RPI_MCU}" == "1" ]]; then
  log "Installing Raspberry Pi MCU service"
  ensure_apt_packages_from_words "${RPI_MCU_APT_DEPS}"

  # Only enable this when Ubuntu is running on a Raspberry Pi and the Pi itself
  # should expose a Klipper MCU. It is not useful on a normal x86 server.
  [[ -d "${RATOS_HOME}/klipper" ]] || die "Klipper source not found. Run 20-klipper before enabling RPI MCU."
  [[ -f "${RATOS_HOME}/printer_data/config/RatOS/boards/rpi/firmware.config" ]] || die "RatOS Raspberry Pi firmware.config not found."
  cp -f "${RATOS_HOME}/printer_data/config/RatOS/boards/rpi/firmware.config" "${RATOS_HOME}/klipper/.config"
  make -C "${RATOS_HOME}/klipper" olddefconfig
  make -C "${RATOS_HOME}/klipper" clean
  chown -R "${RATOS_USER}:${RATOS_USER}" "${RATOS_HOME}/klipper"
  make -C "${RATOS_HOME}/klipper" flash
  cp "${RATOS_HOME}/klipper/scripts/klipper-mcu.service" /etc/systemd/system/klipper_mcu.service
  systemctl enable klipper_mcu.service
fi

if [[ "${INSTALL_LATTEPANDA_IOTA_RP2040_MCU}" == "1" ]]; then
  log "Building and flashing LattePanda IOTA RP2040 Klipper firmware"
  ensure_apt_packages_from_words "${LATTEPANDA_IOTA_RP2040_APT_DEPS}"

  [[ -d "${RATOS_HOME}/klipper" ]] || die "Klipper source not found. Run 20-klipper before enabling LattePanda IOTA RP2040 MCU."

  # The LattePanda IOTA exposes an onboard RP2040. Build a generic RP2040 USB
  # Klipper image and let Klipper's flash helper handle the bootloader device.
  write_file "${RATOS_HOME}/klipper/.config" 0644 "${RATOS_USER}" "${RATOS_USER}" <<'EOF'
CONFIG_LOW_LEVEL_OPTIONS=y
CONFIG_MACH_RPXXXX=y
CONFIG_MACH_RP2040=y
CONFIG_RPXXXX_FLASH_START_0100=y
CONFIG_RP2040_FLASH_GENERIC_03=y
CONFIG_RPXXXX_USB=y
CONFIG_USB_VENDOR_ID=0x1d50
CONFIG_USB_DEVICE_ID=0x614e
CONFIG_USB_SERIAL_NUMBER_CHIPID=y
EOF

  make -C "${RATOS_HOME}/klipper" olddefconfig
  grep -q '^CONFIG_MACH_RP2040=y' "${RATOS_HOME}/klipper/.config" || die "Klipper did not accept the RP2040 firmware configuration."
  grep -q '^CONFIG_RPXXXX_USB=y' "${RATOS_HOME}/klipper/.config" || die "Klipper did not accept the RP2040 USB firmware configuration."
  make -C "${RATOS_HOME}/klipper" clean
  chown -R "${RATOS_USER}:${RATOS_USER}" "${RATOS_HOME}/klipper"
  make -C "${RATOS_HOME}/klipper"

  [[ -f "${RATOS_HOME}/klipper/out/klipper.uf2" ]] || die "RP2040 Klipper firmware was not built."

  log "Flashing RP2040 with FLASH_DEVICE=${LATTEPANDA_IOTA_RP2040_FLASH_DEVICE}"
  make -C "${RATOS_HOME}/klipper" flash FLASH_DEVICE="${LATTEPANDA_IOTA_RP2040_FLASH_DEVICE}"
fi
