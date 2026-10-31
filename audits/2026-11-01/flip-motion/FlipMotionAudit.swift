import AppKit
import FluentKit

private final class FlipAuditPage: NSView {
    let index: Int
    init(_ index: Int) { self.index = index; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        [NSColor.red, .green, .blue][index % 3].setFill(); bounds.fill()
        ("Page \(index)" as NSString).draw(at: NSPoint(x: 50, y: 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.white])
    }
}

@main struct FlipMotionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var rows: [[String: Any]] = []
        for vertical in [false, true] { for rtl in [false, true] {
            let selected = FluentState(wrappedValue: 0)
            var builds = 0, callbacks: [Int] = []
            let context = FluentRenderContext(reduceMotion: false, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            func definition() -> some FluentUpdatablePrimitiveView {
                FluentFlipView(Array(0..<1000), selection: selected.projectedValue,
                    orientation: vertical ? .vertical : .horizontal, onSelectionChanged: { callbacks.append($0) }) { index in
                    FluentNativeView(make: {
                        builds += 1
                        return FlipAuditPage(index)
                    }, update: { (_: NSView, _) in })
                }
            }
            let native = definition()._makeView(in: context)
            let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 400, height: 240),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = native; window.makeKeyAndOrderFront(nil)
            native.layoutSubtreeIfNeeded(); native.displayIfNeeded(); CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            let container = native.subviews.first { $0.identifier?.rawValue == "FluentKit.FlipView.Content" }!
            let variant = (vertical ? "vertical" : "horizontal") + (rtl ? "-rtl" : "-ltr")
            func key(_ code: UInt16) {
                native.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
            }
            func record(_ state: String, image: Bool = true) throws {
                native.layoutSubtreeIfNeeded(); native.displayIfNeeded(); CATransaction.flush()
                func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
                let pages = container.subviews.map { view -> [String: Any] in
                    let transform = view.layer?.presentation()?.transform ?? view.layer!.transform
                    return ["id": view.identifier!.rawValue, "hidden": view.isHidden,
                            "position": vertical ? view.frame.minY + transform.m42 : view.frame.minX + transform.m41]
                }
                rows.append(["variant": variant, "state": state, "selected": selected.wrappedValue,
                    "pages": pages, "mounted": pages.count, "builds": builds, "callbacks": callbacks,
                    "contentBounds": all(container).compactMap { ($0 as? FlipAuditPage).map { ["index": String($0.index), "bounds": NSStringFromRect($0.bounds)] } }])
                if image {
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(container.bounds.width * 2), pixelsHigh: Int(container.bounds.height * 2),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext; cg.scaleBy(x: 2, y: 2)
                    (container.layer!.presentation() ?? container.layer!).render(in: cg)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(state).png"))
                }
            }
            let next: UInt16 = vertical ? 125 : rtl ? 123 : 124
            let previous: UInt16 = vertical ? 126 : rtl ? 124 : 123
            try record("initial")
            key(next); CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025)); try record("first")
            key(next); try record("interrupted")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025)); try record("before-reverse")
            key(previous); try record("reversed")
            for _ in 0..<20 { key(next) }; try record("burst")
            for index in 0..<16 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)); try record("burst-frame-\(index)", image: false)
            }
            try record("settled")
            selected.wrappedValue = 999
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04)); try record("jump")
            window.setContentSize(NSSize(width: 520, height: 300)); native.layoutSubtreeIfNeeded()
            try record("resized")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3)); try record("final")
            var reduced = context; reduced.reduceMotion = true
            _ = definition()._updateView(native, in: reduced)
            key(previous); try record("reduced")
            window.close()
        }}
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
