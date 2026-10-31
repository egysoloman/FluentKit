#!/bin/zsh
set -eu
RADIO_AUDIT="$(cd "$(dirname "$0")" && pwd)"
RADIO_STAGE="${1:?Specify before or after}"
case "$RADIO_STAGE" in before|after) ;; *) exit 64 ;; esac
RADIO_PRODUCTS="${FLUENTKIT_RADIO_PRODUCTS:-${TMPDIR}/fluentkit-quality-release/out/Products/Release}"
RADIO_APP="/tmp/Fluent Radio $RADIO_STAGE.app"
mkdir -p "$RADIO_APP/Contents/MacOS" "$RADIO_APP/Contents/Resources" "$RADIO_AUDIT/$RADIO_STAGE/native" "$RADIO_AUDIT/$RADIO_STAGE/interactive"
ditto "$RADIO_PRODUCTS/FluentKit_FluentKit.bundle" "$RADIO_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$RADIO_APP/Contents/Info.plist" "$RADIO_STAGE" "$RADIO_AUDIT" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':f'org.fluentkit.audit.radio.{sys.argv[2]}',
    'CFBundleName':f'Fluent Radio {sys.argv[2]}','CFBundleExecutable':'RadioAudit','CFBundlePackageType':'APPL',
    'AuditOutputPath':f'{sys.argv[3]}/{sys.argv[2]}/interactive'}))
PY
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$RADIO_PRODUCTS" \
    "$RADIO_AUDIT/RadioAudit.swift" "$RADIO_PRODUCTS/FluentKit.o" -o "$RADIO_APP/Contents/MacOS/RadioAudit"
"$RADIO_APP/Contents/MacOS/RadioAudit" "$RADIO_AUDIT/$RADIO_STAGE/native"
