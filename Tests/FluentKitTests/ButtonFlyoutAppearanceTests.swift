import XCTest
@testable import FluentKit

@MainActor
final class ButtonFlyoutAppearanceTests: XCTestCase {
    @MainActor private final class Fixture {
        let window: NSWindow
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 360))
        let owner = FluentButton(title: "Commands")
        init() {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 100, y: 180, width: 600, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView!.addSubview(container)
            container.addSubview(owner)
            owner.frame = NSRect(x: 120, y: 180, width: 180, height: 40)
            owner.theme = .custom(colorScheme: .light, materialEffectsEnabled: false)
            owner.reduceMotion = true
            window.orderFront(nil)
        }
        func close() { owner.flyoutItems = nil; owner.commandBarFlyoutConfiguration = nil; window.close() }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func open() throws -> NSWindow {
            owner.performClick(nil)
            waitForUI(window.childWindows?.isEmpty == false)
            return try XCTUnwrap(window.childWindows?.first)
        }
        func row(_ title: String, in panel: NSWindow) throws -> NSView {
            try XCTUnwrap(all(panel.contentView!).first { $0.accessibilityTitle() == title })
        }
        func configure(command: Bool) {
            if command {
                owner.commandBarFlyoutConfiguration = .init(primaryCommands: [
                    .toggle(id: 1, "Toggle", systemImageName: "bold", isOn: false) { _ in }],
                    secondaryCommands: [.init(id: 2, "Secondary") {}])
            } else { owner.flyoutItems = [.init(id: 1, "Menu", state: .on) {}] }
        }
    }

    func testButtonMenuUpdatesItsExistingRowAndAction() throws {
        let f = Fixture(); defer { f.close() }
        var oldCalls = 0, newCalls = 0
        f.owner.flyoutItems = [.init(id: 1, "Old") { oldCalls += 1 }]
        let panel = try f.open(), old = try f.row("Old", in: panel)
        f.owner.flyoutItems = [.init(id: 1, "New", keyEquivalent: "n") { newCalls += 1 }]
        XCTAssertTrue(f.window.childWindows?.first === panel)
        let updated = try f.row("New", in: panel)
        XCTAssertTrue(updated === old)
        XCTAssertTrue(updated.accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
    }

    func testEmptyButtonMenuClosesAndRetiresThePreviousRow() throws {
        let f = Fixture(); defer { f.close() }
        f.configure(command: false)
        let panel = try f.open(), row = try f.row("Menu", in: panel)
        f.owner.flyoutItems = []
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(row.accessibilityPerformPress())
        XCTAssertEqual(f.owner.accessibilityValue() as? String, f.owner.fluentControlString("Closed"))
    }

    func testThemeUpdatesPreservePanelControlsAndLocalToggleState() throws {
        for command in [false, true] {
            let f = Fixture(); defer { f.close() }
            f.configure(command: command)
            let panel = try f.open()
            let row = try f.row(command ? "Toggle" : "Menu", in: panel)
            if command { XCTAssertTrue(row.accessibilityPerformPress()) }
            let value = row.accessibilityValue() as? String
            let surface = try XCTUnwrap(f.all(panel.contentView!).compactMap { $0 as? FluentMaterialView }.first)
            let theme = FluentTheme.custom(colorScheme: .dark, materialEffectsEnabled: true)
                .with(materialConfiguration: .init(material: .nativeAcrylic, isEnabled: true), for: .transient)
            f.owner.theme = theme
            XCTAssertTrue(f.window.childWindows?.first === panel)
            XCTAssertTrue(try f.row(command ? "Toggle" : "Menu", in: panel) === row)
            XCTAssertEqual(row.accessibilityValue() as? String, value)
            XCTAssertEqual(surface.fluentTheme, theme)
            XCTAssertEqual(panel.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            XCTAssertEqual(surface.resolvedBackend,
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .opaque : .visualEffect)
        }
    }

    func testSystemThemesFollowWindowAndAncestorAppearanceInPlainWindows() throws {
        for command in [false, true] { for ancestor in [false, true] {
            let f = Fixture(); defer { f.close() }
            f.owner.theme = .custom(colorScheme: .system, materialEffectsEnabled: false)
            f.configure(command: command)
            let panel = try f.open()
            if ancestor { f.container.appearance = NSAppearance(named: .darkAqua) }
            else { f.window.appearance = NSAppearance(named: .darkAqua) }
            waitForUI(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            XCTAssertTrue(f.window.childWindows?.first === panel)
            let surface = try XCTUnwrap(f.all(panel.contentView!).compactMap { $0 as? FluentMaterialView }.first)
            XCTAssertEqual(surface.fluentTheme?.colorScheme, .dark)
            f.owner.theme = .custom(colorScheme: .light, materialEffectsEnabled: false)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
            f.container.appearance = NSAppearance(named: .aqua)
            f.container.appearance = NSAppearance(named: .darkAqua)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua,
                           "An explicit owner theme stays explicit")
        } }
    }

    func testCoordinatorStillUpdatesBothPresentersAndTheirCurrentActions() throws {
        for command in [false, true] {
            let f = Fixture(); defer { f.close() }
            let coordinator = FluentAppearanceCoordinator(theme: f.owner.theme)
            coordinator.attach(to: f.window)
            f.configure(command: command)
            let panel = try f.open()
            coordinator.updateTheme(.custom(colorScheme: .dark, materialEffectsEnabled: false))
            XCTAssertTrue(f.window.childWindows?.first === panel)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            XCTAssertTrue(try f.row(command ? "Toggle" : "Menu", in: panel).accessibilityPerformPress())
        }
    }

    func testReducedMotionSettlesAnActiveCommandExpansionWithoutResettingToggle() throws {
        let f = Fixture(); defer { f.close() }
        f.configure(command: true); f.owner.reduceMotion = false
        let panel = try f.open(), toggle = try f.row("Toggle", in: panel)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertTrue(try f.row("More", in: panel).accessibilityPerformPress())
        let layer = try XCTUnwrap(panel.contentView?.layer)
        XCTAssertNotNil(layer.mask)
        f.owner.reduceMotion = true
        XCTAssertNil(layer.mask)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertEqual(toggle.accessibilityValue() as? String, "On")
        f.owner.reduceMotion = false
        XCTAssertNil(layer.mask)
        XCTAssertTrue(layer.animationKeys()?.isEmpty != false)
        XCTAssertTrue(f.window.childWindows?.first === panel)
    }

    func testReducedMotionSettlesAnActiveMenuEntrance() throws {
        let f = Fixture(); defer { f.close() }
        f.configure(command: false); f.owner.reduceMotion = false
        let panel = try f.open()
        let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
        waitForUI(host.animationRoot.layer?.animationKeys()?.isEmpty == false)
        f.owner.reduceMotion = true
        XCTAssertTrue(host.animationRoot.layer?.animationKeys()?.isEmpty != false)
        XCTAssertTrue(host.revealMaskLayer.animationKeys()?.isEmpty != false)
        XCTAssertTrue(CATransform3DIsIdentity(try XCTUnwrap(host.animationRoot.layer).transform))
        f.owner.reduceMotion = false
        XCTAssertTrue(host.animationRoot.layer?.animationKeys()?.isEmpty != false)
        XCTAssertTrue(f.window.childWindows?.first === panel)
    }

    func testButtonUpdatesTheOpenSubmenuAndItsCurrentLeafAction() throws {
        let f = Fixture(); defer { f.close() }
        var oldCalls = 0, newCalls = 0
        f.owner.flyoutItems = [.submenu(id: "branch", "Branch") {
            FluentMenuItem(id: "leaf", "Old leaf") { oldCalls += 1 }
        }]
        let root = try f.open(), branch = try f.row("Branch", in: root)
        XCTAssertTrue(branch.accessibilityPerformPress())
        waitForUI(root.childWindows?.isEmpty == false)
        let child = try XCTUnwrap(root.childWindows?.first), leaf = try f.row("Old leaf", in: child)
        let focus = child.firstResponder
        f.owner.flyoutItems = [.submenu(id: "branch", "Renamed branch") {
            FluentMenuItem(id: "leaf", "New leaf") { newCalls += 1 }
        }]
        f.owner.theme = .custom(colorScheme: .dark, materialEffectsEnabled: false)
        XCTAssertTrue(f.window.childWindows?.first === root)
        XCTAssertTrue(root.childWindows?.first === child)
        XCTAssertTrue(child.firstResponder === focus)
        XCTAssertTrue(try f.row("Renamed branch", in: root) === branch)
        XCTAssertTrue(try f.row("New leaf", in: child) === leaf)
        XCTAssertEqual(child.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertTrue(leaf.accessibilityPerformPress())
        XCTAssertEqual(oldCalls, 0); XCTAssertEqual(newCalls, 1)
        XCTAssertFalse(root.isVisible); XCTAssertFalse(child.isVisible)
        XCTAssertFalse(leaf.accessibilityPerformPress())
    }

    func testButtonReducedMotionReachesAnOpenSubmenu() throws {
        let f = Fixture(); defer { f.close() }
        f.owner.flyoutItems = [.submenu(id: "branch", "Branch") { FluentMenuItem("Leaf") {} }]
        let root = try f.open()
        f.owner.reduceMotion = false
        XCTAssertTrue(try f.row("Branch", in: root).accessibilityPerformPress())
        waitForUI(root.childWindows?.isEmpty == false)
        let child = try XCTUnwrap(root.childWindows?.first)
        let host = try XCTUnwrap(child.contentView as? FluentPopupTransitionHost)
        waitForUI(host.animationRoot.layer?.animationKeys()?.isEmpty == false)
        f.owner.reduceMotion = true
        XCTAssertTrue(host.animationRoot.layer?.animationKeys()?.isEmpty != false)
        XCTAssertTrue(host.revealMaskLayer.animationKeys()?.isEmpty != false)
        XCTAssertTrue(root.childWindows?.first === child)
        f.owner.reduceMotion = false
        XCTAssertTrue(host.animationRoot.layer?.animationKeys()?.isEmpty != false)
    }

    func testThemeChangeSettlesMenuAndCommandAnimationsEvenWhenMotionStaysEnabled() throws {
        for command in [false, true] {
            let f = Fixture(); defer { f.close() }
            f.configure(command: command); f.owner.reduceMotion = false
            let panel = try f.open()
            if command {
                XCTAssertTrue(try f.row("More", in: panel).accessibilityPerformPress())
                XCTAssertNotNil(panel.contentView?.layer?.mask)
            } else {
                let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
                waitForUI(host.animationRoot.layer?.animationKeys()?.isEmpty == false)
            }
            f.owner.theme = .custom(colorScheme: .dark, materialEffectsEnabled: false)
            if command {
                XCTAssertNil(panel.contentView?.layer?.mask)
                XCTAssertTrue(panel.contentView?.layer?.animationKeys()?.isEmpty != false)
            } else {
                let host = try XCTUnwrap(panel.contentView as? FluentPopupTransitionHost)
                XCTAssertTrue(host.animationRoot.layer?.animationKeys()?.isEmpty != false)
                XCTAssertTrue(host.revealMaskLayer.animationKeys()?.isEmpty != false)
            }
            XCTAssertFalse(f.owner.reduceMotion)
            XCTAssertTrue(f.window.childWindows?.first === panel)
        }
    }

    func testLocalDeclarativeThemeSurvivesWindowCoordinatorTransactions() throws {
        for command in [false, true] {
            let f = Fixture(); defer { f.close() }
            f.owner.removeFromSuperview()
            let coordinator = FluentAppearanceCoordinator(theme: f.owner.theme)
            coordinator.attach(to: f.window)
            let declaration = FluentButtonView("Local",
                flyoutItems: command ? nil : [.init(id: 1, "Run") {}],
                commandBarFlyoutConfiguration: command ? .init(primaryCommands: [.init(id: 1, "Run") {}]) : nil)
                .fluentColorScheme(.dark)
            let host = FluentViewHost(declaration, context: FluentRenderContext(theme: f.owner.theme, reduceMotion: true))
            host.frame = NSRect(x: 120, y: 180, width: 180, height: 40)
            f.container.addSubview(host)
            let owner = try XCTUnwrap(f.all(host).compactMap { $0 as? FluentButton }.first)
            defer { owner.flyoutItems = nil; owner.commandBarFlyoutConfiguration = nil }
            owner.performClick(nil)
            waitForUI(f.window.childWindows?.isEmpty == false)
            let panel = try XCTUnwrap(f.window.childWindows?.first)
            XCTAssertEqual(owner.theme.colorScheme, .dark)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            coordinator.updateTheme(.custom(accent: .systemPink, colorScheme: .light, materialEffectsEnabled: false))
            XCTAssertTrue(f.window.childWindows?.first === panel)
            XCTAssertEqual(owner.theme.colorScheme, .dark)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            let surface = try XCTUnwrap(f.all(panel.contentView!).compactMap { $0 as? FluentMaterialView }.first)
            XCTAssertEqual(surface.fluentTheme, owner.theme)
        }
    }

    func testDirectAppearanceUpdatePreservesToggleAndCommandsAcrossPresentations() throws {
        let f = Fixture(); defer { f.close() }
        var values: [Bool] = []
        let flyout = FluentCommandBarFlyout(primaryCommands: [
            .toggle(id: 1, "Toggle", systemImageName: "bold", isOn: false) { values.append($0) }],
            theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: false)
        defer { flyout.dismiss() }
        flyout.present(relativeTo: f.owner)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let toggle = try f.row("Toggle", in: panel)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        flyout.update(theme: .custom(colorScheme: .dark, materialEffectsEnabled: false), reduceMotion: true)
        XCTAssertTrue(f.window.childWindows?.first === panel)
        XCTAssertEqual(toggle.accessibilityValue() as? String, "On")
        XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertEqual(panel.contentView?.layer?.opacity, 1)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(values, [true, false])
        flyout.dismiss()
        flyout.update(theme: .custom(colorScheme: .light, materialEffectsEnabled: false))
        flyout.present(relativeTo: f.owner)
        let next = try XCTUnwrap(f.window.childWindows?.first)
        XCTAssertEqual(next.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(next.contentView?.layer?.opacity, 1)
        XCTAssertEqual(try f.row("Toggle", in: next).accessibilityValue() as? String, "Off")
    }

    func testReducingMotionBeforeTheScheduledEntranceDoesNotReplayIt() throws {
        let f = Fixture(); defer { f.close() }
        let flyout = FluentCommandBarFlyout(primaryCommands: [.init("Run") {}], reduceMotion: false)
        defer { flyout.dismiss() }
        flyout.present(relativeTo: f.owner)
        let panel = try XCTUnwrap(f.window.childWindows?.first)
        let layer = try XCTUnwrap(panel.contentView?.layer)
        XCTAssertEqual(layer.opacity, 0)
        flyout.update(reduceMotion: true)
        XCTAssertEqual(layer.opacity, 1)
        flyout.update(reduceMotion: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertTrue(layer.animationKeys()?.isEmpty != false)
    }
}
