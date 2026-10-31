#!/bin/zsh
set -eu
SEARCH_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$SEARCH_AUDIT/../../.."
SEARCH_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
SEARCH_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$SEARCH_OUTPUT"
SEARCH_OUTPUT="$(cd "$SEARCH_OUTPUT" && pwd)"
swift build --target FluentKit -c release --scratch-path "$SEARCH_BUILD" -Xswiftc -warnings-as-errors
SEARCH_PRODUCTS="$(swift build -c release --scratch-path "$SEARCH_BUILD" --show-bin-path)"
SEARCH_BIN="$SEARCH_BUILD/audit-tools"
mkdir -p "$SEARCH_BIN"
ditto "$SEARCH_PRODUCTS/FluentKit_FluentKit.bundle" "$SEARCH_BIN/FluentKit_FluentKit.bundle"
SEARCH_LIBRARY="${FLUENTKIT_SEARCH_LIBRARY:-$SEARCH_PRODUCTS/FluentKit.o}"
shasum -a 256 "$SEARCH_LIBRARY" > "$SEARCH_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SEARCH_PRODUCTS" \
    "$SEARCH_AUDIT/SearchGeometryAudit.swift" "$SEARCH_LIBRARY" -o "$SEARCH_BIN/SearchGeometryAudit"
"$SEARCH_BIN/SearchGeometryAudit" "$SEARCH_OUTPUT/images" > "$SEARCH_OUTPUT/results.json" 2> "$SEARCH_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$SEARCH_OUTPUT/render.log"
