import AppKit
import FluentKit

@main struct Probe {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let description = "Light, Dark and RTL mounting checked; interactive states need the acceptance matrix"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        let context = FluentRenderContext(reduceMotion: true)
        let plain = FluentSettingsCard("Plain", description: description, systemImageName: "play.circle")._makeView(in: context)
        let expanded = FluentSettingsExpander("Expanded", description: description, systemImageName: "play.circle",
            isExpanded: FluentBinding(get: { true }, set: { _ in })) { FluentText("Body") }._makeView(in: context)
        for view in [plain, expanded] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20).isActive = true
        }
        plain.topAnchor.constraint(equalTo: root.topAnchor, constant: 20).isActive = true
        expanded.topAnchor.constraint(equalTo: plain.bottomAnchor, constant: 16).isActive = true
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var rows: [[String: Any]] = []
        let widthConstraints = [plain, expanded].map { $0.widthAnchor.constraint(equalToConstant: 780) }
        NSLayoutConstraint.activate(widthConstraints)
        for width in [820, 500, 340, 820] {
            widthConstraints.forEach { $0.constant = CGFloat(width - 40) }
            window.setContentSize(NSSize(width: width, height: 400))
            for _ in 0..<4 {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            }
            for card in all(window.contentView!).filter({ ["FluentKit.Settings.Card", "FluentKit.Settings.Expander.Header"].contains($0.identifier?.rawValue ?? "") }) {
                let labels = all(card).compactMap { $0 as? NSTextField }
                guard let label = labels.first(where: { $0.stringValue == description }) else { continue }
                let cell = label.cell as! NSTextFieldCell
                rows.append(["windowWidth": width, "actualRootBounds": NSStringFromRect(root.bounds), "card": labels.first?.stringValue ?? "",
                    "cardFrame": NSStringFromRect(card.frame), "labelFrame": NSStringFromRect(label.frame),
                    "labelIntrinsic": NSStringFromSize(label.intrinsicContentSize),
                    "labelCellSize": NSStringFromSize(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: 1000))),
                    "singleLine": cell.usesSingleLineMode, "wraps": cell.wraps, "scrollable": cell.isScrollable,
                    "lineLimit": label.maximumNumberOfLines, "preferredMaxLayoutWidth": label.preferredMaxLayoutWidth])
            }
        }
        print(String(data: try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        window.close()
    }
}
