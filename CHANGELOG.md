# Changelog

All notable FluentKit changes are recorded here. Versions follow Semantic Versioning.

## Unreleased

- AutoSuggestBox discards provider results when the query changes during the provider callback,
  preventing stale suggestions from flashing over a newer model value. Enter submission now
  synchronizes a closure binding before resolving the chosen suggestion, so an external reset
  cannot submit new text paired with an obsolete item. Existing external-reset cancellation
  semantics remain unchanged. Evidence: `audits/2026-11-01/autosuggest-focus/REPORT.md`.

- AutoSuggestBox restores the user's query when cancelling a preview whose selected item was
  removed or replaced by a result refresh. Escape also restores after the list closes; Tab only
  restores while it is open, following WinUI's keyboard handler. **Behavior change:** clear/query
  helper buttons are no longer Tab stops and pointer activation keeps editing focus in the field;
  their native actions remain available. See `audits/2026-11-01/autosuggest-cancel/REPORT.md`.

- FluentKit-owned windows and both Galleries now automatically recalculate AppKit's key-view
  loop, allowing Tab to reach controls added by navigation, sheets or detached tabs.
  Explicit focus scopes and ContentDialog preserve keyboard cycles across that recalculation,
  using current stack order after insertion/reordering. Text command delegates, editing validation
  and marked text retain their handling; consumed Tab events also update the input-device tracker.
  Manually owned NSWindow instances still choose their own native key-loop policy. Evidence and
  remaining AutoSuggestBox integration issues: `audits/2026-11-01/gallery-keyboard/REPORT.md`.

- CheckBox and RadioButton now share WinUI HighVisibility focus borders: 2pt outer / 1pt
  inner strokes, -7/-3 margins, corrected stroke placement and corner radii, and explicit-theme
  High Contrast system-color roles. CheckBox replaces its inset accent ring and keeps outside
  focus drawing visible after AppKit reapplies corner-radius clipping. Standard focus remains
  static on press; WinUI FocusPress animation belongs to Reveal mode. Evidence and limits:
  `audits/2026-11-01/choice-focus/REPORT.md`.

- CheckBox now enters Pressed on Space keyDown and commits on keyUp, ignores Return/Enter,
  and supports keypad Add/Subtract like WinUI. CheckBox/RadioButton cancel input on focus loss,
  removal, hiding and window deactivation or disabling, and coordinate combined Space/pointer releases.
  **Behavior change:** same-model value updates preserve an active gesture; release acts on the
  current value through the current binding, including after a binding replacement. Changing
  a binding expression alone does not cancel input; obsolete observer callbacks are isolated.
  Choice bindings update synchronously on main and reject stale subscriptions/values.
  See `audits/2026-11-01/choice-input/REPORT.md` for evidence and remaining limits.

- RadioButton fixes unnamed grouping in ordinary NSView containers and stops merging separate
  single-child containers. The binding adapter remains transparent. **Behavior change:** named
  groups use exact identifiers, including leading/trailing whitespace. Standalone radios and
  the declarative group are exposed to accessibility, with numeric selected values and change
  notifications. Default High Contrast brushes and label colors resolve under the explicit Fluent
  theme, sharing the CheckBox resolver. See `audits/2026-11-01/radio-accessibility/REPORT.md`.

- Default CheckBox styling now follows WinUI's unchecked, checked and indeterminate resource
  matrices, including High Contrast, a 4pt corner radius and a 1pt border. Captured presses
  return to the normal appearance outside the control without losing release/reentry handling.
  High Contrast system colors resolve under the explicit Fluent theme during event updates.
  Standalone CheckBox is exposed to accessibility with a numeric checked value and change
  notifications. Style configuration adds optional `isIndeterminate`; appearance adds an
  optional presenter background. Existing style initializer calls remain valid. TreeView uses
  the mixed-state brushes and clips its presenter background inside the HC row border.
  See `audits/2026-11-01/checkbox-style/REPORT.md` for evidence and remaining limits.

- TreeView accessibility disclosure queries no longer trigger `onExpanding` or lazy loading.
  Expansion events now use the native will-expand notification. **Behavior change:** changes to
  `expandedIDs` after mounting emit expansion/collapse events; initial state and internal reload
  restoration remain silent. `onCollapsed` receives the updated binding state, and requests to
  reopen from that callback are preserved. See `audits/2026-11-01/treeview-expansion/REPORT.md`.

- TreeView checkbox interactions now commit on release inside their target, cancel when moved
  outside or interrupted, and show hover/pressed feedback. Chevron activation remains on press.
  Hit targets include the full WinUI template padding in LTR/RTL; reused or removed rows cannot
  receive a stale checkbox release. See `audits/2026-11-01/treeview-pointer/REPORT.md`.

