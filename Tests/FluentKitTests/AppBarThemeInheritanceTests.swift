import XCTest
@testable import FluentKit

@MainActor
final class AppBarThemeInheritanceTests: XCTestCase {
    private func withWindow(appDark: Bool = false, hostDark: Bool,
                            _ body: (NSWindow) throws -> Void) rethrows {
        _ = NSApplication.shared
        let original = NSApp.appearance
        NSApp.appearance = NSAppearance(named: appDark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 540, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: hostDark ? .darkAqua : .aqua)
        defer { window.close(); NSApp.appearance = original }
        window.orderFront(nil)
        try body(window)
    }

    private func attach(_ view: NSView, to window: NSWindow, width: CGFloat = 100, height: CGFloat = 64) {
        window.contentView!.addSubview(view)
        view.frame = NSRect(x: 20, y: 140, width: width, height: height)
        view.layoutSubtreeIfNeeded()
    }

    private func iconPoint(_ button: FluentAppBarButton) -> NSPoint {
        switch button.presentation {
        case .fullSize, .labelCollapsed: NSPoint(x: button.bounds.midX, y: 24)
        case .compact: NSPoint(x: button.bounds.midX, y: 20)
        case .labelOnRight: NSPoint(x: 20, y: button.bounds.midY)
        case .overflow: NSPoint(x: button.reservesOverflowToggleSlot ? 58 : 20, y: 20)
        }
    }

