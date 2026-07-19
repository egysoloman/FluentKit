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
