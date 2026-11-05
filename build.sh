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
mkarchiso -v -w "$ISO_WORK" -o "$OUT_DIR" "$PROFILE"
rm -rf "$ISO_WORK"

cd "$OUT_DIR"
for iso in *.iso; do sha256sum "$iso" >"$iso.sha256"; done
echo ":: Done:"; ls -lh "$OUT_DIR"
