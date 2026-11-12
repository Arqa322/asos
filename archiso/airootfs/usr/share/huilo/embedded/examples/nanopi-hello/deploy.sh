#!/usr/bin/env bash
# Build for aarch64, test in qemu, copy to the board and run it there.
#   ./deploy.sh pi@nanopi.local
set -euo pipefail
cd "$(dirname "$0")"
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=/usr/share/huilo/embedded/aarch64-linux-gnu.cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build
echo ":: test run in qemu"
qemu-aarch64-static -L /usr/aarch64-linux-gnu build/hello
if [[ -n "${1:-}" ]]; then
	echo ":: deploy to $1"
	scp build/hello "$1":/tmp/hello
	ssh "$1" /tmp/hello
fi
