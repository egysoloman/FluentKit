# Changelog

All notable FluentKit changes are recorded here. Versions follow Semantic Versioning.

## Unreleased

No unreleased changes yet.

## [0.1.0] - 2026-08-02

Initial public framework baseline.

- Native Swift/AppKit declarative view tree with state, bindings, environment propagation, and stable reconciliation.
- Fluent theme tokens, Mica window surfaces, native controls, layout, collections, navigation, overlays, menus, motion, accessibility, localization, and RTL support.
- Native application scenes, settings, commands, Dock menus, Services routing, file import/export, printing, sharing, document sessions, and multi-document coordination.
- Gallery and executable validation with Light/Dark/RTL bitmap baselines.

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
