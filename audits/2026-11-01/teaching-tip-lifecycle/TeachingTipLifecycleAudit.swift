import AppKit
import FluentKit

@main struct TeachingTipLifecycleAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func rect(_ r: NSRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] {
            for kind in ["detach", "reparent", "close", "resize"] {
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
                let context = FluentRenderContext(theme: theme, reduceMotion: true,
                    layoutDirection: rtl ? .rightToLeft : .leftToRight)
                let state = FluentState(wrappedValue: true)
                var opened = 0, closed = 0, closing = 0
                let tip = FluentButtonView("Target").teachingTip(isPresented: state.projectedValue,
                    title: "TeachingTip", placement: .top, shouldConstrainToRootBounds: false,
                    size: NSSize(width: 320, height: 100), onClosing: { _ in closing += 1 },
                    onClosed: { _ in closed += 1 }, onOpened: { opened += 1 }) { FluentText("Lifecycle audit") }
                let host = FluentViewHost(tip, context: context)
                host.translatesAutoresizingMaskIntoConstraints = true
                host.autoresizingMask = [.minXMargin]
                host.frame = NSRect(x: 280, y: 160, width: 100, height: 32)
                let screen = NSScreen.main!.visibleFrame
                func window() -> NSWindow {
                    let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 700, height: 400),
                        styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    window.contentView!.wantsLayer = true
                    window.contentView!.layer?.backgroundColor = theme.windowBackground.cgColor
                    window.orderFront(nil)
                    return window
                }
                let owner = window()
                let root = owner.contentView!
                root.addSubview(host)
                wait { opened == 1 }
                let panel = owner.childWindows!.first!
                let content = panel.contentView!
                let responder = panel.firstResponder
                let initialFrame = panel.frame
                let initialX = host.frame.minX
                let variant = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(kind)"
                func capture(_ phase: String) throws {
                    records.append(["variant": variant, "kind": kind, "phase": phase,
                        "panelFrame": rect(panel.frame), "visible": panel.isVisible, "hasParent": panel.parent != nil,
                        "binding": state.wrappedValue, "opened": opened, "closed": closed, "closing": closing,
                        "panelMovementX": panel.frame.minX - initialFrame.minX, "targetMovementX": host.frame.minX - initialX,
                        "sameContent": panel.contentView === content, "sameResponder": panel.firstResponder === responder,
                        "screen": rect(screen), "scale": owner.backingScaleFactor])
                    root.displayIfNeeded(); content.displayIfNeeded(); CATransaction.flush()
                    let rootRect = owner.convertToScreen(root.convert(root.bounds, to: nil))
                    let canvas = screen, scale = owner.backingScaleFactor
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(canvas.width * scale)), pixelsHigh: Int(ceil(canvas.height * scale)),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                    cg.scaleBy(x: scale, y: scale)
                    var views = [(root, rootRect)]
                    if panel.isVisible { views.append((content, panel.frame)) }
                    for (view, screenRect) in views {
                        cg.saveGState()
                        cg.translateBy(x: screenRect.minX - canvas.minX, y: screenRect.minY - canvas.minY)
                        if view.isFlipped { cg.translateBy(x: 0, y: view.bounds.height); cg.scaleBy(x: 1, y: -1) }
                        view.layer?.render(in: cg)
                        cg.restoreGState()
                    }
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(phase).png"))
                }
                try capture("opened")
                var other: NSWindow?
                switch kind {
                case "detach": host.removeFromSuperview()
                case "reparent": other = window(); other!.contentView!.addSubview(host)
                case "close": owner.close()
                default:
                    owner.setContentSize(NSSize(width: 800, height: 400))
                    root.layoutSubtreeIfNeeded()
                    wait { abs(panel.frame.minX - initialFrame.minX - (host.frame.minX - initialX)) < 0.5 }
                }
                try capture("changed")
                state.wrappedValue = false
                wait { !panel.isVisible }
                host.removeFromSuperview(); owner.close(); other?.close()
            }
        }}
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
