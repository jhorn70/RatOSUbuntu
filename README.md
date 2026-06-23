# RatOS on Ubuntu Server

This is a first-pass Ubuntu Server installer derived from the RatOS CustomPIOS modules in `C:\Projects\RatOS`.

It assumes a fresh Ubuntu Server install and intentionally keeps the `pi` user and `/home/pi` layout by default, because the RatOS image, nginx config, Klipper service, and several upstream scripts expect those paths.

## Run

Copy this directory to the Ubuntu machine, then run:

```bash
cd RatOSUbuntu
chmod +x install.sh
sudo ./install.sh
```

You can rerun individual phases:

```bash
sudo ./install.sh 20-klipper
sudo ./install.sh 30-moonraker 40-ratos
```

Each phase installs and checks the apt packages it needs, so rerunning a single step should work as long as earlier filesystem state exists. For example, `60-extras` expects Klipper's virtualenv when linear movement analysis is enabled.

## Configuration

Edit `config.env` before running if you need a different user, branches, or optional components.

Defaults:

- `RATOS_USER=pi`
- RatOS branches: `v2.1.x` / `v2.1.x-deployment`
- Crowsnest, timelapse, and linear movement analysis enabled
- KlipperScreen disabled
- Raspberry Pi MCU disabled

The dependency package groups are also configurable in `config.env`, including `KLIPPER_APT_DEPS`, `RATOS_APT_DEPS`, `MAINSAIL_APT_DEPS`, and the optional component groups.

## Notes

This skips Raspberry Pi image-only work from the CustomPIOS `piconfig` module, such as `/boot/config.txt`, FKMS/KMS changes, serial console boot args, and `raspi-config`.

If you run Ubuntu on a Raspberry Pi and want the Pi itself to act as a Klipper MCU, set:

```bash
INSTALL_RPI_MCU=1
```

in `config.env` before running `60-extras`.