- TreeView adds `onMoveItems` for atomic checked-subtree reordering, preserving selection order
  and omitting descendants already carried by a selected ancestor. The drag image shows the
  selected-node count. Existing `onMove` stays a single-row callback. Drop validation rejects
  cycles, invalid indices, stale topology and foreign sources; lazy loading may continue a drag
  after the destination is validated again. Gallery applies the whole group in one data update.
  Native outline clicks now reach the drawn checkbox/chevron, and lazy Gallery loading preserves
  nodes already moved into the folder. Physical drag/drop acceptance remains open in the audit.

- Declarative accessibility, focus, lifecycle, form, command, dialog, toolbar and related wrappers
  now forward current content and actions instead of replaying their first mounted value.
  SettingsCard refreshes its saved trailing-action callback for native appearance changes.
  FocusScope releases its host correctly, and combined accessibility labels use updated children.

- ComboBox updates an already-open popup when its host receives a new theme, including native
  AppKit embeddings without an AppearanceCoordinator. The popup stays open with its selection
  intact; temporary transition imagery is settled before repainting.

- FlipView retargets repeated adjacent navigation from its visible viewport and supplies native
  page content with the actual viewport size. At most five pages remain mounted during motion.
  Nonadjacent selection jumps now land directly, matching WinUI's adjacent-transition distinction;
  grabbing an unfinished sequence synchronizes selection to the visible neighborhood before
  single-page manipulation. Rejected or reentrant binding writes cancel the old operation.

- NavigationView preserves the visible frame when a second navigation interrupts an entrance,
  preventing a blank page while the intermediate and destination pages are transparent. Resizing
  settles the current destination and removes temporary snapshots; ordinary transitions keep
  their existing modes and timings.

- AutoSuggestBox suggestions now follow scrolling and moving ancestor views. A fully clipped
  input closes its suggestions; scrolling back does not reopen stale results, and new input
  reopens the popup at the current anchor without moving keyboard focus.

- TextField, SearchBox and SecureField now align their custom chrome with the allocated frame.
  Removing native bezel alignment insets prevents an extra 4pt of width and clipped corners in
  containers. SearchBox and SecureField also refresh placeholder/text appearance immediately
  when disabled or re-enabled.

- SearchBox preserves the native cell’s 2pt text inset when editing, including shared field-editor
  reuse and deferred AppKit setup. Placeholder and entered text no longer shift left on focus.

- SettingsExpander now follows nested expansion, content replacement and width-dependent content
  height instead of freezing its opening height. Temporary animation constraints are released
  when settled, so following rows and scroll extents update together. Expander natural width and
  vertical-stack fill allocation no longer override explicit frames. Gallery's Expander examples
  adapt to narrow page widths instead of forcing a 520pt body beyond the viewport.

- Navigation-history and undo scopes now forward the latest declarative content and action
  captures instead of replaying their first mounted value. Gallery routes can replace the page
  body; compatible native views retain identity and child undo environments remain intact.

- WindowShell's shared chrome tint and cutout mask now commit resize geometry together without
  implicit animations. This removes a separate right/bottom color seam in Gallery window zoom,
  including geometry updates reported by the content surfaces.

- Material backgrounds now resize with their containing view during window zoom. Disabling
  implicit geometry animations prevents the opaque fallback and Mica tint from lagging behind
  the new window bounds and briefly exposing a different color at the right and bottom edges.

- TitleBar back/forward buttons now animate the arrow inward on press and spring back on release,
  with RTL mirroring and reduced-motion support. Pointer release outside cancels; re-entry restores
  the press. Space activates once on key-up, Return ignores repeat, and hidden/disabled controls
  reject programmatic and accessibility presses. Hiding or deactivating clears stale hover/press.

- FlipView yields new outward trackpad gestures at a settled first/last page to enclosing
  responders. Shared pan rejection now replays tentative events in order, preserving the original
  begin phase and deltas for FlipView, Pivot and SwipeControl cross-axis handoff. Unresolved
  jitter has a bounded 32-event buffer; inward paging still consumes its own momentum.

- Fixed trackpad clicks being misclassified as touchscreen input: AppKit's mouse `.touch`
  subtype also represents indirect trackpad input. ComboBox and MenuFlyout now retain desktop
  geometry for trackpads; CommandBar, text command surfaces, SplitButton and hover policies share
  the correction. Direct touch retains larger targets. Device records no longer leak between
  unrelated windows or get overwritten by a stale `NSApp.currentEvent` after a recognized touch.

- FlipView now lazily builds the current and adjacent pages, adds stable `id:` and vertical
  `orientation:` initializers, and tracks phased gestures before settling one page. Existing calls
  remain source-compatible; page-local state outside the cache is now released, so durable state
  belongs in the model. Stable IDs preserve selection/native content on reorder. Binding setters
  that reject, redirect or synchronously change data no longer leave displayed selection stale.
