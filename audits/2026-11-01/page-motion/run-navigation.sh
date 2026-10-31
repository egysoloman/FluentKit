#!/bin/zsh
set -eu
MOTION_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$MOTION_AUDIT/../../.."
MOTION_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
MOTION_PRODUCTS="$(swift build -c release --scratch-path "$MOTION_BUILD" --show-bin-path)"
MOTION_OUTPUT="${1:?Usage: run-navigation.sh output-directory}"
mkdir -p "$MOTION_OUTPUT" "$MOTION_BUILD/audit-tools"
MOTION_OUTPUT="$(cd "$MOTION_OUTPUT" && pwd)"
MOTION_LIBRARY="${FLUENTKIT_MOTION_LIBRARY:-$MOTION_PRODUCTS/FluentKit.o}"
shasum -a 256 "$MOTION_LIBRARY" > "$MOTION_OUTPUT/library-sha256.txt"
ditto "$MOTION_PRODUCTS/FluentKit_FluentKit.bundle" "$MOTION_BUILD/audit-tools/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$MOTION_PRODUCTS" \
    "$MOTION_AUDIT/NavigationMotionAudit.swift" "$MOTION_LIBRARY" -o "$MOTION_BUILD/audit-tools/NavigationMotionAudit"
"$MOTION_BUILD/audit-tools/NavigationMotionAudit" "$MOTION_OUTPUT/images" > "$MOTION_OUTPUT/run.log" 2>&1
