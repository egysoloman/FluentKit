import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
failures = []
for row in rows:
    name = row["variant"] + "/" + row["phase"]
    x, y, width, height = row["panelFrame"]
    sx, sy, sw, sh = row["screen"]
    checks = {"width fits work area": x >= sx and x + width <= sx + sw,
              "faceplate minimum width": width >= row["anchorFrame"][2],
              "selection unchanged": row["selectionUnchanged"],
              "no action": row["commits"] == 0}
    checks.update({key: row[key] for key in ["samePanel", "sameContent", "sameResponder", "visible"]})
    failures.extend(name + ": " + key for key, passed in checks.items() if not passed)
if len(rows) != 16:
    failures.append("Expected 16 states")
print(json.dumps({"states": len(rows), "failures": failures}, indent=2))
sys.exit(bool(failures))
