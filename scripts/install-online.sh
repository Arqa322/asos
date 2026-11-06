#!/usr/bin/env bash
# ============================================================================
#  ASOS online installer — run from the OFFICIAL Arch Linux ISO (live, root).
#
#  Installs Arch Linux with every ASOS setting (Hyprland, zapret + Flowseal,
#  Atom game pack, office, sysadmin tools, Arduino, NanoPi) straight onto a
#  disk, without building the ASOS ISO first. Works on real hardware and in
#  VirtualBox/VMware/QEMU (guest tools are added automatically).
#
#  In the Arch live console:
#    curl -fsSL https://raw.githubusercontent.com/Arqa322/asos/claude/arch-hyprland-custom-image-hl6sdl/scripts/install-online.sh -o i.sh
#    bash i.sh
#
#  Non-interactive (all optional):
#    ASOS_DISK=/dev/sda ASOS_USER=user ASOS_PASSWORD=secret ASOS_HOSTNAME=asos \
#    ASOS_TZ=Europe/Moscow ASOS_FS=btrfs ASOS_AUTOLOGIN=yes ASOS_YES=1 bash i.sh
#
#  Skip parts:  ASOS_SKIP_AUR=1  ASOS_SKIP_ARDUINO=1  ASOS_SKIP_GROUPS="Atom game pack;Office ..."
# ============================================================================
set -euo pipefail

