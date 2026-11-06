#!/usr/bin/env bash
# ============================================================================
#  Create and start an ASOS virtual machine in Oracle VirtualBox (Linux/macOS).
#  Same settings as create-vm.ps1: <=4 cores, <=8 GB RAM, 20 GB VDI on SATA
#  (AHCI, not NVMe), EFI, VMSVGA + 3D, NAT, USB 3.0, ISO from ~/Downloads.
#
#  usage: ./create-vm.sh [--iso PATH] [--name ASOS] [--cpus 4] [--memory 8192]
#                        [--disk 20] [--boot-wait 90] [--no-autotype] [--recreate]
# ============================================================================
set -euo pipefail

NAME=ASOS CPUS=4 MEM=8192 DISK=20 ISO="" WAIT=90 AUTOTYPE=1 RECREATE=0
INSTALL_CMD="curl -fsSL https://raw.githubusercontent.com/Arqa322/asos/claude/arch-hyprland-custom-image-hl6sdl/scripts/install-online.sh -o i.sh && bash i.sh"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--iso) ISO=$2; shift 2 ;;
		--name) NAME=$2; shift 2 ;;
		--cpus) CPUS=$2; shift 2 ;;
		--memory) MEM=$2; shift 2 ;;
		--disk) DISK=$2; shift 2 ;;
		--boot-wait) WAIT=$2; shift 2 ;;
		--no-autotype) AUTOTYPE=0; shift ;;
		--recreate) RECREATE=1; shift ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		*) echo "unknown option $1" >&2; exit 1 ;;
	esac
done

info() { echo -e "\e[32m::\e[0m $*"; }
warn() { echo -e "\e[33m!!\e[0m $*" >&2; }
die()  { echo -e "\e[31merror:\e[0m $*" >&2; exit 1; }
vbox_try() { # what, then variants separated by "--or"
	local what=$1; shift
	local -a cur=()
	for a in "$@" "--or"; do
		if [[ "$a" == "--or" ]]; then
			VBoxManage "${cur[@]}" >/dev/null 2>&1 && return 0
			cur=()
		else
			cur+=("$a")
		fi
	done
	warn "не удалось включить: $what (не критично)"
}

command -v VBoxManage >/dev/null || die "VBoxManage не найден — установлен ли VirtualBox?"
info "VirtualBox $(VBoxManage --version)"

