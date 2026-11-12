#!/usr/bin/env bash
# ============================================================================
#  Build the ASOS ISO.
#
#  On Arch Linux (needs archiso):     sudo ./build.sh
#  Anywhere with Docker/Podman:       ./build.sh --docker
#
#  Steps: copy the archiso profile to WORK_DIR -> fetch zapret + Flowseal ->
#  build AUR packages into a local repo -> pre-install Arduino cores/libraries
#  -> mkarchiso. The git tree itself is never modified.
#
#  Env:
#    ZAPRET_VERSION   zapret release tag            (default: latest)
#    FLOWSEAL_REF     Flowseal branch or tag        (default: main)
#    ARDUINO_CORES    cores to pre-install          (default: arduino:avr)
#    ARDUINO_LIBS     ';' separated libraries       (default: see fetch-arduino.sh)
#    SKIP_AUR=1       do not build AUR packages
#    SKIP_ARDUINO=1   do not pre-install Arduino cores/libraries
#    OUT_DIR          default ./out
#    WORK_DIR         default ./work
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
WORK_DIR="${WORK_DIR:-$ROOT/work}"

if [[ "${1:-}" == "--docker" ]]; then
	engine=$(command -v docker || command -v podman) || { echo "docker/podman not found" >&2; exit 1; }
	exec "$engine" run --rm --privileged \
		-e ZAPRET_VERSION -e FLOWSEAL_REF -e ARDUINO_CORES -e ARDUINO_LIBS \
		-e SKIP_AUR -e SKIP_ARDUINO -e ASOS_IN_CONTAINER=1 \
		-v "$ROOT:/build" -w /build \
		docker.io/archlinux/archlinux:latest \
		bash -c 'pacman -Syu --noconfirm --needed archiso base-devel git curl sudo arduino-cli && ./build.sh'
fi

[[ $EUID -eq 0 ]] || { echo "run as root: sudo ./build.sh  (or ./build.sh --docker)" >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "mkarchiso not found: pacman -S archiso" >&2; exit 1; }

# ------------------------------------------------------------- preflight ---
NEED_GB=${NEED_GB:-40}
CACHE_DIR=$(pacman-conf CacheDir 2>/dev/null | head -n1); CACHE_DIR=${CACHE_DIR:-/var/cache/pacman/pkg/}
if [[ -d /run/archiso && "${ALLOW_LIVE:-0}" != 1 ]]; then
	echo "!! build.sh запущен в live-образе Arch: файлы пишутся в оперативную память, места не хватит." >&2
	echo "   Соберите на установленной системе с диском от ${NEED_GB} ГБ, через ./build.sh --docker или в GitHub Actions." >&2
	exit 1
fi
mkdir -p "$WORK_DIR" "$OUT_DIR" "$CACHE_DIR"
free_gb() { df -P -BG "$1" | awk 'NR==2 {gsub("G","",$4); print $4}'; }
declare -A seen=()
for d in "$WORK_DIR" "$OUT_DIR" "$CACHE_DIR"; do
	fs=$(df -P "$d" | awk 'NR==2 {print $1}')
	[[ -n "${seen[$fs]:-}" ]] && continue; seen[$fs]=1
	f=$(free_gb "$d")
	if (( f < NEED_GB )); then
		echo "!! мало места: на $d (файловая система $fs) свободно ${f} ГБ, нужно не меньше ${NEED_GB} ГБ" >&2
		echo "   (развёрнутая система ~15 ГБ + кэш пакетов ~6 ГБ + сжатый образ и ISO по ~7 ГБ)." >&2
		echo "   При нехватке места pacman оставляет недокачанные пакеты и пишет об ошибке подписи (signature)." >&2
		echo "   Освободите место, укажите другой диск (WORK_DIR=/путь OUT_DIR=/путь) или соберите в GitHub Actions." >&2
		[[ "${IGNORE_SPACE:-0}" == 1 ]] || exit 1
	fi
done

echo ":: Проверка ключей pacman"
[[ -s /etc/pacman.d/gnupg/pubring.gpg || -s /etc/pacman.d/gnupg/pubring.kbx ]] || pacman-key --init
pacman-key --populate archlinux >/dev/null
pacman -Sy --noconfirm --needed archlinux-keyring

