import AppKit
import FluentKit

@main struct CommandBarLifecycleAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            CATransaction.flush()
            let size = view.bounds.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
            view.layer!.render(in: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func revealMask(_ layer: CALayer) -> CALayer? {
            if let mask = layer.mask, mask.name?.hasSuffix("RevealClip") == true { return mask }
            return layer.sublayers?.compactMap { revealMask($0) }.first
        }
        var results: [[String: Any]] = []
        for dark in [false, true] {
            for rtl in [false, true] {
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                let direction: NSUserInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
                let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
                func content() -> FluentCommandBarView {
                    FluentCommandBarView(primaryCommands: [
                        FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") {},
                        FluentCommandBarItem("Paste", systemImageName: "doc.on.clipboard") {},
                        FluentCommandBarItem("Share", systemImageName: "square.and.arrow.up") {},
                        FluentCommandBarItem("Delete", systemImageName: "trash") {}
                    ], secondaryCommands: [FluentCommandBarItem("Settings", systemImageName: "gear") {}])
                }
                let bar = content()._makeView(in: context) as! FluentCommandBar
                bar.userInterfaceLayoutDirection = direction
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let stage = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
                stage.wantsLayer = true
                stage.layer?.backgroundColor = theme.windowBackground.cgColor
                window.contentView = stage
                stage.addSubview(bar)
                bar.frame = NSRect(x: 0, y: 180, width: 200, height: 64)
                window.makeKeyAndOrderFront(nil)
                bar.layoutSubtreeIfNeeded()
                bar.setOpen(true, animated: false)
                let primary = bar.primaryCommandViews
                let secondary = bar.secondaryCommandViews
                let originalPanel = window.childWindows!.first!
                originalPanel.makeFirstResponder(secondary[0])
                var events: [Bool] = []
                bar.onIsOpenChanged = { events.append($0) }
                let variant = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")"
                func record(_ phase: String) throws {
                    bar.layoutSubtreeIfNeeded()
                    let panel = window.childWindows?.first
                    let root = panel?.contentView
                    // AppKit attaches backing sublayers lazily; inspect the committed render tree.
                    root?.layoutSubtreeIfNeeded()
                    root?.displayIfNeeded()
                    CATransaction.flush()
                    let clip = root?.layer.flatMap { revealMask($0) }
                    let clipCoversPopup = root.map { clip?.frame.contains($0.bounds) == true } ?? false
                    results.append(["variant": variant, "phase": phase, "isOpen": bar.isOpen,
                        "width": bar.bounds.width, "overflow": bar.overflowedPrimaryIndexes,
                        "hiddenOverflowCount": bar.overflowedPrimaryIndexes.filter { bar.primaryCommandViews[$0].isHidden }.count,
                        "retainedPrimaryCount": zip(primary, bar.primaryCommandViews).filter { $0 === $1 }.count,
                        "retainedSecondaryCount": zip(secondary, bar.secondaryCommandViews).filter { $0 === $1 }.count,
                        "samePanel": panel === originalPanel, "sameFocus": panel?.firstResponder === secondary[0],
                        "openEvents": events, "clipCoversPopup": clipCoversPopup,
                        "clipFrame": clip.map { NSStringFromRect($0.frame) } ?? "missing",
                        "popupBounds": root.map { NSStringFromRect($0.bounds) } ?? "missing",
                        "windowsComparison": "pending"])
                    try capture(stage, "\(variant)-\(phase)-bar")
                    if let root = panel?.contentView { try capture(root, "\(variant)-\(phase)-popup") }
                }
                try record("open")
                for _ in 0..<5 { _ = content()._updateView(bar, in: context); bar.layoutSubtreeIfNeeded() }
                try record("refresh")
                if !bar.isOpen { bar.setOpen(true, animated: false) }
                bar.setFrameSize(NSSize(width: 360, height: 64))
                try record("wide")
                bar.setFrameSize(NSSize(width: 160, height: 64))
                try record("narrow")
                bar.setOpen(false, animated: false)
                window.close()
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
