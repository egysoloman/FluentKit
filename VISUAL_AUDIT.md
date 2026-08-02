# FluentKit Gallery Visual and Motion Audit

Date: 2026-07-19  
Scope: `Sources/FluentKit`, `Sources/FluentGallery`, and the bundled WinUI 3 source tree  
Status: Audit baseline with implementation progress tracked below.

## Full-Bounds Inside-Ring Correction - 2026-07-20

The latest Controls and Inputs captures exposed that the previous half-device-pixel inset was
appropriate for a centered stroke but incorrect for the filled even-odd rings now used by Fluent
chrome. The inset left a transparent seam at the outer boundary, which appeared as clipped leading
or trailing arcs on first/last segmented items, Button-family controls, TextBox, NumberBox, and
FormField children.

- Shared Button elevation masks now place their outer rounded path on the complete local bounds and
  subtract the source 1pt or High Contrast 2pt thickness only from the inner path.
- TextBox, PasswordBox, SearchBox, NumberBox, and editable ComboBox use the same full-bounds outer
  path. The focused 2pt accent replacement clips to that exact outer radius, so it cannot terminate
  early at either horizontal edge.
- SegmentedControl keeps the animated selection below a separate topmost border overlay. That
  overlay now owns a full-bounds even-odd ring, eliminating the remaining first/last-item seam.
- Centered-stroke code paths such as the legacy underline retain pixel-center alignment; filled
  rings do not apply a second inset.

Light and Dark captures were reviewed at 1x and 2x. The standard Light Button-family elevation
segment remains on the visual bottom; Dark standard Button chrome retains the unflipped source
brush. TextControl focus uses `SystemAccentColorDark1` in Light and `SystemAccentColorLight2` in
Dark, exactly as `TextBox_themeresources_perf2026.xaml` specifies.

The text context surface in the supplied screenshot is already FluentKit's custom
TextCommandBarFlyout in its secondary-only state. `TextCommandBarFlyout.cpp` exposes Cut/Copy only
for a real non-empty selection and Paste only when the clipboard contains a supported type. IME
marked text is not a TextBox selection, so Select All alone is the source-correct command set in
that state. Real selection captures and executable validation confirm the custom 40pt Cut/Copy
primary commands and More overflow in both Light and Dark.

## RepeatButton Atomic Control - 2026-07-20

`RepeatButton_themeresources_perf2026.xaml`, `RepeatButton_Partial.cpp`, and the generated dependency
property defaults define one Button-family surface and a separate press/repeat lifecycle. FluentKit
now provides native `FluentRepeatButton` and declarative `FluentRepeatButtonView` APIs:

- Normal, PointerOver, Pressed, and Disabled resolve through the dedicated RepeatButton resource
  families. Geometry remains the shared 32pt Button height, padding, 4pt corner radius, and
  scheme-correct three-point elevation edge.
- Pointer-down or Space invokes immediately because the source defaults to `ClickMode=Press`. The
  first timer tick occurs after 500ms and later ticks every 33ms by default; both values are public,
  validated `TimeInterval` properties.
- Pointer exit pauses repetition, re-entry starts a fresh delay, and pointer release, Space release,
  Escape, focus loss, disabling, or removal from a window invalidates the timer. Return and
  accessibility press invoke once without entering the repeat loop.
- The source's only visual transition is the 83ms Background `BrushTransition`; FluentKit uses an
  explicit `CABasicAnimation` because AppKit backing layers do not guarantee implicit actions.
- Declarative updates preserve the native control and active behavior. Reduce Motion removes the
  visual transition without changing repeat timing. Gallery Controls includes a live counter, and
  the Controls Light/Dark baselines cover the final surface.

Executable validation covers resource mapping, defaults, immediate press, delayed/interval ticks,
pointer exit/re-entry, release, Space/Return, accessibility, disable cancellation, stable identity,
the 83ms transition, and Reduce Motion.

## ToggleButton Atomic Control - 2026-07-20

`ToggleButton_themeresources_perf2026.xaml` defines ToggleButton as Button geometry with an
independent toggle state machine. FluentKit now exposes a native `FluentToggleButton` and a bound
`FluentToggleButtonView` without routing through `NSButton` toggle chrome:

- Normal, PointerOver, Pressed, Disabled, Checked, CheckedPointerOver, CheckedPressed,
  CheckedDisabled, and all four Indeterminate combinations resolve through the source resource
  families. Checked uses `AccentFillColor*`, `TextOnAccentFillColor*`, and
  `AccentControlElevationBorderBrush`; Indeterminate intentionally retains the unaccented Button
  surface defined by the source template.
- The component uses the shared Button padding, 32pt height, 4pt corner radius, and elevation-ring
  renderer. Its only source transition, `ContentPresenter.BackgroundTransition`, is an explicit
  83ms `CABasicAnimation` using `ControlFastOutSlowInKeySpline`, rather than relying on AppKit
  backing-layer implicit actions.
- Pointer activation commits on release inside and cancels outside. Space/Return, accessibility
  press, disabled rejection, two-state and three-state cycling, external binding cancellation,
  stable declarative identity, and Reduce Motion use the same state path.
- Gallery Controls now includes Checked, Indeterminate, and CheckedDisabled examples. Fresh Light
  and Dark Controls baselines cover the component.

Executable validation checks source resource selection, exact transition duration, pointer and
keyboard commit timing, mixed-state cycling, accessibility values, binding identity, and Reduce
Motion.

## Dark Palette and Inside-Border Geometry - 2026-07-20

The Dark semantic pass now treats the bundled Common and NavigationView dictionaries as the
authority instead of precompositing approximate grays:

- Dark text, control fill, control stroke, strong stroke, divider, card, layer, solid background,
  flyout fallback, and on-accent foreground tokens retain their source channels and alpha.
- `SystemAccentColor` remains the raw application accent used by selection highlight. Controls
  resolve `AccentFillColorDefault/Secondary/Tertiary/Disabled` and
  `AccentTextFillColorPrimary/Secondary/Tertiary` separately. The default #0078D4 accent maps the
  source fallback Light/Dark palette exactly; custom macOS accents use the blending fallback
  suggested by `SystemThemingInterop.cpp` because AppKit does not provide six system variants.
- NavigationView's expanded pane is transparent and its content/header hosts use
  `LayerFillColorDefault`, matching `NavigationView_themeresources.xaml`. Gallery no longer paints a
  separate card band behind the page header. Mica and transient material behavior were not changed.

The latest 2x screenshots also exposed three shared geometry defects rather than page-padding
errors:

- SegmentedControl's selected surface could appear to cut the leading edge. The topmost boundary is
  now one full-bounds even-odd fill ring, while the animated selected surface remains below it.
- Button-like `CAGradientLayer` geometry had interpreted non-flipped AppKit unit coordinates in the
  wrong direction. Light Button, DropDownButton, ComboBox, and CalendarDatePicker now place the
  source-flipped 3pt elevation segment at the visual bottom. Dark standard controls retain the
  source top segment; accent controls retain their bottom segment in both schemes.
- TextBox, PasswordBox, SearchBox, NumberBox input chrome, and FormField now clip the source gradient
  to an even-odd rounded fill ring whose outer path equals the host bounds. Left and right borders
  therefore remain painted at 1x and 2x. Focused TextBox uses one base ring plus one 2pt bottom accent
  replacement, rather than stacking two focused gradients.

Executable validation covers the exact default accent variants, accent text variants, shared
elevation direction, topmost SegmentedControl stroke ownership, and the single focused TextControl
border model. Fresh Controls and Inputs Light/Dark baselines cover the resulting pixels.

## TextControl Editing Session - 2026-07-20

The TextBox-family field editor is now a shared FluentKit subsystem instead of inheriting AppKit's
selection, caret, and contextual-menu pixels independently in each component.

- `TextControlSelectionHighlightColor` maps to
  `AccentFillColorSelectedTextBackgroundBrush`, which resolves to the system accent in both Light
  and Dark. RichEdit's non-High-Contrast `COLOR_HIGHLIGHTTEXT` override is white.
- WinUI creates an opaque white caret with `DestInvert` composition. AppKit does not expose that
  blend mode on `NSTextView`, so FluentKit resolves the standard surface result to opaque black in
  Light and opaque white in Dark while retaining AppKit's native blink timing and geometry.
- `SelectionHighlightColorWhenNotFocused` defaults to transparent in WinUI. FluentKit keeps normal
  field-editor teardown behavior when focus leaves the editing session, while a Fluent text-command
  flyout retains and restores the active native editor target.
- TextBox, PasswordBox, SearchBox, NumberBox, and editable ComboBox all apply these attributes after
  AppKit finishes creating or resetting the shared field editor. SearchBox's placeholder, active
  editor, caret, and search glyph continue to use the same source-derived content rectangle.
- Right-click text commands are application-owned Fluent presenters, not `NSMenu`. Availability
  follows `TextCommandBarFlyout.cpp`: TextBox-family controls derive Cut, Copy, Paste, Undo, Redo,
  and Select All from selection/edit/clipboard/history state; PasswordBox exposes only Paste and
  Select All. The native editor still executes every command so IME, clipboard, undo, and
  accessibility behavior remain AppKit-owned.
- The presenter now reproduces the CommandBarFlyout split instead of rendering every command as a
  normal MenuFlyout row. Available Cut, Copy, and Paste actions occupy 40 x 40 icon-primary slots;
  More expands the secondary Undo, Redo, and Select All rows. When no primary action exists, the
  secondary list opens directly rather than showing an empty compact bar. Opening uses the source
  83ms linear opacity storyboard; command, Escape, and outside-click dismissal remain immediate.
- Context command surfaces use content width rather than matching the complete TextBox host.
  Gallery diagnostics are available through `FLUENTKIT_GALLERY_OPEN_TEXT_COMMANDS=1`.

Executable validation covers real `NSWindow` field editors, SearchBox caret geometry, active
selection colors, 40pt primary-command geometry, overflow expansion, content sizing, Escape
dismissal, and PasswordBox command restrictions. Light and Dark compact/expanded diagnostic
captures were reviewed. The next visual phase is a source-by-source reconciliation of the Dark
semantic palette; no Dark surface values were changed as part of this editing-session pass.

## Button-like Surface and Trigger Correction - 2026-07-20

The latest Light capture exposed that the shared Button elevation brush was vertically reversed:
the stronger three-point edge appeared at the top instead of forming the lower elevation edge.
The implementation now follows `Common_themeresources_any.xaml` directly:

- Light `ControlElevationBorderBrush` applies the source `ScaleY=-1` and places its absolute 3pt
  segment on the visual bottom.
- Dark standard controls retain the unflipped source brush; accent controls keep their source
  flipped brush in both schemes.
- Button, DropDownButton, selection ComboBox, editable ComboBox normal state, and CalendarDatePicker
  all use the same `updateFluentElevationBorderLayer` geometry. ComboBox cannot drift to a separate
  top-edge implementation.
- TextBox, PasswordBox, SearchBox, and editable ComboBox editing/open state remain on the separate
  2pt `TextControlElevationBorderBrush` path and do not reuse Button elevation colors.

The same pass fixed two state and lifecycle defects:

- Optional `nil === nil` responder comparisons could classify a control with no window/editor as
  focused. Text controls now require a real first responder before drawing focused chrome.
- DropDownButton presents only after pointer-up inside, a release outside cancels, and clicking an
  already-open trigger removes the presenter without recreating it. Ordinary `Button.Flyout` now
  follows the same toggle contract and never latches its owner in Pressed while open.
- The hidden native `NSComboBox` is permanently transparent in both modes. The editable faceplate
  alone owns text pixels and the custom 30pt glyph column, preventing an AppKit arrow flash.

Fresh Controls and Inputs Light/Dark baselines cover these changes. Executable validation asserts
the light bottom-edge direction for DropDownButton and ComboBox, the TextControl-specific 2pt brush,
the editable Button/TextControl state switch, release-to-open semantics, immediate close, and the
absence of popup exit animations.

### Backing-coordinate and TextControl follow-up - 2026-07-20

The Retina captures exposed that a shared gradient definition was insufficient on AppKit: `NSButton`
and `NSSegmentedControl` install flipped backing layers, while plain `NSView`, `NSControl`, and
`NSDatePicker` do not. The shared elevation renderer now resolves the visual top/bottom from the
actual parent layer before applying the WinUI absolute three-point brush. This keeps Light standard
and accent elevation on the visual bottom across Button, ToggleButton, RepeatButton, DropDownButton,
ComboBox, and CalendarDatePicker; Dark standard controls retain the source top-oriented brush.

The same follow-up makes TextControl theme changes independent of AppKit's effective appearance:
placeholder, edited text, typing attributes, caret, and selection colors are reapplied from the
Fluent theme after field-editor creation/reset. Light focused TextControls use
`SystemAccentColorDark1`; Dark uses `SystemAccentColorLight2`.

SegmentedControl now hosts its outer and focus rings in a hit-test-transparent overlay view ordered
above the selected surface and all labels. The selected view can no longer cover the first/last
rounded edge even when its presentation frame is moving. Validation checks this real view/layer
ownership instead of relying on unrelated sibling `zPosition` values.

## ComboBox Modes and Popup Motion - 2026-07-20

The two WinUI ComboBox layout paths are now represented explicitly instead of sharing the
MenuFlyout presenter:

- `FluentComboBoxMode.selection` keeps the bound item in the popup faceplate. Its popup uses the
  source `SplitOpenThemeAnimation` geometry: a 50% initial clip centered on the selected row, then
  expands toward both edges. The maximum visible range remains 15 items with no more than 7 on one
  side, matching `GetNonPannablePopupLayout` and the ComboBox theme resources.
- `FluentComboBoxMode.editable` uses a real native `NSTextField` faceplate with the source
  `ComboBoxEditableTextPadding` (11,5,38,6). The hidden `NSComboBox` remains the stable option and
  accessibility bridge, while the text field owns editing, IME, selection, and arbitrary text.
  Only the trailing glyph column opens the popup. The popup starts below the field and flips above
  only when the available screen height requires it, matching `GetEditableComboBoxPopupLayout`.
- Editable text changes update the optional text binding and clear the option selection when the
  text is not an exact option title. Committing a popup row writes both text and stable selection.

Popup entrance ownership is one opaque animation root with one presenter clip. MenuFlyout follows
`MenuPopupThemeTransition`: the complete animation root translates by the source closed ratio, the
clip receives the inverse translation, and the popup border expands around the source edge. Root
menus use 50%; submenus use 67%. ComboBox does not reuse that transition. Selection ComboBox runs
SplitOpen around a fixed selected-item offset, while editable ComboBox uses its external TextBox
faceplate as the fixed one-sided reveal baseline. Captures at 20ms show the expected partial one-to-two
row lead-in; the presenter reaches full layout on the 250ms source timeline. No AppKit combo arrow,
native panel shadow, or duplicate popup border is painted in the editable path.

