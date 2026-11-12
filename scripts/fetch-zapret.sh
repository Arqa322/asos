#!/usr/bin/env bash
# Download zapret (bol-van) nfqws binary and Flowseal strategies/lists into the
# archiso airootfs (/opt/zapret). Run before mkarchiso (build.sh does it for you).
#
#   ZAPRET_VERSION   zapret release tag      (default: latest)
#   FLOWSEAL_REF     Flowseal branch or tag  (default: main)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-$ROOT/archiso/airootfs/opt/zapret}"
ZAPRET_REPO="https://github.com/bol-van/zapret"
FLOWSEAL_REPO="https://github.com/Flowseal/zapret-discord-youtube"
FLOWSEAL_REF="${FLOWSEAL_REF:-main}"

latest_tag() { # newest vX.Y[.Z] tag of a repo
	git ls-remote --tags --refs "$1" | sed 's|.*refs/tags/||' | grep -E '^v[0-9]+(\.[0-9]+)*$' | sort -V | tail -n1
}

ZAPRET_VERSION="${ZAPRET_VERSION:-$(latest_tag "$ZAPRET_REPO")}"
[[ -n "$ZAPRET_VERSION" ]] || { echo "cannot determine zapret version" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo ":: zapret $ZAPRET_VERSION"
curl -fsSL --retry 4 -o "$tmp/zapret.tar.gz" \
	"$ZAPRET_REPO/releases/download/$ZAPRET_VERSION/zapret-$ZAPRET_VERSION.tar.gz"
tar -xzf "$tmp/zapret.tar.gz" -C "$tmp" --wildcards "*/binaries/linux-x86_64/nfqws" "*/docs/LICENSE.txt" 2>/dev/null ||
	tar -xzf "$tmp/zapret.tar.gz" -C "$tmp" --wildcards "*/binaries/linux-x86_64/nfqws"

echo ":: Flowseal zapret-discord-youtube ($FLOWSEAL_REF)"
git clone -q --depth 1 --branch "$FLOWSEAL_REF" "$FLOWSEAL_REPO" "$tmp/flowseal"
fs_commit=$(git -C "$tmp/flowseal" rev-parse --short HEAD)
fs_version=$(cat "$tmp/flowseal/.service/version.txt" 2>/dev/null || echo "$FLOWSEAL_REF")

rm -rf "$DEST"
install -d "$DEST" "$DEST/flowseal/bin" "$DEST/flowseal/lists" "$DEST/flowseal/strategies"
install -m 0755 "$tmp"/zapret-*/binaries/linux-x86_64/nfqws "$DEST/nfqws"
[[ -f $(echo "$tmp"/zapret-*/docs/LICENSE.txt) ]] && install -m 0644 "$tmp"/zapret-*/docs/LICENSE.txt "$DEST/LICENSE.zapret.txt"

# fake payloads (*.bin only — WinDivert/winws Windows binaries are not needed)
install -m 0644 "$tmp"/flowseal/bin/*.bin "$DEST/flowseal/bin/"

# lists: ipset-all.txt is the "none" placeholder, the full list lives in ipset-all.txt.backup
for l in list-general.txt list-google.txt list-exclude.txt ipset-exclude.txt; do
	install -m 0644 "$tmp/flowseal/lists/$l" "$DEST/flowseal/lists/$l"
done
if [[ -s "$tmp/flowseal/lists/ipset-all.txt.backup" ]]; then
	install -m 0644 "$tmp/flowseal/lists/ipset-all.txt.backup" "$DEST/flowseal/lists/ipset-all-loaded.txt"
else
	grep -v '203.0.113.113' "$tmp/flowseal/lists/ipset-all.txt" >"$DEST/flowseal/lists/ipset-all-loaded.txt" || true
fi

# strategies: "general (FAKE TLS AUTO ALT2).bat" -> general-fake-tls-auto-alt2.bat
shopt -s nullglob
for f in "$tmp"/flowseal/general*.bat; do
	name=$(basename "$f" .bat | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
	install -m 0644 "$f" "$DEST/flowseal/strategies/$name.bat"
done
install -m 0644 "$tmp/flowseal/LICENSE.txt" "$DEST/LICENSE.flowseal.txt" 2>/dev/null || true

cat >"$DEST/VERSION" <<EOF
zapret $ZAPRET_VERSION
flowseal $fs_version ($fs_commit)
EOF
echo ":: installed to $DEST"
ls "$DEST/flowseal/strategies" | sed 's/\.bat$//' | tr "\n" " "; echo
