#!/bin/zsh
set -eu
PICKER_REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
PICKER_OUTPUT="${1:-/tmp/fluentkit-picker-recheck}"
PICKER_DEBUG="${FLUENTKIT_PICKER_DEBUG:-/tmp/fluentkit-repair-tests}"
PICKER_RELEASE="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
mkdir -p "$PICKER_OUTPUT"
PICKER_OUTPUT="$(cd "$PICKER_OUTPUT" && pwd)"
cd "$PICKER_REPO"
swift test --scratch-path "$PICKER_DEBUG" -Xswiftc -warnings-as-errors > "$PICKER_OUTPUT/tests.log" 2>&1
./tools/run-quality-checks.sh "$PICKER_OUTPUT/quality" > "$PICKER_OUTPUT/quality.log" 2>&1
PICKER_PRODUCTS="$(swift build -c release --scratch-path "$PICKER_RELEASE" --show-bin-path)"
PICKER_BIN="$PICKER_RELEASE/audit-tools"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$PICKER_PRODUCTS" \
    "audits/2026-10-31/picker-transactions/PickerInteractionAudit.swift" "$PICKER_PRODUCTS/FluentKit.o" \
    -o "$PICKER_BIN/PickerInteractionAudit"
"$PICKER_BIN/PickerInteractionAudit" "$PICKER_OUTPUT/visual" > "$PICKER_OUTPUT/interaction.json" 2> "$PICKER_OUTPUT/interaction.log"
PICKER_DEBUG_PRODUCTS="$(swift build --scratch-path "$PICKER_DEBUG" --show-bin-path)"
"$PICKER_DEBUG_PRODUCTS/FluentKitValidation" > "$PICKER_OUTPUT/native-validation.log" 2>&1