`swift build -Xswiftc -warnings-as-errors` and `swift run FluentKitValidation` pass after this
change. Gallery `inputs` now presents both Selection and Editable examples so the two source paths
remain visible and testable.

## Endpoint and Transition Revalidation - 2026-07-20

The source-fidelity input and popup pass was rechecked against fresh Light and Dark endpoint
captures after the latest baseline and border changes. The Gallery can now freeze live Core
Animation presentation layers before bitmap capture, so popup evidence is no longer limited to
the final model layer.

- TextBox, PasswordBox, and SearchBox render a complete inside border at the fixed 32pt host size.
  Their native line boxes share the same source-derived baseline, while the SearchBox adornment
  remains geometrically centered.
- Button, DropDownButton, and closed ComboBox share the source `ControlElevationBorderBrush`
  three-point edge geometry. The light theme reads the lower elevation edge without a second
  outer stroke.
- The opened ComboBox popup shows the bound current value first, keeps the selected pill inside
  the selected row, and does not assign an extra first-item keyboard highlight.
- Light and Dark MenuFlyout and ComboBox child-panel captures show no readable page-content bleed
  and no stacked AppKit/CALayer black perimeter. The temporary opaque fallback remains the sole
  transient surface until material work resumes.
- `FluentKitValidation` passes, including MenuFlyout whole-presenter motion, ComboBox selected-item
  reveal centers, source closed ratios, and the shared native text baseline. `swift build -Xswiftc
  -warnings-as-errors` and `git diff --check` also pass.
- MenuFlyout and ComboBox open captures at 20ms, 50ms, 125ms, and 200ms are distinct. MenuFlyout
  translates the complete presenter against an inverse clip while its border expands. Selection
  ComboBox keeps all rows stationary and expands only the shared clip around the selected item.
- MenuFlyout and ComboBox popup dismissal is immediate. Item commit, Escape, trigger toggling, and
  outside clicks synchronously remove the complete child panel without allocating an exit animation.
- RTL endpoint and midpoint captures keep the ComboBox selection pill on the trailing edge, mirror
  submenu chevrons, and move the menu check slot without mirroring the check glyph itself.
- Reduce Motion 50ms and 200ms captures are byte-identical for both MenuFlyout and ComboBox. The
  validation executable also checks that no entrance animation is allocated and dismissal remains immediate.

Remaining popup acceptance work is reference-color comparison for increased contrast and the
broader state matrix below. Navigation motion
is revalidated separately in the following section.

## Navigation Transition Revalidation - 2026-07-20

Fresh presentation-layer captures now cover vertical selection in both directions, pane close/open,
RTL, Top navigation, Dark, High Contrast, and Reduce Motion. The Gallery snapshot harness accepts
`FLUENTKIT_GALLERY_NAV_SELECT` and `FLUENTKIT_GALLERY_TOGGLE_PANE`, and freezes active navigation
layer geometry at `FLUENTKIT_SNAPSHOT_PRESENTATION_DELAY_MS` before bitmap capture.

- The 48pt compact rail and 40pt item surface keep the icon and pane-toggle center at x=24 in every
  expanded, collapsing, compact, and opening frame. Expanded mode only reveals trailing text.
- A real close-completion defect was found in `.left` mode: completion restored
  `panePresentationExpanded` merely because the resolved display mode was `.expanded`. At 48pt this
  repainted expanded item labels and exposed glyph fragments along the pane edge. Completion and
  Reduce Motion now derive presentation mode from the actual open state, so settled compact captures
  contain no text fragments.
- `NavigationViewItemHeader` opening now preserves the exact two-segment source timeline: zero
  opacity from 0-100ms, followed by the `(0,0.35,0.15,1)` fade from 100-200ms. The spline is no longer
  applied to the complete keyframe group, which previously made the title visible before 100ms.
- The active 3 x 16 rail remains continuous in both vertical directions. Captures at 50, 150, 300,
  and 550ms show old position, connected midpoint, directional travel, and target settlement without
  a first-frame jump. RTL keeps the rail on the trailing pane edge. Top mode uses the corresponding
  horizontal 16 x 3 path and routes overflow selection through `More`.
- Gallery Reduce Motion is now applied to the complete navigation shell rather than only the page
  transition. Decoded 50ms and 250ms close captures are byte-identical, and the component validation
  confirms that pane, header, and indicator animations are not allocated.

Status: the audited NavigationView geometry and motion matrix is accepted for Light, Dark, RTL, Top,
High Contrast, and Reduce Motion. Broader control-state and reference-color acceptance remains open.

## Latest Corrective Audit - 2026-07-19 (authoritative)

This section supersedes any earlier statement that the input, menu, ComboBox popup, or
collapsed NavigationView visuals have passed visual acceptance. The current implementation may
have the intended state objects and animation hooks, but the supplied capture proves that the
rendered result is still incorrect.

### Evidence from the latest capture

The ComboBox popup is rendered over the Inputs page. The underlying `Work` value and date remain
visible through the popup, the popup has a dark outer outline, each row has another outline, and the
selected row is not visually isolated from the popup surface. This is not a WinUI Liquid Glass
effect; it is a translucent AppKit child panel with an ordinary stroke and shadow.

The collapsed NavigationView still exposes a fragment of its section text. The label is being
animated or retained while the pane is already at compact width, so the text is clipped by the
pane rather than removed from the layout/clip tree at the correct transition boundary.

### Finding A-1: ComboBox popup transparency leaks page content

Owner: `FluentComboBoxPopup` / popup surface renderer

Files: `Sources/FluentKit/FluentComboBoxPopup.swift:90-103`, `:292-301`

The popup window is explicitly non-opaque with a clear window background. Its root view paints a
white fill at alpha `0.94` and then paints a normal border. The result is compositing, not Liquid
Glass: the controls behind the popup remain legible as ghost text. The popup must be an opaque
composition surface or use a real Liquid Glass material that samples and blurs the background
without preserving readable foreground glyphs.

Required behavior:

- No underlying TextBox, ComboBox, DatePicker, or label text may remain readable through the popup.
- Liquid Glass is the only permitted transient material; Acrylic is out of scope.
- The material, border, shadow, clipping mask, and content must be one coordinated surface.
- The popup must remain visually stable over light, dark, high-contrast, and transparent page content.

Classification: FluentKit popup surface, not Gallery layout.

### Finding A-2: ComboBox popup has stacked black borders

Owner: popup panel plus popup root plus item rows

Files: `FluentComboBoxPopup.swift:96-99`, `:292-301`, `:400-414`, `:477-479`

At least three visual layers can draw an outline: the `NSPanel` shadow, the popup root border,
and the row border used for pointer-over/pressed. Because the popup itself is translucent, the
underlying ComboBox border also contributes to the apparent dark edge. WinUI's ComboBox popup has
one overlay border and per-item fills; it does not produce this black nested-panel appearance.

Required behavior:

- One popup elevation/border treatment only.
- Row hover is a subtle fill, not a black outline.
- The selected pill, row fill, popup border, and shadow must not overlap into a second outline.
- The popup clip must prevent child rows from painting outside the rounded surface.

Classification: FluentKit component implementation.

### Finding A-3: ComboBox item state model still conflates keyboard focus and pointer-over

Owner: `FluentComboBoxPopupRow`

File: `FluentComboBoxPopup.swift:459-484`

The current branch treats `isPointerOver || isKeyboardSelected` as one background state and adds a
border for `isPointerOver || isPressed`. WinUI keeps these state axes separate:

```text
Unselected
UnselectedPointerOver
Selected
SelectedPointerOver
SelectedPressed
Disabled
```

The selection pill belongs to the selected item. It must not be driven by popup hover, keyboard
highlight, or popup placement. Pointer-over on an unselected item must still be visible.

Classification: FluentKit state/template implementation.

### Finding A-4: TextBox/SearchBox black edges and wrong focus geometry remain unresolved

Owner: TextBox chrome plus Gallery style selection

Files: `Sources/FluentGallery/main.swift:520-568`,
`Sources/FluentKit/FluentInputControls.swift:20-45`,
`Sources/FluentKit/FluentStyles.swift:559-591`

The Gallery still applies `FluentAutomaticTextFieldStyle` to the TextBox, PasswordBox, SearchBox,
ComboBox, DatePicker, and form input. The renderer fills and strokes a rounded rectangle, while
native AppKit fields can still contribute their own cell/content edge. This explains the heavy
outline, baseline displacement, and duplicated edge visible in the capture.

WinUI TextBox acceptance requires:

- one Fluent-owned chrome layer;
- no native bezel or native focus ring;
- normal 1px control border;
- focused bottom accent stroke of 2px, not a four-sided black outline;
- independent SearchBox icon/content layout;
- identical content insets across TextBox and PasswordBox.

Classification: both Gallery configuration and FluentKit input chrome. The Gallery currently
selects the wrong style, while FluentKit still permits competing edge rendering.

### Finding A-5: Collapsed NavigationView leaks section-label text

Owner: `FluentNavigationView` pane layout and transition lifecycle

Files: `Sources/FluentKit/FluentNavigationView.swift:1093-1124`, `:1201-1224`, `:712-745`

During close, `preservesSectionLabelDuringTransition` keeps the label visible while
`panePresentationExpanded` is already false and the pane is being reduced to compact width. In
`layoutLeftPane`, the label is intentionally excluded from the top-height calculation while it is
preserved. That leaves a visible `NSTextField` without its required layout space, so its glyphs are
clipped by the compact pane and appear as a fragment.

WinUI's `NavigationViewItemHeader` does not leave a freely painted clipped label in the compact
layout. Its opacity/visibility transition and header height transition are coordinated; after the
close boundary the header is collapsed and cannot paint into the item region.

Required behavior:

- During close, the label may fade, but it must remain inside a clip/layout region with a defined
  height until the fade completes.
- The compact pane must never display a partial label prefix.
- The first navigation item must not move because the label is being retained or removed.
- Reopening during close must cancel the old label transition without exposing stale text.

Classification: FluentNavigationView component implementation, not Gallery content.

### Finding A-6: The popup pictured is a ComboBox popup, not a normal MenuFlyout

The screenshot's selected row and left selection pill identify the surface as the dedicated
ComboBox popup. It must not be judged by ordinary MenuFlyout styling. Conversely, a command menu
must remain a `Button`/`DropDownButton` with an attached `MenuFlyout`; its menu rows use the
MenuFlyoutItem template and do not inherit Button chrome.

The intended ownership model is:

```text
FluentButton / FluentDropDownButton + FluentFlyout
FluentComboBox + FluentComboBoxPopup + FluentComboBoxItem
```

Both closed controls may share the Button-like control tokens, but ComboBox is still a Selector,
not a Button. Their popup surfaces and state machines must remain separate.

### Finding A-7: Earlier "completed" entries require visual revalidation

The report entries below describe code paths or validation scaffolding, not acceptance of the
current pixels. In particular, the ComboBox/TextBox pass, MenuFlyout pass, and collapsed-pane
transition must be treated as **implementation present, visual acceptance failed** until the
following are captured and compared:

- closed and opened ComboBox over text-heavy content;
- menu open/close with no readable content bleeding through;
- TextBox normal/focused/disabled/SearchBox states;
- NavigationView expanded-to-compact and compact-to-expanded at mid-animation;
- Light, Dark, RTL, increased contrast, and Reduce Motion.

### Corrective order

1. Fix popup/window compositing and remove all duplicate borders.
2. Fix TextBox ownership so only Fluent chrome paints the input edge.
3. Separate ComboBoxItem selected, keyboard, pointer-over, and pressed states.
4. Fix NavigationView section-label clipping and close-transition layout.
5. Recheck Button/DropDownButton states and MenuFlyout independently.
6. Only then perform pixel and frame-level acceptance against WinUI references.

### Navigation collapse implementation update - 2026-07-20

Finding A-5 has been repaired at the structural and behavioral levels. The section title no longer
paints directly into the pane while the pane width is collapsing:

- `FluentNavigationView` now owns a dedicated, clipped 40pt section-header host corresponding to
  the WinUI `NavigationViewItemHeader` `InnerHeaderGrid`.
- Closing commits the header host to zero height and hides its text before the pane begins shrinking,
  so the 48pt compact rail cannot expose a clipped title prefix.
- The primary item viewport repositions with the source-derived 200ms header transition instead of
  jumping immediately to its compact Y position.
- Opening follows the source sequence: opacity remains at zero for the first 100ms and reaches one
  at 200ms. Generation checks prevent a delayed close from hiding a rapidly reopened header.
- The section header now uses the source-derived 14pt semibold typography and 16pt leading margin.
- Pane-toggle controls receive the environment theme during initial mount, eliminating the white
  hamburger glyph that appeared in Light snapshots before the first declarative update.

Executable validation covers the clipped host geometry, close-boundary visibility, 200ms item
reposition, delayed open keyframes, rapid reversal, indicator alignment, and initial theme injection.
Expanded and compact Light/Dark endpoint captures no longer contain section-title fragments.

Status: superseded by **Navigation Transition Revalidation - 2026-07-20**, which adds normalized
mid-animation, RTL, High Contrast, and Reduce Motion evidence.

### Input chrome, Button-like controls, and popup-root motion update - 2026-07-20

The clipped field edge and displaced input baseline from the supplied Inputs capture have been
corrected at component level:

- TextBox, PasswordBox, and SearchBox now paint their background before AppKit draws the native
  content, then paint the border and focused bottom stroke afterward. Native cells can no longer
  erase the leading/trailing control stroke.
- The rounded border is a filled inside ring whose outer path equals the host bounds. Only the
  centered-stroke underline endpoints use the `0.5 / backingScaleFactor` pixel-grid rule, so neither
  form can be clipped by the view boundary at 1x or Retina scale.
- Native single-line editor rectangles use a font-descender correction for their visual baseline.
  SearchBox retains its independent search-icon and content geometry instead of inheriting the
  plain TextBox correction.
- Button, DropDownButton, and the closed ComboBox use the same Button background states and the
  same `ControlElevationBorderBrush` geometry. The gradient stops are `0.33` and `1.0`, and every
  border mask stays inside the control bounds. Pressed controls replace the elevation gradient with
  the ordinary control stroke, matching the Button resource state change.
- ComboBox keeps its selector-specific focus pill and popup, but its closed title foreground and
  control surface now resolve through the Button visual tokens. A custom text style may still
  provide the semantic content font without taking ownership of the outer chrome.

MenuFlyout motion now follows the ownership and closed-ratio information in the bundled WinUI
source rather than a fixed `4pt + 0.96` approximation:

- `DropDownButton_perf2026.xaml` confirms that DropDownButton reuses Button background, border,
  padding, and corner-radius resources; only the 12pt animated chevron occupies a second column.
- `MenuFlyout_Partial.cpp` creates `MenuPopupThemeTransition` with `ClosedRatio = 0.5` for a root
  menu and applies the transition to the popup animation root. Submenus use their own source ratio.
