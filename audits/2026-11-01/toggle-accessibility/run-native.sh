#!/bin/zsh
set -eu
AUDIT_SOURCE="$(cd "$(dirname "$0")" && pwd)"
AUDIT_PRODUCTS="${1:?Provide the SwiftPM products directory}"
AUDIT_OUTPUT="${2:?Provide a new output directory}"
mkdir -p "$AUDIT_OUTPUT/bin"
cp -R "$AUDIT_PRODUCTS/FluentKit_FluentKit.bundle" "$AUDIT_OUTPUT/bin/"
swiftc -parse-as-library -swift-version 5 -warnings-as-errors -I "$AUDIT_PRODUCTS" \
    "$AUDIT_SOURCE/ToggleAccessibilityAudit.swift" "$AUDIT_PRODUCTS/FluentKit.o" \
    -o "$AUDIT_OUTPUT/bin/ToggleAccessibilityAudit"
"$AUDIT_OUTPUT/bin/ToggleAccessibilityAudit" > "$AUDIT_OUTPUT/states.json" 2> "$AUDIT_OUTPUT/run.log"
