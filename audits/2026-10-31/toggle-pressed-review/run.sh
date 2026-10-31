#!/bin/zsh
set -eu
TOGGLE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
TOGGLE_REPO="$(cd "$TOGGLE_AUDIT/../../.." && pwd)"
TOGGLE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
TOGGLE_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-toggle-review}"
mkdir -p "$TOGGLE_OUTPUT"
TOGGLE_OUTPUT="$(cd "$TOGGLE_OUTPUT" && pwd)"
cd "$TOGGLE_REPO"
swift build --target FluentKit -c release --scratch-path "$TOGGLE_BUILD" -Xswiftc -warnings-as-errors
TOGGLE_PRODUCTS="$(swift build -c release --scratch-path "$TOGGLE_BUILD" --show-bin-path)"
TOGGLE_BIN="$TOGGLE_BUILD/audit-tools"
mkdir -p "$TOGGLE_BIN"
cp -R "$TOGGLE_PRODUCTS/FluentKit_FluentKit.bundle" "$TOGGLE_BIN/"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TOGGLE_PRODUCTS" "$TOGGLE_AUDIT/ToggleStateAudit.swift" "$TOGGLE_PRODUCTS/FluentKit.o" -o "$TOGGLE_BIN/ToggleStateAudit"
"$TOGGLE_BIN/ToggleStateAudit" "$TOGGLE_OUTPUT" > "$TOGGLE_OUTPUT/metrics.json" 2> "$TOGGLE_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$TOGGLE_OUTPUT/render.log"
