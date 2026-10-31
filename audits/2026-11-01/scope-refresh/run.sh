#!/bin/zsh
set -eu
SCOPE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$SCOPE_AUDIT/../../.."
SCOPE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
SCOPE_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$SCOPE_OUTPUT"
SCOPE_OUTPUT="$(cd "$SCOPE_OUTPUT" && pwd)"
swift build --target FluentKit -c release --scratch-path "$SCOPE_BUILD" -Xswiftc -warnings-as-errors
SCOPE_PRODUCTS="$(swift build -c release --scratch-path "$SCOPE_BUILD" --show-bin-path)"
SCOPE_BIN="$SCOPE_BUILD/audit-tools"
mkdir -p "$SCOPE_BIN"
ditto "$SCOPE_PRODUCTS/FluentKit_FluentKit.bundle" "$SCOPE_BIN/FluentKit_FluentKit.bundle"
SCOPE_LIBRARY="${FLUENTKIT_SCOPE_LIBRARY:-$SCOPE_PRODUCTS/FluentKit.o}"
shasum -a 256 "$SCOPE_LIBRARY" > "$SCOPE_OUTPUT/library-sha256.txt"
shasum -a 256 FluentKitGallery/FluentKitGallery/*.swift > "$SCOPE_OUTPUT/gallery-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SCOPE_PRODUCTS" \
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
    "$SCOPE_AUDIT/ScopeGalleryAudit.swift" "$SCOPE_LIBRARY" -o "$SCOPE_BIN/ScopeGalleryAudit"
"$SCOPE_BIN/ScopeGalleryAudit" "$SCOPE_OUTPUT/images" > "$SCOPE_OUTPUT/results.json" 2> "$SCOPE_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$SCOPE_OUTPUT/render.log"
