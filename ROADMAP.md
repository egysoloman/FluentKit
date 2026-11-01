# FluentKit Roadmap

FluentKit is a native Swift/AppKit declarative framework for macOS, with a Fluent-inspired
visual language. WinUI source and reference projects inform behavior and design; macOS
integration, performance and developer overrides remain part of the implementation contract.

## Current implementation

Available APIs and automated coverage do not imply complete Windows visual or interaction parity.
API examples live in [README.md](README.md); shipped changes live in [CHANGELOG.md](CHANGELOG.md).

| Area | Available foundation | Work still open |
| --- | --- | --- |
| Composition, state and layout (1–13) | Declarative builders, bindings, environment propagation, stable identity, native layout, diffable collections, forms and single/multiple windows | Component state coverage and application integration acceptance |
| Text (14) | Plain/secure/search editors, native IME and undo, rich-text formatting and selection, attachment IDs and find/replace operations | Document-scale editing, full attachment lifecycle, richer command routing and integrated find UI |
| Navigation and presentation (15) | Left/Compact/Minimal/Top navigation, page transitions, title bars, WindowShell, inspectors, coordinated sheets/dialogs/file panels and scene restoration | Broader native window restoration and navigation edge cases |
| Motion (16, 18) | Timing curves, springs, keyframes, matched geometry, interruption, completion cleanup and Reduce Motion | Component-specific state acceptance and physical input behavior |
| Visual system (17) | Theme stores, system appearance, contrast/density, typography, control styles, state coordination and configurable material roles | Wider coordinator adoption, custom accent palettes and remaining control states |
| Menus and flyouts (19) | Native main menus, Fluent in-app menus, submenus, CommandBarFlyout, native-editor text commands and distinct ComboBox presenters | Arbitrary custom content and increased-contrast acceptance across the remaining flyout family |
| Accessibility and localization (20) | Semantic trees, labels/actions/rotors, focus announcements, localization and RTL | End-to-end VoiceOver operation and application-level keyboard acceptance |
| Application services (21) | Settings scenes, document coordination, import/export, Services, printing, sharing, tab policy and state migration | Wider host-application integration coverage |
| Production hardening (22) | SwiftPM/Xcode builds, XCTest, native validation, Release work-count gates and reviewed visual fixtures | Broader performance/leak coverage and the platform acceptance matrix below |

