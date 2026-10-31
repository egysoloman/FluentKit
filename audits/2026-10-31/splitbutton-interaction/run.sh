#!/bin/zsh
set -eu
SPLIT_AUDIT="$(cd "$(dirname "$0")" && pwd)"
SPLIT_REPO="$(cd "$SPLIT_AUDIT/../../.." && pwd)"
SPLIT_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
SPLIT_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-splitbutton-interaction}"
mkdir -p "$SPLIT_OUTPUT"
SPLIT_OUTPUT="$(cd "$SPLIT_OUTPUT" && pwd)"
cd "$SPLIT_REPO"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$SPLIT_BUILD" -Xswiftc -warnings-as-errors
fi
SPLIT_PRODUCTS="$(swift build -c release --scratch-path "$SPLIT_BUILD" --show-bin-path)"
SPLIT_BIN="$SPLIT_BUILD/audit-tools"
mkdir -p "$SPLIT_BIN"
cp -R "$SPLIT_PRODUCTS/FluentKit_FluentKit.bundle" "$SPLIT_BIN/"
shasum -a 256 "$SPLIT_PRODUCTS/FluentKit.o" > "$SPLIT_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SPLIT_PRODUCTS" \
    "$SPLIT_AUDIT/SplitButtonInteractionAudit.swift" "$SPLIT_PRODUCTS/FluentKit.o" -o "$SPLIT_BIN/SplitButtonInteractionAudit"
"$SPLIT_BIN/SplitButtonInteractionAudit" "$SPLIT_OUTPUT/images" > "$SPLIT_OUTPUT/results.json" 2> "$SPLIT_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$SPLIT_OUTPUT/render.log"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    python3 "$SPLIT_AUDIT/check_results.py" "$SPLIT_OUTPUT/results.json"
fi
