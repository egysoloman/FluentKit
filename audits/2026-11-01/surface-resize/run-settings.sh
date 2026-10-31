#!/bin/zsh
set -eu
RESIZE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
RESIZE_APP="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
RESIZE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
RESIZE_CORE="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-pointer-validation}"
RESIZE_OUTPUT="${1:?Usage: run-settings.sh output-directory}"
mkdir -p "$RESIZE_OUTPUT"
RESIZE_OUTPUT="$(cd "$RESIZE_OUTPUT" && pwd)"
RESIZE_PRODUCTS="$(swift build -c release --scratch-path "$RESIZE_BUILD" --show-bin-path)"
mkdir -p "$RESIZE_BUILD/audit-tools"
ditto "$RESIZE_PRODUCTS/FluentKit_FluentKit.bundle" "$RESIZE_BUILD/audit-tools/FluentKit_FluentKit.bundle"
RESIZE_SOURCES=("$RESIZE_APP"/Sources/FluentIME/*.swift)
RESIZE_SOURCES=( ${RESIZE_SOURCES:#*/main.swift} )
shasum -a 256 "${RESIZE_SOURCES[@]}" > "$RESIZE_OUTPUT/app-source-sha256.txt"
shasum -a 256 "$RESIZE_PRODUCTS/FluentKit.o" > "$RESIZE_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -I "$RESIZE_PRODUCTS" -I "$RESIZE_CORE/out/Products/Release" \
    -Xcc "-fmodule-map-file=$RESIZE_CORE/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${RESIZE_SOURCES[@]}" "$RESIZE_AUDIT/SettingsResizeAudit.swift" \
    "$RESIZE_PRODUCTS/FluentKit.o" "$RESIZE_CORE/out/Products/Release/FluentIMECore.o" "$RESIZE_CORE/out/Products/Release/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$RESIZE_BUILD/audit-tools/SettingsResizeAudit"
FLUENTIME_RENDER_THEME=dark FLUENTIME_RENDER_PAGE=keys "$RESIZE_BUILD/audit-tools/SettingsResizeAudit" \
    "$RESIZE_OUTPUT/images" "$RESIZE_APP/dist/Fluent IME.app/Contents/Resources/Rime" > "$RESIZE_OUTPUT/render.log" 2>&1
