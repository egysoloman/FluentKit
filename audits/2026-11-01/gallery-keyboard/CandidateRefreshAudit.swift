import AppKit
import FluentKit
@main struct CandidateRefreshAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        var rows: [[String: Any]] = []
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        for stable in [false, true] {
            let query = FluentState(wrappedValue: "")
            func page(_ note: String) -> some FluentView {
                FluentVStack {
                    FluentText(note)
                    FluentAutoSuggestBox(query.projectedValue, suggestions: { _ in
                        [FluentAutoSuggestBoxSuggestion(id: stable ? AnyHashable("apple") : AnyHashable(UUID()), title: "Apple"),
                         FluentAutoSuggestBoxSuggestion(id: stable ? AnyHashable("apricot") : AnyHashable(UUID()), title: "Apricot")]
                    })
                    FluentButtonView("After")
                }
            }
            let host = FluentViewHost(page("Initial"), context: .init(reduceMotion: true))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = true
            window.contentView = host; window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
            let field = all(host).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as! NSTextField
            window.makeFirstResponder(field); field.selectText(nil)
            let editor = field.currentEditor() as! NSTextView
            editor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
            let preview = query.wrappedValue
            host.update(page("Refreshed")); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
            // Deliberately use AppKit's own command path, with no Fluent focus scope.
            editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
            rows.append(["stableIDs": stable, "preview": preview, "afterTab": query.wrappedValue,
                "hasScope": false, "field": field.stringValue])
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
    }
}
