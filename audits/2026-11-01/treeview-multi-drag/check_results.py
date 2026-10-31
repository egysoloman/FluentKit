"""Check saved evidence; this does not certify a successful native drag/drop."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent

def read(name):
    return json.loads((root / name).read_text())

assert read("before/lazy-load.json")["movedEntriesPreserved"] is False
loaded = read("after/lazy-load.json")
assert loaded["movedEntriesPreserved"] is True
assert loaded["afterLoad"] == ["plan", "notes", "remote-a", "remote-b"]

states = read("after/move-gallery/results.json")
assert len(states) == 12
expected = {
    "moved-into-unloaded": ["Work", "Specs", "Remote"],
    "loaded-preserves-moved": ["Work", "Specs", "Remote", "Plan", "Notes", "Shared document", "Reference"],
    "group-order": ["Remote", "Plan", "Notes", "Shared document", "Reference", "Work", "Specs"],
    "failed-transaction-preserves-tree": ["Remote", "Plan", "Notes", "Shared document", "Reference", "Work", "Specs"],
}
assert {(s["variant"], s["phase"]) for s in states} == {
    (variant, phase) for variant in ("light", "dark", "rtl") for phase in expected
}
for state in states:
    assert state["width"] == 600
    assert state["labels"] == expected[state["phase"]]

before = read("before/pointer-interactive/states.json")[0]
after = read("after/interaction-trace/states.json")
assert "Checked: 1" in before["text"] and "Invoked notes" in before["text"]
assert "Checked: 2" in after[0]["text"] and "Invoked notes" not in after[0]["text"]
assert any(row["labels"] == ["Spec A"] for row in after[1]["rows"])

trace = read("after/launch-services/drag-events.json")
begin = next(event for event in trace if event["event"] == "begin")
assert begin["localMask"] == 16
assert begin["pasteboardTypes"] == begin["registeredTypes"] == ["com.fluentkit.treeview.node"]
components = next(event["components"] for event in trace if event["event"] == "image")
assert any(item["key"] == "FluentKit.TreeView.Count" for item in components)
# Preserve the incomplete result rather than treating a dragging image as successful acceptance.
assert not any(event["event"] == "accept" for event in trace)
assert "Executed 401 tests, with 0 failures" in (root / "after/all-tests-final.log").read_text()
assert "FluentKitValidation: PASS" in (root / "after/native-final.log").read_text()
assert "BUILD SUCCEEDED" in (root / "after/gallery-pointer-build.log").read_text()
print("PASS: lazy-load preservation, 12 Gallery states, pointer routing, 401 tests and build evidence.")
print("OPEN: complete native drag/drop acceptance; this check does not close it.")
