#!/bin/zsh
set -eu
FLIP_AUDIT="$(cd "$(dirname "$0")" && pwd)"
FLIP_REPO="$(cd "$FLIP_AUDIT/../../.." && pwd)"
FLIP_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
FLIP_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-flip-audit}"
mkdir -p "$FLIP_OUTPUT"
FLIP_OUTPUT="$(cd "$FLIP_OUTPUT" && pwd)"
cd "$FLIP_REPO"
swift build --target FluentKit -c release --scratch-path "$FLIP_BUILD" -Xswiftc -warnings-as-errors
FLIP_PRODUCTS="$(swift build -c release --scratch-path "$FLIP_BUILD" --show-bin-path)"
FLIP_BIN="$FLIP_BUILD/audit-tools"
mkdir -p "$FLIP_BIN"
cp -R "$FLIP_PRODUCTS/FluentKit_FluentKit.bundle" "$FLIP_BIN/"
shasum -a 256 "$FLIP_PRODUCTS/FluentKit.o" > "$FLIP_OUTPUT/library-sha256.txt"
for FLIP_CASE in PerformanceAudit VisualAudit; do
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$FLIP_PRODUCTS" \
        "$FLIP_AUDIT/$FLIP_CASE.swift" "$FLIP_PRODUCTS/FluentKit.o" -o "$FLIP_BIN/Flip$FLIP_CASE"
    "$FLIP_BIN/Flip$FLIP_CASE" "$FLIP_OUTPUT/images" > "$FLIP_OUTPUT/$FLIP_CASE.json" 2> "$FLIP_OUTPUT/$FLIP_CASE.log"
    python3 tools/check_test_diagnostics.py "$FLIP_OUTPUT/$FLIP_CASE.log"
done
python3 "$FLIP_AUDIT/check_results.py" "$FLIP_OUTPUT"
