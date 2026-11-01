#!/usr/bin/env python3
"""Check captured client rectangles; this does not validate IME candidate windows."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
rows = json.loads((root / "client-reference/states.json").read_text())
queries = [r for r in rows if r["reason"] == "manual-coordinate-query"]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


check(len(queries) == 9, "expected nine explicit coordinate queries")
for client, widths in [("actual-settings", [640, 600, 1000, 640]),
                       ("native-search", [640, 600, 1000, 640]),
                       ("native-text", [640])]:
    states = [r for r in queries if r["client"] == client]
    check([r["window"]["width"] for r in states] == widths, f"{client}: widths")
    check(len({r["editorIdentity"] for r in states}) == 1, f"{client}: editor replaced")
    offsets = []
    for r in states:
        frame, rect = r["searchScreen"], r["firstRect"]
        check(r["editorText"] == "hua" and not r["marked"], f"{client}: plain text premise")
        check(rect["width"] == 0 and rect["height"] > 0, f"{client}: caret dimensions")
        check(frame["x"] <= rect["x"] <= frame["x"] + frame["width"], f"{client}: caret x")
        check(frame["y"] <= rect["y"] and rect["y"] + rect["height"] <= frame["y"] + frame["height"],
              f"{client}: caret y")
        offsets.append((rect["x"] - frame["x"], rect["y"] - frame["y"]))
    check(len(set(offsets)) == 1, f"{client}: relative character position changed")

actual = [r for r in queries if r["client"] == "actual-settings"]
check([r["searchScreen"]["width"] for r in actual] == [310, 270, 480, 310], "settings declared widths")
check(actual[2]["firstRect"]["x"] - actual[0]["firstRect"]["x"] == 95, "wide settings character shift")
check(rows[-1]["reason"] == "quit", "client did not finish")

source_mismatches = []
for line in (root / "client-reference/source-sha256.txt").read_text().splitlines():
    expected, filename = line.split("  ", 1)
    path = Path(filename)
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        source_mismatches.append(filename)

result = {"coordinateQueries": len(queries), "errors": errors,
          "systemPinyinMarkedQueries": sum(r["marked"] and r["inputSource"] == "com.apple.inputmethod.SCIM.ITABC" for r in queries),
          "sourceMismatchesSinceBuild": source_mismatches,
          "candidateWindowValidation": "not established; no stable system-Pinyin composition was captured"}
(root / "checks.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(bool(errors))
