#!/bin/zsh
set -eu
TOOLTIP_ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLTIP_PRODUCTS="${1:?Debug products with testable FluentKit module}"
TOOLTIP_OUTPUT="${2:?output directory}"
mkdir -p "$TOOLTIP_OUTPUT"
TOOLTIP_OUTPUT="$(cd "$TOOLTIP_OUTPUT" && pwd)"
TOOLTIP_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-tooltip-probe-XXXXXX")"
ditto "$TOOLTIP_PRODUCTS/FluentKit_FluentKit.bundle" "$TOOLTIP_BIN/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -swift-version 5 -warnings-as-errors -I "$TOOLTIP_PRODUCTS" \
    "$TOOLTIP_ROOT/TooltipMotionAudit.swift" "$TOOLTIP_PRODUCTS/FluentKit.o" -o "$TOOLTIP_BIN/TooltipMotionAudit"
shasum -a 256 "$TOOLTIP_ROOT/TooltipMotionAudit.swift" "$TOOLTIP_PRODUCTS/FluentKit.o" "$TOOLTIP_BIN/TooltipMotionAudit" > "$TOOLTIP_OUTPUT/provenance.txt"
"$TOOLTIP_BIN/TooltipMotionAudit" "$TOOLTIP_OUTPUT" > "$TOOLTIP_OUTPUT/stdout.log" 2> "$TOOLTIP_OUTPUT/native.log"
