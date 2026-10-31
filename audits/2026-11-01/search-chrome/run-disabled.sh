#!/bin/zsh
set -eu
CHROME_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$CHROME_AUDIT/../../.."
CHROME_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
CHROME_OUTPUT="${1:?Usage: run-disabled.sh output-directory}"
mkdir -p "$CHROME_OUTPUT"
CHROME_PRODUCTS="$(swift build -c release --scratch-path "$CHROME_BUILD" --show-bin-path)"
CHROME_LIBRARY="${FLUENTKIT_SEARCH_LIBRARY:-$CHROME_PRODUCTS/FluentKit.o}"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CHROME_PRODUCTS" \
    "$CHROME_AUDIT/DisabledTextAudit.swift" "$CHROME_LIBRARY" -o "$CHROME_BUILD/audit-tools/DisabledTextAudit"
"$CHROME_BUILD/audit-tools/DisabledTextAudit" > "$CHROME_OUTPUT/disabled-text.json"