- FlipView keeps dragged page positions across parent refreshes, preserves mounted editor focus
  on stable-ID moves, and applies inherited disabled state to newly realized pages. Shared pan
  velocity expires when a gesture pauses before release; Pivot regression coverage is retained.
  A 1,000-page Release probe reduced 30 parent refreshes from 30,000 to 60 content evaluations.
  Exact gesture physics, phased boundary chaining and real touch/VoiceOver acceptance remain open.

- CalendarView and CalendarDatePicker now use continuous virtualized Month/Year/Decade grids.
  CalendarView adds the `numberOfWeeksInView` initializer argument (2–8, default 6). A bounded cell cache preserves
  dates under partial scrolling, mounted keyboard focus, and browsing during parent/model updates.
  Visible-scope headers and range-aware navigation follow the WinUI source; PageUp/PageDown and
  level changes preserve smaller date fields where valid. Level changes after scrolling retain
  the browsed location. The Gallery demonstrates compact scrolling and external selection updates.
- Calendar behavior correction: omitted date bounds now use the current Gregorian year ±100
  (January 1 through December 31 in the configured time zone), matching WinUI defaults. Specify
  explicit bounds for a wider range. Out-of-range dates are excluded from the generated grid.
  Continuous scrolling replaces the previous fixed-page wheel threshold; native macOS scrolling
  remains the input mechanism. Snap points, scope labels/motion and real Windows/VoiceOver parity
  are still pending.

- FluentViewBuilder now compiles single-branch `if`, optional binding and nested conditionals
  through an additional concrete `buildOptional` overload; existing generic calls remain valid.

- SplitButton/ToggleSplitButton now hit-test correctly away from the parent's origin, update open
  menus without losing retained rows or current actions, and follow anchor/placement changes.
  `showFlyout()` is now idempotent; use `hideFlyout()` to close. Hidden/detached/disabled controls
  cancel captured presses and menus; MenuFlyout also follows window movement and closes with its
  parent or when the application deactivates. Accessibility exposes the separate menu action and
  expanded state. Disabled programmatic primary invocations no longer run actions or toggle.
- SplitButton paints primary/secondary elevation independently for mouse presses, spans the
  separator with the primary background, and uses both pressed fills for touch. Toggle bindings
  retain stable subscriptions, reject stale deliveries and display the value accepted by setters.
  Added direct SplitButton and ToggleSplitButton Gallery examples and reproducible audit evidence.

- AutoSuggestBox now uses a scrollable suggestion viewport, follows keyboard selection, and
  preserves stable-ID rows/selection during live result updates. Popup size/position and reveal
  clips follow content, screen space and anchor changes; window close/detach invalidates old rows.
- Fixed Escape/Tab restoring only the displayed query while leaving the binding at a candidate,
  closed lists accepting navigation, stale candidate submission after external reset, and pending
  debounces reopening dismissed suggestions. Committed-text mode cancels pre-composition refreshes.
- AutoSuggestBox headers stay within the control; text, adornments and rows mirror in RTL without
  ending editing. Field-editor viewports retain complete glyphs and the end of long queries;
  previews/resets retain alignment. Text roles use theme typography. Added a richer Gallery sample.
- Added `onTextChangedEvent` with user-input, suggestion-chosen and programmatic-change reasons.
  Text changes are debounced before querying the provider; focus alone no longer raises the event.
  The existing string callback now also reports actual programmatic/selection text changes.
- Behavior correction to WinUI: AutoSuggestBox `maxSuggestionListHeight == 0` hides suggestions;
  negative values use available space. Previously both were treated as an unconstrained maximum.
- MenuBar preserves identified top-level controls, live menu panels, retained rows and open submenu
  branches during updates/reordering. `FluentMenuItem` accepts an optional stable ID, and standalone
  `FluentMenuFlyout.update(items:theme:reduceMotion:)` refreshes content without reopening the menu.
  Disabled/removed branches close safely; delayed hover follows retained rows; popup geometry and
  animation clips follow content, typography, anchor position and FlowDirection changes. Closed
  presenters reject queued clicks and keyboard events rather than acting on reopened menus.
- MenuBar/Menu builders now compose conditional branches, loops and arrays. Added a direct MenuBar
  Gallery sample with delayed live updates, submenu actions, disabled states and access keys.
- Context-menu refreshes update wrapped content and live menu actions; removing their host closes
  the popup and detaches it from its window.
