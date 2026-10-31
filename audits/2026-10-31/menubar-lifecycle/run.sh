#!/bin/zsh
set -eu
MENU_AUDIT="$(cd "$(dirname "$0")" && pwd)"
MENU_REPO="$(cd "$MENU_AUDIT/../../.." && pwd)"
MENU_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
MENU_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-menu-lifecycle}"
mkdir -p "$MENU_OUTPUT"
MENU_OUTPUT="$(cd "$MENU_OUTPUT" && pwd)"
cd "$MENU_REPO"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$MENU_BUILD" -Xswiftc -warnings-as-errors
fi
MENU_PRODUCTS="$(swift build -c release --scratch-path "$MENU_BUILD" --show-bin-path)"
MENU_BIN="$MENU_BUILD/audit-tools"
mkdir -p "$MENU_BIN"
cp -R "$MENU_PRODUCTS/FluentKit_FluentKit.bundle" "$MENU_BIN/"
shasum -a 256 "$MENU_PRODUCTS/FluentKit.o" > "$MENU_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$MENU_PRODUCTS" \
    "$MENU_AUDIT/MenuLifecycleAudit.swift" "$MENU_PRODUCTS/FluentKit.o" -o "$MENU_BIN/MenuLifecycleAudit"
"$MENU_BIN/MenuLifecycleAudit" "$MENU_OUTPUT/images" > "$MENU_OUTPUT/results.json" 2> "$MENU_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$MENU_OUTPUT/render.log"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    python3 "$MENU_AUDIT/check_results.py" "$MENU_OUTPUT/results.json"
fi
