# Compatibility Policy

FluentKit targets native macOS desktop applications.

## Supported baseline

- macOS 12 or later.
- Swift 5.9 language mode.
- AppKit is the rendering and responder foundation. FluentKit does not provide a markup or XAML compatibility layer.
- The package can be built with Swift Package Manager. Full XCTest integration requires an Xcode toolchain; the repository's `FluentKitValidation` executable remains the portable smoke gate when only Command Line Tools are installed.

## API policy

- The version in `VERSION` and the package's release tags follow Semantic Versioning.
- Public types and initializers are documented before they are considered stable.
- Additive public APIs are preferred within a major version.
- Removing or changing the meaning of a public API requires a migration note in `CHANGELOG.md` and a major version unless the API is explicitly marked experimental.
- AppKit behavior, system appearance, available materials, Services registration, printing, and sharing remain subject to the host OS. FluentKit adapts its visual and interaction layer without replacing those native contracts.

## Validation gates

Every release candidate must pass:

```text
swift build -Xswiftc -warnings-as-errors
swift run FluentKitValidation
```

Gallery Light/Dark/RTL snapshots must be regenerated for user-facing visual changes and inspected
against the baselines documented in `SNAPSHOT_BASELINES.md`.
