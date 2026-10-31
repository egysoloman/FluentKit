#!/bin/zsh
set -eu
TREE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
TREE_REPO="$(cd "$TREE_AUDIT/../../.." && pwd)"
TREE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
TREE_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-treeview-lifecycle}"
mkdir -p "$TREE_OUTPUT"
TREE_OUTPUT="$(cd "$TREE_OUTPUT" && pwd)"
cd "$TREE_REPO"
swift build --target FluentKit -c release --scratch-path "$TREE_BUILD" -Xswiftc -warnings-as-errors
TREE_PRODUCTS="$(swift build -c release --scratch-path "$TREE_BUILD" --show-bin-path)"
TREE_BIN="$TREE_BUILD/audit-tools"
mkdir -p "$TREE_BIN"
if [ -d "$TREE_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$TREE_PRODUCTS/FluentKit_FluentKit.bundle" "$TREE_BIN/"
fi
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TREE_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift \
    "$TREE_AUDIT/TreeViewGalleryAudit.swift" "$TREE_PRODUCTS/FluentKit.o" \
    -o "$TREE_BIN/TreeViewGalleryAudit"
"$TREE_BIN/TreeViewGalleryAudit" "$TREE_OUTPUT/images" \
    > "$TREE_OUTPUT/results.json" 2> "$TREE_OUTPUT/render.log"