- CommandBar reconciles command updates in place, preserving its open overflow panel and focus.
  Commands accept an optional stable `id`; `setCommands(primary:secondary:)` updates both groups
  atomically and retains identified controls across reorders/group moves. Without IDs, controls
  retain identity by group and position. Updated actions and toggle state no longer require
  recreating the native buttons, and model updates do not invoke toggle actions.
- Fixed hidden primary commands in overflow, incorrect primary-width measurement while the menu
  is open, and stale close animations reclaiming controls from a reopened popup. Resizes retain
  command focus across the bar/popup boundary, update the shared animation clip to fit new rows,
  and preserve the device-specific opening density.
- ListView/GridView headers clamp their available content width to zero after subtracting the
  WinUI 12pt side margins, including during reuse and narrow resize. Long text can compress,
  RTL preserves the correct leading edge, and content is clipped to the header. CI now rejects
  AppKit constraint-conflict diagnostics even when XCTest reports passing assertions.
- Header content follows WinUI's default leading alignment at its natural width instead of
  stretching every custom button/template. Explicitly stretching content, such as
  `FluentVStack(alignment: .width)`, still fills the slot; the divider retains the full slot width.
- TreeView retains native node and cell identity for content-only updates, preserves unbound
  selection through stable-ID reordering, and prevents queued normalization from writing to a
  detached selection binding. RTL row content now follows the mirrored chevron column.
- Added an interactive TreeView Gallery sample for single/tri-state selection, lazy children,
  expansion, invocation and single-item reordering. The quality gate mounts this sample.
- Fixed nested FluentHStack RTL buttons retaining positions from an old, wider layout after
  the stack shrinks; native spacing and intrinsic button sizes are preserved.
- TreeView (`FluentOutline`, now also `FluentTreeView`): WinUI TreeViewItem rows (32pt, 16pt
  indentation, chevron column, accent selection pill), `FluentTreeViewSelection` with tri-state
  multiple selection, `.expandedIDs`, `.onExpanding` (for `hasUnrealizedChildren`), `.onCollapsed`,
  `.onItemInvoked`, `.onMove` drag reordering, and WinUI Left/Right/Space/Return keyboard behavior.
- ListView/GridView group headers follow WinUI's ListViewHeaderItem: 48pt default height
  (`FluentCollectionLayout.defaultHeaderHeight`, was 34), 12,8,12,0 padding and a 1pt BaseLow
  divider. Group headers are sticky by default; `.areStickyGroupHeadersEnabled(false)` opts out.
- Added `.scrollIntoView(_:alignment:)` to FluentCollection, FluentListView and FluentGridView. The
  binding is cleared after scrolling, and `.leading` keeps the item clear of a pinned group header.
- Fixed `.frame(width:height:)` losing to content hugging (both at 750): explicit sizes now use
  priority 999, so a 32pt row stays 32pt in fitting-size layouts such as ForEach.
- FluentForEach now follows the axis and alignment of an enclosing FluentHStack/FluentVStack, and
  when `spacing` is omitted it uses that stack's spacing. Behavior change: an unspaced ForEach
  directly inside a FluentVStack now uses the stack's spacing (12 by default) instead of 8.

- Added direct Gallery samples for ToggleButton, RepeatButton, StackPanel, Grid, SplitView,
  NavigationView, TabView, TeachingTip, TitleBar, CommandBarFlyout, RichEditBox, Clipboard and
  StoragePickers. FluentGrid now shares space equally across columns and rows like WinUI's default
  star sizing.

- Flyouts now pick touch or pointer layouts from the device that opened them, as WinUI's
  InputDeviceTypeUsedToOpen: MenuFlyout default vs narrow padding, ComboBox touch item padding and
  240pt minimum popup width, taller CommandBar overflow rows, and primary text commands only for
  touch and pen (a Ctrl-click is a mouse). FlipView, Pivot and SemanticZoom pointer-only buttons
  ignore touch.

- Added CaptureElement camera preview (AVFoundation preview layer with stretch, mirroring and
  placeholder) and FluentCameraCapture (permission, devices, start/stop with explicit errors). The
  Gallery app declares camera access. FluentVStack/FluentHStack now accept a single child of any type.

- Added MapControl backed by MapKit: two-way center and Web Mercator zoom level, icon layer synced
  by id, interactive controls toggle and element clicks. The Gallery app now allows outgoing network
  connections for map tiles.

- Added AnimatedVisualPlayer (AutoPlay loop, play/pause/resume/stop/progress, playback rate,
  stretch, fallback content) and AnimatedIcon (WinUI marker lookup order, coalesced state changes,
  Cut/QueueOne/SpeedUpQueueOne queues, 20ms and Reduce Motion cuts, pointer-driven states, fallback
  symbol) over a `FluentAnimatedVisualSource` protocol, with Back, ChevronDownSmall, Settings,
  GlobalNavigationButton and Find sources on WinUI's marker timelines. Lottie JSON is not supported.

