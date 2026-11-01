#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parent
summary = {}
for version in ["before", "after"]:
    rows = json.loads((root / version / "results.json").read_text())
    errors = []
    if len(rows) != 28:
        errors.append({"condition": "28 scenarios", "actual": len(rows)})
    for row in rows:
        scenario = row["scenario"]
        expected = {
            "model": "Ap" if scenario == "focus" else "Pear",
            "field": "Ap" if scenario == "focus" else "Pear",
            "submitted": "Pear" if scenario.startswith("closure") else "",
            "chosen": "none",
            "transientRows": [],
            "rows": ["Pear result"] if scenario == "provider-fresh" else [],
            "editorPreserved": True,
        }
        for field, value in expected.items():
            if row[field] != value:
                errors.append({"scenario": scenario, "rtl": row["rtl"], "preview": row["preview"],
                               "field": field, "actual": row[field], "expected": value})
    summary[version] = {"states": len(rows), "fieldDifferences": len(errors), "errors": errors}
(root / "comparison.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({key: {k: v for k, v in value.items() if k != "errors"} for key, value in summary.items()}, indent=2))
raise SystemExit(bool(summary["after"]["errors"]))
