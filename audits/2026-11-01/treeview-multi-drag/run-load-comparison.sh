#!/bin/zsh
set -eu
TREE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$TREE_AUDIT/../../.."
TREE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
TREE_PRODUCTS="$(swift build -c release --scratch-path "$TREE_BUILD" --show-bin-path)"
for phase in before after; do
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TREE_PRODUCTS" \
        "$TREE_AUDIT/$phase/GalleryLoadSource.swift" "$TREE_AUDIT/GalleryLoadAudit.swift" \
        "$TREE_PRODUCTS/FluentKit.o" -o "$TREE_BUILD/audit-tools/GalleryLoadAudit"
    "$TREE_BUILD/audit-tools/GalleryLoadAudit" > "$TREE_AUDIT/$phase/lazy-load.json"
done