- `LayoutTransition_partial.cpp` applies parallel timelines to the popup presenter and its border:
  content translates as one block while the clip translates inversely and the border expands in Y.
  FluentKit uses a clipped opaque host with separate `PopupBorder` and `Presenter` layers. ComboBox
  does not reuse this motion: its dedicated SplitOpen clip expands around the current item without
  translating the rows. Both popup types disappear immediately on dismissal.

Executable validation now checks the inside border paths, elevation-gradient stops, parallel
border/presenter animation paths, the exact root/submenu/ComboBox closed scales, and the absence of a second popup
CALayer stroke. New Light and Dark endpoint captures show complete field borders, aligned 32pt
content geometry, and a downward Chevron in both the DropDownButton and closed/open ComboBox states.

### Source-fidelity correction pass - 2026-07-20

The supplied border/baseline capture exposed two remaining implementation errors in the previous
pass. They are now corrected from the bundled templates:

- `TextControlThemePadding` is `10,5,6,6` in `Common_themeresources.xaml`; TextBox, PasswordBox,
  and SearchBox use that shared content rectangle. The previous `10,3,6,6` audit entry came from
  the wrong resource path and raised the native AppKit glyph box too far.
- Fluent text-field border rings use the full host bounds as their outer path. The even-odd inner
  subtraction and focused bottom edge remain inside that path, so AppKit cannot clip the outer edge.
- `DropDownButton_perf2026.xaml` and the ComboBox template both use a 12pt
  `AnimatedChevronDownSmallVisualSource`. The fallback now keeps the glyph pointing down in both
  AppKit layer coordinate systems and matches the source's 9/60 press, 18/60 release, 1.875pt
  depression, and 0.75pt return overshoot.
- `ControlElevationBorderBrush` is an absolute brush with `EndPoint="0,3"`, not a gradient over
  the full control height. Button, DropDownButton, and ComboBox now share one three-point edge
  geometry; the light resource is flipped to the bottom edge, while the dark standard resource
  remains top-oriented. Their CAShapeLayer path is a full-bounds filled ring and both the gradient
  and mask use the window backing scale, so rounded antialiasing cannot remove an outer edge.
- A ComboBox pointer-over changes only the `UnselectedPointerOver`/`SelectedPointerOver` fill. It
  no longer changes the bound selection or moves the selected Pill. The initial keyboard index is
  kept separate from the selected visual state.
- MenuFlyout and ComboBox popup panels have no AppKit shadow and no second Fluent CALayer border.
  The temporary opaque popup surface is the sole fill and edge owner. Menu open motion
  uses a clipped host: the border expands from `scaleY = 0.5` for a root menu (`0.33` for a submenu)
  while all presenter content translates together by the matching 0.5/0.67 ratio and the clip moves
  inversely. ComboBox uses the independent source `SplitOpenThemeAnimation` for a 250ms clip centered
  on the current item. Both popup types dismiss immediately without exit motion.
- `FluentVisualStateCoordinator` is now an adopted, partial shared layer rather than a missing
  abstraction. ProgressBar, Button, DropDownButton, and the closed ComboBox use it for state
  precedence, unchanged-state suppression, and Reduce Motion; remaining controls still need migration.

Status: superseded by **Endpoint and Transition Revalidation - 2026-07-20**. The later pass adds
mid-animation, RTL, increased-contrast, Reduce Motion, and 2x Retina evidence; this still does not
claim full WinUI visual completion for the long-tail control set.

### Corrective pixel pass - 2026-07-20

The follow-up capture showed that the previous source mapping still produced two AppKit-specific
rendering errors: native single-line cells were being reduced to a typographic line box and then
baseline-adjusted a second time, while centered border strokes left a visible gap or clipped corner
when the control was hosted at a fixed 32pt height.

- `fluentTextControlRect` now preserves the full native single-line line box, applies the WinUI
  horizontal content ownership, and applies one font-descender correction. TextBox, PasswordBox,
  and SearchBox therefore share a stable baseline; SearchBox text and its search glyph use the same
  optical center.
- Rounded text-field borders are now filled inside rings. The outer ring follows the control bounds
  and the inner ring is inset by the source border thickness, so no centered stroke half can be
  clipped by the host.
- The ring, Button-like elevation gradient, and its mask now resolve against the actual window
  backing scale. Fresh 2x Light/Dark captures retain every rounded edge and the three-point
  elevation lip without turning a half-point logical inset into a full Retina point.
- Button, DropDownButton, and closed ComboBox explicitly clear native layer borders and use the
  same continuous-corner, full-bounds elevation ring. DropDownButton keeps the source second-column
  contract: an 8pt gap followed by a 12pt animated chevron.
- `FluentPopupTransitionHost` gives MenuFlyout a complete presenter translation, inverse clip, and
  source border Y-scale. ComboBox uses only the selected-item-centered clip path, so its rows never
  inherit MenuFlyout translation. Dismissal removes either host immediately.

The validation executable covers the native line-box centers, SearchBox icon/text center, full-bounds
inside rings, MenuFlyout presenter/clip transforms, ComboBox reveal centers, 250ms entrances,
immediate dismissal, and Reduce Motion.
Light/Dark Inputs baselines were regenerated after this pass. Visual acceptance remains open for
normalized mid-transition captures and the broader long-tail control set.

### Button-owned flyout contract - 2026-07-20

The menu trigger contract now includes a declarative Button-owned path in addition to the dedicated
DropDownButton. `FluentButtonView.flyout(placement:items:)` stores the flyout with the button
configuration, preserves the button action, and opens the existing `FluentMenuFlyout` after AppKit
button tracking completes. The owner releases its Pressed visual before presentation and tracks the
open state through accessibility/automation state, while MenuFlyout rows continue to use their
separate presenter template.

The Gallery now demonstrates three distinct semantics: `FluentDropDownButton` for a chevron command
menu, a regular `FluentButtonView` with an attached flyout, and a regular target with a context-menu
modifier. Executable validation covers the attached flyout action, child-panel creation, pressed
state, keyboard dismissal, and cleanup. A child-panel capture confirms the same single opaque
surface used by the existing MenuFlyout path while material work remains deferred.

### Dedicated NumberBox composition - 2026-07-20

The Gallery's former NumberBox example was a styled `FluentStepper`, so its behavior and geometry
could not reproduce the bundled `NumberBox.xaml` and `NumberBox.cpp`. FluentKit now owns a dedicated
`FluentNumberBoxControl` and declarative `FluentNumberBox` with the source placement modes:

- Hidden leaves the native Fluent text editor as the complete control surface.
- Inline reserves the source 72pt trailing column, applies 4pt source margins, and lays out adjacent
  32 x 24 RepeatButtons. RTL mirrors the content and button order without changing the outer edge.
- Compact reserves a 32pt indicator column and presents a focus-scoped 48 x 88 opaque popup,
  containing two 36 x 36 RepeatButtons with 6pt padding and a 4pt gap. The popup is vertically
  centered on the NumberBox and dismisses immediately on focus loss or an outside click.

The component no longer delegates value behavior to `NSStepper`. Its native AppKit field editor
retains IME, selection, clipboard, undo, caret, accessibility, and responder semantics, while the
NumberBox owns empty-input-to-`NaN`, invalid-input overwrite, disabled validation, range clamping,
wrapping, Up/Down, PageUp/PageDown, focused wheel stepping, and boundary button enablement.

Executable validation covers declarative Int bindings, external clamping, all three placement
modes, exact Inline and Compact geometry, RTL, popup lifecycle, `NaN`, validation modes, wrapping,
keyboard and pointer actions, accessibility, and immediate cleanup. Fresh Inputs and Compact-popup
Light/Dark 2x captures cover the resulting pixels. Increased contrast and alternate density remain
part of the long-tail visual acceptance matrix.

### CalendarDatePicker closed-state and native calendar boundary - 2026-07-20

The Gallery's single-line date field maps to WinUI `CalendarDatePicker`, not the three-column
`DatePicker`. The closed control now follows `CalendarDatePicker_themeresources_perf2026.xaml`:

- 32pt minimum height, one-point border, ControlElevationBorderBrush, and the source control fills;
- a fixed 32pt trailing glyph column with a 12pt calendar glyph;
- source text padding `12,0,0,2` and a shared single-line baseline;
- discrete Normal, PointerOver, Pressed, Focused, and Disabled setters without an invented brush
  animation;
- native AppKit bezel, background, and focus ring disabled so the Fluent surface has one owner.

AppKit exposes no public method for opening the private calendar button embedded in a text-field
`NSDatePicker`. FluentKit therefore owns an explicit transient `NSPopover`; its content is a native
`.clockAndCalendar` `NSDatePicker`, preserving date selection, locale, calendar, time-zone, range,
keyboard, and accessibility behavior. Primary click anywhere on the closed field, keyboard
Enter/Space, and `performClick` all use this same presentation path.

Status: the closed CalendarDatePicker geometry and state ownership are behaviorally accepted in
Light/Dark at 1x/2x. The calendar grid intentionally remains native AppKit rendering, so exact WinUI
calendar-grid visual parity is partial rather than complete.

## Full Non-Material Audit and Remediation Plan - 2026-07-19

### Scope and exclusions

This is the current implementation audit for the Gallery and its reusable FluentKit controls. It
covers geometry, ownership, visual states, animation, popup placement, clipping, focus, keyboard
and accessibility surfaces, and Gallery composition. It deliberately excludes the Acrylic/Liquid
Glass migration. During this work, transient surfaces should use a neutral opaque test surface so
that geometry and state bugs can be judged without material noise.

The status vocabulary is intentionally strict:

| Status | Meaning |
|---|---|
| Missing | No reusable implementation or required state exists |
| Structural | A component/layer/state path exists, but visual parity is not proven |
| Behavioral | Interaction, binding, keyboard, or animation lifecycle has executable checks |
| Visually accepted | Reference screenshots/frame checks pass across the required states |

Most controls currently stop at Structural or Behavioral. Existing validation must not be read as
visual acceptance.

### Component inventory and current status

| Gallery area | Components exercised | Current assessment | Main gap |
|---|---|---|---|
| Shell | `FluentTitleBar`, `FluentNavigationView`, page transition host, scroll host | Structural | compact label clipping, icon-column geometry, full state capture |
| Overview | Button, Toggle, Slider, TextBox, SecureField, ProgressBar, CheckBox, RadioButton, SegmentedControl, Stepper, cards | Structural/Behavioral | mixed visual systems and card/layout acceptance |
| Controls | Button, MenuFlyout, ContextMenu, ProgressBar, ToggleSwitch, Slider, CheckBox, RadioButton, SegmentedControl | Structural/Behavioral | menu trigger states, wrong segmented semantics, pixel parity |
| Inputs | TextBox, PasswordBox, SearchBox, DropDownButton, ComboBox, CalendarDatePicker, NumberBox, FormField | Structural/Behavioral | cross-theme popup/grid acceptance and remaining long-tail states |
| Collections | snapshot collection/grid and selection | Structural | container metrics, selection/hover parity, viewport sizing |
| Navigation | split view and selection binding | Structural | split-pane states and transition acceptance |
| Motion/theme | Reduce Motion, theme buttons, TeachingTip, material cards | Structural | shared visual-state contract and deterministic frame capture |
| Application | settings scene, native window tabs, segmented tabbing control | Structural | TabView/SelectorBar semantics and native/AppKit boundary documentation |

### Findings by responsibility

#### P0: Input rendering is not a single-owner system

`FluentAutomaticTextFieldStyle` is applied throughout `inputsPage` at
`Sources/FluentGallery/main.swift:520-568`. It draws a complete rounded field while native
`NSSearchField`, `NSComboBox`, `NSDatePicker`, and the text-field cell can still paint content or
edge chrome. This is the direct source of the heavy outlines, baseline displacement, and inconsistent
focus indicator.

Required design:

- one Fluent-owned background/border/focus renderer per input;
- native bezel, native focus ring, and duplicate cell chrome disabled;
- TextBox normal/focused/disabled states defined independently;
- SearchBox icon/content insets owned by SearchBox, not by the generic TextBox renderer;
- DatePicker and NumberBox use the same outer metrics but keep their own inner controls;
- FormField must not add another border around a child that already owns its surface.

Owner: FluentKit input controls plus Gallery style selection. This is not a page-layout-only bug.

#### P0: ComboBox is structurally separate but still visually mixed with MenuFlyout

The dedicated `FluentComboBoxPopup` is present, but the control still combines native `NSComboBox`,
custom focus layers, a custom popup window, and row-level borders. The popup currently exposes
underlying page text and its selected/keyboard/pointer states are not independent.

Required design:

- closed ComboBox shares Button-like control tokens, but remains a Selector;
- popup width is anchored to the ComboBox minimum width and expands only for content;
- popup placement is based on the anchor rect and selected-row center;
- selected pill is driven only by selected value;
- `UnselectedPointerOver`, `SelectedPointerOver`, and `SelectedPressed` have distinct visuals;
- keyboard highlight must not be used as pointer-over;
- one popup outline and one controlled shadow are allowed in the test surface;
- no popup child may paint beyond its rounded clip.

Owner: FluentKit ComboBox and popup. Gallery currently uses ComboBox correctly for theme selection,
but still uses a MenuButton for account selection, which is semantically a separate command-menu case.

#### P0: Navigation collapse has a lifecycle/clip defect

`preservesSectionLabelDuringTransition` keeps the label visible while the pane is already laid out
as compact. The label is then excluded from the top-height calculation in `layoutLeftPane`, so its
glyphs are clipped by the compact pane and a fragment becomes visible.

Required design:

- retain the label only inside a transition container with explicit height and clipping;
- collapse or remove the label at the same boundary as its header height;
- never allow the compact pane to paint expanded text;
- keep icon and pane-toggle centers fixed across expanded/compact states;
- cancel stale label animations on rapid reopen/close.

Owner: `FluentNavigationView`, not Gallery page content.

#### P1: Menu trigger and ComboBox share visual tokens but not templates

`FluentDropDownButton` is an independent `NSButton` subclass and its `draw` path does not provide a
complete Normal/PointerOver/Pressed/Focused/Disabled state surface. The WinUI model is a Button or
DropDownButton with an attached Flyout. MenuFlyoutItem is not a Button and should use its own row
template. ComboBox is a Selector with Button-like closed chrome, not a Button subclass.

Plan consequence: introduce a shared control-chrome contract, then implement Button/DropDownButton,
ComboBox, and MenuFlyoutItem as separate consumers of that contract.

#### P1: SegmentedControl is being used for multiple incompatible semantics

`FluentSegmentedControl` is backed by `NSSegmentedControl` and is used for progress status, generic
selection, and application tabbing. Its large selected blue rectangle is not WinUI SelectorBar
visuals. The Gallery must classify each usage before changing pixels:

