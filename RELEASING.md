# Releasing FluentKit

FluentKit follows Semantic Versioning. The version in `VERSION`, the changelog heading, the Git tag,
and the GitHub Release must match.

## Release checklist

1. Move completed entries from `Unreleased` into a dated version section in `CHANGELOG.md`.
2. Update `VERSION` to the same semantic version.
3. Verify the installation example in `README.md` points to the intended release line.
4. Run the release gates:

   ```bash
   swift build -Xswiftc -warnings-as-errors
   swift run FluentKitValidation
   swift build --configuration release -Xswiftc -warnings-as-errors
   ```

5. Commit and push the release preparation changes.
6. Wait for the `main` branch CI workflow to complete successfully.
7. Create and push an annotated tag:

   ```bash
   git tag -a v0.1.0 -m "FluentKit 0.1.0"
   git push origin v0.1.0
   ```

8. Create a GitHub Release from that tag and mark it as the latest release. Stable versions should
   not be marked as pre-releases.

## Initial 0.1.0 release notes

Use the following summary for the first GitHub Release:

````markdown
FluentKit 0.1.0 is the first public release of a native Swift/AppKit declarative UI framework
inspired by Fluent Design.

## Highlights

- Swift-native declarative view composition, state, and bindings
- Fluent-inspired controls, navigation, windowing, dialogs, and flyouts
- Native AppKit interoperability and macOS platform behavior
- Accessibility, localization, RTL, High Contrast, and Reduce Motion support
- SwiftPM Gallery and a standalone Xcode Gallery application
- Executable validation and visual regression baselines

## Requirements

- macOS 12 or later
- Swift 5.9 or later

## Installation

```swift
.package(
    url: "https://github.com/egysoloman/FluentKit.git",
    from: "0.1.0"
)
```
````
