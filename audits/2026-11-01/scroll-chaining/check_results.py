#!/usr/bin/env python3
"""Check a newly rendered Release probe; baseline failure is preserved separately."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
rows = json.loads((root / 'results.json').read_text())
assert len(rows) == 48
variants = {row['variant'] for row in rows}
assert len(variants) == 16
for variant in variants:
    states = {row['phase']: row for row in rows if row['variant'] == variant}
    assert set(states) == {'initial', 'partial', 'settled'}
    assert states['initial']['outerSelection'] == 1
    assert states['partial']['outerSelection'] == 1
    assert states['settled']['outerSelection'] == states['settled']['expectedOuter']
    assert len({row['innerSelection'] for row in states.values()}) == 1
    assert len(states['partial']['positions']) == 2
    for phase in states:
        assert (root / 'images' / f'{variant}-{phase}.png').is_file()
print('16/16 parent handoffs; inner selection preserved; 48 rendered states present')
