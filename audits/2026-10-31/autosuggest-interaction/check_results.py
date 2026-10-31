#!/usr/bin/env python3
"""Check native release observations, not guessed screenshot success."""
import json
import sys
from pathlib import Path

records = json.loads(Path(sys.argv[1]).read_text())
assert len(records) == 16
assert {(r['variant'], r['phase']) for r in records} == {
    (f'{theme}-{direction}', phase) for theme in ('light', 'dark')
    for direction in ('ltr', 'rtl') for phase in ('open', 'last', 'resize', 'reset')
}
for r in records:
    assert r['headerVisible'] and r['glyphVisible'] and r['editorFocused'], r
    assert r['alignment'] == (2 if r['variant'].endswith('rtl') else 0), r
    if r['variant'].endswith('rtl'):
        assert abs(r['queryX'] - 4) < 0.5, r
    if r['phase'] == 'reset':
        assert not r['open'] and r['rows'] == 0 and r['text'] == '', r
        continue
    assert r['samePanel'] and r['open'] and r['hasScroll'] and r['clipCovers'], r
    assert r['rows'] == 20 and abs(r['anchorGap'] - 2) < 0.5, r
    assert abs(r['height'] - (164 if r['phase'] == 'resize' else 84)) < 0.5, r
    if r['phase'] in ('last', 'resize'):
        assert r['selected'] == 'Apple 19' and r['selectedVisibleHeight'] >= 39, r
print('AutoSuggestBox: 16 light/dark, LTR/RTL scroll/update/reset states passed')
