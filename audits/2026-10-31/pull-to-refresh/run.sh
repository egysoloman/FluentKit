#!/bin/zsh
set -eu
SWIPE_REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SWIPE_OUTPUT="${1:-/tmp/fluentkit-ptr-recheck}"
SWIPE_DEBUG="${FLUENTKIT_SWIPE_DEBUG:-/tmp/fluentkit-repair-tests}"
SWIPE_RELEASE="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
mkdir -p "$SWIPE_OUTPUT"
SWIPE_OUTPUT="$(cd "$SWIPE_OUTPUT" && pwd)"
cd "$SWIPE_REPO"
swift test --scratch-path "$SWIPE_DEBUG" -Xswiftc -warnings-as-errors > "$SWIPE_OUTPUT/tests.log" 2>&1
./tools/run-quality-checks.sh "$SWIPE_OUTPUT/quality" > "$SWIPE_OUTPUT/quality.log" 2>&1
SWIPE_PRODUCTS="$(swift build -c release --scratch-path "$SWIPE_RELEASE" --show-bin-path)"
SWIPE_BIN="$SWIPE_RELEASE/audit-tools"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SWIPE_PRODUCTS" \
    "audits/2026-10-31/pull-to-refresh/RefreshVisualAudit.swift" "$SWIPE_PRODUCTS/FluentKit.o" \
    -o "$SWIPE_BIN/RefreshVisualAudit"
"$SWIPE_BIN/RefreshVisualAudit" "$SWIPE_OUTPUT/visual" > "$SWIPE_OUTPUT/visual.json" 2> "$SWIPE_OUTPUT/visual.log"
SWIPE_DEBUG_PRODUCTS="$(swift build --scratch-path "$SWIPE_DEBUG" --show-bin-path)"
"$SWIPE_DEBUG_PRODUCTS/FluentKitValidation" > "$SWIPE_OUTPUT/native-validation.log" 2>&1
