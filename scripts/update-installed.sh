#!/usr/bin/env bash
# ============================================================================
#  Update an installed Huilo (or older ASOS) system to the latest scripts and
#  configs — no reinstall. Run as root, e.g. from a text console
#  (Ctrl+Alt+F2, in VirtualBox: Host key + F2):
#
#    curl -fsSL https://raw.githubusercontent.com/Arqa322/Huilo/claude/arch-hyprland-custom-image-hl6sdl/scripts/update-installed.sh | sudo bash
#
#  * migrates ASOS -> Huilo: commands, services, zapret config (values kept),
#    boot entries, per-user state
#  * scripts, wallpapers, safe graphics mode, Plymouth boot splash, equalizer
#    (EasyEffects), log tools, console look, the Huilo Dusk theme (rofi menus,
#    swaync notifications, swayosd), the AI assistant (ии), legacy names
#  * every user's desktop configs are replaced file by file; a changed file is
#    kept as <file>.bak-<date>; personal files (user.lua, kitty/user.conf,
#    huilo/sway.conf, ai.conf) are never touched
#  * restarts the tty1 session at the end
# ============================================================================
set -euo pipefail
REF="${HUILO_REF:-claude/arch-hyprland-custom-image-hl6sdl}"
[[ $EUID -eq 0 ]] || { echo "run as root: ... | sudo bash" >&2; exit 1; }
info() { echo -e "\e[32m::\e[0m $*"; }
warn() { echo -e "\e[33m!!\e[0m $*" >&2; }

SRC=$(mktemp -d /var/tmp/huilo-update.XXXXXX)
trap 'rm -rf "$SRC"' EXIT
# the repository was renamed asos -> Huilo; GitHub redirects the old name
got=0
for repo in ${HUILO_REPO:-Arqa322/Huilo Arqa322/asos}; do
	info "загрузка ($repo @ $REF)"
	if curl -fsSL --retry 3 "https://codeload.github.com/$repo/tar.gz/refs/heads/$REF" | tar -xz -C "$SRC" --strip-components=1 2>/dev/null; then
		got=1; break
	fi
done
A="$SRC/archiso/airootfs"
[[ $got == 1 && -d "$A/usr/local/bin" ]] || { echo "download failed" >&2; exit 1; }

# ------------------------------------------------------------- packages ---
info "пакеты: безопасный режим, оформление, экран загрузки, эквалайзер, помощник"
pkgs=(sway foot drm-info mesa-utils awww starship fastfetch kbd terminus-font jq
	plymouth easyeffects lsp-plugins-lv2 calf pipewire-audio
	rofi rofi-emoji rofi-calc wtype swaync swayosd hyprsunset adw-gtk-theme capitaine-cursors
	papirus-icon-theme inter-font dconf gum qt6ct)
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

