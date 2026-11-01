import AppKit
import FluentKit

@main struct MenuPointerAudit {
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
            all(w.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
        }
        func viewport(_ w: NSWindow) -> NSView { all(w.contentView!).compactMap { $0 as? NSScrollView }.first!.superview! }
        func pointer(_ view: NSView, _ entered: Bool) {
            let event = NSEvent.enterExitEvent(with: entered ? .mouseEntered : .mouseExited,
                location: entered ? view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) : NSPoint(x: -30, y: -30),
                modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil,
                eventNumber: 1, trackingNumber: 0, userData: nil)!
            if entered { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
        }
        func wait(_ predicate: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(2)
            while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            return predicate()
        }
        func observeDelay() { RunLoop.main.run(until: Date().addingTimeInterval(0.26)) }
        func open(_ w: NSWindow) throws -> NSWindow {
            pointer(viewport(w), true); pointer(rows(w)[0], true)
            guard wait({ w.childWindows?.isEmpty == false }), let child = w.childWindows?.first else {
                throw NSError(domain: "MenuPointerAudit.Open", code: 1)
            }
            return child
        }
        func alpha(_ row: NSView) -> CGFloat {
            guard let bitmap = row.bitmapImageRepForCachingDisplay(in: row.bounds) else { return -1 }
            row.cacheDisplay(in: row.bounds, to: bitmap)
            return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 4)?.alphaComponent ?? -1
        }
        func contrast(_ theme: FluentTheme, appearance: NSAppearance) -> CGFloat {
            var foreground: NSColor?, background: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                foreground = theme.menuSubmenuOpenedForeground.usingColorSpace(.sRGB)
                background = theme.windowBackground.usingColorSpace(.sRGB)
            }
            guard let foreground, let background else { return 0 }
            func luminance(_ c: NSColor) -> CGFloat {
                let values = [c.redComponent, c.greenComponent, c.blueComponent].map {
                    $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
                }
                return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
            }
            let f = luminance(foreground), b = luminance(background)
            return (max(f, b) + 0.05) / (min(f, b) + 0.05)
        }
        var samples: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for highContrast in [false, true] {
            for action in ["leaveRoot", "leaveChild", "padding", "siblingRace", "grandchild", "disabled", "ownerPaint", "reorder"] {
                let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 650, height: 400),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; defer { window.close() }
                let anchor = NSView(frame: NSRect(x: rtl ? 400 : 40, y: 280, width: 150, height: 32))
                anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                window.contentView?.addSubview(anchor); window.makeKeyAndOrderFront(nil)
                let items: [FluentMenuItem] = [
                    .submenu(id: "branch", "First branch") {
                        FluentMenuItem.submenu("Deep branch") { FluentMenuItem("Deep leaf") {} }
                        FluentMenuItem("Leaf") {}
                    },
                    .submenu(id: "second", "Second branch") { FluentMenuItem("Second leaf") {} },
                    FluentMenuItem(id: "disabled", "Disabled", isEnabled: false) {}
                ]
                let theme = FluentTheme.custom(contrast: highContrast ? .high : .standard, colorScheme: dark ? .dark : .light)
                let menu = FluentMenuFlyout(items: items, theme: theme, reduceMotion: true)
                defer { menu.dismiss(animated: false) }
                FluentInputDeviceTracker.shared.record(.mouse, in: window)
                menu.present(relativeTo: anchor)
                guard let root = window.childWindows?.first else { throw NSError(domain: "MenuPointerAudit.Root", code: 1) }
                let row = rows(root)[0], child = try open(root)
                let expectedAppearance: NSAppearance.Name = highContrast
                    ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                    : (dark ? .darkAqua : .aqua)
                // AppKit can canonicalize the accessibility appearance aliases to Aqua/DarkAqua.
                let resolvedName = NSAppearance(named: expectedAppearance)?.name
                let appearancesMatch = root.effectiveAppearance.name == resolvedName
                    && child.effectiveAppearance.name == resolvedName
                let textContrast = contrast(theme, appearance: root.effectiveAppearance)
                var passed = false
                switch action {
                case "leaveRoot":
                    pointer(row, false); pointer(viewport(root), false)
                    passed = child.isVisible && wait { child.parent == nil } && !child.isVisible
                case "leaveChild":
                    pointer(row, false); pointer(viewport(root), false); pointer(viewport(child), true)
                    pointer(rows(child)[1], true); pointer(rows(child)[1], false); pointer(viewport(child), false)
                    passed = wait { child.parent == nil }
                case "padding", "ownerPaint":
                    pointer(row, false); pointer(viewport(root), false); pointer(viewport(child), true)
                    observeDelay()
                    passed = root.childWindows?.first === child
                    if action == "ownerPaint" {
                        passed = passed && row.isAccessibilityExpanded() && !row.isAccessibilitySelected()
                            && (highContrast ? alpha(row) == 0 : alpha(row) > 0)
                    }
                case "siblingRace":
                    pointer(rows(root)[1], true); pointer(viewport(child), true); pointer(rows(child)[1], true)
                    observeDelay(); passed = root.childWindows?.first === child
                case "grandchild":
                    let grandchild = try open(child)
                    pointer(row, false); pointer(viewport(root), false)
                    pointer(rows(child)[0], false); pointer(viewport(child), false); pointer(viewport(grandchild), true)
                    observeDelay(); passed = root.childWindows?.first === child && child.childWindows?.first === grandchild
                case "disabled":
                    pointer(row, false); pointer(rows(root)[2], true)
                    passed = wait { child.parent == nil }
                case "reorder":
                    pointer(row, false); pointer(viewport(child), true)
                    menu.update(items: items.reversed())
                    passed = root.childWindows?.first === child && row.isAccessibilityExpanded()
                        && row.frame.minY == rows(root).map(\.frame.minY).max()
                default: break
                }
                var sample: [String: Any] = ["dark": dark, "rtl": rtl, "highContrast": highContrast, "action": action,
                    "passed": passed && appearancesMatch && (!highContrast || textContrast >= 4.5),
                    "appearancesMatch": appearancesMatch, "expandedTextContrast": Double(textContrast),
                    "rootVisible": menu.isPresented, "childRetained": root.childWindows?.first === child,
                    "ownerExpanded": row.isAccessibilityExpanded(), "ownerSelected": row.isAccessibilitySelected(),
                    "ownerBackgroundAlpha": Double(alpha(row))]
                if action == "ownerPaint", sample["passed"] as? Bool == true,
                   let folder = ProcessInfo.processInfo.environment["FLUENTKIT_MENU_CAPTURE_DIR"] {
                    let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(highContrast ? "hc" : "standard")-pointer.png"
                    let path = URL(fileURLWithPath: folder).appendingPathComponent(name).path
                    sample["captureBounds"] = try capture([root, child], path: path)
                    sample["capture"] = path
                }
                samples.append(sample)
            }
        } } }
        print(String(decoding: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
