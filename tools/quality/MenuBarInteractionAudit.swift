import AppKit
import FluentKit

@main struct MenuBarInteractionAudit {
    @MainActor private static func capture(_ panels: [NSWindow], path: String) throws -> [Double] {
        // Flush and wait for the presenter before capturing its window group.
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
                guard shot.terminationStatus == 0 else { throw NSError(domain: "MenuBarInteractionAudit.Capture", code: Int(shot.terminationStatus)) }
                return rectangle.map(Double.init)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        throw NSError(domain: "MenuBarInteractionAudit.PanelNotOnscreen", code: 1)
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func rows(_ w: NSWindow?) -> [NSView] {
            w?.contentView.map { all($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" } } ?? []
        }
        func pointer(_ v: NSView, _ entering: Bool) {
            let event = NSEvent.enterExitEvent(with: entering ? .mouseEntered : .mouseExited,
                location: v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: v.window!.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil)!
            if entering { v.mouseEntered(with: event) } else { v.mouseExited(with: event) }
        }
        func mouse(_ v: NSView, type: NSEvent.EventType) {
            let event = NSEvent.mouseEvent(with: type,
                location: v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: v.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            if type == .leftMouseDown { v.mouseDown(with: event) } else { v.mouseDragged(with: event) }
        }
        func key(_ responder: NSResponder, _ window: NSWindow, code: UInt16, dispatch: Bool, repeating: Bool = false) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: repeating, keyCode: code)!
            if dispatch { NSApp.sendEvent(event) } else { responder.keyDown(with: event) }
        }
        func alpha(_ view: NSView) -> CGFloat {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 4)?.alphaComponent ?? -1
        }
        var samples: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] {
            for action in ["hover", "disabled", "cancel", "dismissPress", "keyCross", "access", "pointerCross", "repeat", "nativeKey"] {
                let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 650, height: 400),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; defer { window.close() }
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let bar = FluentMenuBar(items: [
                    FluentMenuBarItem(id: "file", "File", accessKey: "f", items: [
                        FluentMenuItem("Disabled", isEnabled: false) {}, .separator, FluentMenuItem("Open") {}]),
                    FluentMenuBarItem(id: "view", "View", items: [FluentMenuItem("Zoom") {}]),
                    FluentMenuBarItem(id: "disabled", "Disabled", isEnabled: false, items: [FluentMenuItem("Unavailable") {}])
                ])
                bar.theme = .custom(contrast: .standard, colorScheme: dark ? .dark : .light)
                bar.reduceMotion = true
                bar.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                bar.frame = NSRect(x: 20, y: 280, width: 600, height: 40)
                window.contentView?.addSubview(bar); window.makeKeyAndOrderFront(nil); bar.layoutSubtreeIfNeeded()
                defer { bar.closeMenu() }
                _ = FluentInputDeviceTracker.shared.lastDeviceType(in: window)
                FluentInputDeviceTracker.shared.record(.mouse, in: window)
                let a = bar.itemControlViews[0], b = bar.itemControlViews[1], disabled = bar.itemControlViews[2]
                var retainedRoot = true
                var passed = false
                switch action {
                case "hover":
                    pointer(a, true); pointer(b, true); pointer(a, false)
                    // The assertion is sampled before the late exit below in the unit fixture;
                    // this native sample also records the missed-exit state explicitly.
                    pointer(a, true); pointer(b, true)
                    passed = alpha(a) == 0 && alpha(b) > 0 && !bar.isFlyoutOpen
                case "disabled":
                    pointer(a, true); pointer(disabled, true)
                    passed = alpha(a) == 0 && alpha(disabled) == 0 && !bar.isFlyoutOpen
                case "cancel":
                    pointer(a, true)
                    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
                    passed = alpha(a) == 0 && !bar.isFlyoutOpen
                case "dismissPress":
                    mouse(a, type: .leftMouseDown); pointer(a, false); bar.closeMenu(); mouse(a, type: .leftMouseDragged)
                    passed = alpha(a) == 0 && !bar.isFlyoutOpen
                case "keyCross":
                    bar.openItem(at: 0)
                    guard let root = window.childWindows?.first, let responder = root.firstResponder else { throw NSError(domain: "MenuBarInteractionAudit.Root", code: 1) }
                    key(responder, root, code: rtl ? 123 : 124, dispatch: true)
                    passed = bar.openItemIndex == 1 && rows(window.childWindows?.first).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() } == ["Zoom"]
                case "access":
                    passed = bar.performAccessKey("f") && rows(window.childWindows?.first).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() } == ["Open"]
                case "pointerCross":
                    FluentInputDeviceTracker.shared.record(.keyboard, in: window)
                    bar.openItem(at: 0); pointer(b, true)
                    passed = bar.openItemIndex == 1 && rows(window.childWindows?.first).allSatisfy { !$0.isAccessibilitySelected() }
                case "repeat":
                    FluentInputDeviceTracker.shared.record(.keyboard, in: window)
                    key(a, window, code: 125, dispatch: false)
                    let root = window.childWindows?.first
                    key(a, window, code: 125, dispatch: false, repeating: true)
                    retainedRoot = root != nil && window.childWindows?.first === root
                    key(a, window, code: 36, dispatch: false)
                    retainedRoot = retainedRoot && window.childWindows?.first === root
                    passed = retainedRoot && bar.openItemIndex == 0
                case "nativeKey":
                    window.makeFirstResponder(a); key(a, window, code: 125, dispatch: true)
                    passed = rows(window.childWindows?.first).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() } == ["Open"]
                default: break
                }
                var sample: [String: Any] = ["dark": dark, "rtl": rtl, "action": action, "passed": passed,
                    "openIndex": bar.openItemIndex ?? -1, "firstAlpha": Double(alpha(a)), "secondAlpha": Double(alpha(b)),
                    "selectedRows": rows(window.childWindows?.first).filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() },
                    "retainedRoot": retainedRoot]
                if passed, ["hover", "keyCross"].contains(action),
                   let folder = ProcessInfo.processInfo.environment["FLUENTKIT_MENUBAR_CAPTURE_DIR"] {
                    let path = URL(fileURLWithPath: folder).appendingPathComponent("\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(action).png").path
                    sample["captureBounds"] = try capture([window.childWindows?.first ?? window], path: path)
                    sample["capture"] = path
                }
                samples.append(sample)
            }
        } }
        print(String(decoding: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
