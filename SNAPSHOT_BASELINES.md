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
| Collections | Light | `.snapshots/collections-light.png` | 980 x 680 |
| Collections | Dark | `.snapshots/collections-dark.png` | 980 x 680 |
| Inputs and forms | Light | `.snapshots/inputs-light.png` | 980 x 680 |
| Inputs and forms | Dark | `.snapshots/inputs-dark.png` | 980 x 680 |
| WindowShell extended reference | Light | `.snapshots/window-shell-extended-light.png` | 980 x 680 |
| WindowShell native + vertical pane | Light | `.snapshots/window-shell-native-light.png` | 980 x 680 |
| CommandBarFlyout expanded | Light | `.snapshots/command-bar-flyout-light.png` | 141 x 133 |
| CommandBarFlyout expanded | Dark | `.snapshots/command-bar-flyout-dark.png` | 141 x 133 |
| MenuFlyout icon slots | Light | `.snapshots/menu-flyout-light.png` | 194 x 121 |
| MenuFlyout icon slots | Dark | `.snapshots/menu-flyout-dark.png` | 194 x 121 |
| MenuFlyout item highlight | High Contrast | `.snapshots/menu-flyout-high-contrast.png` | 194 x 121 |
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

CommandBarFlyout captures set `FLUENTKIT_GALLERY_OPEN_MENU=1`, select the `Command bar` button with
`FLUENTKIT_GALLERY_MENU_TITLE`, and invoke More through `FLUENTKIT_GALLERY_OPEN_SUBMENU=More` before
capturing the child panel. The High Contrast MenuFlyout baseline additionally sets
`FLUENTKIT_GALLERY_CONTRAST=high` and highlights `New item` through
`FLUENTKIT_GALLERY_HIGHLIGHT_MENU_ITEM`.

WindowShell reference captures use `FLUENTKIT_GALLERY_SHOW_BACK=1` for the extended title-bar Back
state. Native + vertical captures set `FLUENTKIT_GALLERY_TITLEBAR_STYLE=native`,
`FLUENTKIT_GALLERY_NAV_MODE=left`, and request title-bar search/toggle to verify the configuration
normalizes unsupported native content to a navigation-pane toggle and no Fluent search field.

Extended, Minimal, and Top shell baselines include the custom `FluentTitleBar`; the native shell
baseline intentionally does not. Minimal captures verify the shared title-bar pane toggle, Top
captures suppress it when no pane action is applicable, and native vertical navigation retains the
toggle inside the pane.

The validation executable checks every listed file for its expected dimensions and non-empty pixel
variation. Visual review remains required for intentional design changes; the check is a regression
gate against missing, blank, or incorrectly sized captures rather than a substitute for design review.
