import XCTest
@testable import FluentKit

final class MaterialBackdropTests: XCTestCase {
    @MainActor private var systemRequiresOpaqueMaterial: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    @MainActor
    func testNavigationUsesAcrylicOnlyWhileItsAutomaticPaneOverlaysContent() throws {
        let open = FluentState(wrappedValue: false)
        let selection = FluentState<Int?>(wrappedValue: 0)
        func host(_ ownership: FluentNavigationPaneMaterialOwnership = .automatic,
                  theme: FluentTheme = .custom(colorScheme: .dark)) -> NSView {
            let root = FluentViewHost(FluentNavigationView(
                [FluentNavigationItem(id: 0, title: "Page")], selection: selection.projectedValue,
                isPaneOpen: open.projectedValue, paneDisplayMode: .leftCompact,
                paneMaterialOwnership: ownership
            ) { FluentText("Content") }, context: .init(theme: theme, reduceMotion: true))
            root.frame = CGRect(x: 0, y: 0, width: 800, height: 500)
            root.layoutSubtreeIfNeeded()
            return root
        }
        func materials(_ view: NSView) -> [FluentMaterialView] {
            (view as? FluentMaterialView).map { [$0] } ?? view.subviews.flatMap(materials)
        }
        let root = host()
        XCTAssertTrue(materials(root).isEmpty, "Closed compact rails inherit their backdrop")
        open.wrappedValue = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        root.layoutSubtreeIfNeeded()
        let overlay = try XCTUnwrap(materials(root).first)
        XCTAssertEqual(materials(root).count, 1)
        XCTAssertEqual(overlay.materialStyle, .acrylic)
        XCTAssertEqual(overlay.preferredBlendingMode, .withinWindow)
        let custom = host(theme: .custom(colorScheme: .dark).with(
            materialConfiguration: .init(material: .nativeAcrylic, blendingMode: .behindWindow), for: .navigation))
        // Entering compact mode closes the new host's pane. Open it after that initial
        // adaptive-layout notification before checking its explicit material override.
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        open.wrappedValue = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        custom.layoutSubtreeIfNeeded()
        XCTAssertEqual(materials(custom).first?.materialStyle, .nativeAcrylic)
        XCTAssertEqual(materials(custom).first?.preferredBlendingMode, .behindWindow)
        open.wrappedValue = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        root.layoutSubtreeIfNeeded()
        XCTAssertTrue(materials(root).isEmpty)
        XCTAssertEqual(materials(host(.standalone)).first?.materialStyle, .mica,
                       "Explicit standalone ownership retains its persistent material")
    }

    @MainActor
    func testMicaWallpaperSubscriptionCanMountAndDetachWithoutDesktopOptions() {
        _ = NSApplication.shared
        let window = BackdropOwnerWindow(contentRect: CGRect(x: 100, y: 100, width: 240, height: 180),
                                         styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.reportsKey = true
        let view = FluentMaterialView(material: .mica)
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 180)
        // Missing AppKit desktop options must use RGB black, not a gray-space color whose
        // RGB component access raises an Objective-C exception.
        window.contentView?.addSubview(view)
        XCTAssertTrue(view.window === window)
        view.removeFromSuperview()
        XCTAssertFalse(view.hasWallpaperBackdrop)
        XCTAssertNil(view.window)
    }

    func testWallpaperFillFitAndCenterHonorAspectRatioAndDisplayScale() {
        let pixels = CGSize(width: 1920, height: 1080), display = CGSize(width: 800, height: 600)
        func mapped(_ scaling: NSImageScaling, clipping: Bool = true, scale: CGFloat = 2) -> CGRect {
            FluentWallpaperGeometry.imageRect(imagePixels: pixels, displaySize: display,
                backingScale: scale, scaling: scaling, allowClipping: clipping)
        }
        let fill = mapped(.scaleProportionallyUpOrDown)
        XCTAssertEqual(fill.midX, 400, accuracy: 0.001)
        XCTAssertEqual(fill.midY, 300, accuracy: 0.001)
        XCTAssertEqual(fill.height, 600, accuracy: 0.001)
        XCTAssertEqual(fill.width / fill.height, 1920 / 1080, accuracy: 0.001)
        XCTAssertEqual(mapped(.scaleProportionallyUpOrDown, clipping: false),
                       CGRect(x: 0, y: 75, width: 800, height: 450))
        XCTAssertEqual(mapped(.scaleNone), CGRect(x: -80, y: 30, width: 960, height: 540))
        XCTAssertEqual(mapped(.scaleNone, scale: 1), CGRect(x: -560, y: -240, width: 1920, height: 1080))
        XCTAssertEqual(mapped(.scaleAxesIndependently), CGRect(origin: .zero, size: display))
        XCTAssertEqual(FluentWallpaperGeometry.imageRect(imagePixels: CGSize(width: 400, height: 200),
            displaySize: display, backingScale: 2, scaling: .scaleProportionallyDown, allowClipping: true),
            CGRect(x: 300, y: 250, width: 200, height: 100))
    }

