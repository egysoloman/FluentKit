#!/usr/bin/env python3
"""Reject AppKit layout conflicts that XCTest can otherwise report as passing tests."""
import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: check_test_diagnostics.py <swift-test-log>")

diagnostic = re.compile(r"Conflicting constraints|Unable to simultaneously satisfy constraints", re.IGNORECASE)
matches = [f"{number}: {line}" for number, line in
           enumerate(Path(sys.argv[1]).read_text(errors="replace").splitlines(), 1)
           if diagnostic.search(line)]
if matches:
    raise SystemExit("AppKit constraint conflicts in test output:\n" + "\n".join(matches))
print("AppKit constraint diagnostics: none")
