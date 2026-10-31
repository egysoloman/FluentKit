#!/usr/bin/env python3
import json
from pathlib import Path
import sys
from PIL import Image, ImageChops

root = Path(sys.argv[1])
rows = json.loads((root / 'results.json').read_text())
assert len(rows) == 32
assert len({r['variant'] for r in rows}) == 8
assert all(r['calls'] == 0 and r['width'] == 40 and r['height'] == int(r['variant'].rsplit('-', 1)[1]) - 4 for r in rows)
for variant in {r['variant'] for r in rows}:
    first = Image.open(root / 'images' / f'{variant}-normal.png').convert('RGBA')
    redisplayed = Image.open(root / 'images' / f'{variant}-redisplayed.png').convert('RGBA')
    assert ImageChops.difference(first, redisplayed).getbbox(alpha_only=False) is None
print('8/8 redisplayed controls match normal pixels; 32 states keep dimensions and do not invoke before release')
