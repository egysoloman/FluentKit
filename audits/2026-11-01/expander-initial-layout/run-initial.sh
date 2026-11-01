#!/bin/zsh
set -eu
EXPANDER_AUDIT="$(cd "$(dirname "$0")" && pwd)"
EXPANDER_PRODUCTS="${1:?Provide the SwiftPM products directory}"
EXPANDER_OUTPUT="${2:?Provide a new output directory}"
EXPANDER_BIN="${TMPDIR:-/tmp}/fluentkit-expander-initial-probe"
mkdir -p "$EXPANDER_BIN" "$EXPANDER_OUTPUT"
cp -R "$EXPANDER_PRODUCTS/FluentKit_FluentKit.bundle" "$EXPANDER_BIN/"
swiftc -g -parse-as-library -swift-version 5 -warnings-as-errors -I "$EXPANDER_PRODUCTS" \
    "$EXPANDER_AUDIT/InitialLayoutAudit.swift" "$EXPANDER_PRODUCTS/FluentKit.o" -o "$EXPANDER_BIN/InitialLayoutAudit"
lldb -b -o 'breakpoint set -n LAYOUT_CONSTRAINTS_NOT_SATISFIABLE' -o run \
    -o 'breakpoint list' -o quit "$EXPANDER_BIN/InitialLayoutAudit" > "$EXPANDER_OUTPUT/debugger.log" 2>&1
python3 - "$EXPANDER_OUTPUT/debugger.log" <<'PY'
import sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
assert 'exited with status = 0' in text, 'Probe did not finish successfully'
assert 'locations = 1, resolved = 1, hit count = 0' in text, 'Constraint breakpoint did not resolve or was hit'
assert 'Conflicting constraints' not in text
print('Initial-layout probe completed; resolved AppKit constraint breakpoint: 0 hits.')
PY