- page/view switching: SelectorBar-like control;
- mutually exclusive form choice: RadioButtons or a selector group;
- command/tabbing policy: a dedicated tab/choice control;
- progress state: a state selector, not automatically SelectorBar.

The current implementation has a custom indicator and hover code, but semantic reuse makes its
visual acceptance ambiguous.

#### P1: Core controls have behavior checks but insufficient visual acceptance

ToggleSwitch, Slider, CheckBox, RadioButton, and ProgressBar have stable layer trees and interaction
tests. Their remaining work is reference-based geometry/color/state capture, not a rewrite of all
behavior. Each must still pass Normal, PointerOver, Pressed, Focused, Selected, Disabled, RTL, Dark,
High Contrast, and Reduce Motion screenshots.

#### P1: Collections and navigation indicators need a separate acceptance pass

The list indicator coordinate conversion and animation infrastructure exists, but the Gallery does
not yet prove the following together: expanded/compact navigation, footer selection, scroll offset,
resize, RTL, rapid replacement, and page transition. Collection item padding, row height, hover
surface, selected rail, and content viewport sizing also require reference captures.

#### P2: Long-tail controls are structurally present or native-backed but not WinUI-equivalent

CalendarDatePicker's native calendar grid, Stepper/NumberBox-like input, ColorPicker, FormField,
cards, TeachingTip, Disclosure, NavigationSplitView, Table, Outline, and application tabbing need
component-specific acceptance.
They should not be used as evidence that the core WinUI control set is complete.

### Implementation plan, in dependency order

#### Phase 0 - Freeze the audit contract

Deliverables:

1. Mark every component with the four status levels above.
2. Freeze a neutral opaque test surface; do not change material systems in this plan.
3. Define shared metrics for control height, corner radius, border thickness, content insets, icon
   column, popup row height, and selection-pill geometry.
4. Define one coordinate-space policy for flipped `NSView`, unflipped `NSView`, CALayer,
   collection-layout, window-screen, and popup-anchor frames.
5. Add a reference-state naming convention: `component/state/theme/size/direction`.

Exit gate: every screenshot or animation claim can be traced to a component, state, and reference.

#### Phase 1 - Fix input ownership and geometry

1. Build the shared TextBox chrome contract.
2. Remove native bezel/focus/cell edge ownership from TextBox, PasswordBox, SearchBox, ComboBox,
   CalendarDatePicker, and Stepper where Fluent draws the outer surface.
3. Fix content insets and baselines; verify SearchBox icon placement separately.
4. Make FormField layout own labels/help/validation spacing without wrapping another field border.
5. Capture normal, focused, disabled, empty, filled, and invalid/success states.

Exit gate: no black duplicate edge and no baseline drift at the standard Gallery size.

#### Phase 2 - Establish Button and menu contracts

1. Define shared Button-like chrome and state resolution.
2. Convert menu-trigger usage to `Button/DropDownButton + attached Flyout` semantics while retaining
   AppKit event behavior.
3. Add trigger hover, pressed, focused, and disabled visuals.
4. Keep MenuFlyoutItem as its own template with check, submenu, separator, accelerator, and
   pointer/pressed states.
5. Verify anchor placement, edge flipping, submenu ownership, keyboard navigation, and dismissal.

Exit gate: a command menu and a ComboBox no longer look like the same component internally, while
their closed control chrome remains aligned.

#### Phase 3 - Finish ComboBox

1. Make popup compositing opaque for the test surface and remove duplicate borders.
2. Separate selected, keyboard, hover, pressed, and disabled row state.
3. Align popup minimum width and selected-row center to the anchor.
4. Add opening, closing, row-press, and selection-change frame captures.
5. Verify popup over text-heavy content, near every screen edge, and after rapid reopen.

Exit gate: no readable content bleed, no stacked black outline, correct pill ownership, and stable
placement across resize and RTL.

#### Phase 4 - Repair NavigationView collapse and indicator acceptance

1. Replace free-floating retained section text with a clipped header transition container.
2. Keep the icon column and pane-toggle center invariant across expanded/compact layouts.
3. Verify item/header/footer/settings/overflow states independently.
4. Capture pane open/close at start, midpoint, and end, including interrupted reversal.
5. Verify vertical and top-mode indicators after scroll, resize, footer selection, RTL, and rapid
   target changes.

Exit gate: no clipped label, no icon jump, and indicator center remains on the selected item.

#### Phase 5 - Classify and finish core control families

1. Split current SegmentedControl usages by semantic role.
2. Implement SelectorBar-like visuals only where the usage is actually a page selector.
3. Recheck ToggleSwitch, Slider, CheckBox, RadioButton, and ProgressBar against reference states.
4. Add pressed/released and Reduce Motion frame checks, not just layer-property assertions.

Exit gate: each Gallery example has one documented WinUI counterpart and one accepted state matrix.

#### Phase 6 - Collections, composite controls, and long tail

1. Validate Collection/Grid item sizing, selection, hover, scrolling, and viewport constraints.
2. Validate NavigationSplitView and NavigationStack composition.
3. Validate the CalendarDatePicker native calendar boundary, Stepper/NumberBox, ColorPicker,
   Disclosure, FormField, TeachingTip, Dialogs, Table, Outline, and native tabbing boundaries.
4. Record unsupported WinUI controls explicitly rather than implying parity from native wrappers.

#### Phase 7 - Gallery verification and completion gate

1. Make each Gallery page a deterministic state fixture rather than a prose showcase.
2. Add controls for theme, contrast, RTL, Reduce Motion, compact/expanded pane, and popup edge
   placement.
3. Capture reference screenshots and normalized animation frames for every P0/P1 component.
4. Run build, accessibility, keyboard, resize, scroll, deactivation, dismissal, and rapid-input
   checks.
5. Mark a component visually accepted only when all required states and interruption paths pass.

### Verification matrix for every P0/P1 component

| Dimension | Required cases |
|---|---|
| Geometry | standard/compact size, resize, RTL, edge placement, flipped coordinates |
| Visual states | normal, pointer-over, pressed, focused, selected, disabled |
| Content | empty, placeholder, filled, long text, icon, validation/help text |
| Motion | open/close, selection change, press, release, interruption, Reduce Motion |
| Lifecycle | external binding update, deactivation, outside click, escape, rapid reopen |
| Accessibility | role, label, value, keyboard focus, activation, selection announcement |
| Evidence | screenshot plus normalized frame capture, not layer existence alone |

### Non-material definition of done

The non-material pass is complete only when:

- no input or popup shows duplicate black edges or readable background bleed;
- compact NavigationView never exposes expanded text and its icon column does not jump;
- Menu trigger, ComboBox, MenuFlyoutItem, and SelectorBar-like controls have distinct correct
  templates and state machines;
- each core control has accepted state and motion evidence in Light, Dark, RTL, High Contrast, and
  Reduce Motion;
- Gallery examples use semantically correct components and stable layout fixtures;
- old views, layers, animations, panels, and indicators are removed or settled after interruption;
- unsupported controls are documented instead of counted as completed.


## Implementation Update - 2026-07-19

Completed in the first layout and motion hardening pass:

- `FluentDivider` now has explicit horizontal and vertical orientations; the Gallery column divider
  uses the vertical contract.
- The shared list selection rail now follows flow-layout document coordinates, updates after layout,
  scrolling, bounds changes, frame changes, selection, and stable-ID reordering, and has executable
  selected-row alignment coverage.
- Gallery page content is keyed by `GalleryPage` inside a persistent transition host with a Fluent
  cubic-bezier token, latest-update coalescing, RTL-aware direction, and Reduce Motion behavior.
- Transition cleanup is driven by a Core Animation completion callback with a generation-checked
  dispatch fallback for non-presenting validation environments; rapid updates resolve to the latest
  requested page without retaining outgoing entries.
- The shared vertical list rail keeps one active indicator layer and follows the WinUI same-level
  NavigationView choreography: 3 x 16 geometry, 600ms source-to-midpoint-to-destination motion,
  connected bounds peak, upward/downward direction, RTL leading edge, presentation-frame continuity
  for rapid target replacement, and Reduce Motion snapping.
- Duplicate page-local titles were removed, the Collections viewport was expanded to show both
  sections completely, and Controls/Inputs Light and Dark captures were regenerated.
- `FluentKitValidation` now verifies every documented bitmap baseline for existence, dimensions,
  and visible pixel variation.

Completed in the NavigationView and TitleBar pass:

- Public `FluentNavigationView` now supplies Auto, Left, LeftCompact, LeftMinimal overlay, and Top
  modes, primary/footer destinations, bound pane state, explicit 350ms open and 120ms close motion,
  keyboard/accessibility behavior, RTL, Reduce Motion, and custom Top overflow.
- The reusable navigation indicator uses one continuous visible rail in both vertical and horizontal
  orientations, with the previous compatibility layer kept hidden. Primary-to-footer changes exercise
  the cross-section path; Top overflow selection routes the horizontal indicator through `More`.
- Navigation item rendering owns normal, pointer-over, pressed, selected combinations, disabled,
  and keyboard-focus states instead of relying on Gallery-specific rows.
- Public `FluentTitleBar` now supplies 32pt compact and 48pt expanded/automatic layouts, pane and
  back actions, icon/title/subtitle, left/center/right slots, RTL, inactive-window state, native
  dragging and double-click behavior, and native traffic-light exclusion/restoration.
- Gallery uses one shared pane binding between `FluentTitleBar` and `FluentNavigationView`, removes
  the duplicate native-rendering label, and retains one shell-owned page title.
- Fourteen Light/Dark/RTL/responsive bitmap baselines now include the integrated title bar.

Completed in the ToggleSwitch pass:

- `FluentToggle` now separates idle, pressed, and dragging interaction state from its committed
  Boolean value. Clicks commit on release-inside, drag release resolves by midpoint/direction, and
  cancellation or external binding updates cannot emit a stale commit.
- The stable 40 x 20 track and knob layers use 12 x 12 Normal, 14 x 14 PointerOver, and 17 x 14
  Pressed/Dragging geometry with 83ms `(0,0,0,1)` state motion. On/Off repositioning uses the
  separate 167ms token. Same-bounds layout no longer overwrites active presentation animations.
- Toggle-specific Light/Dark/High Contrast fills and strokes now distinguish Off and borderless On
  tracks. RTL mirrors text, track placement, drag direction, and logical endpoints.
- Reduce Motion, keyboard focus, accessibility press, disabled behavior, external binding
  cancellation, exact geometry, single-commit behavior, and animation survival have executable
  coverage. Gallery exposes On, Off, and Disabled states together.

Completed in the Slider pass:

- `FluentSlider` now owns stable track, value-fill, 18 x 18 outer-thumb, inner-thumb, and focus
  layers. The inner thumb uses 12 x 12 Normal, 14 x 14 PointerOver/Disabled, and 10 x 10 Pressed
  geometry with source-derived 167ms/250ms `(0,0,0,1)` motion.
- Value and pointer position remain direct while only inner-thumb geometry animates. Same-bounds
  layout preserves active state motion; resizing and direction changes deliberately snap to a
  defined model state.
- RTL endpoints and arrow keys, Home/End, keyboard focus, accessibility increment/decrement,
  disabled input rejection, external-binding drag cancellation, Escape restoration, and Reduce
  Motion have executable coverage. Gallery exposes interactive and Disabled sliders in desktop and
  Minimal Light/Dark captures.

Completed in the CheckBox and RadioButton pass:

- Both controls now separate pointer-over and pressed interaction state from their committed Boolean
  value, commit on release-inside, cancel on release-outside/Escape, and discard stale pointer input
  when an external binding wins.
- CheckBox uses stable box, check-glyph, and focus layers. Its check path follows the
  `AnimatedAcceptVisualSource` markers with a 19-frame reveal using `(0.55,0,0,1)` and a four-frame
  clear using `(0.167,0.167,0.833,0.833)`.
- RadioButton uses stable 20pt outer, selected-dot, pressed-feedback, and focus layers. Its dot uses
  12pt Normal, 14pt PointerOver/Disabled, and 10pt Pressed geometry with source-derived 250ms/167ms
  motion; an unselected press expands the dedicated feedback dot from 4pt to 10pt.
- Same-bounds reconciliation preserves explicit glyph motion. RTL, keyboard focus/activation,
  accessibility press, disabled input, Reduce Motion, exact geometry/timing, and single-commit paths
  have executable coverage. Gallery exposes checked, unchecked, selected, and disabled states.

Completed in the SegmentedControl pass:

- `NSSegmentedControl` remains the input and accessibility surface, while the overridden Fluent
  renderer is the only visual owner. Stable custom labels and one selection-indicator layer survive
  compatible declarative updates.
- Pointer state is independent from committed selection. Release inside commits once; release
  outside, Escape, disabled state, and external binding updates cancel stale pointer interaction.
- Selection writes final model geometry first and begins from sampled presentation geometry. The
  arbitrary scale/opacity keyframes are removed; synchronized position and bounds use the
  SelectorBar-derived 167ms `(0,0,0,1)` token.
- Same-bounds layout does not touch an active animation. Actual resize/direction changes deliberately
  snap to model geometry. RTL mirrors labels, hit testing, selection movement, and arrow keys;
  Reduce Motion snaps without allocating an animation.
- Validation covers visual ownership, stable identity, exact motion properties, cancellation, RTL,
  and Reduce Motion. Gallery exposes interactive and Disabled states in desktop and Minimal
  Light/Dark captures.

Completed in the focus, pane-collapse, and MenuFlyout pass:

- Pointer focus no longer produces keyboard-only focus visuals on Button, ToggleSwitch, Slider,
  CheckBox, RadioButton, SegmentedControl, or NavigationView controls.
- NavigationView hides section text before its pane frame begins collapsing, so the compact rail
  never displays a clipped label prefix during motion.
- Gallery exposes two left-click MenuFlyout entries. Both are covered through actual synthesized
  left-button down/up events rather than programmatic action dispatch.
- Root menus reveal from 50% height and submenus from 33% height using the dedicated 250ms
  `(0,0,0,1)` motion. The complete presenter moves by 50%/67%, its clip moves inversely, and the
  border expands from 50%/33% at the resolved top or bottom edge.
- MenuFlyout dismissal immediately removes the presenter hierarchy; there is no exit animation.
- Menu geometry animation uses explicit Core Animation presenter, clip, and border transforms; the
  previous TeachingTip translation plus uniform X/Y scaling path has been removed.

Completed in the ComboBox popup and TextBox chrome pass:

- `FluentComboBox` no longer reuses `FluentMenuFlyout`. Its dedicated popup owns ComboBoxItem
  rows, selected background, leading selection Pill, pointer/pressed/keyboard states, current-item
  vertical alignment, outside-click/Escape dismissal, and a 250ms SplitOpen clip centered on the
  current item. The clip grows near an edge instead of shifting its center; dismissal is immediate.
