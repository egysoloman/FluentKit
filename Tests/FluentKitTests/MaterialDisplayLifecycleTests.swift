import XCTest
@testable import FluentKit

final class MaterialDisplayLifecycleTests: XCTestCase {
    @MainActor
    private func mount(_ material: FluentMaterial) -> (MaterialDisplayWindow, NSView, FluentMaterialView) {
        _ = NSApplication.shared
        let origin = NSScreen.main?.visibleFrame.origin ?? .zero
        let window = MaterialDisplayWindow(contentRect: NSRect(x: origin.x + 100, y: origin.y + 100,
            width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let parent = NSView(frame: NSRect(x: 20, y: 30, width: 400, height: 220))
        window.contentView!.addSubview(parent)
        let view = FluentMaterialView(material: material)
        view.frame = NSRect(x: 10, y: 10, width: 200, height: 140)
        view.configure(theme: .custom(colorScheme: .dark), role: material == .mica ? .window : .transient)
        parent.addSubview(view)
        window.orderFront(nil)
        window.contentView!.layoutSubtreeIfNeeded()
        return (window, parent, view)
    }

    @MainActor
    func testBackingNotificationUpdatesAcrylicGrainWithoutAnotherLayout() throws {
        let (window, _, view) = mount(.acrylic)
        defer { window.close() }
        let noise = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "FluentKit.Material.Noise" })
        window.reportedScale = 2
        view.layout()
        for scale: CGFloat in [1, 2, 1] {
            window.reportedScale = scale
            NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
            XCTAssertEqual(noise.contentsScale, scale, "A display change must not wait for an unrelated layout")
        }
    }

    @MainActor
    func testNativeBackingCallbackUpdatesGrainAndPreservesContent() throws {
        let (window, _, view) = mount(.acrylic)
        defer { window.close() }
        let content = NSTextField(labelWithString: "Retained content")
        view.addSubview(content)
        let noise = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "FluentKit.Material.Noise" })
        window.reportedScale = 2
        view.layout()
        window.reportedScale = 1
        view.viewDidChangeBackingProperties()
        XCTAssertEqual(noise.contentsScale, 1)
        XCTAssertTrue(content.superview === view)
        XCTAssertNil(noise.animation(forKey: "contentsScale"))
    }

    @MainActor
    private func wallpaper(in view: FluentMaterialView) throws -> CALayer {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            throw XCTSkip("The system requires an opaque backdrop")
        }
        let deadline = Date().addingTimeInterval(5)
        while !view.hasWallpaperBackdrop && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard view.hasWallpaperBackdrop else {
            throw XCTSkip("AppKit did not provide a readable static desktop image")
        }
        return try XCTUnwrap(view.layer?.sublayers?
            .first { $0.name == "FluentKit.Material.OpaqueFallback" }?.sublayers?.first)
    }

    @MainActor
    func testScreenConfigurationChangeRepositionsUnchangedWallpaperWithoutDecodingAgain() throws {
        let (window, parent, view) = mount(.mica)
        defer { window.close() }
        let backdrop = try wallpaper(in: view)
        let image = backdrop.contents as AnyObject?
        let original = backdrop.frame
        // An origin-only display configuration change likewise changes the required local
        // sample rectangle without changing the cached image's size, URL or decode recipe.
        parent.setFrameOrigin(NSPoint(x: parent.frame.minX + 80, y: parent.frame.minY))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertEqual(backdrop.frame.minX, original.minX - 80, accuracy: 0.01)
        XCTAssertTrue(image === (backdrop.contents as AnyObject?), "Geometry changes reuse the decoded wallpaper")
    }

    @MainActor
    func testAncestorMoveAndScrollKeepWallpaperAnchoredToDesktop() throws {
        let (window, parent, view) = mount(.mica)
        defer { window.close() }
        let backdrop = try wallpaper(in: view)
        let original = backdrop.frame
        let image = backdrop.contents as AnyObject?
        parent.setFrameOrigin(NSPoint(x: parent.frame.minX + 80, y: parent.frame.minY))
        waitForUI(abs(backdrop.frame.minX - (original.minX - 80)) < 0.01)
        XCTAssertEqual(backdrop.frame.minX, original.minX - 80, accuracy: 0.01)
        parent.setBoundsOrigin(NSPoint(x: 0, y: 40))
        waitForUI(abs(backdrop.frame.minY - (original.minY + 40)) < 0.01)
        XCTAssertEqual(backdrop.frame.minY, original.minY + 40, accuracy: 0.01)
        XCTAssertTrue(image === (backdrop.contents as AnyObject?))
        view.materialStyle = .acrylic
        parent.setBoundsOrigin(.zero)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertFalse(view.hasWallpaperBackdrop)
        XCTAssertNil(backdrop.superlayer, "Pending geometry updates cannot restore an obsolete Mica layer")
    }

    @MainActor
    func testReparentingObservesTheNewAncestorsAndDetachCancelsPendingGeometry() throws {
        let (window, originalParent, view) = mount(.mica)
        defer { window.close() }
        let image = try wallpaper(in: view).contents as AnyObject?
        let newParent = NSView(frame: NSRect(x: 30, y: 50, width: 350, height: 200))
        window.contentView!.addSubview(newParent)
        view.removeFromSuperview()
        newParent.addSubview(view)
        let backdrop = try wallpaper(in: view)
        let original = backdrop.frame
        newParent.setFrameOrigin(NSPoint(x: 70, y: 50))
        waitForUI(abs(backdrop.frame.minX - (original.minX - 40)) < 0.01)
        XCTAssertEqual(backdrop.frame.minX, original.minX - 40, accuracy: 0.01)
        XCTAssertTrue(image === (backdrop.contents as AnyObject?))
        originalParent.setBoundsOrigin(NSPoint(x: 100, y: 100))
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertEqual(backdrop.frame.minX, original.minX - 40, accuracy: 0.01)
        newParent.setBoundsOrigin(NSPoint(x: 0, y: 60))
        view.removeFromSuperview()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertFalse(view.hasWallpaperBackdrop)
        XCTAssertNil(backdrop.superlayer)
    }

    @MainActor
    func testGeometryObserversAndQueuedUpdatesDoNotRetainDetachedMaterial() {
        _ = NSApplication.shared
        let window = MaterialDisplayWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        weak var detached: FluentMaterialView?
        autoreleasepool {
            let view = FluentMaterialView(material: .mica)
            view.frame = NSRect(x: 20, y: 20, width: 200, height: 140)
            window.contentView!.addSubview(view)
            window.contentView!.setBoundsOrigin(NSPoint(x: 0, y: 40))
            detached = view
            view.removeFromSuperview()
        }
        waitForUI(detached == nil)
        XCTAssertNil(detached)
    }
}

private final class MaterialDisplayWindow: NSWindow {
    var reportedScale: CGFloat?
    override var isKeyWindow: Bool { true }
    override var backingScaleFactor: CGFloat { reportedScale ?? super.backingScaleFactor }
}
