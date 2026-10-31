import XCTest
@testable import FluentKit

final class FlipViewVirtualizationTests: XCTestCase {
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    @MainActor func testOnlyViewportNeighborhoodBuildsAndUpdatesContent() throws {
        _ = NSApplication.shared
        var builds = 0, makes = 0, updates = 0
        func page(_ value: Int) -> FluentNativeView {
            builds += 1
            return FluentNativeView(make: { makes += 1; return NSTextField(labelWithString: "") },
                update: { (field: NSTextField, _) in updates += 1; field.stringValue = String(value) })
        }
        let context = FluentRenderContext(reduceMotion: true)
        let native = FluentFlipView(Array(0..<1000), content: page)._makeView(in: context)
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180); native.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(builds, 3); XCTAssertLessThanOrEqual(makes, 3)
        builds = 0; updates = 0
        for _ in 0..<5 { XCTAssertTrue(FluentFlipView(Array(0..<1000), content: page)._updateView(native, in: context)) }
        XCTAssertLessThanOrEqual(builds, 15); XCTAssertLessThanOrEqual(updates, 15)
    }
    @MainActor func testAppendingPagesRetainsTheCurrentNativeContent() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        func content(_ count: Int) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(Array(0..<count)) { value in
                FluentNativeView(make: { NSTextField(labelWithString: "") }, update: { (field: NSTextField, _) in field.stringValue = String(value) })
            }
        }
        let native = content(3)._makeView(in: context)
        let first = try XCTUnwrap(all(native).compactMap { $0 as? NSTextField }.first { $0.stringValue == "0" })
        XCTAssertTrue(content(4)._updateView(native, in: context))
        XCTAssertTrue(all(native).contains { $0 === first }, "Appending should not rebuild the currently visible page")
    }
    @MainActor func testRejectedSelectionDoesNotDivergeFromTheBinding() throws {
        _ = NSApplication.shared
        var changes: [Int] = []
        let binding = FluentBinding<Int>(get: { 0 }, set: { _ in })
        let native = FluentFlipView([0,1,2], selection: binding, onSelectionChanged: { changes.append($0) }) { FluentText(String($0)) }
            ._makeView(in: .init(reduceMotion: true))
        native.keyDown(with: key(124))
        XCTAssertEqual(native.accessibilityValue() as? String, "1 of 3")
        XCTAssertTrue(changes.isEmpty)
    }
    @MainActor private func host(_ view: some FluentUpdatablePrimitiveView, context: FluentRenderContext = .init(reduceMotion: true)) throws -> FluentFlipViewHost {
        _ = NSApplication.shared
        let native = try XCTUnwrap(view._makeView(in: context) as? FluentFlipViewHost)
        native.frame = NSRect(x: 0, y: 0, width: 320, height: 180); native.layoutSubtreeIfNeeded()
        return native
    }
    private func page(_ index: Int, in view: NSView) throws -> NSView {
        try XCTUnwrap(all(view).first { $0.identifier?.rawValue == "FluentKit.FlipView.Page.\(index)" })
    }
    @MainActor func testStableIDsPreserveSelectedItemAndNativeIdentityAcrossEdits() throws {
        let selection = FluentState(wrappedValue: 1)
        var changes: [Int] = []
        func content(_ items: [String]) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(items, id: \.self, selection: selection.projectedValue, onSelectionChanged: { changes.append($0) }) {
                FluentText($0)
            }
        }
        let native = try host(content(["a","b","c"]))
        let retained = try page(1, in: native)
        XCTAssertTrue(content(["c","a","b","d"])._updateView(native, in: .init(reduceMotion: true)))
        XCTAssertEqual(selection.wrappedValue, 2); XCTAssertTrue(try page(2, in: native) === retained)
        XCTAssertEqual(native.accessibilityValue() as? String, "3 of 4")
        XCTAssertTrue(content(["c","a","d"])._updateView(native, in: .init(reduceMotion: true)))
        XCTAssertEqual(selection.wrappedValue, 2); XCTAssertNil(retained.superview)
        XCTAssertEqual(changes, [2,2], "Removing the selected item changes selection even when the replacement has the same index")
        selection.wrappedValue = 0
        XCTAssertTrue(content(["a","d","c"])._updateView(native, in: .init(reduceMotion: true)))
        XCTAssertEqual(selection.wrappedValue, 0, "An explicit changed index wins over item retention")
    }
    @MainActor func testLargeJumpsBuildOnlyDestinationNeighborsAndLatePagesTrackDependencies() throws {
        let selection = FluentState(wrappedValue: 0), prefix = FluentState(wrappedValue: "A")
        var builds = 0
        let native = try host(FluentFlipView(Array(0..<50_000), selection: selection.projectedValue) { value in
            builds += 1; return FluentText("\(prefix.wrappedValue)-\(value)")
        })
        let first = try page(0, in: native)
        native.keyDown(with: key(119))
        XCTAssertEqual(selection.wrappedValue, 49_999); XCTAssertLessThanOrEqual(builds, 5)
        XCTAssertNil(first.superview)
        XCTAssertEqual(try page(49_999, in: native).superview?.subviews.count, 2)
        prefix.wrappedValue = "B"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertTrue(all(try page(49_999, in: native)).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "B-49999" })
    }
    @MainActor func testPanGeometrySinglePageSettlingAndVerticalRTL() throws {
        for vertical in [false,true] { for rtl in [false,true] {
            let selection = FluentState(wrappedValue: 0)
            let context = FluentRenderContext(reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            let native = try host(FluentFlipView(Array(0..<20), selection: selection.projectedValue,
                orientation: vertical ? .vertical : .horizontal) { FluentText(String($0)) }, context: context)
            let extent: CGFloat = vertical ? 180 : 320
            XCTAssertNotNil(native.beginInteractivePan()); native.updateInteractivePan(translation: -extent * 0.25)
            let current = try page(0, in: native)
            let next = try page(1, in: native)
            XCTAssertEqual(vertical ? current.frame.minY : current.frame.minX, extent * 0.25 * (vertical || rtl ? 1 : -1), accuracy: 0.01)
            XCTAssertEqual(vertical ? next.frame.minY : next.frame.minX, extent * 0.75 * (vertical || rtl ? -1 : 1), accuracy: 0.01)
            XCTAssertEqual(selection.wrappedValue, 0)
            native.endInteractivePan(velocity: 0)
            XCTAssertEqual(selection.wrappedValue, 0); XCTAssertFalse(native.isPanning)
            XCTAssertNotNil(native.beginInteractivePan()); native.updateInteractivePan(translation: -extent * 0.7)
            native.endInteractivePan(velocity: -10_000)
            XCTAssertEqual(selection.wrappedValue, 1, "MandatorySingle must never skip multiple pages")
            XCTAssertEqual(try page(1, in: native).layer?.transform.m41, 0)
            XCTAssertEqual(try page(1, in: native).layer?.transform.m42, 0)
            if vertical {
                let previous = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == "FluentKit.FlipView.Previous" })
                XCTAssertEqual(previous.frame, NSRect(x:141, y:163, width:38, height:16))
                native.keyDown(with: key(125)); XCTAssertEqual(selection.wrappedValue, 2)
                native.keyDown(with: key(123)); XCTAssertEqual(selection.wrappedValue, 2, "Vertical paging must not consume Left")
            }
        }}
    }
    @MainActor func testParentRefreshKeepsPanAndLargeJumpKeepsOutgoingPageUntilCompletion() throws {
        for reduced in [false, true] {
            let selection = FluentState(wrappedValue: 0), context = FluentRenderContext(reduceMotion: reduced)
            func content() -> some FluentUpdatablePrimitiveView { FluentFlipView(Array(0..<100), selection: selection.projectedValue) { FluentText(String($0)) } }
            let native = try host(content(), context: context)
            XCTAssertNotNil(native.beginInteractivePan()); native.updateInteractivePan(translation: -90)
            XCTAssertTrue(content()._updateView(native, in: context)); native.layoutSubtreeIfNeeded()
            XCTAssertTrue(native.isPanning); XCTAssertEqual(native.panOffset, -90)
            XCTAssertEqual(try page(0, in: native).frame.minX, -90)
            native.endInteractivePan(velocity: 0)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            XCTAssertFalse(native.isPanning); XCTAssertEqual(selection.wrappedValue, 0)
            if !reduced {
                native.keyDown(with: key(119))
                let outgoing = try page(0, in: native)
                XCTAssertTrue(content()._updateView(native, in: context))
                XCTAssertNotNil(outgoing.superview); XCTAssertFalse(outgoing.isHidden)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
                XCTAssertNil(outgoing.superview)
                XCTAssertFalse(try page(99, in: native).isHidden)
            }
        }
    }
    @MainActor func testInteractionCancellationPreventsStaleSelectionAfterResizeDisableOrDataRemoval() throws {
        let selection = FluentState(wrappedValue: 0)
        func content(_ count: Int, vertical: Bool = false) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(Array(0..<count), selection: selection.projectedValue, orientation: vertical ? .vertical : .horizontal) { FluentText(String($0)) }
        }
        let native = try host(content(10))
        for reason in 0..<4 {
            XCTAssertNotNil(native.beginInteractivePan()); native.updateInteractivePan(translation: -230)
            if reason == 0 { native.isEnabled = false }
            if reason == 1 { native.frame.size.width = 400; native.layoutSubtreeIfNeeded() }
            if reason == 2 { XCTAssertTrue(content(10, vertical: true)._updateView(native, in: .init(reduceMotion: true))) }
            if reason == 3 { XCTAssertTrue(content(0)._updateView(native, in: .init(reduceMotion: true))) }
            XCTAssertFalse(native.isPanning); native.endInteractivePan(velocity: -10_000)
            XCTAssertEqual(selection.wrappedValue, reason == 3 ? -1 : 0)
            native.isEnabled = true
        }
        XCTAssertTrue(all(native).filter { $0.identifier?.rawValue.hasPrefix("FluentKit.FlipView.Page.") == true }.isEmpty)
    }
    @MainActor func testLazyPagesInheritDisabledStateAndRecoverTheirOwnEnabledValues() throws {
        let selection = FluentState(wrappedValue: 0)
        func content(_ disabled: Bool) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(Array(0..<10), selection: selection.projectedValue) { FluentButtonView("Page \($0)").disabled($0 == 8) }.disabled(disabled)
        }
        let wrapper = content(true)._makeView(in: .init(reduceMotion: true))
        selection.wrappedValue = 9
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let buttons = all(wrapper).compactMap { $0 as? NSButton }.filter { $0.title.hasPrefix("Page ") }
        XCTAssertEqual(buttons.count, 2); XCTAssertTrue(buttons.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(content(false)._updateView(wrapper, in: .init(reduceMotion: true)))
        XCTAssertTrue(try XCTUnwrap(buttons.first { $0.title == "Page 9" }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(buttons.first { $0.title == "Page 8" }).isEnabled)
    }
    @MainActor func testRedirectedAndReentrantBindingWritesUseAcceptedCurrentState() throws {
        var value = 0, changes: [Int] = []
        let binding = FluentBinding<Int>(get: { value }, set: { value = $0 == 1 ? 2 : $0 })
        let native = try host(FluentFlipView([0,1,2], selection: binding, onSelectionChanged: { changes.append($0) }) { FluentText(String($0)) })
        native.keyDown(with: key(124))
        XCTAssertEqual(value, 2); XCTAssertEqual(changes, [2]); XCTAssertEqual(native.accessibilityValue() as? String, "3 of 3")
        var other = 0, events: [Int] = [], hook: (() -> Void)?
        let reentrant = FluentBinding<Int>(get: { other }, set: { other = $0; let action = hook; hook = nil; action?() })
        func content(_ items: [Int]) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(items, selection: reentrant, onSelectionChanged: { events.append($0) }) { FluentText(String($0)) }
        }
        let control = try host(content([0,1,2]))
        hook = { XCTAssertTrue(content([])._updateView(control, in: .init(reduceMotion: true))) }
        control.keyDown(with: key(124))
        XCTAssertEqual(other, -1); XCTAssertEqual(events, [-1]); XCTAssertTrue((control.accessibilityValue() as? String)?.hasPrefix("0") == true)
    }

    @MainActor func testPhasedTrackpadInputFollowsMotionIgnoresStaleVelocityAndOwnsMomentum() throws {
        let selection = FluentState(wrappedValue: 0)
        let native = try host(FluentFlipView([0,1,2], selection: selection.projectedValue) { FluentText(String($0)) })
        func event(_ dx: CGFloat, phase: Int64, time: Double, momentum: Int64 = 0) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(dx), wheel3: 0)!
            cg.timestamp = UInt64(time * 1_000_000_000)
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
            return NSEvent(cgEvent: cg)!
        }
        native.scrollWheel(with: event(-80, phase:1, time:10))
        XCTAssertTrue(native.isPanning); XCTAssertEqual(native.panOffset, -80); XCTAssertEqual(selection.wrappedValue, 0)
        native.scrollWheel(with: event(0, phase:4, time:11))
        XCTAssertFalse(native.isPanning); XCTAssertEqual(selection.wrappedValue, 0, "Pausing before release must not replay the initial flick velocity")
        native.scrollWheel(with: event(-200, phase:1, time:20))
        native.scrollWheel(with: event(0, phase:4, time:20.01))
        XCTAssertEqual(selection.wrappedValue, 1)
        native.scrollWheel(with: event(-500, phase:0, time:20.02, momentum:1))
        native.scrollWheel(with: event(-500, phase:0, time:20.03, momentum:2))
        native.scrollWheel(with: event(0, phase:0, time:20.04, momentum:3))
        XCTAssertEqual(selection.wrappedValue, 1, "Trailing momentum belongs to the completed gesture")
    }

    @MainActor func testEditingFocusSurvivesReorderAndMovesToControlWhenSelectedItemIsRemoved() throws {
        let selection = FluentState(wrappedValue: 0)
        func content(_ items: [Int]) -> some FluentUpdatablePrimitiveView {
            FluentFlipView(items, id: \.self, selection: selection.projectedValue) { id in
                FluentNativeView(make: { NSTextField(string: "Draft \(id)") }, update: { (field: NSTextField, _) in
                    field.identifier = NSUserInterfaceItemIdentifier("Draft.\(id)")
                })
            }
        }
        let native = try host(content([0,1,2]))
        let window = NSWindow(contentRect: native.frame, styleMask:[.titled], backing:.buffered, defer:false)
        window.isReleasedWhenClosed = false; window.contentView = native; window.makeKeyAndOrderFront(nil); defer { window.close() }
        let field = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == "Draft.0" } as? NSTextField)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Kept", replacementRange:NSRange(location:0,length:editor.string.utf16.count))
        XCTAssertTrue(content([-1,0,1,2])._updateView(native, in:.init(reduceMotion:true)))
        XCTAssertTrue(field.currentEditor() === editor); XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.string, "Kept"); XCTAssertEqual(selection.wrappedValue, 1)
        XCTAssertTrue(content([-1,1,2])._updateView(native, in:.init(reduceMotion:true)))
        XCTAssertNil(field.window); XCTAssertTrue(window.firstResponder === native)
    }

}
