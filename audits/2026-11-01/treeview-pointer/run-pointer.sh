#!/bin/zsh
set -eu
POINTER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
POINTER_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
# Deliberately use existing products: the same probe can run against the saved baseline.
POINTER_PRODUCTS="$POINTER_BUILD/out/Products/Release"
mkdir -p "$POINTER_BUILD/audit-tools"
ditto "$POINTER_PRODUCTS/FluentKit_FluentKit.bundle" "$POINTER_BUILD/audit-tools/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$POINTER_PRODUCTS" \
    "$POINTER_AUDIT/TreePointerAudit.swift" "$POINTER_PRODUCTS/FluentKit.o" -o "$POINTER_BUILD/audit-tools/TreePointerAudit"
"$POINTER_BUILD/audit-tools/TreePointerAudit" "${@:1}"
