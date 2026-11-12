#!/usr/bin/env bash
# shellcheck disable=SC2034
# ASOS — custom Arch Linux live/install image with Hyprland, zapret (Flowseal strategies),
# Atom game pack, office suite and sysadmin toolbox.

iso_name="asos"
iso_label="ASOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="ASOS <https://github.com/arqa322/asos>"
iso_application="ASOS Live/Install medium (Arch Linux + Hyprland)"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-wheel"]="0:0:440"
  ["/etc/sudoers.d/90-asos-live"]="0:0:440"
  ["/usr/local/bin/asos-zapret"]="0:0:755"
  ["/usr/local/bin/asos-install"]="0:0:755"
  ["/usr/local/bin/asos-welcome"]="0:0:755"
  ["/usr/local/bin/asos-game"]="0:0:755"
  ["/usr/local/bin/asos-user-groups"]="0:0:755"
  ["/usr/local/bin/asos-power"]="0:0:755"
  ["/usr/local/bin/asos-arduino"]="0:0:755"
  ["/usr/local/bin/asos-nanopi"]="0:0:755"
  ["/usr/local/bin/asos-session"]="0:0:755"
  ["/usr/local/bin/asos-doctor"]="0:0:755"
  ["/usr/local/bin/asos-wallpaper"]="0:0:755"
  ["/usr/local/bin/asos-groups"]="0:0:755"
  ["/usr/share/asos/fetch-zapret.sh"]="0:0:755"
  ["/usr/share/asos/embedded/examples/nanopi-hello/deploy.sh"]="0:0:755"
  ["/usr/share/asos/embedded/examples/serial-bridge.py"]="0:0:755"
  ["/usr/share/asos/pkg-select.sh"]="0:0:755"
  ["/opt/zapret/nfqws"]="0:0:755"
)
