#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parent
result = {}
for stage in ['before', 'after']:
    rows = json.loads((root / stage / 'native/results.json').read_text())
    errors = []
    for row in rows:
        for field, expected in row['expected'].items():
            actual = row[field]
            if isinstance(expected, list):
                indices = [3] if actual[3] == expected[3] == 0 else range(4)
                equal = all(abs(actual[i] - expected[i]) < 0.001 for i in indices)
            else:
                equal = abs(actual - expected) < 0.001
            if not equal:
                errors.append({'variant': row['variant'], 'selected': row['selected'], 'field': field,
                               'actual': actual, 'expected': expected})
    result[stage] = {'samples': len(rows), 'mismatched_fields': len(errors),
                     'mismatched_samples': len({(e['variant'], e['selected']) for e in errors}), 'errors': errors}
    print(stage, {k: v for k, v in result[stage].items() if k != 'errors'})
(root / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(bool(result['after']['errors']))
