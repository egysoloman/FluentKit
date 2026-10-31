import json
from pathlib import Path

root = Path(__file__).resolve().parent
result = {}
expectations = {}
for stage in ['before', 'after']:
    rows = json.loads((root / stage / 'native/results.json').read_text())
    expectations[stage] = {r['id']: r['expected'] for r in rows}
    if not rows or len(expectations[stage]) != len(rows):
        raise ValueError(f'{stage}: missing samples or duplicate IDs')
    errors = [{'id': r['id'], 'field': k, 'actual': r[k], 'expected': v}
              for r in rows for k, v in r['expected'].items() if r[k] != v]
    result[stage] = {'samples': len(rows), 'mismatched_states': len({e['id'] for e in errors}),
                     'mismatched_fields': len(errors), 'errors': errors}
    print(stage, {k: v for k, v in result[stage].items() if k != 'errors'})
if expectations['before'] != expectations['after']:
    raise ValueError('Before/after samples must use identical IDs and expectations')
(root / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(bool(result['after']['errors']))
