#!/bin/zsh
set -eu
CANCEL_ROOT="$(cd "$(dirname "$0")" && pwd)"
CANCEL_PRODUCTS="${1:?Release products directory}"
CANCEL_OUTPUT="${2:?output directory}"
mkdir -p "$CANCEL_OUTPUT"
CANCEL_OUTPUT="$(cd "$CANCEL_OUTPUT" && pwd)"
CANCEL_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-cancel-probe-XXXXXX")"
ditto "$CANCEL_PRODUCTS/FluentKit_FluentKit.bundle" "$CANCEL_BIN/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CANCEL_PRODUCTS" \
    "$CANCEL_ROOT/CancelAudit.swift" "$CANCEL_PRODUCTS/FluentKit.o" -o "$CANCEL_BIN/CancelAudit"
"$CANCEL_BIN/CancelAudit" > "$CANCEL_OUTPUT/results.json" 2> "$CANCEL_OUTPUT/native.log"
