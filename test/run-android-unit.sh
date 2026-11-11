#!/usr/bin/env bash
# Argument validation and result mapping (Options.java, Results.java) against test/vectors.json, on a plain JVM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/android"
rm -rf "$OUT" && mkdir -p "$OUT"
javac -d "$OUT" "$HERE/../android/src/ti/paysheet/Options.java" "$HERE/../android/src/ti/paysheet/Results.java" \
	"$HERE/android/VectorsTest.java"
java -cp "$OUT" ti.paysheet.VectorsTest "$HERE/vectors.json"
