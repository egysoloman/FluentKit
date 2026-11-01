#!/bin/zsh
set -eu
TOGGLE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
TOGGLE_PRODUCTS="${1:?Provide SwiftPM products directory}"
TOGGLE_OUTPUT="${2:?Provide a new output directory}"
TOGGLE_MODULES="$TOGGLE_PRODUCTS"
TOGGLE_OBJECTS=("$TOGGLE_PRODUCTS/FluentKit.o")
if [ ! -f "${TOGGLE_OBJECTS[1]}" ]; then
    TOGGLE_MODULES="$TOGGLE_PRODUCTS/Modules"
    TOGGLE_OBJECTS=("$TOGGLE_PRODUCTS"/FluentKit.build/*.o(N))
fi
if [ "${#TOGGLE_OBJECTS[@]}" -eq 0 ]; then
    echo "No FluentKit objects found" >&2
    exit 1
fi
mkdir -p "$TOGGLE_OUTPUT"
TOGGLE_OUTPUT="$(cd "$TOGGLE_OUTPUT" && pwd)"
TOGGLE_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-toggle-events.XXXXXX")"
if [ -d "$TOGGLE_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$TOGGLE_PRODUCTS/FluentKit_FluentKit.bundle" "$TOGGLE_BIN/"
fi
shasum -a 256 "$TOGGLE_AUDIT/KeyboardEventProbe.swift" "${TOGGLE_OBJECTS[@]}" > "$TOGGLE_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TOGGLE_MODULES" \
    "$TOGGLE_AUDIT/KeyboardEventProbe.swift" "${TOGGLE_OBJECTS[@]}" -o "$TOGGLE_BIN/Probe"
"$TOGGLE_BIN/Probe" > "$TOGGLE_OUTPUT/events.json" 2> "$TOGGLE_OUTPUT/events.log"
