#!/bin/zsh
set -eu
# Maintained quality gates. Historical audit evidence stays local and is not a dependency.
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
QUALITY_BUILD_ARGUMENTS=()
if [ -n "${FLUENTKIT_QUALITY_BUILD_SYSTEM:-}" ]; then
    QUALITY_BUILD_ARGUMENTS=(--build-system "$FLUENTKIT_QUALITY_BUILD_SYSTEM")
fi
swift build "${QUALITY_BUILD_ARGUMENTS[@]}" --target FluentKit -c release --scratch-path "$QUALITY_BUILD" -Xswiftc -warnings-as-errors
QUALITY_PRODUCTS="$(swift build "${QUALITY_BUILD_ARGUMENTS[@]}" -c release --scratch-path "$QUALITY_BUILD" --show-bin-path)"
# Swift Build and the earlier native SwiftPM engine place modules and objects differently.
QUALITY_MODULES="$QUALITY_PRODUCTS"
QUALITY_OBJECTS=("$QUALITY_PRODUCTS/FluentKit.o")
if [ ! -f "$QUALITY_PRODUCTS/FluentKit.o" ]; then
    QUALITY_MODULES="$QUALITY_PRODUCTS/Modules"
    QUALITY_OBJECTS=("$QUALITY_PRODUCTS"/FluentKit.build/*.o(N))
fi
if [ "${#QUALITY_OBJECTS[@]}" -eq 0 ] || [ ! -f "${QUALITY_OBJECTS[1]}" ]; then
    echo "No FluentKit object files found in $QUALITY_PRODUCTS" >&2
    exit 1
fi
QUALITY_BIN="$QUALITY_BUILD/audit-tools"
mkdir -p "$QUALITY_BIN"
if [ -d "$QUALITY_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$QUALITY_PRODUCTS/FluentKit_FluentKit.bundle" "$QUALITY_BIN/"
fi
for QUALITY_CASE in InputAudit CollectionAudit EditingAudit ComboBoxSelectionAudit ComboBoxTextSearchAudit ComboBoxCompletionAudit ComboBoxSubmissionAudit MenuHierarchyAudit MenuPointerAudit MenuBarInteractionAudit AppearanceAudit; do
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$QUALITY_MODULES" \
        "$QUALITY_FIXTURES/$QUALITY_CASE.swift" "${QUALITY_OBJECTS[@]}" \
        -o "$QUALITY_BIN/$QUALITY_CASE"
    "$QUALITY_BIN/$QUALITY_CASE" > "$QUALITY_OUTPUT/$QUALITY_CASE.json" 2> "$QUALITY_OUTPUT/$QUALITY_CASE.log"
done
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$QUALITY_MODULES" \
    FluentKitGallery/FluentKitGallery/GalleryModels.swift \
    FluentKitGallery/FluentKitGallery/GalleryCatalog.swift \
    FluentKitGallery/FluentKitGallery/GalleryScreen.swift \
    FluentKitGallery/FluentKitGallery/ContentDialogGallerySample.swift \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift \
    FluentKitGallery/FluentKitGallery/MenuBarGallerySample.swift \
    FluentKitGallery/FluentKitGallery/AutoSuggestBoxGallerySample.swift \
    FluentKitGallery/FluentKitGallery/ComboBoxGallerySample.swift \
    FluentKitGallery/FluentKitGallery/SplitButtonGallerySample.swift \
    FluentKitGallery/FluentKitGallery/MaterialGallerySample.swift \
    FluentKitGallery/FluentKitGallery/CalendarViewGallerySample.swift \
    FluentKitGallery/FluentKitGallery/FlipViewGallerySample.swift \
    "$QUALITY_FIXTURES/GallerySampleAudit.swift" "${QUALITY_OBJECTS[@]}" -o "$QUALITY_BIN/GallerySampleAudit"
"$QUALITY_BIN/GallerySampleAudit" > "$QUALITY_OUTPUT/GallerySampleAudit.json" 2> "$QUALITY_OUTPUT/GallerySampleAudit.log"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$QUALITY_MODULES" \
    "$QUALITY_FIXTURES/VisualAudit.swift" "${QUALITY_OBJECTS[@]}" -o "$QUALITY_BIN/VisualAudit"
"$QUALITY_BIN/VisualAudit" "$QUALITY_OUTPUT/visual" > "$QUALITY_OUTPUT/VisualAudit.log" 2>&1
python3 "$QUALITY_TOOLS/check_audit_results.py" "$QUALITY_OUTPUT"
# Pixel comparison requires a reviewed baseline with a matching OS build, scale and fonts.
if [ -n "${AUDIT_VISUAL_BASELINE:-}" ]; then
    python3 "$QUALITY_TOOLS/compare_snapshots.py" "$AUDIT_VISUAL_BASELINE" "$QUALITY_OUTPUT/visual"
fi
