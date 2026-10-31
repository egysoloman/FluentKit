#!/usr/bin/env python3
"""Validate retained menu branches and the rendered shared clips after live updates."""
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text())
phases = ('open', 'refresh', 'content', 'reorder', 'direction')
expected = {(f'{scheme}-{direction}', phase) for scheme in ('light', 'dark') for direction in ('ltr', 'rtl') for phase in phases}
assert len(rows) == len(expected) and {(r['variant'], r['phase']) for r in rows} == expected
for row in rows:
    assert all(row[k] for k in ('sameRoot', 'sameChild', 'retainedTop', 'retainedLeaf', 'leafSelected', 'rootClip', 'childClip')), row
    assert row['retainedRootRows'] == 2, row
    assert row['openIndex'] == (1 if row['phase'] in ('reorder', 'direction') else 0), row
    assert row['childCount'] == (2 if row['phase'] in ('open', 'refresh') else 3), row
    direction = row['variant'].split('-')[-1]
    if row['phase'] == 'direction': direction = 'ltr' if direction == 'rtl' else 'rtl'
    assert row['rootDirection'] == direction, row
print(f'Menu lifecycle: {len(rows)} light/dark, LTR/RTL nested update/reorder/direction states passed')
