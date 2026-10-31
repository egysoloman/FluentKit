#!/bin/zsh
set -eu
CALENDAR_SCROLL_AUDIT="$(cd "$(dirname "$0")" && pwd)"
CALENDAR_SCROLL_REPO="$(cd "$CALENDAR_SCROLL_AUDIT/../../.." && pwd)"
CALENDAR_SCROLL_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
CALENDAR_SCROLL_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-calendar-scrolling}"
mkdir -p "$CALENDAR_SCROLL_OUTPUT"
CALENDAR_SCROLL_OUTPUT="$(cd "$CALENDAR_SCROLL_OUTPUT" && pwd)"
cd "$CALENDAR_SCROLL_REPO"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$CALENDAR_SCROLL_BUILD" -Xswiftc -warnings-as-errors
fi
CALENDAR_SCROLL_PRODUCTS="$(swift build -c release --scratch-path "$CALENDAR_SCROLL_BUILD" --show-bin-path)"
CALENDAR_SCROLL_BIN="$CALENDAR_SCROLL_BUILD/audit-tools"
mkdir -p "$CALENDAR_SCROLL_BIN"
cp -R "$CALENDAR_SCROLL_PRODUCTS/FluentKit_FluentKit.bundle" "$CALENDAR_SCROLL_BIN/"
shasum -a 256 "$CALENDAR_SCROLL_PRODUCTS/FluentKit.o" > "$CALENDAR_SCROLL_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CALENDAR_SCROLL_PRODUCTS" \
    "$CALENDAR_SCROLL_AUDIT/CalendarScrollingAudit.swift" "$CALENDAR_SCROLL_PRODUCTS/FluentKit.o" -o "$CALENDAR_SCROLL_BIN/CalendarScrollingAudit"
"$CALENDAR_SCROLL_BIN/CalendarScrollingAudit" "$CALENDAR_SCROLL_OUTPUT/images" > "$CALENDAR_SCROLL_OUTPUT/results.json" 2> "$CALENDAR_SCROLL_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$CALENDAR_SCROLL_OUTPUT/render.log"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    python3 "$CALENDAR_SCROLL_AUDIT/check_results.py" "$CALENDAR_SCROLL_OUTPUT/results.json"
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CALENDAR_SCROLL_PRODUCTS" \
        "$CALENDAR_SCROLL_AUDIT/CalendarDatePickerScrollingAudit.swift" "$CALENDAR_SCROLL_PRODUCTS/FluentKit.o" \
        -o "$CALENDAR_SCROLL_BIN/CalendarDatePickerScrollingAudit"
    "$CALENDAR_SCROLL_BIN/CalendarDatePickerScrollingAudit" "$CALENDAR_SCROLL_OUTPUT/images" > "$CALENDAR_SCROLL_OUTPUT/popover.log" 2>&1
    python3 tools/check_test_diagnostics.py "$CALENDAR_SCROLL_OUTPUT/popover.log"
fi
