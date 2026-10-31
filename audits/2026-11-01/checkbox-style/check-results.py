#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parent
after = json.loads((root / 'after/native/results.json').read_text())
oracle = {(r['variant'], r['control']): r['expected'] for r in after}
reports = {}
for stage in ['before', 'after']:
    records = json.loads((root / f'{stage}/native/results.json').read_text())
    errors = []
    for row in records:
        for field, expected in oracle[row['variant'], row['control']].items():
            actual = row[field]
            if isinstance(expected, list):
                # Zero-alpha RGB has no observable difference.
                indices = [3] if expected[3] == actual[3] == 0 else range(4)
                equal = all(abs(actual[i] - expected[i]) < 0.001 for i in indices)
            else:
                equal = abs(actual - expected) < 0.001
            if not equal:
                errors.append({'variant': row['variant'], 'control': row['control'], 'field': field,
                               'actual': actual, 'expected': expected})
    reports[stage] = {'states': len(records), 'mismatched_fields': len(errors),
                     'mismatched_states': len({(r['variant'], r['control']) for r in errors}), 'errors': errors}
(root / 'comparison.json').write_text(json.dumps(reports, indent=2) + '\n')
for stage, result in reports.items():
    print(stage, {key: value for key, value in result.items() if key != 'errors'})
raise SystemExit(bool(reports['after']['errors']))
