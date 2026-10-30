#!/bin/zsh
set -eu
AUDIT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_REPO="$(cd "$AUDIT_DIR/../.." && pwd)"
AUDIT_OUTPUT="${1:-$AUDIT_DIR/repaired}"
mkdir -p "$AUDIT_OUTPUT"
AUDIT_OUTPUT="$(cd "$AUDIT_OUTPUT" && pwd)"
"$AUDIT_DIR/run.sh" "$AUDIT_OUTPUT"
cd "$AUDIT_REPO"
AUDIT_BUILD="${TMPDIR:-/tmp}/fluentkit-audit-release"
AUDIT_PRODUCTS="$(swift build -c release --scratch-path "$AUDIT_BUILD" --show-bin-path)"
AUDIT_BIN="$AUDIT_BUILD/audit-tools"
swiftc -parse-as-library -O -swift-version 5 -I "$AUDIT_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/GalleryModels.swift \
    FluentKitGallery/FluentKitGallery/GalleryCatalog.swift \
    FluentKitGallery/FluentKitGallery/GalleryScreen.swift \
    FluentKitGallery/FluentKitGallery/ContentDialogGallerySample.swift \
    "$AUDIT_DIR/GallerySampleAudit.swift" "$AUDIT_PRODUCTS/FluentKit.o" -o "$AUDIT_BIN/GallerySampleAudit"
"$AUDIT_BIN/GallerySampleAudit" > "$AUDIT_OUTPUT/GallerySampleAudit.json" 2> "$AUDIT_OUTPUT/GallerySampleAudit.log"
swiftc -parse-as-library -O -swift-version 5 -I "$AUDIT_PRODUCTS" \
    "$AUDIT_DIR/VisualAudit.swift" "$AUDIT_PRODUCTS/FluentKit.o" -o "$AUDIT_BIN/VisualAudit"
"$AUDIT_BIN/VisualAudit" "$AUDIT_OUTPUT/visual" > "$AUDIT_OUTPUT/VisualAudit.log" 2>&1
python3 tools/check_audit_results.py "$AUDIT_OUTPUT"
# Pixel comparison is explicit because OS build, scale and fonts must match the reviewed baseline.
if [ -n "${AUDIT_VISUAL_BASELINE:-}" ]; then
    python3 tools/compare_snapshots.py "$AUDIT_VISUAL_BASELINE" "$AUDIT_OUTPUT/visual"
fi
