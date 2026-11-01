#!/bin/zsh
set -eu
FOCUS_ROOT="$(cd "$(dirname "$0")" && pwd)"
FOCUS_STAGE="${1:?Specify before or after}"
case "$FOCUS_STAGE" in before|after) ;; *) exit 64 ;; esac
if [ "$FOCUS_STAGE" = before ] && [ -z "${FLUENTKIT_FOCUS_PRODUCTS:-}" ]; then
    echo 'before requires FLUENTKIT_FOCUS_PRODUCTS pointing to baseline products' >&2
    exit 64
fi
FOCUS_PRODUCTS="${FLUENTKIT_FOCUS_PRODUCTS:-${TMPDIR:-/tmp}/fluentkit-quality-release/out/Products/Release}"
FOCUS_BIN="${TMPDIR:-/tmp}/fluentkit-choice-focus-$FOCUS_STAGE"
mkdir -p "$FOCUS_BIN"
ditto "$FOCUS_PRODUCTS/FluentKit_FluentKit.bundle" "$FOCUS_BIN/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$FOCUS_PRODUCTS" \
    "$FOCUS_ROOT/FocusAudit.swift" "$FOCUS_PRODUCTS/FluentKit.o" -o "$FOCUS_BIN/FocusAudit"
"$FOCUS_BIN/FocusAudit" "$FOCUS_ROOT/$FOCUS_STAGE/native"
