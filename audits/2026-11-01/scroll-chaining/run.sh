#!/bin/zsh
set -eu
CHAIN_AUDIT="$(cd "$(dirname "$0")" && pwd)"
CHAIN_REPO="$(cd "$CHAIN_AUDIT/../../.." && pwd)"
CHAIN_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
CHAIN_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-scroll-chaining-audit}"
mkdir -p "$CHAIN_OUTPUT"
CHAIN_OUTPUT="$(cd "$CHAIN_OUTPUT" && pwd)"
cd "$CHAIN_REPO"
# Baseline capture may reuse a previously built, hash-recorded library.
if [ "${CHAIN_REUSE_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$CHAIN_BUILD" -Xswiftc -warnings-as-errors
fi
CHAIN_PRODUCTS="$(swift build -c release --scratch-path "$CHAIN_BUILD" --show-bin-path)"
CHAIN_BIN="$CHAIN_BUILD/audit-tools"
mkdir -p "$CHAIN_BIN"
cp -R "$CHAIN_PRODUCTS/FluentKit_FluentKit.bundle" "$CHAIN_BIN/"
shasum -a 256 "$CHAIN_PRODUCTS/FluentKit.o" > "$CHAIN_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CHAIN_PRODUCTS" \
    "$CHAIN_AUDIT/ScrollChainingAudit.swift" "$CHAIN_PRODUCTS/FluentKit.o" -o "$CHAIN_BIN/ScrollChainingAudit"
"$CHAIN_BIN/ScrollChainingAudit" "$CHAIN_OUTPUT/images" > "$CHAIN_OUTPUT/results.json" 2> "$CHAIN_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$CHAIN_OUTPUT/render.log"
