#!/bin/zsh
set -eu
HEADER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
HEADER_REPO="$(cd "$HEADER_AUDIT/../../.." && pwd)"
HEADER_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
HEADER_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-header-layout}"
mkdir -p "$HEADER_OUTPUT"
HEADER_OUTPUT="$(cd "$HEADER_OUTPUT" && pwd)"
cd "$HEADER_REPO"
swift build --target FluentKit -c release --scratch-path "$HEADER_BUILD" -Xswiftc -warnings-as-errors
HEADER_PRODUCTS="$(swift build -c release --scratch-path "$HEADER_BUILD" --show-bin-path)"
HEADER_BIN="$HEADER_BUILD/audit-tools"
mkdir -p "$HEADER_BIN"
if [ -d "$HEADER_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$HEADER_PRODUCTS/FluentKit_FluentKit.bundle" "$HEADER_BIN/"
fi
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$HEADER_PRODUCTS" \
    "$HEADER_AUDIT/HeaderLayoutAudit.swift" "$HEADER_PRODUCTS/FluentKit.o" -o "$HEADER_BIN/HeaderLayoutAudit"
"$HEADER_BIN/HeaderLayoutAudit" "$HEADER_OUTPUT/images" \
    > "$HEADER_OUTPUT/results.json" 2> "$HEADER_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$HEADER_OUTPUT/render.log"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$HEADER_PRODUCTS" \
    "$HEADER_AUDIT/HeaderTemplateAudit.swift" "$HEADER_PRODUCTS/FluentKit.o" -o "$HEADER_BIN/HeaderTemplateAudit"
"$HEADER_BIN/HeaderTemplateAudit" "$HEADER_OUTPUT/images" \
    > "$HEADER_OUTPUT/templates.json" 2> "$HEADER_OUTPUT/templates.log"
python3 tools/check_test_diagnostics.py "$HEADER_OUTPUT/templates.log"
python3 "$HEADER_AUDIT/check_results.py" "$HEADER_OUTPUT/results.json" "$HEADER_OUTPUT/templates.json"
