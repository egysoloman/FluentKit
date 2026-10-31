#!/bin/zsh
set -eu
THEME_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$THEME_AUDIT/../../.."
THEME_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
THEME_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$THEME_OUTPUT"
THEME_OUTPUT="$(cd "$THEME_OUTPUT" && pwd)"
swift build --target FluentKit -c release --scratch-path "$THEME_BUILD" -Xswiftc -warnings-as-errors
THEME_PRODUCTS="$(swift build -c release --scratch-path "$THEME_BUILD" --show-bin-path)"
THEME_BIN="$THEME_BUILD/audit-tools"
mkdir -p "$THEME_BIN"
ditto "$THEME_PRODUCTS/FluentKit_FluentKit.bundle" "$THEME_BIN/FluentKit_FluentKit.bundle"
THEME_LIBRARY="${FLUENTKIT_THEME_LIBRARY:-$THEME_PRODUCTS/FluentKit.o}"
shasum -a 256 "$THEME_LIBRARY" > "$THEME_OUTPUT/library-sha256.txt"
shasum -a 256 FluentKitGallery/FluentKitGallery/*.swift > "$THEME_OUTPUT/gallery-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$THEME_PRODUCTS" \
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
    "$THEME_AUDIT/GalleryThemeAudit.swift" "$THEME_LIBRARY" -o "$THEME_BIN/GalleryThemeAudit"
"$THEME_BIN/GalleryThemeAudit" "$THEME_OUTPUT/images" > "$THEME_OUTPUT/render.log" 2>&1