    private func pixel(_ view: NSView, at point: NSPoint) throws -> NSColor {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        return try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB))
    }

    private func assertForeground(_ color: NSColor, white: Bool,
                                  file: StaticString = #filePath, line: UInt = #line) {
        for value in [color.redComponent, color.greenComponent, color.blueComponent] {
            XCTAssertEqual(value, white ? 1 : 0, accuracy: 0.03, file: file, line: line)
        }
    }

    private func assertColor(_ actual: CGColor?, matches expected: NSColor,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(actual.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB), file: file, line: line)
        let expected = try XCTUnwrap(expected.usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.003, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.003, file: file, line: line)
    }

    func testSystemCommandUsesItsHostAppearanceInsteadOfTheApplication() throws {
        for dark in [false, true] { for high in [false, true] {
            try withWindow(appDark: !dark, hostDark: dark) { window in
                let button = FluentAppBarButton("Command", systemImageName: "star.fill")
                button.theme = .custom(contrast: high ? .high : .standard, colorScheme: .system)
                button.reduceMotion = true
                attach(button, to: window)
                assertForeground(try pixel(button, at: iconPoint(button)), white: dark)
                XCTAssertEqual(button.theme.colorScheme, .system)
            }
        } }
    }

    func testLiveWindowAppearanceRefreshesCheckedForegroundAndCachedBackground() throws {
        try withWindow(hostDark: false) { window in
            let button = FluentAppBarToggleButton("Command", systemImageName: "star.fill", isChecked: true)
            button.theme = .custom(contrast: .standard, colorScheme: .system)
            button.reduceMotion = true
            attach(button, to: window)
            let chrome = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
            var changes = 0
            button.onIsCheckedChanged = { _ in changes += 1 }
            for dark in [true, false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                assertForeground(try pixel(button, at: iconPoint(button)), white: !dark)
                try assertColor(chrome.backgroundColor,
                    matches: FluentTheme.custom(contrast: .standard, colorScheme: dark ? .dark : .light).accentFillDefault)
                XCTAssertTrue(button.isChecked)
                XCTAssertEqual(button.theme.colorScheme, .system)
            }
            XCTAssertEqual(changes, 0)
        }
    }

    func testReparentingBetweenLocalAppearancesKeepsRequestedSystemPreference() throws {
        try withWindow(hostDark: false) { window in
            let light = NSView(frame: NSRect(x: 0, y: 50, width: 220, height: 180))
            let dark = NSView(frame: NSRect(x: 250, y: 50, width: 220, height: 180))
            light.appearance = NSAppearance(named: .aqua)
            dark.appearance = NSAppearance(named: .darkAqua)
            window.contentView!.addSubview(light); window.contentView!.addSubview(dark)
            let button = FluentAppBarButton("Command", systemImageName: "star.fill")
            button.theme = .custom(contrast: .standard, colorScheme: .system)
            button.reduceMotion = true
            button.frame = NSRect(x: 20, y: 20, width: 100, height: 64)
            for parent in [light, dark, light, dark] {
                button.removeFromSuperview()
                parent.addSubview(button)
                assertForeground(try pixel(button, at: iconPoint(button)), white: parent === dark)
                XCTAssertEqual(button.theme.colorScheme, .system)
                XCTAssertTrue(button.window === window)
            }
        }
    }

    func testInheritedApplicationAppearanceRefreshesCachedColorsAndKeepsExplicitOverrides() throws {
        try withWindow(hostDark: false) { window in
            window.appearance = nil
            let system = FluentAppBarToggleButton("System", systemImageName: "star.fill", isChecked: true)
            system.theme = .custom(contrast: .standard, colorScheme: .system)
            system.reduceMotion = true
            attach(system, to: window)
            let chrome = try XCTUnwrap(system.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
            let explicit = [false, true].map { dark -> FluentAppBarButton in
                let button = FluentAppBarButton("Explicit", systemImageName: "star.fill")
                button.theme = .custom(contrast: .standard, colorScheme: dark ? .dark : .light)
                button.reduceMotion = true
                attach(button, to: window)
                return button
            }
            for dark in [true, false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let expected: NSAppearance.Name = dark ? .darkAqua : .aqua
                waitForUI(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == expected)
                assertForeground(try pixel(system, at: iconPoint(system)), white: !dark)
                try assertColor(chrome.backgroundColor,
                    matches: FluentTheme.custom(contrast: .standard, colorScheme: dark ? .dark : .light).accentFillDefault)
                for (index, button) in explicit.enumerated() {
                    assertForeground(try pixel(button, at: iconPoint(button)), white: index == 1)
                }
                XCTAssertNil(window.appearance)
                XCTAssertEqual(system.theme.colorScheme, .system)
            }
        }
    }

    func testSystemCommandBarPrimaryAndMoreFollowLiveWindowAppearance() throws {
        try withWindow(hostDark: false) { window in
            let bar = FluentCommandBar(primaryCommands: [.init("Command", systemImageName: "star.fill") {}],
                                       secondaryCommands: [.init("Secondary") {}])
            bar.theme = .custom(contrast: .high, colorScheme: .system)
            bar.reduceMotion = true
            attach(bar, to: window, width: 320)
            let primary = try XCTUnwrap(bar.primaryCommandViews.first as? FluentAppBarButton)
            let more = try XCTUnwrap(bar.subviews.first { $0.identifier?.rawValue == "FluentKit.CommandBar.MoreButton" })
            for dark in [true, false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                assertForeground(try pixel(primary, at: iconPoint(primary)), white: dark)
                assertForeground(try pixel(more, at: NSPoint(x: more.bounds.midX, y: more.bounds.midY)), white: dark)
                XCTAssertTrue(bar.primaryCommandViews.first === primary)
                XCTAssertEqual(bar.theme.colorScheme, .system)
            }
        }
    }

    func testSeparatorRefreshesItsCachedColorAcrossHostAppearanceChanges() throws {
        for high in [false, true] {
            try withWindow(hostDark: false) { window in
                let separator = FluentAppBarSeparator()
                separator.theme = .custom(contrast: high ? .high : .standard, colorScheme: .system)
                attach(separator, to: window, width: 5)
                let line = try XCTUnwrap(separator.layer?.sublayers?.first { $0.name == "FluentKit.AppBarSeparator.Divider" })
                for dark in [true, false, true] {
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    _ = try pixel(separator, at: NSPoint(x: 2.5, y: 24))
                    try assertColor(line.backgroundColor,
                        matches: FluentTheme.custom(contrast: high ? .high : .standard, colorScheme: dark ? .dark : .light).divider)
                    XCTAssertEqual(separator.theme.colorScheme, .system)
                }
            }
        }
    }

    func testSystemOverflowForegroundUpdatesWithoutReplacingPanelRowsOrFocus() throws {
        try withWindow(hostDark: false) { window in
            let bar = FluentCommandBar(primaryCommands: [],
                secondaryCommands: [.init("Command", systemImageName: "star.fill") {}])
            bar.theme = .custom(contrast: .standard, colorScheme: .system)
            bar.reduceMotion = true
            attach(bar, to: window, width: 200)
            bar.setOpen(true, animated: false)
            defer { bar.setOpen(false, animated: false) }
            let panel = try XCTUnwrap(window.childWindows?.first)
            let row = try XCTUnwrap(bar.secondaryCommandViews.first as? FluentAppBarButton)
            panel.makeFirstResponder(row)
            var changes = 0; bar.onIsOpenChanged = { _ in changes += 1 }
            for dark in [true, false, true] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let expected: NSAppearance.Name = dark ? .darkAqua : .aqua
                // Child-window appearance propagation is deferred by AppKit. Await the native
                // inheritance, then independently check the command's actual rendered color.
                waitForUI(panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == expected &&
                    row.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == expected)
                assertForeground(try pixel(row, at: iconPoint(row)), white: dark)
                XCTAssertTrue(window.childWindows?.first === panel)
                XCTAssertTrue(bar.secondaryCommandViews.first === row)
                XCTAssertTrue(panel.firstResponder === row)
                XCTAssertTrue(bar.isOpen)
            }
            XCTAssertEqual(changes, 0)
        }
    }

    func testAdaptiveImageFollowsExplicitThemeAndReturnsToHostInheritance() throws {
        for hostDark in [false, true] {
            try withWindow(appDark: !hostDark, hostDark: hostDark) { window in
                let color = NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .red : .blue
                }
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    color.setFill(); rect.fill(); return true
                }
                let button = FluentAppBarButton("Command")
                button.icon = .image(image)
                button.reduceMotion = true
                attach(button, to: window)
                for scheme in [FluentThemeColorScheme.light, .dark, .system, .light, .dark] {
                    button.theme = .custom(contrast: .standard, colorScheme: scheme)
                    let pixel = try pixel(button, at: iconPoint(button))
                    let dark = scheme == .system ? hostDark : scheme == .dark
                    XCTAssertGreaterThan(dark ? pixel.redComponent - pixel.blueComponent : pixel.blueComponent - pixel.redComponent, 0.5)
                    XCTAssertEqual(button.theme.colorScheme, scheme)
                }
            }
        }
    }

    func testAdaptiveAccentUsesRequestedAppearanceOutsideTheDrawingCallback() throws {
        try withWindow(hostDark: false) { window in
            let accent = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .red : .blue
            }
            let button = FluentAppBarToggleButton("Command", isChecked: true)
            button.reduceMotion = true
            attach(button, to: window)
            let chrome = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
            for dark in [true, false, true] {
                NSAppearance(named: dark ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
                    button.theme = .custom(accent: accent, contrast: .high, colorScheme: dark ? .dark : .light)
                }
                let pixel = try XCTUnwrap(chrome.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(dark ? pixel.redComponent - pixel.blueComponent : pixel.blueComponent - pixel.redComponent, 0.5)
            }
        }
    }

    func testAttachedFlyoutReceivesLiveExplicitThemeWithoutLosingItsPresentation() throws {
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        try withWindow(hostDark: false) { window in
            let button = FluentAppBarButton("Menu", flyoutItems: [FluentMenuItem("Item", action: {})])
            button.theme = .custom(colorScheme: .light, materialEffectsEnabled: false)
            button.reduceMotion = true
            attach(button, to: window)
            button.showFlyout()
            defer { button.hideFlyout(animated: false) }
            let panel = try XCTUnwrap(window.childWindows?.first)
            let row = try XCTUnwrap(panel.contentView.flatMap { all($0).first { $0.identifier?.rawValue == "FluentKit.Menu.Item" } })
            let presenter = try XCTUnwrap(row.superview)
            panel.makeFirstResponder(presenter)
            for dark in [true, false, true] {
                button.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), dark ? .darkAqua : .aqua)
                XCTAssertTrue(window.childWindows?.first === panel)
                XCTAssertTrue(presenter.subviews.contains { $0 === row })
                XCTAssertTrue(panel.firstResponder === presenter)
                XCTAssertTrue(button.isFlyoutPresented)
            }
        }
    }
}