clean_cache() { # partial downloads and packages without a detached signature
	local f removed=0
	[[ -d "$CACHE_DIR" && "$(realpath "$CACHE_DIR")" != / ]] || return 0
	shopt -s nullglob
	for f in "$CACHE_DIR"/*.part "$CACHE_DIR"/download-*; do rm -rf "$f"; removed=$((removed + 1)); done
	for f in "$CACHE_DIR"/*.pkg.tar.zst "$CACHE_DIR"/*.pkg.tar.xz; do
		[[ -s "$f.sig" ]] || { rm -f "$f"; removed=$((removed + 1)); }
	done
	shopt -u nullglob
	(( removed == 0 )) || echo ":: кэш pacman: удалено $removed недокачанных или неподписанных файлов"
}
clean_cache

PROFILE="$WORK_DIR/profile"
AUR_REPO="$WORK_DIR/aur-repo"
ISO_WORK="$WORK_DIR/mkarchiso"

echo ":: Preparing profile in $PROFILE"
rm -rf "$ISO_WORK" "$PROFILE"
mkdir -p "$WORK_DIR"
cp -a "$ROOT/archiso" "$PROFILE"

echo ":: Fetching zapret + Flowseal strategies"
DEST="$PROFILE/airootfs/opt/zapret" "$ROOT/scripts/fetch-zapret.sh"

if [[ "${SKIP_AUR:-0}" != 1 ]]; then
	echo ":: Building AUR packages"
	"$ROOT/scripts/build-aur.sh" "$PROFILE/packages.aur" "$AUR_REPO"
	if [[ -s "$AUR_REPO/built.txt" ]]; then
		{
			echo
			echo "# ---------- AUR packages (built by scripts/build-aur.sh) ----------"
			cat "$AUR_REPO/built.txt"
		} >>"$PROFILE/packages.x86_64"
		cat >>"$PROFILE/pacman.conf" <<EOF

# Local repository with AUR packages, used only while building the ISO
[asos-aur]
SigLevel = Optional TrustAll
Server = file://$AUR_REPO
EOF
	fi
fi

if [[ "${SKIP_ARDUINO:-0}" != 1 ]]; then
	echo ":: Pre-installing Arduino cores and libraries"
	"$ROOT/scripts/fetch-arduino.sh" "$PROFILE/airootfs/etc/skel"
fi

echo ":: Building ISO"
LOG="$WORK_DIR/mkarchiso.log"
if ! mkarchiso -v -w "$ISO_WORK" -o "$OUT_DIR" "$PROFILE" 2>&1 | tee "$LOG"; then
	if grep -q -i -E 'signature|PGP|corrupted|invalid or corrupted package' "$LOG"; then
		echo "!! ошибка проверки подписи пакетов: обновляю ключи, чищу кэш и пробую ещё раз"
		pacman -Sy --noconfirm archlinux-keyring
		pacman-key --populate archlinux >/dev/null
		grep -o -E "[a-z0-9@._+-]+-[0-9][^ ]*\.pkg\.tar\.(zst|xz)" "$LOG" | sort -u | while read -r bad; do rm -f "$CACHE_DIR/$bad" "$CACHE_DIR/$bad.sig"; done
		clean_cache
		rm -rf "$ISO_WORK"
		mkarchiso -v -w "$ISO_WORK" -o "$OUT_DIR" "$PROFILE" 2>&1 | tee "$LOG" || {
			echo "!! сборка снова не удалась. Последние ошибки:" >&2
			grep -i -E 'error|ошибка' "$LOG" | tail -n 15 >&2
			echo "   Полный журнал: $LOG" >&2
			exit 1
		}
	else
		echo "!! mkarchiso завершился с ошибкой, журнал: $LOG" >&2
		grep -i -E 'error|ошибка' "$LOG" | tail -n 15 >&2
		exit 1
	fi
fi
rm -rf "$ISO_WORK"

cd "$OUT_DIR"
for iso in *.iso; do sha256sum "$iso" >"$iso.sha256"; done
echo ":: Done:"; ls -lh "$OUT_DIR"
