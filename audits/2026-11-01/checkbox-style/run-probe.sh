#!/bin/zsh
set -eu
CHECKBOX_AUDIT="$(cd "$(dirname "$0")" && pwd)"
CHECKBOX_STAGE="${1:?Specify before or after}"
case "$CHECKBOX_STAGE" in before|after) ;; *) exit 64 ;; esac
CHECKBOX_PRODUCTS="${FLUENTKIT_CHECKBOX_PRODUCTS:-${TMPDIR}/fluentkit-quality-release/out/Products/Release}"
CHECKBOX_APP="/tmp/Fluent CheckBox $CHECKBOX_STAGE.app"
mkdir -p "$CHECKBOX_APP/Contents/MacOS" "$CHECKBOX_APP/Contents/Resources" "$CHECKBOX_AUDIT/$CHECKBOX_STAGE/native" "$CHECKBOX_AUDIT/$CHECKBOX_STAGE/interactive"
ditto "$CHECKBOX_PRODUCTS/FluentKit_FluentKit.bundle" "$CHECKBOX_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$CHECKBOX_APP/Contents/Info.plist" "$CHECKBOX_STAGE" "$CHECKBOX_AUDIT" <<'PY'
import plistlib, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier': f'org.fluentkit.audit.checkbox.{sys.argv[2]}',
    'CFBundleName': f'Fluent CheckBox {sys.argv[2]}', 'CFBundleExecutable': 'CheckBoxAudit', 'CFBundlePackageType': 'APPL',
    'AuditOutputPath': f'{sys.argv[3]}/{sys.argv[2]}/interactive'}))
PY
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CHECKBOX_PRODUCTS" \
    "$CHECKBOX_AUDIT/CheckBoxAudit.swift" "$CHECKBOX_PRODUCTS/FluentKit.o" -o "$CHECKBOX_APP/Contents/MacOS/CheckBoxAudit"
"$CHECKBOX_APP/Contents/MacOS/CheckBoxAudit" "$CHECKBOX_AUDIT/$CHECKBOX_STAGE/native"
