import XCTest
@testable import FluentKit

@MainActor
final class ToggleAccessibilityTests: XCTestCase {
    func testStandaloneSwitchExposesNativeSemanticsAndNumericState() {
        _ = NSApplication.shared
        let toggle = FluentToggle(title: "Automatic correction")
        let native = NSSwitch(frame: .zero)
        XCTAssertTrue(toggle.isAccessibilityElement())
        XCTAssertEqual(toggle.accessibilityRole(), native.accessibilityRole())
        XCTAssertEqual(toggle.accessibilitySubrole(), .switch)
        XCTAssertEqual(toggle.accessibilitySubrole(), native.accessibilitySubrole())
        XCTAssertEqual(toggle.accessibilityTitle(), "Automatic correction")
        XCTAssertEqual(toggle.accessibilityValue() as? NSNumber, 0)
        XCTAssertEqual(CFGetTypeID(toggle.accessibilityValue()! as CFTypeRef), CFNumberGetTypeID())
        var changes: [Bool] = []
        toggle.onValueChanged = { changes.append($0) }
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(toggle.accessibilityValue() as? NSNumber, 1)
        toggle.isOn = true
        XCTAssertEqual(changes, [true], "Unchanged assignment must not create another change")
        toggle.isEnabled = false
        XCTAssertFalse(toggle.isAccessibilityEnabled())
        XCTAssertFalse(toggle.accessibilityPerformPress())
        XCTAssertEqual(toggle.accessibilityValue() as? NSNumber, 1)
        XCTAssertEqual(changes, [true])
        toggle.isOn = false
        XCTAssertEqual(toggle.accessibilityValue() as? NSNumber, 0, "Disabled controls still reflect external values")
        toggle.title = "Renamed switch"
        XCTAssertEqual(toggle.accessibilityTitle(), "Renamed switch")
    }

