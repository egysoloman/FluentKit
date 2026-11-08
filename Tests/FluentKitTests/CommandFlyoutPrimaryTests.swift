import XCTest
@testable import FluentKit

@MainActor
final class CommandFlyoutPrimaryTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let anchor = NSView(frame: NSRect(x: 80, y: 120, width: 320, height: 32))
        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 120, y: 180, width: 600, height: 340),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView!.addSubview(anchor)
            window.makeKeyAndOrderFront(nil)
        }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func button(_ title: String, in panel: NSWindow) throws -> NSButton {
            try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSButton }
                .first { $0.accessibilityTitle() == title })
        }
        func open(_ flyout: FluentCommandBarFlyout) throws -> NSWindow {
            flyout.present(relativeTo: anchor)
            return try XCTUnwrap(window.childWindows?.first)
        }
        func click(_ button: NSButton, at point: NSPoint, releaseAt end: NSPoint? = nil) throws {
            let panel = try XCTUnwrap(button.window)
            panel.styleMask.insert(.nonactivatingPanel)
            panel.makeKeyAndOrderFront(nil)
            XCTAssertTrue(panel.isKeyWindow)
            let time = ProcessInfo.processInfo.systemUptime
            func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: button.convert(point, to: nil),
                    modifierFlags: [], timestamp: time, windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            }
            // NSButton's native mouse tracking consumes the queued release synchronously.
            let up = try event(.leftMouseUp, at: end ?? point)
            NSApp.postEvent(up, atStart: true)
            if let end { NSApp.postEvent(try event(.leftMouseDragged, at: end), atStart: true) }
            NSApp.sendEvent(try event(.leftMouseDown, at: point))
            // Recent AppKit versions track an un-overridden NSButton asynchronously. Deliver
            // our remaining drag/release events too; queueing them alone only drives the legacy
            // synchronous path used by buttons that override mouseDown.
            let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
            let deadline = Date(timeIntervalSinceNow: 0.05)
            while Date() < deadline, let queued = NSApp.nextEvent(matching: mask, until: deadline,
                                                                 inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    func testPrimaryActionCanRepeatWithoutClosingOrReplacingItsPanel() throws {
        let f = Fixture(); defer { f.window.close() }
        var calls = 0, dismissals = 0
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init("Run") { calls += 1 }], reduceMotion: true)
        defer { flyout.onDismiss = nil; flyout.dismiss() }
        flyout.onDismiss = { dismissals += 1 }
        let panel = try f.open(flyout)
        let button = try f.button("Run", in: panel)
        for count in 1...3 {
            XCTAssertTrue(button.accessibilityPerformPress())
            XCTAssertEqual(calls, count)
            XCTAssertEqual(dismissals, 0)
            XCTAssertTrue(flyout.isPresented)
            XCTAssertTrue(f.window.childWindows?.first === panel)
        }
    }

    func testPrimaryTogglePublishesNewStateBeforeTheCallbackAndRetainsItOnReopen() throws {
        for initiallyOn in [false, true] {
            let f = Fixture(); defer { f.window.close() }
            var values: [Bool] = [], accessibilityValues: [String?] = []
            weak var button: NSButton?
            let flyout = FluentCommandBarFlyout(primaryCommands: [.toggle("Toggle", isOn: initiallyOn) {
                values.append($0)
                accessibilityValues.append(button?.accessibilityValue() as? String)
            }], reduceMotion: true)
            defer { flyout.dismiss() }
            let panel = try f.open(flyout)
            button = try f.button("Toggle", in: panel)
            XCTAssertTrue(button!.accessibilityPerformPress())
            XCTAssertTrue(button!.accessibilityPerformPress())
            XCTAssertTrue(button!.accessibilityPerformPress())
            XCTAssertEqual(values, [!initiallyOn, initiallyOn, !initiallyOn])
            XCTAssertEqual(accessibilityValues, values.map { $0 ? "On" : "Off" })
            flyout.dismiss()
            let reopened = try f.open(flyout)
            button = try f.button("Toggle", in: reopened)
            XCTAssertEqual(button?.accessibilityValue() as? String, initiallyOn ? "Off" : "On")
            XCTAssertTrue(button!.accessibilityPerformPress())
            XCTAssertEqual(values.last, initiallyOn)
        }
    }

    func testSecondaryToggleClosesButKeepsItsValueForTheNextPresentation() throws {
        let f = Fixture(); defer { f.window.close() }
        var values: [Bool] = [], dismissals = 0
        var widths: [CGFloat] = []
        let flyout = FluentCommandBarFlyout(primaryCommands: [], secondaryCommands: [
            .toggle("Toggle", isOn: false) { values.append($0) }], reduceMotion: true)
        defer { flyout.onDismiss = nil; flyout.dismiss() }
        flyout.onDismiss = { dismissals += 1 }
        for _ in 0..<2 {
            let panel = try f.open(flyout)
            widths.append(panel.frame.width)
            XCTAssertTrue(try f.button("Toggle", in: panel).accessibilityPerformPress())
            XCTAssertFalse(flyout.isPresented)
        }
        XCTAssertEqual(values, [true, false])
        XCTAssertEqual(dismissals, 2)
        XCTAssertEqual(widths[0], widths[1], "Reserve check space even while a toggle is off")
    }

    func testPrimaryActionCanExplicitlyDismissAndRetireItsOldButton() throws {
        let f = Fixture(); defer { f.window.close() }
        var flyout: FluentCommandBarFlyout!
        var calls = 0, dismissals = 0
        flyout = FluentCommandBarFlyout(primaryCommands: [.init("Close") {
            calls += 1; flyout.dismiss()
        }], reduceMotion: true)
        defer { flyout.onDismiss = nil; flyout.dismiss(); flyout = nil }
        flyout.onDismiss = { dismissals += 1 }
        let panel = try f.open(flyout)
        let button = try f.button("Close", in: panel)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertFalse(flyout.isPresented)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(dismissals, 1)
    }

    func testPrimaryCallbackCanReplaceItsPanelAndRetireTheOldButton() throws {
        let f = Fixture(); defer { f.window.close() }
        var flyout: FluentCommandBarFlyout!
        var calls = 0
        flyout = FluentCommandBarFlyout(primaryCommands: [.init("Replace") {
            calls += 1; flyout.present(relativeTo: f.anchor)
        }], reduceMotion: true)
        defer { flyout.dismiss(); flyout = nil }
        let old = try f.open(flyout)
        let button = try f.button("Replace", in: old)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(flyout.isPresented)
        XCTAssertFalse(f.window.childWindows?.first === old)
    }

    func testRetainedPrimaryCallbackRejectsReentryThenAcceptsTheNextInvocation() throws {
        let f = Fixture(); defer { f.window.close() }
        var calls = 0, reentries: [Bool] = []
        weak var button: NSButton?
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init("Run") {
            calls += 1
            if calls < 4 { reentries.append(button?.accessibilityPerformPress() ?? false) }
        }], reduceMotion: true)
        defer { flyout.dismiss() }
        let panel = try f.open(flyout)
        button = try f.button("Run", in: panel)
        XCTAssertTrue(button!.accessibilityPerformPress())
        XCTAssertTrue(button!.accessibilityPerformPress())
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(reentries, [false, false])
        XCTAssertTrue(flyout.isPresented)
    }

    func testPrimaryCallbackCannotReenterAPeerOrToggleOverflow() throws {
        let f = Fixture(); defer { f.window.close() }
        weak var peer: NSButton?, more: NSButton?
        var accepted: [Bool] = [], peerCalls = 0
        let flyout = FluentCommandBarFlyout(primaryCommands: [
            .init("Run") { accepted = [peer?.accessibilityPerformPress() ?? true, more?.accessibilityPerformPress() ?? true] },
            .init("Peer") { peerCalls += 1 }
        ], secondaryCommands: [.init("Secondary") {}], reduceMotion: true)
        defer { flyout.dismiss() }
        let panel = try f.open(flyout)
        peer = try f.button("Peer", in: panel); more = try f.button("More", in: panel)
        XCTAssertTrue(try f.button("Run", in: panel).accessibilityPerformPress())
        XCTAssertEqual(accepted, [false, false])
        XCTAssertEqual(peerCalls, 0)
        XCTAssertTrue(peer!.accessibilityPerformPress())
        XCTAssertEqual(peerCalls, 1)
        XCTAssertTrue(more!.accessibilityPerformPress())
        XCTAssertTrue(try f.button("Secondary", in: panel).accessibilityPerformPress())
        XCTAssertFalse(flyout.isPresented)
    }

    func testDisabledPrimaryDoesNotExecuteOrClose() throws {
        let f = Fixture(); defer { f.window.close() }
        var calls = 0
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init("Disabled", isEnabled: false) { calls += 1 }], reduceMotion: true)
        defer { flyout.dismiss() }
        let panel = try f.open(flyout)
        XCTAssertFalse(try f.button("Disabled", in: panel).accessibilityPerformPress())
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(flyout.isPresented)
    }

    func testMouseClickInvokesTheWholeCommandSurfaceWithOrWithoutAnIcon() throws {
        for primary in [false, true] { for image in [nil, "star"] as [String?] { for edge in [false, true] {
            let f = Fixture(); defer { f.window.close() }
            var calls = 0
            let command = FluentCommandBarItem("Run", systemImageName: image) { calls += 1 }
            let flyout = FluentCommandBarFlyout(primaryCommands: primary ? [command] : [],
                secondaryCommands: primary ? [] : [command], reduceMotion: true)
            defer { flyout.dismiss() }
            let panel = try f.open(flyout)
            let button = try f.button("Run", in: panel)
            let point = NSPoint(x: edge ? 1 : button.bounds.midX, y: button.bounds.midY)
            try f.click(button, at: point)
            waitForUI(calls == 1)
            XCTAssertEqual(calls, 1, "primary=\(primary), image=\(image ?? "nil"), edge=\(edge)")
            XCTAssertEqual(flyout.isPresented, primary, "primary=\(primary), image=\(image ?? "nil"), edge=\(edge)")
            if primary {
                try f.click(button, at: point)
                XCTAssertEqual(calls, 2)
            }
        } } }
    }

    func testMousePressDraggedOutsideDoesNotExecuteOrDismiss() throws {
        for primary in [false, true] {
            let f = Fixture(); defer { f.window.close() }
            var calls = 0
            let command = FluentCommandBarItem("Run") { calls += 1 }
            let flyout = FluentCommandBarFlyout(primaryCommands: primary ? [command] : [],
                secondaryCommands: primary ? [] : [command], reduceMotion: true)
            defer { flyout.dismiss() }
            let panel = try f.open(flyout)
            let button = try f.button("Run", in: panel)
            try f.click(button, at: NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                        releaseAt: NSPoint(x: button.bounds.maxX + 20, y: button.bounds.midY))
            XCTAssertEqual(calls, 0)
            XCTAssertFalse(button.isHighlighted, "primary=\(primary)")
            XCTAssertTrue(flyout.isPresented)
        }
    }

    func testRefreshingCommandsRetainsSurvivingButtonsAndRetiresRemovedCommands() throws {
        let f = Fixture(); defer { f.window.close() }
        var commands: [FluentTextCommand] = [], calls = 0
        let remaining = FluentTextCommand(kind: .copy, title: "Remaining", accelerator: "",
            systemImageName: "star", action: { calls += 1 }, isPrimary: true)
        commands = [FluentTextCommand(kind: .cut, title: "Remove", accelerator: "",
            systemImageName: "scissors", action: { commands = [remaining] }, isPrimary: true), remaining]
        let flyout = FluentTextCommandFlyout(commands: commands, theme: .current,
            reduceMotion: true, refreshCommands: { commands })
        defer { flyout.dismiss(animated: false) }
        flyout.present(relativeTo: f.anchor, at: .zero)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let remove = try f.button("Remove", in: panel)
        let retained = try f.button("Remaining", in: panel)
        XCTAssertTrue(remove.accessibilityPerformPress())
        XCTAssertNil(remove.superview)
        XCTAssertFalse(remove.accessibilityPerformPress())
        XCTAssertTrue(try f.button("Remaining", in: panel) === retained)
        XCTAssertEqual(panel.frame.width, 56, accuracy: 0.01)
        XCTAssertTrue(retained.accessibilityPerformPress())
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(flyout.isPresented)
    }

    func testRefreshingCommandsSettlesAnInFlightExpansionAndKeepsOverflowExpanded() throws {
        let f = Fixture(); defer { f.window.close() }
        let primary = FluentTextCommand(kind: .copy, title: "Refresh", accelerator: "",
            systemImageName: "star", action: {}, isPrimary: true)
        let secondary = FluentTextCommand(kind: .selectAll, title: "Secondary", accelerator: "",
            systemImageName: nil, action: {}, isPrimary: false)
        let commands = [primary, secondary]
        let flyout = FluentTextCommandFlyout(commands: commands, theme: .current,
            reduceMotion: false, refreshCommands: { commands })
        defer { flyout.dismiss(animated: false) }
        flyout.present(relativeTo: f.anchor, at: .zero)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let more = try f.button("More", in: panel)
        XCTAssertTrue(more.accessibilityPerformPress())
        let oldSecondary = try f.button("Secondary", in: panel)
        let layer = try XCTUnwrap(panel.contentView?.layer)
        XCTAssertNotNil(layer.mask)
        XCTAssertTrue(try f.button("Refresh", in: panel).accessibilityPerformPress())
        XCTAssertNil(layer.mask)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertTrue(layer.animationKeys()?.isEmpty != false)
        XCTAssertFalse(oldSecondary.accessibilityPerformPress())
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertTrue(layer.animationKeys()?.isEmpty != false)
        XCTAssertTrue(try f.button("Secondary", in: panel).accessibilityPerformPress())
        XCTAssertFalse(flyout.isPresented)
    }

    func testPrimaryCallbackReplacementDoesNotRefreshTheNewPresentation() throws {
        let f = Fixture(); defer { f.window.close() }
        var flyout: FluentTextCommandFlyout!
        var refreshes = 0
        let command = FluentTextCommand(kind: .copy, title: "Replace", accelerator: "",
            systemImageName: "star", action: { flyout.present(relativeTo: f.anchor, at: .zero) }, isPrimary: true)
        flyout = FluentTextCommandFlyout(commands: [command], theme: .current,
            reduceMotion: true, refreshCommands: { refreshes += 1; return [] })
        defer { flyout.dismiss(animated: false); flyout = nil }
        flyout.present(relativeTo: f.anchor, at: .zero)
        let old = try XCTUnwrap(f.window.childWindows?.first)
        XCTAssertTrue(try f.button("Replace", in: old).accessibilityPerformPress())
        XCTAssertEqual(refreshes, 0)
        XCTAssertTrue(flyout.isPresented)
        XCTAssertFalse(f.window.childWindows?.first === old)
    }

    func testTouchTextCommandsRefreshAfterCutAndKeepTheNativeEditor() throws {
        let f = Fixture(); defer { f.window.close() }
        let previousDevice = FluentInputDeviceTracker.shared.lastDeviceType
        defer {
            // Detached controls use the process-wide fallback; do not leak simulated touch
            // into later pointer tests. `.none` is not a recordable device, so use mouse then.
            FluentInputDeviceTracker.shared.record(previousDevice == .none ? .mouse : previousDevice, in: nil)
        }
        // Preserve all pasteboard representations, including rich text and image data.
        let saved = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            NSPasteboard.general.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem(); entries.forEach { item.setData($0.1, forType: $0.0) }; return item
            }
            NSPasteboard.general.writeObjects(items)
        }
        NSPasteboard.general.clearContents()
        let field = FluentTextField()
        field.frame = f.anchor.bounds; field.stringValue = "abc def"
        f.anchor.addSubview(field); field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        FluentInputDeviceTracker.shared.record(.touch, in: f.window)
        let event = try XCTUnwrap(NSEvent.otherEvent(with: .applicationDefined,
            location: field.convert(NSPoint(x: 40, y: 16), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: f.window.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0))
        field.rightMouseDown(with: event)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let cut = try f.button(field.fluentControlString("Cut"), in: panel)
        XCTAssertTrue(cut.accessibilityPerformPress())
        XCTAssertEqual(editor.string, " def")
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertFalse(cut.accessibilityPerformPress())
        let paste = try f.button(field.fluentControlString("Paste"), in: panel)
        XCTAssertTrue(paste.accessibilityPerformPress())
        XCTAssertEqual(editor.string, "abc def")
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertTrue(try f.button("More", in: panel).accessibilityPerformPress())
        XCTAssertTrue(try f.button(field.fluentControlString("Select All"), in: panel).accessibilityPerformPress())
        XCTAssertTrue(f.window.childWindows?.isEmpty != false)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 7))
    }
}
