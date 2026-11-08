import XCTest
@testable import FluentKit

@MainActor
final class CommandFlyoutCallbackTests: XCTestCase {
    private final class Fixture {
        let window: NSWindow
        let anchor = NSView(frame: NSRect(x: 180, y: 280, width: 320, height: 48))
        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 120, y: 180, width: 700, height: 420),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView!.addSubview(anchor)
            window.orderFront(nil)
        }
        func close() { window.close() }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func button(_ title: String, in panel: NSWindow) throws -> NSView {
            try XCTUnwrap(all(panel.contentView!).first { $0 is NSButton && $0.accessibilityTitle() == title })
        }
        func menuRow(in panel: NSWindow) throws -> NSView {
            try XCTUnwrap(all(panel.contentView!).first { $0.identifier?.rawValue == "FluentKit.Menu.Item" })
        }
        func bar() -> FluentCommandBar {
            let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [
                .init(id: "branch", "Branch") {}, .init(id: "other", "Other") {}])
            bar.reduceMotion = true
            anchor.addSubview(bar);bar.frame = anchor.bounds
            bar.layoutSubtreeIfNeeded();bar.setOpen(true, animated: false)
            return bar
        }
    }

    func testCommandCallbackCanReplaceTheFlyoutWithoutTheOldInvocationClosingIt() throws {
        for explicitlyDismiss in [false, true] {
            let f = Fixture(); defer { f.close() }
            var calls = 0
            var flyout: FluentCommandBarFlyout!
            flyout = FluentCommandBarFlyout(primaryCommands: [], secondaryCommands: [.init("Replace") {
                calls += 1
                if explicitlyDismiss { flyout.dismiss() }
                flyout.present(relativeTo: f.anchor)
            }], reduceMotion: true)
            defer { flyout.onDismiss = nil;flyout.dismiss();flyout = nil }
            flyout.present(relativeTo: f.anchor)
            let old = try XCTUnwrap(f.window.childWindows?.first)
            XCTAssertTrue(try f.button("Replace", in: old).accessibilityPerformPress())
            XCTAssertEqual(calls, 1)
            XCTAssertTrue(flyout.isPresented)
            let replacement = try XCTUnwrap(f.window.childWindows?.first)
            XCTAssertFalse(replacement === old)
            XCTAssertFalse(old.isVisible)
        }
    }

    func testDismissNotifiesOnlyForAnExistingPresentation() {
        let f = Fixture(); defer { f.close() }
        let flyout = FluentCommandBarFlyout(primaryCommands: [], secondaryCommands: [.init("Run") {}], reduceMotion: true)
        var dismissals = 0
        flyout.onDismiss = { dismissals += 1 }
        flyout.dismiss()
        XCTAssertEqual(dismissals, 0)
        for expected in 1...2 {
            flyout.present(relativeTo: f.anchor)
            flyout.dismiss();flyout.dismiss()
            XCTAssertEqual(dismissals, expected)
        }
    }

    func testRetiredPrimaryAndSecondaryCommandsCannotInvokeAgain() throws {
        for primary in [false, true] {
            let f = Fixture(); defer { f.close() }
            var calls = 0
            let command = FluentCommandBarItem("Run") { calls += 1 }
            let flyout = FluentCommandBarFlyout(primaryCommands: primary ? [command] : [],
                secondaryCommands: primary ? [] : [command], reduceMotion: true)
            defer { flyout.dismiss() }
            flyout.present(relativeTo: f.anchor)
            let old = try XCTUnwrap(f.window.childWindows?.first)
            let row = try f.button("Run", in: old)
            XCTAssertTrue(row.accessibilityPerformPress())
            XCTAssertFalse(flyout.isPresented)
            XCTAssertFalse(row.accessibilityPerformPress())
            XCTAssertEqual(calls, 1)
        }
    }

    func testRetiredRowCannotCloseAReplacementOpenedFromDismissCallback() throws {
        let f = Fixture(); defer { f.close() }
        var calls = 0, dismissals = 0
        let flyout = FluentCommandBarFlyout(primaryCommands: [], secondaryCommands: [.init("Run") { calls += 1 }], reduceMotion: true)
        defer { flyout.onDismiss = nil;flyout.dismiss() }
        flyout.onDismiss = {
            dismissals += 1
            if dismissals == 1 { flyout.present(relativeTo: f.anchor) }
        }
        flyout.present(relativeTo: f.anchor)
        let old = try XCTUnwrap(f.window.childWindows?.first)
        let row = try f.button("Run", in: old)
        XCTAssertTrue(row.accessibilityPerformPress())
        let replacement = try XCTUnwrap(f.window.childWindows?.first)
        XCTAssertFalse(row.accessibilityPerformPress())
        XCTAssertTrue(flyout.isPresented)
        XCTAssertTrue(f.window.childWindows?.first === replacement)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(dismissals, 1)
    }

    func testCollapsingMoreRetiresItsSecondaryRows() throws {
        let f = Fixture(); defer { f.close() }
        var calls = 0
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init("Primary") {}],
            secondaryCommands: [.init("Secondary") { calls += 1 }], reduceMotion: true)
        defer { flyout.dismiss() }
        flyout.present(relativeTo: f.anchor)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let more = try f.button("More", in: panel)
        XCTAssertTrue(more.accessibilityPerformPress())
        let retired = try f.button("Secondary", in: panel)
        XCTAssertTrue(more.accessibilityPerformPress())
        XCTAssertNil(retired.superview)
        XCTAssertFalse(retired.accessibilityPerformPress())
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(flyout.isPresented)
        XCTAssertTrue(more.accessibilityPerformPress())
        let current = try f.button("Secondary", in: panel)
        XCTAssertFalse(current === retired)
        XCTAssertTrue(current.accessibilityPerformPress())
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(flyout.isPresented)
    }

    func testLeafRemovingItsAnchorOrAttachmentStillClosesTheOuterChain() throws {
        for removeOwner in [false, true] { for nested in [false, true] {
            let f = Fixture(); defer { f.close() }
            let bar = f.bar(); defer { bar.setOpen(false, animated: false) }
            let branch = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarButton)
            var calls = 0
            let leaf = FluentMenuItem("Remove") { [weak bar, weak branch] in
                calls += 1
                if removeOwner { bar?.secondaryCommands = [.init(id: "other", "Other") {}] }
                else { branch?.flyoutItems = nil }
            }
            branch.flyoutItems = nested ? [.submenu("Nested") { leaf }] : [leaf]
            let root = try XCTUnwrap(f.window.childWindows?.first)
            branch.showFlyout()
            let child = try XCTUnwrap(root.childWindows?.first)
            var leafPanel = child
            if nested {
                XCTAssertTrue(try f.menuRow(in: child).accessibilityPerformPress())
                leafPanel = try XCTUnwrap(child.childWindows?.first)
            }
            XCTAssertTrue(try f.menuRow(in: leafPanel).accessibilityPerformPress())
            XCTAssertEqual(calls, 1)
            XCTAssertFalse(bar.isOpen)
            XCTAssertFalse(branch.isFlyoutPresented)
            XCTAssertFalse(child.isVisible)
            XCTAssertFalse(leafPanel.isVisible)
        } }
    }

    func testLeafCanReplaceItsAttachedBranchOrOpenAPeer() throws {
        for peer in [false, true] {
            let f = Fixture(); defer { f.close() }
            let bar = f.bar(); defer { bar.setOpen(false, animated: false) }
            let branch = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarButton)
            let destination = peer ? try XCTUnwrap(bar.secondaryCommandViews[1] as? FluentAppBarButton) : branch
            branch.flyoutItems = [FluentMenuItem("Replace") { [weak branch, weak destination] in
                branch?.hideFlyout(animated: false)
                destination?.flyoutItems = [FluentMenuItem("New leaf") {}]
                destination?.showFlyout()
            }]
            let root = try XCTUnwrap(f.window.childWindows?.first)
            branch.showFlyout()
            let old = try XCTUnwrap(root.childWindows?.first)
            XCTAssertTrue(try f.menuRow(in: old).accessibilityPerformPress())
            XCTAssertTrue(bar.isOpen)
            XCTAssertTrue(destination.isFlyoutPresented)
            XCTAssertFalse(old.isVisible)
            XCTAssertFalse(root.childWindows?.first === old)
        }
    }

    func testLeafCallbackCanOpenAPrimaryFlyout() throws {
        let f = Fixture(); defer { f.close() }
        let bar = f.bar(); defer { bar.setOpen(false, animated: false) }
        bar.primaryCommands = [.init(id: "primary", "Primary") {}]
        let primary = try XCTUnwrap(bar.primaryCommandViews[0] as? FluentAppBarButton)
        let branch = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarButton)
        primary.flyoutItems = [FluentMenuItem("New primary leaf") {}]
        branch.flyoutItems = [FluentMenuItem("Replace") { [weak branch, weak primary] in
            branch?.hideFlyout(animated: false)
            primary?.showFlyout()
        }]
        let root = try XCTUnwrap(f.window.childWindows?.first)
        branch.showFlyout()
        let old = try XCTUnwrap(root.childWindows?.first)
        XCTAssertTrue(try f.menuRow(in: old).accessibilityPerformPress())
        XCTAssertFalse(old.isVisible)
        XCTAssertTrue(primary.isFlyoutPresented)
    }

    func testCommandInvocationCannotReenterTheSameRetiredRow() throws {
        let f = Fixture(); defer { f.close() }
        var calls = 0
        var acceptedReentry: Bool?
        weak var row: NSView?
        let flyout = FluentCommandBarFlyout(primaryCommands: [], secondaryCommands: [.init("Run") {
            calls += 1
            if calls == 1 { acceptedReentry = row?.accessibilityPerformPress() }
        }], reduceMotion: true)
        defer { flyout.dismiss() }
        flyout.present(relativeTo: f.anchor)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        row = try f.button("Run", in: panel)
        XCTAssertTrue(row!.accessibilityPerformPress())
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(acceptedReentry, false)
        XCTAssertFalse(flyout.isPresented)
    }
}
