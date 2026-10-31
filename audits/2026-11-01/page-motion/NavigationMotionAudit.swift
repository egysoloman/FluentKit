import AppKit
import FluentKit

final class NavigationAuditPage: NSView {
    let color: NSColor
    let name: String
    init(_ name: String, _ color: NSColor) {
        self.name = name; self.color = color
        super.init(frame: .zero); wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("Audit.Page." + name)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill(); bounds.fill()
        NSColor.white.setFill(); NSRect(x: 24, y: 12, width: 45, height: 25).fill()
        (name as NSString).draw(at: NSPoint(x: 100, y: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.white])
    }
}

@main struct NavigationMotionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func layers(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers) }
        var records: [[String: Any]] = []
        for mode in [FluentNavigationTransitionMode.slide, .entrance, .bottomUp, .drillIn, .crossFade] {
            for rtl in [false, true] {
                var selected: Int? = 0
                let pages = [NavigationAuditPage("A", .red), NavigationAuditPage("B", .green), NavigationAuditPage("C", .blue)]
                let context = FluentRenderContext(theme: .custom(colorScheme: .dark, materialEffectsEnabled: false),
                    reduceMotion: false, layoutDirection: rtl ? .rightToLeft : .leftToRight)
                func definition() -> FluentNavigationView<Int> {
                    FluentNavigationView((0..<3).map { FluentNavigationItem(id: $0, title: "Page \($0)") },
                        selection: FluentBinding(get: { selected }, set: { selected = $0 }),
                        isPaneOpen: FluentBinding(get: { false }, set: { _ in }), paneDisplayMode: .leftMinimal,
                        isPaneToggleButtonVisible: false, contentTransition: mode) { FluentNativeView(pages[selected ?? 0]) }
                }
                let root = definition()._makeView(in: context)
                let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 500, height: 300),
                    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = root; window.makeKeyAndOrderFront(nil)
                root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
                let presenter = all(root).first { $0.identifier?.rawValue == "FluentKit.NavigationView.Content" }!
                let variant = mode.rawValue + (rtl ? "-rtl" : "-ltr")
                func record(_ state: String) throws {
                    root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
                    let size = presenter.bounds.size
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                    cg.scaleBy(x: 2, y: 2)
                    if presenter.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
                    (presenter.layer!.presentation() ?? presenter.layer!).render(in: cg)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(variant + "-" + state + ".png"))
                    let tree = layers(presenter.layer!)
                    var red = 0, opaque = 0
                    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                        let pixel = bitmap.bitmapData! + y * bitmap.bytesPerRow + x * 4
                        if pixel[3] > 120 { opaque += 1 }
                        if pixel[0] > 120 && pixel[1] < 80 && pixel[2] < 80 && pixel[3] > 120 { red += 1 }
                    }}
                    records.append(["variant": variant, "state": state, "redPixels": red, "opaquePixels": opaque,
                        "entries": presenter.subviews.count,
                        "snapshots": tree.filter { $0.name == "FluentKit.NavigationView.InterruptedSnapshot" }.count,
                        "animations": tree.reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) },
                        "pages": all(presenter).compactMap { ($0 as? NavigationAuditPage)?.name },
                        "currentIdentityRetained": all(presenter).contains { $0 === pages[selected ?? 0] }])
                }
                try record("initial")
                selected = 1; _ = definition()._updateView(root, in: context)
                CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
                try record("first")
                selected = 2; _ = definition()._updateView(root, in: context)
                CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
                try record("interrupted")
                window.setContentSize(NSSize(width: 640, height: 340))
                root.layoutSubtreeIfNeeded(); CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                try record("resized")
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.7)); try record("settled")
                selected = 0
                _ = definition()._updateView(root, in: FluentRenderContext(theme: context.theme, reduceMotion: true, layoutDirection: context.layoutDirection))
                CATransaction.flush(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)); try record("reduced")
                window.close()
            }
        }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
