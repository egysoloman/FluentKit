import XCTest
@testable import FluentKit

@MainActor
final class SharedHoverEntryTests: XCTestCase {
    private struct HoverStyle: FluentCollectionItemStyle {
        func appearance(for configuration: FluentCollectionItemStyleConfiguration) -> FluentCollectionItemAppearance {
            .init(backgroundColor: configuration.controlState == .pointerOver ? .red : .clear,
                  contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
        }
    }

    @MainActor private final class Fixture {
        let kind: String
        let window: NSWindow
        let first: NSView
        let current: NSView
        var bar: FluentCommandBar?
        var menu: FluentMenuFlyout?
        let commands: [FluentCommandBarItem]
        let items: [FluentMenuItem]

        init(_ kind: String, disabled: Bool = false) throws {
            _ = NSApplication.shared
            self.kind = kind
            commands = [.init(id: 1, "One", systemImageName: "star", isEnabled: !disabled) {},
                        .init(id: 2, "Two", systemImageName: "pencil") {}]
            items = [.init(id: 1, "One", isEnabled: !disabled) {}, .init(id: 2, "Two") {}]
            window = NSWindow(contentRect: NSRect(x: 100, y: 180, width: 620, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            let anchor = NSView(frame: NSRect(x: 60, y: 260, width: 480, height: 48))
            window.contentView!.addSubview(anchor)
            window.orderFront(nil)
            let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
            if kind.hasPrefix("bar") || kind == "more" {
                let overflow = kind == "barSecondary"
                let view = FluentCommandBar(primaryCommands: overflow ? [] : commands,
                    secondaryCommands: overflow ? commands : [.init(id: 3, "Extra") {}])
                bar = view; view.theme = theme; view.reduceMotion = true
                anchor.addSubview(view); view.frame = anchor.bounds; view.layoutSubtreeIfNeeded()
                if overflow { view.setOpen(true, animated: false) }
                if kind == "more" {
                    first = try XCTUnwrap(view.subviews.first { $0.identifier?.rawValue == "FluentKit.CommandBar.MoreButton" })
                    (first as? NSControl)?.isEnabled = !disabled
                    current = view.primaryCommandViews[1]
                } else {
                    let controls = overflow ? view.secondaryCommandViews : view.primaryCommandViews
                    first = controls[0]; current = controls[1]
                }
            } else if kind == "menu" {
                let flyout = FluentMenuFlyout(items: items, theme: theme, reduceMotion: true)
                menu = flyout; flyout.present(relativeTo: anchor)
                let views = Self.all(try XCTUnwrap(window.childWindows?.first?.contentView))
                first = try XCTUnwrap(views.first { $0.accessibilityTitle() == "One" })
                current = try XCTUnwrap(views.first { $0.accessibilityTitle() == "Two" })
            } else {
                var snapshot = FluentCollectionSnapshot<String, Int>()
                snapshot.appendSections(["items"]); snapshot.appendItems([0, 1], toSection: "items")
                let definition = FluentCollection(snapshot: snapshot,
                    layout: kind == "list" ? .list() : .adaptiveGrid(minimumItemWidth: 80),
                    isEnabled: { $0 != (disabled ? 0 : -1) }, itemStyle: HoverStyle()) { FluentText("Item \($0)") }
                let host = definition._makeView(in: FluentRenderContext(theme: theme, reduceMotion: true))
                window.contentView!.addSubview(host)
                host.frame = NSRect(x: 40, y: 40, width: 360, height: 200)
                host.layoutSubtreeIfNeeded()
                let native = try XCTUnwrap(Self.all(host).compactMap { $0 as? NSCollectionView }.first)
                waitForUI(native.item(at: IndexPath(item: 1, section: 0)) != nil)
                first = try XCTUnwrap(native.item(at: IndexPath(item: 0, section: 0))?.view)
                current = try XCTUnwrap(native.item(at: IndexPath(item: 1, section: 0))?.view)
            }
        }

        static func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func close() { menu?.dismiss(animated: false); bar?.setOpen(false, animated: false); window.close() }
        func event(_ view: NSView) throws -> NSEvent {
            try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered,
                location: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil))
        }
        func color(_ view: NSView) throws -> [CGFloat] {
            let color: NSColor
            if let layer = view.layer?.sublayers?.first(where: {
                ["FluentKit.AppBarButton.InnerBorder", "FluentKit.CollectionItem.Surface"].contains($0.name ?? "")
            }) {
                color = try XCTUnwrap(layer.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
            } else {
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                color = try XCTUnwrap(bitmap.colorAt(x: Int(8 * CGFloat(bitmap.pixelsWide) / view.bounds.width),
                    y: Int(8 * CGFloat(bitmap.pixelsHigh) / view.bounds.height))?.usingColorSpace(.sRGB))
            }
            return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
        func mutate(_ mutation: String) {
            switch mutation {
            case "hide": first.isHidden = true
            case "clip": first.frame = first.frame.offsetBy(dx: 2000, dy: 0)
            default:
                if let bar {
                    if kind == "barPrimary" { bar.primaryCommands = [commands[1]] }
                    else if kind == "barSecondary" { bar.secondaryCommands = [commands[1]] }
                    else { bar.overflowButtonVisibility = .collapsed; bar.layoutSubtreeIfNeeded() }
                } else if let menu { menu.update(items: [items[1]]) }
                else { first.removeFromSuperview() }
            }
        }
    }

    private func verifyLateEnters(_ kinds: [String]) throws {
        for kind in kinds { for mutation in ["hide", "clip", "remove"] {
            let f = try Fixture(kind); defer { f.close() }
            let late = try f.event(f.first)
            f.mutate(mutation)
            let normal = try f.color(f.current)
            f.current.mouseEntered(with: try f.event(f.current))
            let hovered = try f.color(f.current)
            XCTAssertNotEqual(hovered, normal, "\(kind) \(mutation) establishes a visible hover")
            f.first.mouseEntered(with: late)
            XCTAssertEqual(try f.color(f.current), hovered, "\(kind) \(mutation)")
        } }
    }

    func testNativeCommandRowsIgnoreUnavailablePeerEnters() throws { try verifyLateEnters(["barPrimary", "barSecondary"]) }
    func testMoreIgnoresUnavailablePeerEnters() throws { try verifyLateEnters(["more"]) }
    func testMenuRowsIgnoreUnavailablePeerEnters() throws { try verifyLateEnters(["menu"]) }
    func testListAndGridIgnoreUnavailablePeerEnters() throws { try verifyLateEnters(["list", "grid"]) }

    func testOrderingOutPreventsLateEntersFromRepaintingControls() throws {
        for kind in ["barPrimary", "barSecondary", "more", "menu", "list", "grid"] {
            let f = try Fixture(kind); defer { f.close() }
            let normal = try f.color(f.first), late = try f.event(f.first)
            let targetWindow = try XCTUnwrap(f.first.window)
            f.first.mouseEntered(with: late)
            XCTAssertNotEqual(try f.color(f.first), normal, kind)
            targetWindow.orderOut(nil)
            XCTAssertEqual(try f.color(f.first), normal, "\(kind) clears on orderOut")
            f.first.mouseEntered(with: late)
            XCTAssertEqual(try f.color(f.first), normal, "\(kind) ignores a late enter while hidden")
        }
    }

    func testVisibleDisabledPeersStillReleaseTheCurrentHover() throws {
        for kind in ["barPrimary", "barSecondary", "more", "menu", "list", "grid"] {
            let f = try Fixture(kind, disabled: true); defer { f.close() }
            let normal = try f.color(f.current), disabled = try f.color(f.first)
            f.current.mouseEntered(with: try f.event(f.current))
            XCTAssertNotEqual(try f.color(f.current), normal, kind)
            f.first.mouseEntered(with: try f.event(f.first))
            XCTAssertEqual(try f.color(f.current), normal, kind)
            XCTAssertEqual(try f.color(f.first), disabled, kind)
        }
    }

    func testUnavailableOverflowPeerCannotCloseTheCurrentSubmenu() throws {
        for mutation in ["hide", "clip"] {
            let f = try Fixture("barSecondary"); defer { f.close() }
            let late = try f.event(f.first)
            f.mutate(mutation)
            let current = try XCTUnwrap(f.current as? FluentAppBarButton)
            current.flyoutItems = [FluentMenuItem("Leaf") {}]
            current.showFlyout()
            XCTAssertTrue(current.isFlyoutPresented)
            f.first.mouseEntered(with: late)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
            XCTAssertTrue(current.isFlyoutPresented, mutation)
            XCTAssertTrue(f.bar?.isOpen == true)
        }
    }
}
