#!/bin/zsh
set -eu
FLIP_AUDIT="$(cd "$(dirname "$0")" && pwd)"
FLIP_REPO="$(cd "$FLIP_AUDIT/../../.." && pwd)"
FLIP_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
FLIP_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-flip-interaction-visual}"
mkdir -p "$FLIP_BUILD" "$FLIP_OUTPUT"
FLIP_BUILD="$(cd "$FLIP_BUILD" && pwd)"
FLIP_OUTPUT="$(cd "$FLIP_OUTPUT" && pwd)"
cd "$FLIP_REPO"
swift build --target FluentKit -c release --scratch-path "$FLIP_BUILD" -Xswiftc -warnings-as-errors >&2
FLIP_PRODUCTS="$(swift build -c release --scratch-path "$FLIP_BUILD" --show-bin-path)"
FLIP_BIN="$FLIP_BUILD/audit-tools"
mkdir -p "$FLIP_BIN"
if [ -d "$FLIP_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$FLIP_PRODUCTS/FluentKit_FluentKit.bundle" "$FLIP_BIN/"
fi
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$FLIP_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/GalleryModels.swift \
    FluentKitGallery/FluentKitGallery/GalleryCatalog.swift \
    FluentKitGallery/FluentKitGallery/GalleryScreen.swift \
    FluentKitGallery/FluentKitGallery/ContentDialogGallerySample.swift \
    "$FLIP_AUDIT/FlipViewInteractionAudit.swift" "$FLIP_PRODUCTS/FluentKit.o" -o "$FLIP_BIN/FlipViewInteractionAudit"
"$FLIP_BIN/FlipViewInteractionAudit" "$FLIP_OUTPUT"
