import XCTest
@testable import FluentKit

@MainActor
final class DisclosureMotionLifecycleTests: XCTestCase {
    private enum Kind: CaseIterable { case settings, down, up }
    private let key = "fluent.chevron.press"
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    private func definition(_ kind: Kind, state: FluentState<Bool>, title: String = "Header", enabled: Bool = true) -> FluentAnyView {
        if kind == .settings {
            return FluentAnyView(FluentSettingsExpander(title, isExpanded: state.projectedValue, isEnabled: enabled) {
                FluentText("Content").frame(height: 80)
            })
        }
        return FluentAnyView(FluentExpander(title, isExpanded: state.projectedValue,
            expandDirection: kind == .down ? .down : .up, isEnabled: enabled) { FluentText("Content").frame(height: 80) })
    }

    private func mount(_ kind: Kind, expanded: Bool = false) throws
        -> (NSWindow, NSView, NSView, FluentChevronPrimitiveLayer, FluentState<Bool>) {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: expanded)
        let native = definition(kind, state: state)._mount(in: .init(reduceMotion: false))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 280),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = native
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)
        native.layoutSubtreeIfNeeded()
        let id = kind == .settings ? "FluentKit.Settings.Expander.Header" : "FluentKit.Expander.Header"
        let header = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == id })
        let chevron = try XCTUnwrap(header.layer?.sublayers?.compactMap { $0 as? FluentChevronPrimitiveLayer }.first)
        return (window, native, header, chevron, state)
    }

    func testInitialAndRepeatedLayoutsDoNotAnimateAnUnchangedState() throws {
        for kind in Kind.allCases {
            for expanded in [false, true] {
                let (window, _, header, chevron, _) = try mount(kind, expanded: expanded)
                defer { window.close() }
                XCTAssertNil(chevron.animation(forKey: key), "Initial \(kind), expanded=\(expanded)")
                header.needsLayout = true; header.layoutSubtreeIfNeeded()
                XCTAssertNil(chevron.animation(forKey: key), "An idle layout is not a state transition")
            }
        }
    }

    func testLayoutAndContentUpdatesPreserveTheExistingRotationTimeline() throws {
        for kind in Kind.allCases {
            let (window, native, header, chevron, state) = try mount(kind)
            defer { window.close() }
            state.wrappedValue = true
            let animation = try XCTUnwrap(chevron.animation(forKey: key), "\(kind)")
            for _ in 0..<3 {
                header.needsLayout = true; header.layoutSubtreeIfNeeded()
                XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime, "\(kind) must not cancel or restart on layout")
            }
            XCTAssertTrue(definition(kind, state: state, title: "Updated header")._update(native, in: .init(reduceMotion: false)))
            native.layoutSubtreeIfNeeded()
            XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime, "\(kind) content update")
            XCTAssertTrue(header === all(native).first { $0.identifier == header.identifier })
            XCTAssertTrue(state.wrappedValue)
        }
    }

    func testPointerChangesDoNotRestartTheDisclosureRotation() throws {
        for kind in Kind.allCases {
            let (window, _, header, chevron, state) = try mount(kind)
            defer { window.close() }
            state.wrappedValue = true
            let animation = try XCTUnwrap(chevron.animation(forKey: key))
            let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            header.mouseEntered(with: event)
            header.layoutSubtreeIfNeeded()
            XCTAssertEqual(chevron.animation(forKey: key)?.beginTime, animation.beginTime, "\(kind) pointer-over is independent of disclosure")
        }
    }

    func testReducedMotionSettlesAndDoesNotReplayOnTheNextLayout() throws {
        for kind in Kind.allCases {
            let (window, native, header, chevron, state) = try mount(kind)
            defer { window.close() }
            state.wrappedValue = true
            XCTAssertNotNil(chevron.animation(forKey: key))
            XCTAssertTrue(definition(kind, state: state)._update(native, in: .init(reduceMotion: true)))
            native.layoutSubtreeIfNeeded()
            XCTAssertNil(chevron.animation(forKey: key))
            XCTAssertTrue(definition(kind, state: state)._update(native, in: .init(reduceMotion: false)))
            header.layoutSubtreeIfNeeded()
            XCTAssertNil(chevron.animation(forKey: key), "Re-enabling motion does not replay a settled transition")
        }
    }

    func testDetachmentFinishesMotionAndReattachmentDoesNotReplayIt() throws {
        for kind in Kind.allCases {
            let (window, native, header, chevron, state) = try mount(kind)
            defer { window.close() }
            state.wrappedValue = true
            XCTAssertNotNil(chevron.animation(forKey: key))
            native.removeFromSuperview()
            XCTAssertNil(chevron.animation(forKey: key), "Detached \(kind) must not retain rotation")
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 280))
            window.contentView = container
            container.addSubview(native)
            XCTAssertTrue(native.window === window)
            native.layoutSubtreeIfNeeded()
            header.needsLayout = true; header.layoutSubtreeIfNeeded()
            XCTAssertNil(chevron.animation(forKey: key), "Reattached \(kind) retains its settled state")
        }
    }

    func testDisablingSettlesTheCurrentMotionWithoutReplayingOnEnable() throws {
        for kind in Kind.allCases {
            let (window, native, header, chevron, state) = try mount(kind)
            defer { window.close() }
            state.wrappedValue = true
            XCTAssertNotNil(chevron.animation(forKey: key))
            let expandedTransform = chevron.transform
            XCTAssertTrue(definition(kind, state: state, enabled: false)._update(native, in: .init(reduceMotion: false)))
            native.layoutSubtreeIfNeeded()
            XCTAssertNil(chevron.animation(forKey: key), "Disabled \(kind) settles its transition")
            XCTAssertTrue(CATransform3DEqualToTransform(chevron.transform, expandedTransform))
            XCTAssertTrue(state.wrappedValue, "Disabling does not change expansion")
            XCTAssertTrue(definition(kind, state: state)._update(native, in: .init(reduceMotion: false)))
            header.layoutSubtreeIfNeeded()
            XCTAssertNil(chevron.animation(forKey: key), "Re-enabling \(kind) does not replay motion")
            state.wrappedValue = false
            header.layoutSubtreeIfNeeded()
            XCTAssertNotNil(chevron.animation(forKey: key), "\(kind) can animate the next real transition")
        }
    }
}
