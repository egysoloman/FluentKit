import AppKit
import FluentKit

@main struct PopupAnchorAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for kind in ["combo", "menu"] { for operation in ["width", "root-resize", "unload"] {
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            let state = FluentState<String?>(wrappedValue: "First")
            let anchor: NSView = kind == "combo" ? FluentComboBox(options: ["First", "Second"], selection: state.projectedValue)._makeView(in: context) : NSView()
            let menu = FluentMenuFlyout(items: [FluentMenuItem("First") {}, FluentMenuItem("Second") {}], theme: theme, reduceMotion: true)
            var dismissals = 0
            menu.onDismiss = { dismissals += 1 }
            anchor.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            let screen = NSScreen.main!.visibleFrame
            let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 600, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let root = window.contentView!
            root.wantsLayer = true; root.layer?.backgroundColor = theme.windowBackground.cgColor
            anchor.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(anchor)
            let width = anchor.widthAnchor.constraint(equalToConstant: 220)
            NSLayoutConstraint.activate([width, anchor.heightAnchor.constraint(equalToConstant: 32),
                anchor.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
                anchor.topAnchor.constraint(equalTo: root.topAnchor, constant: 120)])
            window.makeKeyAndOrderFront(nil); root.layoutSubtreeIfNeeded()
            let native = all(anchor).compactMap { $0 as? NSComboBox }.first
            if kind == "combo" { native!.performClick(nil) } else { menu.present(relativeTo: anchor) }
            settle()
            let panel = window.childWindows!.first!, content = panel.contentView!, responder = panel.firstResponder
            let variant = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(kind)-\(operation)"
            func capture(_ phase: String) throws {
                let closed = operation == "unload" && phase == "changed"
                let anchorRect = anchor.window.map { $0.convertToScreen(anchor.convert(anchor.bounds, to: nil)) }
                records.append(["variant": variant, "phase": phase, "kind": kind, "operation": operation,
                    "shouldClose": closed, "visible": panel.isVisible, "detached": panel.parent == nil,
                    "samePanel": window.childWindows?.first === panel, "sameContent": panel.contentView === content,
                    "sameResponder": panel.firstResponder === responder, "selectionUnchanged": state.wrappedValue == "First",
                    "dismissals": dismissals, "panelFrame": rect(panel.frame), "anchorFrame": anchorRect.map(rect) ?? [],
                    "widthMatches": abs(panel.frame.width - anchor.bounds.width) < 0.5,
                    "leadingMatches": anchorRect.map { abs((rtl ? panel.frame.maxX - $0.maxX : panel.frame.minX - $0.minX)) < 0.5 } ?? false,
                    "screen": rect(screen), "scale": window.backingScaleFactor])
                root.displayIfNeeded(); content.displayIfNeeded(); CATransaction.flush()
                let scale = window.backingScaleFactor
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(screen.width * scale)), pixelsHigh: Int(ceil(screen.height * scale)),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: scale, y: scale)
                var surfaces = [(root, window.convertToScreen(root.convert(root.bounds, to: nil)))]
                if panel.isVisible { surfaces.append((content, panel.frame)) }
                for (view, frame) in surfaces {
                    cg.saveGState(); cg.translateBy(x: frame.minX - screen.minX, y: frame.minY - screen.minY)
                    if view.isFlipped { cg.translateBy(x: 0, y: view.bounds.height); cg.scaleBy(x: 1, y: -1) }
                    view.layer?.render(in: cg); cg.restoreGState()
                }
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(phase).png"))
            }
            try capture("opened")
            switch operation {
            case "width": width.constant = 400; root.layoutSubtreeIfNeeded()
            case "root-resize": window.setContentSize(NSSize(width: 760, height: 400)); root.layoutSubtreeIfNeeded()
            default: anchor.removeFromSuperview()
            }
            settle(); try capture("changed")
            if kind == "combo", panel.isVisible { native!.performClick(nil) } else { menu.dismiss(animated: false) }
            window.close()
        }}}}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
