import AppKit
@testable import FluentKit

@main
struct TooltipMotionAudit {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "FluentKit ToolTip Motion Audit"
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 260))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        window.contentView = root
        let theme = FluentTheme.custom(colorScheme: .dark, materialEffectsEnabled: false)
        let coordinator = FluentAppearanceCoordinator(theme: theme)
        coordinator.attach(to: window)
        let header = NSView(frame: NSRect(x: 0, y: 212, width: 600, height: 48))
        root.addSubview(header)
        window.applyFluentWindowControlsStyle(.windows, titleBarHeight: 48, hostedIn: header)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        root.layoutSubtreeIfNeeded()
        let controls = header.subviews.first { $0.identifier?.rawValue == "FluentKit.WindowControls.Windows" }!
        let hosts = controls.subviews.compactMap { $0 as? FluentToolTipHost }
        precondition(hosts.count == 3)
        if CommandLine.arguments.contains("--interactive") {
            Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { _ in NSApp.terminate(nil) }
            app.run()
            return
        }
        var records: [[String: Any]] = []
        let started = Date()

        func event(_ host: FluentToolTipHost, x: CGFloat = 20, y: CGFloat = 20) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: host.convert(NSPoint(x: x, y: y), to: nil),
                modifierFlags: [], timestamp: Date.timeIntervalSinceReferenceDate,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        }
        func wait(_ interval: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(interval)) }
        func sample(_ stage: String, imageName: String? = nil) throws {
            root.layoutSubtreeIfNeeded()
            let panels = window.childWindows?.compactMap { $0 as? FluentToolTipPanel } ?? []
            let panel = panels.first
            var row: [String: Any] = ["stage": stage, "time": Date().timeIntervalSince(started), "panels": panels.count]
            if let panel, let surface = panel.contentView as? FluentToolTipSurface {
                surface.layoutSubtreeIfNeeded()
                row["frame"] = [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height]
                row["windowNumber"] = panel.windowNumber
                row["alpha"] = panel.alphaValue
                row["contentAlpha"] = surface.content.alphaValue
                row["text"] = (surface.content as? NSTextField)?.stringValue ?? "custom"
            }
            records.append(row)
            guard let imageName else { return }
            let scale: CGFloat = 2
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 520,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: scale, y: scale)
            root.displayIfNeeded()
            CATransaction.flush()
            root.layer?.render(in: cg)
            if let panel, let surface = panel.contentView {
                surface.displayIfNeeded()
                CATransaction.flush()
                let origin = window.convertPoint(fromScreen: panel.frame.origin)
                cg.saveGState()
                cg.translateBy(x: origin.x, y: origin.y)
                cg.setAlpha(panel.alphaValue)
                surface.layer?.render(in: cg)
                cg.restoreGState()
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(imageName))
        }
        hosts[0].mouseEntered(with: event(hosts[0]))
        wait(1.1)
        try sample("first", imageName: "01-first.png")
        hosts[0].mouseExited(with: event(hosts[0], x: 48))
        hosts[1].mouseEntered(with: event(hosts[1]))
        for frame in 0..<12 {
            try sample("to-second-\(frame)", imageName: frame == 4 ? "02-moving.png" : nil)
            wait(0.025)
        }
        try sample("second", imageName: "03-second.png")
        hosts[1].mouseExited(with: event(hosts[1], x: 48))
        hosts[2].mouseEntered(with: event(hosts[2]))
        wait(0.07)
        try sample("to-third", imageName: "04-interrupted.png")
        hosts[2].mouseExited(with: event(hosts[2], x: -2))
        hosts[0].mouseEntered(with: event(hosts[0]))
        for frame in 0..<12 {
            try sample("return-first-\(frame)")
            wait(0.025)
        }
        try sample("returned", imageName: "05-returned.png")
        coordinator.setPreference(.light)
        try sample("light", imageName: "06-light.png")
        hosts[0].mouseExited(with: event(hosts[0], x: -300, y: 200))
        for frame in 0..<18 {
            try sample("exit-\(frame)")
            wait(0.025)
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("samples.json"))
        hosts.forEach { $0.dismiss(animated: false) }
        window.orderOut(nil)
    }
}
