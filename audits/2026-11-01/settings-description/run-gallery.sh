#!/bin/zsh
set -eu
EXPANDER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$EXPANDER_AUDIT/../../.."
EXPANDER_PRODUCTS="${1:?Provide the SwiftPM products directory}"
EXPANDER_OUTPUT="${2:?Provide a new output directory}"
if [ -e "$EXPANDER_OUTPUT/results.json" ]; then
    echo "Choose a new output directory; audit evidence already exists" >&2
    exit 1
fi
EXPANDER_MODULES="$EXPANDER_PRODUCTS"
EXPANDER_OBJECTS=("$EXPANDER_PRODUCTS/FluentKit.o")
if [ ! -f "${EXPANDER_OBJECTS[1]}" ]; then
    EXPANDER_MODULES="$EXPANDER_PRODUCTS/Modules"
    EXPANDER_OBJECTS=("$EXPANDER_PRODUCTS"/FluentKit.build/*.o(N))
fi
if [ "${#EXPANDER_OBJECTS[@]}" -eq 0 ]; then
    echo "No FluentKit objects found" >&2
    exit 1
fi
EXPANDER_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-settings-description-gallery.XXXXXX")"
mkdir -p "$EXPANDER_BIN" "$EXPANDER_OUTPUT/images"
EXPANDER_OUTPUT="$(cd "$EXPANDER_OUTPUT" && pwd)"
EXPANDER_SOURCES=(FluentKitGallery/FluentKitGallery/*.swift)
EXPANDER_SOURCES=(${EXPANDER_SOURCES:#*/App.swift})
cp -R "$EXPANDER_PRODUCTS/FluentKit_FluentKit.bundle" "$EXPANDER_BIN/"
shasum -a 256 "${EXPANDER_OBJECTS[@]}" "${EXPANDER_SOURCES[@]}" "$EXPANDER_AUDIT/SettingsGalleryAudit.swift" > "$EXPANDER_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -swift-version 5 -warnings-as-errors -I "$EXPANDER_MODULES" \
    "${EXPANDER_SOURCES[@]}" "$EXPANDER_AUDIT/SettingsGalleryAudit.swift" \
    "${EXPANDER_OBJECTS[@]}" -o "$EXPANDER_BIN/ExpanderGalleryAudit"
"$EXPANDER_BIN/ExpanderGalleryAudit" "$EXPANDER_OUTPUT/images" > "$EXPANDER_OUTPUT/results.json" 2> "$EXPANDER_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$EXPANDER_OUTPUT/render.log"
python3 "$EXPANDER_AUDIT/../expander-layout/check_results.py" "$EXPANDER_OUTPUT"
python3 "$EXPANDER_AUDIT/check_results.py" "$EXPANDER_OUTPUT/results.json"
