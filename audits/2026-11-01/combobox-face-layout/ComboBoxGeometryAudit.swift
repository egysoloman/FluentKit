import AppKit
@testable import FluentKit

@main struct ComboBoxGeometryAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let selection = FluentState<String?>(wrappedValue: "Preset")
        let expanded = FluentState(wrappedValue: true)
        let context = FluentRenderContext(theme: .custom(colorScheme: .light), reduceMotion: true)
        var rows: [[String: Any]] = []
        for mode in [FluentComboBoxMode.selection, .editable] {
            let combo = FluentComboBox(options: ["Preset", "中文", "English"], selection: selection.projectedValue, mode: mode)
            let variants: [(String, FluentAnyView)] = [
                ("direct", FluentAnyView(combo)),
                ("frame", FluentAnyView(combo.frame(width: 220))),
                ("stack", FluentAnyView(FluentVStack(alignment: .leading) { combo.frame(width: 220); FluentText("Following content") })),
                ("expander", FluentAnyView(FluentExpander("Interactive sample", isExpanded: expanded.projectedValue) {
                    FluentVStack(alignment: .leading) { combo.frame(width: 220); FluentText("Following content") }
                })),
                ("gallery-sample", FluentAnyView(MaterialGallerySample(theme: context.theme)))
            ]
            for (name, definition) in variants {
                if mode == .editable && name == "gallery-sample" { continue }
                let key = "\(mode)-\(name)"
                let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 430, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .aqua)
                let root = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 500))
                window.contentView = root
                let mounted = definition._mount(in: context)
                root.addSubview(mounted)
                mounted.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([mounted.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), mounted.topAnchor.constraint(equalTo: root.topAnchor, constant: 20), mounted.widthAnchor.constraint(equalToConstant: 390)])
                window.orderFront(nil)
                root.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                root.layoutSubtreeIfNeeded()
                let host = all(mounted).first { $0.identifier?.rawValue == "FluentKit.ComboBox.Host" }!
                let bridge = all(host).compactMap { $0 as? NSComboBox }.first!
                rows.append(["case": key, "height": host.bounds.height, "intrinsic": NSStringFromSize(host.intrinsicContentSize), "fitting": NSStringFromSize(host.fittingSize), "font": bridge.font!.fontName, "fontSize": bridge.font!.pointSize,
                    "tree": all(mounted).prefix(14).map { ["type": String(describing: type(of: $0)), "frame": NSStringFromRect($0.frame), "intrinsic": NSStringFromSize($0.intrinsicContentSize), "fitting": NSStringFromSize($0.fittingSize), "hugging": $0.contentHuggingPriority(for: .vertical).rawValue, "compression": $0.contentCompressionResistancePriority(for: .vertical).rawValue] }])
                root.displayIfNeeded(); CATransaction.flush()
                if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                    root.cacheDisplay(in: root.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(key + ".png"))
                }
                window.close()
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("geometry.json"))
        for row in rows { print(row["case"]!, row["height"]!, row["intrinsic"]!, row["fitting"]!) }
    }
}
