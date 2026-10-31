#!/bin/zsh
set -eu
POINTER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$POINTER_AUDIT/../../.."
POINTER_PRODUCTS="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}/out/Products/Release"
POINTER_APP='/tmp/Fluent Tree Pointer Review.app'
mkdir -p "$POINTER_APP/Contents/MacOS" "$POINTER_APP/Contents/Resources"
ditto "$POINTER_PRODUCTS/FluentKit_FluentKit.bundle" "$POINTER_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$POINTER_APP/Contents/Info.plist" <<'PY'
import sys, plistlib
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.fluentkit.audit.treepointer',
    'CFBundleName': 'Fluent Tree Pointer Review', 'CFBundleExecutable': 'TreePointerReview', 'CFBundlePackageType': 'APPL',
    'AuditOutputPath': str(Path('audits/2026-11-01/treeview-pointer/after/interactive').resolve())}))
PY
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$POINTER_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift "$POINTER_AUDIT/../treeview-multi-drag/TreeDragInteractive.swift" \
    "$POINTER_PRODUCTS/FluentKit.o" -o "$POINTER_APP/Contents/MacOS/TreePointerReview"
