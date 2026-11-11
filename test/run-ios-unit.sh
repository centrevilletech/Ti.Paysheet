#!/usr/bin/env bash
# Argument validation and result mapping (PaysheetOptions.swift, PaysheetResults.swift) against test/vectors.json.
# macOS with Xcode (swiftc).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/ios"
rm -rf "$OUT" && mkdir -p "$OUT"
swiftc -O -o "$OUT/vectors" "$HERE/../ios/Classes/PaysheetOptions.swift" "$HERE/../ios/Classes/PaysheetResults.swift" \
	"$HERE/ios/main.swift"
"$OUT/vectors" "$HERE/vectors.json"
swiftc -O -o "$OUT/lifecycle" "$HERE/../ios/Classes/PaysheetPresentations.swift" "$HERE/../ios/Classes/PaysheetResults.swift" \
	"$HERE/ios/lifecycle/main.swift"
"$OUT/lifecycle"
