#!/bin/zsh
set -eu
POPUP_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$POPUP_AUDIT/../../.."
POPUP_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
POPUP_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$POPUP_OUTPUT"
POPUP_OUTPUT="$(cd "$POPUP_OUTPUT" && pwd)"
POPUP_PRODUCTS="$(swift build -c release --scratch-path "$POPUP_BUILD" --show-bin-path)"
POPUP_BIN="$POPUP_BUILD/audit-tools"
mkdir -p "$POPUP_BIN"
ditto "$POPUP_PRODUCTS/FluentKit_FluentKit.bundle" "$POPUP_BIN/FluentKit_FluentKit.bundle"
POPUP_LIBRARY="${FLUENTKIT_POPUP_LIBRARY:-$POPUP_PRODUCTS/FluentKit.o}"
shasum -a 256 "$POPUP_LIBRARY" > "$POPUP_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$POPUP_PRODUCTS" \
    "$POPUP_AUDIT/AutoSuggestAnchorAudit.swift" "$POPUP_LIBRARY" -o "$POPUP_BIN/AutoSuggestAnchorAudit"
"$POPUP_BIN/AutoSuggestAnchorAudit" "$POPUP_OUTPUT/images" > "$POPUP_OUTPUT/render.log" 2>&1
python3 tools/check_test_diagnostics.py "$POPUP_OUTPUT/render.log"
