"""Check the straight focus edges in actual 1x/2x native layer renders, not just path metadata."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
result = {}
for stage in ['before', 'after']:
    rows = json.loads((root / stage / 'native/results.json').read_text())
    samples, errors = [], []
    for row in rows:
        if not row['id'].endswith('-down'):
            continue
        for scale in [1, 2]:
            name = row['id'][:-5] + f'-{scale}x.png'
            im = Image.open(root / stage / 'native' / name).convert('RGB')
            background = im.getpixel((0, 0))
            for label, y, brush in [('outside', 29, None), ('primary-outer', 30, 'outer'),
                                    ('primary-inner', 31, 'outer'), ('secondary', 32, 'inner')]:
                actual = im.getpixel((110 * scale, y * scale + scale // 2))
                expected = background
                if brush:
                    color = row['expected'][brush]['color']
                    expected = tuple(round(color[i] * 255 * color[3] + background[i] * (1 - color[3])) for i in range(3))
                sample = {'image': name, 'sample': label, 'actual': actual, 'expected': expected}
                samples.append(sample)
                if max(abs(a-b) for a, b in zip(actual, expected)) > 3:
                    errors.append(sample)
    result[stage] = {'samples': len(samples), 'mismatches': len(errors), 'errors': errors, 'measurements': samples}
    print(stage, 'pixel samples:', len(samples), 'mismatches:', len(errors))
(root / 'pixels.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(bool(result['after']['errors']))
