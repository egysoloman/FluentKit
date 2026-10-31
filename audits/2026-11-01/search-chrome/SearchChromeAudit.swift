import AppKit
import FluentKit

private final class ChromeRoot: NSView { override var isFlipped: Bool { true } }
@main struct SearchChromeAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func color(_ value: NSColor?) -> [CGFloat] {
            guard let c = value?.usingColorSpace(.deviceRGB) else { return [] }
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        for dark in [false, true] { for width: CGFloat in [220, 480] { for wrapped in [false, true] {
            let field = FluentSearchTextField(placeholder: "查找设置")
            field.theme = .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false)
            field.frame = NSRect(x: 20, y: 20, width: width, height: 32)
            let root = ChromeRoot(frame: NSRect(x: 0, y: 0, width: width + 40, height: 72))
            root.wantsLayer = true
            let captureView: NSView
            if wrapped {
                let host = FluentViewHost(FluentNativeView(field).frame(width: width, height: 32).background(.clear), context: .init(theme: field.theme))
                host.frame = NSRect(x: 20, y: 20, width: width, height: 32)
                host.wantsLayer = true
                root.addSubview(host); captureView = host
            } else {
                root.addSubview(field); captureView = field
            }
            let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = root; window.makeKeyAndOrderFront(nil); window.makeFirstResponder(nil)
            var hovered = false
            func hover(_ flag: Bool) {
                hovered = flag
                let event = NSEvent.enterExitEvent(with: flag ? .mouseEntered : .mouseExited, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
                if flag { field.mouseEntered(with: event) } else { field.mouseExited(with: event) }
            }
            func capture(_ state: String) throws {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
                root.layoutSubtreeIfNeeded(); root.display(); CATransaction.flush()
                let focused = window.firstResponder === field || (field.currentEditor() != nil && window.firstResponder === field.currentEditor())
                let appearance = field.fluentStyle.appearance(for: .init(isEnabled: field.isEnabled, isFocused: focused,
                    isPointerOver: hovered, controlSize: .regular, theme: field.theme))
                let name = "\(dark ? "dark" : "light")-\(Int(width))-\(wrapped ? "wrapped" : "bare")-\(state)"
                records.append(["name": name, "focused": focused, "enabled": field.isEnabled,
                    "nativeBezel": field.isBezeled, "nativeBorder": field.isBordered, "nativeBackground": field.drawsBackground,
                    "actualFrame": [field.frame.minX, field.frame.minY, field.frame.width, field.frame.height],
                    "requestedWidth": width, "wrapped": wrapped,
                    "radius": appearance.cornerRadius, "focusWidth": appearance.focusIndicatorWidth,
                    "fill": color(appearance.backgroundColor), "textColor": color(field.textColor),
                    "placeholderColor": color(field.placeholderAttributedString?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)])
                for scale: CGFloat in [1, 2] {
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(32 * scale),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
                    cg.scaleBy(x: scale, y: scale)
                    if !wrapped { cg.translateBy(x: 0, y: 32); cg.scaleBy(x: 1, y: -1) }
                    if wrapped {
                        captureView.layer!.render(in: cg)
                    } else {
                        field.draw(field.bounds)
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-\(Int(scale))x.png"))
                }
            }
            try capture("normal"); hover(true); try capture("hover"); hover(false)
            field.selectText(nil); try capture("focused")
            field.isEnabled = false; try capture("disabled-from-focus")
            window.makeFirstResponder(nil); try capture("disabled")
            field.isEnabled = true; try capture("reenabled")
            field.selectText(nil); try capture("refocused")
            window.makeFirstResponder(nil); try capture("blurred")
            window.close()
        }}}
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
