#!/usr/bin/env bash
# ============================================================================
#  Build the AUR packages listed in archiso/packages.aur into a local pacman
#  repository that mkarchiso can install from.
#
#  usage: build-aur.sh <list-file> <repo-dir>
#
#  - makepkg never runs as root: inside the build container a throw-away
#    "asosbuild" user is created; on a real Arch host the user who called
#    sudo ($SUDO_USER) is used.
#  - A package that fails to build is skipped and reported; the names of the
#    packages that were built go to <repo-dir>/built.txt.
# ============================================================================
set -uo pipefail

LIST=${1:?usage: build-aur.sh <list-file> <repo-dir>}
REPO=${2:?usage: build-aur.sh <list-file> <repo-dir>}
REPO_NAME=asos-aur
AUR_URL=${AUR_URL:-https://aur.archlinux.org}

[[ $EUID -eq 0 ]] || { echo "build-aur.sh must run as root" >&2; exit 1; }
mkdir -p "$REPO"
REPO=$(realpath "$REPO")
BUILD_ROOT=$(mktemp -d /var/tmp/asos-aur.XXXXXX)
trap 'rm -rf "$BUILD_ROOT"' EXIT

in_container() { [[ -f /.dockerenv || -f /run/.containerenv || "${ASOS_IN_CONTAINER:-0}" == 1 ]]; }

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
	BUILDER=$SUDO_USER
elif in_container; then
	BUILDER=asosbuild
	id "$BUILDER" &>/dev/null || useradd -m -r -s /bin/bash "$BUILDER"
	echo "$BUILDER ALL=(ALL) NOPASSWD: /usr/bin/pacman" >/etc/sudoers.d/90-asosbuild
	chmod 0440 /etc/sudoers.d/90-asosbuild
else
	echo "Run via 'sudo ./build.sh' from a normal user, or use './build.sh --docker'." >&2
	exit 1
fi
chown "$BUILDER" "$BUILD_ROOT"

as_builder() { sudo -u "$BUILDER" -H -- "$@"; }

built=() failed=()
while read -r pkg <&3; do
	pkg=${pkg%%#*}; pkg=${pkg//[[:space:]]/}
	[[ -n "$pkg" ]] || continue
	echo ":: AUR: building $pkg"
	if as_builder git clone -q --depth 1 "$AUR_URL/$pkg.git" "$BUILD_ROOT/$pkg" &&
		[[ -f "$BUILD_ROOT/$pkg/PKGBUILD" ]] &&
		(cd "$BUILD_ROOT/$pkg" && as_builder env PKGDEST="$BUILD_ROOT/$pkg/out" \
			makepkg --syncdeps --noconfirm --needed --clean --cleanbuild --nocheck); then
		cp -f "$BUILD_ROOT/$pkg"/out/*.pkg.tar.* "$REPO/"
		# a split PKGBUILD may produce several packages; record the requested one
		built+=("$pkg")
		# inside the throw-away build container make it available as a
		# dependency for the following AUR packages (never touch a real host)
		if in_container; then
			pacman -U --noconfirm --needed "$BUILD_ROOT/$pkg"/out/*.pkg.tar.* >/dev/null || true
		fi
	else
		echo "!! AUR: $pkg failed to build — skipped" >&2
		failed+=("$pkg")
	fi
done 3<"$LIST"

shopt -s nullglob
pkgfiles=("$REPO"/*.pkg.tar.zst "$REPO"/*.pkg.tar.xz)
rm -f "$REPO/$REPO_NAME".db* "$REPO/$REPO_NAME".files*
if [[ ${#pkgfiles[@]} -gt 0 ]]; then
	repo-add -q "$REPO/$REPO_NAME.db.tar.gz" "${pkgfiles[@]}"
else
	# empty but valid repository so pacman.conf stays usable
	repo-add -q "$REPO/$REPO_NAME.db.tar.gz"
fi
printf '%s\n' "${built[@]}" >"$REPO/built.txt"
chmod -R a+rX "$REPO"

echo ":: AUR built:  ${built[*]:-none}"
[[ ${#failed[@]} -eq 0 ]] || echo "!! AUR failed: ${failed[*]}" >&2
exit 0
