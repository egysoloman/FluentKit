#!/bin/zsh
set -eu
KEY_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$KEY_ROOT/../../.."
KEY_STAGE="${1:?before or after}"
case "$KEY_STAGE" in
    before)
        : "${FLUENTKIT_KEY_PRODUCTS:?before requires baseline Release products}"
        KEY_OPTIONS=()
        ;;
    after) KEY_OPTIONS=(--automatic) ;;
    *) exit 64 ;;
esac
KEY_PRODUCTS="${FLUENTKIT_KEY_PRODUCTS:-${TMPDIR}/fluentkit-quality-release/out/Products/Release}"
KEY_BIN="${TMPDIR}/fluentkit-gallery-keyboard-$KEY_STAGE"
mkdir -p "$KEY_BIN" "$KEY_ROOT/$KEY_STAGE"
ditto "$KEY_PRODUCTS/FluentKit_FluentKit.bundle" "$KEY_BIN/FluentKit_FluentKit.bundle"
KEY_SOURCES=(FluentKitGallery/FluentKitGallery/*.swift)
KEY_SOURCES=(${KEY_SOURCES:#*/App.swift})
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$KEY_PRODUCTS" \
    "${KEY_SOURCES[@]}" "$KEY_ROOT/FocusChainAudit.swift" "$KEY_PRODUCTS/FluentKit.o" -o "$KEY_BIN/FocusChainAudit"
"$KEY_BIN/FocusChainAudit" "${KEY_OPTIONS[@]}" > "$KEY_ROOT/$KEY_STAGE/chain.json" 2> "$KEY_ROOT/$KEY_STAGE/native.log"

for KEY_FIXTURE in SceneAudit ScopeAudit WindowAudit CandidateRefreshAudit; do
    swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$KEY_PRODUCTS" \
        "$KEY_ROOT/$KEY_FIXTURE.swift" "$KEY_PRODUCTS/FluentKit.o" -o "$KEY_BIN/$KEY_FIXTURE"
    case "$KEY_FIXTURE" in
        SceneAudit) KEY_NAME=scene ;;
        ScopeAudit) KEY_NAME=scope-expanded ;;
        WindowAudit) KEY_NAME=windows ;;
        CandidateRefreshAudit) KEY_NAME=candidate-refresh ;;
    esac
    "$KEY_BIN/$KEY_FIXTURE" > "$KEY_ROOT/$KEY_STAGE/$KEY_NAME.json" 2> "$KEY_ROOT/$KEY_STAGE/$KEY_NAME.log"
done
