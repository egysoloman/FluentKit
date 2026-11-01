import AppKit
import FluentKit

@main struct CallbackAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
        var results: [[String: Any]] = []
        for rtl in [false, true] {
            for preview in [false, true] {
                for scenario in ["focus", "reset-focused", "reset-blurred", "closure-enter", "closure-query", "provider-empty", "provider-fresh"] {
                    let state = FluentState(wrappedValue: "")
                    var model = "", submitted = "", chosen = "none", queries: [String] = [], events: [String] = []
                    var transientRows: [String] = []
                    var window: NSWindow!
                    let binding = scenario.hasPrefix("closure") ? FluentBinding(get: { model }, set: { model = $0 }) : state.projectedValue
                    let view = FluentAutoSuggestBox(binding, querySystemImageName: "magnifyingglass", suggestions: { query in
                        queries.append(query)
                        if scenario.hasPrefix("provider") && query == "Ap" {
                            state.wrappedValue = "Pear"
                            DispatchQueue.main.async {
                                transientRows = window.childWindows?.filter(\.isVisible).flatMap { child in
                                    child.contentView.map(all)?.filter { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Suggestion" }
                                        .compactMap { $0.accessibilityLabel() } ?? []
                                } ?? []
                            }
                            return [.init(id: 1, title: "Apple")]
                        }
                        if scenario.hasPrefix("provider") && query == "Pear" {
                            return scenario == "provider-fresh" ? [.init(id: 3, title: "Pear result")] : []
                        }
                        return [.init(id: 1, title: "Apple"), .init(id: 2, title: "Apricot")]
                    }, updateTextOnSelect: preview,
                        onTextChangedEvent: { events.append("\($0.reason):\($0.text)") },
                        onSubmit: { submitted = $0; chosen = $1?.title ?? "none" })
                        ._makeView(in: .init(reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                    window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 450, height: 200),
                        styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    let stage = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 200))
                    window.contentView = stage; stage.addSubview(view)
                    view.frame = NSRect(x: 20, y: 110, width: 320, height: view.intrinsicContentSize.height)
                    window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
                    let field = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as! NSTextField
                    field.selectText(nil)
                    let originalEditor = field.currentEditor() as! NSTextView
                    originalEditor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0)); settle()
                    if scenario.hasPrefix("provider") {
                        settle()
                    } else {
                        originalEditor.doCommand(by: #selector(NSResponder.moveDown(_:)))
                        if scenario.hasPrefix("closure") {
                            model = "Pear"
                            if scenario == "closure-enter" {
                                originalEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                            } else {
                                let query = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.QueryButton" } as! NSButton
                                query.performClick(nil)
                            }
                        } else {
                            if scenario == "reset-focused" { state.wrappedValue = "Pear" }
                            _ = window.makeFirstResponder(nil); settle()
                            if scenario == "reset-blurred" { state.wrappedValue = "Pear" }
                            field.selectText(nil); settle()
                            (field.currentEditor() as! NSTextView).doCommand(by: #selector(NSResponder.cancelOperation(_:)))
                        }
                        settle()
                    }
                    let rows = window.childWindows?.filter(\.isVisible).flatMap { child in
                        child.contentView.map(all)?.filter { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Suggestion" }
                            .compactMap { $0.accessibilityLabel() } ?? []
                    } ?? []
                    results.append(["rtl": rtl, "preview": preview, "scenario": scenario,
                        "model": binding.get(), "field": field.stringValue, "submitted": submitted, "chosen": chosen,
                        "transientRows": transientRows, "rows": rows, "queries": queries, "events": events,
                        "editorPreserved": field.currentEditor() === originalEditor])
                    window.close()
                }
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
