import XCTest
@testable import FluentKit

@MainActor
final class NavigationChevronLifecycleTests: XCTestCase {
    private final class BackingWindow: NSWindow {
        var simulatedScale: CGFloat?
        override var backingScaleFactor: CGFloat { simulatedScale ?? super.backingScaleFactor }
    }
    private let key = "fluent.chevron.press"
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    private func definition(_ selection: FluentState<String?>, title: String = "Group",
                            enabled: Bool = true, children: Bool = true, expanded: Bool = false,
                            top: Bool = false) -> FluentNavigationView<String> {
        let item = FluentNavigationItem(id: "group", title: title, systemImageName: "folder", isEnabled: enabled,
            children: children ? [FluentNavigationItem(id: "child", title: "Child", systemImageName: "doc")] : [],
            selectsOnInvoked: false, isExpanded: expanded)
        return FluentNavigationView([item], selection: selection.projectedValue,
                                    paneDisplayMode: top ? .top : .left) { FluentText("Content") }
    }

    private func mount(top: Bool = false, expanded: Bool = false, rtl: Bool = false) throws
        -> (NSWindow, NSView, NSButton, FluentChevronPrimitiveLayer, FluentState<String?>) {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: nil)
        let context = FluentRenderContext(reduceMotion: false, layoutDirection: rtl ? .rightToLeft : .leftToRight)
        let view = definition(selection, expanded: expanded, top: top)._makeView(in: context)
        let window = BackingWindow(contentRect: NSRect(x: 120, y: 100, width: 720, height: 420),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(all(view).compactMap { $0 as? NSButton }.first { $0.accessibilityTitle() == "Group" })
        let chevron = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.NavigationView.ItemChevron" } as? FluentChevronPrimitiveLayer)
        // These checks test cancellation and timeline identity, not elapsed playback. Keep the
        // 250ms animation available even if AppKit dispatch/layout takes longer on a busy runner.
        let localTime = chevron.convertTime(CACurrentMediaTime(), from: nil)
        chevron.speed = 0
        chevron.timeOffset = localTime
        return (window, view, button, chevron, selection)
    }

    func testInitialDirectionsMatchTheUpDownVisualInBothLayouts() throws {
        for top in [false, true] {
            for rtl in [false, true] {
                for expanded in [false, true] {
                    let (window, _, _, chevron, _) = try mount(top: top, expanded: expanded, rtl: rtl)
                    defer { window.close() }
                    XCTAssertNil(chevron.animation(forKey: key), "Initial display is not an expansion transition")
                    XCTAssertEqual(chevron.transform.m11, expanded ? -1 : 1, accuracy: 0.001)
                    XCTAssertEqual(chevron.transform.m12, 0, accuracy: 0.001,
                                   "WinUI uses UpDownSmall for navigation, including RTL")
                }
            }
        }
    }

