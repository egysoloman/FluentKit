#!/usr/bin/env python3
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
assert len(rows) == 32
failures = []
for row in rows:
    expected = 80 if row["phase"] == "screen-notification" else 0
    conditions = {
        "movement": abs(row["movementX"] - expected) < 0.5,
        "panelIdentity": row["samePanel"], "contentIdentity": row["sameContent"],
        "responderIdentity": row["sameResponder"], "visible": row["visible"],
        "noCommit": row["commits"] == 0 and row["selection"] == "中文",
    }
    for condition, passed in conditions.items():
        if not passed: failures.append({"variant": row["variant"], "phase": row["phase"], "condition": condition})
print(json.dumps({"states": len(rows), "failures": failures}, indent=2))
sys.exit(bool(failures))
