FluentKit 0.2.0 expands the native Swift/AppKit control library and fixes rendering, editing, layout and interaction issues found by source review and reproducible audits against WinUI.

## Highlights

- Stable declarative updates: reduced duplicate refresh work, preserved native view identity, reliable external text resets, and incremental collection updates.
- Expanded controls and samples, including Pivot, SemanticZoom, AnnotatedScrollBar, RefreshContainer and richer Collection/TreeView behavior.
- Improved menus, CommandBar, AutoSuggestBox, SplitButton, search geometry, Expander layout, navigation transitions and live scrollbar adaptation.
- Native switch/selection accessibility, keyboard focus routing, RTL and system appearance propagation improvements.
- Optional continuous ToolTip transitions and configurable materials. Fixed Fluent material recipes remain the presets; applications can override roles or individual surfaces.
- Reproducible audit tools and regression evidence are included in the repository. Passing automated checks is not a claim of complete Windows visual or input parity.

## Migration notes

- Explicit `.frame` dimensions now use priority 999. `FluentForEach` inherits its containing stack's axis and spacing; in a default VStack this changes spacing from 8pt to 12pt.
- ListView group headers default to 48pt and stick while scrolling; disable with `.areStickyGroupHeadersEnabled(false)` when needed. ScrollIntoView request bindings clear after handling.
- CheckBox/RadioButton keyboard activation commits on Space release; Return is not an activation key. See the changelog for interaction and cancellation details.
- Mica/Acrylic presets use fixed Fluent recipes instead of silently selecting Liquid Glass on newer macOS versions. Native effects are optional through material configuration.

## Validation and remaining work

The release candidate passed 489 XCTest tests with no AppKit constraint diagnostics, native executable validation, Debug/Release builds, the Xcode Gallery build, and deterministic Release rendering/input gates. Light/Dark/RTL Gallery captures were regenerated and reviewed.

Known follow-ups include Toggle keyboard commit timing and narrow SettingsCard description wrapping. Physical mouse/trackpad/touch acceptance, real system IME/VoiceOver sessions, multi-display scaling/wallpaper behavior, and Windows pixel/frame comparisons remain open. Full control parity and Lottie playback are not claimed. See [the follow-up queue](https://github.com/egysoloman/FluentKit/blob/v0.2.0/audits/2026-11-01/FOLLOW-UP.md).

## Requirements and installation

macOS 12 or later; Swift 5.9 language mode. Some native effects require newer macOS versions and fall back on older systems.

```swift
.package(url: "https://github.com/egysoloman/FluentKit.git", from: "0.2.0")
```

This is a source-package release; it does not install or replace any running input method.

[Full changelog](https://github.com/egysoloman/FluentKit/blob/v0.2.0/CHANGELOG.md) · [Changes since 0.1.0](https://github.com/egysoloman/FluentKit/compare/v0.1.0...v0.2.0)
