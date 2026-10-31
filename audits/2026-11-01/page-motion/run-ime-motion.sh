#!/bin/zsh
set -eu
MOTION_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$MOTION_AUDIT/../../.."
MOTION_SOURCE="${FLUENTIME_MOTION_SOURCE:-/Users/stars/Downloads/Fluent IME/Sources/FluentIME/IMEPageMotion.swift}"
MOTION_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
MOTION_PRODUCTS="$(swift build -c release --scratch-path "$MOTION_BUILD" --show-bin-path)"
MOTION_OUTPUT="${1:?Usage: run-ime-motion.sh output-directory}"
mkdir -p "$MOTION_OUTPUT" "$MOTION_BUILD/audit-tools"
MOTION_OUTPUT="$(cd "$MOTION_OUTPUT" && pwd)"
ditto "$MOTION_PRODUCTS/FluentKit_FluentKit.bundle" "$MOTION_BUILD/audit-tools/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$MOTION_PRODUCTS" \
    "$MOTION_SOURCE" "$MOTION_AUDIT/IMEPageMotionAudit.swift" "$MOTION_PRODUCTS/FluentKit.o" \
    -o "$MOTION_BUILD/audit-tools/IMEPageMotionAudit"
"$MOTION_BUILD/audit-tools/IMEPageMotionAudit" "$MOTION_OUTPUT/images" > "$MOTION_OUTPUT/run.log" 2>&1
