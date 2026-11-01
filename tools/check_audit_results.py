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
search = load('ComboBoxTextSearchAudit')
assert len(search) == 64 and {(r['dark'], r['rtl'], r['always'], r['open'], r['scenario']) for r in search} == {
    (dark, rtl, always, opened, scenario) for dark in (False, True) for rtl in (False, True)
    for always in (False, True) for opened in (False, True) for scenario in ('prefix', 'words', 'escape', 'disabled')
}, search
for row in search:
    expected = 0 if row['scenario'] == 'disabled' else 3 if row['scenario'] == 'words' else 4
    assert row['selection'] == expected and row['popupOpen'] == row['open'], row
    assert row['panelPreserved'] is True and row['responderPreserved'] is True, row
    expected_title = ['Alpha', 'Bravo', 'Blue sky', 'Blue sea', 'Charlie'][expected]
    assert row['focusedTitles'] == row['selectedTitles'] == ([expected_title] if row['open'] else []), row
    cancelled = row['scenario'] == 'escape' and row['open']
    assert row['afterSelection'] == (0 if cancelled else expected), row
    assert row['afterPopupOpen'] == (row['open'] and not cancelled), row
completion = load('ComboBoxCompletionAudit')
assert len(completion) == 64 and {(r['dark'], r['rtl'], r['bound'], r['always'], r['open'], r['committedText']) for r in completion} == {
    (dark, rtl, bound, always, opened, committed) for dark in (False, True) for rtl in (False, True)
    for bound in (False, True) for always in (False, True) for opened in (False, True) for committed in (False, True)
}, completion
for row in completion:
    assert row['completedText'] == row['redoText'] == 'Charlie' and row['undoText'] == 'Alpha', row
    assert row['suffix'] == [2, 5] and row['deletedText'] == 'Ch', row
    assert row['implicitRowAnimations'] == [], row
    assert row['selection'] == row['selectionAfterDeletion'] == (2 if row['always'] else 0), row
    assert all(row[key] is True for key in ('modelMatches', 'editorPreserved', 'panelPreserved',
        'freeTextCommitted', 'markedTextPreserved', 'externalResetWins')), row
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
