#!/bin/zsh
set -eu
EXPANDER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$EXPANDER_AUDIT/../../.."
EXPANDER_PRODUCTS="${1:?Provide the SwiftPM products directory}"
EXPANDER_OUTPUT="${2:?Provide a new output directory}"
EXPANDER_BIN="${TMPDIR:-/tmp}/fluentkit-expander-initial-gallery"
mkdir -p "$EXPANDER_BIN" "$EXPANDER_OUTPUT/images"
EXPANDER_OUTPUT="$(cd "$EXPANDER_OUTPUT" && pwd)"
EXPANDER_SOURCES=(FluentKitGallery/FluentKitGallery/*.swift)
EXPANDER_SOURCES=(${EXPANDER_SOURCES:#*/App.swift})
cp -R "$EXPANDER_PRODUCTS/FluentKit_FluentKit.bundle" "$EXPANDER_BIN/"
shasum -a 256 "$EXPANDER_PRODUCTS/FluentKit.o" "${EXPANDER_SOURCES[@]}" "$EXPANDER_AUDIT/../expander-layout/ExpanderGalleryAudit.swift" > "$EXPANDER_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -swift-version 5 -warnings-as-errors -I "$EXPANDER_PRODUCTS" \
    "${EXPANDER_SOURCES[@]}" "$EXPANDER_AUDIT/../expander-layout/ExpanderGalleryAudit.swift" \
    "$EXPANDER_PRODUCTS/FluentKit.o" -o "$EXPANDER_BIN/ExpanderGalleryAudit"
"$EXPANDER_BIN/ExpanderGalleryAudit" "$EXPANDER_OUTPUT/images" > "$EXPANDER_OUTPUT/results.json" 2> "$EXPANDER_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$EXPANDER_OUTPUT/render.log"
python3 "$EXPANDER_AUDIT/../expander-layout/check_results.py" "$EXPANDER_OUTPUT"