- Added ParallaxView: a background arranged larger by the shift and translated with WinUI's clamped
  parallax formula behind scrolling content, with relative/absolute source offsets, max shift
  ratio and 10% under/overpan. Fixed frame-laid-out hosts in Pivot, SwipeControl, SemanticZoom,
  AnnotatedScrollView and RefreshContainer being shrunk to their content by Auto Layout.

- Added RefreshContainer (pull to refresh) driven by the scroll view's elastic overscroll for
  trackpad and macOS 27 touch: WinUI's Idle/Peeking/Interacting/Pending/Refreshing states, 100pt
  pull with a 0.8 execution ratio, the rotating 30pt indicator with Pending pulse and refreshing
  spin, four pull directions, deferral-based completion and a two-way isRefreshing binding.
  Gallery sample added with partial coverage.

- Added AnnotatedScrollView, a scroll view with a WinUI AnnotatedScrollBar: proportional labels with
  the source collision rules, an accent thumb and pointer ghost, a detail label raised for touch,
  click/drag jumps, repeating step buttons with SmallChange, and a cancellable Scrolling callback.
  Gallery sample added with partial coverage.

- Added SemanticZoom with pinch (trackpad and macOS 27 touch) using WinUI's 0.5 zoom floor and 5%
  switch threshold, Ctrl/⌘ minus/plus, optional Ctrl+wheel, the opt-in pointer-only zoom-out
  button, CanChangeViews, a two-way binding, and a proxy that carries the chosen group back to the
  app. The shared input foundation gains a pinch driver. Gallery sample added with partial coverage.

- Added SwipeControl with Reveal and Execute modes on left/right (RTL-mirrored) or top/bottom
  sides, WinUI's 100pt threshold and open/close rules, BehaviorOnInvoked, single-open and
  outside-press dismissal, touch and trackpad input through the shared pan driver, and VoiceOver
  custom actions for every command. Gallery sample added with partial coverage.

- Added a shared input foundation: `FluentInputDeviceTracker` records the last input device per
  window (mouse, touch, pen, keyboard) like WinUI's InputDeviceType and posts changes, and an
  internal pan driver unifies macOS 27 direct touch, phased trackpad swipes and discrete wheel
  steps along either axis with RTL mapping. Pivot now uses it and hides its navigation buttons
  for touch.

- Pivot now pans interactively with direct touch on macOS 27, trackpad swipes and horizontal mouse
  wheels: content follows the gesture with the neighbouring item visible, carousel and clipped
  static headers follow WinUI's header curves, non-wrapping ends rubber-band, and releases snap to
  the adjacent item or back based on projected velocity. Vertical swipes stay with enclosing
  scroll views and mouse drags do not pan.

- Added Pivot with source-derived header geometry, accent selection pipe, static and carousel
  header modes, carousel-only wrapping, locked mode, hover navigation buttons, header and
  Ctrl+Tab/PageUp/PageDown keyboard navigation, RTL, optional title and left/right header slots,
  and WinUI's fly-out/fly-in content motion. Added a direct Gallery sample with partial coverage;
  touch panning, header templates and PivotItem loading events remain pending.

- TimePicker's flyout now uses the shared Fluent looping selectors instead of the native time
  editor, with locale-driven field order, localized period labels and digits, RTL ordering, and
  Return/Escape/Tab keyboard transactions. TimePicker and DatePicker reject queued notifications
  from replaced bindings, keep bound `nil` over fallbacks, write coerced values back, and apply
  binding and configuration changes atomically. Gallery now has separate DatePicker,
  CalendarDatePicker and TimePicker samples; DatePicker and TimePicker remain partial.

- Added embedded CalendarView with single/multiple/no selection, blackout/range reconciliation,
  RTL keyboard navigation and 4×4 Year/Decade views; CalendarDatePicker shares the same grid.
  Fixed weekday ordering, time-zone-inconsistent date math and out-of-range month navigation.
  CalendarDatePicker now rejects queued notifications from replaced bindings and updates its AX value.
  Added a direct Gallery sample with partial coverage; full scrolling/calendar/accessibility
  parity remains pending.

- Matched FlipView navigation-button geometry, idle/hover visibility and wheel-burst throttling
  to the WinUI source; added keyboard focus and current-page accessibility actions. Disabled
  composites now restore child controls before reconciling their parent and track newly mounted
  controls without retaining removed ones.

- Fixed FlipView observer replacement, selection synchronization after item removal/empty/refill,
  interrupted-page cleanup and RTL transition direction. Added a direct Gallery sample with
  conservative partial coverage; WinUI touch/virtualization parity remains pending.

