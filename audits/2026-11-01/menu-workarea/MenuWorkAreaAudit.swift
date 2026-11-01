import AppKit
import FluentKit

@main struct MenuWorkAreaAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        func key(_ code: UInt16, _ panel: NSWindow) {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            panel.firstResponder?.keyDown(with: e)
        }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for kind in ["long-title", "long-root", "long-submenu"] {
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            let screen = NSScreen.main!.visibleFrame
            let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 120, width: 700, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = window.contentView!
            root.wantsLayer = true; root.layer?.backgroundColor = theme.windowBackground.cgColor
            let anchor = NSView(frame: NSRect(x: 250, y: 180, width: 160, height: 32))
            anchor.wantsLayer = true; anchor.layer?.backgroundColor = theme.accent.cgColor
            anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            root.addSubview(anchor)
            window.makeKeyAndOrderFront(nil)
            let regular = (0..<50).map { (i: Int) in FluentMenuItem(id: i, "Option \(i)") {} }
            let items = kind == "long-title" ? [FluentMenuItem(String(repeating: "Long title 很长的菜单标题 ", count: 40)) {}] :
                kind == "long-root" ? regular : Array(regular.prefix(40)) + [FluentMenuItem(id: "branch", "Last branch", submenu: regular, action: {})]
            let menu = FluentMenuFlyout(items: items, theme: theme, matchesAnchorWidth: false, reduceMotion: true)
            menu.present(relativeTo: anchor)
            let panel = window.childWindows!.first!
            let originalContent = panel.contentView!
            let originalResponder = panel.firstResponder
            let variant = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(kind)"
            func capture(_ phase: String, active: NSWindow, requireLast: Bool = false) throws {
                let panels = [panel] + (panel.childWindows ?? [])
                let rows = all(active.contentView!).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }
                let last = rows.last!
                let lastRect = active.convertToScreen(last.convert(last.bounds, to: nil))
                let lastVisible = screen.contains(lastRect) && last.visibleRect.contains(last.bounds)
                records.append(["variant": variant, "phase": phase, "kind": kind, "panelFrames": panels.map { rect($0.frame) },
                    "fitsWorkArea": panels.allSatisfy { screen.contains($0.frame) }, "visible": panels.allSatisfy(\.isVisible),
                    "sameRootPanel": window.childWindows?.first === panel, "sameRootContent": panel.contentView === originalContent,
                    "sameRootResponder": panel.firstResponder === originalResponder,
                    "lastSelected": last.isAccessibilitySelected(), "lastVisible": lastVisible, "requireLast": requireLast,
                    "lastRowFrame": rect(lastRect), "rowCount": rows.count,
                    "scrollable": all(active.contentView!).contains { $0 is NSScrollView }, "screen": rect(screen), "scale": window.backingScaleFactor])
                root.displayIfNeeded()
                panels.forEach { $0.contentView!.displayIfNeeded() }
                CATransaction.flush()
                let scale = window.backingScaleFactor
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(screen.width * scale)), pixelsHigh: Int(ceil(screen.height * scale)),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: scale, y: scale)
                let surfaces = [(root, window.convertToScreen(root.convert(root.bounds, to: nil)))] + panels.map { ($0.contentView!, $0.frame) }
                for (view, frame) in surfaces {
                    cg.saveGState(); cg.translateBy(x: frame.minX - screen.minX, y: frame.minY - screen.minY)
                    if view.isFlipped { cg.translateBy(x: 0, y: view.bounds.height); cg.scaleBy(x: 1, y: -1) }
                    view.layer?.render(in: cg); cg.restoreGState()
                }
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(phase).png"))
            }
            try capture("opened", active: panel)
            key(119, panel)
            try capture("end", active: panel, requireLast: true)
            if kind == "long-submenu" {
                key(rtl ? 123 : 124, panel)
                let child = panel.childWindows!.first!
                try capture("child-opened", active: child)
                key(119, child)
                try capture("child-end", active: child, requireLast: true)
            }
            menu.dismiss(animated: false); window.close()
        }}}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
