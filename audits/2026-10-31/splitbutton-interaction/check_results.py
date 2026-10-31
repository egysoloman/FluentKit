#!/usr/bin/env python3
import json
import sys

records = json.load(open(sys.argv[1]))
assert len(records) == 72
for variant in sorted({row['variant'] for row in records}):
    phases = {row['phase']: row for row in records if row['variant'] == variant}
    assert len(phases) == 9, variant
    for phase, row in phases.items():
        assert row['hit'] == (phase != 'hide'), (variant, phase, 'hit')
        assert row['open'] == (phase in ('open', 'repeat', 'update', 'move')), (variant, phase, 'open')
        assert row['expanded'] == row['open'], (variant, phase, 'AX expanded')
        if row['open']:
            assert row['samePanel'], (variant, phase, 'identity')
        if phase in ('update', 'move'):
            assert row['rows'][0] == 'Publish revised action', (variant, phase, 'live items')
        if phase in ('invoke', 'hide'):
            assert row['action'] == 'new', (variant, phase, 'latest action')
    assert not phases['mousePress']['equalFills'], (variant, 'mouse regions')
    assert phases['touchPress']['equalFills'], (variant, 'touch regions')
    assert abs(phases['move']['panelX'] - phases['update']['panelX'] - 30) < 0.5, variant
    assert abs(phases['move']['panelY'] - phases['update']['panelY'] - 20) < 0.5, variant
print('SplitButton: 72 states passed (8 variants × 9 phases)')