- Fixed CollectionView resize ordering: list rows stay in one column and retain their scroll
  offset as legacy scrollbars and window widths change. Tiny/collapsed viewports recover without
  negative content constraints or stale flow-layout extents. Release audits now reject collection
  width and constraint diagnostics.

- Added atomic host updates, stable native-view configuration, focused external text resets,
  composition commit policy and editor undo/redo synchronization. Stable ForEach ordering no
  longer rebuilds its arranged-subview list, and Equatable state can suppress duplicate emissions.
- Separated collection structure and visible content updates, with optional per-item content
  versions. Added deterministic work-count regressions and reproducible Release audit gates.
- Added WinUI semantic typography metrics and configurable fonts, shared aspect-preserving icon
  sources, separate AppBar chevron measurement, and a dense command-height option.
- Separated fixed Mica/Acrylic base colors from explicit native AppKit and Liquid Glass choices.
  Added framework string resources and tracked localized accessibility defaults.
- Linked Gallery coverage to an exhaustive sample registry, added audit-focused samples, and
  introduced controlled state screenshots with a pixel-difference gate. Windows parity and
  real IME/VoiceOver acceptance remain separate from these automated checks.

- Fixed non-finite title-bar button frames during transient zero-height layout.

- Fixed FluentButton image-only and image-plus-label rendering, intrinsic measurement, RTL
  leading/trailing placement, and image preservation during declarative updates. Added optional
  image content to FluentButtonView, including its style and flyout modifiers.
- Fixed extended WindowShell viewport sizing so native AppKit content fills the remaining window
  height and continues to resize below a fixed-height title bar.
- Added opt-in leading primary-command alignment for document toolbars. CommandBar retains its
  WinUI-standard trailing alignment by default; the leading variant mirrors in RTL.

## [0.1.0] - 2026-08-02

Initial public framework baseline.

- Native Swift/AppKit declarative view tree with state, bindings, environment propagation, and stable reconciliation.
- Fluent theme tokens, Mica window surfaces, native controls, layout, collections, navigation, overlays, menus, motion, accessibility, localization, and RTL support.
- Native application scenes, settings, commands, Dock menus, Services routing, file import/export, printing, sharing, document sessions, and multi-document coordination.
- Gallery and executable validation with Light/Dark/RTL bitmap baselines.
- SwiftPM XCTest coverage and GitHub Actions gates for warning-free Debug and Release builds.

- Gallery navigation now uses a dedicated `.bottomUp` page entrance while the existing generic
  NavigationView transition modes remain available. `.entrance` follows WinUI's asymmetric
  forward/back triggers, while `.bottomUp` remains fixed to the lower-edge Gallery direction.
  Added a global `materialEffectsEnabled` theme switch and migrated transient and
  NavigationView surfaces to Liquid Glass with an opaque fallback when effects are disabled.
- NavigationStack now uses the shared page presenter for coordinated push/pop transitions, including
  duplicate route values at different depths. Window restoration preserves a launch-time active ID,
  rejects non-finite saved frames, and contains partially off-screen frames within the best visible
  screen.
- RichTextEditor now publishes drag-selection changes once per RunLoop turn, reuses stable binding
  observers across declarative updates, and drops stale asynchronous text or selection deliveries.
- Added public `FluentWindowShell` configuration axes and presets for native/extended title bars,
  optional title-bar search, title-bar or pane toggles, vertical Compact/Minimal/Left navigation,
  horizontal Top navigation, Solid/Mica/Liquid Glass backdrops, and content-corner policies. The
  Gallery now consumes the shell, and its HeaderContent and page content share one clipped WinUI-like
  ContentSurface with responsive title-bar slot priority.
- Completed the WindowShell state matrix: Back and pane-header content are public, native chrome
  normalizes unsupported Fluent search/title-bar toggle requests, and TitleBar/NavigationView
  toggles now expose reliable accessibility press actions. Added extended-reference and native+
  vertical-pane Light shell baselines plus same-window native/extended switching validation.
- Added a window-owned document-modal presentation coordinator shared by custom Sheet,
  ConfirmationDialog, FluentAlert, file importer, and file exporter hosts. Presentations now queue per window,
  restore focus, reuse stable binding observers, survive rapid close/reopen without stale writeback,
  and cancel when their host leaves the window. Presented Sheets update content, title, size, theme,
  and Liquid Glass fallback state in place while native ConfirmationDialog remains backed by
  `NSAlert`.
- Added binding-driven `FluentPopover` with automatic/top/bottom/leading/trailing placement,
  RTL edge mapping, transient/semitransient/application-defined behavior, native focus restore,
  Liquid Glass content, Reduce Motion, stable same-size updates, and geometry-safe presenter
  replacement when AppKit cannot resize a live popover. `FluentPopoverButton` now shares the same
  material/content controller and exposes placement, behavior, RTL, and Reduce Motion configuration.
