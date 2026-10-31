#!/usr/bin/env python3
"""Validate hosted geometry and rendered corners, not just the configured radius."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent
summary = {}
for folder in ('baseline', 'after'):
    rows = json.loads((ROOT / folder / 'results.json').read_text())
    assert len(rows) == 64
    wrapped = [r for r in rows if r['wrapped']]
    overflow = [r['actualFrame'][2] - r['requestedWidth'] for r in wrapped]
    assert set(overflow) == ({4} if folder == 'baseline' else {0})
    assert all(r['radius'] == 4 and r['focusWidth'] == (2 if r['focused'] else 0) for r in rows)
    assert not any(r['nativeBezel'] or r['nativeBorder'] or r['nativeBackground'] for r in rows)
    corners = []
    for row in wrapped:
        for scale in (1, 2):
            im = Image.open(ROOT / folder / 'images' / f"{row['name']}-{scale}x.png").convert('RGBA')
            alpha = [im.getpixel((x, y))[3] / 255 for x in (0, im.width-1) for y in (0, im.height-1)]
            if folder == 'after':
                assert max(alpha) < 0.02, (row['name'], scale, alpha)
            elif row['focused']:
                assert max(alpha) > 0.1, (row['name'], scale, alpha)
            corners.append(dict(state=row['name'], scale=scale, alpha=alpha))
    summary[folder] = dict(states=len(rows), wrappedStates=len(wrapped), overflow=sorted(set(overflow)), corners=corners)

for folder in ('baseline', 'after'):
    rows = json.loads((ROOT / folder / 'disabled-text.json').read_text())
    assert len(rows) == 18
    for offset in range(0, len(rows), 3):
        normal, disabled, restored = rows[offset:offset+3]
        assert abs(normal['inkAlpha'] - restored['inkAlpha']) < 1/255
        if folder == 'after' or normal['type'] == 'FluentTextField':
            assert disabled['inkAlpha'] < normal['inkAlpha'] * 0.7
        else:
            assert disabled['inkAlpha'] == normal['inkAlpha']

for folder in ('settings-before', 'settings-after'):
    rows = json.loads((ROOT / folder / 'results.json').read_text())
    assert len(rows) == 7 and all(r['sameSearchInstance'] for r in rows)
    assert all(r['marked'] for r in rows if r['state'].startswith('marked'))
    for row in rows:
        assert row['alignmentInsets'] == ([0, 2, 0, 2] if folder.endswith('before') else [0, 0, 0, 0])
        slot = row['ancestors'][1]['bounds'][2]
        assert row['fieldFrame'][2] - slot == (4 if folder.endswith('before') else 0)
        if 'caretFrame' in row:
            assert row['caretFrame'][0] - row['textRect'][0] == 2
assert (ROOT/'settings-before/app-source-sha256.txt').read_bytes() == (ROOT/'settings-after/app-source-sha256.txt').read_bytes()
(ROOT/'comparison.json').write_text(json.dumps(summary, indent=2) + '\n')
print('64 states/build; hosted 4pt overflow removed; all 1x/2x corner samples clear after repair.')
print('Search/secure disabled placeholder ink updates immediately; actual IME retains identity and marked text.')
