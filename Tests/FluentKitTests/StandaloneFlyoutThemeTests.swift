import XCTest
@testable import FluentKit

@MainActor
final class StandaloneFlyoutThemeTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 360))
        let anchor = NSView(frame: NSRect(x: 120, y: 180, width: 180, height: 40))
        let items: [FluentMenuItem] = [.submenu(id: 1, "Branch") { FluentMenuItem(id: 2, "Leaf") {} }]
        var coordinator: FluentAppearanceCoordinator?
        var menu: FluentMenuFlyout?
        var command: FluentCommandBarFlyout?

        init(command: Bool, requested: FluentTheme?, root: FluentTheme? = nil, dark: Bool = false) {
            _ = NSApplication.shared
            window = NSWindow(contentRect: container.bounds, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView!.addSubview(container)
            container.addSubview(anchor)
            if let root {
                let owner = FluentAppearanceCoordinator(theme: root)
                coordinator = owner
                owner.attach(to: window)
            }
            if command {
                let primary: [FluentCommandBarItem] = [.toggle(id: 1, "Toggle", systemImageName: "bold", isOn: false) { _ in }]
                let secondary: [FluentCommandBarItem] = [.init(id: 2, "Secondary") {}]
                if let requested {
                    self.command = FluentCommandBarFlyout(primaryCommands: primary, secondaryCommands: secondary,
                        alwaysExpanded: true, theme: requested, reduceMotion: true)
                } else {
                    self.command = FluentCommandBarFlyout(primaryCommands: primary, secondaryCommands: secondary,
                        alwaysExpanded: true, reduceMotion: true)
                }
            } else if let requested {
                menu = FluentMenuFlyout(items: items, theme: requested, reduceMotion: true)
            } else {
                menu = FluentMenuFlyout(items: items, reduceMotion: true)
            }
            window.orderFront(nil)
        }
        func open(at target: NSView? = nil) throws -> NSWindow {
            let target = target ?? anchor
            command?.present(relativeTo: target)
            menu?.present(relativeTo: target)
            return try XCTUnwrap(target.window?.childWindows?.first)
        }
        func dismiss() { menu?.dismiss(animated: false); command?.dismiss() }
        func close() { dismiss(); window.close() }
        func update(_ theme: FluentTheme) {
            menu?.update(items: items, theme: theme)
            command?.update(theme: theme)
        }
    }

    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    private func surface(_ panel: NSWindow) throws -> FluentMaterialView {
        try XCTUnwrap(all(try XCTUnwrap(panel.contentView)).compactMap { $0 as? FluentMaterialView }.first)
    }
    private func row(_ title: String, in panel: NSWindow) throws -> NSView {
        try XCTUnwrap(all(try XCTUnwrap(panel.contentView)).first { $0.accessibilityTitle() == title })
    }
    private func check(_ panel: NSWindow, theme: FluentTheme, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try surface(panel).fluentTheme, theme, file: file, line: line)
        XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                       theme.isDark ? .darkAqua : .aqua, file: file, line: line)
    }
    private func theme(dark: Bool) -> FluentTheme {
        .custom(accent: .magenta, material: .nativeAcrylic, colorScheme: dark ? .dark : .light,
                materialEffectsEnabled: false)
    }
    private func verifyExplicitTheme(command: Bool) throws {
        for dark in [false, true] {
            let requested = theme(dark: dark)
            let root = theme(dark: !dark).with(accent: .systemBlue)
            let f = Fixture(command: command, requested: requested, root: root); defer { f.close() }
            let panel = try f.open()
            try check(panel, theme: requested)
            f.coordinator?.updateTheme(root.with(accent: .systemGreen))
            XCTAssertTrue(f.window.childWindows?.first === panel)
            try check(panel, theme: requested)
        }
    }

    func testExplicitMenuThemeSurvivesCoordinatorRegistrationAndUpdates() throws { try verifyExplicitTheme(command: false) }
    func testExplicitCommandThemeSurvivesCoordinatorRegistrationAndUpdates() throws { try verifyExplicitTheme(command: true) }

    func testDefaultPresentersFollowCoordinatorAndLocalNativeAppearance() throws {
        for command in [false, true] {
            let root = theme(dark: false)
            let f = Fixture(command: command, requested: nil, root: root); defer { f.close() }
            let panel = try f.open()
            try check(panel, theme: root)
            let next = theme(dark: true).with(accent: .systemGreen)
            f.coordinator?.updateTheme(next)
            try check(panel, theme: next)
            let surface = try surface(panel)
            f.container.appearance = NSAppearance(named: .aqua)
            waitForUI(surface.fluentTheme?.colorScheme == .light)
            try check(panel, theme: next.with(colorScheme: .light))
            XCTAssertTrue(f.window.childWindows?.first === panel)
        }
    }

    func testPublicMenuUpdateKeepsItsThemeAndOpenSubmenuIdentity() throws {
        let f = Fixture(command: false, requested: nil, root: theme(dark: false)); defer { f.close() }
        let panel = try f.open(), branch = try row("Branch", in: panel)
        XCTAssertTrue(branch.accessibilityPerformPress())
        let child = try XCTUnwrap(panel.childWindows?.first), leaf = try row("Leaf", in: child)
        let focus = child.firstResponder
        let requested = theme(dark: true)
        f.update(requested)
        f.coordinator?.updateTheme(theme(dark: false).with(accent: .systemGreen))
        try check(panel, theme: requested)
        try check(child, theme: requested)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertTrue(panel.childWindows?.first === child)
        XCTAssertTrue(try row("Branch", in: panel) === branch)
        XCTAssertTrue(try row("Leaf", in: child) === leaf)
        XCTAssertTrue(child.firstResponder === focus)
        XCTAssertTrue(leaf.accessibilityPerformPress())
        XCTAssertFalse(f.menu?.isPresented == true)
    }

    func testPublicCommandUpdateKeepsItsThemeToggleAndFocus() throws {
        let f = Fixture(command: true, requested: nil, root: theme(dark: false)); defer { f.close() }
        let panel = try f.open(), toggle = try row("Toggle", in: panel)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        panel.makeFirstResponder(toggle)
        let requested = theme(dark: true)
        f.update(requested)
        f.coordinator?.updateTheme(theme(dark: false).with(accent: .systemGreen))
        try check(panel, theme: requested)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertTrue(try row("Toggle", in: panel) === toggle)
        XCTAssertTrue(panel.firstResponder === toggle)
        XCTAssertEqual(toggle.accessibilityValue() as? String, "On")
    }

    func testRepeatingTheCurrentThemeStillCreatesAnExplicitOverride() throws {
        for command in [false, true] {
            let requested = theme(dark: false)
            let f = Fixture(command: command, requested: nil, root: requested); defer { f.close() }
            let panel = try f.open()
            f.update(requested)
            f.coordinator?.updateTheme(theme(dark: true))
            try check(panel, theme: requested)
        }
    }

    func testCommandBuilderDistinguishesDefaultAndExplicitThemes() throws {
        for explicit in [false, true] {
            let root = theme(dark: true), requested = theme(dark: false)
            let f = Fixture(command: true, requested: nil, root: root); defer { f.close() }
            if explicit {
                f.command = FluentCommandBarFlyout(theme: requested, reduceMotion: true,
                    primaryCommands: { FluentCommandBarItem("Run", systemImageName: "play") {} })
            } else {
                f.command = FluentCommandBarFlyout(reduceMotion: true,
                    primaryCommands: { FluentCommandBarItem("Run", systemImageName: "play") {} })
            }
            let panel = try f.open()
            try check(panel, theme: explicit ? requested : root)
            let next = root.with(accent: .systemGreen)
            f.coordinator?.updateTheme(next)
            try check(panel, theme: explicit ? requested : next)
        }
    }

    func testRequestedSystemThemeFollowsPlainWindowChanges() throws {
        for command in [false, true] { for dark in [false, true] {
            let requested = theme(dark: false).with(colorScheme: .system)
            let f = Fixture(command: command, requested: requested, dark: dark); defer { f.close() }
            let panel = try f.open(), surface = try surface(panel)
            try check(panel, theme: requested.with(colorScheme: dark ? .dark : .light))
            f.window.appearance = NSAppearance(named: dark ? .aqua : .darkAqua)
            waitForUI(surface.fluentTheme?.colorScheme == (dark ? .light : .dark))
            try check(panel, theme: requested.with(colorScheme: dark ? .light : .dark))
            XCTAssertTrue(f.window.childWindows?.first === panel)
        } }
    }

    func testDefaultAndSystemThemesInheritAncestorAppearanceAndClearOverride() throws {
        for command in [false, true] { for useDefault in [false, true] {
            let requested = useDefault ? FluentTheme() : theme(dark: false).with(colorScheme: .system)
            let f = Fixture(command: command, requested: useDefault ? nil : requested); defer { f.close() }
            f.container.appearance = NSAppearance(named: .darkAqua)
            let panel = try f.open(), surface = try surface(panel)
            try check(panel, theme: requested.with(colorScheme: .dark))
            f.container.appearance = nil
            waitForUI(surface.fluentTheme?.colorScheme == .light)
            try check(panel, theme: requested.with(colorScheme: .light))
        } }
    }

    func testExplicitThemesIgnorePlainWindowAndAncestorAppearanceChanges() throws {
        for command in [false, true] {
            let requested = theme(dark: false)
            let f = Fixture(command: command, requested: requested); defer { f.close() }
            let panel = try f.open()
            f.window.appearance = NSAppearance(named: .darkAqua)
            f.container.appearance = NSAppearance(named: .darkAqua)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            try check(panel, theme: requested)
        }
    }

    func testReopenedSystemThemeUsesNewAnchorAndStopsObservingOldWindow() throws {
        for command in [false, true] {
            let requested = theme(dark: false).with(colorScheme: .system)
            let f = Fixture(command: command, requested: requested); defer { f.close() }
            _ = try f.open(); f.dismiss()
            let second = NSWindow(contentRect: f.container.bounds, styleMask: [.titled], backing: .buffered, defer: false)
            second.isReleasedWhenClosed = false; second.animationBehavior = .none
            defer { f.dismiss(); second.close() }
            second.appearance = NSAppearance(named: .darkAqua)
            let anchor = NSView(frame: f.anchor.frame)
            second.contentView!.addSubview(anchor); second.orderFront(nil)
            let panel = try f.open(at: anchor), surface = try surface(panel)
            try check(panel, theme: requested.with(colorScheme: .dark))
            f.window.appearance = NSAppearance(named: .darkAqua)
            second.appearance = NSAppearance(named: .aqua)
            waitForUI(surface.fluentTheme?.colorScheme == .light)
            try check(panel, theme: requested.with(colorScheme: .light))
            f.window.appearance = NSAppearance(named: .aqua)
            f.window.appearance = NSAppearance(named: .darkAqua)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            try check(panel, theme: requested.with(colorScheme: .light))
        }
    }
}
