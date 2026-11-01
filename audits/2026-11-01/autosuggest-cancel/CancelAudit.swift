import AppKit
import FluentKit

@main struct CancelAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        var results: [[String: Any]] = []
        for rtl in [false, true] {
            for change in ["stable", "replacement", "removal", "empty", "external"] {
                for command in ["tab", "backtab", "escape", "enter"] {
                    let state = FluentState(wrappedValue: "")
                    var values = [FluentAutoSuggestBoxSuggestion(id: 1, title: "Apple"), .init(id: 2, title: "Apricot")]
                    var submitted = "", submittedID = "", events: [String] = []
                    let context = FluentRenderContext(reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
                    func content() -> FluentAutoSuggestBox {
                        FluentAutoSuggestBox(state.projectedValue, querySystemImageName: "magnifyingglass", suggestions: { _ in values },
                            onTextChangedEvent: { events.append("\($0.reason):\($0.text)") },
                            onSubmit: { submitted = $0; submittedID = $1.map { String(describing: $0.id) } ?? "nil" })
                    }
                    let view = content()._makeView(in: context)
                    let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 450, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = true
                    let stage = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 200))
                    let after = NSButton(title: "After", target: nil, action: nil)
                    window.contentView = stage; stage.addSubview(view); stage.addSubview(after)
                    view.frame = NSRect(x: 20, y: 110, width: 320, height: view.intrinsicContentSize.height)
                    after.frame = NSRect(x: 20, y: 40, width: 100, height: 32)
                    window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded()
                    let field = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" } as! NSTextField
                    field.selectText(nil)
                    let editor = field.currentEditor() as! NSTextView
                    editor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                    editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
                    let preview = state.wrappedValue
                    switch change {
                    case "replacement": values = [.init(id: 3, title: "Apple"), .init(id: 4, title: "Apricot")]
                    case "removal": values = [.init(id: 2, title: "Apricot")]
                    case "empty": values = []
                    case "external": state.wrappedValue = "Pear"
                    default: break
                    }
                    _ = content()._updateView(view, in: context)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                    let popupOpen = window.childWindows?.contains { $0.isVisible } ?? false
                    let clear = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.ClearButton" }!
                    let query = all(view).first { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.QueryButton" }!
                    let selector: Selector
                    switch command {
                    case "tab": selector = #selector(NSResponder.insertTab(_:))
                    case "backtab": selector = #selector(NSResponder.insertBacktab(_:))
                    case "escape": selector = #selector(NSResponder.cancelOperation(_:))
                    default: selector = #selector(NSResponder.insertNewline(_:))
                    }
                    editor.doCommand(by: selector)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                    results.append(["rtl": rtl, "change": change, "command": command, "preview": preview,
                        "popupBefore": popupOpen, "text": state.wrappedValue, "field": field.stringValue,
                        "popupAfter": window.childWindows?.contains { $0.isVisible } ?? false,
                        "submitted": submitted, "submittedID": submittedID, "events": events,
                        "clearTabStop": clear.canBecomeKeyView, "queryTabStop": query.canBecomeKeyView,
                        "focusAfter": window.firstResponder === after])
                    window.close()
                }
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted,.sortedKeys]), as: UTF8.self))
    }
}
