#!/usr/bin/env bash
# Build the example app against the module zips in ../dist (run ../build.sh first).
#
#   ./build.sh android     # -> app/build/android/app/build/outputs/apk/debug/app-debug.apk
#   ./build.sh ios         # simulator build (macOS) -> app/build/iphone/build/Products/Debug-iphonesimulator/*.app
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="${1:?android or ios}"
ZIP_PLATFORM="$PLATFORM"; [ "$PLATFORM" = ios ] && ZIP_PLATFORM=iphone
rm -rf "$HERE/app/modules/$ZIP_PLATFORM"
unzip -q -o "$HERE"/../dist/ti.paysheet-"$ZIP_PLATFORM"-*.zip -d "$HERE/app"
cd "$HERE/app"
if [ "$PLATFORM" = android ]; then
	ti build -p android -T emulator --build-only --no-prompt
else
	ti build -p ios -T simulator --build-only --no-prompt
fi
