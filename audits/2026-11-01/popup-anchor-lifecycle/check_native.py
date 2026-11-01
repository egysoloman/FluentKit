#!/usr/bin/env python3
"""Check public-API popup geometry and cleanup captures, retaining baseline failures."""
import argparse
import json
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
parser.add_argument("--expect-pass", action="store_true")
args = parser.parse_args()
records = json.loads((args.directory / "results.json").read_text())
assert len(records) == 48
assert len({(r["variant"], r["phase"]) for r in records}) == 48
assert len(list((args.directory / "images").glob("*.png"))) == 48
failures = Counter()
failed_states = 0
for record in records:
    checks = {"selection": record["selectionUnchanged"]}
    if record["shouldClose"]:
        checks.update(hidden=not record["visible"], detached=record["detached"])
        if record["kind"] == "menu":
            checks["dismiss_once"] = record["dismissals"] == 1
    else:
        checks.update(visible=record["visible"], attached=not record["detached"],
                      panel=record["samePanel"], content=record["sameContent"],
                      responder=record["sameResponder"], width=record["widthMatches"],
                      leading=record["leadingMatches"])
    errors = [name for name, passed in checks.items() if not passed]
    failures.update(errors)
    failed_states += bool(errors)
print(json.dumps({"states": len(records), "failed_states": failed_states,
                  "failed_fields": dict(failures)}, sort_keys=True))
if args.expect_pass and failed_states:
    raise SystemExit(1)
