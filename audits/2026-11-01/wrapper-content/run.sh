#!/bin/zsh
set -eu
WRAPPER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$WRAPPER_AUDIT/../../.."
WRAPPER_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
WRAPPER_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$WRAPPER_OUTPUT"
WRAPPER_OUTPUT="$(cd "$WRAPPER_OUTPUT" && pwd)"
WRAPPER_PRODUCTS="$(swift build -c release --scratch-path "$WRAPPER_BUILD" --show-bin-path)"
WRAPPER_LIBRARY="${FLUENTKIT_WRAPPER_LIBRARY:-$WRAPPER_PRODUCTS/FluentKit.o}"
WRAPPER_BIN="$WRAPPER_BUILD/audit-tools"
mkdir -p "$WRAPPER_BIN"
ditto "$WRAPPER_PRODUCTS/FluentKit_FluentKit.bundle" "$WRAPPER_BIN/FluentKit_FluentKit.bundle"
shasum -a 256 "$WRAPPER_LIBRARY" > "$WRAPPER_OUTPUT/library-sha256.txt"
if [[ "${WRAPPER_SEMANTIC_ONLY:-0}" != 1 ]]; then
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$WRAPPER_PRODUCTS" \
    "$WRAPPER_AUDIT/WrapperCases.swift" "$WRAPPER_AUDIT/WrapperContentAudit.swift" \
    "$WRAPPER_LIBRARY" -o "$WRAPPER_BIN/WrapperContentAudit"
"$WRAPPER_BIN/WrapperContentAudit" "$WRAPPER_OUTPUT/images" > "$WRAPPER_OUTPUT/render.log" 2>&1
fi
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$WRAPPER_PRODUCTS" \
    "$WRAPPER_AUDIT/SemanticLabelAudit.swift" "$WRAPPER_LIBRARY" -o "$WRAPPER_BIN/SemanticLabelAudit"
"$WRAPPER_BIN/SemanticLabelAudit" "$WRAPPER_OUTPUT/semantic-labels.json" > "$WRAPPER_OUTPUT/semantic.log" 2>&1
