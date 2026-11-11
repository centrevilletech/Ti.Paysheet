#!/usr/bin/env bash
# Build the module and drop the distributable zips in dist/.
#
#   ./build.sh            # Android, plus iOS when run on macOS
#   ./build.sh android    # one platform
#   ./build.sh ios
#
# Requires the Titanium CLI and SDK 13.4+; Android needs an Android SDK and NDK, iOS needs Xcode and network access (Swift Package).
# The Ti CLI refuses to build a module that sits inside an app project, so this builds from a temp copy.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ $# -gt 0 ]; then
	PLATFORMS=("$@")
elif [ "$(uname)" = Darwin ]; then
	PLATFORMS=(android ios)
else
	PLATFORMS=(android)
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$SRC/dist"
for platform in "${PLATFORMS[@]}"; do
	rsync -a --exclude build --exclude dist --exclude libs --exclude metadata.json "$SRC/$platform/" "$TMP/$platform/"
	cp "$SRC/LICENSE" "$TMP/$platform/LICENSE"   # packaged into the zip
	mkdir -p "$TMP/$platform/assets"
	cp "$SRC/assets/ti.paysheet.js" "$TMP/$platform/assets/"   # shared JavaScript layer, merged into the module
	(cd "$TMP/$platform" && ti build -p "$platform" --build-only)
	cp "$TMP/$platform"/dist/*.zip "$SRC/dist/"
done
ls "$SRC"/dist/*.zip
