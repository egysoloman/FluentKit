#!/bin/zsh
set -eu
SEARCH_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$SEARCH_AUDIT/../../.."
SEARCH_APP="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
SEARCH_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
SEARCH_CORE="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-search-audit}"
SEARCH_OUTPUT="${1:?Usage: run-settings.sh output-directory}"
mkdir -p "$SEARCH_OUTPUT"
SEARCH_OUTPUT="$(cd "$SEARCH_OUTPUT" && pwd)"
SEARCH_PRODUCTS="$(swift build -c release --scratch-path "$SEARCH_BUILD" --show-bin-path)"
mkdir -p "$SEARCH_BUILD/audit-tools"
ditto "$SEARCH_PRODUCTS/FluentKit_FluentKit.bundle" "$SEARCH_BUILD/audit-tools/FluentKit_FluentKit.bundle"
SEARCH_SOURCES=("$SEARCH_APP"/Sources/FluentIME/*.swift)
SEARCH_SOURCES=( ${SEARCH_SOURCES:#*/main.swift} )
shasum -a 256 "${SEARCH_SOURCES[@]}" > "$SEARCH_OUTPUT/app-source-sha256.txt"
SEARCH_LIBRARY="${FLUENTKIT_SEARCH_LIBRARY:-$SEARCH_PRODUCTS/FluentKit.o}"
shasum -a 256 "$SEARCH_LIBRARY" > "$SEARCH_OUTPUT/library-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -I "$SEARCH_PRODUCTS" -I "$SEARCH_CORE/out/Products/Release" \
    -Xcc "-fmodule-map-file=$SEARCH_CORE/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${SEARCH_SOURCES[@]}" "$SEARCH_AUDIT/SettingsSearchAudit.swift" \
    "$SEARCH_LIBRARY" "$SEARCH_CORE/out/Products/Release/FluentIMECore.o" "$SEARCH_CORE/out/Products/Release/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$SEARCH_BUILD/audit-tools/SettingsSearchAudit"
FLUENTIME_RENDER_THEME=dark FLUENTIME_RENDER_PAGE=keys "$SEARCH_BUILD/audit-tools/SettingsSearchAudit" \
    "$SEARCH_OUTPUT/images" "$SEARCH_APP/dist/Fluent IME.app/Contents/Resources/Rime" > "$SEARCH_OUTPUT/render.log" 2>&1
