#!/usr/bin/env bash
# ============================================================================
#  Update an installed ASOS system to the latest scripts and configs
#  (no reinstall). Run as root, e.g. from a text console (Ctrl+Alt+F2,
#  in VirtualBox: Host key + F2):
#
#    curl -fsSL https://raw.githubusercontent.com/Arqa322/asos/claude/arch-hyprland-custom-image-hl6sdl/scripts/update-installed.sh | sudo bash
#
#  * /usr/local/bin, /usr/share/asos, udev rules, skel, sway safe mode
#  * every user's Hyprland/Waybar config is replaced (old one kept as backup):
#    Hyprland 0.57+ reads only ~/.config/hypr/hyprland.lua
#  * installs sway + foot (safe graphics mode) and VM guest tools
#  * adds the "safe graphics" boot entry, restarts the tty1 session
#  Your zapret settings (/etc/zapret) are not touched.
# ============================================================================
set -euo pipefail
REPO="${ASOS_REPO:-Arqa322/asos}"
REF="${ASOS_REF:-claude/arch-hyprland-custom-image-hl6sdl}"
[[ $EUID -eq 0 ]] || { echo "run as root: ... | sudo bash" >&2; exit 1; }
info() { echo -e "\e[32m::\e[0m $*"; }
warn() { echo -e "\e[33m!!\e[0m $*" >&2; }

SRC=$(mktemp -d /var/tmp/asos-update.XXXXXX)
trap 'rm -rf "$SRC"' EXIT
info "загрузка ASOS ($REPO @ $REF)"
curl -fsSL --retry 4 "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" | tar -xz -C "$SRC" --strip-components=1
A="$SRC/archiso/airootfs"
[[ -d "$A/usr/local/bin" ]] || { echo "download failed" >&2; exit 1; }

info "пакеты: sway, foot, drm-info (безопасный графический режим)"
pkgs=(sway foot drm-info mesa-utils awww starship fastfetch kbd terminus-font)
case "$(systemd-detect-virt --vm 2>/dev/null || true)" in
	oracle) pkgs+=(virtualbox-guest-utils) ;;
	vmware) pkgs+=(open-vm-tools) ;;
	kvm|qemu) pkgs+=(qemu-guest-agent spice-vdagent) ;;
esac
pacman -Sy --needed --noconfirm "${pkgs[@]}" || warn "часть пакетов не установилась: ${pkgs[*]}"
case "$(systemd-detect-virt --vm 2>/dev/null || true)" in
	oracle) systemctl enable --now vboxservice.service 2>/dev/null || true ;;
	vmware) systemctl enable --now vmtoolsd.service 2>/dev/null || true ;;
esac

info "скрипты и общие файлы"
install -m 0755 "$A"/usr/local/bin/* /usr/local/bin/
mkdir -p /usr/share/asos
cp -a "$A/usr/share/asos/." /usr/share/asos/
cp -a "$A/usr/share/applications/." /usr/share/applications/
install -Dm0644 "$A/etc/udev/rules.d/70-asos-embedded.rules" /etc/udev/rules.d/70-asos-embedded.rules
mkdir -p /usr/share/backgrounds
cp -a "$A/usr/share/backgrounds/asos" /usr/share/backgrounds/
install -Dm0644 "$SRC/archiso/packages.x86_64" /usr/share/asos/packages.x86_64
install -Dm0755 "$SRC/scripts/pkg-select.sh" /usr/share/asos/pkg-select.sh
install -Dm0755 "$SRC/scripts/fetch-zapret.sh" /usr/share/asos/fetch-zapret.sh
# console look: Catppuccin palette, Terminus font, login banner, ASOS name
install -Dm0644 "$A/etc/vtrgb" /etc/vtrgb
install -Dm0644 "$A/etc/systemd/system/asos-vtrgb.service" /etc/systemd/system/asos-vtrgb.service
systemctl enable asos-vtrgb.service 2>/dev/null || true
install -Dm0644 "$A/etc/issue" /etc/issue
install -Dm0644 "$A/etc/os-release" /etc/os-release.asos && mv -f /etc/os-release.asos /etc/os-release
sed -i 's/^FONT=.*/FONT=ter-v18n/' /etc/vconsole.conf 2>/dev/null || true
rm -f /etc/skel/.config/hypr/hyprland.conf /etc/skel/.config/hypr/user.conf
cp -a "$A/etc/skel/." /etc/skel/
udevadm control --reload 2>/dev/null || true

