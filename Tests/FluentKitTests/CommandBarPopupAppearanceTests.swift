import XCTest
@testable import FluentKit

@MainActor final class CommandBarPopupAppearanceTests: XCTestCase {
    private func adaptiveIcon() -> NSImage {
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .red : .blue
        }
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill(); rect.fill(); return true
        }
    }

    private func mount(_ theme: FluentTheme, hostDark: Bool) -> (NSWindow, FluentCommandBar) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 140, y: 160, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: hostDark ? .darkAqua : .aqua)
        let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [
            FluentCommandBarItem(id: "adaptive", "Adaptive image", icon: .image(adaptiveIcon())) {}
        ])
        bar.theme = theme; bar.reduceMotion = true
        window.contentView!.addSubview(bar)
        bar.frame = NSRect(x: 20, y: 260, width: 300, height: 64)
        window.makeKeyAndOrderFront(nil); bar.layoutSubtreeIfNeeded()
        bar.setOpen(true, animated: false)
        return (window, bar)
    }

    private func assertIcon(_ button: NSView, dark: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds), file: file, line: line)
        button.cacheDisplay(in: button.bounds, to: bitmap)
        let x = Int(20 * CGFloat(bitmap.pixelsWide) / button.bounds.width)
        let y = Int(20 * CGFloat(bitmap.pixelsHigh) / button.bounds.height)
        let pixel = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), file: file, line: line)
        // Compare the chosen variant, allowing AppKit's display-profile color conversion.
        let dominant = dark ? pixel.redComponent : pixel.blueComponent
        let other = dark ? pixel.blueComponent : pixel.redComponent
        XCTAssertGreaterThan(dominant - other, 0.5, file: file, line: line)
    }

    func testOverflowAdaptiveImageUsesExplicitThemeInsteadOfOppositeHost() throws {
        for dark in [false, true] { for high in [false, true] {
            let theme = FluentTheme.custom(contrast: high ? .high : .standard, colorScheme: dark ? .dark : .light)
            let (window, bar) = mount(theme, hostDark: !dark)
            defer { bar.setOpen(false, animated: false); window.close() }
            try assertIcon(bar.secondaryCommandViews[0], dark: dark)
        } }
    }

    func testOpenOverflowThemeChangesPreservePanelFocusAndRefreshAdaptiveImages() throws {
        for hostDark in [false, true] {
            let (window, bar) = mount(.custom(contrast: .standard, colorScheme: .light), hostDark: hostDark)
            defer { bar.setOpen(false, animated: false); window.close() }
            let panel = try XCTUnwrap(window.childWindows?.first)
            let row = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarButton)
            panel.makeFirstResponder(row)
            var callbacks = 0; bar.onIsOpenChanged = { _ in callbacks += 1 }
            for dark in [true, false] {
                bar.theme = .custom(contrast: .high, colorScheme: dark ? .dark : .light)
                try assertIcon(row, dark: dark)
                bar.layoutSubtreeIfNeeded()
                try assertIcon(row, dark: dark)
                XCTAssertTrue(window.childWindows?.first === panel)
                XCTAssertTrue(bar.secondaryCommandViews[0] === row)
                XCTAssertTrue(panel.firstResponder === row)
            }
            XCTAssertEqual(callbacks, 0)
        }
    }

    func testReturningToSystemThemeUsesTheAnchorAppearance() throws {
        for hostDark in [false, true] {
            let theme = FluentTheme.custom(contrast: .standard, colorScheme: hostDark ? .light : .dark)
            let (window, bar) = mount(theme, hostDark: hostDark)
            defer { bar.setOpen(false, animated: false); window.close() }
            let panel = try XCTUnwrap(window.childWindows?.first)
            let row = try XCTUnwrap(bar.secondaryCommandViews[0] as? FluentAppBarButton)
            bar.theme = theme.with(colorScheme: .system)
            try assertIcon(row, dark: hostDark)
            bar.layoutSubtreeIfNeeded()
            XCTAssertTrue(window.childWindows?.first === panel)
            XCTAssertEqual(panel.effectiveAppearance.name, window.effectiveAppearance.name)
        }
    }
}