    func testBoundSwitchExposesOneActionTargetAndPublishesOnlyOneChange() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: false)
        let bound = FluentBoundToggle(state.projectedValue, title: "Bound switch")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bound
        window.orderFront(nil)
        defer { window.close() }
        var changes: [Bool] = []
        let observer = state.projectedValue.observe? { changes.append($0) }
        changes.removeAll()
        defer { if let observer { state.projectedValue.removeObserver?(observer) } }
        XCTAssertFalse(bound.isAccessibilityElement())
        XCTAssertTrue(bound.toggle.isAccessibilityElement())
        XCTAssertTrue(bound.toggle.accessibilityPerformPress())
        XCTAssertTrue(state.wrappedValue)
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(bound.toggle.accessibilityValue() as? NSNumber, 1)
        state.wrappedValue = false
        XCTAssertEqual(bound.toggle.accessibilityValue() as? NSNumber, 0)
        XCTAssertEqual(changes, [true, false])
        XCTAssertTrue(bound.toggle.accessibilityPerformPress())
        XCTAssertEqual(changes, [true, false, true])
    }

    func testReconciledSwitchActsOnNewBindingAndPreservesItsAccessibleIdentity() throws {
        _ = NSApplication.shared
        let first = FluentState(wrappedValue: false)
        let second = FluentState(wrappedValue: true)
        let definition = FluentToggleView("First", isOn: first.projectedValue)
        let native = try XCTUnwrap(definition._makeView(in: .init(reduceMotion: true)) as? FluentBoundToggle)
        let original = native.toggle
        XCTAssertTrue(FluentToggleView("Second", isOn: second.projectedValue)
            ._updateView(native, in: .init(reduceMotion: true)))
        XCTAssertTrue(native.toggle === original)
        XCTAssertTrue(original.isAccessibilityElement())
        XCTAssertEqual(original.accessibilityTitle(), "Second")
        XCTAssertEqual(original.accessibilityValue() as? NSNumber, 1)
        XCTAssertTrue(original.accessibilityPerformPress())
        XCTAssertFalse(second.wrappedValue)
        XCTAssertFalse(first.wrappedValue)
        first.wrappedValue = true
        XCTAssertEqual(original.accessibilityValue() as? NSNumber, 0, "Old observation must not change the current accessible value")
    }
    func testMetadataCrossesTransparentWrappersButStopsAtSemanticGroups() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: false)
        let definition = FluentToggleView("Visual title", isOn: state.projectedValue)
            .controlSize(.regular).padding(8).frame(width: 280)
            .accessibilityLabel("Accessible switch").accessibilityHint("Changes an option")
            .accessibilityIdentifier("test.switch")
        let root = definition._mount(in: .init(reduceMotion: true))
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let toggle = try XCTUnwrap(all(root).compactMap { $0 as? FluentToggle }.first)
        XCTAssertEqual(toggle.accessibilityLabel(), "Accessible switch")
        XCTAssertEqual(toggle.accessibilityHelp(), "Changes an option")
        XCTAssertEqual(toggle.accessibilityIdentifier(), "test.switch")
        XCTAssertEqual(toggle.title, "Visual title")
        let group = FluentToggleView("Child title", isOn: state.projectedValue)
            .accessibilityGroup(label: "Original group").padding(8)
            .accessibilityLabel("Named group")._mount(in: .init(reduceMotion: true))
        let semanticGroup = try XCTUnwrap(all(group).first { $0.isAccessibilityElement() && $0.accessibilityRole() == .group })
        let child = try XCTUnwrap(all(group).compactMap { $0 as? FluentToggle }.first)
        XCTAssertEqual(semanticGroup.accessibilityLabel(), "Named group")
        XCTAssertNotEqual(child.accessibilityLabel(), "Named group")
        XCTAssertEqual(semanticGroup.accessibilityChildren() as? [NSView], [child])
    }

    func testHiddenSubtreeRestoresItsChildrenWithoutReplacingControlsOrChangingLayout() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: false)
        func definition(_ hidden: Bool) -> some FluentView {
            FluentVStack(alignment: .leading) {
                FluentToggleView("First", isOn: state.projectedValue)
                FluentToggleView("Second", isOn: state.projectedValue).accessibilityGroup(label: "Group")
            }.padding(8).accessibilityHidden(hidden).accessibilityLabel("Contents")
        }
        let native = definition(true)._mount(in: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = native
        window.orderFront(nil)
        defer { window.close() }
        native.layoutSubtreeIfNeeded()
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let controls = all(native).compactMap { $0 as? FluentToggle }
        XCTAssertEqual(controls.count, 2)
        let frames = controls.map { $0.convert($0.bounds, to: native) }
        for hidden in [false, true, false] {
            XCTAssertTrue(definition(hidden)._update(native, in: .init(reduceMotion: true)))
            native.layoutSubtreeIfNeeded()
            XCTAssertEqual(native.accessibilityChildren()?.isEmpty, hidden)
            XCTAssertEqual(all(native).compactMap { $0 as? FluentToggle }, controls)
            XCTAssertEqual(controls.map { $0.convert($0.bounds, to: native) }, frames)
            if hidden { XCTAssertNil(native.accessibilityHitTest(.zero)) }
        }
    }

    func testSemanticGroupQueriesCurrentChildrenAfterReorderingAndRemoval() throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: false)
        func definition(_ names: [String]) -> some FluentView {
            FluentVStack {
                FluentForEach(names, id: \.self) { name in
                    FluentToggleView(name, isOn: state.projectedValue)
                }
            }.accessibilityGroup(label: "Switches")
        }
        let native = definition(["A", "B"])._mount(in: .init(reduceMotion: true))
        func switches(_ view: NSView) -> [FluentToggle] {
            if let toggle = view as? FluentToggle { return [toggle] }
            return (view.accessibilityChildren() as? [NSView] ?? []).flatMap(switches)
        }
        let items = try XCTUnwrap(native.accessibilityChildren()?.first as? NSView)
        XCTAssertEqual(items.accessibilityRole(), .group, "ForEach is a semantic Items group, not an ignored layout wrapper")
        let original = switches(native)
        XCTAssertEqual(original.map(\.title), ["A", "B"])
        XCTAssertTrue(definition(["B", "C", "A"])._update(native, in: .init(reduceMotion: true)))
        let reordered = switches(native)
        XCTAssertEqual(reordered.map(\.title), ["B", "C", "A"])
        XCTAssertTrue(reordered[0] === original[1])
        XCTAssertTrue(reordered[2] === original[0])
        XCTAssertTrue(definition([])._update(native, in: .init(reduceMotion: true)))
        XCTAssertEqual(switches(native).count, 0)
    }

    func testCombinedLabelsExcludeHiddenSubtreesBeforeAndAfterMounting() throws {
        _ = NSApplication.shared
        func definition(_ hidden: Bool) -> some FluentView {
            FluentVStack {
                FluentButtonView("First").accessibilityLabel("Shown")
                FluentButtonView("Second").accessibilityLabel("Optional")
                    .padding(4).accessibilityHidden(hidden)
            }.accessibilityElement(children: .combine)
        }
        let native = definition(true)._mount(in: .init(reduceMotion: true))
        XCTAssertEqual(native.accessibilityLabel(), "Shown")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = native
        window.orderFront(nil)
        defer { window.close() }
        for hidden in [false, true, false] {
            XCTAssertTrue(definition(hidden)._update(native, in: .init(reduceMotion: true)))
            XCTAssertEqual(native.accessibilityLabel(), hidden ? "Shown" : "Shown, Optional")
            XCTAssertEqual(native.accessibilityChildren()?.count, 0)
        }
    }

    func testContainExposesSemanticChildrenAndRespectsHiddenSubtrees() {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: false)
        func definition(_ hidden: Bool) -> some FluentView {
            FluentVStack {
                FluentToggleView("First", isOn: state.projectedValue)
                FluentToggleView("Second", isOn: state.projectedValue).padding(4).accessibilityHidden(hidden)
            }.accessibilityElement(children: .contain, label: "Controls")
        }
        let native = definition(true)._mount(in: .init(reduceMotion: true))
        XCTAssertEqual((native.accessibilityChildren() as? [FluentToggle])?.map(\.title), ["First"])
        XCTAssertTrue(definition(false)._update(native, in: .init(reduceMotion: true)))
        XCTAssertEqual((native.accessibilityChildren() as? [FluentToggle])?.map(\.title), ["First", "Second"])
        XCTAssertTrue(definition(true)._update(native, in: .init(reduceMotion: true)))
        XCTAssertEqual((native.accessibilityChildren() as? [FluentToggle])?.map(\.title), ["First"])
    }

}