Materials default to wallpaper-derived Mica for window backgrounds and layered Acrylic for
transient surfaces. Automatic navigation panes inherit the background while inline and use
Acrylic when open over content. Role and surface overrides remain available, including native
AppKit materials and Liquid Glass. Accessibility policies select opaque fallbacks.
WinUI Mica/Acrylic and WinUIEssentials inform these presets; matching their exact rendering
is not required. The macOS composition and developer overrides remain intentional; see the
[acknowledgement and license](README.md#acknowledgements).

## Next work

1. **Release and repository maintenance.** Keep generated evidence local, maintain reproducible
   checks in `tools/quality` and `Tests`, and publish only after the release gates pass.
2. **Application integration.** Continue acceptance of search focus and font changes, native
   context commands, hover lifecycle, scroller style changes, theme propagation and page motion
   in real applications. Synthetic events and green tests alone do not close these items.
3. **Collections and TreeView.** Validate physical multi-item drag/drop, cross-tree transfer,
   templates and container entrance/content/reorder transitions while preserving selection and
   stable native identity. Disclosure motion now survives layout and content updates; expansion
   row motion still needs its own policy and acceptance, separate from initial entrance.
4. **Calendar.** The embedded CalendarView/CalendarDatePicker grid supports selection modes,
   blackout dates, range reconciliation, RTL keyboard navigation and virtualized continuous
   Month/Year/Decade scrolling with era-aware items, scope boundaries and keyboard paging.
   Pending work includes optional snap points, scope labels and motion, item templates,
   density indicators and broader calendar/era comparison on Windows.
5. **FlipView.** Bounded lazy pages, stable-ID selection, horizontal/vertical paging and phased
   drag/settling are implemented. New outward gestures at a settled edge chain to the parent.
   Pending work includes item-container semantics, DirectManipulation behavior, residual scroll
   transfer after an owned gesture reaches an edge, and navigation-button visual acceptance.
6. **Text, windows and visual states.** Complete the open contracts in the table above without
   replacing native editing, responder, accessibility or window lifecycle ownership.
   SettingsExpander, Expander, NavigationView group, ComboBox, DropDownButton and SplitButton chevrons preserve
   motion across repeated layout and content updates. Navigation uses the default up/down
   directions; DropDownButton cancels stale activation and updates live menu actions.
   ComboBox cancels captured/deferred pointer activation across native lifecycle changes.
   SplitButton separates secondary pointer motion from whole-button keyboard/flyout chrome,
   uses the host's visual downward direction and cancels stale activation on focus loss.
   RepeatButton cancels long presses across lifecycle changes. Directional glyphs use static
   press geometry and preserve foreground transitions; PipsPager forwards motion policy to
   retained children immediately. PipsPager scales only its navigation icon, coordinates hover
   ownership and cancels stale presses across lifecycle changes. Open ComboBox popups update
   titles, direction and motion policy while retaining native identity and focus. Collection
   mutations reconcile stable option identities, preserve surviving rows/scroll state and cancel
   captured input; removed selections are normalized without erasing editable text.
   Editable ComboBox text and its active editor reserve the mirrored glyph column in RTL,
   preserving native selection, marked text and horizontal scrolling. Continue full keyboard
   contracts and hierarchical flyout behavior. ComboBox now preserves its native editor while
   open and routes bounded navigation, F4/Option toggling, Escape and parent focus traversal.
   ComboBox now defaults to Committed selection with an explicit Always option, distinguishing
   navigation previews, selected bindings, accessibility state and mode-specific dismissal.
   Editable ComboBox uses the shared text coordinator for active external resets,
   composition policy, undo/redo and binding replacement; Release gates cover these paths.
   Noneditable prefix search now handles immediate selection, space-separated queries, timeout,
   wrapping, Unicode folding and a developer opt-out without changing arrow-preview policy.
   Editable prefix completion now preserves native suffix selection/undo, deletion, marked text,
   external-reset precedence and stable option identity. Next add custom text-submission events,
   including handled callbacks, option insertion/rebinding and repeated-submission suppression.
   Retain PipsPager High Contrast resource and full application-flow acceptance.

## Platform acceptance still required

- Physical mouse/trackpad scrolling and mouse connection changes, including persistent scrollers.
- Real touch input, high-refresh-rate animation and interrupted gestures.
- System Pinyin composition, candidate-window positioning, commit/cancel, moving and resizing.
- VoiceOver, full keyboard navigation, High Contrast and Reduce Motion in application flows.
- Mixed-resolution and mixed-DPI displays, cross-display windows/popups and wallpaper changes.
  Animated wallpaper current-frame sampling is not supported by the current file-based Mica cache.
- Windows screenshot and interaction comparison for controls that claim source-derived fidelity.
  Material appearance remains platform-adapted; matching native Windows pixels is not promised.

## Validation and evidence

Run the commands in [CONTRIBUTING.md](CONTRIBUTING.md) and the maintained
[quality checks](tools/quality/README.md). Reviewed regression fixtures are documented in
[SNAPSHOT_BASELINES.md](SNAPSHOT_BASELINES.md). Raw audit reports, captures and logs stay outside
version control; they are not build dependencies.

Each completed feature needs public API documentation, relevant executable validation, a Gallery
example when visual behavior is involved, and warning-free builds. Mark remaining physical or
visual acceptance explicitly. Follow [RELEASING.md](RELEASING.md) when preparing a version.
