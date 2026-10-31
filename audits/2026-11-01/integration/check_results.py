#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
rows = json.loads((root / 'settings/states.json').read_text())
assert len({r['searchIdentity'] for r in rows}) == 1
menus = [m for r in rows for m in r['menus']]
assert menus and {m['appearance'] for m in menus} >= {'NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'}
menu_sizes = {tuple(map(float, re.findall(r'[\d.]+', m['frame'])[-2:])) for m in menus}
assert (180, 80) in menu_sizes and menu_sizes <= {(180, 80), (180, 116)}
presses = [r for r in rows if r['reason'].startswith('NSEventType(rawValue: 1)') and r['toggles']]
assert any(t['presentationKnob'] == '{{0, 0}, {17, 14}}' for r in presses for t in r['toggles'])
assert all(t['track'] == '{{0, 0}, {40, 20}}' for r in rows for t in r['toggles'])
assert any(r['reason'] == 'app-light' and r['preference'] == 'dark'
           and r['appearance'] == 'NSAppearanceNameDarkAqua' for r in rows)
marked = [r for r in rows if r['marked'] and r['reason'] in ['manual', 'app-light', 'app-dark']]
assert marked and all(r['search'] == 'hua' for r in marked)
assert len({r['editorIdentity'] for r in marked}) == 1
assert {r['appearance'] for r in marked} == {'NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'}
assert all(r['inputSource'] == 'org.fluentime.inputmethod.FluentIME.Hans' for r in marked)
assert rows[-1]['search'] == '' and not rows[-1]['marked']
captures = [(i + 1, r) for i, r in enumerate(rows) if r['reason'] == 'manual']
zoomed = [(i, r) for i, r in captures if float(re.findall(r'[\d.]+', r['window'])[-2]) > 1000]
assert zoomed
colors = []
for i, row in zoomed:
    image = Image.open(root / 'settings' / f'capture-{i}.png').convert('RGB')
    samples = [image.getpixel((int(image.width * x), int(image.height * y)))
               for x, y in [(.25, .9), (.75, .9), (.95, .9), (.95, .5)]]
    assert len(set(samples)) == 1
    colors.append(samples[0])
toggles = json.loads((root / 'toggle/metrics.json').read_text())
assert len(toggles) == 24
for r in toggles:
    expected = (12, 12) if r['override'] else {'normal': (12, 12), 'hover': (14, 14), 'pressed': (17, 14)}[r['state']]
    assert (r['knobWidth'], r['knobHeight']) == expected
result = {'interactiveStates': len(rows), 'searchNativeInstances': 1, 'markedInputSource': marked[0]['inputSource'],
          'compositionPreservedAcrossThemes': True, 'menuSize': '180x80pt', 'switchStates': len(toggles),
          'maximizedBackgroundRGB': colors, 'nativeCandidatePositionVerified': False}
(root / 'checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False))
