#!/bin/zsh
set -eu
PINYIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
PINYIN_SOURCE="${FLUENTIME_SOURCE:-/Users/stars/Downloads/Fluent IME}"
PINYIN_PRODUCTS="${FLUENTKIT_PINYIN_PRODUCTS:-${TMPDIR}/fluentkit-quality-release/out/Products/Release}"
PINYIN_CORE_BUILD="${FLUENTIME_BUILD:-/tmp/fluentkit-ime-system-pinyin}"
PINYIN_CORE="$PINYIN_CORE_BUILD/out/Products/Release"
PINYIN_BUNDLE="${1:?app bundle path}"
PINYIN_OUTPUT="${2:?output directory}"
mkdir -p "$PINYIN_OUTPUT" "$PINYIN_BUNDLE/Contents/MacOS" "$PINYIN_BUNDLE/Contents/Resources"
PINYIN_OUTPUT="$(cd "$PINYIN_OUTPUT" && pwd)"
ditto "$PINYIN_PRODUCTS/FluentKit_FluentKit.bundle" "$PINYIN_BUNDLE/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$PINYIN_BUNDLE/Contents/Info.plist" "$PINYIN_OUTPUT" "$PINYIN_SOURCE/dist/Fluent IME.app/Contents/Resources/Rime" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.fluentkit.audit.system-pinyin',
    'CFBundleName':'Fluent Settings Pinyin Audit','CFBundleExecutable':'SettingsPinyinAudit',
    'CFBundlePackageType':'APPL','CFBundleVersion':'1','NSHighResolutionCapable':True,
    'AuditOutput':sys.argv[2],'RimeSharedDirectory':sys.argv[3]}))
PY
PINYIN_SOURCES=("$PINYIN_SOURCE"/Sources/FluentIME/*.swift)
PINYIN_SOURCES=( ${PINYIN_SOURCES:#*/main.swift} )
shasum -a 256 "${PINYIN_SOURCES[@]}" "$PINYIN_SOURCE"/Sources/FluentIMECore/*.swift "$PINYIN_ROOT/SettingsPinyinAudit.swift" "$PINYIN_PRODUCTS/FluentKit.o" "$PINYIN_CORE/FluentIMECore.o" > "$PINYIN_OUTPUT/source-sha256.txt"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$PINYIN_PRODUCTS" -I "$PINYIN_CORE" \
    -Xcc "-fmodule-map-file=$PINYIN_CORE_BUILD/out/Intermediates.noindex/GeneratedModuleMaps/CRimeBridge.modulemap" \
    "${PINYIN_SOURCES[@]}" "$PINYIN_ROOT/SettingsPinyinAudit.swift" \
    "$PINYIN_PRODUCTS/FluentKit.o" "$PINYIN_CORE/FluentIMECore.o" "$PINYIN_CORE/CRimeBridge.o" \
    -L /opt/homebrew/opt/librime/lib -lrime -framework InputMethodKit -framework Carbon \
    -o "$PINYIN_BUNDLE/Contents/MacOS/SettingsPinyinAudit"
