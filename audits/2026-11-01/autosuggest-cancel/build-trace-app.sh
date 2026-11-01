#!/bin/zsh
set -eu
CANCEL_ROOT="$(cd "$(dirname "$0")" && pwd)"
CANCEL_PRODUCTS="${1:?Release products directory}"
CANCEL_APP="${2:?app directory}"
CANCEL_LOG="${3:?log path}"
mkdir -p "$CANCEL_APP/Contents/MacOS" "$CANCEL_APP/Contents/Resources"
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CANCEL_PRODUCTS" \
    "$CANCEL_ROOT/TraceApp.swift" "$CANCEL_PRODUCTS/FluentKit.o" -o "$CANCEL_APP/Contents/MacOS/TraceApp"
ditto "$CANCEL_PRODUCTS/FluentKit_FluentKit.bundle" "$CANCEL_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$CANCEL_APP" "$CANCEL_LOG" <<'PY'
import sys,plistlib
from pathlib import Path
app=Path(sys.argv[1]).resolve()
with (app/'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleExecutable':'TraceApp','CFBundleIdentifier':'org.fluentkit.audit.'+app.stem,
        'CFBundleName':app.stem,'CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication',
        'AuditLogPath':str(Path(sys.argv[2]).resolve())},f)
PY
