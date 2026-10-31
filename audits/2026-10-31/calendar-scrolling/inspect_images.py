#!/usr/bin/env python3
"""Optional contact sheets and strict RGBA checks; requires Pillow."""
import hashlib
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw

output = Path(sys.argv[1])
images = output / 'images'
for phase in ['initial', 'partial', 'far']:
    files = [images / f'{scheme}-{direction}-{mode}-{phase}.png'
             for scheme in ['light', 'dark'] for direction in ['ltr', 'rtl']
             for mode in ['month', 'year', 'decade']]
    sheet = Image.new('RGB', (1050, 1640), '#aaa')
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(files):
        frame = Image.open(path).convert('RGB')
        frame.thumbnail((350, 390))
        x, y = index % 3 * 350, index // 3 * 410
        sheet.paste(frame, (x, y + 20))
        draw.text((x + 5, y + 3), path.stem, fill='black')
    sheet.save(output / f'{phase}-contact-sheet.png')

rows = []
for far in sorted(images.glob('*-far.png')):
    refresh = far.with_name(far.name.replace('-far.png', '-refresh.png'))
    a, b = Image.open(far).convert('RGBA'), Image.open(refresh).convert('RGBA')
    assert a.size == b.size and a.tobytes() == b.tobytes(), far
    rows.append({'variant': far.stem.removesuffix('-far'), 'farRefreshPixelsEqual': True,
                 'rgbaSha256': hashlib.sha256(a.tobytes()).hexdigest()})
assert len(rows) == 12
(output / 'refresh-pixel-check.json').write_text(json.dumps(rows, indent=2) + '\n')
print('12 far/refresh pairs match across every RGBA byte.')
