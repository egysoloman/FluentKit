#!/bin/zsh
set -eu
SCREEN_AUDIT="$(cd "$(dirname "$0")" && pwd)"
SCREEN_PRODUCTS="${1:?Provide SwiftPM products directory}"
SCREEN_OUTPUT="${2:?Provide a new output directory}"
if [ -e "$SCREEN_OUTPUT/results.json" ]; then exit 1; fi
mkdir -p "$SCREEN_OUTPUT/images"
SCREEN_OUTPUT="$(cd "$SCREEN_OUTPUT" && pwd)"
SCREEN_MODULES="$SCREEN_PRODUCTS"
SCREEN_OBJECTS=("$SCREEN_PRODUCTS/FluentKit.o")
if [ ! -f "${SCREEN_OBJECTS[1]}" ]; then
    SCREEN_MODULES="$SCREEN_PRODUCTS/Modules"
    SCREEN_OBJECTS=("$SCREEN_PRODUCTS"/FluentKit.build/*.o(N))
fi
if [ "${#SCREEN_OBJECTS[@]}" -eq 0 ]; then exit 1; fi
SCREEN_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-screen-audit.XXXXXX")"
cp -R "$SCREEN_PRODUCTS/FluentKit_FluentKit.bundle" "$SCREEN_BIN/"
shasum -a 256 "$SCREEN_AUDIT/MenuWorkAreaAudit.swift" "${SCREEN_OBJECTS[@]}" > "$SCREEN_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SCREEN_MODULES" \
    "$SCREEN_AUDIT/MenuWorkAreaAudit.swift" "${SCREEN_OBJECTS[@]}" -o "$SCREEN_BIN/Probe"
"$SCREEN_BIN/Probe" "$SCREEN_OUTPUT/images" > "$SCREEN_OUTPUT/results.json" 2> "$SCREEN_OUTPUT/render.log"
