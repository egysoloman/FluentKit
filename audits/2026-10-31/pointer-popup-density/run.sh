#!/bin/zsh
set -eu
DENSITY_AUDIT="$(cd "$(dirname "$0")" && pwd)"
DENSITY_REPO="$(cd "$DENSITY_AUDIT/../../.." && pwd)"
DENSITY_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
DENSITY_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-density-audit}"
mkdir -p "$DENSITY_OUTPUT"
DENSITY_OUTPUT="$(cd "$DENSITY_OUTPUT" && pwd)"
cd "$DENSITY_REPO"
swift build --target FluentKit -c release --scratch-path "$DENSITY_BUILD" -Xswiftc -warnings-as-errors
DENSITY_PRODUCTS="$(swift build -c release --scratch-path "$DENSITY_BUILD" --show-bin-path)"
DENSITY_BIN="$DENSITY_BUILD/audit-tools"
mkdir -p "$DENSITY_BIN"
cp -R "$DENSITY_PRODUCTS/FluentKit_FluentKit.bundle" "$DENSITY_BIN/"
shasum -a 256 "$DENSITY_PRODUCTS/FluentKit.o" > "$DENSITY_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$DENSITY_PRODUCTS" "$DENSITY_AUDIT/PopupDensityAudit.swift" "$DENSITY_PRODUCTS/FluentKit.o" -o "$DENSITY_BIN/PopupDensityAudit"
"$DENSITY_BIN/PopupDensityAudit" "$DENSITY_OUTPUT/images" > "$DENSITY_OUTPUT/metrics.json" 2> "$DENSITY_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$DENSITY_OUTPUT/render.log"
python3 "$DENSITY_AUDIT/check_results.py" "$DENSITY_OUTPUT"
