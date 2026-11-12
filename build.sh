#!/usr/bin/env bash
# ============================================================================
#  Build the Huilo ISO.
#
#  On Arch Linux (needs archiso):     sudo ./build.sh [options]
#  Anywhere with Docker/Podman:       ./build.sh --docker [options]
#
#  Options:
#    --without GROUPS   leave optional groups out (comma separated), e.g.
#                       --without office,games,sysadmin
#    --minimal          core system only (Hyprland desktop, browser, CLI)
#    --list-groups      show the optional groups
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
#    HUILO_WITHOUT     same as --without
#    SKIP_AUR=1       do not build AUR packages
#    SKIP_ARDUINO=1   do not pre-install Arduino cores/libraries
#    OUT_DIR          default ./out
#    WORK_DIR         default ./work   (both may be on another disk, also with --docker)
#    PKG_CACHE        --docker only: host folder for the pacman package cache
#                     (keeps ~6 GB of downloads between builds / off the system disk)
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
WORK_DIR="${WORK_DIR:-$ROOT/work}"

WITHOUT="${HUILO_WITHOUT:-${ASOS_WITHOUT:-}}"   # ASOS_WITHOUT: the name before the rename (legacy)
DOCKER=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--docker) DOCKER=1 ;;
		--without) WITHOUT+=" ${2:?--without needs a list of groups}"; shift ;;
		--without=*) WITHOUT+=" ${1#*=}" ;;
		--minimal) WITHOUT+=" minimal" ;;
		--list-groups) echo "Необязательные группы (./build.sh --without группа1,группа2):"; "$ROOT/scripts/pkg-select.sh" --list-groups; exit 0 ;;
		-h|--help) sed -n '2,30p' "$0"; exit 0 ;;
		*) echo "unknown option: $1 (see ./build.sh --help)" >&2; exit 1 ;;
	esac
	shift
done
EXCLUDED=$("$ROOT/scripts/pkg-select.sh" --resolve "$WITHOUT") || exit 2
excluded() { grep -qx "$1" <<<"$EXCLUDED"; }
[[ -z "$EXCLUDED" ]] || echo ":: без групп: $(tr '\n' ' ' <<<"$EXCLUDED")"

if [[ $DOCKER == 1 ]]; then
	engine=$(command -v docker || command -v podman) || { echo "docker/podman not found" >&2; exit 1; }
	# work/out/cache folders outside the repository are mounted at the paths the
	# build inside the container uses
	mounts=(-v "$ROOT:/build")
	mkdir -p "$WORK_DIR" "$OUT_DIR"
	[[ "$(realpath -m "$WORK_DIR")" == "$(realpath -m "$ROOT/work")" ]] || mounts+=(-v "$(realpath "$WORK_DIR"):/build/work")
	[[ "$(realpath -m "$OUT_DIR")" == "$(realpath -m "$ROOT/out")" ]] || mounts+=(-v "$(realpath "$OUT_DIR"):/build/out")
	if [[ -n "${PKG_CACHE:-}" ]]; then mkdir -p "$PKG_CACHE"; mounts+=(-v "$(realpath "$PKG_CACHE"):/var/cache/pacman/pkg"); fi
	exec "$engine" run --rm --privileged \
		-e ZAPRET_VERSION -e FLOWSEAL_REF -e ARDUINO_CORES -e ARDUINO_LIBS -e NEED_GB -e IGNORE_SPACE \
		-e SKIP_AUR -e SKIP_ARDUINO -e HUILO_IN_CONTAINER=1 -e HUILO_WITHOUT="$(tr '\n' ' ' <<<"$EXCLUDED")" \
		"${mounts[@]}" -w /build \
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
# --populate signs the Arch keys with the local master key: a keyring without a
# secret key (fresh containers ship one) must be initialised first
if ! gpg --homedir /etc/pacman.d/gnupg --list-secret-keys 2>/dev/null | grep -q '^sec'; then
	pacman-key --init
fi
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

# optional groups: mkarchiso gets the filtered plain lists; the full tagged lists
# and the selector go into the image so huilo-install can remove groups later
"$ROOT/scripts/pkg-select.sh" "$ROOT/archiso/packages.x86_64" --without "$EXCLUDED" >"$PROFILE/packages.x86_64"
"$ROOT/scripts/pkg-select.sh" "$ROOT/archiso/packages.aur" --without "$EXCLUDED" >"$PROFILE/packages.aur"
install -Dm0644 "$ROOT/archiso/packages.x86_64" "$PROFILE/airootfs/usr/share/huilo/packages.x86_64"
install -Dm0755 "$ROOT/scripts/pkg-select.sh" "$PROFILE/airootfs/usr/share/huilo/pkg-select.sh"
install -Dm0755 "$ROOT/scripts/fetch-zapret.sh" "$PROFILE/airootfs/usr/share/huilo/fetch-zapret.sh"
{
	echo "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%MZ)"
	echo "GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
	echo "EXCLUDED_GROUPS=\"$(tr '\n' ' ' <<<"$EXCLUDED" | xargs)\""
} >"$PROFILE/airootfs/usr/share/huilo/build-info"
echo ":: пакетов в образе: $(wc -l <"$PROFILE/packages.x86_64") (+ AUR: $(wc -l <"$PROFILE/packages.aur"))"

if excluded zapret; then
	echo ":: zapret отключён (--without zapret)"
	rm -f "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/zapret.service"
else
	echo ":: Fetching zapret + Flowseal strategies"
	DEST="$PROFILE/airootfs/opt/zapret" "$ROOT/scripts/fetch-zapret.sh"
fi

if [[ "${SKIP_AUR:-0}" != 1 && -s "$PROFILE/packages.aur" ]]; then
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
[huilo-aur]
SigLevel = Optional TrustAll
Server = file://$AUR_REPO
EOF
	fi
fi

if [[ "${SKIP_ARDUINO:-0}" != 1 ]] && ! excluded arduino; then
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