# -------------------------------------------------- ASOS -> Huilo (once) ---
if compgen -G "/usr/local/bin/asos-*" >/dev/null || [[ -d /usr/share/asos ]]; then
	info "переход ASOS → Huilo"
	systemctl disable asos-vtrgb.service 2>/dev/null || true
	rm -f /usr/local/bin/asos-* /etc/systemd/system/asos-*.service /etc/systemd/system/*.wants/asos-*.service \
		/etc/udev/rules.d/70-asos-embedded.rules /etc/sysctl.d/80-asos.conf /etc/modules-load.d/asos.conf \
		/usr/share/applications/asos-*.desktop
	rm -rf /usr/share/asos /usr/share/backgrounds/asos
	if [[ -f /etc/zapret/asos.conf && ! -f /etc/zapret/huilo.conf ]]; then
		mv /etc/zapret/asos.conf /etc/zapret/huilo.conf
	fi
	rm -f /etc/zapret/asos.conf
	if [[ -d /boot/loader/entries ]]; then
		for e in /boot/loader/entries/asos*.conf; do
			[[ -f "$e" ]] || continue
			sed -i -e 's/asos\.session=/huilo.session=/g' -e 's/asos\.nogui/huilo.nogui/g' -e 's/ASOS/Huilo/g' "$e"
			mv "$e" "/boot/loader/entries/$(basename "$e" | sed 's/^asos/huilo/')"
		done
		sed -i 's/^default asos/default huilo/' /boot/loader/loader.conf 2>/dev/null || true
	fi
	[[ -f /etc/default/grub ]] && sed -i 's/GRUB_DISTRIBUTOR="ASOS"/GRUB_DISTRIBUTOR="Huilo"/' /etc/default/grub
fi

# ---------------------------------------------------------- system files ---
info "скрипты и общие файлы"
for f in "$A"/usr/local/bin/*; do   # old names are symlinks to huilo-legacy
	if [[ -L "$f" ]]; then rm -f "/usr/local/bin/$(basename "$f")"; cp -a "$f" /usr/local/bin/
	else install -m 0755 "$f" /usr/local/bin/; fi
done
rm -rf /usr/local/lib/huilo/legacy && mkdir -p /usr/local/lib/huilo && cp -a "$A/usr/local/lib/huilo/legacy" /usr/local/lib/huilo/
install -Dm0644 -t /etc/profile.d "$A"/etc/profile.d/huilo-*.sh
mkdir -p /usr/share/rofi/themes /usr/share/qt6ct/colors
install -m 0644 "$A"/usr/share/rofi/themes/huilo*.rasi /usr/share/rofi/themes/
install -m 0644 "$A"/usr/share/qt6ct/colors/huilo.conf /usr/share/qt6ct/colors/
mkdir -p /usr/share/huilo /usr/share/backgrounds /usr/share/plymouth/themes
cp -a "$A/usr/share/huilo/." /usr/share/huilo/
cp -a "$A/usr/share/applications/." /usr/share/applications/
cp -a "$A/usr/share/backgrounds/huilo" /usr/share/backgrounds/
cp -a "$A/usr/share/plymouth/themes/huilo" /usr/share/plymouth/themes/
install -Dm0644 "$SRC/archiso/packages.x86_64" /usr/share/huilo/packages.x86_64
install -Dm0755 "$SRC/scripts/pkg-select.sh" /usr/share/huilo/pkg-select.sh
install -Dm0755 "$SRC/scripts/fetch-zapret.sh" /usr/share/huilo/fetch-zapret.sh
install -Dm0644 "$A/etc/udev/rules.d/70-huilo-embedded.rules" /etc/udev/rules.d/70-huilo-embedded.rules
install -Dm0644 "$A/etc/sysctl.d/80-huilo.conf" /etc/sysctl.d/80-huilo.conf
install -Dm0644 "$A/etc/modules-load.d/huilo.conf" /etc/modules-load.d/huilo.conf
install -Dm0644 "$A/etc/vtrgb" /etc/vtrgb
install -Dm0644 "$A/etc/systemd/system/huilo-vtrgb.service" /etc/systemd/system/huilo-vtrgb.service
install -Dm0644 "$A/etc/issue" /etc/issue
install -Dm0644 "$A/etc/os-release" /etc/os-release.huilo && mv -f /etc/os-release.huilo /etc/os-release
sed -i 's/^FONT=.*/FONT=ter-v18n/' /etc/vconsole.conf 2>/dev/null || true
# zapret: new service (paths changed); settings in /etc/zapret are kept
install -Dm0644 "$A/etc/systemd/system/zapret.service" /etc/systemd/system/zapret.service
[[ -f /etc/zapret/huilo.conf ]] || install -Dm0644 "$A/etc/zapret/huilo.conf" /etc/zapret/huilo.conf
rm -f /etc/skel/.config/hypr/hyprland.conf /etc/skel/.config/hypr/user.conf
cp -a "$A/etc/skel/." /etc/skel/
systemctl daemon-reload
systemctl enable huilo-vtrgb.service 2>/dev/null || true
systemctl is-enabled --quiet zapret.service 2>/dev/null && systemctl restart zapret.service || true
udevadm control --reload 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true

# ------------------------------------------------- Plymouth boot splash ---
info "экран загрузки (Plymouth, тема huilo)"
install -Dm0644 "$A/etc/plymouth/plymouthd.conf" /etc/plymouth/plymouthd.conf
if [[ -f /etc/mkinitcpio.conf ]]; then
	sed -i -E '/^HOOKS=/{/plymouth/!s/\bkms\b/kms plymouth/}' /etc/mkinitcpio.conf
	grep -q '^HOOKS=.*plymouth' /etc/mkinitcpio.conf || sed -i -E '/^HOOKS=/s/\b(systemd|udev)\b/\1 plymouth/' /etc/mkinitcpio.conf
	mkinitcpio -P >/dev/null 2>&1 && info "initramfs пересобран" || warn "mkinitcpio завершился с ошибкой — проверьте: sudo mkinitcpio -P"
fi
for e in /boot/loader/entries/huilo*.conf; do   # the splash needs "splash" on the kernel command line
	[[ -f "$e" ]] && ! grep -q 'huilo.nogui\|nomodeset' "$e" && grep -q '^options' "$e" && ! grep -q '\bsplash\b' "$e" \
		&& sed -i 's/^options .*/& splash/' "$e"
done