# ---------------------------------------------------------------- the ISO
if [[ -z "$ISO" ]]; then
	dl=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
	[[ -d "$dl" && "$dl" != "$HOME" ]] || for d in "$HOME/Загрузки" "$HOME/Downloads"; do [[ -d "$d" ]] && { dl=$d; break; }; done
	info "ищу ISO в $dl"
	ISO=$(ls -t "$dl"/asos-*.iso 2>/dev/null | head -n1 || true)
	[[ -n "$ISO" ]] || ISO=$(ls -t "$dl"/archlinux-*.iso 2>/dev/null | head -n1 || true)
	[[ -n "$ISO" ]] || ISO=$(ls -t "$dl"/*.iso 2>/dev/null | head -n1 || true)
	[[ -n "$ISO" ]] || die "в $dl нет файлов .iso — укажите --iso /путь/к/образу.iso"
fi
[[ -f "$ISO" ]] || die "ISO не найден: $ISO"
ISO=$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")
info "ISO: $ISO ($(du -h "$ISO" | cut -f1))"

# ------------------------------------------------------- host limits
if [[ "$(uname)" == Darwin ]]; then
	cores=$(sysctl -n hw.physicalcpu); ram=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
else
	cores=$(lscpu -p=CORE,SOCKET 2>/dev/null | grep -v '^#' | sort -u | wc -l); [[ $cores -gt 0 ]] || cores=$(nproc)
	ram=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
fi
(( CPUS > cores )) && CPUS=$cores
# leave the host at least 40% of its RAM; round to 256 MB
cap=$(( ram * 6 / 10 / 256 * 256 ))
(( MEM > cap )) && MEM=$cap
(( MEM < 2048 )) && MEM=2048
info "хост: $cores физ. ядер, $ram МБ ОЗУ  ->  ВМ: $CPUS ядра, $MEM МБ ОЗУ, диск $DISK ГБ (SATA)"

# ------------------------------------------------------------ create VM
if VBoxManage list vms | grep -q "^\"$NAME\" "; then
	[[ $RECREATE == 1 ]] || die "ВМ \"$NAME\" уже существует. Другое имя: --name ASOS2, пересоздать: --recreate (диск ВМ будет удалён)"
	read -rp "Удалить существующую ВМ \"$NAME\" вместе с диском? Введите YES: " a
	[[ "$a" == YES ]] || die "отменено"
	VBoxManage controlvm "$NAME" poweroff >/dev/null 2>&1 || true
	sleep 2
	VBoxManage unregistervm "$NAME" --delete
fi

base=$(VBoxManage list systemproperties | sed -n 's/^Default machine folder:[[:space:]]*//p')
VDI="$base/$NAME/$NAME.vdi"

created=0
for os in ArchLinux_64 ArchLinux_x64 Linux_64 Linux_x64; do
	if VBoxManage createvm --name "$NAME" --ostype "$os" --register >/dev/null 2>&1; then created=1; info "тип ОС: $os"; break; fi
done
[[ $created == 1 ]] || die "не удалось создать ВМ"

VBoxManage modifyvm "$NAME" --cpus "$CPUS" --memory "$MEM" --vram 128 --graphicscontroller vmsvga \
	--firmware efi --ioapic on --nic1 nat --boot1 dvd --boot2 disk --boot3 none --boot4 none
vbox_try "часы в UTC" modifyvm "$NAME" --rtc-use-utc on --or modifyvm "$NAME" --rtcuseutc on
vbox_try "3D-ускорение (нужно для Hyprland)" modifyvm "$NAME" --accelerate-3d on --or modifyvm "$NAME" --accelerate3d on
vbox_try "паравиртуализация KVM" modifyvm "$NAME" --paravirt-provider kvm --or modifyvm "$NAME" --paravirtprovider kvm
vbox_try "звук" modifyvm "$NAME" --audio-enabled on --audio-out on --audio-in on --or modifyvm "$NAME" --audioout on
vbox_try "общий буфер обмена" modifyvm "$NAME" --clipboard-mode bidirectional --or modifyvm "$NAME" --clipboard bidirectional
vbox_try "drag'n'drop" modifyvm "$NAME" --drag-and-drop bidirectional --or modifyvm "$NAME" --draganddrop bidirectional
vbox_try "USB 3.0 (xHCI)" modifyvm "$NAME" --usb-xhci on --or modifyvm "$NAME" --usbxhci on --or modifyvm "$NAME" --usb-ohci on
vbox_try "планшетная мышь" modifyvm "$NAME" --mouse usbtablet

info "диск $DISK ГБ (VDI, динамический) на контроллере SATA/AHCI"
VBoxManage createmedium disk --filename "$VDI" --size $(( DISK * 1024 )) --format VDI >/dev/null
VBoxManage storagectl "$NAME" --name SATA --add sata --controller IntelAhci --portcount 2 --hostiocache on --bootable on
VBoxManage storageattach "$NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$VDI" --nonrotational on --discard on
VBoxManage storageattach "$NAME" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$ISO"

[[ "$(uname)" == Linux ]] && ! id -nG | grep -qw vboxusers && warn "добавьте себя в группу vboxusers для проброса USB: sudo usermod -aG vboxusers ${USER:-$(id -un)}"

info "запуск ВМ"
VBoxManage startvm "$NAME" --type gui

echo
echo "Команда установщика ASOS для консоли Arch live:"
echo "  $INSTALL_CMD"
echo
if [[ $AUTOTYPE == 1 && "$(basename "$ISO")" == archlinux-* ]]; then
	read -rp "Ввести её в ВМ автоматически через $WAIT с (после загрузки live-системы)? [Y/n] " a
	if [[ -z "$a" || "$a" =~ ^[YyДд] ]]; then
		for (( i = WAIT; i > 0; i -= 5 )); do printf '\r  ожидание загрузки: %3d с ' "$i"; sleep 5; done; echo
		VBoxManage controlvm "$NAME" keyboardputstring "$INSTALL_CMD"
		VBoxManage controlvm "$NAME" keyboardputscancode 1c 9c
		info "команда введена. Дальше отвечайте на вопросы установщика в окне ВМ."
		echo "  Если строка ввелась раньше, чем появилось приглашение root@archiso, наберите команду выше вручную."
	fi
fi
info "после установки: Устройства -> Оптические диски -> Изъять диск, затем reboot в ВМ"
