#!/usr/bin/env python3
"""Check the resized and restored public header geometry in the standalone probe."""
import json
import math
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
expected = {(f"{kind}-{scheme}-{direction}", width)
            for kind in ("list", "grid") for scheme in ("light", "dark")
            for direction in ("ltr", "rtl") for width in (600, 180, 40, 1200, 320)}
assert len(rows) == len(expected) and {(r["variant"], r["requestedWidth"]) for r in rows} == expected
for row in rows:
    assert row["headers"], row
    for header in row["headers"]:
        width = header["header"]["width"]
        slot_width = max(0, width - 24)
        start = width - 12 - slot_width if row["variant"].endswith("rtl") else 12
        for key in ("label", "divider"):
            r = header[key]
            assert all(math.isfinite(v) for v in r.values()) and r["width"] >= 0 and r["height"] >= 0, header
        label, divider = header["label"], header["divider"]
        assert label["width"] <= slot_width + 0.5, header
        label_start = width - 12 - label["width"] if row["variant"].endswith("rtl") else 12
        assert abs(label["x"] - label_start) < 0.5, header
        assert abs(divider["width"] - slot_width) < 0.5 and abs(divider["x"] - start) < 0.5, header
        assert abs(header["label"]["y"] - 8) < 0.5 and header["divider"]["height"] == 1, header
    if row["requestedWidth"] == 320:
        assert row["scrollY"] > 0, row
print(f"Header layout: {len(rows)} resize/restore states passed")
if len(sys.argv) > 2:
    templates = json.loads(Path(sys.argv[2]).read_text())
    assert len(templates) == 6 and {(r["rtl"], r["template"]) for r in templates} == {(d, t) for d in (False, True) for t in range(3)}
    for row in templates:
        assert abs(row["width"] - row["expectedWidth"]) < 0.5, row
        assert abs(row["x"] - row["expectedX"]) < 0.5, row
    print("Header content: 6 natural/stretch template states passed")
