#!/usr/bin/env python3
"""Check live refresh and resize observations from the public Release probe."""
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
expected = {(f"{scheme}-{direction}", phase) for scheme in ("light", "dark")
            for direction in ("ltr", "rtl") for phase in ("open", "refresh", "wide", "narrow")}
assert len(rows) == len(expected) and {(r["variant"], r["phase"]) for r in rows} == expected
for row in rows:
    assert row["isOpen"] and row["samePanel"] and row["sameFocus"], row
    assert row["hiddenOverflowCount"] == 0, row
    assert row["clipCoversPopup"], row
    assert row["retainedPrimaryCount"] == 4 and row["retainedSecondaryCount"] == 1, row
    assert row["openEvents"] == [], row
    assert row["overflow"] == {"open": [2, 3], "refresh": [2, 3], "wide": [], "narrow": [1, 2, 3]}[row["phase"]], row
print(f"CommandBar lifecycle: {len(rows)} light/dark, LTR/RTL refresh/resize states passed")
