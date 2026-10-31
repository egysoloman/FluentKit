import XCTest
@testable import FluentKit

final class CommandBarLifecycleTests: XCTestCase {
    @MainActor private func window(_ bar: FluentCommandBar, width: CGFloat = 400) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let stage = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        window.contentView = stage
        stage.addSubview(bar)
        bar.frame = NSRect(x: 0, y: 180, width: width, height: 48)
        bar.reduceMotion = true
        window.makeKeyAndOrderFront(nil)
        bar.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    func testDeclarativeRefreshKeepsControlsOpenPanelAndFocusedCommand() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        func content() -> FluentCommandBarView {
            FluentCommandBarView(primaryCommands: [FluentCommandBarItem("Copy", labelPosition: .collapsed) {}],
                secondaryCommands: [FluentCommandBarItem("First") {}, FluentCommandBarItem("Second") {}])
        }
        let bar = try XCTUnwrap(content()._makeView(in: context) as? FluentCommandBar)
        let window = window(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let primary = bar.primaryCommandViews[0]
        let secondary = bar.secondaryCommandViews[1]
        panel.makeFirstResponder(secondary)
        var changes: [Bool] = []
        bar.onIsOpenChanged = { changes.append($0) }
        for _ in 0..<5 { XCTAssertTrue(content()._updateView(bar, in: context)); bar.layoutSubtreeIfNeeded() }
        XCTAssertTrue(bar.primaryCommandViews[0] === primary)
        XCTAssertTrue(bar.secondaryCommandViews[1] === secondary)
        XCTAssertTrue(bar.isOpen)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(panel.firstResponder === secondary)
        XCTAssertTrue(changes.isEmpty)
    }

