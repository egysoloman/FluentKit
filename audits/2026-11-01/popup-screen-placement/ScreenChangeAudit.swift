import AppKit
import FluentKit

@main struct ScreenChangeAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] {
            for kind in ["combo", "menu", "command-bar", "command-flyout"] {
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                let context = FluentRenderContext(theme: theme, reduceMotion: true,
                    layoutDirection: rtl ? .rightToLeft : .leftToRight)
                let selection = FluentState<String?>(wrappedValue: "中文")
                var commits = 0
                let anchor: NSView
                let open: () -> Void
                let close: () -> Void
                switch kind {
                case "combo":
                    anchor = FluentComboBox(options: ["中文", "English", "日本語"], selection: selection.projectedValue)._makeView(in: context)
                    let native = all(anchor).compactMap { $0 as? NSComboBox }.first!
                    open = { native.performClick(nil) }; close = { native.performClick(nil) }
                case "command-bar":
                    let bar = FluentCommandBar(primaryCommands: [], secondaryCommands: [
                        FluentCommandBarItem("First", systemImageName: "doc") { commits += 1 },
                        FluentCommandBarItem("Second", systemImageName: "folder") { commits += 1 }
                    ])
                    bar.theme = theme; bar.reduceMotion = true
                    anchor = bar
                    open = { bar.setOpen(true, animated: false) }; close = { bar.setOpen(false, animated: false) }
                case "command-flyout":
                    anchor = NSView()
                    let flyout = FluentCommandBarFlyout(primaryCommands: [FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") { commits += 1 }],
                        secondaryCommands: [FluentCommandBarItem("Details") { commits += 1 }], alwaysExpanded: true,
                        theme: theme, reduceMotion: true)
                    open = { flyout.present(relativeTo: anchor, at: NSPoint(x: 100, y: 16)) }
                    close = { flyout.dismiss() }
                default:
                    anchor = NSView()
                    let menu = FluentMenuFlyout(items: [FluentMenuItem("First") { commits += 1 }, FluentMenuItem("Second") { commits += 1 }],
                        theme: theme, reduceMotion: true)
                    open = { menu.present(relativeTo: anchor, at: NSPoint(x: 100, y: 16)) }
                    close = { menu.dismiss(animated: false) }
                }
                anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                let screen = NSScreen.main!.visibleFrame
                let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 600, height: 400),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let root = window.contentView!
                root.wantsLayer = true; root.layer?.backgroundColor = theme.windowBackground.cgColor
                anchor.wantsLayer = true
                anchor.layer?.borderWidth = 1; anchor.layer?.borderColor = theme.accent.cgColor
                root.addSubview(anchor)
                anchor.frame = NSRect(x: 50, y: 240, width: 220, height: 48)
                window.makeKeyAndOrderFront(nil)
                anchor.layoutSubtreeIfNeeded()
                open()
                let panel = window.childWindows!.first!
                let content = panel.contentView!
                let originalFrame = panel.frame
                let originalResponder = panel.firstResponder
                let variant = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(kind)"
                func capture(_ phase: String) throws {
                    records.append(["variant": variant, "phase": phase, "kind": kind,
                        "panelFrame": rect(panel.frame), "movementX": panel.frame.minX - originalFrame.minX,
                        "anchorFrame": rect(window.convertToScreen(anchor.convert(anchor.bounds, to: nil))),
                        "samePanel": window.childWindows?.first === panel, "sameContent": panel.contentView === content,
                        "sameResponder": panel.firstResponder === originalResponder,
                        "selection": selection.wrappedValue ?? "", "commits": commits,
                        "visible": panel.isVisible, "screen": rect(screen), "scale": window.backingScaleFactor])
                    root.displayIfNeeded(); content.displayIfNeeded(); CATransaction.flush()
                    let rootRect = window.convertToScreen(root.convert(root.bounds, to: nil))
                    let canvas = rootRect.union(panel.frame).insetBy(dx: -8, dy: -8)
                    let scale = window.backingScaleFactor
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(canvas.width * scale)), pixelsHigh: Int(ceil(canvas.height * scale)),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                    cg.scaleBy(x: scale, y: scale)
                    for (view, screenRect) in [(root, rootRect), (content, panel.frame)] {
                        cg.saveGState()
                        cg.translateBy(x: screenRect.minX - canvas.minX, y: screenRect.minY - canvas.minY)
                        if view.isFlipped { cg.translateBy(x: 0, y: view.bounds.height); cg.scaleBy(x: 1, y: -1) }
                        view.layer?.render(in: cg)
                        cg.restoreGState()
                    }
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(phase).png"))
                }
                try capture("opened")
                anchor.setFrameOrigin(NSPoint(x: 130, y: 240))
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
                try capture("screen-notification")
                close(); window.close()
            }
        }}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
