import json
from pathlib import Path

root = Path(__file__).resolve().parent

def differences(actual, expected, path=''):
    if isinstance(expected, dict):
        actual = actual if isinstance(actual, dict) else {}
        return [e for k, v in expected.items() for e in differences(actual.get(k), v, f'{path}.{k}')]
    if isinstance(expected, list) and isinstance(actual, list) and len(actual) == len(expected):
        return [e for i, (a, b) in enumerate(zip(actual, expected)) for e in differences(a, b, f'{path}[{i}]')]
    if isinstance(actual, (int, float)) and isinstance(expected, (int, float)) and abs(actual - expected) < 0.001:
        return []
    return [] if actual == expected else [{'field': path.lstrip('.'), 'actual': actual, 'expected': expected}]

result, oracles = {}, {}
for stage in ['before', 'after']:
    rows = json.loads((root / stage / 'native/results.json').read_text())
    oracles[stage] = {r['id']: r['expected'] for r in rows}
    assert rows and len(oracles[stage]) == len(rows)
    errors = [dict(id=r['id'], **e) for r in rows for e in differences(r, r['expected'])]
    result[stage] = {'samples': len(rows), 'mismatched_states': len({e['id'] for e in errors}), 'mismatched_fields': len(errors), 'errors': errors}
    print(stage, {k: v for k, v in result[stage].items() if k != 'errors'})
assert oracles['before'] == oracles['after'], 'Before and after must use the same expectations'
(root / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(bool(result['after']['errors']))
