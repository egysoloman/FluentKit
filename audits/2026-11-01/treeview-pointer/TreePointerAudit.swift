import AppKit
import FluentKit

@main struct TreePointerAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        for dark in [false, true] { for rtl in [false, true] { for height: CGFloat in [32, 48] {
            let checked = FluentState(wrappedValue: Set<String>())
            let expanded = FluentState(wrappedValue: Set<String>())
            let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            let tree = FluentTreeView(nodes: [FluentTreeViewNode(id: "root", children: [
                FluentTreeViewNode(id: "child") { FluentText("Child") }
            ]) { FluentText("Root") }], selection: .multiple(checked.projectedValue), rowHeight: height).expandedIDs(expanded.projectedValue)
            let host = FluentViewHost(tree, context: FluentRenderContext(theme: theme, reduceMotion: true,
                layoutDirection: rtl ? .rightToLeft : .leftToRight))
            host.wantsLayer = true; host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let outline = all(host).compactMap { $0 as? NSOutlineView }.first!
            let cell = outline.view(atColumn: 0, row: 0, makeIfNecessary: true)!
            cell.layoutSubtreeIfNeeded()
            let inside = NSPoint(x: rtl ? cell.bounds.width - 30 : 30, y: height / 2)
            let outside = NSPoint(x: cell.bounds.width / 2, y: height / 2)
            let arrowPadding = NSPoint(x: rtl ? cell.bounds.width - 71 : 71, y: height / 2)
            let variant = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(Int(height))"
            func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: cell.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            }
            func capture(_ phase: String) throws {
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
                let box = cell.layer!.sublayers!.first { $0.sublayers?.contains(where: { $0 is CAShapeLayer }) == true }!
                records.append(["variant": variant, "phase": phase, "checked": checked.wrappedValue.sorted(),
                    "expanded": expanded.wrappedValue.sorted(), "boxFrame": NSStringFromRect(box.frame),
                    "fill": box.backgroundColor!.components!, "width": host.bounds.width])
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 260, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(phase).png"))
            }
            try capture("idle")
            cell.mouseMoved(with: event(.mouseMoved, inside)); try capture("hover")
            outline.mouseDown(with: event(.leftMouseDown, inside)); try capture("down")
            outline.mouseDragged(with: event(.leftMouseDragged, outside)); try capture("outside")
            outline.mouseUp(with: event(.leftMouseUp, outside)); try capture("cancelled")
            outline.mouseDown(with: event(.leftMouseDown, inside))
            outline.mouseDragged(with: event(.leftMouseDragged, outside))
            outline.mouseDragged(with: event(.leftMouseDragged, inside)); try capture("reentered")
            outline.mouseUp(with: event(.leftMouseUp, inside)); try capture("committed")
            // The baseline misses this target and enters AppKit's synchronous row tracking loop.
            // Padding baseline coverage uses the nonblocking hit-routing test instead.
            if !CommandLine.arguments.contains("--skip-chevron") {
                outline.mouseDown(with: event(.leftMouseDown, arrowPadding)); try capture("chevron-down")
                outline.mouseUp(with: event(.leftMouseUp, arrowPadding)); try capture("chevron-up")
            }
            window.close()
        } } }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
        print("Captured \(records.count) native pointer states; direct NSEvent delivery is not a hardware gesture test.")
    }
}
