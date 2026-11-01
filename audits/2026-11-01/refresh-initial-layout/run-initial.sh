#!/bin/zsh
set -eu
REFRESH_AUDIT="$(cd "$(dirname "$0")" && pwd)"
REFRESH_PRODUCTS="${1:?Provide the SwiftPM products directory}"
REFRESH_OUTPUT="${2:?Provide a new output directory}"
REFRESH_BIN="${TMPDIR:-/tmp}/fluentkit-refresh-initial-probe"
mkdir -p "$REFRESH_BIN" "$REFRESH_OUTPUT"
cp -R "$REFRESH_PRODUCTS/FluentKit_FluentKit.bundle" "$REFRESH_BIN/"
swiftc -g -parse-as-library -swift-version 5 -warnings-as-errors -I "$REFRESH_PRODUCTS" \
    "$REFRESH_AUDIT/InitialLayoutAudit.swift" "$REFRESH_PRODUCTS/FluentKit.o" -o "$REFRESH_BIN/InitialLayoutAudit"
lldb -b -o 'breakpoint set -n LAYOUT_CONSTRAINTS_NOT_SATISFIABLE' -o run \
    -o 'breakpoint list' -o quit "$REFRESH_BIN/InitialLayoutAudit" > "$REFRESH_OUTPUT/debugger.log" 2>&1
python3 - "$REFRESH_OUTPUT/debugger.log" <<'PY'
import sys
from pathlib import Path
log=Path(sys.argv[1]).read_text()
assert 'exited with status = 0' in log, 'Probe did not finish successfully'
assert 'locations = 1, resolved = 1, hit count = 0' in log, 'Constraint breakpoint did not resolve or was hit'
assert 'Conflicting constraints' not in log
print('Initial-layout probe completed; resolved AppKit constraint breakpoint: 0 hits.')
PY