    @MainActor
    func testOverflowedPrimaryIsVisibleAndReturnsToStripWhenSpaceBecomesAvailable() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: (0..<4).map {
            FluentCommandBarItem("Command \($0)", systemImageName: "doc", labelPosition: .collapsed) {}
        }, secondaryCommands: [FluentCommandBarItem("Settings") {}])
        let window = window(bar, width: 200)
        defer { bar.setOpen(false, animated: false); window.close() }
        XCTAssertEqual(bar.overflowedPrimaryIndexes, [2, 3])
        let moved = bar.primaryCommandViews[3]
        bar.setOpen(true, animated: false)
        XCTAssertFalse(moved.isHidden, "An overflowed primary command must be visible inside the popup")
        bar.layoutSubtreeIfNeeded()
        XCTAssertFalse(moved.isHidden)
        let panel = try XCTUnwrap(window.childWindows?.first)
        bar.setFrameSize(NSSize(width: 360, height: 64))
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.overflowedPrimaryIndexes.isEmpty, "Measure primary widths rather than their wider overflow row presentation")
        XCTAssertTrue(moved.superview === bar)
        XCTAssertFalse(moved.isHidden)
        XCTAssertTrue(window.childWindows?.first === panel)
    }

    @MainActor
    func testIdentifiedCommandsReorderAcrossGroupsWithoutRecreation() throws {
        _ = NSApplication.shared
        let first = FluentCommandBarItem(id: "a", "First") {}
        let second = FluentCommandBarItem(id: "b", "Second") {}
        let bar = FluentCommandBar(primaryCommands: [first], secondaryCommands: [second])
        let window = window(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        let a = bar.primaryCommandViews[0], b = bar.secondaryCommandViews[0]
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        var changes: [Bool] = []
        bar.onIsOpenChanged = { changes.append($0) }
        bar.setCommands(primary: [], secondary: [first, second])
        XCTAssertTrue(bar.secondaryCommandViews[0] === a)
        XCTAssertTrue(bar.secondaryCommandViews[1] === b)
        XCTAssertTrue(panel.firstResponder === b)
        bar.setCommands(primary: [], secondary: [second, first])
        XCTAssertTrue(bar.secondaryCommandViews[0] === b)
        XCTAssertTrue(bar.secondaryCommandViews[1] === a)
        XCTAssertTrue(panel.firstResponder === b)
        XCTAssertLessThan(b.frame.minY, a.frame.minY)
        bar.setCommands(primary: [first], secondary: [second])
        XCTAssertTrue(bar.primaryCommandViews[0] === a)
        XCTAssertTrue(a.superview === bar)
        XCTAssertTrue(panel.firstResponder === b)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(changes.isEmpty)
    }

    @MainActor
    func testLiveCommandsUseLatestTitleActionStateAndPopupWidth() throws {
        _ = NSApplication.shared
        var calls: [String] = []
        var toggleValues: [Bool] = []
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [
            FluentCommandBarItem(id: "a", "Old") { calls.append("old") },
            .toggle(id: "b", "Old toggle", isOn: false) { toggleValues.append($0) }
        ])
        let window = window(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let oldWidth = panel.frame.width
        let action = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarButton)
        let toggle = try XCTUnwrap(bar.secondaryCommandViews[1] as? FluentAppBarToggleButton)
        bar.secondaryCommands = [
            FluentCommandBarItem(id: "a", "A much longer replacement command title", keyEquivalent: "k") { calls.append("new") },
            .toggle(id: "b", "New toggle", isOn: true) { toggleValues.append($0) }
        ]
        XCTAssertTrue(toggle.isChecked)
        XCTAssertTrue(toggleValues.isEmpty, "Updating model state must not invoke a user action")
        XCTAssertEqual(toggle.label, "New toggle")
        XCTAssertGreaterThan(panel.frame.width, oldWidth)
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertTrue(bar.secondaryCommandViews[0] === action)
        XCTAssertEqual(action.keyboardAcceleratorTextOverride, "⌘K")
        action.invokeAction()
        XCTAssertEqual(calls, ["new"])
        XCTAssertFalse(bar.isOpen)
        toggle.invokeAction()
        toggle.invokeAction()
        XCTAssertEqual(toggleValues, [false, true])
    }

    @MainActor
    func testDisabledRemovedAndReplacedCommandsRecoverFocus() throws {
        _ = NSApplication.shared
        let a = FluentCommandBarItem(id: "a", "First") {}
        let b = FluentCommandBarItem(id: "b", "Second") {}
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [a, b])
        let window = window(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let first = bar.secondaryCommandViews[0]
        XCTAssertTrue(panel.firstResponder === first)
        bar.secondaryCommands = [FluentCommandBarItem(id: "a", "Disabled", isEnabled: false) {}, b]
        XCTAssertTrue(bar.secondaryCommandViews[0] === first)
        XCTAssertTrue(panel.firstResponder === bar.secondaryCommandViews[1])
        bar.secondaryCommands = [.toggle(id: "b", "Replacement", isOn: true) { _ in }]
        let replacement = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarToggleButton)
        XCTAssertTrue(panel.firstResponder === replacement)
        XCTAssertNil(first.superview)
        bar.secondaryCommands = []
        XCTAssertTrue(bar.isOpen, "An expanded bar can have no overflow rows")
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        bar.secondaryCommands = [a]
        XCTAssertTrue(bar.isOpen)
        XCTAssertTrue(window.childWindows?.first?.firstResponder === bar.secondaryCommandViews[0])
    }

    @MainActor
    func testAnimatedCloseCannotStealControlsFromReopenedPopup() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: [FluentCommandBarItem("Primary") {}],
            secondaryCommands: [FluentCommandBarItem("Secondary") {}])
        let window = window(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        bar.reduceMotion = false
        bar.setOpen(true, animated: false)
        bar.setOpen(false, animated: true)
        bar.setOpen(true, animated: false)
        let reopened = try XCTUnwrap(bar.secondaryCommandViews[0].window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertTrue(bar.isOpen)
        XCTAssertTrue(bar.secondaryCommandViews[0].window === reopened)
        XCTAssertTrue(reopened.firstResponder === bar.secondaryCommandViews[0])
        XCTAssertEqual(window.childWindows?.count, 1)
    }

    @MainActor
    func testAnimatedCloseRemovesPanelAfterItsCommandBarDetaches() {
        _ = NSApplication.shared
        var bar: FluentCommandBar? = FluentCommandBar(primaryCommands: [],
            secondaryCommands: [FluentCommandBarItem("Secondary") {}])
        let window = window(bar!)
        defer { window.close() }
        bar!.reduceMotion = false
        bar!.setOpen(true, animated: false)
        bar!.setOpen(false, animated: true)
        bar!.removeFromSuperview()
        bar = nil
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    @MainActor
    func testFocusedPrimaryKeepsKeyboardFocusAcrossOverflowMoves() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: (0..<4).map { FluentCommandBarItem("Command \($0)") {} },
            secondaryCommands: [FluentCommandBarItem("Settings") {}])
        let window = window(bar, width: 200)
        defer { bar.setOpen(false, animated: false); window.close() }
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let command = bar.primaryCommandViews[3]
        panel.makeFirstResponder(command)
        bar.setFrameSize(NSSize(width: 360, height: 64))
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.firstResponder === command)
        if NSApp.isActive { XCTAssertTrue(window.isKeyWindow) }
        bar.setFrameSize(NSSize(width: 160, height: 64))
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(panel.firstResponder === command)
        if NSApp.isActive { XCTAssertTrue(panel.isKeyWindow) }
        XCTAssertTrue(bar.isOpen)
    }

    @MainActor
    func testLiveRefreshPreservesTheDeviceUsedToOpenOverflow() throws {
        _ = NSApplication.shared
        let command = FluentCommandBarItem("Settings") {}
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [command])
        let window = window(bar)
        defer { bar.setOpen(false, animated: false); window.close() }
        FluentInputDeviceTracker.shared.record(.touch, in: window)
        bar.setOpen(true, animated: false)
        let panel = try XCTUnwrap(window.childWindows?.first)
        FluentInputDeviceTracker.shared.record(.mouse, in: window)
        bar.secondaryCommands = [command, FluentCommandBarItem("Help") {}]
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertEqual(bar.overflowInputDeviceType, .touch)
        XCTAssertEqual(bar.overflowRowHeight, 48)
    }

    @MainActor
    func testResizeWhileOpenPreservesPanelAndFocusedSecondaryInBothDirections() throws {
        _ = NSApplication.shared
        for direction in [NSUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            let bar = FluentCommandBar(primaryCommands: (0..<4).map { FluentCommandBarItem("Command \($0)") {} },
                secondaryCommands: [FluentCommandBarItem("Settings") {}])
            bar.userInterfaceLayoutDirection = direction
            let window = window(bar, width: 200)
            defer { bar.setOpen(false, animated: false); window.close() }
            bar.setOpen(true, animated: false)
            let panel = try XCTUnwrap(window.childWindows?.first)
            let focused = bar.secondaryCommandViews[0]
            let separator = try XCTUnwrap(focused.superview?.subviews.first { $0 is FluentAppBarSeparator })
            panel.makeFirstResponder(focused)
            var openEvents: [Bool] = []
            bar.onIsOpenChanged = { openEvents.append($0) }
            for width: CGFloat in [360, 160, 400, 200] {
                bar.setFrameSize(NSSize(width: width, height: 64))
                bar.layoutSubtreeIfNeeded()
                XCTAssertTrue(window.childWindows?.first === panel)
                XCTAssertTrue(panel.firstResponder === focused)
                let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
                XCTAssertEqual(host.revealMaskLayer.frame, host.animationRoot.bounds,
                    "Growing the live popup must not leave new rows outside the entrance clip")
                for index in bar.overflowedPrimaryIndexes {
                    XCTAssertTrue(bar.primaryCommandViews[index].window === panel)
                    XCTAssertFalse(bar.primaryCommandViews[index].isHidden)
                }
                if !bar.overflowedPrimaryIndexes.isEmpty {
                    XCTAssertTrue(focused.superview?.subviews.contains { $0 === separator } == true)
                }
                for index in bar.visiblePrimaryIndexes {
                    XCTAssertTrue(bar.primaryCommandViews[index].superview === bar)
                    XCTAssertFalse(bar.primaryCommandViews[index].isHidden)
                }
            }
            XCTAssertTrue(openEvents.isEmpty)
        }
    }
}
