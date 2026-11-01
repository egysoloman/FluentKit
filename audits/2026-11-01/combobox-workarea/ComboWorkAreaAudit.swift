import AppKit
import FluentKit

@main struct ComboWorkAreaAudit {
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
            for kind in ["long-title", "resize"] {
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                let context = FluentRenderContext(theme: theme, reduceMotion: true,
                    layoutDirection: rtl ? .rightToLeft : .leftToRight)
                let selection = FluentState<String?>(wrappedValue: "中文")
                let commits = 0
                let anchor: NSView
                let open: () -> Void
                let close: () -> Void
                let options = kind == "long-title" ? [String(repeating: "Long option 很长的选项 ", count: 40), "Second"] : ["First", "Second"]
                selection.wrappedValue = options[0]
                anchor = FluentComboBox(options: options, selection: selection.projectedValue)._makeView(in: context)
                let native = all(anchor).compactMap { $0 as? NSComboBox }.first!
                open = { native.performClick(nil) }; close = { native.performClick(nil) }
                anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                let screen = NSScreen.main!.visibleFrame
                let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 850, height: 400),
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
                        "selectionUnchanged": selection.wrappedValue == options[0], "commits": commits,
                        "fitsWorkArea": panel.frame.minX >= screen.minX && panel.frame.maxX <= screen.maxX,
                        "coversFaceplateWidth": panel.frame.width >= anchor.bounds.width,
                        "visible": panel.isVisible, "screen": rect(screen), "scale": window.backingScaleFactor])
                    root.displayIfNeeded(); content.displayIfNeeded(); CATransaction.flush()
                    let rootRect = window.convertToScreen(root.convert(root.bounds, to: nil))
                    let canvas = screen
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
                anchor.setFrameSize(NSSize(width: 600, height: 48))
                anchor.layoutSubtreeIfNeeded()
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
                try capture("resized")
                close(); window.close()
            }
        }}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
