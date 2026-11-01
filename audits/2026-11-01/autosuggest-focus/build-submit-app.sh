#!/bin/zsh
set -eu
CALLBACK_ROOT="$(cd "$(dirname "$0")" && pwd)"
CALLBACK_PRODUCTS="${1:?Release products directory}"
CALLBACK_APP="${2:?app directory}"
CALLBACK_LOG="${3:?log path}"
mkdir -p "$CALLBACK_APP/Contents/MacOS" "$CALLBACK_APP/Contents/Resources"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CALLBACK_PRODUCTS" \
    "$CALLBACK_ROOT/SubmitApp.swift" "$CALLBACK_PRODUCTS/FluentKit.o" -o "$CALLBACK_APP/Contents/MacOS/SubmitApp"
ditto "$CALLBACK_PRODUCTS/FluentKit_FluentKit.bundle" "$CALLBACK_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$CALLBACK_APP" "$CALLBACK_LOG" <<'PY'
import sys,plistlib
from pathlib import Path
app=Path(sys.argv[1]).resolve()
with (app/'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleExecutable':'SubmitApp','CFBundleIdentifier':'org.fluentkit.audit.autosuggest-callback',
        'CFBundleName':'AutoSuggest callback audit','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication',
        'AuditLogPath':str(Path(sys.argv[2]).resolve())},f)
PY
