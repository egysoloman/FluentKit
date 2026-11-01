#!/usr/bin/env python3
"""Check recorded geometry; no GUI operations or system preference changes."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read(path):
    return json.loads((ROOT / path).read_text())


def native_errors(rows):
    errors = []
    for row in rows:
        horizontal = row["kind"] == "refresh-horizontal"
        size_index = 3 if horizontal else 2
        position_index = 0 if horizontal else 1
        key = [row["kind"], row["rtl"], row["step"]]
        viewport = row["viewport"]
        if not all(math.isfinite(v) for v in viewport) or min(viewport[2:]) <= 0:
            errors.append([key, "invalid viewport"])
        if abs(row["document"][size_index] - viewport[size_index]) > 0.01:
            errors.append([key, "document cross-axis size"])
        if abs(viewport[position_index] - 100) > 1:
            errors.append([key, "scroll position"])
        if not horizontal and row["childMaxX"] > viewport[2] + 0.01:
            errors.append([key, "row extends beyond viewport"])
    return errors


def gallery_errors(rows):
    errors = []
    for row in rows:
        key = [row["dark"], row["rtl"], row["width"], row["step"], row["change"], row["scrollIndex"]]
        if row["document"][2] > row["viewport"][2] + 0.01:
            errors.append([key, "document exceeds viewport"])
        for expander in row["expanders"]:
            frame = expander["frame"]
            if not all(math.isfinite(v) for v in frame) or min(frame[2:]) < 0:
                errors.append([key, "invalid expander frame"])
            if frame[0] + frame[2] > row["document"][2] + 0.01:
                errors.append([key, "expander exceeds document"])
    return errors


def ime_errors(rows):
    errors = []
    for row in rows:
        key = [row["page"], row["width"], row["step"]]
        if row["requestedStyle"] != -1 and row["actualStyle"] != row["requestedStyle"]:
            errors.append([key, "requested scroller style rejected"])
        expected_gap = 24 if row["page"] == "preview" else 20
        if abs(row["rightGap"] - expected_gap) > 0.01:
            errors.append([key, "trailing space"])
        if abs(row["viewport"][1] - row["targetY"]) > 1:
            errors.append([key, "scroll position"])
        if row["childMaxX"] > row["viewport"][2] + 0.01:
            errors.append([key, "content exceeds viewport"])
    return errors


summary = {}
for name, before, after, count, check in [
    ("native", "before/results.json", "after-final/results.json", 88, native_errors),
    ("gallery", "before/gallery-results.json", "after/gallery-results.json", 192, gallery_errors),
    ("ime", "ime-before-current/results.json", "ime-after/results.json", 105, ime_errors),
]:
    old, new = read(before), read(after)
    assert len(old) == len(new) == count, (name, len(old), len(new))
    old_errors, new_errors = check(old), check(new)
    assert old_errors, (name, "baseline must expose a regression")
    summary[name] = {"statesPerBuild": count, "beforeErrors": old_errors, "afterErrors": new_errors}
    assert not new_errors, (name, new_errors)
    print(f"{name}: {count} states; {len(old_errors)} -> {len(new_errors)} failed conditions")
(ROOT / "comparison.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
