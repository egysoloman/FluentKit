#!/bin/zsh
set -eu
TITLE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
TITLE_REPO="$(cd "$TITLE_AUDIT/../../.." && pwd)"
TITLE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
TITLE_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-titlebar-button-audit}"
mkdir -p "$TITLE_OUTPUT"
TITLE_OUTPUT="$(cd "$TITLE_OUTPUT" && pwd)"
cd "$TITLE_REPO"
# Baseline capture may reuse a previously built, hash-recorded library.
if [ "${TITLE_REUSE_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$TITLE_BUILD" -Xswiftc -warnings-as-errors
fi
TITLE_PRODUCTS="$(swift build -c release --scratch-path "$TITLE_BUILD" --show-bin-path)"
TITLE_BIN="$TITLE_BUILD/audit-tools"
mkdir -p "$TITLE_BIN"
cp -R "$TITLE_PRODUCTS/FluentKit_FluentKit.bundle" "$TITLE_BIN/"
shasum -a 256 "$TITLE_PRODUCTS/FluentKit.o" > "$TITLE_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TITLE_PRODUCTS" \
    "$TITLE_AUDIT/TitleBarAudit.swift" "$TITLE_PRODUCTS/FluentKit.o" -o "$TITLE_BIN/TitleBarAudit"
"$TITLE_BIN/TitleBarAudit" "$TITLE_OUTPUT/images" > "$TITLE_OUTPUT/results.json" 2> "$TITLE_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$TITLE_OUTPUT/render.log"
