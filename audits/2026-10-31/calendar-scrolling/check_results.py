#!/usr/bin/env python3
import json
import sys
from pathlib import Path

records = json.load(open(sys.argv[1]))
assert len(records) == 48
for name in sorted({r['variant'] for r in records}):
    phases = {r['phase']: r for r in records if r['variant'] == name}
    assert len(phases) == 4
    mode = name.split('-')[-1]
    for phase, row in phases.items():
        assert row['hasScroll'], (name, phase)
        assert 0 < row['visible'] <= (49 if mode == 'month' else 20), (name, phase, row['visible'])
        assert row['realized'] <= (70 if mode == 'month' else 32), (name, phase, row['realized'])
        assert row['selected'] == 1, (name, phase)
    a, b, c, d = (phases[p] for p in ['initial','partial','far','refresh'])
    assert a['visible'] == (42 if mode == 'month' else 16), (name, a['visible'])
    assert abs(b['offset'] - a['offset'] - 13) < 0.01, name
    assert b['header'] == a['header'], name
    assert c['offset'] > b['offset'] and c['header'] != a['header'], name
    assert c == {**d, 'phase':'far'}, (name, 'parent refresh must preserve browsing')
arithmetic = json.loads(Path(sys.argv[1]).with_name('date-arithmetic.json').read_text())
assert {r['case']:r['visible'] for r in arithmetic} == {'apia-2011-december':41, 'apia-2026-may':42}
assert all(r['weekdayColumnsCorrect'] for r in arithmetic)
print('Calendar scrolling: 48 states passed (12 variants × 4 phases); 2 Samoa weekday-column cases passed')