- Automatic TextBox, PasswordBox, and SearchBox styling now shares one Fluent chrome renderer.
  Normal state uses a 1pt rounded elevation border; focused state retains that border and adds the
  source-derived 2pt bottom accent instead of thickening all four sides.
- Inputs Light/Dark baselines were regenerated, and timing-sensitive validation now waits on
  observable completion conditions rather than relying on fixed sleeps shorter than the motion.

Still open by design:

- Long-tail acceptance remains open for CalendarDatePicker's native calendar grid, NumberBox,
  collection controls, and remaining transient presenters. Text input content insets/baselines and
  ComboBox edge placement still need full visual acceptance across density, RTL, and
  increased-contrast scenarios.
- MenuFlyout and ComboBox popup currently use one opaque edge owner. Liquid Glass, TeachingTip, and
  remaining popover/overlay material boundaries remain separate follow-up work.
- Full XCTest integration remains blocked until a complete Xcode toolchain provides `XCTest`.

## 1. Objective

The target is not a WinUI runtime compatibility layer. FluentKit should preserve AppKit windowing, input, keyboard, accessibility, and native control behavior while reproducing the visible appearance, visual states, and motion character of WinUI 3.

The material direction is now explicit:

- Acrylic is not part of the target design.
- In-application transient surfaces must use Liquid Glass.
- The macOS system main menu remains native `NSMenu`.
- WinUI source remains the authority for geometry, state sequences, durations, curves, and keyframes where the target deliberately reproduces WinUI behavior.

## 2. Executive Summary

The project already contains a broad AppKit-based declarative control library, custom drawing, theme tokens, state-aware controls, menu flyouts, transition hosts, keyframe/value animation, and matched geometry infrastructure. The current Gallery, however, does not yet provide a reliable visual proof of WinUI fidelity.

The most visible failures have different owners:

| Symptom | Owner | Primary cause |
|---|---|---|
| Gallery page changes have no visible transition | Resolved | Stable keyed transition host, RTL direction, Reduce Motion, and rapid-update coalescing |
| Navigation indicator appears near the top | Resolved | Explicit document-to-layer conversion plus layout/scroll/resize synchronization |
| Menu content looks doubled or ghosted | FluentKit surface | Acrylic transparency allows underlying text to remain legible; panel shadow and inner border create a second outline |
| Menu motion does not feel specific to a menu | FluentKit motion | Menu reuses TeachingTip motion tokens |
| Navigation selection does not resemble WinUI | Visual acceptance | Reusable row states and two-indicator motion exist; exact token/pixel comparison remains |
| Controls have inconsistent motion | FluentKit motion architecture | WinUI tokens coexist with generic Core Animation defaults and component-local timing choices |

The correct order is to stabilize coordinates and host lifecycles first, then replace the material layer, then reproduce component visuals and choreography. Adjusting colors before those structural issues are fixed will not produce reliable results.

## 3. Audit Method

This audit used:

- The two supplied Gallery screenshots.
- Static inspection of the Gallery shell and FluentKit component implementations.
- Comparison with motion constants and algorithms in the bundled WinUI 3 source.
- A clean `swift build`, which completed successfully.

The audit did not include frame-by-frame runtime capture, automated pixel comparison, or interaction recording. Those are required in the verification phase.

## 4. Architecture Assessment

### 4.1 What the project currently is

FluentKit is a Swift/AppKit declarative UI layer. Its native behavior comes from AppKit, while custom `NSView`, `NSControl`, Core Graphics, and Core Animation code supplies Fluent visuals.

This is appropriate for the stated target:

```text
WinUI source and reference behavior
        -> Swift visual/state/motion specifications
        -> AppKit controls and event handling
        -> Core Graphics/Core Animation/Liquid Glass rendering
```

Windows Composition and XAML runtime objects cannot be reused directly. Algorithms and specifications must be rewritten in Swift; only their final low-level operations map to macOS rendering primitives.

### 4.2 Existing strengths

- Stable declarative primitives and AppKit hosting exist.
- Core controls expose semantic states and theme inputs.
- Duration and cubic-bezier tokens have begun to use WinUI values.
- A custom in-application menu presenter exists.
- Transition, value animation, keyframe, spring, and matched geometry infrastructure exists.
- Reduce Motion is represented in the rendering context.
- The project builds successfully.

### 4.3 Structural weaknesses

- Motion is opt-in and inconsistently connected to the Gallery.
- Generic animation defaults remain alongside WinUI-specific tokens.
- Several visual components mix AppKit view coordinates with CALayer coordinates.
- Some components update animated geometry and then overwrite it in a nonanimated layout pass.
- Material behavior is encoded inside individual presenters instead of a single surface system.
- NavigationView and TitleBar structure is now reusable; remaining weaknesses are component-level
  visual token fidelity rather than Gallery-owned shell drawing.

## 5. Critical Findings

### P0-1: Navigation indicator coordinate failure - resolved

Owner: FluentKit `FluentList`  
File: `Sources/FluentKit/FluentList.swift`, `updateSelectionIndicator`

The selection indicator is a sublayer of `collectionView.layer`. Its target frame is calculated directly from `NSCollectionViewFlowLayout` attributes and assigned to the sublayer. The implementation does not establish whether the sublayer geometry matches the collection view's flipped coordinate system.

Impact:

- The selected row and accent indicator can disagree.
- The indicator may appear near the top or opposite side of the list.
- Animation keyframes inherit the same invalid coordinates.
- Scrolling and relayout can move the indicator unpredictably.

Required correction:

- Define one coordinate space for layout and animation.
- Convert item frames explicitly into the indicator host's layer coordinates.
- Recompute after layout, scrolling, bounds changes, row insertion, and selection changes.
- Test flipped and nonflipped hosts instead of relying on CALayer defaults.

Acceptance criteria:

- Indicator center aligns with the selected row before, during, and after animation.
- Alignment remains correct after scrolling, resizing, theme changes, and rapid selection changes.

Current status: complete with executable selected-row, scrolling, resize, stable-ID update, RTL, and
Reduce Motion coverage. `FluentList` converts layout document frames into its layer coordinate space
before calculating the rail frame.

### P0-2: Gallery main navigation has no page transition - resolved

Owner: FluentGallery  
File: `Sources/FluentGallery/main.swift`, `GalleryNavigationShell`

The page body is inserted directly into the scroll view. It is not wrapped by a persistent transition host keyed by the selected page. The existing transition component therefore never receives an old/new page pair.

Impact:

- Sidebar selection changes immediately replace the page.
- Users cannot see the motion system while using the primary Gallery workflow.
- The Gallery understates the framework's existing animation capability.

Required correction:

- Keep a stable content host across page changes.
- Track old and new page identities explicitly.
- Apply direction-aware entrance/exit choreography.
- Preserve scroll position according to an explicit policy.
- Respect system and Gallery Reduce Motion settings.

Acceptance criteria:

- Every primary navigation change has a visible, interruptible transition when motion is enabled.
- No stale page remains mounted after completion.
- Rapid navigation settles on the last requested page without flashing.

Current status: complete. Gallery keys page content by `GalleryPage` inside a persistent transition
host and uses a Fluent 250ms cubic-bezier token with RTL direction, Reduce Motion, generation-safe
completion cleanup, and latest-update coalescing.

### P0-3: Transient surface system uses the rejected material

Owner: FluentKit material/presentation layer  
Files: `FluentMaterialView.swift`, `FluentMenus.swift`, `FluentTeachingTip.swift`, `FluentOverlays.swift`

MenuFlyout and TeachingTip instantiate `.acrylic`. Acrylic is no longer part of the target direction.

Impact:

- Underlying text remains readable through menus, producing perceived ghosting.
- Material appearance does not match the chosen macOS-native Liquid Glass direction.
- Material tuning is duplicated across presenters.

Required correction:

- Introduce one Liquid Glass surface renderer.
- Route MenuFlyout, TeachingTip, Popover, transient panels, and optional navigation surfaces through it.
- Centralize glass tint, blur, saturation, edge highlight, border, shadow, active state, and contrast behavior.
- Provide graceful fallback for systems without the desired Liquid Glass API.
- Remove component-local Acrylic alpha tuning.

Acceptance criteria:

- Text behind a menu cannot be read as a duplicate of foreground content.
- Glass remains visibly distinct from opaque content surfaces.
- Light, dark, inactive-window, and increased-contrast states remain legible.

## 6. Navigation Audit

### P1-1: Navigation row state ownership - implemented, visual acceptance open

Gallery no longer owns a private row renderer. `FluentNavigationItemButton` now draws the reusable
normal, pointer-over, pressed, selected, selected-pointer-over, selected-pressed, disabled, and
keyboard-focus states. Exact WinUI resource colors and pixel comparison remain part of visual
acceptance rather than a missing state-model capability.

Required states:

- Normal
- PointerOver
- Pressed
- Selected
- SelectedPointerOver
- SelectedPressed
- Disabled where applicable
- Keyboard focused

The selected surface and accent indicator must be coordinated. They should not be implemented as unrelated visual updates.

### P1-2: Indicator choreography - complete for list and NavigationView paths

The shared list renderer now maintains separate previous and next indicator layers. Its vertical
same-level path uses a stable 3 x 16 rail, a 600ms `0`, `0.333`, `1` timeline, WinUI source curves,
connected-rectangle peak scaling, outgoing opacity hold/fade, and explicit direction-aware geometry.
The model frame remains stable while the effective position keyframes encode the visual result of the
WinUI CenterPoint transition; this avoids the AppKit frame jump that a raw anchor-point mutation would
cause.

The reusable NavigationView uses the same two-indicator engine vertically for primary/footer
destinations and horizontally for Top navigation. Hidden Top selections route through `More` without
moving the model indicator to an invalid destination. Same-target repetition, target replacement,
cancellation, RTL leading-rail placement, primary-to-footer changes, Top overflow, and Reduce Motion
are covered by executable validation. The CenterPoint behavior is represented internally through
stable model frames plus effective position/scale keyframes; a public anchor API is not required for
the component acceptance contract.

### P1-3: Gallery navigation is not a reusable NavigationView proof - resolved

Original finding: the shell combined `FluentList` with Gallery-specific native rows and a separate
footer button, so it did not demonstrate a coherent public NavigationView component.

Required correction:

- Move item layout, state rendering, selection indicator, footer/settings placement, pane sizing, and pane motion into a reusable navigation presenter.
- Keep Gallery data and destination content outside the component.

Current status: complete. Gallery supplies only destination metadata, selection, pane binding, and
page content to public `FluentNavigationView`; the component owns item/footer layout, pane modes,
selection surfaces, overflow, indicator geometry, pane motion, keyboard, and accessibility.

## 7. Menu and Popup Audit

### P1-4: Menu positioning API is ambiguous

`present(relativeTo:at:)` mixes anchor-view bounds, local points, window coordinates, and screen coordinates. Menu buttons pass a local `bounds.minY` point even though a button-relative placement mode would be more reliable.

Required correction:

- Separate anchor-rect placement from pointer placement.
- Use explicit placement modes such as bottom-start, bottom-end, top-start, pointer, and submenu-leading/trailing.
- Calculate the final screen frame before creating or animating the panel.
- Record whether the surface was flipped above/below so motion direction matches placement.

### P1-5: Menu motion is borrowed from TeachingTip - resolved

The menu previously used TeachingTip open/close tokens: scale, vertical translation, opacity,
`300ms` open, and `200ms` close.

Implemented correction:

- Dedicated root-open and submenu-open tokens use 250ms timing.
- Root and submenu presenters translate by 50% and 67% while their clips translate inversely and
  their borders expand from 50% and 33% at the resolved top or bottom placement edge.
- Dismissal removes the panel immediately without an exit animation.
- Reduce Motion reaches final presentation state without entrance animation.

### P1-6: Menu outline appears doubled

The panel has a native shadow while the material view adds its own border and clips to rounded corners. With a translucent surface this produces an outer shadow, inner border, and visible underlying geometry.

Required correction:

- Make the Liquid Glass surface the single owner of edge highlight, border, and shadow.
- Avoid layering a generic panel shadow with an unrelated inner stroke unless both values are deliberately specified.

### P2-1: Menu item model is visually incomplete

The current item model supports title, state, shortcut, separator, submenu, and action. It does not expose a leading icon/glyph or richer command presentation.

Required additions:

- Optional leading icon.
- Check/radio/icon slot rules.
- Accelerator column metrics.
- Submenu indicator slot.
- Destructive or emphasized command role if required by the target Gallery.
- Explicit disabled and focus visuals.

## 8. Control Appearance Audit

### P1-7: Several controls retain visibly native macOS chrome

The supplied Inputs screenshot shows native date and stepper arrows and other AppKit-specific geometry. Preserving AppKit behavior is correct, but their visible chrome must be replaced or overlaid when the target is WinUI appearance.

High-priority controls and native-boundary follow-up:

- CalendarDatePicker calendar-grid visual acceptance (closed-state chrome is complete)
- Stepper/NumberBox
- ComboBox
- TextField/SecureField

Slider, CheckBox, and RadioButton no longer use native chrome or immediate-mode selection glyphs;
their full visual surfaces are owned by stable FluentKit layers. Exact state acceptance is recorded
in section 20.

Required approach:

- Keep the native editor/control for event handling and accessibility.
- Hide or neutralize incompatible native chrome.
- Draw the Fluent visual surface and states in the owning wrapper.
- Preserve native first responder, text input, selection, keyboard, and accessibility behavior.

ComboBox progress in this pass:

- `FluentComboBoxHost` keeps a transparent native `NSComboBox` for editing, keyboard, and
  accessibility semantics while owning the visible surface.
- Its geometry follows the WinUI 3 template: 32pt minimum height, filled background, 1pt base
  border, a 38pt trailing glyph column, a `Margin=-4` focused highlight with 2pt border and 7pt
  radius, and a leading 3 x 16 focus Pill.
- Application-owned ComboBox options use a selected-item Pill rather than a menu checkmark; the
  pressed state compresses that Pill to 62.5% over 167ms.
- Validation checks the layer identity, exact geometry, focus highlight, popup ownership, and
  source-derived motion. CalendarDatePicker closed-state chrome is complete; NumberBox and the
  native calendar-grid visual boundary remain follow-up work.

### P1-8: Control state animations can be overwritten by layout - resolved for rebuilt controls

Original finding: Toggle geometry was changed in an animated transaction before a layout pass wrote
the same geometry with actions disabled. The rewritten ToggleSwitch, Slider, CheckBox, and
RadioButton now skip same-bounds geometry work and only cancel/snap-resolve animation when bounds or
layout direction actually changes. SegmentedControl and other audited controls retain their own
layout/animation conflicts.

Required correction:

- Separate model geometry from presentation animation.
- Do not rewrite animated layer properties in the next nonanimated layout pass unless bounds actually changed.
- On resize, sample or cancel the current animation deliberately and continue from a defined state.

### P2-2: Theme colors are approximations rather than generated resources

