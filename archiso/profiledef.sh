#!/usr/bin/env bash
# shellcheck disable=SC2034
# Huilo — custom Arch Linux live/install image with Hyprland, zapret (Flowseal strategies),
# Atom game pack, office suite and sysadmin toolbox.

iso_name="huilo"
iso_label="HUILO_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Huilo <https://github.com/arqa322/huilo>"
iso_application="Huilo Live/Install medium (Arch Linux + Hyprland)"
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
  ["/etc/sudoers.d/90-huilo-live"]="0:0:440"
  ["/usr/local/bin/huilo-zapret"]="0:0:755"
  ["/usr/local/bin/huilo-install"]="0:0:755"
  ["/usr/local/bin/huilo-welcome"]="0:0:755"
  ["/usr/local/bin/huilo-game"]="0:0:755"
  ["/usr/local/bin/huilo-user-groups"]="0:0:755"
  ["/usr/local/bin/huilo-power"]="0:0:755"
  ["/usr/local/bin/huilo-arduino"]="0:0:755"
  ["/usr/local/bin/huilo-nanopi"]="0:0:755"
  ["/usr/local/bin/huilo-session"]="0:0:755"
  ["/usr/local/bin/huilo-doctor"]="0:0:755"
  ["/usr/local/bin/huilo-wallpaper"]="0:0:755"
  ["/usr/local/bin/huilo-groups"]="0:0:755"
  ["/usr/local/bin/huilo-logs"]="0:0:755"
  ["/usr/local/bin/huilo-logwatch"]="0:0:755"
  ["/usr/local/bin/huilo-eq"]="0:0:755"
  ["/usr/share/huilo/fetch-zapret.sh"]="0:0:755"
  ["/usr/share/huilo/embedded/examples/nanopi-hello/deploy.sh"]="0:0:755"
  ["/usr/share/huilo/embedded/examples/serial-bridge.py"]="0:0:755"
  ["/usr/share/huilo/pkg-select.sh"]="0:0:755"
  ["/opt/zapret/nfqws"]="0:0:755"
)