# ------------------------------------------------------------- users ---
stamp=$(date +%Y%m%d-%H%M%S)
# what Huilo owns in a home directory (keep in sync with etc/skel, see docs/MAINTAINING.md)
MANAGED=(
	.config/hypr/hyprland.lua .config/hypr/theme.lua .config/hypr/hypridle.conf .config/hypr/hyprlock.conf
	.config/waybar/config.jsonc .config/waybar/style.css
	.config/rofi/config.rasi .config/swaync/config.json .config/swaync/style.css
	.config/swayosd/style.css .config/swayosd/config.toml
	.config/kitty/kitty.conf .config/kitty/colors.conf
	.config/gtk-3.0/settings.ini .config/gtk-3.0/gtk.css .config/gtk-4.0/settings.ini .config/gtk-4.0/gtk.css
	.config/qt6ct/qt6ct.conf
	.config/fastfetch/config.jsonc .config/fastfetch/huilo-logo.txt .config/starship.toml
	.bashrc .bash_profile
)
SEEDED=(.config/hypr/user.lua .config/kitty/user.conf .config/huilo/sway.conf)
while IFS=: read -r user _ uid gid _ home shell; do
	(( uid >= 1000 && uid < 60000 )) || continue
	[[ -d "$home" && "$shell" != */nologin ]] || continue
	info "пользователь $user: конфиги рабочего стола (старые — в *.bak-$stamp)"
	huilo-user-groups "$user" || true
	[[ -d "$home/.local/state/asos" && ! -e "$home/.local/state/huilo" ]] && mv "$home/.local/state/asos" "$home/.local/state/huilo"
	[[ -d "$home/.config/asos" && ! -e "$home/.config/huilo" ]] && mv "$home/.config/asos" "$home/.config/huilo"
	rm -f "$home/.config/hypr/hyprland.conf" "$home/.config/fastfetch/asos-logo.txt"
	if [[ -f "$home/.config/hypr/user.conf" ]]; then
		mv "$home/.config/hypr/user.conf" "$home/.config/hypr/user.conf.old"
		warn "  ~/.config/hypr/user.conf (старый формат) переименован в user.conf.old — перенесите свои настройки в user.lua"
	fi
	# replaced by the new look (rofi, swaync): kept as backups
	for old in .config/mako/config .config/wofi/config .config/wofi/style.css; do
		[[ -f "$home/$old" ]] && mv "$home/$old" "$home/$old.bak-$stamp"
	done
	# managed files: replaced; a file the user changed is kept as .bak-<date>
	for f in "${MANAGED[@]}"; do
		[[ -f "$A/etc/skel/$f" ]] || continue
		mkdir -p "$home/$(dirname "$f")"
		if [[ -f "$home/$f" ]] && ! cmp -s "$A/etc/skel/$f" "$home/$f"; then cp -a "$home/$f" "$home/$f.bak-$stamp"; fi
		install -m 0644 "$A/etc/skel/$f" "$home/$f"
		chown "$uid:$gid" "$home/$f"
	done
	# personal files: only created when missing
	for f in "${SEEDED[@]}" $(cd "$A/etc/skel" && ls .local/share/easyeffects/output/*.json); do
		[[ -f "$A/etc/skel/$f" && ! -e "$home/$f" ]] || continue
		mkdir -p "$home/$(dirname "$f")"
		install -m 0644 "$A/etc/skel/$f" "$home/$f"
		chown "$uid:$gid" "$home/$f"
	done
	rm -f "$home/.local/state/huilo/session/last-ok"
	for d in .config .config/hypr .config/waybar .config/kitty .config/rofi .config/swaync .config/swayosd \
		.config/gtk-3.0 .config/gtk-4.0 .config/qt6ct .config/fastfetch .config/huilo .local .local/share \
		.local/share/easyeffects .local/share/easyeffects/output; do
		[[ -d "$home/$d" ]] && chown "$uid:$gid" "$home/$d"
	done
	[[ -d "$home/.local/state/huilo" ]] && chown -R "$uid:$gid" "$home/.local/state/huilo"
done </etc/passwd

if [[ -d /boot/loader/entries && -f /boot/loader/entries/huilo.conf ]]; then
	opts=$(sed -n 's/^options[[:space:]]*//p' /boot/loader/entries/huilo.conf | sed 's/ huilo\.session=[a-z-]*//')
	printf 'title   Huilo (безопасная графика: sway без 3D)\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions %s huilo.session=sway-software\n' "$opts" \
		>/boot/loader/entries/huilo-safe.conf
	info "пункт загрузки «безопасная графика» обновлён"
fi

info "готово. Через 5 с перезапускаю графический сеанс на tty1 (переключиться: Ctrl+Alt+F1, в VirtualBox — Host+F1)"
info "экран загрузки с фото появится после перезагрузки; диагностика графики: huilo-doctor, журналы: huilo-logs"
sleep 5
systemctl restart getty@tty1.service || true
