#!/bin/zsh
set -eu
MENU_AUDIT="$(cd "$(dirname "$0")" && pwd)"
MENU_PRODUCTS="${1:?Provide Swift Build Release products directory}"
MENU_OUTPUT="${2:?Provide a new output directory}"
mkdir -p "$MENU_OUTPUT"
if [ -e "$MENU_OUTPUT/menu.json" ]; then exit 1; fi
MENU_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-search-menu.XXXXXX")"
cp -R "$MENU_PRODUCTS/FluentKit_FluentKit.bundle" "$MENU_BIN/"
shasum -a 256 "$MENU_AUDIT/SearchMenuAudit.swift" "$MENU_PRODUCTS/FluentKit.o" > "$MENU_OUTPUT/menu-source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$MENU_PRODUCTS" \
    "$MENU_AUDIT/SearchMenuAudit.swift" "$MENU_PRODUCTS/FluentKit.o" -o "$MENU_BIN/SearchMenuAudit"
"$MENU_BIN/SearchMenuAudit" > "$MENU_OUTPUT/menu.json" 2> "$MENU_OUTPUT/menu.log"
