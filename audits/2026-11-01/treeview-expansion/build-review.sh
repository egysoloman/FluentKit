#!/bin/zsh
set -eu
EXPANSION_AUDIT="$(cd "$(dirname "$0")" && pwd)"
EXPANSION_STAGE="${1:?Specify before or after}"
case "$EXPANSION_STAGE" in before|after) ;; *) exit 64 ;; esac
cd "$EXPANSION_AUDIT/../../.."
EXPANSION_PRODUCTS="${FLUENTKIT_EXPANSION_PRODUCTS:-${FLUENTKIT_QUALITY_BUILD:-${TMPDIR}/fluentkit-quality-release}/out/Products/Release}"
EXPANSION_APP="/tmp/Fluent Tree Expansion $EXPANSION_STAGE.app"
mkdir -p "$EXPANSION_APP/Contents/MacOS" "$EXPANSION_APP/Contents/Resources"
ditto "$EXPANSION_PRODUCTS/FluentKit_FluentKit.bundle" "$EXPANSION_APP/Contents/Resources/FluentKit_FluentKit.bundle"
python3 - "$EXPANSION_APP/Contents/Info.plist" "$EXPANSION_STAGE" <<'PY'
import sys, plistlib
from pathlib import Path
stage = sys.argv[2]
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier': f'org.fluentkit.audit.treeexpansion.{stage}',
    'CFBundleName': f'Fluent Tree Expansion {stage}', 'CFBundleExecutable': 'TreeExpansionReview', 'CFBundlePackageType': 'APPL',
    'AuditOutputPath': str(Path(f'audits/2026-11-01/treeview-expansion/{stage}/interactive').resolve())}))
PY
swiftc -parse-as-library -O -swift-version 5 -warnings-as-errors -I "$EXPANSION_PRODUCTS" \
    FluentKitGallery/FluentKitGallery/TreeViewGallerySample.swift "$EXPANSION_AUDIT/../treeview-multi-drag/TreeDragInteractive.swift" \
    "$EXPANSION_PRODUCTS/FluentKit.o" -o "$EXPANSION_APP/Contents/MacOS/TreeExpansionReview"
