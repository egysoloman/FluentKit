import XCTest
@testable import FluentKit

@MainActor
final class MaterialConfigurationTests: XCTestCase {
    private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }

    private func fallback(_ view: FluentMaterialView) throws -> NSColor {
        let color = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "FluentKit.Material.OpaqueFallback" }?.backgroundColor)
        return try XCTUnwrap(NSColor(cgColor: color)?.usingColorSpace(.deviceRGB))
    }

    func testDefaultPresetsAndFieldwiseOverridePrecedence() {
        let theme = FluentTheme.custom(colorScheme: .dark)
        XCTAssertEqual(theme.material(for: .window), .mica)
        XCTAssertEqual(theme.material(for: .navigation), .mica)
        XCTAssertEqual(theme.material(for: .transient), .acrylic)
        XCTAssertEqual(theme.material(for: .toolTip), .acrylic)
        let preset = FluentMaterialConfiguration(material: .mica, tintColor: .green, fallbackColor: .gray,
            blendingMode: .withinWindow, isEnabled: false)
        let configured = theme.with(materialConfiguration: .init(material: .nativeAcrylic, tintColor: .blue), for: .transient)
            .with(materialConfiguration: .init(fallbackColor: .orange, isEnabled: true), for: .toolTip)
        let resolved = configured.resolvedMaterialConfiguration(for: .toolTip, preset: preset,
            override: .init(material: .liquidGlass, tintColor: .clear))
        XCTAssertEqual(resolved.material, .liquidGlass)
        XCTAssertEqual(resolved.tintColor, .clear)
        XCTAssertEqual(resolved.fallbackColor, .orange)
        XCTAssertEqual(resolved.blendingMode, .withinWindow)
        XCTAssertEqual(resolved.isEnabled, true)
        XCTAssertEqual(configured.material(for: .toolTip), .nativeAcrylic)
        XCTAssertEqual(configured.material(for: .window), .mica)
        XCTAssertEqual(configured.with(materialConfiguration: nil, for: .toolTip)
            .resolvedMaterialConfiguration(for: .toolTip).fallbackColor, nil)
        XCTAssertNil(configured.with(materialEffectsEnabled: false).material(for: .toolTip))
    }

    func testThemeCopiesPreserveRoleOverridesAndScopedModifiersDoNotLeak() throws {
        let theme = FluentTheme.custom(colorScheme: .dark)
            .with(materialConfiguration: .init(material: .nativeAcrylic, tintColor: .blue), for: .container)
        for copy in [theme.with(accent: .red), theme.with(density: .compact), theme.with(contrast: .high),
                     theme.with(colorScheme: .light), theme.with(material: .sidebar), theme.with(materialEffectsEnabled: false),
                     theme.with(typography: theme.typography)] {
            XCTAssertEqual(copy.materialConfigurations, theme.materialConfigurations)
        }
        let base = FluentTheme.custom(colorScheme: .dark)
        func tree(_ material: FluentMaterial) -> some FluentView {
            FluentHStack {
                FluentText("Scoped").materialBackground()
                    .materialConfiguration(.init(material: material), for: .container)
                FluentText("Sibling").materialBackground()
            }
        }
        let host = FluentViewHost(tree(.nativeAcrylic), context: FluentRenderContext(theme: base))
        let first = descendants(host, FluentMaterialView.self)
        XCTAssertEqual(first.map(\.materialStyle), [.nativeAcrylic, .acrylic])
        host.update(tree(.liquidGlass))
        let second = descendants(host, FluentMaterialView.self)
        XCTAssertEqual(second.map(\.materialStyle), [.liquidGlass, .acrylic])
        XCTAssertEqual(first.map(ObjectIdentifier.init), second.map(ObjectIdentifier.init))
    }

    func testNativeBindingSurvivesThemeChangesAndAccessibilityDefeatsLocalEnable() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .light)
            .with(materialConfiguration: .init(tintColor: .blue, fallbackColor: .green), for: .transient)
        let material = FluentMaterialView()
        material.configure(theme: theme, role: .transient,
            configuration: .init(material: .nativeAcrylic, tintColor: .red, isEnabled: true))
        material.fluentTheme = theme.with(colorScheme: .dark)
            .with(materialConfiguration: .init(material: .mica, fallbackColor: .orange), for: .transient)
        XCTAssertEqual(material.materialStyle, .nativeAcrylic)
        XCTAssertEqual(material.tintColor, .red)
        XCTAssertEqual(material.fallbackColor, .orange)
        material.fluentTheme = material.fluentTheme?.with(materialEffectsEnabled: false)
        XCTAssertEqual(material.resolvedBackend, .opaque)
        XCTAssertFalse(material.isMaterialEnabled)
        XCTAssertEqual(try fallback(material).alphaComponent, 1)
        material.fluentTheme = theme.with(contrast: .high)
        XCTAssertEqual(material.resolvedBackend, .opaque)
        XCTAssertEqual(material.tintColor, .red, "stored customization survives the accessibility override")
        let contrast = try fallback(material)
        XCTAssertNotEqual(contrast, NSColor.green.usingColorSpace(.deviceRGB))
        XCTAssertEqual(contrast.alphaComponent, 1)
        material.fluentTheme = theme
        XCTAssertTrue(material.isMaterialEnabled)
        XCTAssertEqual(material.materialStyle, .nativeAcrylic)
    }

    func testDynamicFallbackColorsResolveUnderTheSurfaceAppearanceAndFlattenAlpha() throws {
        _ = NSApplication.shared
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .red : .blue
        }
        let view = FluentMaterialView()
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        view.configure(theme: theme, role: .container, configuration: .init(fallbackColor: color))
        XCTAssertEqual(try fallback(view).blueComponent, 1, accuracy: 0.001)
        view.fluentTheme = theme.with(colorScheme: .dark)
        XCTAssertEqual(try fallback(view).redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(try fallback(view).blueComponent, 0, accuracy: 0.001)
        view.configure(theme: theme.with(colorScheme: .dark), role: .container,
            configuration: .init(fallbackColor: .clear))
        XCTAssertEqual(try fallback(view).redComponent, theme.with(colorScheme: .dark).windowBackground.usingColorSpace(.deviceRGB)!.redComponent, accuracy: 0.002)
        XCTAssertEqual(try fallback(view).alphaComponent, 1)
    }

    func testSurfaceConfigurationUpdatesPreserveFieldEditorAndMarkedText() throws {
        _ = NSApplication.shared
        var created = 0
        func surface(_ material: FluentMaterial, _ role: FluentMaterialRole, _ radius: CGFloat, _ border: Bool) -> some FluentView {
            FluentMaterialSurface(role: role, material: material, cornerRadius: radius, showsBorder: border) {
                FluentNativeView(make: { created += 1; return NSTextField(string: "draft") }, update: { _, _ in })
            }
        }
        let context = FluentRenderContext(theme: .custom(colorScheme: .dark))
        let host = FluentViewHost(surface(.mica, .window, 4, true), context: context)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 80),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(descendants(host, NSTextField.self).first)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setMarkedText("hua", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let native = try XCTUnwrap(descendants(host, FluentMaterialView.self).first)
        for material in [FluentMaterial.nativeAcrylic, .liquidGlass, .acrylic] {
            host.update(surface(material, .container, 20, false))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(descendants(host, FluentMaterialView.self).first === native)
            XCTAssertTrue(descendants(host, NSTextField.self).first === field)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(native.materialStyle, material)
            XCTAssertEqual(native.layer?.cornerRadius, 20)
            XCTAssertEqual(native.layer?.borderWidth, 0)
        }
        XCTAssertEqual(created, 1)
    }

    func testGlassCornerRadiusTracksSurfaceWithoutReplacingTheBackend() throws {
        _ = NSApplication.shared
        guard FluentMaterialView.isNativeGlassAvailable,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else { throw XCTSkip("Native Glass is unavailable") }
        let view = FluentMaterialView(material: .liquidGlass)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let glass = try XCTUnwrap(view.subviews.first { $0.identifier?.rawValue == "FluentKit.Material.NativeGlass" })
        for radius: CGFloat in [4, 20, 0] {
            view.layer?.cornerRadius = radius
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual((glass.value(forKey: "cornerRadius") as? NSNumber)?.doubleValue, Double(radius))
            XCTAssertTrue(view.subviews.contains { $0 === glass })
        }
    }

    func testCardMaterialIsOptInAndSwitchingPreservesItsContent() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .dark)
        let content = NSTextField(string: "Editable content")
        let card = FluentCard(contentView: content)
        card.theme = theme
        XCTAssertTrue(descendants(card, FluentMaterialView.self).isEmpty)
        card.materialConfiguration = .init(material: .nativeAcrylic)
        let material = try XCTUnwrap(descendants(card, FluentMaterialView.self).first)
        XCTAssertEqual(material.preferredBlendingMode, .withinWindow)
        card.theme = theme.with(materialEffectsEnabled: false)
        XCTAssertTrue(descendants(card, FluentMaterialView.self).first === material)
        XCTAssertEqual(material.resolvedBackend, .opaque)
        let fill = try fallback(material)
        XCTAssertLessThan(fill.redComponent, theme.windowBackground.usingColorSpace(.deviceRGB)!.redComponent + 0.1, "a translucent white card fill must not become an opaque white card in dark mode")
        XCTAssertEqual(fill.alphaComponent, 1)
        XCTAssertTrue(content.superview === card)
        card.materialConfiguration = nil
        XCTAssertTrue(descendants(card, FluentMaterialView.self).isEmpty)
        card.theme = theme.with(materialConfiguration: .init(material: .nativeMica), for: .container)
        XCTAssertEqual(descendants(card, FluentMaterialView.self).first?.materialStyle, .nativeMica)
        XCTAssertTrue(card.contentView === content)
    }

    func testPopupAndToolTipRespectRoleOverridesAfterTheyAreCreated() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .dark)
        let popup = FluentPopupTransitionHost(content: NSView(), theme: theme, cornerRadius: 8, name: "MaterialTest")
        let tip = FluentToolTipSurface(content: NSTextField(labelWithString: "Help"), context: FluentRenderContext(theme: theme))
        let material = try XCTUnwrap(descendants(tip, FluentMaterialView.self).first)
        let changed = theme.with(materialConfiguration: .init(material: .nativeAcrylic, tintColor: .red), for: .transient)
            .with(materialConfiguration: .init(material: .liquidGlass), for: .toolTip)
        popup.update(theme: changed)
        tip.update(context: FluentRenderContext(theme: changed))
        XCTAssertEqual(popup.surface.materialStyle, .nativeAcrylic)
        XCTAssertEqual(material.materialStyle, .liquidGlass)
        XCTAssertEqual(material.tintColor, .red)
        tip.update(context: FluentRenderContext(theme: theme))
        XCTAssertEqual(material.materialStyle, .acrylic)
        XCTAssertNil(material.tintColor)
    }

    func testUnchangedRecipeAndGlassConfigurationsDoNotRebuildNativeEffects() {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .dark)
        for style in [FluentMaterial.mica, .liquidGlass] {
            let view = FluentMaterialView(material: style)
            view.configure(theme: theme, role: .transient, configuration: .init(material: style))
            var changes: [NSVisualEffectView.Material] = []
            let observation = view.observe(\.material, options: [.new]) { _, change in
                if let value = change.newValue { changes.append(value) }
            }
            for _ in 0..<10 {
                view.configure(theme: theme, role: .transient, configuration: .init(material: style))
            }
            XCTAssertTrue(changes.isEmpty, "unchanged surfaces must not switch native materials during content refresh")
            observation.invalidate()
        }
    }

    func testWorkspaceAccessibilityNotificationReappliesMaterialConfiguration() {
        _ = NSApplication.shared
        let view = FluentMaterialView(material: .nativeAcrylic)
        let expected = view.material
        view.material = .menu
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        XCTAssertEqual(view.material, expected, "display-option notifications must be observed on the workspace notification center")
    }
}
