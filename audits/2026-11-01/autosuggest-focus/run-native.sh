#!/bin/zsh
set -eu
CALLBACK_ROOT="$(cd "$(dirname "$0")" && pwd)"
CALLBACK_PRODUCTS="${1:?Release products directory}"
CALLBACK_OUTPUT="${2:?output directory}"
mkdir -p "$CALLBACK_OUTPUT"
CALLBACK_OUTPUT="$(cd "$CALLBACK_OUTPUT" && pwd)"
CALLBACK_BIN="$(mktemp -d "${TMPDIR:-/tmp}/fluentkit-callback-probe-XXXXXX")"
ditto "$CALLBACK_PRODUCTS/FluentKit_FluentKit.bundle" "$CALLBACK_BIN/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CALLBACK_PRODUCTS" \
    "$CALLBACK_ROOT/CallbackAudit.swift" "$CALLBACK_PRODUCTS/FluentKit.o" -o "$CALLBACK_BIN/CallbackAudit"
shasum -a 256 "$CALLBACK_ROOT/CallbackAudit.swift" "$CALLBACK_PRODUCTS/FluentKit.o" "$CALLBACK_BIN/CallbackAudit" > "$CALLBACK_OUTPUT/provenance.txt"
"$CALLBACK_BIN/CallbackAudit" > "$CALLBACK_OUTPUT/results.json" 2> "$CALLBACK_OUTPUT/native.log"
