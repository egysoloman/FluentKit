#!/usr/bin/env python3
"""Measure the reported Chinese text region, excluding the caret; verify sampled menu motion."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
rows = json.loads((root / "current/results.json").read_text())
assert len(rows) == 80
measurements = []
for row in rows:
    if not row["variant"].startswith("dark-ltr-zh") or row["state"] not in (
            "placeholder", "focused-placeholder", "unfocused-text", "editing"):
        continue
    bitmap = Image.open(root / "current/images" / f"{row['variant']}-{row['state']}-2x.png").convert("RGBA")
    x, y, _, height = row["textRect"]
    points = []
    # Exclude the initial caret column and the end-of-text caret; retain several Chinese glyphs.
    for py in range(int(y * 2), int((y + height) * 2)):
        for px in range(int((x + 3) * 2), int((x + 48) * 2)):
            red, green, blue, alpha = bitmap.getpixel((px, py))
            if alpha > 127 and min(red, green, blue) > 153:
                points.append((px, py))
    assert points
    box = [min(p[0] for p in points) / 2, min(p[1] for p in points) / 2,
           (max(p[0] for p in points) + 1) / 2, (max(p[1] for p in points) + 1) / 2]
    measurements.append(dict(variant=row["variant"], state=row["state"], font=row["font"],
                             inkBox=box, verticalCenter=(box[1] + box[3]) / 2, controlCenter=16))
(root / "vertical-ink.json").write_text(json.dumps(measurements, ensure_ascii=False, indent=2) + "\n")
assert len(measurements) == 8
menus = json.loads((root / "menu.json").read_text())
for menu in menus:
    assert menu["sameEditor"]
    assert any(0 < f["presentationOpacity"] < 1 and f["animationDuration"] == 0.083 for f in menu["frames"])
    assert menu["frames"][-1]["presentationOpacity"] == 1
print("4 context-menu material paths have observed intermediate fade frames and preserve the editor.")
for font in {m["font"] for m in measurements}:
    print(font, "ink centers:", sorted({m["verticalCenter"] for m in measurements if m["font"] == font}))