Many surfaces use manually chosen calibrated colors and alpha values. This creates a generally gray, washed hierarchy and makes state differences subtle.

Required correction:

- Parse or transcribe relevant WinUI resource keys into semantic Swift tokens.
- Keep Liquid Glass material tokens separate from WinUI opaque fill tokens.
- Define Light, Dark, High Contrast, Disabled, PointerOver, Pressed, and Selected variants centrally.
- Prevent components from inventing their own opacity values.

### P2-3: Metrics are globally scaled approximations

Spacing, control height, corner radius, card radius, and navigation width are derived from a small handcrafted token set. This is useful infrastructure but insufficient for exact control fidelity.

Required correction:

- Add component-specific metrics sourced from WinUI theme resources.
- Avoid multiplying corner radii blindly with density.
- Keep macOS-specific hit target adjustments separate from visible WinUI geometry.

## 9. Motion System Audit

### P1-9: Two timing systems coexist

WinUI-derived motion tokens exist, but the default rendering context still uses Core Animation's generic `easeInEaseOut`. Components also choose local curves and durations.

Impact:

- Similar state changes feel unrelated.
- Page, control, navigation, and popup motion have inconsistent acceleration.
- Correct tokens can be bypassed accidentally.

Required correction:

- Make semantic motion tokens the only public default path.
- Group tokens by interaction: control state, navigation, connected animation, popup/menu, teaching tip, dialog, and emphasis.
- Require explicit exceptions rather than component-local raw durations.

### P1-10: Connected and Gravity motion are incomplete

The token layer contains default/direct/gravity-related values, but the connected-animation service lifecycle and full Gravity keyframe algorithm are not yet represented.

Required implementation:

- Source/target registration by stable identity.
- Snapshot or overlay hosting when source and target do not coexist.
- Old/new frame capture in one coordinate system.
- Direct and Gravity configurations.
- Coordinated elements.
- Interruption, cancellation, timeout, and cleanup.
- Gravity peak at the WinUI source phase with separate in/out curves, Y/Z displacement, scale, and shadow behavior.

### P1-11: Transition cleanup uses timers rather than animation completion - resolved

The transition host removes old content using a timer based on expected duration. Timers can drift from actual presentation completion during run-loop pressure, Reduce Motion changes, cancellation, or nested animations.

Required correction:

- Use animation completion callbacks or a transaction completion contract.
- Make cancellation idempotent.
- Remove old content exactly once.
- Clear transforms, opacity, shadows, and overlays on every exit path.

This area is a likely source of genuine stale-view ghosting once page transitions are enabled, even though the supplied menu screenshot is primarily material transparency.

Current status: complete. `FluentTransitionHost` installs a Core Animation completion delegate,
guards cleanup by transition generation, cancels superseded work, resets matched-geometry transforms
and shadows, and retains a dispatch fallback only for non-presenting validation environments.

### P2-4: Gallery motion-system coverage - partially resolved

The Motion page contains local examples, but primary workflows do not demonstrate page navigation, popup placement, menu hierarchy, selection movement, dialog presentation, and connected transitions together.

Required correction:

- Add representative motion to normal Gallery workflows.
- Keep a dedicated diagnostics page for replay, slow motion, reduced motion, and interruption testing.

Current status: navigation selection, page replacement, adaptive pane motion, Top overflow, menus,
and TeachingTip are reachable through normal Gallery workflows. Deterministic replay/slow-motion
diagnostics and connected-animation workflow coverage remain open.

## 10. Liquid Glass Surface Requirements

The Liquid Glass renderer should be a reusable surface abstraction rather than a renamed Acrylic enum case.

Required inputs:

- Surface role: menu, teaching tip, popover, dialog, navigation, toolbar, transient overlay.
- Color scheme and contrast.
- Window active state.
- Corner radius and shape.
- Elevation/shadow role.
- Placement edge and motion origin.
- Fallback capability.

Required rendering responsibilities:

- Native glass/backdrop effect where available.
- Stable tint and saturation control.
- Edge highlight and inner stroke.
- Shadow/elevation.
- Content legibility layer.
- Clipping and corner continuity.
- Active/inactive transition.
- Motion-safe opacity/highlight/shadow animation.

Liquid Glass must not allow background text to appear as a readable duplicate under foreground text. Glass character should come from material response and edge behavior, not uncontrolled low alpha.

## 11. Gallery-Specific Corrections

The Gallery must become a verification application rather than a loose component showcase.

Required changes:

1. **Complete:** use the reusable navigation component instead of Gallery-specific navigation drawing.
2. **Complete:** add a stable page transition host keyed by page identity.
3. Demonstrate every visual state for every core control.
4. Provide light, dark, increased-contrast, and Reduce Motion modes.
5. Include popup/menu placement near every screen edge.
6. Include rapid interaction and interruption scenarios.
7. **Complete:** remove explanatory labels such as "Native macOS rendering" when they distract from the target visual comparison.
8. Keep component examples aligned to a consistent grid and width system.
9. Add WinUI reference captures beside automated Gallery captures outside the shipping UI.

## 12. Prioritized Remediation Plan

### Phase 1: Rendering correctness

1. **Complete:** fix list/indicator coordinate conversion.
2. **Complete for page/navigation; popup placement remains:** establish stable page and popup hosts.
3. **Complete for page/navigation:** replace timer-only cleanup with completion-driven cleanup.
4. **Complete for page/navigation:** add interruption and cancellation handling.

### Phase 2: Surface architecture

5. Implement the Liquid Glass renderer.
6. Migrate MenuFlyout, TeachingTip, Popover, and overlays.
7. Centralize edge, border, shadow, and contrast ownership.

### Phase 3: Navigation fidelity

8. **Complete:** implement reusable NavigationView visual states.
9. **Complete:** rewrite the selection indicator using the WinUI two-indicator algorithm.
10. **Complete:** add pane open/close and page transition choreography.

### Phase 4: Core control fidelity

11. Normalize motion token consumption.
12. Fix animated geometry/layout conflicts.
13. Replace incompatible native chrome on core inputs.
14. Generate semantic visual tokens from WinUI resources.

### Phase 5: Verification

15. Add deterministic screenshot scenarios.
16. Add animation frame capture at defined normalized times.
17. Test light/dark/high contrast/reduced motion.
18. Test resize, scrolling, rapid selection, popup flipping, cancellation, and window deactivation.

## 13. Verification Matrix

Each audited component should pass:

| Area | Required checks |
|---|---|
| Geometry | 1x/2x scale, resize, scroll, flipped coordinates, edge placement |
| States | normal, hover, pressed, selected, focused, disabled |
| Themes | light, dark, increased contrast, inactive window |
| Motion | start, midpoint, end, rapid repeat, cancellation, Reduce Motion |
| Material | legibility, edge highlight, shadow, background response, fallback |
| Accessibility | keyboard, focus order, VoiceOver role/value/action |
| Performance | no stale views, no retained panels, no layout thrash, stable frame pacing |

## 14. Definition of Visual Completion

The Gallery should be considered visually complete only when:

- Core components are recognizable as WinUI 3 without relying on labels.
- AppKit behavior remains intact but incompatible native chrome is not visible.
- Navigation selection and page changes reproduce the intended WinUI state sequence and motion character.
- Transient surfaces consistently use Liquid Glass and remain legible.
- No indicator, overlay, shadow, or old page remains in an incorrect coordinate or lifecycle state.
- Motion parameters are traceable to WinUI source or to an explicitly documented macOS Liquid Glass adaptation.
- Automated screenshots and keyframe captures pass across supported appearances and window sizes.

## 15. Final Assessment

FluentKit now has stable shell coordinates, transition hosting, reusable navigation choreography, and
custom title-bar integration. The Gallery is a reliable proof of those structural paths, but it is
not yet a complete proof of WinUI control fidelity. ToggleSwitch, Slider, CheckBox, RadioButton,
SegmentedControl, and ProgressBar now pass their source-derived geometry, interaction, motion, RTL,
accessibility, and Reduce Motion contracts. The immediate non-material work is the long-tail control
set and transient placement/motion acceptance.
The obsolete Acrylic surface path remains an explicit later phase.

The target architecture should remain AppKit-native in behavior while becoming WinUI-source-driven in visible state and motion, with Liquid Glass as the macOS material adaptation for transient surfaces.

## 16. Follow-up Ownership Findings

The screenshot review identifies four additional issues and clarifies ownership. These are not one common Gallery bug.

### P0-4: Divider orientation is missing - resolved

Owner: FluentKit layout component  
File: `Sources/FluentKit/FluentContainers.swift`, `FluentDivider`

`FluentDivider` always creates a one-point-high view. When inserted into the Gallery's horizontal root `FluentHStack`, it has no fixed width and becomes the flexible consumer of the stack's remaining width. This produces the large empty center region and the long one-point horizontal line visible in the screenshot.

Required correction:

- Make divider orientation explicit, or derive it from the containing stack.
- Horizontal divider: flexible width, fixed height.
- Vertical divider: fixed width, flexible height.
- Do not rely on an unconstrained `NSStackView` arranged subview to infer orientation.

Current status: complete through explicit horizontal/vertical APIs and Gallery/validation coverage.

### P1-12: Gallery duplicates the page title - resolved

Owner: Gallery composition  
Files: `Sources/FluentGallery/main.swift`, `GalleryNavigationShell` and `collectionsPage`

The shell renders a header containing `page.title`, while each page also renders its own `pageHeading`. The Collections screenshot therefore shows two independent titles.

Required correction:

- Choose one title owner.
- Prefer a NavigationView/Header contract: the shell owns the page title and page content owns only its local section headings.
- Do not remove titles by visual hiding; define the hierarchy explicitly so accessibility exposes one page title.

Current status: complete. The shell owns the page title and page bodies own only section headings.

### P1-13: Collection content is constrained below its required extent - resolved for Gallery

Owner: Gallery sizing, with a component clipping contract to verify  
File: `Sources/FluentGallery/main.swift`, `collectionsPage`

The Gallery fixes the collection surface at `220pt`, while two section headers, item rows, spacing, and the following explanatory text require more vertical space. The result is content visually reaching into the following caption or being clipped at the wrong boundary.

Required correction:

- Decide whether the example is a fixed viewport with scrolling or an intrinsic collection preview.
- If it is a viewport, the collection owns scrolling and clips strictly to its bounds.
- If it is an intrinsic preview, derive height from layout content and place the caption after the measured result.
- Add a test for section headers and the last row at the lower edge.

Current status: Gallery uses a 360pt collection viewport that exposes both audited sections without
overlapping the following caption. A general intrinsic collection-sizing API remains separate work.

### P1-14: NavigationView and TitleBar capabilities - resolved

Owner: FluentKit capability plus Gallery integration

Original finding: WinUI 3 NavigationView exposes `Auto`, `Left`, `Top`, `LeftCompact`, and
`LeftMinimal` pane modes, together with bound pane state, toggle visibility, pane lengths, and
responsive thresholds. Gallery originally used a fixed-width stack/list and only exposed the
separate two-column `FluentNavigationSplitView` capability.

Original finding: WinUI 3 TitleBar also supports a compact/expanded height model, pane toggle, back
button, icon, title, subtitle, left header, centered content, and right header. Gallery originally
used an independent AppKit title bar and FluentKit did not expose that reusable capability.

Required correction:

- Add a reusable `FluentNavigationView` capability with expanded, compact, minimal/overlay, and optional top modes.
- Add a reusable `FluentTitleBar` capability with compact/expanded layout and drag-region ownership.
- Keep AppKit traffic lights, window controls, keyboard behavior, and accessibility semantics native underneath the visual layer.
- Refactor Gallery to consume those components instead of manually composing a fixed sidebar and independent title header.

Current status: complete. `FluentNavigationView` implements all listed pane modes and bindings.
`FluentTitleBar` implements compact/expanded geometry, pane/back controls, icon/title/subtitle,
left/center/right slots, drag-region behavior, RTL/inactive states, native title synchronization,
and reversible full-size chrome integration. Gallery composes the two components around one pane
binding and disables the NavigationView's internal toggle.

### Ownership summary

```text
FluentKit component defects:
  collection intrinsic-size contract
  exact core-control state geometry and motion
  Liquid Glass surface and motion ownership

Gallery composition defects:
  deterministic motion diagnostics remain incomplete
  edge-placement popup scenarios remain incomplete
```

The next non-material remediation item is the long-tail control set and MenuFlyout placement/motion.
Liquid Glass remains explicitly deferred until layout, state, and motion are stable.

## 17. Menu Inventory and Gaps

Menus are present in the project, but they were previously grouped under the broader popup/command category rather than counted as a separate component family.

### Existing menu APIs

| API | Role | Current implementation |
|---|---|---|
| `FluentMenuItem` | Declarative item model | Title, enabled state, check state, shortcut, submenu, action |
| `FluentMenuFlyout` | In-app popup menu | Custom borderless `NSPanel` and custom item presenter |
| `FluentDropDownButton` | Chevron button-triggered menu | Owns the trigger state and opens a `FluentMenuFlyout` relative to the button |
| `FluentMenuButton` | Compatibility alias | Deprecated alias for `FluentDropDownButton` |
| `FluentContextMenuView` | Context menu modifier/view | Opens a `FluentMenuFlyout` at the pointer location |
| `FluentCommandsView` | Declarative command integration | Connects command data to application/menu behavior |
| `FluentMainMenuCoordinator` | macOS main menu | Native `NSMenu`, retained for AppKit behavior |

Relevant files:

- `Sources/FluentKit/FluentMenus.swift`
- `Sources/FluentKit/FluentCommands.swift`

### Menu gaps

The current implementation does not yet expose a complete WinUI-style menu hierarchy:

- No explicit public `FluentMenu` container.
- No public `FluentMenuBar` or top-level in-app menu bar.
- MenuFlyout and ContextMenu share one presenter even though their placement and invocation semantics differ.
- Menu item visuals do not have a full icon/content/accelerator slot model.
- Menu placement is based on mixed local, window, and screen coordinates.
- Menu motion reuses TeachingTip tokens rather than a menu-specific specification.
- Menu surfaces still use the rejected Acrylic path and must migrate to Liquid Glass.
- Native main menu and in-app MenuFlyout are intentionally different systems, but this distinction is not yet reflected in a unified public API/documentation model.

The menu family should therefore be counted separately in the component plan. It currently contains six relevant public APIs, with three major visual components requiring focused work: MenuFlyout, ContextMenu, and the menu-triggering control. A complete target family should additionally define `FluentMenu` and, where needed, `FluentMenuBar`.

### WinUI MenuFlyout motion specification

WinUI does not open a menu with a generic two-axis scale-and-fade animation. It uses the dedicated internal `MenuPopupThemeTransition`, which reveals the menu vertically from the edge nearest its placement anchor.

Source locations:

- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/LayoutTransition_partial.cpp`, `MenuPopupThemeTransition::CreateStoryboardImpl`
- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/MenuPopupThemeTransition_Partial.h`
- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/MenuFlyout_Partial.cpp`, `PreparePopupTheme`
- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/MenuFlyoutSubItem_Partial.cpp`, submenu transition setup

Verified parameters and behavior:

- Root MenuFlyout uses `ClosedRatio = 0.5`. Its border begins at `scaleY = 0.5` and expands to `1.0`.
- A submenu uses `ClosedRatio = 0.67`. Its border begins at `scaleY = 0.33` and expands to `1.0`.
- Open duration is `250 ms`.
- Open easing is cubic Bezier `(0,0,0,1)`.
- Opening animates clip translation, content translation, and border Y scale together. It does not scale the menu in X.
- Direction is placement-aware. A menu placed below its target reveals downward from its top edge; a menu placed above the target reverses the animation and reveals upward from its bottom edge.
- Closing is not the opening animation played backward. The menu fades from opacity `1` to `0` linearly over `83 ms` while preserving an interrupted opening clip if dismissal occurs mid-transition.
- An associated light-dismiss overlay, when present, fades linearly over `83 ms`.
- Menu-item `Normal`, `PointerOver`, `Pressed`, `Disabled`, and `SubMenuOpened` states primarily switch semantic brushes immediately. The template does not stagger menu-item entrance animations.
- WinUI can skip open/close motion through `AreOpenCloseAnimationsEnabled`. FluentKit additionally
  adopts the project requirement that application flyouts always disappear immediately.

The intended visual result is therefore a fast anchored reveal: the attachment edge remains visually stable while the remaining menu height is uncovered. It should not look like a floating card zooming toward the viewer.

Current FluentKit status:

- `FluentMotion.menuOpen` and `submenuOpen` provide the dedicated entrance timing contract.
- `FluentMenuFlyout` resolves final screen placement before selecting a top- or bottom-edge reveal.
- Root and submenu presenters move by 0.5 and 0.67 of their opened height, their clips move by the
  exact inverse amount, and their borders begin at scale 0.5 and 0.33.
- Close does not run the WinUI unload storyboard; the panel is removed synchronously per the current
  FluentKit visual contract.
- Submenu hover delay remains a separate interaction policy.
- The deferred Liquid Glass migration remains open; this pass changes motion only.

## 18. Consolidated Problem List

### Rendering and layout

1. **Resolved:** `FluentDivider` has explicit horizontal and vertical contracts.
2. **Resolved:** `FluentList` converts collection layout coordinates before positioning CALayers.
3. `FluentCollection` examples and Gallery pages use fixed heights without a clear viewport/intrinsic sizing contract.
4. Some animated layer geometry can be overwritten by subsequent nonanimated layout passes.
5. Transient surfaces can have multiple independent border/shadow owners.

### Gallery composition

6. **Resolved:** Gallery page content uses a persistent keyed transition host.
7. **Resolved:** the shell is the single page-title owner.
8. **Resolved:** Gallery uses public `FluentNavigationView` pane modes.
9. **Resolved:** Gallery uses public `FluentTitleBar` above the navigation shell.
10. **Partially resolved:** pane modes and page transitions are normal workflows; comprehensive menu
    edge placement remains open.

### Navigation and window chrome

11. **Resolved:** public `FluentNavigationView` covers Expanded, Compact, Minimal/Overlay, Auto, and Top.
12. **Resolved:** public `FluentTitleBar` covers compact/expanded height and all audited content slots.
13. **Implemented, awaiting pixel acceptance:** navigation rows own selected/hover/pressed/focus/disabled states.
14. **Resolved:** reusable NavigationView covers vertical primary/footer and horizontal Top indicator paths.

### Menus and transient surfaces

15. Existing MenuFlyout uses Acrylic, contrary to the Liquid Glass direction.
16. Menu transparency permits readable background content and creates the reported ghosting.
17. Menu positioning does not have explicit placement modes or a stable anchor-rect contract.
18. **Resolved:** MenuFlyout uses placement-aware 250ms root/submenu presenter, inverse-clip, and
    border entrance motion, then dismisses immediately.
19. Menu item content slots are incomplete.
20. There is no explicit public `FluentMenu`/`FluentMenuBar` layer.

### Motion and verification

21. Generic `easeInEaseOut` defaults coexist with WinUI-derived motion tokens.
22. Connected and Gravity animation lifecycles are incomplete.
23. **Resolved for transitions/navigation:** completion-driven cleanup has a deterministic fallback.
24. **Partially resolved:** 14 deterministic responsive screenshots and normalized navigation
    keyframe checks exist; per-core-control keyframe captures remain open.

## 19. Implementation Plan

The plan is intentionally component-oriented. Each component must be inspected against the bundled WinUI source before implementation.

### Phase 0: Establish contracts

1. Define semantic resource/token namespaces for geometry, color, state, motion, surface, and accessibility.
2. Define a shared coordinate-space policy for AppKit views, flipped views, collection layout frames, CALayers, screen frames, and popup anchors.
3. Define Liquid Glass surface roles and fallback behavior.
4. Define the component acceptance harness: light, dark, high contrast, reduced motion, resize, scroll, keyboard, and interruption cases.

### Phase 1: Fix shared geometry

5. **Complete:** make `FluentDivider` orientation explicit.
6. **Complete:** correct `FluentList` indicator coordinate conversion and relayout behavior.
7. Establish collection viewport versus intrinsic-size behavior.
8. Make animated geometry resilient to layout passes and resizing.

### Phase 2: Build shared surface and window chrome

9. Implement `FluentLiquidGlassSurface`.
10. Migrate MenuFlyout, ContextMenu, TeachingTip, Popover, dialogs, and transient overlays from Acrylic to Liquid Glass.
11. **Complete:** implement `FluentTitleBar` with compact/expanded modes and AppKit drag-region integration.
12. **Complete:** verify title-bar content does not conflict with native traffic lights or window controls.

### Phase 3: Implement NavigationView

13. **Complete:** implement Expanded/Left mode.
14. **Complete:** implement LeftCompact mode with icon-only pane.
15. **Complete:** implement LeftMinimal/overlay mode and pane toggle.
16. **Complete:** implement Auto thresholds and Top mode.
17. **Complete structurally, pixel acceptance open:** implement row states and the WinUI indicator algorithm.
18. **Complete:** add pane open/close and selection motion with interruption handling.

### Phase 4: Implement menu family

19. Separate MenuFlyout, ContextMenu, and menu-bar invocation/placement contracts.
20. Add explicit `FluentMenu` and, if required by the application shell, `FluentMenuBar` APIs.
21. Add icon/content/accelerator/submenu slots to `FluentMenuItem`.
22. Implement stable placement modes and edge flipping.
23. Implement menu-specific open, close, hover, pressed, and submenu motion from WinUI resources.
24. Preserve native `NSMenu` for the macOS system main menu.

### Phase 5: Migrate core controls

25. **Complete:** Button and ToggleSwitch foundations; ToggleSwitch includes source-derived
    interaction, geometry, RTL, accessibility, and Reduce Motion verification.
26. **Complete:** Slider, CheckBox, RadioButton, SegmentedControl, and ProgressBar.
27. **Complete structurally/behaviorally:** TextBox, SearchBox, ComboBox, CalendarDatePicker, and
    NumberBox/Stepper; cross-theme popup and native-grid pixel acceptance remains open.
28. ListView, GridView/CollectionView, Table, and Outline.
29. Dialogs, TeachingTip, Popover, Disclosure, and remaining long-tail controls.

### Phase 6: Rebuild Gallery as the verification surface

30. **Complete:** replace the fixed Gallery shell with `FluentNavigationView` and `FluentTitleBar`.
31. **Complete for audited title/collection defects:** remove duplicate page titles and clipping patches.
32. **Complete for page/pane, menu edge cases open:** add visible transitions and normal-workflow demonstrations.
33. Add Liquid Glass, theme, contrast, and Reduce Motion diagnostics.
34. Add screenshots and animation keyframe captures for every primary component.

### Phase 7: Completion gate

35. Compare screenshots against WinUI reference states.
36. Verify no stale indicator, old page, panel, shadow, or transform survives completion/cancellation.
37. Run build, accessibility, keyboard, resize, scrolling, and rapid-interaction checks.
38. Mark a component complete only when appearance, state behavior, motion, and fallback behavior all pass.

## 20. Core Controls Source Audit

The Controls screenshot exposes component-level state and motion gaps. The Gallery uses the public bindings directly and does not apply custom offsets or animation to these controls, so these findings belong to FluentKit rather than Gallery composition.

### Segmented selection - resolved

Owner: FluentKit component
Files: `Sources/FluentKit/FluentSegmentedControl.swift`, `Sources/FluentKit/FluentStyles.swift`

Original finding: the component contained a 250 ms selection-indicator animation, but its
presentation was not reliable:

- `FluentSegmentedControlNative` remains an `NSSegmentedControl` with native labels and selection state while also overlaying custom labels and a custom `selectionIndicatorView`.
- Every declarative update assigns theme/style again, rebuilds all overlay labels, and performs another indicator synchronization.
- `layout()` always calls `updateSelectionIndicator(animated: false)`, so a layout or state reconciliation during the 250 ms transition can replace the animated geometry with its final frame.
- The custom animation adds arbitrary scale and opacity keyframes (`1 -> 0.94 -> 1`, `1 -> 0.78 -> 1`) that are not sourced from the WinUI selection-control templates.

Required correction:

- Use one visual owner: retain AppKit interaction/semantics but suppress native segment chrome, or replace the native cell presenter with a dedicated AppKit container.
- Keep stable label and indicator objects across declarative updates.
- Separate model geometry from presentation geometry and do not write nonanimated frames while a transition is active.
- Derive the selected/pressed transition from the matching WinUI control template instead of treating the current approximation as verified WinUI motion.

Current status: complete. FluentKit deliberately keeps `NSSegmentedControl` as the semantic/input
surface, but its overridden renderer does not call the native cell drawing path; FluentKit owns the
visible background, border, labels, focus, interaction fills, and selection surface. Compatible
updates mutate stable label objects in place. Selection stores final model geometry and animates
position from the current presentation frame using FluentKit's compact-selection transition; it is
not presented as a WinUI SelectorBar implementation. The previous unsourced scale and opacity
keyframes are removed. Same-bounds
layout preserves active motion, while resize and direction changes explicitly snap. Pointer commit,
release-outside/Escape/external cancellation, disabled state, RTL layout/hit testing/arrow keys,
accessibility value, Reduce Motion, Gallery states, and desktop/Minimal Light/Dark captures have
executable coverage. WinUI does not expose a literal SegmentedControl counterpart in the bundled
source; this remains a FluentKit compact-selection API rather than a compatibility claim.

### SelectorBar - resolved

Owner: FluentKit component
Files: `Sources/FluentKit/FluentSelectorBar.swift`, `Sources/FluentGallery/main.swift`

Current status: complete. Page and view switching now uses a dedicated AppKit-native SelectorBar
rather than repurposing `NSSegmentedControl`. The implementation follows the bundled WinUI
`SelectorBar_perf2026.xaml` and theme resources: transparent item surfaces, `0,4` bar padding,
`12,10,12,7` item padding, 8pt icon/text spacing, 0.8 icon scale, and an independent 4 x 3 pill per
item. Selecting an item animates only that item's pill to 4x horizontal scale and full opacity over
167ms with `(0,0,0,1)`; there is no shared sliding indicator. It supports stable item identity,
optional selection, disabled-item skipping, direct arrow-key selection, RTL visual order,
radio-group accessibility semantics, and Reduce Motion snapping. Collections Gallery Light/Dark
baselines and executable component checks cover the visual and behavioral contract.

### Slider thumb - resolved

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentSlider.swift`, `Sources/FluentKit/FluentStyles.swift`

The circle at the end of the upper range track is the Slider thumb; the lower `FluentProgressBar` has no thumb. WinUI defines the thumb as an 18 x 18 outer circle containing a 12 x 12 accent inner circle. Its inner circle transitions through separate visual states:

- Normal: 12 px visual size (`0.86` relative scale in the template), returning over 167 ms.
- PointerOver: 14 px (`1.167` relative scale), over 250 ms.
- Pressed: 10 px (`0.71` relative scale), over 250 ms.
- Curve: `ControlFastOutSlowInKeySpline`, `(0,0,0,1)`.

Source: `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/CommonStyles/Slider_themeresources.xaml`, especially the `SliderThumbStyle` CommonStates.

Original finding: FluentKit drew one 14 px accent circle and showed a larger translucent halo for
hover/drag. It redrew immediately and had no animatable outer/inner thumb layers, so it could not
reproduce the WinUI pressed contraction or hover expansion.

Required correction:

- Build a stable outer thumb layer and inner accent layer.
- Animate only the inner-circle geometry using the WinUI state values and motion tokens; apply the
  template's state brushes immediately.
- Keep drag position animation separate from thumb-state animation so pointer motion remains direct while the pressed visual remains interpolated.

Current status: complete. `FluentSlider` uses stable named track, value-fill, outer-thumb,
inner-thumb, and focus layers. The visible geometry is a 4pt track, 18 x 18 outer thumb, and
12/14/10/14 inner thumb for Normal/PointerOver/Pressed/Disabled. Only inner bounds and corner radius
animate with the source-derived 167ms/250ms cubic-bezier tokens; pointer position remains direct.
Same-bounds layout, external binding updates during drag, Escape cancellation, RTL pointer and arrow
direction, Home/End, accessibility increments, disabled input, and Reduce Motion are covered by the
validation executable and desktop/Minimal Light/Dark Gallery captures.

### ToggleSwitch pressed and dragging states - resolved

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentToggle.swift`, `Sources/FluentKit/FluentStyles.swift`

WinUI explicitly separates interaction state from logical value. Its template has `Normal`, `PointerOver`, `Pressed`, and `Disabled` common states, plus `Dragging`, `Off`, and `On` toggle states and dedicated `DraggingToOn`, `OnToDragging`, and `DraggingToOff` transitions. The 40 x 20 track uses a 12 x 12 normal knob, a 14 x 14 hover knob, and a 17 x 14 pressed knob. State-size changes use the 83 ms faster token and `(0,0,0,1)` curve; drag release uses reposition transitions and resolves to the final On or Off state.

Source: `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/CommonStyles/ToggleSwitch_themeresources_perf2026.xaml`.

Original FluentKit divergence:

- `mouseDown` sets pressed and immediately toggles `isOn`; therefore there is no pressed-without-commit state.
- Pressed is cleared by an 83 ms timer rather than by pointer release/cancel.
- There is no `mouseDragged` or drag position.
- `refreshAppearance` animates layer frames and then requests layout; `layout()` writes the same frames with actions disabled, which can suppress or interrupt the visible transition.

Required correction:

