#!/bin/zsh
set -eu
MOTION_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$MOTION_AUDIT/../../.."
MOTION_APP="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
MOTION_SOURCE="${FLUENTIME_MOTION_SOURCE:-$MOTION_APP/Sources/FluentIME/IMEPageMotion.swift}"
MOTION_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
MOTION_CORE="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-search-audit}"
MOTION_OUTPUT="${1:?Usage: run-settings.sh output-directory}"
mkdir -p "$MOTION_OUTPUT"
MOTION_OUTPUT="$(cd "$MOTION_OUTPUT" && pwd)"
MOTION_PRODUCTS="$(swift build -c release --scratch-path "$MOTION_BUILD" --show-bin-path)"
mkdir -p "$MOTION_BUILD/audit-tools"
ditto "$MOTION_PRODUCTS/FluentKit_FluentKit.bundle" "$MOTION_BUILD/audit-tools/FluentKit_FluentKit.bundle"
MOTION_SOURCES=("$MOTION_APP"/Sources/FluentIME/*.swift)
MOTION_SOURCES=( ${MOTION_SOURCES:#*/main.swift} )
MOTION_SOURCES=( ${MOTION_SOURCES:#*/IMEPageMotion.swift} )
shasum -a 256 "${MOTION_SOURCES[@]}" "$MOTION_SOURCE" > "$MOTION_OUTPUT/app-source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -I "$MOTION_PRODUCTS" -I "$MOTION_CORE/out/Products/Release" \
    -Xcc "-fmodule-map-file=$MOTION_CORE/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${MOTION_SOURCES[@]}" "$MOTION_SOURCE" "$MOTION_AUDIT/SettingsMotionAudit.swift" \
    "$MOTION_PRODUCTS/FluentKit.o" "$MOTION_CORE/out/Products/Release/FluentIMECore.o" "$MOTION_CORE/out/Products/Release/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$MOTION_BUILD/audit-tools/SettingsMotionAudit"
FLUENTIME_RENDER_THEME=dark FLUENTIME_RENDER_PAGE=home "$MOTION_BUILD/audit-tools/SettingsMotionAudit" \
    "$MOTION_OUTPUT/images" "$MOTION_APP/dist/Fluent IME.app/Contents/Resources/Rime" > "$MOTION_OUTPUT/run.log" 2>&1
