#!/bin/zsh
set -eu
AUDIT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_REPO="$(cd "$AUDIT_DIR/../.." && pwd)"
AUDIT_BUILD="${TMPDIR:-/tmp}/fluentkit-audit-release"
AUDIT_OUTPUT="${1:-$AUDIT_DIR/reproduced}"
mkdir -p "$AUDIT_OUTPUT"
cd "$AUDIT_REPO"
swift build --target FluentKit -c release --scratch-path "$AUDIT_BUILD" -Xswiftc -warnings-as-errors
AUDIT_PRODUCTS="$(swift build -c release --scratch-path "$AUDIT_BUILD" --show-bin-path)"
AUDIT_BIN="$AUDIT_BUILD/audit-tools"
mkdir -p "$AUDIT_BIN"
if [ -d "$AUDIT_PRODUCTS/FluentKit_FluentKit.bundle" ]; then
    cp -R "$AUDIT_PRODUCTS/FluentKit_FluentKit.bundle" "$AUDIT_BIN/"
fi
for AUDIT_CASE in InputAudit CollectionAudit EditingAudit AppearanceAudit; do
    swiftc -parse-as-library -O -swift-version 5 -I "$AUDIT_PRODUCTS" \
        "$AUDIT_DIR/$AUDIT_CASE.swift" "$AUDIT_PRODUCTS/FluentKit.o" \
        -o "$AUDIT_BIN/$AUDIT_CASE"
    "$AUDIT_BIN/$AUDIT_CASE" > "$AUDIT_OUTPUT/$AUDIT_CASE.json" 2> "$AUDIT_OUTPUT/$AUDIT_CASE.log"
done
