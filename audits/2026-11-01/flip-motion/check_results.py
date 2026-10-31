#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
data = {name: json.loads((root / name / 'results.json').read_text()) for name in ('before', 'after')}
summary = {}
for name, rows in data.items():
    assert len(rows) == 108
    deltas = []
    lost = 0
    for variant in {r['variant'] for r in rows}:
        states = {r['state']: r for r in rows if r['variant'] == variant}
        for a, b in [('first', 'interrupted'), ('before-reverse', 'reversed')]:
            previous = {p['id']: p for p in states[a]['pages'] if not p['hidden']}
            current = {p['id']: p for p in states[b]['pages'] if not p['hidden']}
            lost += len(previous.keys() - current.keys())
            deltas += [abs(current[k]['position'] - previous[k]['position']) for k in previous.keys() & current.keys()]
        if name == 'after':
            for state in ('settled', 'jump', 'resized', 'final', 'reduced'):
                row = states[state]
                visible = [p for p in row['pages'] if not p['hidden']]
                assert len(visible) == 1, row
                assert abs(visible[0]['position']) < .01, row
                assert visible[0]['id'].endswith('.' + str(row['selected'])), row
            assert states['jump']['builds'] - states['settled']['builds'] == 2
            assert states['interrupted']['callbacks'] == [1, 2]
            assert states['reversed']['callbacks'] == [1, 2, 1]
    summary[name] = {'max_interrupt_jump_pt': max(deltas), 'lost_visible_pages': lost,
                     'max_mounted': max(r['mounted'] for r in rows)}
    if name == 'after':
        assert lost == 0 and max(deltas) < 2, summary[name]
        assert max(r['mounted'] for r in rows) <= 5
        for path in (root / name / 'images').glob('*.png'):
            alpha = Image.open(path).convert('RGBA').getchannel('A')
            opaque = sum(count for value, count in enumerate(alpha.histogram()) if value > 120)
            assert opaque / (alpha.width * alpha.height) > .98, path
(root / 'checks.json').write_text(json.dumps(summary, indent=2) + '\n')
print('PASS:', json.dumps(summary))
