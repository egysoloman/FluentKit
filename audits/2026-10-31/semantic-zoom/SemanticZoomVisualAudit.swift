import AppKit
import FluentKit

@main struct SemanticZoomVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for variant in ["light", "dark", "rtl"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true, layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight)
            let zoomedIn = FluentState(wrappedValue: true)
            var destination: AnyHashable?
            let letters = ["A", "B", "G", "K", "L"]
            let host = FluentViewHost(FluentAnyView(FluentSemanticZoom(
                isZoomedInViewActive: zoomedIn.projectedValue, isZoomOutButtonEnabled: true,
                onViewChangeCompleted: { _, target in destination = target },
                zoomedInView: {
                    FluentVStack(spacing: 6) {
                        FluentAnyView(FluentForEach(letters, id: { $0 }) { letter in
                            FluentText("\(letter) — contacts starting with \(letter)", style: .body)
                        })
                    }.padding(12).frame(width: 320, height: 200)
                },
                zoomedOutView: { proxy in
                    FluentHStack(spacing: 8) {
                        FluentButtonView("A") { proxy.zoomIn(to: "A") }
                        FluentButtonView("B") { proxy.zoomIn(to: "B") }
                        FluentButtonView("G") { proxy.zoomIn(to: "G") }
                        FluentButtonView("K") { proxy.zoomIn(to: "K") }
                        FluentButtonView("L") { proxy.zoomIn(to: "L") }
                    }.padding(12).frame(width: 320, height: 200)
                }).frame(width: 320, height: 200)), context: context)
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            let zoom = descendants(host).first { $0.identifier?.rawValue == "FluentKit.SemanticZoom" }!
            let button = descendants(zoom).first { $0.identifier?.rawValue == "FluentKit.SemanticZoom.ZoomOutButton" }!
            func capture(_ state: String) throws {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                let scale: CGFloat = 2
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                    pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                cg.scaleBy(x: scale, y: scale)
                if host.isFlipped { cg.translateBy(x: 0, y: host.bounds.height); cg.scaleBy(x: 1, y: -1) }
                host.layer!.render(in: cg)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(state).png"))
                records.append(["variant": variant, "state": state, "zoomedIn": zoomedIn.wrappedValue,
                                "buttonVisible": !button.isHidden, "touchScreen": "pending device", "windowsComparison": "pending"])
            }
            try capture("zoomed-in")
            let move = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            zoom.mouseMoved(with: move)
            precondition(!button.isHidden, "Mouse movement reveals the zoom-out button")
            try capture("zoom-out-button")
            // Ctrl+minus zooms out.
            zoom.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27)!)
            precondition(zoomedIn.wrappedValue == false && button.isHidden)
            try capture("zoomed-out")
            let letterButton = descendants(zoom).first { ($0 as? NSButton)?.title == "K" || $0.accessibilityLabel() == "K" }
            _ = letterButton?.accessibilityPerformPress()
            if letterButton is NSButton { (letterButton as! NSButton).performClick(nil) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            precondition(zoomedIn.wrappedValue == true && destination == AnyHashable("K"), "Choosing a group zooms in to it")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
