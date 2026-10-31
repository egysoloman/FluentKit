#!/bin/zsh
set -eu
COMMAND_AUDIT="$(cd "$(dirname "$0")" && pwd)"
COMMAND_REPO="$(cd "$COMMAND_AUDIT/../../.." && pwd)"
COMMAND_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR:-/tmp}/fluentkit-quality-release}"
COMMAND_OUTPUT="${1:-${TMPDIR:-/tmp}/fluentkit-commandbar-lifecycle}"
mkdir -p "$COMMAND_OUTPUT"
COMMAND_OUTPUT="$(cd "$COMMAND_OUTPUT" && pwd)"
cd "$COMMAND_REPO"
# Only use an existing build when recording a baseline before rebuilding the library.
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    swift build --target FluentKit -c release --scratch-path "$COMMAND_BUILD" -Xswiftc -warnings-as-errors
fi
COMMAND_PRODUCTS="$(swift build -c release --scratch-path "$COMMAND_BUILD" --show-bin-path)"
COMMAND_BIN="$COMMAND_BUILD/audit-tools"
mkdir -p "$COMMAND_BIN"
cp -R "$COMMAND_PRODUCTS/FluentKit_FluentKit.bundle" "$COMMAND_BIN/"
shasum -a 256 "$COMMAND_PRODUCTS/FluentKit.o" > "$COMMAND_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$COMMAND_PRODUCTS" \
    "$COMMAND_AUDIT/CommandBarLifecycleAudit.swift" "$COMMAND_PRODUCTS/FluentKit.o" -o "$COMMAND_BIN/CommandBarLifecycleAudit"
"$COMMAND_BIN/CommandBarLifecycleAudit" "$COMMAND_OUTPUT/images" > "$COMMAND_OUTPUT/results.json" 2> "$COMMAND_OUTPUT/render.log"
python3 tools/check_test_diagnostics.py "$COMMAND_OUTPUT/render.log"
if [ "${AUDIT_USE_EXISTING_BUILD:-0}" != 1 ]; then
    python3 "$COMMAND_AUDIT/check_results.py" "$COMMAND_OUTPUT/results.json"
fi