stamp=$(date +%Y%m%d-%H%M%S)
while IFS=: read -r user _ uid gid _ home shell; do
	(( uid >= 1000 && uid < 60000 )) || continue
	[[ -d "$home" && "$shell" != */nologin ]] || continue
	info "пользователь $user: обновляю конфиги Hyprland/Waybar (старые — в *.bak-$stamp)"
	for d in .config/hypr .config/waybar .config/kitty .config/fastfetch .config/starship.toml .bashrc; do
		[[ -e "$home/$d" ]] && cp -a "$home/$d" "$home/$d.bak-$stamp"
	done
	mkdir -p "$home/.config/hypr" "$home/.config/waybar" "$home/.config/asos"
	rm -f "$home/.config/hypr/hyprland.conf"
	install -m 0644 "$A/etc/skel/.config/hypr/hyprland.lua" "$A/etc/skel/.config/hypr/hypridle.conf" \
		"$A/etc/skel/.config/hypr/hyprlock.conf" "$home/.config/hypr/"
	[[ -f "$home/.config/hypr/user.lua" ]] || install -m 0644 "$A/etc/skel/.config/hypr/user.lua" "$home/.config/hypr/"
	if [[ -f "$home/.config/hypr/user.conf" ]]; then
		mv "$home/.config/hypr/user.conf" "$home/.config/hypr/user.conf.old"
		warn "  ~/.config/hypr/user.conf (старый формат) переименован в user.conf.old — перенесите свои настройки в user.lua"
	fi
	install -m 0644 "$A/etc/skel/.config/waybar/config.jsonc" "$A/etc/skel/.config/waybar/style.css" "$home/.config/waybar/"
	mkdir -p "$home/.config/kitty" "$home/.config/fastfetch"
	install -m 0644 "$A/etc/skel/.config/kitty/kitty.conf" "$home/.config/kitty/"
	install -m 0644 "$A/etc/skel/.config/fastfetch/config.jsonc" "$A/etc/skel/.config/fastfetch/asos-logo.txt" "$home/.config/fastfetch/"
	install -m 0644 "$A/etc/skel/.config/starship.toml" "$home/.config/starship.toml"
	install -m 0644 "$A/etc/skel/.bashrc" "$home/.bashrc"
	[[ -f "$home/.config/asos/sway.conf" ]] || install -m 0644 "$A/etc/skel/.config/asos/sway.conf" "$home/.config/asos/"
	install -m 0644 "$A/etc/skel/.bash_profile" "$home/.bash_profile"
	rm -f "$home/.local/state/asos/session/last-ok"
	chown -R "$uid:$gid" "$home/.config/hypr" "$home/.config/waybar" "$home/.config/asos" "$home/.config/kitty" \
		"$home/.config/fastfetch" "$home/.config/starship.toml" "$home/.bash_profile" "$home/.bashrc"
done </etc/passwd

if [[ -d /boot/loader/entries && -f /boot/loader/entries/asos.conf ]]; then
	opts=$(sed -n 's/^options[[:space:]]*//p' /boot/loader/entries/asos.conf | sed 's/ asos\.session=[a-z-]*//')
	printf 'title   ASOS (безопасная графика: sway без 3D)\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions %s asos.session=sway-software\n' "$opts" \
		>/boot/loader/entries/asos-safe.conf
	info "добавлен пункт загрузки «безопасная графика»"
fi

info "готово. Через 5 с перезапускаю графический сеанс на tty1 (переключиться: Ctrl+Alt+F1, в VirtualBox — Host+F1)"
sleep 5
info "если графика снова не запустится, на tty1 будет подсказка; диагностика: asos-doctor"
systemctl restart getty@tty1.service || true
