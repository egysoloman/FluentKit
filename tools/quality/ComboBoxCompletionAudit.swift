import AppKit
import FluentKit

@main struct ComboBoxCompletionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func wait(_ ready: () -> Bool) {
            let deadline = Date().addingTimeInterval(0.5)
            while !ready(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        }
        let names = ["Alpha", "Bravo", "Charlie", "Chase"]
        var samples: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for bound in [false, true] {
            for always in [false, true] { for open in [false, true] { for committedText in [false, true] {
                let selected = FluentState<Int?>(wrappedValue: 0)
                let text = FluentState(wrappedValue: "Alpha")
                let host = FluentViewHost(FluentComboBox(options: Array(names.indices), selection: selected.projectedValue,
                    mode: .editable, text: bound ? text.projectedValue.textInput(.init(commitPolicy: committedText ? .committedText : .continuous)) : nil,
                    title: { names[$0] }).selectionChangedTrigger(always ? .always : .committed),
                    context: .init(theme: .custom(colorScheme: dark ? .dark : .light), reduceMotion: true,
                        layoutDirection: rtl ? .rightToLeft : .leftToRight))
                let window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 500, height: 300),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; defer { window.close() }
                window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
                host.frame = NSRect(x: 50, y: 170, width: 280, height: 32)
                window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
                guard let bridge = all(host).compactMap({ $0 as? NSComboBox }).first,
                      let field = all(host).first(where: { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" }) as? NSTextField else {
                    throw NSError(domain: "ComboBoxCompletionAudit", code: 1)
                }
                field.selectText(nil)
                guard let editor = field.currentEditor() as? NSTextView else { throw NSError(domain: "ComboBoxCompletionAudit", code: 2) }
                if open { bridge.performClick(nil) }
                let panel = window.childWindows?.first(where: { $0.isVisible })
                let delegate = editor.delegate
                editor.insertText("Ch", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                wait { field.stringValue == "Charlie" && (!bound || text.wrappedValue == "Charlie") && (!always || selected.wrappedValue == 2) }
                CATransaction.flush()
                let rowLayers: [CALayer] = panel?.contentView.map { all($0).flatMap { $0.layer?.sublayers ?? [] } } ?? []
                var implicitRowAnimations: [String] = []
                for layer in rowLayers where layer.name?.hasPrefix("FluentKit.ComboBoxItem.") == true {
                    for key in layer.animationKeys() ?? [] where key == "opacity" || key == "backgroundColor" {
                        implicitRowAnimations.append(key)
                    }
                }
                var row: [String: Any] = ["dark": dark, "rtl": rtl, "bound": bound, "always": always, "open": open,
                    "committedText": committedText, "completedText": editor.string, "selection": selected.wrappedValue ?? -1,
                    "implicitRowAnimations": implicitRowAnimations,
                    "suffix": [editor.selectedRange().location, editor.selectedRange().length],
                    "modelMatches": !bound || text.wrappedValue == "Charlie",
                    "editorPreserved": field.currentEditor() === editor && editor.delegate === delegate,
                    "panelPreserved": open ? panel?.isVisible == true : window.childWindows?.contains(where: { $0.isVisible }) != true]
                editor.undoManager?.undo()
                wait { editor.string == "Alpha" && (!bound || text.wrappedValue == "Alpha") && (!always || selected.wrappedValue == 0) }
                row["undoText"] = editor.string
                editor.undoManager?.redo()
                wait { editor.string == "Charlie" && (!bound || text.wrappedValue == "Charlie") && (!always || selected.wrappedValue == 2) }
                row["redoText"] = editor.string
                if editor.string == "Charlie" { editor.setSelectedRange(NSRange(location: 2, length: 5)) }
                editor.deleteBackward(nil)
                wait { field.stringValue == "Ch" && (!bound || text.wrappedValue == "Ch") }
                row["deletedText"] = editor.string; row["selectionAfterDeletion"] = selected.wrappedValue ?? -1
                NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                    isARepeat: false, keyCode: 36)!)
                row["freeTextCommitted"] = selected.wrappedValue == nil && field.stringValue == "Ch"
                editor.setMarkedText("Ch", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                editor.didChangeText()
                if bound { text.wrappedValue = "Br" } else { selected.wrappedValue = 1 }
                row["markedTextPreserved"] = editor.hasMarkedText() && editor.string == "Ch"
                editor.unmarkText(); editor.didChangeText()
                wait { editor.string == (bound ? "Br" : "Bravo") }
                row["externalResetWins"] = editor.string == (bound ? "Br" : "Bravo")
                    && (bound ? text.wrappedValue == "Br" && selected.wrappedValue == nil : selected.wrappedValue == 1)
                samples.append(row)
            } } }
        } } }
        print(String(decoding: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
