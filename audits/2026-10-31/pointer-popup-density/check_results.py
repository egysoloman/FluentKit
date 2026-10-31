import json
import sys
from pathlib import Path
from PIL import Image
root = Path(sys.argv[1])
rows = json.loads((root/'metrics.json').read_text())
assert len(rows) == 32
for row in rows:
    touch = row['variant'].endswith('-direct-touch')
    assert row['device'] == ('touch' if touch else 'keyboard' if row['variant'].endswith('-keyboard') else 'mouse'), row
    if row['variant'].endswith('-trackpad'): assert row['subtype'] == 3
    if row['kind'] == 'combo':
        assert row['width'] == (240 if touch else 180), row
        assert row['height'] == (104 if touch else 80), row
        assert row['rowHeights'] == ([48,48] if touch else [36,36]), row
    else:
        assert row['height'] == (92 if touch else 76), row
        # Menu row views exclude the 2pt top/bottom template margin; pitch is 36/44.
        assert row['rowHeights'] == ([40,40] if touch else [32,32]), row
    path = root/'images'/(row['variant']+'-'+row['kind']+'.png')
    image = Image.open(path).convert('RGBA')
    assert image.size == (row['width']*2,row['height']*2), path
    assert len(image.getcolors(image.width * image.height) or []) > 20, path
for path in (root/'images').glob('*-trackpad-*.png'):
    mouse = path.with_name(path.name.replace('-trackpad-','-mouse-'))
    a,b = Image.open(path).convert('RGBA'),Image.open(mouse).convert('RGBA')
    assert a.size == b.size and a.tobytes() == b.tobytes(), path
print('32 rendered popup/menu states passed; all 8 trackpad/mouse image pairs are pixel-identical.')
