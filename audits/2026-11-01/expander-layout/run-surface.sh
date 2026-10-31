#!/bin/zsh
set -eu
EXPANDER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$EXPANDER_AUDIT/../../.."
EXPANDER_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
EXPANDER_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$EXPANDER_OUTPUT"
EXPANDER_OUTPUT="$(cd "$EXPANDER_OUTPUT" && pwd)"
swift build --target FluentKit -c release --scratch-path "$EXPANDER_BUILD" -Xswiftc -warnings-as-errors
EXPANDER_PRODUCTS="$(swift build -c release --scratch-path "$EXPANDER_BUILD" --show-bin-path)"
EXPANDER_BIN="$EXPANDER_BUILD/audit-tools"
mkdir -p "$EXPANDER_BIN"
ditto "$EXPANDER_PRODUCTS/FluentKit_FluentKit.bundle" "$EXPANDER_BIN/FluentKit_FluentKit.bundle"
EXPANDER_LIBRARY="${FLUENTKIT_EXPANDER_LIBRARY:-$EXPANDER_PRODUCTS/FluentKit.o}"
shasum -a 256 "$EXPANDER_LIBRARY" > "$EXPANDER_OUTPUT/library-sha256.txt"
shasum -a 256 FluentKitGallery/FluentKitGallery/*.swift > "$EXPANDER_OUTPUT/gallery-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$EXPANDER_PRODUCTS" \
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
    "$EXPANDER_AUDIT/ExpanderSurfaceAudit.swift" "$EXPANDER_LIBRARY" -o "$EXPANDER_BIN/ExpanderSurfaceAudit"
"$EXPANDER_BIN/ExpanderSurfaceAudit" "$EXPANDER_OUTPUT/images" > "$EXPANDER_OUTPUT/results.json" 2> "$EXPANDER_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$EXPANDER_OUTPUT/render.log"
python3 "$EXPANDER_AUDIT/check_results.py" "$EXPANDER_OUTPUT"
