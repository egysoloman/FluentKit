# Changelog

All notable FluentKit changes are recorded here. Versions follow Semantic Versioning.

## [0.1.0] - 2026-07-19

Initial public framework baseline.

- Native Swift/AppKit declarative view tree with state, bindings, environment propagation, and stable reconciliation.
- Fluent theme tokens, Mica window surfaces, native controls, layout, collections, navigation, overlays, menus, motion, accessibility, localization, and RTL support.
- Native application scenes, settings, commands, Dock menus, Services routing, file import/export, printing, sharing, document sessions, and multi-document coordination.
- Gallery and executable validation with Light/Dark/RTL bitmap baselines.

## Unreleased

Changes after `0.1.0` will be grouped here until the next tagged release. Breaking public API changes
require a major version; additive APIs remain source-compatible within a major version whenever
AppKit and Swift permit it.

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
- Expanded Gallery choice-control states, regenerated desktop/Minimal Light/Dark baselines, and added
  exact geometry, timing, same-bounds reconciliation, single-commit, cancellation, and environment
  validation.
- Rebuilt SegmentedControl with one Fluent-owned visual surface over `NSSegmentedControl` semantics,
  stable label/indicator identity, release-inside selection, external-update cancellation, mirrored
  RTL layout/input, disabled and Reduce Motion states, and same-bounds animation protection.
- Replaced the unsourced selection scale/opacity choreography with direct model geometry and a
  presentation-sampled 167ms `(0,0,0,1)` position transition derived from the SelectorBar selection
  resource; expanded Gallery states and executable motion/identity coverage.
- Added the shared `FluentVisualState`, `FluentVisualStateTransition`, and
  `FluentVisualStateCoordinator` contract for named control states, motion tokens, and Reduce Motion.
- Rebuilt ProgressBar from immediate drawing into a stable CALayer visual tree with 1pt/3pt
  determinate geometry, presentation-sampled 250ms value motion, RTL fill direction, paused/error
  settle states, and a two-layer indeterminate loop. Gallery now exposes Normal, Paused, Error, and
  Indeterminate modes; validation covers layer identity, state transitions, accessibility, RTL, and
  Reduce Motion. Regenerated Controls Light/Dark baselines.
