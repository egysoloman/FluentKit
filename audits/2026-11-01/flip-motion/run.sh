#!/bin/zsh
set -eu
FLIP_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$FLIP_AUDIT/../../.."
FLIP_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
FLIP_PRODUCTS="$(swift build -c release --scratch-path "$FLIP_BUILD" --show-bin-path)"
FLIP_OUTPUT="${1:?Usage: run.sh output-directory}"
mkdir -p "$FLIP_OUTPUT" "$FLIP_BUILD/audit-tools"
FLIP_OUTPUT="$(cd "$FLIP_OUTPUT" && pwd)"
FLIP_LIBRARY="${FLUENTKIT_FLIP_LIBRARY:-$FLIP_PRODUCTS/FluentKit.o}"
shasum -a 256 "$FLIP_LIBRARY" > "$FLIP_OUTPUT/library-sha256.txt"
ditto "$FLIP_PRODUCTS/FluentKit_FluentKit.bundle" "$FLIP_BUILD/audit-tools/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$FLIP_PRODUCTS" \
    "$FLIP_AUDIT/FlipMotionAudit.swift" "$FLIP_LIBRARY" -o "$FLIP_BUILD/audit-tools/FlipMotionAudit"
"$FLIP_BUILD/audit-tools/FlipMotionAudit" "$FLIP_OUTPUT/images" > "$FLIP_OUTPUT/run.log" 2>&1
