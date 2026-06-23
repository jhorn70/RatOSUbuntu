#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '\n\033[1;32m==> %s\033[0m\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARN: %s\033[0m\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this script with sudo/root."
}

as_user() {
  # Most upstream installers assume they run as the printer user, not as root.
  # Prefer sudo, but keep runuser as a fallback for very small server images.
  if command -v sudo >/dev/null 2>&1; then
    sudo -H -u "${RATOS_USER}" "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "${RATOS_USER}" -- "$@"
  else
    die "Neither sudo nor runuser is available to execute commands as ${RATOS_USER}."
  fi
}

as_user_env() {
  # Same as as_user, but allows passing environment assignments such as
  # NETWORK=skipnetworkmanagerinstall to upstream scripts.
  if command -v sudo >/dev/null 2>&1; then
    sudo -H -u "${RATOS_USER}" env "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "${RATOS_USER}" -- env "$@"
  else
    die "Neither sudo nor runuser is available to execute commands as ${RATOS_USER}."
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_update_once() {
  # Individual stages may request packages independently. Avoid repeating
  # apt-get update several times during one harness run.
  if [[ "${RATOS_APT_UPDATED:-0}" != "1" ]]; then
    apt-get update
    RATOS_APT_UPDATED=1
  fi
}

missing_packages() {
  # Print only packages not already installed, so rerunning a stage stays fast
  # and does not hide the interesting output in apt noise.
  local pkg
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"; then
      printf '%s\n' "${pkg}"
    fi
  done
}

ensure_apt_packages() {
  local missing
  mapfile -t missing < <(missing_packages "$@")
  if [[ "${#missing[@]}" -gt 0 ]]; then
    log "Installing apt dependencies: ${missing[*]}"
    apt_update_once
    apt_install "${missing[@]}"
  fi
}

ensure_apt_packages_from_words() {
  # config.env stores package groups as shell words so users can override them
  # without editing the installer logic.
  # shellcheck disable=SC2206
  local packages=($1)
  if [[ "${#packages[@]}" -gt 0 ]]; then
    ensure_apt_packages "${packages[@]}"
  fi
}

require_commands() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

require_ubuntu_like() {
  # This is a soft platform check. The scripts are written for Ubuntu Server,
  # but Debian-like systems may work well enough for experimentation.
  [[ -r /etc/os-release ]] || die "/etc/os-release not found; this installer expects Ubuntu Server."
  # shellcheck disable=SC1091
  source /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" ubuntu "*|*" debian "*) ;;
    *) warn "This does not look like Ubuntu/Debian (${PRETTY_NAME:-unknown}); continuing anyway." ;;
  esac
}

clone_or_update() {
  local repo="$1"
  local branch="$2"
  local dest="$3"

  # Keep clones idempotent. If a step fails halfway through, rerunning should
  # update the existing checkout instead of failing because the directory exists.
  if [[ -d "${dest}/.git" ]]; then
    log "Updating ${dest}"
    as_user git -C "${dest}" fetch --all --prune
    as_user git -C "${dest}" checkout "${branch}"
    as_user git -C "${dest}" pull --ff-only
  else
    log "Cloning ${repo} -> ${dest}"
    as_user git clone --branch "${branch}" "${repo}" "${dest}"
  fi
}

ensure_user() {
  # RatOS image scripts and several copied config files expect a pi user and
  # /home/pi by default. The names are configurable, but pi is the least
  # surprising path through the existing ecosystem.
  if ! id "${RATOS_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${RATOS_USER}"
  fi
  if [[ -n "${RATOS_PASSWORD:-}" ]]; then
    printf '%s:%s\n' "${RATOS_USER}" "${RATOS_PASSWORD}" | chpasswd
  fi
  usermod -aG sudo,tty,dialout,input,plugdev,netdev,systemd-journal "${RATOS_USER}"
  install -d -m 0755 -o "${RATOS_USER}" -g "${RATOS_USER}" "${RATOS_HOME}"
}

ensure_dirs() {
  # Moonraker, Klipper, Mainsail, and RatOS all meet under printer_data.
  # Creating it early makes individual stages safe to run on their own.
  install -d -m 0755 -o "${RATOS_USER}" -g "${RATOS_USER}" \
    "${RATOS_HOME}/printer_data" \
    "${RATOS_HOME}/printer_data/config" \
    "${RATOS_HOME}/printer_data/comms" \
    "${RATOS_HOME}/printer_data/logs" \
    "${RATOS_HOME}/printer_data/systemd"
}

write_file() {
  # Write through a temp file, then install with the desired owner/mode. This
  # avoids leaving root-owned files in /home/pi or half-written service files.
  local path="$1"
  local mode="$2"
  local owner="$3"
  local group="$4"
  local tmp
  tmp="$(mktemp)"
  cat > "${tmp}"
  install -m "${mode}" -o "${owner}" -g "${group}" "${tmp}" "${path}"
  rm -f "${tmp}"
}
