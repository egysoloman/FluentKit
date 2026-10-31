#!/bin/zsh
set -eu
CHOICE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
CHOICE_REVIEW='/tmp/Fluent Choice Keyboard.app'
CHOICE_PRODUCTS="${FLUENTKIT_CHOICE_PRODUCTS:-${TMPDIR:-/tmp}/fluentkit-quality-release/out/Products/Release}"
mkdir -p "$CHOICE_REVIEW/Contents/MacOS" "$CHOICE_REVIEW/Contents/Resources"
ditto "$CHOICE_PRODUCTS/FluentKit_FluentKit.bundle" "$CHOICE_REVIEW/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$CHOICE_REVIEW/Contents/Info.plist" "$CHOICE_AUDIT/after/keyboard-events.json" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.fluentkit.audit.choicekeyboard',
    'CFBundleName':'Fluent Choice Keyboard','CFBundleExecutable':'KeyboardReview','CFBundlePackageType':'APPL',
    'AuditOutputPath':sys.argv[2]}))
PY
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$CHOICE_PRODUCTS" \
    "$CHOICE_AUDIT/KeyboardReview.swift" "$CHOICE_PRODUCTS/FluentKit.o" -o "$CHOICE_REVIEW/Contents/MacOS/KeyboardReview"
