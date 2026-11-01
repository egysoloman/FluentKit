#!/usr/bin/env python3
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
rows = json.loads((p / 'samples.json').read_text())
by_stage = {r['stage']: r for r in rows}
visible = [r for r in rows if r['panels']]
assert all(r['panels'] <= 1 for r in rows)
assert len({r['windowNumber'] for r in visible}) == 1
first, mid, second = (by_stage[s] for s in ('first', 'to-second-4', 'second'))
assert first['frame'][0] < mid['frame'][0] < second['frame'][0]
assert 0 < mid['contentAlpha'] < 1
assert by_stage['to-third']['frame'][2] < second['frame'][2]
assert by_stage['returned']['frame'] == first['frame']
assert by_stage['light']['panels'] == 1
assert by_stage['light']['windowNumber'] == first['windowNumber']
assert by_stage['exit-17']['panels'] == 0
assert any(0 < r.get('alpha', 0) < 1 for r in rows if r['stage'].startswith('exit-'))
result = dict(samples=len(rows), visible_samples=len(visible), panel_instances=1,
              intermediate_motion=True, interrupted_return=True, content_crossfade=True,
              theme_preserves_panel=True, exit_completed=True)
(p / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
