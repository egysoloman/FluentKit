#!/bin/zsh
set -eu
# Maintained quality gates. Dated audit directories retain their historical fixtures and data.
QUALITY_TOOLS="$(cd "$(dirname "$0")" && pwd)"
QUALITY_REPO="$(cd "$QUALITY_TOOLS/.." && pwd)"
QUALITY_FIXTURES="$QUALITY_TOOLS/quality"
QUALITY_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
QUALITY_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-quality-results}"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [output-directory]" >&2
    exit 64
fi
mkdir -p "$QUALITY_OUTPUT" "$QUALITY_BUILD"
QUALITY_OUTPUT="$(cd "$QUALITY_OUTPUT" && pwd)"
QUALITY_BUILD="$(cd "$QUALITY_BUILD" && pwd)"
cd "$QUALITY_REPO"
swift build --target FluentKit -c release --scratch-path "$QUALITY_BUILD" -Xswiftc -warnings-as-errors
QUALITY_PRODUCTS="$(swift build -c release --scratch-path "$QUALITY_BUILD" --show-bin-path)"
QUALITY_BIN="$QUALITY_BUILD/audit-tools"
mkdir -p "$QUALITY_BIN"
if [ -d "$QUALITY_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$QUALITY_PRODUCTS/FluentKit_FluentKit.bundle" "$QUALITY_BIN/"
fi
for QUALITY_CASE in InputAudit CollectionAudit EditingAudit AppearanceAudit; do
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$QUALITY_PRODUCTS" \
        "$QUALITY_FIXTURES/$QUALITY_CASE.swift" "$QUALITY_PRODUCTS/FluentKit.o" \
        -o "$QUALITY_BIN/$QUALITY_CASE"
    "$QUALITY_BIN/$QUALITY_CASE" > "$QUALITY_OUTPUT/$QUALITY_CASE.json" 2> "$QUALITY_OUTPUT/$QUALITY_CASE.log"
done
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$QUALITY_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/GalleryModels.swift \
    FluentKitGallery/FluentKitGallery/GalleryCatalog.swift \
    FluentKitGallery/FluentKitGallery/GalleryScreen.swift \
    FluentKitGallery/FluentKitGallery/ContentDialogGallerySample.swift \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift \
    "$QUALITY_FIXTURES/GallerySampleAudit.swift" "$QUALITY_PRODUCTS/FluentKit.o" -o "$QUALITY_BIN/GallerySampleAudit"
"$QUALITY_BIN/GallerySampleAudit" > "$QUALITY_OUTPUT/GallerySampleAudit.json" 2> "$QUALITY_OUTPUT/GallerySampleAudit.log"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$QUALITY_PRODUCTS" \
    "$QUALITY_FIXTURES/VisualAudit.swift" "$QUALITY_PRODUCTS/FluentKit.o" -o "$QUALITY_BIN/VisualAudit"
"$QUALITY_BIN/VisualAudit" "$QUALITY_OUTPUT/visual" > "$QUALITY_OUTPUT/VisualAudit.log" 2>&1
python3 "$QUALITY_TOOLS/check_audit_results.py" "$QUALITY_OUTPUT"
# Pixel comparison requires a reviewed baseline with a matching OS build, scale and fonts.
if [ -n "${AUDIT_VISUAL_BASELINE:-}" ]; then
    python3 "$QUALITY_TOOLS/compare_snapshots.py" "$AUDIT_VISUAL_BASELINE" "$QUALITY_OUTPUT/visual"
fi
