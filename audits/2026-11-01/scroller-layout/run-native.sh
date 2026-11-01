#!/bin/zsh
set -eu
SCROLLER_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCROLLER_PRODUCTS="${1:?Release products directory}"
SCROLLER_OUTPUT="${2:?output directory}"
mkdir -p "$SCROLLER_OUTPUT"
SCROLLER_OUTPUT="$(cd "$SCROLLER_OUTPUT" && pwd)"
SCROLLER_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-scroller-probe-XXXXXX")"
ditto "$SCROLLER_PRODUCTS/FluentKit_FluentKit.bundle" "$SCROLLER_BIN/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SCROLLER_PRODUCTS" \
    "$SCROLLER_ROOT/ScrollerAudit.swift" "$SCROLLER_PRODUCTS/FluentKit.o" -o "$SCROLLER_BIN/ScrollerAudit"
shasum -a 256 "$SCROLLER_ROOT/ScrollerAudit.swift" "$SCROLLER_PRODUCTS/FluentKit.o" "$SCROLLER_BIN/ScrollerAudit" > "$SCROLLER_OUTPUT/provenance.txt"
"$SCROLLER_BIN/ScrollerAudit" > "$SCROLLER_OUTPUT/results.json" 2> "$SCROLLER_OUTPUT/native.log"
