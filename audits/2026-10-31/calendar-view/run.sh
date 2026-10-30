#!/bin/zsh
set -eu
CALENDAR_REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
CALENDAR_OUTPUT="${1:-/tmp/fluentkit-calendar-recheck}"
CALENDAR_DEBUG="${FLUENTKIT_CALENDAR_DEBUG:-/tmp/fluentkit-repair-tests}"
CALENDAR_RELEASE="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
mkdir -p "$CALENDAR_OUTPUT"
CALENDAR_OUTPUT="$(cd "$CALENDAR_OUTPUT" && pwd)"
cd "$CALENDAR_REPO"
swift test --scratch-path "$CALENDAR_DEBUG" -Xswiftc -warnings-as-errors > "$CALENDAR_OUTPUT/tests.log" 2>&1
./tools/run-quality-checks.sh "$CALENDAR_OUTPUT/quality" > "$CALENDAR_OUTPUT/quality.log" 2>&1
CALENDAR_PRODUCTS="$(swift build -c release --scratch-path "$CALENDAR_RELEASE" --show-bin-path)"
CALENDAR_BIN="$CALENDAR_RELEASE/audit-tools"
for CALENDAR_PROBE in CalendarViewVisualAudit CalendarDatePickerPopoverAudit; do
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CALENDAR_PRODUCTS" \
        "audits/2026-10-31/calendar-view/$CALENDAR_PROBE.swift" "$CALENDAR_PRODUCTS/FluentKit.o" \
        -o "$CALENDAR_BIN/$CALENDAR_PROBE"
done
"$CALENDAR_BIN/CalendarViewVisualAudit" "$CALENDAR_OUTPUT/visual" > "$CALENDAR_OUTPUT/visual.json" 2> "$CALENDAR_OUTPUT/visual.log"
"$CALENDAR_BIN/CalendarDatePickerPopoverAudit" "$CALENDAR_OUTPUT/popover.png" > "$CALENDAR_OUTPUT/popover.log" 2>&1
CALENDAR_DEBUG_PRODUCTS="$(swift build --scratch-path "$CALENDAR_DEBUG" --show-bin-path)"
"$CALENDAR_DEBUG_PRODUCTS/FluentKitValidation" > "$CALENDAR_OUTPUT/native-validation.log" 2>&1
