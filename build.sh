#!/usr/bin/env bash
# ============================================================================
#  Build the ASOS ISO.
#
#  On Arch Linux (needs archiso):     sudo ./build.sh
#  Anywhere with Docker/Podman:       ./build.sh --docker
#
#  Env: ZAPRET_VERSION (default latest), FLOWSEAL_REF (default main),
#       OUT_DIR (default ./out), WORK_DIR (default ./work)
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
WORK_DIR="${WORK_DIR:-$ROOT/work}"

if [[ "${1:-}" == "--docker" ]]; then
	engine=$(command -v docker || command -v podman) || { echo "docker/podman not found" >&2; exit 1; }
	exec "$engine" run --rm --privileged \
		-e ZAPRET_VERSION -e FLOWSEAL_REF \
		-v "$ROOT:/build" -w /build \
		docker.io/archlinux/archlinux:latest \
		bash -c 'pacman -Syu --noconfirm --needed archiso git curl && ./build.sh'
fi

[[ $EUID -eq 0 ]] || { echo "run as root: sudo ./build.sh  (or ./build.sh --docker)" >&2; exit 1; }
command -v mkarchiso >/dev/null || { echo "mkarchiso not found: pacman -S archiso" >&2; exit 1; }

echo ":: Fetching zapret + Flowseal strategies"
"$ROOT/scripts/fetch-zapret.sh"

echo ":: Building ISO"
rm -rf "$WORK_DIR"
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$ROOT/archiso"
rm -rf "$WORK_DIR"

cd "$OUT_DIR"
for iso in *.iso; do sha256sum "$iso" >"$iso.sha256"; done
echo ":: Done:"; ls -lh "$OUT_DIR"
