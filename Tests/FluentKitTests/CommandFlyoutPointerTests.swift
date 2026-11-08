import XCTest
@testable import FluentKit

@MainActor
final class CommandFlyoutPointerTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let anchor = NSView(frame: NSRect(x: 160, y: 220, width: 180, height: 40))
        let flyout: FluentCommandBarFlyout
        let commands = [FluentCommandBarItem(id: 1, "One", systemImageName: "star") {},
                        FluentCommandBarItem(id: 2, "Two", systemImageName: "pencil") {}]
        let primary: Bool

        init(primary: Bool, dark: Bool = false) {
            _ = NSApplication.shared
            self.primary = primary
            window = NSWindow(contentRect: NSRect(x: 120, y: 200, width: 620, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView!.addSubview(anchor)
            window.orderFront(nil)
            flyout = FluentCommandBarFlyout(primaryCommands: primary ? commands : [],
                secondaryCommands: primary ? [] : commands, alwaysExpanded: true,
                theme: .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false), reduceMotion: true)
            flyout.present(relativeTo: anchor)
        }

        func close() { flyout.dismiss(); window.close() }
        var panel: NSWindow { window.childWindows!.first! }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func button(_ title: String) throws -> NSButton {
            try XCTUnwrap(all(panel.contentView!).compactMap { $0 as? NSButton }
                .first { $0.accessibilityTitle() == title })
        }
        func update(_ commands: [FluentCommandBarItem]) {
            flyout.update(configuration: .init(primaryCommands: primary ? commands : [],
                secondaryCommands: primary ? [] : commands, alwaysExpanded: true))
        }
        func enter(_ button: NSButton) throws {
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            button.mouseEntered(with: try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil)))
        }
        func render(_ view: NSView) throws -> NSBitmapImageRep {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        func pixel(_ view: NSView, x: CGFloat = 8, y: CGFloat = 8) throws -> [CGFloat] {
            let bitmap = try render(view)
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / view.bounds.width),
                y: Int(y * CGFloat(bitmap.pixelsHigh) / view.bounds.height))?.usingColorSpace(.sRGB))
            return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
    }

    func testEnteringAPeerClearsHoverEvenIfTheExitWasMissed() throws {
        for dark in [false, true] { for primary in [false, true] {
            let f = Fixture(primary: primary, dark: dark); defer { f.close() }
            let first = try f.button("One"), second = try f.button("Two")
            let normal = try f.pixel(first), secondNormal = try f.pixel(second)
            try f.enter(first)
            XCTAssertNotEqual(try f.pixel(first), normal)
            try f.enter(second)
            XCTAssertEqual(try f.pixel(first), normal)
            XCTAssertNotEqual(try f.pixel(second), secondNormal)
            first.isEnabled = false
            try f.enter(first)
            XCTAssertEqual(try f.pixel(second), secondNormal, "Disabled peers still clear the old hover owner")
        } }
    }

    func testReorderingRetainedCommandsClearsTheirOldPointerLocation() throws {
        for primary in [false, true] {
            let f = Fixture(primary: primary); defer { f.close() }
            let first = try f.button("One")
            let normal = try f.pixel(first)
            try f.enter(first)
            f.update(f.commands)
            XCTAssertNotEqual(try f.pixel(first), normal, "An unchanged frame retains hover")
            f.update(Array(f.commands.reversed()))
            XCTAssertTrue(try f.button("One") === first)
            XCTAssertEqual(try f.pixel(first), normal)
        }
    }

    func testDisableHideAndReparentCannotRestoreAnOldHover() throws {
        for primary in [false, true] {
            let f = Fixture(primary: primary); defer { f.close() }
            let first = try f.button("One")
            let normal = try f.pixel(first)
            for mutation in ["disable", "hide", "ancestor", "reparent"] {
                try f.enter(first)
                XCTAssertNotEqual(try f.pixel(first), normal)
                let parent = try XCTUnwrap(first.superview)
                switch mutation {
                case "disable": first.isEnabled = false; first.isEnabled = true
                case "hide": first.isHidden = true; first.isHidden = false
                case "ancestor": parent.isHidden = true; parent.isHidden = false
                default: first.removeFromSuperview(); parent.addSubview(first)
                }
                XCTAssertEqual(try f.pixel(first), normal, mutation)
            }
        }
    }

    func testWindowOrderingAndFocusLossClearHover() throws {
        for primary in [false, true] {
            let f = Fixture(primary: primary); defer { f.close() }
            let first = try f.button("One")
            let normal = try f.pixel(first)
            let panel = f.panel
            try f.enter(first)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
            XCTAssertEqual(try f.pixel(first), normal)
            try f.enter(first)
            panel.orderOut(nil)
            XCTAssertEqual(try f.pixel(first), normal)
        }
    }

    func testPrimaryMoreAndSecondaryRowsShareOneHoverOwner() throws {
        let f = Fixture(primary: true); defer { f.close() }
        f.flyout.update(configuration: .init(primaryCommands: f.commands,
            secondaryCommands: [.init(id: 3, "Secondary") {}]))
        let more = try f.button("More")
        // Turning AlwaysExpanded off keeps the existing overflow open.
        let first = try f.button("One"), row = try f.button("Secondary")
        let firstNormal = try f.pixel(first), moreNormal = try f.pixel(more), rowNormal = try f.pixel(row)
        try f.enter(first); try f.enter(more)
        XCTAssertEqual(try f.pixel(first), firstNormal)
        XCTAssertNotEqual(try f.pixel(more), moreNormal)
        try f.enter(row)
        XCTAssertEqual(try f.pixel(more), moreNormal)
        XCTAssertNotEqual(try f.pixel(row), rowNormal)
        try f.enter(first)
        XCTAssertEqual(try f.pixel(row), rowNormal)
    }

    func testSecondaryCheckmarkTurnsDownBeforeItsLongRisingStroke() throws {
        for dark in [false, true] {
            let f = Fixture(primary: false, dark: dark); defer { f.close() }
            f.update([.toggle(id: 1, "Checked", isOn: true) { _ in }])
            let row = try f.button("Checked")
            let bitmap = try f.render(row)
            let sx = CGFloat(bitmap.pixelsWide) / row.bounds.width
            let sy = CGFloat(bitmap.pixelsHigh) / row.bounds.height
            func inkY(around x: CGFloat) throws -> CGFloat {
                var ys: [CGFloat] = []
                let baseline = try XCTUnwrap(bitmap.colorAt(x: Int(8 * sx), y: Int(8 * sy))?.usingColorSpace(.sRGB))
                for px in Int((x - 0.6) * sx)...Int((x + 0.6) * sx) {
                    for py in Int((row.bounds.midY - 7) * sy)...Int((row.bounds.midY + 7) * sy) {
                        let color = try XCTUnwrap(bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB))
                        if abs(color.redComponent - baseline.redComponent) > 0.3
                            || abs(color.alphaComponent - baseline.alphaComponent) > 0.3 {
                            ys.append(CGFloat(py) / sy)
                        }
                    }
                }
                XCTAssertFalse(ys.isEmpty)
                return ys.reduce(0, +) / CGFloat(max(1, ys.count))
            }
            let elbow = try inkY(around: 17), tip = try inkY(around: 23)
            XCTAssertGreaterThan(elbow, tip + 4, "Bitmap y increases downwards: the elbow must be below the long-stroke tip")
        }
    }
}
