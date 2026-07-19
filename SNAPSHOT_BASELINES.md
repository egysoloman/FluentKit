# Snapshot Baselines

The checked-in PNGs are native AppKit render baselines for the Gallery. They are intentionally kept
as ordinary files so a package consumer can inspect them without a special snapshot service.

| Page | Scheme | File | Size |
| --- | --- | --- | --- |
| Accessibility | Light | `.snapshots/accessibility-light.png` | 980 x 680 |
| Accessibility | Dark | `.snapshots/accessibility-dark.png` | 980 x 680 |
| Accessibility | RTL | `.snapshots/accessibility-rtl.png` | 980 x 680 |
| Application | Light | `.snapshots/application-light.png` | 980 x 680 |
| Application | Dark | `.snapshots/application-dark.png` | 980 x 680 |
| Controls | Light | `.snapshots/controls-light.png` | 980 x 680 |
| Controls | Dark | `.snapshots/controls-dark.png` | 980 x 680 |
| Inputs and forms | Light | `.snapshots/inputs-light.png` | 980 x 680 |
| Inputs and forms | Dark | `.snapshots/inputs-dark.png` | 980 x 680 |
| Minimal navigation | Light | `.snapshots/navigation-minimal-light.png` | 560 x 680 |
| Minimal navigation | Dark | `.snapshots/navigation-minimal-dark.png` | 560 x 680 |
| Top navigation overflow | Light | `.snapshots/navigation-top-light.png` | 980 x 680 |
| Top navigation overflow | Dark | `.snapshots/navigation-top-dark.png` | 980 x 680 |
| Top navigation overflow | RTL | `.snapshots/navigation-top-rtl.png` | 980 x 680 |

Regenerate a baseline with:

```text
FLUENTKIT_SNAPSHOT_PATH="$PWD/.snapshots/controls-light.png" \
FLUENTKIT_GALLERY_PAGE=controls FLUENTKIT_GALLERY_SCHEME=light swift run FluentGallery
```

Responsive shell captures additionally set `FLUENTKIT_GALLERY_NAV_MODE` and, for Minimal mode,
`FLUENTKIT_SNAPSHOT_WIDTH=560`. Top captures select the Accessibility destination so the checked-in
image exercises a selection that lives inside the overflow flyout.

The validation executable checks every listed file for its expected dimensions and non-empty pixel
variation. Visual review remains required for intentional design changes; the check is a regression
gate against missing, blank, or incorrectly sized captures rather than a substitute for design review.
