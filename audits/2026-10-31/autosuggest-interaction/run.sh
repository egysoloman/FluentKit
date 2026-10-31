#!/bin/zsh
set -eu
SUGGEST_AUDIT="$(cd "$(dirname "$0")" && pwd)"
SUGGEST_REPO="$(cd "$SUGGEST_AUDIT/../../.." && pwd)"
SUGGEST_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
SUGGEST_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-autosuggest-interaction}"
mkdir -p "$SUGGEST_OUTPUT"
SUGGEST_OUTPUT="$(cd "$SUGGEST_OUTPUT" && pwd)"
cd "$SUGGEST_REPO"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$SUGGEST_BUILD" -Xswiftc -warnings-as-errors
fi
SUGGEST_PRODUCTS="$(swift build -c release --scratch-path "$SUGGEST_BUILD" --show-bin-path)"
SUGGEST_BIN="$SUGGEST_BUILD/audit-tools"
mkdir -p "$SUGGEST_BIN"
cp -R "$SUGGEST_PRODUCTS/FluentKit_FluentKit.bundle" "$SUGGEST_BIN/"
shasum -a 256 "$SUGGEST_PRODUCTS/FluentKit.o" > "$SUGGEST_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SUGGEST_PRODUCTS" \
    "$SUGGEST_AUDIT/AutoSuggestInteractionAudit.swift" "$SUGGEST_PRODUCTS/FluentKit.o" -o "$SUGGEST_BIN/AutoSuggestInteractionAudit"
"$SUGGEST_BIN/AutoSuggestInteractionAudit" "$SUGGEST_OUTPUT/images" > "$SUGGEST_OUTPUT/results.json" 2> "$SUGGEST_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$SUGGEST_OUTPUT/render.log"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    python3 "$SUGGEST_AUDIT/check_results.py" "$SUGGEST_OUTPUT/results.json"
fi
