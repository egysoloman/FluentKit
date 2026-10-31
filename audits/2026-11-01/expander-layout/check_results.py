#!/usr/bin/env python3
"""Validate geometry from the actual Gallery drivers, independently of XCTest."""
import json
from pathlib import Path
import struct
import sys

output = Path(sys.argv[1])
records = json.loads((output / "results.json").read_text())
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

if "children" in records[0]:
    check(len(records) == 24, "Expected 24 Gallery expander states")
    for row in records:
        name = f"{row['variant']}-{row['state']}"
        # Both renderers use a fixed 2x bitmap scale, independent of the screen's backing scale.
        png = (output / "images" / f"{name}.png").read_bytes()
        width = struct.unpack(">I", png[16:20])[0] / 2
        if not row["viewportHidden"]:
            check(abs(row["viewportHeight"] - row["expectedContentHeight"]) < 0.5,
                  f"{name}: expanded viewport does not follow content")
        check(row["outerFrame"][0] + row["outerFrame"][2] <= width + 0.5,
              f"{name}: settings card exceeds the visible window")
        check(len(row["children"]) == 2, f"{name}: actual Expander page is missing")
        for child in row["children"]:
            check(child["bounds"][2] <= child["parentBounds"][2] + 0.5,
                  f"{name}: inner expander exceeds its allocated width")
else:
    check(len(records) == 100, "Expected 100 integrated window/page/expander states")
    for row in records:
        name = f"{row['variant']}-{row['state']}"
        for layer in row["layers"]:
            check(all(abs(a - b) < 0.5 for a, b in zip(layer["frame"], layer["presentation"])),
                  f"{name}: {layer['name']} presentation geometry lags")
        if row["state"].startswith("page"):
            check(row["expanderCount"] == 2, f"{name}: navigation left stale page content")
    for variant in {r["variant"] for r in records}:
        states = {r["state"]: r for r in records if r["variant"] == variant}
        expanded, collapsed = states["page-08"], states["both-collapsed"]
        delta = expanded["viewportHeight"] - collapsed["viewportHeight"]
        check(delta > 0, f"{variant}: nested collapse did not shrink its outer viewport")
        check(abs(expanded["documentHeight"] - collapsed["documentHeight"] - delta) < 0.5,
              f"{variant}: scroll document retained stale extent")
        check(abs(collapsed["followingRowFrame"][1] - expanded["followingRowFrame"][1] - delta) < 0.5,
              f"{variant}: following row did not move with the expander")
        check(states["outer-closed"]["viewportHidden"], f"{variant}: closed outer content remains visible")
        check(not states["reopened-resized"]["viewportHidden"], f"{variant}: reopen/resize left content hidden")

summary = {"states": len(records), "failures": errors}
(output / "checks.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
sys.exit(bool(errors))