- Completed multi-window presentation restoration: frame keys are now scene-specific, automatic
  scenes persist their declaration-ordered open set and active window ID, disabled-restoration
  scenes are excluded from reopen, and restored frames are reapplied after AppKit window ordering
  so native cascade behavior cannot shift independent windows.
- Switched Liquid Glass composition to behind-window blending, made the Gallery window transparent
  to wallpaper-level material, and guarded material updates against redundant appearance recursion.
  ComboBox popup rows and NavigationView items now use host-owned single-hover state with one
  tracking area per row and deterministic reset during scrolling, layout, focus loss, and dismissal.
- Added source-aligned MenuFlyout system-icon slots with presenter-wide 28pt check/icon placeholders,
  16pt symbols, 11pt narrow padding, accelerator and submenu trailing columns, native `NSMenu`
  forwarding, and mirrored slot placement without mirroring non-directional glyphs. Added dedicated
  Light/Dark flyout baselines. TextCommandBarFlyout now commits More expansion geometry immediately
  and runs the source 250ms collapsed-to-expanded clip instead of animating the panel model frame.
- Added MenuFlyout-specific High Contrast resources for system Highlight/HighlightText/GrayText
  states and a dedicated high-contrast bitmap baseline. Added public `FluentCommandBarFlyout`,
  `FluentCommandBarItem`, primary/secondary builders, action/toggle/separator elements,
  `AlwaysExpanded`, a regular Button attachment, source-sized More expansion, Liquid Glass, immediate
  dismissal, executable behavior coverage, and Light/Dark expanded baselines.
- Routed MenuFlyout, ComboBox SplitOpen, Toggle binding updates, and CollectionItem background/
  selection motion through the shared animation execution layer. Batches preserve source geometry,
  presentation-state interruption, Reduce Motion, synchronized start times, and generation-safe
  completion without serializing unrelated controls.
- Added explicit horizontal and vertical `FluentDivider` orientation.
- Corrected shared list selection-rail layout updates across selection, scrolling, resizing, and
  stable-ID changes; added selected-row geometry validation.
- Reworked the shared vertical list rail into a WinUI-inspired two-indicator choreography with
  3 x 16 geometry, 600ms directional keyframes, connected-rect scaling, outgoing fade, RTL support,
  rapid-target cancellation, and Reduce Motion coverage.
- Added keyed Gallery page transitions with Reduce Motion, rapid-update coalescing, and
  completion-driven cleanup with a deterministic fallback.
- Removed duplicate Gallery page titles and expanded the Collections example to avoid section/item
  clipping.
- Added executable existence, dimension, and pixel-variation checks for documented Gallery bitmap
  baselines and regenerated Controls/Inputs Light and Dark captures.
- Added a public stable-ID `FluentNavigationView` with automatic, Left, Compact, Minimal overlay, and
  Top layouts; configurable WinUI-derived thresholds and pane widths; primary/footer destinations;
  separate pane/content headers; bound pane state; stale-selection cleanup; keyboard, accessibility,
  RTL, and Reduce Motion behavior; and completion-driven 350ms/120ms pane motion.
- Migrated the Gallery shell from its private list wrapper to `FluentNavigationView`. Top mode now
  keeps a stable visible prefix, presents hidden destinations through `FluentMenuFlyout`, and routes
  hidden selection plus the horizontal shared indicator through `More`.
- Added responsive Minimal Light/Dark and Top Light/Dark/RTL Gallery bitmap baselines and executable
  coverage for adaptive thresholds, overlay geometry, Top overflow actions, disabled items, and
  primary-to-footer selection motion.
- Added public `FluentTitleBar` with 32pt compact and 48pt expanded/automatic layouts, pane/back
  controls, icon/title/subtitle, left/center/right slots, RTL and inactive-window states, native
  dragging and double-click behavior, traffic-light exclusion, title synchronization, and reversible
  AppKit chrome configuration.
- Integrated `FluentTitleBar` above the Gallery `FluentNavigationView` through one shared pane
  binding, removed the duplicate native-rendering label, and regenerated all 14 responsive
  Light/Dark/RTL snapshot baselines.
- Reconciled the visual audit against completed divider, indicator, page-transition, NavigationView,
  and TitleBar work. ProgressBar, MenuFlyout motion, and deferred Liquid Glass work remain open
  visual-acceptance items.
- Rebuilt `FluentToggle` around independent idle, pressed, and dragging interaction state. Binding
  commits now occur once on release, drag positioning is direct, cancellation/external updates are
  deterministic, and keyboard/accessibility activation shares the same commit path.
