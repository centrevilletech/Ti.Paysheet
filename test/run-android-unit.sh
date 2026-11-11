#!/usr/bin/env bash
# Argument validation and result mapping (Options.java, Results.java) against test/vectors.json, on a plain JVM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build/android"
rm -rf "$OUT" && mkdir -p "$OUT"
SRC="$HERE/../android/src/ti/paysheet"
javac -d "$OUT" "$SRC/Options.java" "$SRC/Results.java" "$SRC/Presentations.java" "$SRC/SecretRequest.java" \
	"$HERE/android/VectorsTest.java" "$HERE/android/PresentationsTest.java"
java -cp "$OUT" ti.paysheet.VectorsTest "$HERE/vectors.json"
java -cp "$OUT" ti.paysheet.PresentationsTest
