#!/bin/zsh
set -eu
SCROLLER_ROOT="$(cd "$(dirname "$0")" && pwd)"
SCROLLER_SOURCE="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
SCROLLER_PRODUCTS="${FLUENTKIT_SCROLLER_PRODUCTS:-${TMPDIR}/fluentkit-quality-release/out/Products/Release}"
SCROLLER_CORE_BUILD="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-system-pinyin}"
SCROLLER_CORE="$SCROLLER_CORE_BUILD/out/Products/Release"
SCROLLER_BUNDLE="${1:?app bundle path}"
SCROLLER_OUTPUT="${2:?output directory}"
mkdir -p "$SCROLLER_OUTPUT" "$SCROLLER_BUNDLE/Contents/MacOS" "$SCROLLER_BUNDLE/Contents/Resources"
SCROLLER_OUTPUT="$(cd "$SCROLLER_OUTPUT" && pwd)"
ditto "$SCROLLER_PRODUCTS/FluentKit_FluentKit.bundle" "$SCROLLER_BUNDLE/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$SCROLLER_BUNDLE/Contents/Info.plist" "$SCROLLER_OUTPUT" "$SCROLLER_SOURCE/dist/Fluent IME.app/Contents/Resources/Rime" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.fluentkit.audit.scroller-layout',
    'CFBundleName':'Fluent Settings Scroller Audit','CFBundleExecutable':'SettingsScrollerAudit',
    'CFBundlePackageType':'APPL','CFBundleVersion':'1','NSHighResolutionCapable':True,
    'AuditOutput':sys.argv[2],'RimeSharedDirectory':sys.argv[3]}))
PY
SCROLLER_SOURCES=("$SCROLLER_SOURCE"/Sources/FluentIME/*.swift)
SCROLLER_SOURCES=( ${SCROLLER_SOURCES:#*/main.swift} )
shasum -a 256 "${SCROLLER_SOURCES[@]}" "$SCROLLER_SOURCE"/Sources/FluentIMECore/*.swift "$SCROLLER_ROOT/SettingsScrollerAudit.swift" "$SCROLLER_PRODUCTS/FluentKit.o" "$SCROLLER_CORE/FluentIMECore.o" > "$SCROLLER_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$SCROLLER_PRODUCTS" -I "$SCROLLER_CORE" \
    -Xcc "-fmodule-map-file=$SCROLLER_CORE_BUILD/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${SCROLLER_SOURCES[@]}" "$SCROLLER_ROOT/SettingsScrollerAudit.swift" \
    "$SCROLLER_PRODUCTS/FluentKit.o" "$SCROLLER_CORE/FluentIMECore.o" "$SCROLLER_CORE/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$SCROLLER_BUNDLE/Contents/MacOS/SettingsScrollerAudit"
shasum -a 256 "${SCROLLER_SOURCES[@]}" "$SCROLLER_SOURCE"/Sources/FluentIMECore/*.swift "$SCROLLER_ROOT/SettingsScrollerAudit.swift" "$SCROLLER_PRODUCTS/FluentKit.o" "$SCROLLER_CORE/FluentIMECore.o" > "$SCROLLER_OUTPUT/source-sha256-after-build.txt"
diff -u "$SCROLLER_OUTPUT/source-sha256.txt" "$SCROLLER_OUTPUT/source-sha256-after-build.txt"
