#!/usr/bin/env python3
"""Deterministic release gates. Latencies are reported, not used as machine-dependent pass/fail."""
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
load = lambda name: json.loads((root / (name + '.json')).read_text())
inputs = load('InputAudit')
assert len(inputs) == 6 and {(r['rows'], r['shell'], r['navigation']) for r in inputs} == {(n, s, nav) for n in (1, 100) for s, nav in ((False, False), (True, False), (True, True))}, inputs
for row in inputs:
    assert row['textChanges'] == 30, row
    assert row['bodyEvaluations'] == row['textChanges'], row
    assert row['rowUpdates'] == row['rows'] * row['textChanges'], row
    assert row['rowMakes'] == 0 and row['nativeAttachments'] == 0, row
collections = load('CollectionAudit')
assert len(collections) == 4 and {(r['rows'], r['shell']) for r in collections} == {(n, s) for n in (1000, 5000) for s in (False, True)}, collections
for row in collections:
    assert row['textChanges'] == 10, row
    assert row['rowMakes'] == 0 and row['nativeAttachments'] == 0, row
    assert row['textChanges'] <= row['rowUpdates'] <= 30 * row['textChanges'], row
layout_log = (root / 'CollectionAudit.log').read_text()
for diagnostic in ('UICollectionViewFlowLayout is not defined', 'item width must be less',
                   'Conflicting constraints', 'Unable to simultaneously satisfy constraints'):
    if diagnostic in layout_log:
        raise SystemExit(f'Collection audit emitted a layout diagnostic: {diagnostic}')
editing = load('EditingAudit')
assert editing['editorPresent'] is True
assert all(editing[key] == 'external reset' for key in ('focusedModel', 'focusedField', 'blurredModel', 'blurredField')), editing
combos = editing['comboBoxes']
assert len(combos) == 8 and {(r['dark'], r['rtl'], r['committed']) for r in combos} == {
    (dark, rtl, committed) for dark in (False, True) for rtl in (False, True) for committed in (False, True)
}, combos
for row in combos:
    assert all(row[key] == 'external reset' for key in ('focusedModel', 'focusedField', 'blurredModel', 'blurredField')), row
    assert all(row[key] is True for key in (
        'editorPreserved', 'sameValueReset', 'popupPreserved', 'matchedSelection', 'compositionPolicy',
        'markedTextPreserved', 'pendingResetPreserved', 'latestResetApplied', 'resetSurvivesBlur',
        'selectionPreservesMarkedText', 'externalSelectionApplied'
    )), row
selection = load('ComboBoxSelectionAudit')
assert len(selection) == 96 and {(r['dark'], r['rtl'], r['always'], r['editable'], r['close']) for r in selection} == {
    (dark, rtl, always, editable, close) for dark in (False, True) for rtl in (False, True)
    for always in (False, True) for editable in (False, True)
    for close in ('return', 'tab', 'toggle', 'escape', 'outside', 'row')
}, selection
for row in selection:
    expected_before = 2 if row['always'] else 1
    expected_after = 1 if row['close'] == 'escape' else (2 if row['always'] or row['editable'] or row['close'] in ('return', 'row') else 1)
    assert row['beforeSelection'] == expected_before and row['afterSelection'] == expected_after, row
    assert row['selectedTitles'] == [f'Option {expected_before}'] and row['focusedTitles'] == ['Option 2'], row
    assert row['editorPreserved'] is True and row['closed'] is True, row
    assert not row['editable'] or row['beforeText'] == 'Option 2', row
    assert row['close'] != 'row' or row['rowPressAccepted'] is True, row
appearance = load('AppearanceAudit')
assert appearance['materials']['mica'] in ('fluentRecipe', 'opaque'), appearance
assert appearance['fonts']['title']['size'] == 28 and appearance['fonts']['largeTitle']['size'] == 40
if (root / 'GallerySampleAudit.json').exists():
    gallery = load('GallerySampleAudit')
    assert len({row['id'] for row in gallery}) == len(gallery)
    for row in gallery:
        assert row['coverage'] != 'implemented' or row['directSample'], row
        assert not row['directSample'] or row['mountingVerified'] == ['light', 'dark', 'rtl'], row
print('Release update counts, attachment identity, external reset, typography and material gates passed.')
