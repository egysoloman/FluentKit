import AppKit
import FluentKit

@main struct MenuHierarchyAudit {
    @MainActor private static func capture(_ panels: [NSWindow], path: String) throws -> [Double] {
        // Flush and wait for both presenters before capturing the root window group.
        // Screen-region captures can include other applications' floating windows.
        for panel in panels { panel.displayIfNeeded() }
        CATransaction.flush()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let rectangles = panels.compactMap { panel -> CGRect? in
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(panel.windowNumber)) as? [[String: Any]]
                guard let row = info?.first, row[kCGWindowIsOnscreen as String] as? Bool == true,
                      let bounds = row[kCGWindowBounds as String] as? [String: Double],
                      let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
            if rectangles.count == panels.count, let first = rectangles.first {
                let bounds = rectangles.dropFirst().reduce(first) { $0.union($1) }.integral
                let rectangle = [bounds.minX, bounds.minY, bounds.width, bounds.height].map { Int($0) }
                let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                shot.arguments = ["-x", "-o", "-l", String(panels[0].windowNumber), path]
                try shot.run(); shot.waitUntilExit()
                guard shot.terminationStatus == 0 else { throw NSError(domain: "MenuHierarchyAudit.Capture", code: Int(shot.terminationStatus)) }
                return rectangle.map(Double.init)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        throw NSError(domain: "MenuHierarchyAudit.PanelNotOnscreen", code: 1)
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func rows(_ w: NSWindow) -> [NSView] {
            w.contentView.map { all($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } } ?? []
        }
        func key(_ code: UInt16, _ w: NSWindow) {
            NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: w.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!)
        }
        var samples: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] {
            for action in ["selection", "childFocus", "escape", "back", "returnOwner", "reopen", "dismissReopen", "rootFocus"] {
                let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 650, height: 400),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; defer { window.close() }
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let anchor = NSView(frame: NSRect(x: rtl ? 400 : 40, y: 280, width: 150, height: 32))
                anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                window.contentView?.addSubview(anchor); window.makeKeyAndOrderFront(nil)
                let menu = FluentMenuFlyout(items: [
                    FluentMenuItem(id: "branch", "Branch", submenu: [
                        FluentMenuItem("Disabled", isEnabled: false) {}, .separator,
                        FluentMenuItem("Deep", submenu: [FluentMenuItem("Leaf") {}], action: {}),
                        FluentMenuItem("Sibling") {}
                    ], action: {}), FluentMenuItem("Other") {}
                ], theme: .custom(colorScheme: dark ? .dark : .light), reduceMotion: true)
                defer { menu.dismiss(animated: false) }
                FluentInputDeviceTracker.shared.record(action == "rootFocus" ? .keyboard : .mouse, in: window)
                menu.present(relativeTo: anchor)
                guard let root = window.childWindows?.first else { throw NSError(domain: "MenuHierarchyAudit", code: 1) }
                let initiallyKey = root.isKeyWindow
                var passed = false
                var child: NSWindow?
                let open: UInt16 = rtl ? 123 : 124, back: UInt16 = rtl ? 124 : 123
                switch action {
                case "selection":
                    key(115, root)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.26))
                    passed = (root.childWindows?.isEmpty ?? true) && rows(root)[0].isAccessibilitySelected()
                case "childFocus":
                    key(115, root); key(open, root)
                    child = root.childWindows?.first
                    passed = child.map { rows($0).filter { $0.isAccessibilitySelected() }.map { $0.accessibilityTitle() } == ["Deep"] } == true
                case "escape":
                    key(115, root); key(open, root)
                    if let middle = root.childWindows?.first {
                        let responder = middle.firstResponder
                        child = middle; key(115, middle); key(open, middle)
                        if let leaf = middle.childWindows?.first {
                            key(53, leaf)
                            passed = menu.isPresented && (root.childWindows?.first === middle) && !leaf.isVisible
                                && middle.firstResponder === responder && (!initiallyKey || middle.isKeyWindow)
                                && rows(middle).contains { $0.accessibilityTitle() == "Deep" && $0.isAccessibilitySelected() }
                        }
                    }
                case "back":
                    key(115, root); key(back, root)
                    passed = menu.isPresented && (window.childWindows?.first === root)
                case "returnOwner":
                    _ = rows(root)[0].accessibilityPerformPress()
                    if let middle = root.childWindows?.first {
                        key(back, middle)
                        passed = menu.isPresented && !middle.isVisible && rows(root)[0].isAccessibilitySelected()
                    }
                case "reopen":
                    menu.update(items: [FluentMenuItem("Replace") { [weak menu, weak anchor] in
                        guard let menu, let anchor else { return }
                        menu.update(items: [FluentMenuItem("Replacement") {}]); menu.present(relativeTo: anchor)
                    }])
                    key(115, root); key(36, root)
                    passed = menu.isPresented && window.childWindows?.first !== root
                        && window.childWindows?.first.map { rows($0).first?.accessibilityTitle() == "Replacement" } == true
                case "dismissReopen":
                    var replacement: NSWindow?
                    menu.onDismiss = { [weak menu, weak anchor, weak window] in
                        guard let menu, let anchor else { return }
                        menu.onDismiss = nil
                        menu.present(relativeTo: anchor)
                        replacement = window?.childWindows?.first
                    }
                    menu.present(relativeTo: anchor)
                    passed = window.childWindows?.count == 1 && window.childWindows?.first === replacement
                    menu.dismiss(animated: false)
                    passed = passed && (window.childWindows?.isEmpty ?? true)
                default:
                    passed = rows(root)[0].isAccessibilitySelected()
                }
                var sample: [String: Any] = ["dark": dark, "rtl": rtl, "action": action, "passed": passed,
                    "applicationActive": NSApp.isActive, "initiallyKey": initiallyKey,
                    "rootKey": root.isKeyWindow, "childKey": child?.isKeyWindow ?? false,
                    "rootVisible": menu.isPresented, "rootSelection": rows(root).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() },
                    "childSelection": child.map { rows($0).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() } } ?? []]
                if action == "escape", passed, let child, let folder = ProcessInfo.processInfo.environment["FLUENTKIT_MENU_CAPTURE_DIR"] {
                    let path = URL(fileURLWithPath: folder).appendingPathComponent("\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-hierarchy.png").path
                    sample["captureBounds"] = try capture([root, child], path: path)
                    sample["capture"] = path
                }
                samples.append(sample)
            }
        } }
        print(String(decoding: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