- Added ToggleSwitch-specific Light/Dark/High Contrast track and knob tokens, exact 40 x 20 and
  12/14/17 x 14 geometry, explicit 83ms state animations protected from same-bounds layout, RTL
  mirroring, custom focus, Reduce Motion, Gallery On/Off/Disabled examples, and executable coverage.
- Rebuilt `FluentSlider` with stable track, value-fill, 18 x 18 outer-thumb, inner-thumb, and focus
  layers. Normal, PointerOver, Pressed, and Disabled inner geometry now uses 12/14/10/14 sizes and
  source-derived 167ms/250ms cubic-bezier motion while pointer position remains direct.
- Added Slider RTL pointer and keyboard direction, Home/End, accessibility increment/decrement,
  disabled input rejection, Escape restoration, external-binding drag cancellation, Reduce Motion,
  exact layer/motion validation, interactive/Disabled Gallery examples, and regenerated desktop and
  Minimal Light/Dark baselines.
- Rebuilt CheckBox and RadioButton around independent pointer-over, pressed, and committed state.
  Both now commit on release-inside, cancel outside/Escape, accept deterministic external bindings,
  and own stable visual/focus layers with RTL, keyboard, accessibility, disabled, and Reduce Motion
  coverage.
- Added source-derived CheckBox check-path motion using the AnimatedAccept 19-frame reveal and
  four-frame clear curves. RadioButton now uses a 20pt outer circle, 12/14/10/14 selected-dot states,
  and a dedicated 4-to-10pt unselected pressed-feedback layer with 250ms/167ms motion.
- Added native `FluentToggleButton` and `FluentRepeatButton` controls with declarative wrappers,
  source-mapped Button-family resources, explicit 83ms background transitions, keyboard and
  accessibility paths, Reduce Motion, stable update identity, Gallery examples, and Light/Dark
  baselines. ToggleButton supports two/three-state cycling; RepeatButton follows press-mode
  invocation with 500ms/33ms defaults and deterministic pointer, focus, disable, and timer cleanup.
- Expanded Gallery choice-control states, regenerated desktop/Minimal Light/Dark baselines, and added
  exact geometry, timing, same-bounds reconciliation, single-commit, cancellation, and environment
  validation.
- Rebuilt SegmentedControl with one Fluent-owned visual surface over `NSSegmentedControl` semantics,
  stable label/indicator identity, release-inside selection, external-update cancellation, mirrored
  RTL layout/input, disabled and Reduce Motion states, and same-bounds animation protection.
- Replaced the unsourced selection scale/opacity choreography with direct model geometry and a
  presentation-sampled 167ms `(0,0,0,1)` position-and-bounds transition derived from the SelectorBar
  selection resource; expanded Gallery states and executable motion/identity coverage.
- Added the shared `FluentVisualState`, `FluentVisualStateTransition`, and
  `FluentVisualStateCoordinator` contract for named control states, motion tokens, and Reduce Motion.
- Rebuilt ProgressBar from immediate drawing into a stable CALayer visual tree with 1pt/3pt
  determinate geometry, presentation-sampled 250ms value motion, RTL fill direction, paused/error
  settle states, and a two-layer indeterminate loop. Gallery now exposes Normal, Paused, Error, and
  Indeterminate modes; validation covers layer identity, state transitions, accessibility, RTL, and
  Reduce Motion. Regenerated Controls Light/Dark baselines.
- Rebuilt the Inputs Gallery layout around top-aligned columns and fixed 280 x 32 control slots;
  removed the incorrect underline style from the default TextBox/ComboBox examples and regenerated
  Inputs Light/Dark baselines.
- Added source-derived ComboBox visual ownership over the native `NSComboBox` semantics: filled
  surface, 38pt glyph column, `Margin=-4`/2pt/7pt focus highlight, 3 x 16 focus Pill, selected-item
  Pill, and 167ms pressed compression. Validation now checks the exact focus geometry and motion.
- Added input-modality-aware focus visibility so ordinary pointer focus no longer displays the
  keyboard-only focus ring across core controls and NavigationView controls.
- Corrected SegmentedControl rapid-selection motion by animating presentation position and bounds
  together, and separated ToggleSwitch's 167ms On/Off repositioning from its 83ms state geometry.
- Added two left-click menu examples to the Gallery and real left-button event snapshot scenarios.
  Root menus now reveal from 50% height, submenus from 33%, over 250ms from the resolved placement
  edge; close uses a separate 83ms linear fade and Reduce Motion skips both animations.
- Prevented NavigationView section text from clipping or jumping through the compact rail during
  pane collapse.

[Unreleased]: https://github.com/egysoloman/FluentKit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/egysoloman/FluentKit/releases/tag/v0.1.0