    @MainActor
    func testAcrylicInNonactivatingPanelFollowsOwnerAndKeepsContentThroughFallback() throws {
        _ = NSApplication.shared
        let owner = BackdropOwnerWindow(contentRect: CGRect(x: 100, y: 100, width: 360, height: 180),
                             styleMask: [.titled], backing: .buffered, defer: false)
        let panel = BackdropPanel(contentRect: CGRect(x: 120, y: 120, width: 180, height: 100),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let parentPanel = BackdropPanel(contentRect: CGRect(x: 110, y: 110, width: 200, height: 120),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false; panel.isReleasedWhenClosed = false
        parentPanel.isReleasedWhenClosed = false
        defer {
            parentPanel.removeChildWindow(panel); owner.removeChildWindow(parentPanel)
            panel.close(); parentPanel.close(); owner.close()
        }
        let material = FluentMaterialView(material: .acrylic)
        let content = NSTextField(labelWithString: "Preserved content")
        material.addSubview(content)
        panel.contentView = material
        owner.makeKeyAndOrderFront(nil)
        owner.addChildWindow(parentPanel, ordered: .above)
        parentPanel.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        owner.reportsKey = true
        material.configure(theme: .custom(colorScheme: .dark), role: .transient)
        let opaque = systemRequiresOpaqueMaterial
        XCTAssertTrue(owner.isKeyWindow)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(material.state, opaque ? .followsWindowActiveState : .active)
        XCTAssertEqual(material.blendingMode, opaque ? .withinWindow : .behindWindow)
        let luminosity = try XCTUnwrap(material.layer?.sublayers?.first { $0.name == "FluentKit.Material.Luminosity" })
        let noise = try XCTUnwrap(material.layer?.sublayers?.first { $0.name == "FluentKit.Material.Noise" })
        XCTAssertEqual(luminosity.isHidden, opaque)
        XCTAssertEqual(noise.isHidden, opaque)
        owner.reportsKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: owner)
        XCTAssertEqual(material.state, opaque ? .followsWindowActiveState : .inactive)
        owner.reportsKey = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: owner)
        XCTAssertEqual(material.state, opaque ? .followsWindowActiveState : .active)
        XCTAssertNotNil(luminosity.compositingFilter)
        material.configure(theme: .custom(contrast: .high, colorScheme: .light), role: .transient)
        XCTAssertEqual(material.resolvedBackend, .opaque)
        XCTAssertTrue(luminosity.isHidden)
        XCTAssertTrue(noise.isHidden)
        XCTAssertTrue(content.superview === material)
        material.configure(theme: .custom(colorScheme: .light), role: .transient)
        XCTAssertEqual(material.resolvedBackend, opaque ? .opaque : .fluentRecipe)
        XCTAssertEqual(luminosity.isHidden, opaque)
        XCTAssertTrue(content.superview === material)
    }

    @MainActor
    func testRecipeStrengthOverridesStayLocalAndSurviveThemeUpdates() throws {
        let theme = FluentTheme.custom(colorScheme: .dark)
            .with(materialConfiguration: .init(tintOpacity: 0.3, luminosityOpacity: 0.7), for: .transient)
        let view = FluentMaterialView()
        view.configure(theme: theme, role: .toolTip, configuration: .init(tintOpacity: 0.6))
        let luminosity = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "FluentKit.Material.Luminosity" })
        let tint = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "FluentKit.Material.MicaTint" })
        func checkStrengths() throws {
            // Accessibility must suppress rendering while retaining the developer's settings.
            XCTAssertEqual(view.luminosityOpacity, 0.7)
            XCTAssertEqual(view.tintOpacity, 0.6)
            if systemRequiresOpaqueMaterial {
                XCTAssertEqual(view.resolvedBackend, .opaque)
                XCTAssertTrue(luminosity.isHidden)
                XCTAssertTrue(tint.isHidden)
            } else {
                XCTAssertEqual(try XCTUnwrap(luminosity.backgroundColor).alpha, 0.7, accuracy: 0.001)
                XCTAssertEqual(try XCTUnwrap(tint.backgroundColor).alpha, 0.6, accuracy: 0.001)
            }
        }
        try checkStrengths()
        view.fluentTheme = theme.with(colorScheme: .light)
        try checkStrengths()
        XCTAssertEqual(theme.resolvedMaterialConfiguration(for: .transient).tintOpacity, 0.3)
        view.materialStyle = .nativeAcrylic
        XCTAssertNil(tint.compositingFilter, "Explicit AppKit alternatives retain normal tint compositing")
        XCTAssertTrue(luminosity.isHidden)
    }
}

private final class BackdropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

private final class BackdropOwnerWindow: NSWindow {
    var reportsKey = false
    override var isKeyWindow: Bool { reportsKey }
}
