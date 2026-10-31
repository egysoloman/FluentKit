#!/usr/bin/env python3
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
summary = {}
for phase in ['before', 'after']:
    rows = json.loads((root / (phase + '-final') / 'results.json').read_text())
    errors = []
    for row in rows:
        for actual, expected in [('title', row['expectedTitle']), ('role', row['expectedRole']),
                                 ('action', row['phase']), ('sameButton', True), ('dark', row['phase'] == 'dark')]:
            if row[actual] != expected:
                errors.append({'wrapper': row['wrapper'], 'phase': row['phase'], 'property': actual,
                               'actual': row[actual], 'expected': expected})
    labels = json.loads((root / (phase + '-final') / 'semantic-labels.json').read_text())
    summary[phase] = {'states': len(rows), 'incorrectWrappers': sorted({e['wrapper'] for e in errors}),
                      'errors': errors, 'mergedLabel': labels}
assert summary['before']['states'] == summary['after']['states'] == 87
assert len(summary['before']['incorrectWrappers']) == 24
assert not summary['after']['errors']
assert summary['after']['mergedLabel'] == {'before': 'Before', 'after': 'After'}
(root / 'checks.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({phase: {'states': r['states'], 'incorrectWrappers': len(r['incorrectWrappers']),
                        'failedProperties': len(r['errors']), 'mergedLabel': r['mergedLabel']} for phase, r in summary.items()}))
