import XCTest
@testable import FluentKit

@MainActor
final class CommandFlyoutUpdateTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let owner = FluentButton(title: "Commands")
        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 120, y: 180, width: 600, height: 340),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            owner.frame = NSRect(x: 120, y: 160, width: 200, height: 40)
            owner.reduceMotion = true
            window.contentView!.addSubview(owner)
            window.makeKeyAndOrderFront(nil)
        }
        func close() { owner.commandBarFlyoutConfiguration = nil; window.close() }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func button(_ title: String, in panel: NSWindow) throws -> NSButton {
            try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSButton }
                .first { $0.accessibilityTitle() == title })
        }
        func open(_ configuration: FluentCommandBarFlyoutConfiguration) throws -> NSWindow {
            owner.commandBarFlyoutConfiguration = configuration
            owner.performClick(nil)
            waitForUI(window.childWindows?.isEmpty == false)
            return try XCTUnwrap(window.childWindows?.first)
        }
    }

    func testSecondaryUpdatePreservesItsPanelAndRowButReplacesContentAndAction() throws {
        let f = Fixture(); defer { f.close() }
        var oldCalls = 0, newCalls = 0
        let panel = try f.open(.init(primaryCommands: [], secondaryCommands: [
            .init(id: "run", "Old") { oldCalls += 1 }]))
        let row = try f.button("Old", in: panel)
        let width = panel.frame.width
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [], secondaryCommands: [
            .init(id: "run", "A longer replacement command", keyEquivalent: "n") { newCalls += 1 }])
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertTrue(try f.button("A longer replacement command", in: panel) === row)
        XCTAssertGreaterThan(panel.frame.width, width)
        XCTAssertTrue(row.accessibilityHelp()?.contains("⌘N") == true)
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
        XCTAssertFalse(panel.isVisible)
    }

    func testPrimaryEnablementAndActionUpdateInPlace() throws {
        let f = Fixture(); defer { f.close() }
        var oldCalls = 0, newCalls = 0
        let panel = try f.open(.init(primaryCommands: [.init(id: 1, "Run") { oldCalls += 1 }]))
        let button = try f.button("Run", in: panel)
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [.init(id: 1, "Run", isEnabled: false) {}])
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(button.accessibilityPerformPress())
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [.init(id: 1, "New") { newCalls += 1 }])
        XCTAssertTrue(try f.button("New", in: panel) === button)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
        XCTAssertTrue(f.window.childWindows?.first === panel)
    }

    func testPrimaryCallbackCanPublishItsNextConfiguration() throws {
        let f = Fixture(); defer { f.close() }
        var oldCalls = 0, newCalls = 0
        let updated = FluentCommandBarFlyoutConfiguration(primaryCommands: [.init(id: 1, "New") { newCalls += 1 }])
        let panel = try f.open(.init(primaryCommands: [.init(id: 1, "Old") {
            oldCalls += 1
            f.owner.commandBarFlyoutConfiguration = updated
        }]))
        let button = try f.button("Old", in: panel)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertTrue(try f.button("New", in: panel) === button)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 1)
        XCTAssertEqual(newCalls, 1)
        XCTAssertTrue(f.window.childWindows?.first === panel)
    }

    func testPrimaryCallbackCanRemoveItselfWithoutRevivingItsInput() throws {
        let f = Fixture(); defer { f.close() }
        var calls = 0
        weak var removed: NSButton?
        var reentry: Bool?
        let panel = try f.open(.init(primaryCommands: [.init(id: 1, "Remove") {
            calls += 1
            f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [.init(id: 2, "Replacement") {}])
            reentry = removed?.accessibilityPerformPress()
        }]))
        let old = try f.button("Remove", in: panel)
        removed = old
        XCTAssertTrue(panel.makeFirstResponder(old))
        XCTAssertTrue(old.accessibilityPerformPress())
        let replacement = try f.button("Replacement", in: panel)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertTrue(panel.firstResponder === replacement)
        XCTAssertFalse(old.accessibilityPerformPress())
        XCTAssertEqual(reentry, false)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(replacement.accessibilityPerformPress())
    }

    func testToggleCallbackCanOverrideTheValueAndFutureAction() throws {
        let f = Fixture(); defer { f.close() }
        var oldValues: [Bool] = [], newValues: [Bool] = []
        let panel = try f.open(.init(primaryCommands: [.toggle(id: 1, "Toggle", isOn: false) { value in
            oldValues.append(value)
            f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [
                .toggle(id: 1, "Toggle", isOn: false) { newValues.append($0) }])
        }]))
        let toggle = try f.button("Toggle", in: panel)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(toggle.accessibilityValue() as? String, "Off")
        XCTAssertTrue(try f.button("Toggle", in: panel) === toggle)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(toggle.accessibilityValue() as? String, "On")
        XCTAssertEqual(oldValues, [true])
        XCTAssertEqual(newValues, [true])
    }

    func testConfigurationUpdateSettlesPendingEntranceAndActiveExpansion() throws {
        let f = Fixture(); defer { f.close() }
        let primary = [FluentCommandBarItem(id: 1, "Primary") {}]
        let secondary = [FluentCommandBarItem(id: 2, "Secondary") {}]
        let flyout = FluentCommandBarFlyout(primaryCommands: primary, secondaryCommands: secondary,
                                          reduceMotion: false)
        defer { flyout.dismiss() }
        flyout.present(relativeTo: f.owner)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let layer = try XCTUnwrap(panel.contentView?.layer)
        XCTAssertEqual(layer.opacity, 0)
        flyout.update(configuration: .init(primaryCommands: primary, secondaryCommands: secondary))
        XCTAssertEqual(layer.opacity, 1)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertTrue(layer.animationKeys()?.isEmpty != false)
        XCTAssertTrue(try f.button("More", in: panel).accessibilityPerformPress())
        XCTAssertNotNil(layer.mask)
        let row = try f.button("Secondary", in: panel)
        flyout.update(configuration: .init(primaryCommands: primary, secondaryCommands: [
            .init(id: 2, "A wider secondary command") {}], alwaysExpanded: true))
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertTrue(try f.button("A wider secondary command", in: panel) === row)
        XCTAssertNil(layer.mask)
        XCTAssertEqual(layer.opacity, 1)
        let frame = panel.frame
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertNil(layer.mask)
        XCTAssertTrue(layer.animationKeys()?.isEmpty != false)
    }

    func testIncomingToggleValueOverridesTheRetainedValueAndUsesTheNewCallback() throws {
        let f = Fixture(); defer { f.close() }
        var oldValues: [Bool] = [], newValues: [Bool] = []
        let panel = try f.open(.init(primaryCommands: [.toggle(id: 1, "Toggle", isOn: false) { oldValues.append($0) }]))
        let button = try f.button("Toggle", in: panel)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(button.accessibilityValue() as? String, "On")
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [
            .toggle(id: 1, "Toggle", isOn: false) { newValues.append($0) }])
        XCTAssertTrue(try f.button("Toggle", in: panel) === button)
        XCTAssertEqual(button.accessibilityValue() as? String, "Off")
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(oldValues, [true])
        XCTAssertEqual(newValues, [true])
    }

    func testReorderRetainsPrimaryAndSecondaryControlsAndTheirFocus() throws {
        let f = Fixture(); defer { f.close() }
        let a = FluentCommandBarItem(id: "a", "A") {}, b = FluentCommandBarItem(id: "b", "B") {}
        let c = FluentCommandBarItem(id: "c", "C") {}, d = FluentCommandBarItem(id: "d", "D") {}
        let panel = try f.open(.init(primaryCommands: [a, .separator(id: "divider"), b],
                                    secondaryCommands: [c, d], alwaysExpanded: true))
        let old = try ["A", "B", "C", "D"].map { try f.button($0, in: panel) }
        let separator = try XCTUnwrap(f.all(panel.contentView!).first {
            $0.identifier?.rawValue == "FluentKit.CommandBarFlyout.Separator"
        })
        XCTAssertTrue(panel.makeFirstResponder(old[2]))
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [b, .separator(id: "divider"), a],
            secondaryCommands: [d, c], alwaysExpanded: true)
        for (title, button) in zip(["A", "B", "C", "D"], old) {
            XCTAssertTrue(try f.button(title, in: panel) === button)
        }
        XCTAssertNotNil(separator.superview)
        XCTAssertLessThan(old[1].frame.minX, old[0].frame.minX)
        XCTAssertLessThan(old[3].frame.minY, old[2].frame.minY)
        XCTAssertTrue(panel.firstResponder === old[2])
    }

    func testRemovingCommandsRetiresTheirInputAndMovesFocusToAnEnabledCommand() throws {
        let f = Fixture(); defer { f.close() }
        var removedCalls = 0
        let panel = try f.open(.init(primaryCommands: [.init(id: "remove", "Remove") { removedCalls += 1 }],
            secondaryCommands: [.init(id: "keep", "Keep") {}, .init(id: "old", "Old row") { removedCalls += 1 }], alwaysExpanded: true))
        let removed = try f.button("Remove", in: panel), oldRow = try f.button("Old row", in: panel)
        let retained = try f.button("Keep", in: panel)
        XCTAssertTrue(panel.makeFirstResponder(removed))
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [], secondaryCommands: [.init(id: "keep", "Keep") {}])
        XCTAssertFalse(removed.accessibilityPerformPress())
        XCTAssertFalse(oldRow.accessibilityPerformPress())
        XCTAssertNil(removed.superview)
        XCTAssertNil(oldRow.superview)
        XCTAssertTrue(try f.button("Keep", in: panel) === retained)
        XCTAssertTrue(panel.firstResponder === retained)
        XCTAssertEqual(removedCalls, 0)
    }

    func testMovingBetweenCommandGroupsTransfersFocusAndRetiresThePreviousTemplate() throws {
        let f = Fixture(); defer { f.close() }
        var values: [Bool] = []
        let toggle = FluentCommandBarItem.toggle(id: "move", "Toggle", isOn: true) { values.append($0) }
        let panel = try f.open(.init(primaryCommands: [toggle], secondaryCommands: [.init(id: "stay", "Stay") {}], alwaysExpanded: true))
        let primary = try f.button("Toggle", in: panel)
        XCTAssertTrue(panel.makeFirstResponder(primary))
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [], secondaryCommands: [toggle, .init(id: "stay", "Stay") {}])
        let row = try f.button("Toggle", in: panel)
        XCTAssertFalse(row === primary)
        XCTAssertFalse(primary.accessibilityPerformPress())
        XCTAssertTrue(panel.firstResponder === row)
        XCTAssertEqual(row.accessibilityValue() as? String, "On")
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(values, [false])
        XCTAssertFalse(panel.isVisible)
    }

    func testAlwaysExpandedUpdatesGeometryAndMoreWithoutReopening() throws {
        let f = Fixture(); defer { f.close() }
        let primary = [FluentCommandBarItem(id: 1, "Primary") {}], secondary = [FluentCommandBarItem(id: 2, "Secondary") {}]
        let panel = try f.open(.init(primaryCommands: primary, secondaryCommands: secondary))
        let oldMore = try f.button("More", in: panel)
        let collapsedHeight = panel.frame.height
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: primary, secondaryCommands: secondary, alwaysExpanded: true)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertGreaterThan(panel.frame.height, collapsedHeight)
        XCTAssertNil(oldMore.superview)
        XCTAssertFalse(oldMore.accessibilityPerformPress())
        let row = try f.button("Secondary", in: panel)
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: primary, secondaryCommands: secondary, alwaysExpanded: false)
        XCTAssertTrue(try f.button("Secondary", in: panel) === row)
        XCTAssertTrue(try f.button("More", in: panel).accessibilityPerformPress())
        XCTAssertEqual(panel.frame.height, collapsedHeight, accuracy: 0.01)
        XCTAssertFalse(row.accessibilityPerformPress())
    }

    func testSecondaryCallbackUpdateDoesNotReviveItsConsumedPresentation() throws {
        let f = Fixture(); defer { f.close() }
        var oldCalls = 0, newCalls = 0
        weak var oldRow: NSButton?
        var reentry: Bool?
        let updated = FluentCommandBarFlyoutConfiguration(primaryCommands: [], secondaryCommands: [
            .init(id: 1, "New") { newCalls += 1 }])
        let original = FluentCommandBarFlyoutConfiguration(primaryCommands: [], secondaryCommands: [.init(id: 1, "Old") {
            oldCalls += 1
            f.owner.commandBarFlyoutConfiguration = updated
            reentry = oldRow?.accessibilityPerformPress()
        }])
        let panel = try f.open(original)
        oldRow = try f.button("Old", in: panel)
        XCTAssertTrue(oldRow!.accessibilityPerformPress())
        XCTAssertEqual(reentry, false)
        XCTAssertFalse(panel.isVisible)
        let reopened = try f.open(updated)
        XCTAssertTrue(try f.button("New", in: reopened).accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 1)
        XCTAssertEqual(newCalls, 1)
    }

    func testDirectUpdateBeforePresentationPublishesConfigurationAndClosesOnlyOnceWhenEmpty() throws {
        let f = Fixture(); defer { f.close() }
        var calls = 0, dismissals = 0
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init(id: 1, "Old") {}], reduceMotion: true)
        defer { flyout.onDismiss = nil; flyout.dismiss() }
        flyout.onDismiss = { dismissals += 1 }
        flyout.update(configuration: .init(primaryCommands: [.init(id: 2, "New") { calls += 1 }], alwaysExpanded: true))
        XCTAssertFalse(flyout.isPresented)
        XCTAssertEqual(flyout.primaryCommands.map(\.title), ["New"])
        XCTAssertTrue(flyout.alwaysExpanded)
        flyout.present(relativeTo: f.owner)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let button = try f.button("New", in: panel)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(calls, 1)
        flyout.update(configuration: .init(primaryCommands: []))
        XCTAssertFalse(flyout.isPresented)
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertEqual(dismissals, 1)
        flyout.update(configuration: .init(primaryCommands: [.separator], secondaryCommands: [.separator]))
        flyout.present(relativeTo: f.owner)
        XCTAssertFalse(flyout.isPresented)
        XCTAssertEqual(dismissals, 1)
    }

    func testEmptyUpdateAllowsDismissCallbackToConfigureAndOpenAReplacement() throws {
        let f = Fixture(); defer { f.close() }
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init(id: 1, "Old") {}], reduceMotion: true)
        defer { flyout.onDismiss = nil; flyout.dismiss() }
        var dismissals = 0
        flyout.onDismiss = {
            dismissals += 1
            flyout.update(configuration: .init(primaryCommands: [.init(id: 2, "Replacement") {}]))
            flyout.present(relativeTo: f.owner)
        }
        flyout.present(relativeTo: f.owner)
        let old = try XCTUnwrap(f.window.childWindows?.first)
        let oldButton = try f.button("Old", in: old)
        flyout.update(configuration: .init(primaryCommands: []))
        let replacement = try XCTUnwrap(f.window.childWindows?.first)
        XCTAssertFalse(replacement === old)
        XCTAssertTrue(flyout.isPresented)
        XCTAssertFalse(oldButton.accessibilityPerformPress())
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(flyout.primaryCommands.first?.title, "Replacement")
        XCTAssertTrue(try f.button("Replacement", in: replacement).accessibilityPerformPress())
    }

    func testDuplicateIDsAndPositionalFallbackHaveIndependentRetainedControls() throws {
        let f = Fixture(); defer { f.close() }
        var calls: [String] = []
        let panel = try f.open(.init(primaryCommands: [.init(id: "same", "One") {}, .init(id: "same", "Two") {}, .init("Position") {}],
            secondaryCommands: [.init("Row") {}], alwaysExpanded: true))
        let old = try ["One", "Two", "Position", "Row"].map { try f.button($0, in: panel) }
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [
            .init(id: "same", "First") { calls.append("first") },
            .init(id: "same", "Second") { calls.append("second") },
            .init("Positional") { calls.append("position") }
        ], secondaryCommands: [.init("Secondary") {}], alwaysExpanded: true)
        for (title, button) in zip(["First", "Second", "Positional", "Secondary"], old) {
            XCTAssertTrue(try f.button(title, in: panel) === button)
        }
        for button in old.prefix(3) { XCTAssertTrue(button.accessibilityPerformPress()) }
        XCTAssertEqual(calls, ["first", "second", "position"])
    }

    func testDisablingTheFocusedCommandMovesFocusWithoutExecutingIt() throws {
        let f = Fixture(); defer { f.close() }
        let panel = try f.open(.init(primaryCommands: [.init(id: 1, "Disable") {}, .init(id: 2, "Keep") {}]))
        let disable = try f.button("Disable", in: panel), keep = try f.button("Keep", in: panel)
        XCTAssertTrue(panel.makeFirstResponder(disable))
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [
            .init(id: 1, "Disable", isEnabled: false) {}, .init(id: 2, "Keep") {}])
        XCTAssertTrue(panel.firstResponder === keep)
        XCTAssertFalse(disable.accessibilityPerformPress())
        XCTAssertTrue(panel.isVisible)
    }

    func testReplacingACommandWithASeparatorDoesNotReviveItWhenTheIDReturns() throws {
        let f = Fixture(); defer { f.close() }
        let keep = FluentCommandBarItem(id: "keep", "Keep") {}
        let panel = try f.open(.init(primaryCommands: [.init(id: "change", "Old") {}, keep]))
        let old = try f.button("Old", in: panel)
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [.separator(id: "change"), keep])
        XCTAssertFalse(old.accessibilityPerformPress())
        XCTAssertNil(old.superview)
        f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: [.toggle(id: "change", "Toggle", isOn: false) { _ in }, keep])
        let toggle = try f.button("Toggle", in: panel)
        XCTAssertFalse(toggle === old)
        XCTAssertFalse(old.accessibilityPerformPress())
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(toggle.accessibilityValue() as? String, "On")
    }

    func testEmptyButtonConfigurationDoesNotLeaveAnInvisiblePresenter() throws {
        for separatorsOnly in [false, true] {
            let f = Fixture(); defer { f.close() }
            f.owner.commandBarFlyoutConfiguration = .init(primaryCommands: separatorsOnly ? [.separator] : [])
            f.owner.performClick(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            XCTAssertTrue(f.window.childWindows?.isEmpty != false)
            XCTAssertNotEqual(f.owner.accessibilityValue() as? String, "Open")
            let panel = try f.open(.init(primaryCommands: [.init("New") {}]))
            XCTAssertTrue(try f.button("New", in: panel).accessibilityPerformPress())
        }
    }
}
