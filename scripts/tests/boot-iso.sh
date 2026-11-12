#!/usr/bin/env bash
# ============================================================================
#  Boot a Huilo ISO in QEMU and record what a user would see.
#
#    scripts/tests/boot-iso.sh out/huilo-*.iso [RESULT_DIR] [SECONDS]
#
#  Two runs:
#   1. uefi     the real UEFI boot path (systemd-boot menu -> default entry),
#               like the VirtualBox VM from vm/create-vm.*: screenshots only
#   2. serial   kernel + initramfs taken from the ISO, same root, plus a serial
#               console that receives the whole system journal: failed units,
#               huilo-session decisions, crashes
#  RESULT_DIR gets uefi-*.png, serial-*.png, serial.log and summary.txt.
#  Needs: qemu-system-x86_64, OVMF, xorriso, socat, python3 + Pillow (PNG).
#  Exit code 1 when the system does not reach the graphical session.
# ============================================================================
set -uo pipefail
ISO=$(realpath "${1:?usage: boot-iso.sh ISO [RESULT_DIR] [SECONDS]}")
OUT=$(realpath -m "${2:-boot-test}")
SECS=${3:-300}
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT

ACCEL=(-accel tcg)
if [[ -w /dev/kvm ]]; then ACCEL=(-accel kvm -cpu host); else echo "!! no KVM: the boot will be slow (TCG)"; fi
MEM=${BOOT_TEST_MEM:-6144}
SMP=${BOOT_TEST_CPUS:-3}

ovmf_code="" ovmf_vars=""
for c in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
	[[ -f "$c" ]] && { ovmf_code=$c; break; }
done
for v in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd; do
	[[ -f "$v" ]] && { ovmf_vars=$v; break; }
done

shot() { # NAME — screenshot through the QEMU monitor
	echo "screendump $TMP/$1.ppm" | socat - "UNIX-CONNECT:$TMP/mon-$RUN.sock" >/dev/null 2>&1 || return 0
	sleep 1
	python3 - "$TMP/$1.ppm" "$OUT/$1.png" <<'EOF' 2>/dev/null || cp "$TMP/$1.ppm" "$OUT/$1.ppm" 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
EOF
}

run() { # NAME, QEMU args...
	RUN=$1; shift
	echo ":: boot run '$RUN' (${SECS}s)"
	qemu-system-x86_64 "${ACCEL[@]}" -machine q35 -m "$MEM" -smp "$SMP" \
		-device virtio-vga -display none -device qemu-xhci -device usb-tablet \
		-nic user,model=virtio-net-pci -device virtio-rng-pci \
		-monitor "unix:$TMP/mon-$RUN.sock,server,nowait" "$@" &
	local qpid=$! t=0 n=0
	for at in 15 30 60 90 120 180 240 300 420 600; do
		(( at <= SECS )) || break
		sleep $((at - t)); t=$at
		kill -0 "$qpid" 2>/dev/null || { echo "!! QEMU exited early"; break; }
		n=$((n + 1)); shot "$(printf '%s-%02d-%03ds' "$RUN" "$n" "$at")"
	done
	echo quit | socat - "UNIX-CONNECT:$TMP/mon-$RUN.sock" >/dev/null 2>&1
	wait "$qpid" 2>/dev/null
}

# 1. UEFI, unmodified boot menu
if [[ -n "$ovmf_code" ]]; then
	cp "${ovmf_vars:-$ovmf_code}" "$TMP/vars.fd"
	run uefi -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" -drive "if=pflash,format=raw,file=$TMP/vars.fd" \
		-cdrom "$ISO" -serial "file:$OUT/uefi-serial.log"
else
	echo "!! OVMF not found — skipping the UEFI run"
fi

# 2. same system, journal on the serial console
LABEL=$(xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p' | head -n1)
xorriso -osirrox on -indev "$ISO" -extract /arch/boot/x86_64/vmlinuz-linux "$TMP/vmlinuz" \
	-extract /arch/boot/x86_64/initramfs-linux.img "$TMP/initramfs.img" >/dev/null 2>&1
if [[ -s "$TMP/vmlinuz" && -n "$LABEL" ]]; then
	run serial -kernel "$TMP/vmlinuz" -initrd "$TMP/initramfs.img" -cdrom "$ISO" -serial "file:$OUT/serial.log" \
		-append "archisobasedir=arch archisolabel=$LABEL cow_spacesize=50% console=tty0 console=ttyS0,115200 systemd.journald.forward_to_console=1 systemd.show_status=1"
else
	echo "!! could not extract the kernel or the volume label (label='$LABEL')"
fi

# ------------------------------------------------------------- summary ---
log="$OUT/serial.log"
{
	echo "ISO: $(basename "$ISO") ($(du -h "$ISO" | cut -f1)), label $LABEL, accel ${ACCEL[*]}"
	echo
	echo "== huilo-session"
	grep -a 'huilo-session' "$log" 2>/dev/null | sed 's/^.*huilo-session\[[0-9]*\]: //' | tail -n 20
	echo
	echo "== failed units / emergency"
	grep -a -E 'FAILED|Failed to start|emergency|Entering emergency|You are in emergency mode|Kernel panic|segfault|core dumped' "$log" 2>/dev/null | tail -n 40
	echo
	echo "== errors of the desktop (Hyprland, sway, waybar, swaync, swayosd, rofi, wallpaper)"
	grep -a -i -E '(hyprland|sway|waybar|swaync|swayosd|awww|hyprlock|hypridle|easyeffects|pipewire|wireplumber)[^ ]*\[[0-9]+\]:.*(error|fail|crit|abort|cannot|unable)' "$log" 2>/dev/null | tail -n 40
	echo
	echo "== last 30 lines of the journal"
	tail -n 30 "$log" 2>/dev/null
} >"$OUT/summary.txt"
cat "$OUT/summary.txt"

if grep -a -q -E 'huilo-session.*(работает|works)' "$log" 2>/dev/null; then
	echo ":: graphical session is up"
	exit 0
fi
echo "!! the graphical session did not report success — see screenshots and $OUT/serial.log"
exit 1
