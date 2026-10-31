#!/usr/bin/env python3
import json
import sys

rows = json.load(open(sys.argv[1]))
assert len(rows) == 108, len(rows)
errors = []
for row in rows:
    closed = row["phase"] in ("clipped", "return", "escape")
    if row["popupOpen"] == closed:
        errors.append((row["variant"], row["phase"], "visibility"))
    if not closed:
        if abs(row.get("belowGap", 999) - 2) > 0.5 or abs(row.get("horizontalError", 999)) > 0.5:
            errors.append((row["variant"], row["phase"], "anchor"))
        if not row["editorFocused"]:
            errors.append((row["variant"], row["phase"], "focus"))
assert not errors, errors
print(f"PASS: {len(rows)} AutoSuggestBox scroll/ancestor/resize/dismiss/reopen states")
