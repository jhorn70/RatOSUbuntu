# RatOS on Ubuntu Server

This repository installs a RatOS-style Klipper host stack on a fresh Ubuntu
Server machine. It is derived from the RatOS CustomPIOS modules, but runs as a
normal root installer instead of building a Raspberry Pi image.

The installer has been tested on Ubuntu Server VMs. For real hardware, use a
fresh or disposable Ubuntu Server install first; the scripts make system-level
changes under `/etc`, `/home`, `/usr/local/bin`, nginx, systemd, and apt.

By default it keeps the RatOS image convention of a `pi` user and `/home/pi`
layout, because RatOS, Mainsail, Klipper service files, and several upstream
scripts expect those paths.

## What It Installs

- Klipper
- Moonraker
- Mainsail served by nginx
- RatOS configuration, theme, and configurator
- Node.js 18 and pnpm for RatOS Configurator
- Optional Crowsnest, moonraker-timelapse, linear movement analysis,
  KlipperScreen, and Raspberry Pi MCU support

## Before You Start

Use a fresh Ubuntu Server machine with:

- working network access
- sudo/root access
- enough disk space for apt packages, source checkouts, and build artifacts
- SSH access, unless you are working directly at the console

This installer downloads packages and upstream repositories from the internet.
It also runs `apt-get full-upgrade -y` during the base step, so expect package
updates and a reboot afterward.

## Install On A Machine

Copy this directory to the target Ubuntu machine:

```bash
scp -r RatOSUbuntu user@machine:/tmp/RatOSUbuntu
```

Then SSH into the machine and review the config:

```bash
ssh user@machine
cd /tmp/RatOSUbuntu
nano config.env
```

Run the full installer:

```bash
chmod +x install.sh
sudo ./install.sh
```

When the installer finishes, reboot:

```bash
sudo reboot
```

After reboot, open Mainsail from another machine on the same network:

```text
http://<machine-ip>/
http://<hostname>.local/
```

The installer prints the detected URLs at the end of the `90-enable` step.

## Configuration

Edit `config.env` before running if you need a different user, password,
branches, package groups, or optional components.

Important defaults:

- `RATOS_USER=pi`
- `RATOS_PASSWORD=raspberry`
- `RATOS_HOME=/home/pi`
- RatOS configuration/theme branch: `v2.1.x`
- RatOS Configurator branch: `v2.1.x-deployment`
- Crowsnest enabled
- moonraker-timelapse enabled
- linear movement analysis enabled
- KlipperScreen disabled
- Raspberry Pi MCU disabled

Optional component flags:

```bash
INSTALL_CROWSNEST=1
INSTALL_TIMELAPSE=1
INSTALL_LINEAR_MOVEMENT_ANALYSIS=1
INSTALL_KLIPPERSCREEN=0
INSTALL_RPI_MCU=0
```

Leave `INSTALL_RPI_MCU=0` unless Ubuntu is running on a Raspberry Pi and you
specifically want the Pi itself to act as a Klipper MCU.

The dependency package groups are also configurable in `config.env`, including
`BASE_APT_DEPS`, `KLIPPER_APT_DEPS`, `RATOS_APT_DEPS`, `MAINSAIL_APT_DEPS`, and
the optional component package groups.

## Rerun Individual Steps

The installer is split into phases. Running with no arguments executes the full
flow:

```bash
sudo ./install.sh
```

You can rerun one or more phases while debugging:

```bash
sudo ./install.sh 20-klipper
sudo ./install.sh 30-moonraker 40-ratos
```

Available steps:

```text
00-base
10-node
20-klipper
30-moonraker
40-ratos
50-mainsail
60-extras
90-enable
```

Each phase installs and checks the apt packages it needs, so rerunning a single
step should work as long as earlier filesystem state exists. For example,
`60-extras` expects Klipper's virtualenv when linear movement analysis is
enabled, so run `20-klipper` before `60-extras`.

## Post-Install

After the machine reboots:

1. Open Mainsail.
2. Use the RatOS configurator to set up the printer.
3. Connect and flash the printer MCU as you normally would for Klipper/RatOS.
4. Check service status if something does not come up cleanly:

```bash
sudo systemctl status klipper
sudo systemctl status moonraker
sudo systemctl status nginx
sudo systemctl status crowsnest
```

Useful logs live under:

```text
/home/pi/printer_data/logs/
/var/log/nginx/
```

Adjust the paths if you changed `RATOS_USER` or `RATOS_HOME`.

## Notes And Caveats

This skips Raspberry Pi image-only work from the CustomPIOS `piconfig` module,
such as `/boot/config.txt`, FKMS/KMS changes, serial console boot args, and
`raspi-config`.

The installer replaces nginx's default site with a Mainsail site and grants the
configured RatOS user passwordless sudo, matching the expectations of the RatOS
image ecosystem.

If you enable Raspberry Pi MCU support, set this in `config.env` before running
`60-extras`:

```bash
INSTALL_RPI_MCU=1
```

Only enable that on Raspberry Pi hardware.
