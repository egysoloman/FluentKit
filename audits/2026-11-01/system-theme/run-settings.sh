#!/bin/zsh
set -eu
THEME_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$THEME_AUDIT/../../.."
THEME_APP="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
THEME_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
THEME_CORE="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-search-audit}"
THEME_OUTPUT="${1:?Usage: run-settings.sh output-directory}"
mkdir -p "$THEME_OUTPUT"
THEME_OUTPUT="$(cd "$THEME_OUTPUT" && pwd)"
THEME_PRODUCTS="$(swift build -c release --scratch-path "$THEME_BUILD" --show-bin-path)"
mkdir -p "$THEME_BUILD/audit-tools"
ditto "$THEME_PRODUCTS/FluentKit_FluentKit.bundle" "$THEME_BUILD/audit-tools/FluentKit_FluentKit.bundle"
THEME_SOURCES=("$THEME_APP"/Sources/FluentIME/*.swift)
THEME_SOURCES=( ${THEME_SOURCES:#*/main.swift} )
shasum -a 256 "${THEME_SOURCES[@]}" > "$THEME_OUTPUT/app-source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -I "$THEME_PRODUCTS" -I "$THEME_CORE/out/Products/Release" \
    -Xcc "-fmodule-map-file=$THEME_CORE/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${THEME_SOURCES[@]}" "$THEME_AUDIT/SettingsThemeAudit.swift" \
    "${THEME_PRODUCTS}/FluentKit.o" "$THEME_CORE/out/Products/Release/FluentIMECore.o" "$THEME_CORE/out/Products/Release/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$THEME_BUILD/audit-tools/SettingsThemeAudit"
for THEME_PREF in system light dark; do
    mkdir -p "$THEME_OUTPUT/$THEME_PREF"
    FLUENTIME_RENDER_THEME="$THEME_PREF" FLUENTIME_RENDER_PAGE="${FLUENTIME_THEME_PAGE:-general}" "$THEME_BUILD/audit-tools/SettingsThemeAudit" \
        "$THEME_OUTPUT/$THEME_PREF/images" "$THEME_APP/dist/Fluent IME.app/Contents/Resources/Rime" > "$THEME_OUTPUT/$THEME_PREF/run.log" 2>&1
done
