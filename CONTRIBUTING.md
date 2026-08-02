# Contributing to FluentKit

Thank you for helping improve FluentKit. The project welcomes focused bug fixes, documentation,
validation coverage, accessibility improvements, and additions that fit its native Swift/AppKit
architecture.

## Requirements

- macOS 12 or later
- Swift 5.9 or later
- Xcode or the Swift toolchain with AppKit support

Clone the repository and run the required validation gates:

```bash
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
```

The standalone Gallery can be built from `FluentKitGallery/FluentKitGallery.xcodeproj`. The SwiftPM
Gallery is available with `swift run FluentGallery`. Run `swift run FluentKitValidation` from an
interactive macOS session when changing controls, navigation, animation, lifecycle, or snapshots.

## Before opening an issue

- Search existing issues to avoid duplicates.
- Confirm the problem against the latest `main` branch when practical.
- Include the macOS version, Swift/Xcode version, a minimal reproduction, and expected behavior.
- Do not disclose security vulnerabilities in public issues; follow [SECURITY.md](SECURITY.md).

## Making changes

Keep changes focused and preserve FluentKit's architectural boundaries:

- Prefer native Swift APIs and AppKit behavior over compatibility shims.
- Do not copy or redistribute Microsoft WinUI source code. Public design documentation may inform
  behavior, but the implementation must remain independent.
- Preserve native accessibility, responder-chain, keyboard, focus, and lifecycle behavior.
- Consider Light and Dark appearance, High Contrast, RTL layout, and Reduce Motion.
- Document public API additions and compatibility implications.
- Add or update Gallery coverage for user-facing behavior.
- Add executable validation for state, lifecycle, geometry, or interaction changes.
- Regenerate and inspect the documented snapshot baselines for intentional visual changes.

## Snapshot changes

Snapshot files live in `.snapshots/` and are documented in `SNAPSHOT_BASELINES.md`. A visual change
should include the relevant regenerated PNGs and a clear explanation of why the new rendering is
expected. Automated dimension and pixel-variation checks do not replace visual review.

## Pull requests

Pull requests should describe the problem, the chosen approach, compatibility impact, and validation
performed. Keep unrelated cleanup in separate changes.

Before submitting, confirm:

- `swift build -Xswiftc -warnings-as-errors` succeeds.
- `swift test -Xswiftc -warnings-as-errors` passes.
- UI and interaction changes have appropriate `swift run FluentKitValidation` coverage.
- Public API changes are documented.
- Visual changes include appropriate Gallery coverage and snapshots.
- Accessibility, RTL, High Contrast, and Reduce Motion were considered.
- No Microsoft WinUI source code was copied or redistributed.

By contributing, you agree that your contribution may be distributed under the repository's MIT
License.
