"""Check recorded regression and external AX evidence, without claiming full VoiceOver parity."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
repo = root.parents[2]
baseline_test = root / "before/TreeViewExpansionEventTests.swift"
current_test = repo / "Tests/FluentKitTests/TreeViewExpansionEventTests.swift"
assert hashlib.sha256(baseline_test.read_bytes()).digest() == hashlib.sha256(current_test.read_bytes()).digest()
assert "Executed 3 tests, with 13 failures (0 unexpected)" in (root / "before/tests.log").read_text()
assert "Executed 407 tests, with 0 failures" in (root / "after/all-tests.log").read_text()
assert "FluentKitValidation: PASS" in (root / "after/native-validation.log").read_text()
assert "BUILD SUCCEEDED" in (root / "after/gallery-build.log").read_text()

before = json.loads((root / "before/interactive/states.json").read_text())
after = json.loads((root / "after/interactive/states.json").read_text())
def remote_is_expanded(state):
    return next(row["expanded"] for row in state["rows"] if row["labels"] == ["Remote"])
assert len(before) == 1 and len(after) == 3
assert "Expanded remote" in before[0]["text"] and not remote_is_expanded(before[0])
assert "Open Remote to load its children." in after[0]["text"] and not remote_is_expanded(after[0])
assert "Expanded remote" in after[1]["text"] and remote_is_expanded(after[1])
labels = [label for row in after[1]["rows"] for label in row["labels"]]
assert "Shared document" in labels and "Reference" in labels
assert "Collapsed remote" in after[2]["text"] and not remote_is_expanded(after[2])
assert len(json.loads((root / "after/gallery/results.json").read_text())) == 15
assert len(json.loads((root / "after/move-gallery/results.json").read_text())) == 12
print("PASS: 13 baseline failures, 407 passing tests, AX read/expand/collapse evidence and Gallery outputs.")
