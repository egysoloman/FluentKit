#!/bin/zsh
set -eu
TREE_AUDIT="$(cd "$(dirname "$0")" && pwd)"
cd "$TREE_AUDIT/../../.."
TREE_BUILD="${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}"
TREE_PRODUCTS="$(swift build -c release --scratch-path "$TREE_BUILD" --show-bin-path)"
TREE_APP='/tmp/Fluent Tree Drag Review.app'
mkdir -p "$TREE_APP/Contents/MacOS" "$TREE_APP/Contents/Resources"
ditto "$TREE_PRODUCTS/FluentKit_FluentKit.bundle" "$TREE_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$TREE_APP/Contents/Info.plist" <<'PY'
import sys,plistlib
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.fluentkit.audit.treedrag',
    'CFBundleName':'Fluent Tree Drag Review','CFBundleExecutable':'TreeDragInteractive','CFBundlePackageType':'APPL',
    'AuditOutputPath':str(Path('audits/2026-11-01/treeview-multi-drag/after/launch-services').resolve())}))
PY
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$TREE_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift "$TREE_AUDIT/TreeDragInteractive.swift" \
    "$TREE_PRODUCTS/FluentKit.o" -o "$TREE_APP/Contents/MacOS/TreeDragInteractive"
