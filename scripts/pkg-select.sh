#!/usr/bin/env bash
# ============================================================================
#  pkg-select.sh — optional package groups of ASOS
#
#  Package lists (archiso/packages.x86_64, archiso/packages.aur) are split into
#  sections "# ---------- [tag] Name ----------". Untagged sections are the core
#  system; tagged ones can be left out.
#
#    pkg-select.sh --list-groups                      groups and descriptions
#    pkg-select.sh --resolve "office,sysadmin"        expand aliases -> tags
#    pkg-select.sh LIST [--without "office games"]    print the packages to install
#    pkg-select.sh LIST --only "office"               print the packages of groups
#
#  Aliases: sysadmin = monitoring nettools disktools virt security
#           embedded = arduino nanopi,   minimal / all = every optional group
#  Non-package groups: zapret (DPI bypass), aur (AUR packages, yay)
# ============================================================================
set -euo pipefail

declare -A DESC=(
	[office]="LibreOffice, Zathura, Xournal++, KeePassXC, калькулятор"
	[communication]="Thunderbird, Telegram, Discord, qBittorrent"
	[media]="OBS Studio, GIMP"
	[vscode]="VS Code (Code - OSS)"
	[games]="Atom game pack: Steam, Lutris, Wine, GameMode, MangoHud, 32-бит драйверы"
	[arduino]="Arduino IDE 2, arduino-cli, PlatformIO, esptool, OpenOCD, логический анализатор"
	[nanopi]="кросс-компилятор aarch64, qemu-user, rkdeveloptool, xfel, прошивка SD"
	[monitoring]="htop, btop, nvtop, glances, sysstat, strace, gdb, stress-ng"
	[nettools]="nmap, Wireshark, tcpdump, mtr, iperf3, Remmina, FileZilla"
	[disktools]="GParted, testdisk, ddrescue, Clonezilla, LVM/RAID/LUKS, rclone, restic, borg"
	[virt]="Docker, QEMU, libvirt, virt-manager, Ansible, OpenTofu, kubectl, Helm"
	[security]="Lynis, ClamAV"
	[zapret]="обход DPI: zapret + стратегии Flowseal"
	[aur]="AUR-помощник yay"
)
ORDER=(office communication media vscode games arduino nanopi monitoring nettools disktools virt security zapret aur)

resolve() { # aliases/commas -> unique tags, one per line
	local w
	for w in ${1//,/ }; do
		case "$w" in
			minimal|all) printf '%s\n' "${ORDER[@]}" ;;
			sysadmin) printf '%s\n' monitoring nettools disktools virt security ;;
			embedded) printf '%s\n' arduino nanopi ;;
			"") ;;
			*) [[ -n "${DESC[$w]:-}" ]] || { echo "unknown group '$w' (see --list-groups)" >&2; exit 2; }
			   echo "$w" ;;
		esac
	done | awk '!seen[$0]++'
}

filter() { # LIST MODE(without|only) "tags"
	local list=$1 mode=$2 tags=" ${3//$'\n'/ } "
	awk -v mode="$mode" -v tags="$tags" '
		/^# -+ / {
			tag = ""
			if (match($0, /\[[a-z0-9-]+\]/)) tag = substr($0, RSTART + 1, RLENGTH - 2)
			sel = (tag != "" && index(tags, " " tag " ") > 0)
			next
		}
		{ sub(/#.*/, ""); gsub(/[ \t]/, "") }
		$0 == "" { next }
		mode == "without" && !sel && !seen[$0]++ { print }
		mode == "only" && sel && !seen[$0]++ { print }
	' "$list"
}

case "${1:-}" in
	--list-groups)
		for g in "${ORDER[@]}"; do printf '  %-14s %s\n' "$g" "${DESC[$g]}"; done
		echo "  алиасы: sysadmin = monitoring,nettools,disktools,virt,security; embedded = arduino,nanopi; minimal = всё"
		;;
	--resolve) tags=$(resolve "${2:-}") || exit 2; [[ -z "$tags" ]] || printf '%s\n' "$tags" ;;
	""|-h|--help) sed -n '2,19p' "$0" ;;
	*)
		list=$1; shift
		[[ -f "$list" ]] || { echo "no such file: $list" >&2; exit 2; }
		case "${1:-}" in
			--without) tags=$(resolve "${2:-}") || exit 2; filter "$list" without "$tags" ;;
			--only) tags=$(resolve "${2:-}") || exit 2; filter "$list" only "$tags" ;;
			"") filter "$list" without "" ;;
			*) echo "unknown option $1" >&2; exit 2 ;;
		esac
		;;
esac
