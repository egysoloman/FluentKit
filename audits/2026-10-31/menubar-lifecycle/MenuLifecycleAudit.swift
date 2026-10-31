import AppKit
import FluentKit

@main struct MenuLifecycleAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func rows(_ panel: NSWindow?) -> [NSView] {
            panel?.contentView.map { descendants($0).filter { $0.identifier?.rawValue == "FluentKit.Menu.Item" }.sorted { $0.frame.minY < $1.frame.minY } } ?? []
        }
        func key(_ code: UInt16, _ panel: NSWindow) {
            panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
        }
        func capture(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); CATransaction.flush()
            let size = view.bounds.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
            view.layer!.render(in: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func clipCovers(_ panel: NSWindow?) -> Bool {
            guard let view = panel?.contentView, let layer = view.layer else { return false }
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); CATransaction.flush()
            func mask(_ layer: CALayer) -> CALayer? {
                if let m = layer.mask, m.name?.hasSuffix("RevealClip") == true { return m }
                return layer.sublayers?.compactMap { mask($0) }.first
            }
            return mask(layer)?.frame.contains(view.bounds) == true
        }
        var records: [[String: Any]] = []
        for dark in [false, true] {
            for rtl in [false, true] {
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
                func content(_ revision: Int = 0, reordered: Bool = false) -> FluentMenuBarView {
                    var leaves = [
                        FluentMenuItem(revision == 0 ? "PNG" : "PNG — updated export options", state: revision == 0 ? .off : .on) {},
                        FluentMenuItem("SVG", keyEquivalent: "e") {}
                    ]
                    if revision > 0 { leaves.append(FluentMenuItem("PDF", systemImageName: "doc.richtext") {}) }
                    let file = FluentMenuBarItem(id: "file", "File", items: [
                        FluentMenuItem("New document", systemImageName: "doc") {},
                        FluentMenuItem("Export", systemImageName: "square.and.arrow.up", submenu: leaves, action: {})
                    ])
                    let view = FluentMenuBarItem(id: "view", "View", items: [FluentMenuItem("Zoom") {}])
                    return FluentMenuBarView(items: reordered ? [view, file] : [file, view])
                }
                let bar = content()._makeView(in: context) as! FluentMenuBar
                bar.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 320),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let stage = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 320))
                stage.wantsLayer = true; stage.layer?.backgroundColor = theme.windowBackground.cgColor
                window.contentView = stage; stage.addSubview(bar)
                bar.frame = NSRect(x: 24, y: 240, width: 500, height: 40)
                window.makeKeyAndOrderFront(nil); bar.layoutSubtreeIfNeeded()
                bar.openItem(at: 0)
                let originalRoot = window.childWindows!.first!
                key(119, originalRoot); key(rtl ? 123 : 124, originalRoot)
                let originalChild = originalRoot.childWindows!.first!
                key(119, originalChild)
                let originalTop = bar.itemControlViews[0]
                let originalRows = rows(originalRoot)
                let originalLeaf = rows(originalChild).last!
                let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")"
                func record(_ phase: String) throws {
                    bar.layoutSubtreeIfNeeded()
                    let root = window.childWindows?.first
                    let child = root?.childWindows?.first
                    records.append(["variant": name, "phase": phase, "openIndex": bar.openItemIndex ?? -1,
                        "sameRoot": root === originalRoot, "sameChild": child === originalChild,
                        "retainedTop": bar.itemControlViews.contains { $0 === originalTop },
                        "retainedRootRows": rows(root).filter { row in originalRows.contains { $0 === row } }.count,
                        "retainedLeaf": rows(child).contains { $0 === originalLeaf },
                        "leafSelected": originalLeaf.isAccessibilitySelected(),
                        "rootClip": clipCovers(root), "childClip": clipCovers(child),
                        "childCount": rows(child).count, "childWidth": child?.frame.width ?? 0,
                        "rootDirection": rows(root).first?.userInterfaceLayoutDirection == .rightToLeft ? "rtl" : "ltr",
                        "windowsComparison": "pending"])
                    try capture(stage, "\(name)-\(phase)-bar")
                    if let root = root?.contentView { try capture(root, "\(name)-\(phase)-root") }
                    if let child = child?.contentView { try capture(child, "\(name)-\(phase)-child") }
                }
                try record("open")
                for _ in 0..<5 { _ = content()._updateView(bar, in: context); bar.layoutSubtreeIfNeeded() }
                try record("refresh")
                _ = content(1)._updateView(bar, in: context)
                try record("content")
                _ = content(1, reordered: true)._updateView(bar, in: context)
                try record("reorder")
                bar.userInterfaceLayoutDirection = rtl ? .leftToRight : .rightToLeft
                bar.needsLayout = true
                try record("direction")
                bar.closeMenu(); window.close()
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
