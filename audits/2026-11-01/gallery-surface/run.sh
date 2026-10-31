#!/bin/zsh
set -eu
SURFACE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$SURFACE_AUDIT/../../.."
SURFACE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
SURFACE_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$SURFACE_OUTPUT"
SURFACE_OUTPUT="$(cd "$SURFACE_OUTPUT" && pwd)"
swift build --target FluentKit -c release --scratch-path "$SURFACE_BUILD" -Xswiftc -warnings-as-errors
SURFACE_PRODUCTS="$(swift build -c release --scratch-path "$SURFACE_BUILD" --show-bin-path)"
SURFACE_BIN="$SURFACE_BUILD/audit-tools"
mkdir -p "$SURFACE_BIN"
ditto "$SURFACE_PRODUCTS/FluentKit_FluentKit.bundle" "$SURFACE_BIN/FluentKit_FluentKit.bundle"
shasum -a 256 "$SURFACE_PRODUCTS/FluentKit.o" > "$SURFACE_OUTPUT/library-sha256.txt"
shasum -a 256 FluentKitGallery/FluentKitGallery/*.swift > "$SURFACE_OUTPUT/gallery-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SURFACE_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/GalleryModels.swift \
    FluentKitGallery/FluentKitGallery/GalleryCatalog.swift \
    FluentKitGallery/FluentKitGallery/GalleryScreen.swift \
    FluentKitGallery/FluentKitGallery/ContentDialogGallerySample.swift \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift \
    FluentKitGallery/FluentKitGallery/MenuBarGallerySample.swift \
    FluentKitGallery/FluentKitGallery/AutoSuggestBoxGallerySample.swift \
    FluentKitGallery/FluentKitGallery/SplitButtonGallerySample.swift \
    FluentKitGallery/FluentKitGallery/CalendarViewGallerySample.swift \
    FluentKitGallery/FluentKitGallery/FlipViewGallerySample.swift \
    "$SURFACE_AUDIT/GallerySurfaceAudit.swift" "$SURFACE_PRODUCTS/FluentKit.o" -o "$SURFACE_BIN/GallerySurfaceAudit"
"$SURFACE_BIN/GallerySurfaceAudit" "$SURFACE_OUTPUT/images" > "$SURFACE_OUTPUT/results.json" 2> "$SURFACE_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$SURFACE_OUTPUT/render.log"