- Track `idle`, `pressed`, and `dragging` interaction states independently from the committed Boolean value.
- On pointer down, preserve the current On/Off value and show the 17 x 14 pressed knob.
- During drag, move the knob continuously within the track while retaining only two commit outcomes: On or Off.
- On release/cancel, resolve by the midpoint/gesture direction and animate from the current presentation position to the selected endpoint.
- Commit the binding exactly once after resolution, not on pointer down.

Current status: complete. The implementation uses stable named track, knob, and focus layers; exact
40 x 20 and 12/14/17 x 14 model geometry; explicit 83ms cubic-bezier animations; direct drag
positioning; directional/midpoint release; release-outside and Escape cancellation; external binding
arbitration; one callback per committed change; RTL endpoint mirroring; accessibility press; and
Reduce Motion snapping. A same-bounds layout call is explicitly verified not to remove the active
knob animation.

### CheckBox and RadioButton selection motion - resolved

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentChoiceControls.swift`, `Sources/FluentKit/FluentStyles.swift`

Original finding: both controls mutated their Boolean state in `mouseDown` and immediately redrew.
Their style configurations did not contain a pressed state; RadioButton did not expose pointer-over
state. Consequently the selected glyphs had no WinUI visual-state transition.

Required correction:

- Add independent pointer-over, pressed, checked/unchecked or selected/unselected states.
- Commit on pointer release inside the control and cancel when released outside.
- Give the check mark and radio inner dot stable presentation layers so their size/opacity can animate with WinUI's 83/167/250 ms state tokens.

Current status: complete. CheckBox owns stable box/check/focus layers and commits only on
release-inside. Its shape-layer stroke follows the source AnimatedAccept marker contract: 19 frames
to reveal with `(0.55,0,0,1)` and four frames to clear with
`(0.167,0.167,0.833,0.833)`. RadioButton owns stable 20pt outer, selected-dot,
pressed-feedback, and focus layers; its dot uses 12/14/10/14 geometry for
Normal/PointerOver/Pressed/Disabled with 250ms/167ms source motion. Both controls preserve active
motion across same-bounds declarative updates and cover release-outside, Escape/external-binding
cancellation, RTL, keyboard, accessibility, disabled, Reduce Motion, and Gallery Light/Dark states.

### ProgressBar - resolved

Owner: FluentKit component  
File: `Sources/FluentKit/FluentProgressBar.swift`

The lower horizontal control is a determinate ProgressBar and should not receive a Slider thumb.
ProgressBar now owns a stable CALayer tree (`Track`, `Determinate`, `Indeterminate.Primary`, and
`Indeterminate.Secondary`) instead of an immediate-mode `draw()` path. Determinate values animate
the presentation width over 250ms with the control-normal curve; indeterminate mode uses a 2-second
two-layer keyframe loop, while paused/error states stop the loop and settle the visible indicator.
The visual state transition is coordinated by `FluentVisualStateCoordinator`, with RTL fill direction,
Reduce Motion snapping, high-contrast geometry, and accessibility value/help coverage in the
validation executable.

### ComboBox template fidelity - partial

Owner: FluentKit component and Gallery Inputs page
Files: `Sources/FluentKit/FluentInputControls.swift`, `Sources/FluentKit/FluentMenus.swift`,
`Sources/FluentGallery/main.swift`

The original Gallery used an underline style for ComboBox, which contradicted the WinUI 3 default
template. The Inputs page now uses a fixed top-aligned two-column layout with 280 x 32 control
slots, and ComboBox uses the automatic filled field appearance. The host renders the source-derived
focus highlight and focus/selected Pills while retaining native input semantics. Full transient
flyout visual parity, CalendarDatePicker's native calendar-grid boundary, and NumberBox rendering
remain separate acceptance items.

### Additional problem-list entries

25. **Resolved:** SegmentedControl has one Fluent visual owner, stable labels/indicator, presentation-
    sampled 167ms selection motion, and same-bounds animation protection.
26. **Resolved:** Slider has stable outer/inner thumb layers, direct value positioning, and
    source-derived Normal/PointerOver/Pressed/Disabled geometry and motion.
27. **Resolved:** ToggleSwitch commits on release, has a direct drag state, and protects active
    animations from same-bounds layout.
28. **Resolved:** CheckBox and RadioButton have independent pressed state, release-inside commit,
    stable glyph layers, and source-derived selected-glyph motion.
29. **Resolved:** ProgressBar uses a stable visual layer tree, presentation-sampled determinate
    width motion, a coordinated indeterminate loop, paused/error states, RTL, Reduce Motion, and
    accessibility coverage.
30. **Partial:** ComboBox uses a Fluent-owned filled surface over native semantics, source-derived
    focus/selection Pills and focus highlight geometry, and 167ms pressed compression; flyout and
    remaining input-family visual acceptance remain open.

## NavigationView-Owned Page Transition Pass - 2026-07-20

Owner: `FluentNavigationView` / shared animation execution layer
Files: `Sources/FluentKit/FluentNavigationTransition.swift`,
`Sources/FluentKit/FluentAnimationCoordinator.swift`, `Sources/FluentKit/FluentLayerAnimator.swift`

The Gallery no longer keys and wraps its page content in a private transition host. NavigationView
now retains the outgoing and incoming destination entries itself and exposes automatic, none,
cross-fade, slide, drill-in, entrance, and suppress policies. Automatic mode follows the bundled
NavigationView source: ordered Top destinations use directional Slide, while left/footer/default
navigation uses Entrance.

The structural timelines map the bundled transition sources rather than a generic 250ms ease:

- Slide uses a 150pt outgoing offset over 150ms, followed by a delayed 200pt incoming offset over
  300ms with `(0.1,0.9,0.2,1)`; LTR/RTL and forward/backward directions are mirrored.
- Entrance uses the source 140pt vertical offset, 150ms outgoing phase, and delayed 300ms incoming
  phase.
- DrillIn uses the source 0.94/1.04 forward and 1.06/0.96 backward scale factors with the
  100ms/333ms/783ms property durations and dedicated opacity curves.
- Suppress and Reduce Motion allocate no page animation and replace immediately.

The per-NavigationView coordinator samples active presentation values before keyed replacement, so
rapid selection changes continue from the visible frame. The old native page is removed at the end
of the 150ms outgoing phase while the incoming phase continues; the final completion removes all
stale entries. Executable validation covers simultaneous old/new retention, forward/back direction,
explicit opacity/transform animations, outgoing and final cleanup, rapid selection, Reduce Motion,
Suppress, and coexistence with the 600ms selection indicator. Light Entrance and Dark Top Slide
presentation captures were visually checked without page overlap, clipping, or residual content.

## Text Selection Performance Pass - 2026-07-20

Owner: `FluentRichTextEditor` and native TextControl editor bridge
Files: `Sources/FluentKit/FluentRichTextEditor.swift`,
`Sources/FluentKit/FluentTextEditing.swift`, `Sources/FluentKit/FluentTextField.swift`,
`Sources/FluentKit/FluentInputControls.swift`

Rapid selection previously had a feedback queue: every local `NSTextView` selection callback wrote
the binding, and the editor's own binding observer scheduled that same range back to the text view.
During a drag this replayed stale ranges on the main thread and could make the editor appear frozen.
The observer now ignores local publications and coalesces genuine external selection changes to the
latest value per RunLoop turn. Applying an already-visible range is a no-op, so AppKit remains the
owner of mouse selection, caret, IME, undo, and clipboard behavior.

Single-line TextBox, SearchBox, PasswordBox, and editable ComboBox fields also no longer rewrite
equal text colors, fonts, selected-text attributes, typing attributes, or themes from their drawing
path. The validation executable covers 1,000 duplicate selection callbacks and 250 rapid drag ranges;
the final selected range remains stable without queued local replay. Strict warning-free build and
the full validation executable pass after this change.

## Popup Direction Geometry Pass - 2026-07-20

Owner: `FluentPopupTransitionHost`, `FluentMenuFlyout`, and generic `FluentTransitionHost`
Files: `Sources/FluentKit/FluentPopupTransitions.swift`, `Sources/FluentKit/FluentMenus.swift`,
`Sources/FluentKit/FluentAnimation.swift`

MenuPopupThemeTransition now uses one logical direction model. A popup opening from the top edge
uses a negative root translation and an equal positive clip translation; the bottom edge is the
strict inverse. The border surface uses the source `CenterY = OpenedLength` behavior: the top-edge
path applies the equivalent `m42` compensation while the bottom-edge path does not. A fixed clip
host contains a separate animation root, and the inverse clip belongs to that root, so presenter
content cannot move outside the popup surface during the entrance. Dismissal remains immediate;
only the entrance storyboard is animated.

The generic move transition converts the logical Top/Bottom edge at the transition entry according
to the actual flipped state of the transition entry. It no longer assumes that every host uses the
unflipped AppKit coordinate system. MenuFlyout submenu placement also inherits the resolved parent
FlowDirection, which keeps RTL submenus on the leading side.

Validation now exercises below-anchor and above-anchor MenuFlyout entrances, inverse root/clip
values, edge-anchored border geometry, LTR/RTL submenu placement, flipped generic transitions,
and immediate dismissal. DropDownButton trigger-state animation remains a separate concern from
the independent MenuFlyout presenter transition.

## DropDownButton / MenuFlyout Contract Pass - 2026-07-20

Owner: `FluentDropDownButton`, `FluentButton`, and `FluentMenuFlyout`
Files: `Sources/FluentKit/FluentList.swift`, `Sources/FluentKit/FluentButton.swift`,
`Sources/FluentKit/FluentMenus.swift`

The chevron trigger is now named after its WinUI control instead of being exposed as the misleading
`FluentMenuButton` implementation name. `FluentMenuButton` remains only as a deprecated source
compatibility alias. A regular `FluentButton` continues to expose the separate attached flyout path,
while `FluentDropDownButton` owns the chevron, pressed/released trigger state, open-state
automation value, and a `FluentMenuFlyout` presenter.

This matches the bundled WinUI contract: `DropDownButton` observes `Button.Flyout` Opened/Closed
events, but does not replace the flyout's presenter transition. When that flyout is a MenuFlyout,
the presenter still uses `MenuPopupThemeTransition`; only the trigger visual and automation state
belong to DropDownButton. Validation covers equal-theme updates during chevron motion, release-to-
open, immediate toggle dismissal, open-state accessibility, and the existing regular Button.Flyout
path.

## MenuFlyout Slot and TextCommand Expansion Pass - 2026-07-20

Owner: `FluentMenuItem`, `FluentMenuPresenterView`, and `FluentTextCommandFlyout`
Files: `Sources/FluentKit/FluentMenus.swift`, `Sources/FluentKit/FluentTextCommandFlyout.swift`

`MenuFlyout_themeresources_perf2026.xaml` defines mouse/keyboard NarrowPadding as `11,4,11,5`,
with independent 28pt check and icon placeholders. FluentKit now computes those placeholders once
for the complete presenter, keeps every row aligned, draws a 16pt SF Symbol in the icon slot, and
keeps accelerator and submenu-chevron columns on the logical trailing edge. Check and icon slots
move to the right in RTL; non-directional check and icon glyphs do not mirror. The same declarative
system image is forwarded when a `FluentMenuItem` is consumed by the native `NSMenu` boundary.

The source confirms that mouse TextCommandBarFlyout invocation places Cut/Copy/Paste in secondary
commands. FluentKit preserves that secondary-only mouse path. For input devices that prefer primary
commands, Cut/Copy/Paste occupy 40pt icon slots and More reveals the secondary list. More now commits
the expanded panel geometry synchronously and applies the source 250ms ControlNormal clip from the
primary bar edge; the complete flyout still dismisses immediately. Validation covers both command
compositions, expansion geometry and animation, LTR/RTL menu slots, accessibility accelerators, and
Light/Dark 194 x 121 MenuFlyout bitmap baselines.

## MenuFlyout High Contrast and Public CommandBarFlyout Pass - 2026-07-20

Owner: `FluentTheme`, `FluentMenuItemRow`, `FluentCommandBarFlyout`, and `FluentButton`
Files: `Sources/FluentKit/Theme.swift`, `Sources/FluentKit/FluentMenus.swift`,
`Sources/FluentKit/FluentTextCommandFlyout.swift`, `Sources/FluentKit/FluentButton.swift`

The bundled MenuFlyout High Contrast dictionary does not reuse generic SubtleFill resources.
PointerOver and Pressed resolve system Highlight plus HighlightText, Disabled resolves GrayText,
normal accelerator text resolves WindowText, and the presenter retains its 2pt WindowText border.
FluentKit now keeps those resources menu-specific and applies one resolved state to title, check,
icon, accelerator, and submenu glyphs. Executable assertions cover the semantic mapping, live hover
icon tint, and border; the 194 x 121 high-contrast baseline covers the final background pixels.

The public CommandBarFlyout API mirrors WinUI's PrimaryCommands, SecondaryCommands, and
AlwaysExpanded contract without exposing the internal TextControl command model. Primary commands
use 40pt icon slots with vertical AppBarSeparator geometry and toggle fills; secondary overflow
supports action/toggle rows, independent icon/check placeholders, horizontal separators, and
accelerators. More commits final panel/root/surface/content bounds before running the shared 250ms
ControlNormal clip. Content is a sibling above the Liquid Glass surface, matching the established
popup host hierarchy, so native material cannot cover command pixels. Dismissal remains immediate.

Validation covers builders, item kinds, accessibility state, Liquid Glass, More expansion,
separator orientation, command invocation, immediate cleanup, and AlwaysExpanded. The Gallery uses
the public Button attachment and supplies 141 x 133 Light/Dark expanded bitmap baselines.

## WindowShell State Matrix Pass - 2026-07-21

Owner: `FluentWindowConfiguration`, `FluentWindowShell`, `FluentTitleBar`, and `FluentNavigationView`
Files: `Sources/FluentKit/FluentWindowShell.swift`, `Sources/FluentKit/FluentTitleBar.swift`,
`Sources/FluentKit/FluentNavigationView.swift`

The Shell now exposes Back and pane-header content in addition to its existing title-bar content.
The public configuration resolves native AppKit chrome explicitly: title-bar search is unavailable
under native chrome, and a requested title-bar toggle is moved to vertical navigation so no pane
action disappears. Extended states can omit search, put the toggle in the pane, or put both search
and toggle in the custom title bar. Top navigation suppresses both toggle locations because it has
no collapsible vertical pane.

The TitleBar and NavigationView custom buttons now implement a direct accessibility press path and
hide unused buttons instead of leaving zero-sized interactive elements in the accessibility tree.
Validation mounts and switches the same window between extended and native Shell states, checks
Back, title-bar/pane toggles, pane-header content, native chrome restoration, search suppression,
Top navigation, Liquid Glass, and clipped ContentSurface geometry. Gallery baselines cover the
reference extended state and native + vertical pane state; existing Minimal and Top baselines cover
the remaining navigation orientations.