REPO="${ASOS_REPO:-Arqa322/asos}"
REF="${ASOS_REF:-claude/arch-hyprland-custom-image-hl6sdl}"
MNT=/mnt
LOG=/root/asos-install.log
SRC=""

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_b=$'\e[1m'; c_0=$'\e[0m'
step() { echo; echo "${c_b}${c_ok}==>${c_0}${c_b} $*${c_0}"; }
info() { echo "${c_ok}  ->${c_0} $*"; }
warn() { echo "${c_warn}  !!${c_0} $*" >&2; }
die()  { echo "${c_err}error:${c_0} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "запустите от root (в live-образе Arch вы уже root)"
exec > >(tee -a "$LOG") 2>&1

# Packages that only make sense on the live medium
LIVE_ONLY=(mkinitcpio-archiso syslinux memtest86+ memtest86+-efi edk2-shell archinstall)

# Files of the ASOS overlay that are live-medium only or must not replace
# the installed system's own copies
OVERLAY_EXCLUDE=(
	./etc/passwd ./etc/shadow ./etc/group ./etc/gshadow ./etc/hostname ./etc/localtime
	./etc/mkinitcpio.conf.d/archiso.conf ./etc/mkinitcpio.d/linux.preset
	./etc/systemd/system/getty@tty1.service.d
	./etc/sudoers.d/90-asos-live
	./etc/systemd/system/etc-pacman.d-gnupg.mount
	./etc/systemd/system/pacman-init.service
	./etc/systemd/system/multi-user.target.wants/pacman-init.service
	./etc/systemd/system/asos-live-setup.service
	./etc/systemd/system/multi-user.target.wants/asos-live-setup.service
	./etc/systemd/journald.conf.d/volatile-storage.conf
	./etc/systemd/logind.conf.d/do-not-suspend.conf
	./etc/pacman.d/hooks ./etc/pacman.d/mirrorlist
	./opt/zapret
)

# ------------------------------------------------------------- preflight ---
step "Проверка окружения"
[[ -d /run/archiso ]] || warn "похоже, это не live-образ Arch — продолжаю, но будьте внимательны"
for c in pacstrap arch-chroot genfstab sgdisk curl tar; do
	command -v "$c" >/dev/null || die "нет команды $c — нужен официальный ISO Arch Linux"
done
UEFI=0; [[ -d /sys/firmware/efi/efivars ]] && UEFI=1
VIRT=$(systemd-detect-virt 2>/dev/null || echo none)
info "режим загрузки: $([[ $UEFI == 1 ]] && echo UEFI || echo BIOS), виртуализация: $VIRT"
curl -fsS -m 15 -o /dev/null https://archlinux.org || die "нет интернета (для Wi-Fi: iwctl; проверьте: ping archlinux.org)"
timedatectl set-ntp true 2>/dev/null || true

# wait for the live medium's keyring initialisation
if systemctl list-units --all pacman-init.service 2>/dev/null | grep -q pacman-init; then
	info "ожидание инициализации ключей pacman"
	for _ in $(seq 1 60); do systemctl is-active --quiet pacman-init.service && break; sleep 2; done
fi
pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null 2>&1 || warn "не удалось обновить archlinux-keyring (продолжаю)"

# ---------------------------------------------------------------- source ---
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [[ -n "$here" && -f "$here/../archiso/packages.x86_64" ]]; then
	SRC=$(cd "$here/.." && pwd)
	info "используются файлы из $SRC"
else
	step "Загрузка ASOS ($REPO @ $REF)"
	SRC=/root/asos-src
	rm -rf "$SRC"; mkdir -p "$SRC"
	curl -fsSL --retry 4 "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" | tar -xz -C "$SRC" --strip-components=1
	[[ -f "$SRC/archiso/packages.x86_64" ]] || die "не удалось скачать репозиторий ASOS"
fi
PROFILE="$SRC/archiso"

# ------------------------------------------------------------- questions ---
ask() { # ask VAR "question" "default"
	local __v=$1 __q=$2 __d=${3:-} __a
	if [[ -n "${!__v:-}" ]]; then return 0; fi
	read -rp "$__q${__d:+ [$__d]}: " __a </dev/tty
	printf -v "$__v" '%s' "${__a:-$__d}"
}

step "Параметры установки"
mapfile -t DISKS < <(lsblk -dpno NAME,SIZE,TYPE,RO,MODEL -e 7,11 | awk '$3=="disk" && $4==0')
LIVEDEV=""
if src=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null); then LIVEDEV=/dev/$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1); fi
echo "Диски:"; printf '  %s\n' "${DISKS[@]}"
DEFAULT_DISK=""
[[ ${#DISKS[@]} -eq 1 ]] && DEFAULT_DISK=${DISKS[0]%% *}
ASOS_DISK=${ASOS_DISK:-}
ask ASOS_DISK "Диск для установки (ВСЕ ДАННЫЕ БУДУТ УДАЛЕНЫ)" "$DEFAULT_DISK"
[[ -b "$ASOS_DISK" ]] || die "$ASOS_DISK не найден"
[[ "$ASOS_DISK" != "$LIVEDEV" ]] || die "$ASOS_DISK — это установочный носитель"
DISK_GB=$(( $(lsblk -bdno SIZE "$ASOS_DISK") / 1024 / 1024 / 1024 ))
(( DISK_GB >= 18 )) || die "диск $ASOS_DISK слишком мал (${DISK_GB} ГБ, нужно от 20 ГБ)"

ASOS_FS=${ASOS_FS:-}; ask ASOS_FS "Файловая система (btrfs — со сжатием, рекомендуется для дисков до 64 ГБ / ext4)" "btrfs"
[[ "$ASOS_FS" == btrfs || "$ASOS_FS" == ext4 ]] || die "ASOS_FS: btrfs или ext4"
ASOS_HOSTNAME=${ASOS_HOSTNAME:-}; ask ASOS_HOSTNAME "Имя компьютера" "asos"
ASOS_USER=${ASOS_USER:-}; ask ASOS_USER "Имя пользователя (латиница, строчные)" "user"
[[ "$ASOS_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "недопустимое имя пользователя"
if [[ -z "${ASOS_PASSWORD:-}" ]]; then
	while true; do
		read -rsp "Пароль для $ASOS_USER (и для sudo): " p1 </dev/tty; echo
		read -rsp "Повторите пароль: " p2 </dev/tty; echo
		[[ -n "$p1" && "$p1" == "$p2" ]] && break
		echo "Пароли пустые или не совпадают."
	done
	ASOS_PASSWORD=$p1
fi
ASOS_TZ=${ASOS_TZ:-}; ask ASOS_TZ "Часовой пояс" "Europe/Moscow"
[[ -f "/usr/share/zoneinfo/$ASOS_TZ" ]] || die "неизвестный часовой пояс $ASOS_TZ"
DEFAULT_AUTOLOGIN=no; [[ "$VIRT" != none ]] && DEFAULT_AUTOLOGIN=yes
ASOS_AUTOLOGIN=${ASOS_AUTOLOGIN:-}; ask ASOS_AUTOLOGIN "Автовход и запуск Hyprland без пароля (yes/no)" "$DEFAULT_AUTOLOGIN"

echo
echo "  диск:        ${c_b}$ASOS_DISK${c_0} (${DISK_GB} ГБ), ФС: $ASOS_FS, загрузка: $([[ $UEFI == 1 ]] && echo UEFI/systemd-boot || echo BIOS/GRUB)"
echo "  компьютер:   $ASOS_HOSTNAME, пользователь: $ASOS_USER, часовой пояс: $ASOS_TZ, автовход: $ASOS_AUTOLOGIN"
if [[ "${ASOS_YES:-0}" != 1 ]]; then
	read -rp "${c_err}Диск $ASOS_DISK будет полностью стёрт.${c_0} Введите YES: " ok </dev/tty
	[[ "$ok" == YES ]] || die "отменено"
fi

# ------------------------------------------------------------- partition ---
step "Разметка и форматирование $ASOS_DISK"
umount -R "$MNT" 2>/dev/null || true
swapoff -a 2>/dev/null || true
wipefs -af "$ASOS_DISK" >/dev/null
sgdisk --zap-all "$ASOS_DISK" >/dev/null
if [[ $UEFI == 1 ]]; then
	sgdisk -n1:0:+1G -t1:ef00 -c1:ESP -n2:0:0 -t2:8304 -c2:ASOS "$ASOS_DISK" >/dev/null
else
	sgdisk -n1:0:+1M -t1:ef02 -c1:BIOSBOOT -n2:0:+1G -t2:8300 -c2:BOOT -n3:0:0 -t3:8304 -c3:ASOS "$ASOS_DISK" >/dev/null
fi
partprobe "$ASOS_DISK" 2>/dev/null || true
udevadm settle
part() { lsblk -lnpo NAME,TYPE "$ASOS_DISK" | awk '$2=="part"{print $1}' | sed -n "${1}p"; }
if [[ $UEFI == 1 ]]; then BOOTP=$(part 1); ROOTP=$(part 2); else BOOTP=$(part 2); ROOTP=$(part 3); fi
[[ -b "$BOOTP" && -b "$ROOTP" ]] || die "не удалось определить разделы"

if [[ $UEFI == 1 ]]; then mkfs.fat -F32 -n ESP "$BOOTP" >/dev/null; else mkfs.ext4 -qF -L BOOT "$BOOTP"; fi
ROOTFLAGS=""
if [[ "$ASOS_FS" == btrfs ]]; then
	mkfs.btrfs -qf -L ASOS "$ROOTP"
	mount "$ROOTP" "$MNT"
	for sv in @ @home @log @pkg; do btrfs -q subvolume create "$MNT/$sv"; done
	umount "$MNT"
	opts="noatime,compress=zstd:3"
	mount -o "$opts,subvol=@" "$ROOTP" "$MNT"
	mkdir -p "$MNT"/{home,var/log,var/cache/pacman/pkg}
	mount -o "$opts,subvol=@home" "$ROOTP" "$MNT/home"
	mount -o "$opts,subvol=@log" "$ROOTP" "$MNT/var/log"
	mount -o "$opts,subvol=@pkg" "$ROOTP" "$MNT/var/cache/pacman/pkg"
	ROOTFLAGS="rootflags=subvol=@"
else
	mkfs.ext4 -qF -L ASOS "$ROOTP"
	mount "$ROOTP" "$MNT"
fi
mkdir -p "$MNT/boot"
mount "$BOOTP" "$MNT/boot"

# ------------------------------------------------------------- packages ---
# Sections of archiso/packages.x86_64 ("# ---------- Name ----------") are
# installed one after another and the package cache is emptied in between,
# so even a 20 GB disk is enough.
declare -a SECTION_NAMES=()
declare -A SECTION_PKGS=()
current="Base"
while IFS= read -r line; do
	if [[ "$line" =~ ^#\ -+\ (.+)\ -+$ ]]; then
		current=${BASH_REMATCH[1]}
		continue
	fi
	line=${line%%#*}; line=${line//[[:space:]]/}
	[[ -n "$line" ]] || continue
	skip=0; for l in "${LIVE_ONLY[@]}"; do [[ "$line" == "$l" ]] && skip=1; done
	[[ $skip == 0 ]] || continue
	if [[ -z "${SECTION_PKGS[$current]+x}" ]]; then SECTION_NAMES+=("$current"); SECTION_PKGS[$current]=""; fi
	SECTION_PKGS[$current]+="$line "
done <"$PROFILE/packages.x86_64"

# guest tools for virtual machines
case "$VIRT" in
	oracle) SECTION_NAMES+=("VirtualBox guest"); SECTION_PKGS["VirtualBox guest"]="virtualbox-guest-utils " ;;
	kvm|qemu) SECTION_NAMES+=("QEMU guest"); SECTION_PKGS["QEMU guest"]="qemu-guest-agent spice-vdagent " ;;
	vmware) SECTION_NAMES+=("VMware guest"); SECTION_PKGS["VMware guest"]="open-vm-tools " ;;
esac

PACMAN_CONF="$PROFILE/airootfs/etc/pacman.conf"
FAILED_PKGS=()
space() { df -h --output=avail "$MNT" | tail -n1 | xargs; }
clean_cache() { rm -rf "$MNT"/var/cache/pacman/pkg/* 2>/dev/null || true; }

first="${SECTION_NAMES[0]}"
step "Установка: $first  (свободно $(space))"
# shellcheck disable=SC2086
pacstrap -K -C "$PACMAN_CONF" "$MNT" ${SECTION_PKGS[$first]} || die "pacstrap не удался — см. $LOG"
install -m 0644 "$PACMAN_CONF" "$MNT/etc/pacman.conf"
clean_cache

skip_groups=";${ASOS_SKIP_GROUPS:-};"
for sec in "${SECTION_NAMES[@]:1}"; do
	if [[ "$skip_groups" == *";$sec;"* ]]; then info "пропуск: $sec"; continue; fi
	step "Установка: $sec  (свободно $(space))"
	# shellcheck disable=SC2206
	pkgs=(${SECTION_PKGS[$sec]})
	if ! arch-chroot "$MNT" pacman -Sy --needed --noconfirm "${pkgs[@]}"; then
		warn "группа целиком не установилась — ставлю пакеты по одному"
		for p in "${pkgs[@]}"; do
			arch-chroot "$MNT" pacman -S --needed --noconfirm "$p" || FAILED_PKGS+=("$p")
		done
	fi
	clean_cache
done

# ---------------------------------------------------------------- overlay ---
step "Настройки ASOS (Hyprland, zapret, Atom, Arduino, NanoPi ...)"
excl=(); for e in "${OVERLAY_EXCLUDE[@]}"; do excl+=(--exclude="$e"); done
tar -C "$PROFILE/airootfs" "${excl[@]}" -cf - . | tar -C "$MNT" --no-same-owner -xf -
chown -R root:root "$MNT/etc/skel" "$MNT/usr/local/bin" "$MNT/usr/share/asos" "$MNT/etc/zapret"
chmod 0750 "$MNT/etc/sudoers.d"; chmod 0440 "$MNT/etc/sudoers.d/10-wheel"
chmod 0755 "$MNT"/usr/local/bin/*

if [[ $ASOS_AUTOLOGIN == yes ]]; then
	mkdir -p "$MNT/etc/systemd/system/getty@tty1.service.d"
	cat >"$MNT/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $ASOS_USER - \$TERM
EOF
fi

genfstab -U "$MNT" >"$MNT/etc/fstab"
echo "$ASOS_HOSTNAME" >"$MNT/etc/hostname"
cat >"$MNT/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $ASOS_HOSTNAME.localdomain $ASOS_HOSTNAME
EOF
ln -sf "/usr/share/zoneinfo/$ASOS_TZ" "$MNT/etc/localtime"

ROOT_UUID=$(blkid -s UUID -o value "$ROOTP")
CMDLINE="root=UUID=$ROOT_UUID rw $ROOTFLAGS quiet splash loglevel=3"

# ------------------------------------------------------------ system setup ---
step "Системные настройки, пользователь, загрузчик"
SERVICES="NetworkManager.service bluetooth.service zapret.service power-profiles-daemon.service systemd-timesyncd.service avahi-daemon.service fstrim.timer"
case "$VIRT" in
	oracle) SERVICES+=" vboxservice.service" ;;
	kvm|qemu) SERVICES+=" qemu-guest-agent.service" ;;
	vmware) SERVICES+=" vmtoolsd.service" ;;
esac
cat >"$MNT/root/asos-setup.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
hwclock --systohc || true
locale-gen
useradd -m -s /bin/bash "$ASOS_USER"
asos-user-groups "$ASOS_USER"
passwd -l root
mkinitcpio -P
if [[ $UEFI == 1 ]]; then
	bootctl install --esp-path=/boot
	mkdir -p /boot/loader/entries
	printf 'default asos.conf\ntimeout 3\nconsole-mode max\neditor no\n' >/boot/loader/loader.conf
	printf 'title   ASOS (Arch Linux + Hyprland)\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux.img\noptions %s\n' "$CMDLINE" >/boot/loader/entries/asos.conf
	printf 'title   ASOS (fallback initramfs)\nlinux   /vmlinuz-linux\ninitrd  /initramfs-linux-fallback.img\noptions %s\n' "$CMDLINE" >/boot/loader/entries/asos-fallback.conf
	systemctl enable systemd-boot-update.service || true
else
	sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="$ROOTFLAGS quiet splash loglevel=3"|' /etc/default/grub
	sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="ASOS"|' /etc/default/grub
	grub-install --target=i386-pc "$ASOS_DISK"
	grub-mkconfig -o /boot/grub/grub.cfg
fi
for s in $SERVICES; do systemctl enable "\$s" 2>/dev/null || echo "warning: cannot enable \$s"; done
EOF
arch-chroot "$MNT" bash /root/asos-setup.sh
printf '%s:%s\n' "$ASOS_USER" "$ASOS_PASSWORD" | arch-chroot "$MNT" chpasswd
rm -f "$MNT/root/asos-setup.sh"

# -------------------------------------------------- zapret + Flowseal ---
step "zapret + стратегии Flowseal"
mkdir -p "$MNT/root/asos-src"
cp -a "$SRC/scripts" "$SRC/archiso" "$MNT/root/asos-src/"
arch-chroot "$MNT" env DEST=/opt/zapret bash /root/asos-src/scripts/fetch-zapret.sh ||
	warn "zapret не скачан — позже: sudo DEST=/opt/zapret bash fetch-zapret.sh"

# -------------------------------------------------------------- AUR ---
if [[ "${ASOS_SKIP_AUR:-0}" != 1 ]]; then
	step "AUR: Arduino IDE 2, rkdeveloptool, xfel, tio, cutecom, mpremote, yay"
	echo "$ASOS_USER ALL=(ALL) NOPASSWD: /usr/bin/pacman" >"$MNT/etc/sudoers.d/99-asos-install"
	chmod 0440 "$MNT/etc/sudoers.d/99-asos-install"
	arch-chroot "$MNT" env SUDO_USER="$ASOS_USER" bash /root/asos-src/scripts/build-aur.sh \
		/root/asos-src/archiso/packages.aur /var/cache/asos-aur || true
	shopt -s nullglob
	aurpkgs=("$MNT"/var/cache/asos-aur/*.pkg.tar.*)
	shopt -u nullglob
	if [[ ${#aurpkgs[@]} -gt 0 ]]; then
		arch-chroot "$MNT" bash -c 'pacman -U --needed --noconfirm /var/cache/asos-aur/*.pkg.tar.*' || warn "часть AUR-пакетов не установилась"
	fi
	rm -f "$MNT/etc/sudoers.d/99-asos-install"
	rm -rf "$MNT/var/cache/asos-aur"
	clean_cache
fi

# ------------------------------------------------------------- Arduino ---
if [[ "${ASOS_SKIP_ARDUINO:-0}" != 1 ]]; then
	step "Arduino: ядро AVR и библиотеки для $ASOS_USER"
	arch-chroot "$MNT" sudo -u "$ASOS_USER" -H bash /root/asos-src/scripts/fetch-arduino.sh "/home/$ASOS_USER" ||
		warn "Arduino не настроен — позже: asos-arduino setup avr"
fi

# ---------------------------------------------------------- VM tweaks ---
if [[ "$VIRT" != none ]]; then
	step "Настройки для виртуальной машины ($VIRT)"
	cat >>"$MNT/home/$ASOS_USER/.config/hypr/user.conf" <<'EOF'

# --- added by ASOS installer: virtual machine ---
# hardware cursors are broken on most virtual GPUs
cursor {
    no_hardware_cursors = true
}
EOF
	arch-chroot "$MNT" chown "$ASOS_USER:$ASOS_USER" "/home/$ASOS_USER/.config/hypr/user.conf"
fi

rm -rf "$MNT/root/asos-src"
clean_cache
cp -f "$LOG" "$MNT/var/log/asos-install.log" 2>/dev/null || true
sync

step "Готово"
echo "  установлено на $ASOS_DISK, свободно $(space)"
if [[ ${#FAILED_PKGS[@]} -gt 0 ]]; then
	warn "не установились пакеты: ${FAILED_PKGS[*]}"
	warn "после загрузки: sudo pacman -S ${FAILED_PKGS[*]}"
fi
umount -R "$MNT" || true
echo
echo "  Извлеките ISO (в VirtualBox: Устройства → Оптические диски → Изъять) и выполните: reboot"
echo "  Пользователь: $ASOS_USER. Журнал установки: /var/log/asos-install.log"
