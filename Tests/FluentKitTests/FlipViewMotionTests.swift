import XCTest
@testable import FluentKit

final class FlipViewMotionTests: XCTestCase {
    @MainActor func testNativePageContentFillsTheViewportDuringNavigationAndResize() throws {
        _ = NSApplication.shared
        var leaves: [Int: NSView] = [:]
        let native = FluentFlipView([0, 1, 2]) { index in
            FluentNativeView(make: { let view = NSView(); leaves[index] = view; return view }, update: { (_: NSView, _) in })
        }._makeView(in: .init(reduceMotion: false))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 320, height: 180),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = native; window.makeKeyAndOrderFront(nil); native.layoutSubtreeIfNeeded()
        XCTAssertEqual(leaves[0]?.bounds.size, NSSize(width: 320, height: 180))
        native.keyDown(with: key(124)); native.layoutSubtreeIfNeeded()
        XCTAssertEqual(leaves[1]?.bounds.size, NSSize(width: 320, height: 180))
        window.setContentSize(NSSize(width: 420, height: 240)); native.layoutSubtreeIfNeeded()
        XCTAssertEqual(leaves[1]?.bounds.size, NSSize(width: 420, height: 240))
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    @MainActor func testRejectedAndReentrantGestureAnchorCannotLeaveStaleTransition() throws {
        _ = NSApplication.shared
        for reentrant in [false, true] {
            var selected = 0, accepts = true, interrupt = false
            var native: FluentFlipViewHost!
            let binding = FluentBinding<Int>(get: { selected }, set: { if accepts { selected = $0 } })
            func content(_ items: [Int]) -> some FluentUpdatablePrimitiveView {
                FluentFlipView(items, selection: binding, onSelectionChanged: { _ in
                    if interrupt {
                        interrupt = false
                        _ = FluentFlipView([Int](), selection: binding) { FluentText(String($0)) }
                            ._updateView(native, in: .init(reduceMotion: false))
                    }
                }) { FluentText(String($0)) }
            }
            native = try XCTUnwrap(content(Array(0..<10))._makeView(in: .init(reduceMotion: false)) as? FluentFlipViewHost)
            native.frame = NSRect(x: 0, y: 0, width: 320, height: 180); native.layoutSubtreeIfNeeded()
            native.keyDown(with: key(124)); native.keyDown(with: key(124))
            if reentrant { interrupt = true } else { accepts = false }
            XCTAssertNil(native.beginInteractivePan())
            XCTAssertFalse(native.isPanning)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            XCTAssertEqual(selected, reentrant ? -1 : 2)
            if reentrant {
                XCTAssertTrue((native.accessibilityValue() as? String)?.hasPrefix("0") == true)
                let container = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" })
                XCTAssertTrue(container.subviews.isEmpty)
            } else { XCTAssertEqual(native.accessibilityValue() as? String, "3 of 10") }
        }
    }

    @MainActor func testRepeatedNavigationRetainsVisiblePositionsAndGestureTakeover() throws {
        _ = NSApplication.shared
        for (axis, rtl) in [(NSUserInterfaceLayoutOrientation.horizontal, false), (.horizontal, true), (.vertical, false)] {
            let state = FluentState(wrappedValue: 0)
            var changes: [Int] = []
            let native = try XCTUnwrap(FluentFlipView(Array(0..<1000), selection: state.projectedValue,
                orientation: axis, onSelectionChanged: { changes.append($0) }) { FluentText(String($0)) }
                ._makeView(in: .init(reduceMotion: false, layoutDirection: rtl ? .rightToLeft : .leftToRight)) as? FluentFlipViewHost)
            let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 320, height: 180),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; defer { window.close() }
            window.contentView = native; window.makeKeyAndOrderFront(nil); native.layoutSubtreeIfNeeded()
            let container = try XCTUnwrap(native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" })
            func page(_ index: Int) throws -> NSView {
                try XCTUnwrap(container.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Page.\(index)" })
            }
            func position(_ view: NSView) -> CGFloat {
                let transform = view.layer?.presentation()?.transform ?? view.layer?.transform ?? CATransform3DIdentity
                return axis == .vertical ? view.frame.minY + transform.m42 : view.frame.minX + transform.m41
            }
            let next: UInt16 = axis == .vertical ? 125 : rtl ? 123 : 124
            native.keyDown(with: key(next)); CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
            let first = try page(0), second = try page(1)
            let firstPosition = position(first), secondPosition = position(second)
            XCTAssertFalse(first.isHidden)
            native.keyDown(with: key(next)); CATransaction.flush()
            XCTAssertTrue(first.superview === container, "A visible page cannot be discarded during a second flip")
            XCTAssertFalse(first.isHidden)
            XCTAssertEqual(position(first), firstPosition, accuracy: 2)
            XCTAssertEqual(position(second), secondPosition, accuracy: 2, "The partial incoming page must not jump to the center")
            XCTAssertEqual(changes, [1, 2]); XCTAssertEqual(state.wrappedValue, 2)
            let beforeGrab = position(first)
            XCTAssertNotNil(native.beginInteractivePan())
            XCTAssertEqual(position(first), beforeGrab, accuracy: 2, "Grabbing a multi-page transition must preserve the visible pages")
            native.endInteractivePan(velocity: 0)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            for _ in 0..<20 { native.keyDown(with: key(next)) }
            XCTAssertLessThanOrEqual(container.subviews.count, 5, "Repeated flips must retain a bounded viewport neighborhood")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.32))
            XCTAssertEqual(container.subviews.filter { !$0.isHidden }.count, 1)
            XCTAssertEqual(native.accessibilityValue() as? String, "\(state.wrappedValue + 1) of 1000")
        }
    }
}
