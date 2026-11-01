#!/usr/bin/env python3
import json
from pathlib import Path
root = Path(__file__).resolve().parent

def checks(stage):
    rows = {r['state']: r for r in json.loads((root/stage/'chain.json').read_text())}
    check = next(v for v in rows['tab-from-settings']['views'] if v['view'].startswith('FluentCheckBox:'))
    result = {
        'gallery_new_control_linked_on_navigation': check['nextValid'] != 'nil',
        'gallery_settings_reaches_body': rows['tab-from-settings']['firstResponder'].startswith('FluentSettingsCardHost:'),
    }
    scene = json.loads((root/stage/'scene.json').read_text())
    result.update({'scene_' + k: scene[k] for k in ['automatic', 'insertedHasNext', 'reachedInserted']})
    return result
before, after = checks('before'), checks('after')
windows = json.loads((root/'after/windows.json').read_text())
for window in windows:
    for key in ['automatic', 'insertedHasNext', 'reachedInserted']:
        after[window['kind'] + '_' + key] = window[key]
report = {'before': before, 'after': after}
(root/'comparison.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
assert not any(before.values()), 'Baseline must reproduce the missing links.'
assert all(after.values()), 'A repaired window still fails navigation.'
