#!/bin/zsh
set -eu
TREE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$TREE_AUDIT/../../.."
TREE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
TREE_PRODUCTS="$(swift build -c release --scratch-path "$TREE_BUILD" --show-bin-path)"
mkdir -p "$TREE_BUILD/audit-tools"
ditto "$TREE_PRODUCTS/FluentKit_FluentKit.bundle" "$TREE_BUILD/audit-tools/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TREE_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift "$TREE_AUDIT/TreeMoveGalleryAudit.swift" \
    "$TREE_PRODUCTS/FluentKit.o" -o "$TREE_BUILD/audit-tools/TreeMoveGalleryAudit"
"$TREE_BUILD/audit-tools/TreeMoveGalleryAudit" "${1:?Output directory required}"
