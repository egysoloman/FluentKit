"""Verify recorded native render/binding results; physical gestures remain a separate check."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
before = json.loads((root / "before/native/results.json").read_text())
after = json.loads((root / "after/native/results.json").read_text())
assert len(before) == 56 and len(after) == 72
variants = {f"{scheme}-{direction}-{height}" for scheme in ("light", "dark")
            for direction in ("ltr", "rtl") for height in (32, 48)}
phases = {"idle", "hover", "down", "outside", "cancelled", "reentered", "committed", "chevron-down", "chevron-up"}
assert {(row["variant"], row["phase"]) for row in after} == {(v, p) for v in variants for p in phases}
def expected_checked(phase):
    return ["child", "root"] if phase in ("committed", "chevron-down", "chevron-up") else []
old_mismatches = sum(row["checked"] != expected_checked(row["phase"]) for row in before)
assert old_mismatches == 32
for row in after:
    assert row["checked"] == expected_checked(row["phase"]), row
    assert row["expanded"] == (["root"] if row["phase"].startswith("chevron-") else []), row
    assert row["width"] == 320
for variant in variants:
    states = {row["phase"]: row for row in after if row["variant"] == variant}
    idle = states["idle"]["fill"]
    assert states["hover"]["fill"] != idle
    assert states["down"]["fill"] not in (idle, states["hover"]["fill"])
    assert states["outside"]["fill"] == states["cancelled"]["fill"] == idle
    assert states["reentered"]["fill"] == states["down"]["fill"]
assert "Executed 404 tests, with 0 failures" in (root / "after/all-tests.log").read_text()
assert "FluentKitValidation: PASS" in (root / "after/native-validation.log").read_text()
assert "BUILD SUCCEEDED" in (root / "after/gallery-build.log").read_text()
interactive = json.loads((root / "after/interactive/states.json").read_text())
assert len(interactive) == 3
assert all("Checked: 2" in state["text"] for state in interactive)
assert not any(row["labels"] == ["Spec A"] for row in interactive[1]["rows"])
assert any(row["labels"] == ["Spec A"] for row in interactive[2]["rows"])
events = json.loads((root / "after/interactive/drag-events.json").read_text())
assert any(event.get("type") == 6 for event in events)
assert not any(event["event"] == "begin" for event in events), "Checkbox drags must not start data reordering"
print(f"PASS: 72 rendered states; {old_mismatches} recorded binding mismatches before, 0 after; 404 tests and builds.")
