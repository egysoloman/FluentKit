import XCTest
@testable import FluentKit

@MainActor
final class MaterialColorTransitionTests: XCTestCase {
    private func layers(_ view: FluentMaterialView) -> [CALayer] {
        (view.layer?.sublayers ?? []).filter { $0.name?.hasPrefix("FluentKit.Material.") == true }
    }

    private func withSurface(_ body: (FluentMaterialView) throws -> Void) rethrows {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 140, width: 300, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let surface = FluentMaterialView(material: .acrylic)
        surface.configure(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), role: .transient)
        window.contentView = surface
        window.orderFront(nil)
        surface.layoutSubtreeIfNeeded()
        CATransaction.flush()
        defer { window.close() }
        try body(surface)
    }

    private func inAnimatedTransaction(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(1)
        body()
        CATransaction.commit()
        CATransaction.flush()
    }

    private func assertNoColorAnimations(_ surface: FluentMaterialView, file: StaticString = #filePath, line: UInt = #line) {
        for layer in layers(surface) {
            for key in ["backgroundColor", "opacity", "hidden", "contents", "compositingFilter"] {
                XCTAssertNil(layer.animation(forKey: key), "\(layer.name ?? "layer").\(key)", file: file, line: line)
            }
        }
    }

    func testLiveThemeAndFallbackUpdatesDoNotCrossfadeTheMaterialLayers() throws {
        for dark in [true, false] { for path in ["configure", "theme", "fallback"] {
            try withSurface { surface in
                let initial = FluentTheme.custom(colorScheme: dark ? .light : .dark, materialEffectsEnabled: false)
                let target = initial.with(colorScheme: dark ? .dark : .light)
                surface.configure(theme: initial, role: .transient)
                CATransaction.flush()
                let fallback = try XCTUnwrap(layers(surface).first { $0.name?.hasSuffix("OpaqueFallback") == true })
                let before = fallback.backgroundColor
                inAnimatedTransaction {
                    switch path {
                    case "configure": surface.configure(theme: target, role: .transient)
                    case "theme": surface.fluentTheme = target
                    default: surface.fallbackColor = .systemRed
                    }
                }
                XCTAssertNotEqual(fallback.backgroundColor, before)
                assertNoColorAnimations(surface)
            }
        } }
    }

    func testRecipeTintAndFallbackActivationDoNotAcquireImplicitTransitions() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            throw XCTSkip("System accessibility settings require opaque materials")
        }
        for material in [FluentMaterial.mica, .acrylic] {
            withSurface { surface in
                let theme = FluentTheme.custom(colorScheme: .dark)
                surface.configure(theme: theme, role: .transient,
                    configuration: .init(material: material, tintColor: .red, tintOpacity: 0.2, luminosityOpacity: 0.4))
                CATransaction.flush()
                inAnimatedTransaction {
                    surface.tintColor = .blue
                    surface.tintOpacity = 0.8
                    surface.luminosityOpacity = 0.7
                }
                assertNoColorAnimations(surface)
                inAnimatedTransaction { surface.isMaterialEnabled = false }
                assertNoColorAnimations(surface)
                inAnimatedTransaction { surface.isMaterialEnabled = true }
                assertNoColorAnimations(surface)
            }
        }
    }

    func testMaterialRefreshPreservesExplicitPopupAnimations() throws {
        try withSurface { surface in
            let root = try XCTUnwrap(surface.layer)
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 0.8; animation.toValue = 1; animation.duration = 10
            root.add(animation, forKey: "fluent.popup.test")
            surface.configure(theme: .custom(colorScheme: .dark, materialEffectsEnabled: false), role: .transient)
            CATransaction.flush()
            XCTAssertNotNil(root.animation(forKey: "fluent.popup.test"))
            assertNoColorAnimations(surface)
        }
    }
}
