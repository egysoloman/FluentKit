import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
p = {r['phase']:r for r in json.loads((root/'PerformanceAudit.json').read_text())}
assert p['initial']['builders'] <= 3 and p['initial']['makes'] <= 3
assert p['refresh30']['builders'] <= 90 and p['refresh30']['updates'] <= 90 and p['refresh30']['makes'] == 0
assert p['last']['selection'] == 999 and p['last']['makes'] <= 3
assert p['append']['selection'] == 999 and p['append']['makes'] <= 1
rows = json.loads((root/'VisualAudit.json').read_text())
assert len(rows) == 56
for variant in {r['variant'] for r in rows}:
    phases = {r['phase']:r for r in rows if r['variant']==variant}
    assert len(phases)==7
    for phase, row in phases.items():
        assert row['mounted']<=3
        assert row['visible']==(2 if phase in ['partial','refresh'] else 1), (variant,phase,row)
        expected = 1 if phase=='next' else 2 if phase=='reorder' else 1000 if phase=='last' else 0
        assert row['selection']==expected
    assert phases['partial']=={**phases['refresh'],'phase':'partial'}, variant
    first = next(r for r in phases['partial']['positions'] if r['id'].endswith('.0'))
    if variant.endswith('vertical'): assert abs(first['y']-45)<0.01 and first['x']==0
    else: assert abs(first['x']-(80 if '-rtl-' in variant else -80))<0.01 and first['y']==0
print('FlipView: bounded content cost, retained identity and 56 rendered interaction states passed.')
