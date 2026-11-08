import XCTest
@testable import FluentKit

@MainActor
final class MaterialAppearanceLifecycleTests: XCTestCase {
    private func requireRecipeEffects() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            throw XCTSkip("System accessibility settings require opaque materials")
        }
    }

    private func layer(_ name: String, in view: FluentMaterialView) throws -> CALayer {
        try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "FluentKit.Material.\(name)" })
    }

    private func components(_ layer: CALayer) throws -> [CGFloat] {
        let color = try XCTUnwrap(layer.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }

    func testSystemMaterialUsesItsWindowAppearanceForRecipeAndFallback() throws {
        _ = NSApplication.shared
        try requireRecipeEffects()
        let previous = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = previous }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for style in [FluentMaterial.mica, .acrylic] {
            for configured in [false, true] {
                let material = FluentMaterialView(material: style)
                window.contentView = material
                if configured {
                    material.configure(theme: FluentTheme(), role: .window,
                        configuration: .init(material: style))
                }
                let reference = FluentMaterialView(material: style)
                for dark in [true, false, true] {
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    material.viewDidChangeEffectiveAppearance()
                    if configured {
                        reference.configure(theme: .custom(colorScheme: dark ? .dark : .light), role: .window,
                            configuration: .init(material: style))
                    } else { reference.fluentTheme = .custom(colorScheme: dark ? .dark : .light) }
                    func colorsMatch() -> Bool {
                        for name in ["OpaqueFallback", "MicaTint", "Luminosity"] {
                            guard let actual = try? components(layer(name, in: material)),
                                  let expected = try? components(layer(name, in: reference)),
                                  zip(actual, expected).allSatisfy({ abs($0 - $1) < 0.001 }) else { return false }
                        }
                        return true
                    }
                    waitForUI(colorsMatch())
                    for name in ["OpaqueFallback", "MicaTint", "Luminosity"] {
                        let actual = try components(layer(name, in: material))
                        let expected = try components(layer(name, in: reference))
                        for (a, e) in zip(actual, expected) {
                            XCTAssertEqual(a, e, accuracy: 0.001, "\(style) \(name), configured=\(configured), dark=\(dark)")
                        }
                    }
                }
            }
        }
    }

    func testDynamicTintResolvesAgainWhenInheritedAppearanceChanges() throws {
        _ = NSApplication.shared
        try requireRecipeEffects()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let material = FluentMaterialView(material: .mica)
        // An adaptive developer override can change even when the recipe's NSColor is equal.
        material.tintColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .red : .blue
        }
        material.tintOpacity = 0.37
        material.luminosityOpacity = 0.61
        window.contentView = material
        for dark in [false, true, false] {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            material.viewDidChangeEffectiveAppearance()
            waitForUI((try? components(layer("MicaTint", in: material))[0]) == (dark ? 1 : 0))
            let tint = try components(layer("MicaTint", in: material))
            XCTAssertEqual(tint[0], dark ? 1 : 0, accuracy: 0.01)
            XCTAssertEqual(tint[2], dark ? 0 : 1, accuracy: 0.01)
            XCTAssertEqual(tint[3], 0.37, accuracy: 0.001)
            XCTAssertEqual(try components(layer("Luminosity", in: material))[3], 0.61, accuracy: 0.001)
        }
    }

    func testMicaRetainsWallpaperWhenANestedMenuTakesKeyAndFallsBackWhenFamilyDeactivates() throws {
        _ = NSApplication.shared
        try requireRecipeEffects()
        let windows = (0..<3).map { index in
            MaterialFocusWindow(contentRect: NSRect(x: 120 + index * 10, y: 120, width: 240, height: 180),
                                styleMask: [.titled], backing: .buffered, defer: false)
        }
        windows.forEach { $0.isReleasedWhenClosed = false }
        let owner = windows[0], popup = windows[1], submenu = windows[2]
        owner.addChildWindow(popup, ordered: .above)
        popup.addChildWindow(submenu, ordered: .above)
        defer {
            popup.removeChildWindow(submenu); owner.removeChildWindow(popup)
            windows.reversed().forEach { $0.close() }
        }
        owner.reportsKey = true
        let material = FluentMaterialView(material: .mica)
        material.frame = NSRect(x: 0, y: 0, width: 240, height: 180)
        owner.contentView = material
        material.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(5)
        while !material.hasWallpaperBackdrop && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard material.hasWallpaperBackdrop else { throw XCTSkip("No readable static desktop wallpaper") }
        owner.reportsKey = false; submenu.reportsKey = true
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: owner)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: submenu)
        XCTAssertTrue(material.hasWallpaperBackdrop, "A child menu is still part of the active window")
        submenu.reportsKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: submenu)
        XCTAssertFalse(material.hasWallpaperBackdrop)
        popup.reportsKey = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: popup)
        XCTAssertTrue(material.hasWallpaperBackdrop)
    }
}

private final class MaterialFocusWindow: NSWindow {
    var reportsKey = false
    override var isKeyWindow: Bool { reportsKey }
}
