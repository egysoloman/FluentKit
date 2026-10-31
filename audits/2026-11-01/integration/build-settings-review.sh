#!/bin/zsh
set -eu
REVIEW_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$REVIEW_AUDIT/../../.."
REVIEW_APP="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
REVIEW_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
REVIEW_CORE="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-search-audit}"
REVIEW_BUNDLE="${FLUENTKIT_REVIEW_BUNDLE:-/tmp/Fluent Settings Integration Audit.app}"
REVIEW_OUTPUT="${1:?Usage: build-settings-review.sh output-directory}"
mkdir -p "$REVIEW_OUTPUT" "$REVIEW_BUNDLE/Contents/MacOS" "$REVIEW_BUNDLE/Contents/Resources"
REVIEW_PRODUCTS="$(swift build -c release --scratch-path "$REVIEW_BUILD" --show-bin-path)"
ditto "$REVIEW_PRODUCTS/FluentKit_FluentKit.bundle" "$REVIEW_BUNDLE/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$REVIEW_BUNDLE/Contents/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.fluentkit.audit.settings.integration',
    'CFBundleName':'Fluent Settings Integration Audit','CFBundleExecutable':'SettingsIntegrationAudit',
    'CFBundlePackageType':'APPL','CFBundleVersion':'1','NSHighResolutionCapable':True}))
PY
REVIEW_SOURCES=("$REVIEW_APP"/Sources/FluentIME/*.swift)
REVIEW_SOURCES=( ${REVIEW_SOURCES:#*/main.swift} )
shasum -a 256 "${REVIEW_SOURCES[@]}" "$REVIEW_PRODUCTS/FluentKit.o" > "$REVIEW_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$REVIEW_PRODUCTS" -I "$REVIEW_CORE/out/Products/Release" \
    -Xcc "-fmodule-map-file=$REVIEW_CORE/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${REVIEW_SOURCES[@]}" "$REVIEW_AUDIT/SettingsIntegrationAudit.swift" \
    "$REVIEW_PRODUCTS/FluentKit.o" "$REVIEW_CORE/out/Products/Release/FluentIMECore.o" "$REVIEW_CORE/out/Products/Release/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$REVIEW_BUNDLE/Contents/MacOS/SettingsIntegrationAudit"
