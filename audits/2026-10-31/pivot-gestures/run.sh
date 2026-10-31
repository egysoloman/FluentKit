#!/bin/zsh
set -eu
PIVOT_REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
PIVOT_OUTPUT="${1:-/tmp/fluentkit-pivot-gesture-recheck}"
PIVOT_DEBUG="${FLUENTKIT_PIVOT_DEBUG:-/tmp/fluentkit-repair-tests}"
PIVOT_RELEASE="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
mkdir -p "$PIVOT_OUTPUT"
PIVOT_OUTPUT="$(cd "$PIVOT_OUTPUT" && pwd)"
cd "$PIVOT_REPO"
swift test --scratch-path "$PIVOT_DEBUG" -Xswiftc -warnings-as-errors > "$PIVOT_OUTPUT/tests.log" 2>&1
./tools/run-quality-checks.sh "$PIVOT_OUTPUT/quality" > "$PIVOT_OUTPUT/quality.log" 2>&1
PIVOT_PRODUCTS="$(swift build -c release --scratch-path "$PIVOT_RELEASE" --show-bin-path)"
PIVOT_BIN="$PIVOT_RELEASE/audit-tools"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$PIVOT_PRODUCTS" \
    "audits/2026-10-31/pivot-gestures/PivotGestureAudit.swift" "$PIVOT_PRODUCTS/FluentKit.o" \
    -o "$PIVOT_BIN/PivotGestureAudit"
"$PIVOT_BIN/PivotGestureAudit" "$PIVOT_OUTPUT/visual" > "$PIVOT_OUTPUT/visual.json" 2> "$PIVOT_OUTPUT/visual.log"
PIVOT_DEBUG_PRODUCTS="$(swift build --scratch-path "$PIVOT_DEBUG" --show-bin-path)"
"$PIVOT_DEBUG_PRODUCTS/FluentKitValidation" > "$PIVOT_OUTPUT/native-validation.log" 2>&1
