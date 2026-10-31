#!/usr/bin/env python3
"""Measure visible glyphs separately from cell/editor frames; requires Pillow."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent

def glyph_bounds(folder, variant, state, scale, area):
    image = Image.open(folder / 'images' / f'{variant}-{state}-{scale}x.png').convert('RGBA')
    x, y, width, height = area
    points = []
    for py in range(int(y * scale), int((y + height) * scale)):
        for px in range(int(x * scale), int((x + width) * scale)):
            r, g, b, a = image.getpixel((px, py))
            ink = min(r, g, b) > 153 if variant.startswith('dark') else max(r, g, b) < 102
            if a > 127 and ink:
                points.append((px / scale, py / scale))
    assert points, (folder, variant, state, scale, 'no visible glyphs')
    return [min(p[i] for p in points) for i in (0, 1)] + [max(p[i] for p in points) for i in (0, 1)]

results = {}
for name in ('baseline', 'after'):
    folder = ROOT / name
    rows = json.loads((folder / 'results.json').read_text())
    assert len(rows) == 40
    variants = sorted({row['variant'] for row in rows})
    comparisons = []
    for variant in variants:
        area = next(row['textRect'] for row in rows if row['variant'] == variant)
        for idle, active in [('placeholder', 'focused-placeholder'), ('unfocused-text', 'editing')]:
            for scale in (1, 2):
                before = glyph_bounds(folder, variant, idle, scale, area)
                focused = glyph_bounds(folder, variant, active, scale, area)
                delta = [round(b - a, 3) for a, b in zip(before, focused)]
                comparisons.append(dict(variant=variant, idle=idle, scale=scale,
                                        inactiveInkBounds=before, activeInkBounds=focused, delta=delta))
                if name == 'after':
                    assert abs(delta[0]) <= 0.5, comparisons[-1]
                    # Direct native-cell and layer rasterization may differ by one device pixel.
                    assert max(abs(d) for d in delta) <= 1 / scale, comparisons[-1]
                else:
                    assert abs(delta[0] + 2) <= 0.5, comparisons[-1]
    results[name] = comparisons

for name, expected_padding in [('settings-before', 0), ('settings-after', 2)]:
    rows = json.loads((ROOT / name / 'results.json').read_text())
    assert len(rows) == 7 and all(row['sameSearchInstance'] for row in rows)
    active = [row for row in rows if 'padding' in row]
    assert all(row['padding'] == expected_padding for row in active)
    assert all(row['marked'] for row in rows if row['state'].startswith('marked'))
    assert all(abs(row['caretFrame'][0] - row['textRect'][0] - expected_padding) < 0.01 for row in active)
assert (ROOT / 'settings-before/app-source-sha256.txt').read_bytes() == (ROOT / 'settings-after/app-source-sha256.txt').read_bytes()
(ROOT / 'glyph-comparison.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
print('32 glyph comparisons per build: baseline shifts left 2pt; repaired left edges stable within 0.5pt, all bounds within one device pixel.')
print('Actual IME: same source hashes and search identity; marked text survives resize; native inset restored.')
