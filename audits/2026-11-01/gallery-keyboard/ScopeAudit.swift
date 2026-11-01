import AppKit
import FluentKit
@main struct ScopeAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        var records: [[String: Any]] = []
        for automatic in [false, true] {
            func page(_ values: [String]) -> some FluentView { FluentVStack {
                FluentButtonView("Before")
                FluentHStack { FluentForEach(values, id: \.self) { FluentButtonView($0) } }.fluentFocusScope()
                FluentButtonView("After")
            } }
            let root = FluentViewHost(page(["A", "B"]))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = automatic
            window.contentView = root; window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)); root.layoutSubtreeIfNeeded()
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            let buttons = all(root).compactMap { $0 as? FluentButton }
            let b = buttons.first { $0.title == "B" }!
            func record(_ stage: String) {
                let nextName = (b.nextValidKeyView as? NSButton)?.title ?? String(describing: b.nextValidKeyView)
                window.makeFirstResponder(b); window.selectNextKeyView(nil)
                records.append(["automatic": automatic, "stage": stage,
                    "selectedNext": (window.firstResponder as? NSButton)?.title ?? String(describing: window.firstResponder),
                    "next": nextName])
            }
            record("initial")
            let extra = NSButton(title: "Added outside", target: nil, action: nil)
            extra.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
            root.addSubview(extra); record("outside-added")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)); record("outside-settled")
            window.setContentSize(NSSize(width: 500, height: 300)); root.layoutSubtreeIfNeeded(); record("resized")
            root.update(page(["A", "C", "B"])); root.layoutSubtreeIfNeeded(); record("inside-added")
            root.update(page(["C", "B"])); root.layoutSubtreeIfNeeded(); record("inside-removed")
            window.recalculateKeyViewLoop(); record("explicit-recalculation")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
