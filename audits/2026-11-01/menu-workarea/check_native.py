#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path

records = json.loads(Path(sys.argv[1]).read_text())
assert len(records) == 32
failures = []
for row in records:
    conditions = {key: row[key] for key in ('fitsWorkArea', 'visible', 'sameRootPanel', 'sameRootContent', 'sameRootResponder')}
    conditions['allRowsRetained'] = row['rowCount'] == (1 if row['kind'] == 'long-title' else 41 if row['kind'] == 'long-submenu' and not row['phase'].startswith('child-') else 50)
    if row['kind'] != 'long-title':
        conditions['scrollable'] = row['scrollable']
    if row['requireLast']:
        conditions['lastVisible'] = row['lastVisible']
        conditions['lastSelected'] = row['lastSelected']
    bad = [key for key, value in conditions.items() if not value]
    if bad:
        failures.append({'variant': row['variant'], 'phase': row['phase'], 'failed': bad})
print(json.dumps({'states': len(records), 'failedStates': len(failures),
                  'failedConditions': dict(Counter(key for item in failures for key in item['failed'])),
                  'failures': failures}, indent=2))
if failures and '--allow-failures' not in sys.argv:
    raise SystemExit(1)
