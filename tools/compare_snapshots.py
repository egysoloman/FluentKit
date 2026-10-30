#!/usr/bin/env python3
"""Compare controlled render pairs; fails on incompatible capture environments or excess drift.
Requires Pillow. Never changes the baseline. Defaults tolerate <= 0.5% changed pixels and <= 0.25/255 mean error.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser()
parser.add_argument('baseline', type=Path)
parser.add_argument('actual', type=Path)
parser.add_argument('--max-mean-error', type=float, default=0.25)
parser.add_argument('--max-changed-fraction', type=float, default=0.005)
args = parser.parse_args()
expected_environment = json.loads((args.baseline / 'visual-environment.json').read_text())
actual_environment = json.loads((args.actual / 'visual-environment.json').read_text())
if expected_environment != actual_environment:
    raise SystemExit('Capture environments differ. Review and capture a matching baseline; no baseline was changed.')
results = []
failed = False
for source in sorted(args.baseline.glob('audit-states-*.png')):
    expected = Image.open(source).convert('RGBA')
    actual = Image.open(args.actual / source.name).convert('RGBA')
    if expected.size != actual.size:
        raise SystemExit(f'{source.name}: dimensions differ')
    diff = ImageChops.difference(expected, actual)
    means = ImageStat.Stat(diff).mean
    pixels = diff.get_flattened_data() if hasattr(diff, 'get_flattened_data') else diff.getdata()
    changed = sum(max(pixel) > 8 for pixel in pixels) / (expected.width * expected.height)
    error = sum(means) / len(means)
    passed = error <= args.max_mean_error and changed <= args.max_changed_fraction
    failed |= not passed
    results.append(dict(image=source.name, meanError=error, changedFraction=changed, passed=passed))
    if not passed:
        diff.convert('RGB').save(args.actual / (source.stem + '-diff.png'))
if not results:
    raise SystemExit('No baseline images found')
print(json.dumps(results, indent=2))
raise SystemExit(1 if failed else 0)
