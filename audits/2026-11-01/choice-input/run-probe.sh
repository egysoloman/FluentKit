#!/bin/zsh
set -eu
CHOICE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
CHOICE_STAGE="${1:?Specify before or after}"
case "$CHOICE_STAGE" in before|after) ;; *) exit 64 ;; esac
if [ "$CHOICE_STAGE" = before ] && [ -z "${FLUENTKIT_CHOICE_PRODUCTS:-}" ]; then
    echo 'before requires FLUENTKIT_CHOICE_PRODUCTS pointing to the baseline build' >&2
    exit 64
fi
CHOICE_PRODUCTS="${FLUENTKIT_CHOICE_PRODUCTS:-${TMPDIR:-/tmp}/fluentkit-quality-release/out/Products/Release}"
CHOICE_BIN="${TMPDIR:-/tmp}/fluentkit-choice-audit-$CHOICE_STAGE"
mkdir -p "$CHOICE_BIN" "$CHOICE_AUDIT/$CHOICE_STAGE/native"
ditto "$CHOICE_PRODUCTS/FluentKit_FluentKit.bundle" "$CHOICE_BIN/FluentKit_FluentKit.bundle"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CHOICE_PRODUCTS" \
    "$CHOICE_AUDIT/ChoiceAudit.swift" "$CHOICE_PRODUCTS/FluentKit.o" -o "$CHOICE_BIN/ChoiceAudit"
"$CHOICE_BIN/ChoiceAudit" "$CHOICE_AUDIT/$CHOICE_STAGE/native"
