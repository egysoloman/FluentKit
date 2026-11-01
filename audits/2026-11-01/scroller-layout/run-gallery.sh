#!/bin/zsh
set -eu
SCROLLER_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCROLLER_PRODUCTS="${1:?Release products directory}"
SCROLLER_OUTPUT="${2:?output directory}"
mkdir -p "$SCROLLER_OUTPUT"
SCROLLER_OUTPUT="$(cd "$SCROLLER_OUTPUT" && pwd)"
SCROLLER_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-gallery-scroller-XXXXXX")"
ditto "$SCROLLER_PRODUCTS/FluentKit_FluentKit.bundle" "$SCROLLER_BIN/FluentKit_FluentKit.bundle"
SCROLLER_SOURCES=(FluentKitGallery/FluentKitGallery/{GalleryModels,GalleryCatalog,GalleryScreen,ContentDialogGallerySample,TreeViewGallerySample,MenuBarGallerySample,AutoSuggestBoxGallerySample,SplitButtonGallerySample,CalendarViewGallerySample,FlipViewGallerySample}.swift)
shasum -a 256 "${SCROLLER_SOURCES[@]}" "$SCROLLER_ROOT/GalleryScrollerAudit.swift" "$SCROLLER_PRODUCTS/FluentKit.o" > "$SCROLLER_OUTPUT/gallery-provenance.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SCROLLER_PRODUCTS" \
    "${SCROLLER_SOURCES[@]}" "$SCROLLER_ROOT/GalleryScrollerAudit.swift" "$SCROLLER_PRODUCTS/FluentKit.o" -o "$SCROLLER_BIN/GalleryScrollerAudit"
"$SCROLLER_BIN/GalleryScrollerAudit" > "$SCROLLER_OUTPUT/gallery-results.json" 2> "$SCROLLER_OUTPUT/gallery-native.log"
