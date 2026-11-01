#!/usr/bin/env python3
"""Check rendered description space, in addition to the existing Expander geometry gates."""
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
failures = []
assert len(rows) == 24
for row in rows:
    if row["descriptionFrame"][3] + 0.5 < row["descriptionMeasuredHeight"]:
        failures.append({"variant": row["variant"], "state": row["state"],
                         "available": row["descriptionFrame"][3],
                         "required": row["descriptionMeasuredHeight"]})
    if row["state"] in ("narrow", "wide", "restored"):
        expected = {"narrow": 820, "wide": 1400, "restored": 1120}[row["state"]]
        assert abs(row["rootBounds"][2] - expected) < 0.5, "Window grew instead of honoring the requested width"
print(json.dumps({"states": len(rows), "clippedDescriptions": failures}, indent=2))
sys.exit(bool(failures))
