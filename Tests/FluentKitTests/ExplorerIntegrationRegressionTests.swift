import AppKit
import XCTest
@testable import FluentKit

final class ExplorerIntegrationRegressionTests: XCTestCase {
    @MainActor
    func testButtonImageOnlyRendersVisibleImage() throws {
        _ = NSApplication.shared
        let button = FluentButton(title: "")
        button.theme = .custom(colorScheme: .light, materialEffectsEnabled: false)
        button.reduceMotion = true
        button.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        button.imagePosition = .imageOnly
        button.frame = NSRect(x: 0, y: 0, width: 40, height: 32)
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent - center.greenComponent, 0.4, "Image-only buttons must draw their image, not just their chrome")
    }

    @MainActor
    func testButtonImageParticipatesInMeasurementAndDeclarativeUpdates() throws {
        _ = NSApplication.shared
        let button = FluentButton(title: "Copy")
        let textWidth = button.intrinsicContentSize.width
        button.image = NSImage(size: NSSize(width: 16, height: 16))
        button.imagePosition = .imageLeading
        XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.width, textWidth + 20)
        let host = FluentViewHost(button)
        let replacement = FluentButton(title: "Paste")
        replacement.image = NSImage(size: NSSize(width: 20, height: 20))
        replacement.imagePosition = .imageTrailing
        host.update(replacement)
        let mounted = try XCTUnwrap(host.subviews.first as? FluentButton)
        XCTAssertTrue(mounted === button)
        XCTAssertTrue(mounted.image === replacement.image)
        XCTAssertEqual(mounted.imagePosition, .imageTrailing)
    }

    @MainActor
    func testExtendedWindowShellFillsNativeContentAndResizes() throws {
        _ = NSApplication.shared
        let native = NSView()
        native.identifier = .init("Explorer.NativeContent")
        let host = FluentViewHost(
            FluentWindowShell(
                configuration: FluentWindowConfiguration(layout: .document, titleBarStyle: .extended, navigationPlacement: FluentWindowNavigationPlacement.none, backdrop: .solid),
                title: "Explorer",
                selection: FluentBinding<String?>(get: { nil }, set: { _ in }),
                header: { FluentEmptyView() },
                content: { FluentNativeView(native) }
            ),
            context: FluentRenderContext(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: true)
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(native.bounds.height, 550)
        window.setContentSize(NSSize(width: 1100, height: 800))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(native.bounds.height, 700)
        XCTAssertGreaterThan(native.bounds.width, 1000)
    }
    @MainActor
    func testLeadingCommandBarMirrorsAndPreservesWinUIDefault() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: [
            FluentCommandBarItem("New", systemImageName: "plus", labelPosition: .collapsed) {},
            FluentCommandBarItem("Copy", systemImageName: "doc.on.doc", labelPosition: .collapsed) {}
        ])
        bar.overflowButtonVisibility = .visible
        bar.frame = NSRect(x: 0, y: 0, width: 600, height: 48)
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.primaryCommandAlignment, .trailing)
        let first = bar.primaryCommandViews[0]
        let second = bar.primaryCommandViews[1]
        XCTAssertGreaterThan(first.frame.minX, 300, "Default must keep WinUI's trailing primary commands")
        bar.primaryCommandAlignment = .leading
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(first.frame.minX, FluentCommandBar.contentLeadingPadding, accuracy: 0.001)
        XCTAssertLessThan(first.frame.minX, second.frame.minX)
        let more = try XCTUnwrap(bar.subviews.first { $0.identifier?.rawValue == "FluentKit.CommandBar.MoreButton" })
        XCTAssertEqual(more.frame.minX, second.frame.maxX, accuracy: 0.001)
        bar.userInterfaceLayoutDirection = .rightToLeft
        bar.needsLayout = true
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(first.frame.maxX, 600 - FluentCommandBar.contentLeadingPadding, accuracy: 0.001)
        XCTAssertGreaterThan(first.frame.minX, second.frame.minX)
        XCTAssertEqual(more.frame.maxX, second.frame.minX, accuracy: 0.001)
    }

    @MainActor
    func testButtonLeadingImageMirrorsWithoutChangingPhysicalLeft() {
        _ = NSApplication.shared
        let button = FluentButton(title: "Copy")
        button.image = NSImage(size: NSSize(width: 16, height: 16))
        button.imagePosition = .imageLeading
        button.frame = NSRect(x: 0, y: 0, width: 120, height: 36)
        let leftToRight = button.contentRects(in: button.bounds)
        XCTAssertLessThan(leftToRight.image.maxX, leftToRight.title.minX)
        button.userInterfaceLayoutDirection = .rightToLeft
        let rightToLeft = button.contentRects(in: button.bounds)
        XCTAssertGreaterThan(rightToLeft.image.minX, rightToLeft.title.maxX)
        button.imagePosition = .imageLeft
        let physicalLeft = button.contentRects(in: button.bounds)
        XCTAssertLessThan(physicalLeft.image.maxX, physicalLeft.title.minX)
    }

    @MainActor
    func testIconOnlyButtonKeepsSixteenPointImageInsideThirtyTwoPointControl() {
        let button = FluentButton(title: "")
        button.image = NSImage(size: NSSize(width: 16, height: 16))
        button.imagePosition = .imageOnly
        button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        XCTAssertEqual(button.contentRects(in: button.bounds).image.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(button.intrinsicContentSize.width, 32)
    }

    @MainActor
    func testDeclarativeImageSurvivesStyleFlyoutAndImageRemoval() throws {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let content = FluentButtonView("Copy", image: image)
            .buttonStyle(FluentBorderlessButtonStyle())
            .flyout { FluentMenuItem("Open") {} }
        let host = FluentViewHost(content)
        let button = try XCTUnwrap(host.subviews.first as? FluentButton)
        XCTAssertTrue(button.image === image)
        XCTAssertEqual(button.imagePosition, .imageLeading)
        host.update(FluentButtonView("Text only"))
        XCTAssertTrue(host.subviews.first === button)
        XCTAssertNil(button.image)
        XCTAssertEqual(button.imagePosition, .noImage)
    }

    @MainActor
    func testTitleBarCaptionButtonsRemainFiniteInTinyArrangeSlots() throws {
        _ = NSApplication.shared
        let host = FluentViewHost(FluentTitleBar(
            title: "Explorer", isBackButtonVisible: true, isForwardButtonVisible: true,
            isPaneToggleButtonVisible: true
        ))
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        for height: CGFloat in [0, 1, 2, 3, 32] {
            host.frame = NSRect(x: 0, y: 0, width: 600, height: height)
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            let controls = descendants(host).filter { $0 is NSControl && $0.identifier?.rawValue.hasPrefix("FluentKit.TitleBar.") == true }
            XCTAssertGreaterThanOrEqual(controls.count, 3)
            for control in controls {
                XCTAssertTrue(control.frame.origin.x.isFinite)
                XCTAssertTrue(control.frame.origin.y.isFinite)
                XCTAssertTrue(control.frame.width.isFinite && control.frame.width >= 0)
                XCTAssertTrue(control.frame.height.isFinite && control.frame.height >= 0)
            }
        }
    }

}
