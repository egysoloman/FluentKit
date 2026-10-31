#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from io import BytesIO
from PIL import Image, ImageChops, ImageStat, ImageCms

root = Path(sys.argv[1])
rows = json.loads((root / "navigation-after/results.json").read_text())
assert len(rows) == 60, len(rows)
for row in rows:
    assert row["currentIdentityRetained"], row
    if row["state"] in ("resized", "settled", "reduced"):
        assert (row["entries"], row["animations"], row["snapshots"]) == (1, 0, 0), row
    if row["state"] == "interrupted":
        assert row["snapshots"] == 1, row
        if row["variant"].split("-")[0] in ("slide", "entrance", "bottomUp"):
            assert row["redPixels"] > 10000 and row["opaquePixels"] > 10000, row

native = json.loads((root / "after/results.json").read_text())
for key in ("resizedIncomingAnimations", "resizedTitleAnimations", "resizedBackAnimations", "settledOverlays", "settledIncomingAnimations", "closedOverlays", "closedIncomingAnimations", "closedTitleAnimations"):
    assert native[key] == 0, (key, native[key])
assert native["resizedOverlayFrames"] == []
assert native["reversingBackImage"]
assert abs(native["reversingBackOpacity"] - native["visibleLeavingBackOpacity"]) < 0.05
assert abs(native["reversingEntranceOpacity"] - native["reversingBackOpacity"]) < 0.001

def read(path):
    im = Image.open(path).convert("RGBA")
    if im.info.get("icc_profile"):
        im = ImageCms.profileToProfile(im, ImageCms.ImageCmsProfile(BytesIO(im.info["icc_profile"])), ImageCms.createProfile("sRGB"), outputMode="RGBA")
    return im

comparisons = {}
for folder in ("baseline-final", "after"):
    images = root / folder / "images"
    if not images.exists():
        continue
    comparisons[folder] = {}
    for state in ("initial", "interrupt"):
        delta = ImageChops.difference(read(images / f"{state}-snapshot.png"), read(images / f"{state}-presentation.png"))
        comparisons[folder][state] = sum(ImageStat.Stat(delta).mean[:3]) / 3
assert comparisons["after"]["initial"] < 1
assert comparisons["after"]["interrupt"] < 10, comparisons

settings = json.loads((root / "settings-after/results.json").read_text())
for row in settings:
    if row["state"].startswith(("detail-", "return-")) or row["state"] == "before-resize":
        assert (row["outgoingPages"], row["incomingPages"]) == (1, 1), row
    if row["state"] in ("resized", "settled", "final"):
        assert (row["outgoingPages"], row["incomingPages"], row["titleAnimations"]) == (0, 0, 0), row
summary = {"navigation_states": len(rows), "settings_states": len(settings), "snapshot_mean_rgb_error": comparisons}
(root / "checks.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
print("PASS:", json.dumps(summary, ensure_ascii=False))