    func testLayoutContentThemeAndHoverKeepTheExistingExpansionTimeline() throws {
        for top in [false, true] {
            let (window, view, button, chevron, selection) = try mount(top: top)
            defer { window.close() }
            button.performClick(nil)
            let animation = try XCTUnwrap(chevron.animation(forKey: key))
            for _ in 0..<3 {
                button.needsLayout = true
                button.layoutSubtreeIfNeeded()
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime)
            }
            let context = FluentRenderContext(theme: .custom(colorScheme: .dark), reduceMotion: false)
            XCTAssertTrue(definition(selection, title: "Updated group", top: top)._updateView(view, in: context))
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(all(view).contains { $0 === button })
            XCTAssertEqual(button.accessibilityTitle(), "Updated group")
            XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime)
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            button.mouseEntered(with: event)
            button.layoutSubtreeIfNeeded()
            XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime)
            button.mouseExited(with: event)
            XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime)
            XCTAssertNil(selection.wrappedValue, "Expansion does not select a nonselecting group")
        }
    }

    func testReducedMotionSettlesWithoutReplayingOnReenable() throws {
        let (window, view, button, chevron, selection) = try mount()
        defer { window.close() }
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        XCTAssertTrue(definition(selection)._updateView(view, in: .init(reduceMotion: true)))
        XCTAssertNil(chevron.animation(forKey: key))
        XCTAssertEqual(chevron.transform.m11, -1, accuracy: 0.001)
        XCTAssertTrue(definition(selection)._updateView(view, in: .init(reduceMotion: false)))
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(chevron.animation(forKey: key))
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        XCTAssertEqual(chevron.transform.m11, 1, accuracy: 0.001)
    }

    func testDetachmentAndReattachmentSettleWithoutReplaying() throws {
        let (window, view, button, chevron, _) = try mount()
        defer { window.close() }
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        view.removeFromSuperview()
        XCTAssertNil(chevron.animation(forKey: key))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 420))
        window.contentView = container
        container.addSubview(view)
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(button.window === window)
        XCTAssertNil(chevron.animation(forKey: key))
        button.viewDidChangeBackingProperties()
        XCTAssertEqual(chevron.contentsScale, window.backingScaleFactor)
    }

    func testDisableAndDisclosureRemovalSettleTheCurrentMotion() throws {
        let (window, view, button, chevron, selection) = try mount()
        defer { window.close() }
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        XCTAssertTrue(definition(selection, enabled: false)._updateView(view, in: .init(reduceMotion: false)))
        XCTAssertFalse(button.isEnabled)
        XCTAssertNil(chevron.animation(forKey: key))
        XCTAssertTrue(definition(selection)._updateView(view, in: .init(reduceMotion: false)))
        XCTAssertNil(chevron.animation(forKey: key))
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        XCTAssertTrue(definition(selection, children: false)._updateView(view, in: .init(reduceMotion: false)))
        XCTAssertTrue(chevron.isHidden)
        XCTAssertNil(chevron.animation(forKey: key))
        XCTAssertTrue(definition(selection)._updateView(view, in: .init(reduceMotion: false)))
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(chevron.isHidden)
        XCTAssertNil(chevron.animation(forKey: key), "Adding a disclosure is not rotating an old one")
    }

    func testDirectionAndModeChangesSettleWithCurrentGeometry() throws {
        let (window, view, button, chevron, selection) = try mount()
        defer { window.close() }
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        let rtl = FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
        XCTAssertTrue(definition(selection)._updateView(view, in: rtl))
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(chevron.animation(forKey: key))
        XCTAssertEqual(chevron.transform.m11, -1, accuracy: 0.001)
        XCTAssertLessThan(chevron.frame.midX, button.bounds.midX)
        button.performClick(nil)
        XCTAssertNotNil(chevron.animation(forKey: key))
        XCTAssertTrue(definition(selection, top: true)._updateView(view, in: rtl))
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(all(view).contains { $0 === button })
        XCTAssertNil(chevron.animation(forKey: key))
        XCTAssertEqual(chevron.transform.m11, 1, accuracy: 0.001)
    }

    func testBackingChangesPreserveMotionWhileHidingSettlesIt() throws {
        let (window, _, button, chevron, _) = try mount()
        defer { window.close() }
        button.performClick(nil)
        let animation = try XCTUnwrap(chevron.animation(forKey: key))
        let backingWindow = try XCTUnwrap(window as? BackingWindow)
        for scale: CGFloat in [1, 2] {
            backingWindow.simulatedScale = scale
            button.viewDidChangeBackingProperties()
            XCTAssertEqual(chevron.contentsScale, scale)
            XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime)
        }
        button.isHidden = true
        XCTAssertNil(chevron.animation(forKey: key))
        button.isHidden = false
        button.layoutSubtreeIfNeeded()
        XCTAssertNil(chevron.animation(forKey: key), "Showing an unchanged row does not replay its expansion")
        XCTAssertEqual(chevron.transform.m11, -1, accuracy: 0.001)
    }

    func testTopGroupReservesChevronSpaceWithoutClippingAShortTitle() throws {
        for rtl in [false, true] {
            let (window, _, button, _, _) = try mount(top: true, rtl: rtl)
            defer { window.close() }
            let geometry = FluentNavigationItemHorizontalGeometry.resolve(in: button.bounds, top: true,
                expanded: true, depth: 0, hasChildren: true, rightToLeft: rtl)
            let titleWidth = ("Group" as NSString).size(withAttributes: [
                .font: FluentTheme.current.typography.font(for: .body)
            ]).width
            XCTAssertGreaterThanOrEqual(geometry.textFrame.width, titleWidth,
                                       "A short top-navigation title must fit beside its disclosure")
            let chevron = try XCTUnwrap(geometry.chevronFrame)
            XCTAssertFalse(geometry.textFrame.intersects(chevron))
        }
    }
}
