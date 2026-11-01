import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
failures = []
for row in rows:
    name = row["variant"] + "/" + row["phase"]
    active = row["phase"] == "opened" or row["kind"] == "resize"
    checks = {"binding": row["binding"] == active, "visibility": row["visible"] == active,
              "parent ownership": row["hasParent"] == active, "one opening": row["opened"] == 1,
              "unload closes once": row["closed"] == (0 if active else 1), "no cancellable unload": row["closing"] == 0}
    if row["kind"] == "resize" and row["phase"] == "changed":
        checks.update({"target moved": abs(row["targetMovementX"] - 100) < 0.5,
                       "panel follows": abs(row["panelMovementX"] - row["targetMovementX"]) < 0.5,
                       "content preserved": row["sameContent"], "responder preserved": row["sameResponder"]})
    failures.extend({"state": name, "check": key} for key, passed in checks.items() if not passed)
if len(rows) != 32:
    failures.append({"state": "all", "check": "Expected 32 states"})
print(json.dumps({"states": len(rows), "failedStates": len({x["state"] for x in failures}), "failures": failures}, indent=2))
sys.exit(bool(failures))
