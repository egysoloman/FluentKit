import XCTest
@testable import FluentKit

@MainActor
final class AppBarForegroundRenderingTests: XCTestCase {
    private func mount(_ button: FluentAppBarButton, dark: Bool) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 320, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        button.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
        button.reduceMotion = true
        window.contentView?.addSubview(button)
        button.frame = NSRect(origin: NSPoint(x: 20, y: 50), size: button.intrinsicContentSize)
        window.orderFront(nil)
        button.layoutSubtreeIfNeeded()
        return window
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.display()
        CATransaction.flush()
        let scale: CGFloat = 2
        let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        try XCTUnwrap(view.layer).render(in: context)
        return NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
    }

    private func iconPoint(_ button: FluentAppBarButton) -> NSPoint {
        switch button.presentation {
        case .fullSize, .labelCollapsed: NSPoint(x: button.bounds.midX, y: 24)
        case .compact: NSPoint(x: button.bounds.midX, y: 20)
        case .labelOnRight: NSPoint(x: 20, y: button.bounds.midY)
        case .overflow: NSPoint(x: 58, y: 20)
        }
    }

    private func pixel(_ bitmap: NSBitmapImageRep, at point: NSPoint, in view: NSView) throws -> NSColor {
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        return try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale),
            y: Int((view.bounds.height - point.y) * scale))?.usingColorSpace(.sRGB))
    }

    func testCheckedCommandForegroundRemainsAboveOpaqueBackgroundInEveryPrimaryPresentation() throws {
        for dark in [false, true] {
            for presentation in ["full", "compact", "collapsed", "right"] {
                let button = FluentAppBarToggleButton("Command", systemImageName: "star.fill", isChecked: true)
                if presentation == "compact" { button.isCompact = true }
                if presentation == "collapsed" { button.defaultLabelPosition = .collapsed }
                if presentation == "right" { button.defaultLabelPosition = .right }
                let window = mount(button, dark: dark)
                defer { window.close() }
                let color = try pixel(render(button), at: iconPoint(button), in: button)
                let expected: CGFloat = dark ? 0 : 1
                for component in [color.redComponent, color.greenComponent, color.blueComponent] {
                    XCTAssertEqual(component, expected, accuracy: 0.03, "\(presentation), dark=\(dark)")
                }
                XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
            }
        }
    }

    func testLabelUpdatesRepaintCheckedCommandContent() throws {
        let button = FluentAppBarToggleButton("OOOO", systemImageName: "star.fill", isChecked: true)
        let window = mount(button, dark: false)
        defer { window.close() }
        let before = try render(button)
        button.label = "IIII"
        let after = try render(button)
        XCTAssertNotEqual(before.tiffRepresentation, after.tiffRepresentation)
        XCTAssertEqual(button.accessibilityTitle(), "IIII")
    }

    func testThemeAndCheckedChangesRefreshForegroundWithoutReplacingControlOrStealingHitTests() throws {
        let button = FluentAppBarToggleButton("Command", systemImageName: "star.fill", isChecked: true)
        let window = mount(button, dark: false)
        defer { window.close() }
        for dark in [true, false, true] {
            button.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            let color = try pixel(render(button), at: iconPoint(button), in: button)
            XCTAssertEqual(color.redComponent, dark ? 0 : 1, accuracy: 0.03)
            XCTAssertTrue(button.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button)
            XCTAssertTrue(button.isChecked)
        }
        button.setCheckedFromBinding(false)
        let unchecked = try pixel(render(button), at: iconPoint(button), in: button)
        XCTAssertGreaterThan(unchecked.redComponent, 0.95, "Dark unchecked command uses its normal text brush")
    }

    func testUncheckedForegroundIsDrawnOnlyOnce() throws {
        let button = FluentAppBarToggleButton("Command", systemImageName: "star.fill", isChecked: false)
        let window = mount(button, dark: false)
        defer { window.close() }
        let color = try pixel(render(button), at: iconPoint(button), in: button)
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(color.alphaComponent, button.theme.textPrimary.alphaComponent, accuracy: 0.01)
    }

    func testForegroundTracksBitmapChangesDirtyRectanglesAndResize() throws {
        func solidBitmap(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> NSBitmapImageRep {
            let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                bytesPerRow: 64, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            return NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        }
        let bitmap = try solidBitmap(red: 1, green: 0, blue: 1)
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(bitmap)
        let button = FluentAppBarToggleButton("Command", isChecked: true)
        button.icon = .image(image)
        let window = mount(button, dark: false)
        defer { window.close() }
        let initial = try pixel(render(button), at: iconPoint(button), in: button)
        func assertMatchesSource(_ actual: NSColor, _ source: NSBitmapImageRep) throws {
            // Compare in the same color space: AppKit may color-match the source bitmap.
            let expected = try XCTUnwrap(source.colorAt(x: 8, y: 8)?.usingColorSpace(.sRGB))
            XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.02)
            XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.02)
            XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.02)
            XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.01)
        }
        try assertMatchesSource(initial, bitmap)
        let replacement = try solidBitmap(red: 0, green: 1, blue: 0)
        image.removeRepresentation(bitmap)
        image.addRepresentation(replacement)
        image.recache()
        button.setFrameSize(NSSize(width: 140, height: 64))
        button.setNeedsDisplay(button.bounds)
        let updated = try pixel(render(button), at: iconPoint(button), in: button)
        try assertMatchesSource(updated, replacement)
        XCTAssertGreaterThan(abs(updated.redComponent - initial.redComponent), 0.9)
    }

    func testMoreHighContrastForegroundStaysAboveHoverAndPressedChrome() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 320, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        defer { window.close() }
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [.init("Command") {}])
        bar.theme = .custom(contrast: .high, colorScheme: .light, materialEffectsEnabled: false)
        bar.reduceMotion = true
        window.contentView?.addSubview(bar)
        bar.frame = NSRect(x: 20, y: 50, width: 180, height: 48)
        window.orderFront(nil)
        bar.layoutSubtreeIfNeeded()
        let more = try XCTUnwrap(bar.subviews.first { $0.identifier?.rawValue == "FluentKit.CommandBar.MoreButton" } as? NSControl)
        let center = NSPoint(x: more.bounds.midX, y: more.bounds.midY)
        more.mouseEntered(with: try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
            location: more.convert(center, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)))
        let hovered = try pixel(render(more), at: center, in: more)
        XCTAssertLessThan(hovered.redComponent, 0.1)
        more.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)))
        let pressed = try pixel(render(more), at: center, in: more)
        XCTAssertLessThan(pressed.redComponent, 0.25)
        XCTAssertFalse(bar.isOpen)
    }
}
