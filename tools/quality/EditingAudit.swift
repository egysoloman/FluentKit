import AppKit
import FluentKit

@main struct EditingAudit {
    @MainActor static func drain() async {
        for _ in 0..<5 { await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in DispatchQueue.main.async { c.resume() } } }
    }

    @MainActor static func auditComboBox(dark: Bool, rtl: Bool, committed: Bool) async throws -> [String: Any] {
        let text = FluentState(wrappedValue: "Option 1")
        let selection = FluentState<Int?>(wrappedValue: 1)
        let host = FluentViewHost(FluentComboBox(options: [0, 1, 2], selection: selection.projectedValue,
            mode: .editable, text: text.projectedValue.textInput(.init(commitPolicy: committed ? .committedText : .continuous)),
            title: { "Option \($0)" }), context: .init(theme: .custom(colorScheme: dark ? .dark : .light), reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(x: 40, y: 160, width: 280, height: 32)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(host)
        views.forEach { $0.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight }
        window.orderFrontRegardless(); host.layoutSubtreeIfNeeded()
        guard let field = views.first(where: { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" }) as? NSTextField,
              let bridge = views.compactMap({ $0 as? NSComboBox }).first else {
            throw NSError(domain: "EditingAudit.ComboBox", code: 1)
        }
        field.selectText(nil)
        guard let editor = field.currentEditor() as? NSTextView else {
            throw NSError(domain: "EditingAudit.ComboBox", code: 2)
        }
        let delegate = editor.delegate
        var result: [String: Any] = ["dark": dark, "rtl": rtl, "committed": committed]
        editor.insertText("unsent local edit", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        text.wrappedValue = "external reset"
        await drain()
        result["focusedModel"] = text.wrappedValue
        result["focusedField"] = field.stringValue
        result["editorPreserved"] = field.currentEditor() === editor && editor.delegate === delegate
        editor.insertText("another unsent edit", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        text.observableValue.send()
        await drain()
        result["sameValueReset"] = editor.string == "external reset" && text.wrappedValue == "external reset"
        window.makeFirstResponder(nil); await drain()
        result["blurredModel"] = text.wrappedValue
        result["blurredField"] = field.stringValue

        field.selectText(nil); bridge.performClick(nil)
        let panel = window.childWindows?.first
        text.wrappedValue = "Option 2"
        result["popupPreserved"] = panel != nil && panel?.isVisible == true && window.childWindows?.first === panel
        result["matchedSelection"] = selection.wrappedValue == 2 && bridge.indexOfSelectedItem == 2
        guard let compositionEditor = field.currentEditor() as? NSTextView else {
            throw NSError(domain: "EditingAudit.ComboBox", code: 3)
        }
        compositionEditor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: 0, length: compositionEditor.string.utf16.count))
        compositionEditor.didChangeText(); await drain()
        result["compositionPolicy"] = text.wrappedValue == (committed ? "Option 2" : "pin")
        text.wrappedValue = "earlier reset"; text.wrappedValue = "Option 0"
        compositionEditor.setMarkedText("ping", selectedRange: NSRange(location: 4, length: 0),
            replacementRange: compositionEditor.markedRange())
        compositionEditor.didChangeText(); await drain()
        result["markedTextPreserved"] = compositionEditor.hasMarkedText() && compositionEditor.string == "ping"
        result["pendingResetPreserved"] = text.wrappedValue == "Option 0"
        compositionEditor.unmarkText(); compositionEditor.didChangeText(); await drain()
        result["latestResetApplied"] = compositionEditor.string == "Option 0" && selection.wrappedValue == 0
        window.makeFirstResponder(nil); await drain()
        result["resetSurvivesBlur"] = text.wrappedValue == "Option 0" && field.stringValue == "Option 0"
        return result
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let state = FluentState(wrappedValue: "initial")
        let bound = FluentBoundTextField(state.projectedValue, placeholder: "Audit")
        let root = NSView(frame:NSRect(x:0,y:0,width:400,height:150))
        bound.frame = NSRect(x:20,y:50,width:300,height:32)
        root.addSubview(bound)
        let window = NSWindow(contentRect:root.bounds,styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.orderFrontRegardless()
        bound.field.selectText(nil)
        await drain()
        var results: [String:Any] = ["editorPresent": bound.field.currentEditor() != nil]
        if let editor = bound.field.currentEditor() as? NSTextView {
            editor.string = "typed"
            editor.didChangeText()
            await drain()
            state.wrappedValue = "external reset"
            await drain()
            results["focusedModel"] = state.wrappedValue
            results["focusedField"] = bound.field.stringValue
            window.makeFirstResponder(nil)
            await drain()
            results["blurredModel"] = state.wrappedValue
            results["blurredField"] = bound.field.stringValue
            bound.field.selectText(nil)
            await drain()
            if let compositionEditor = bound.field.currentEditor() as? NSTextView {
                compositionEditor.setMarkedText("pin",selectedRange:NSRange(location:3,length:0),replacementRange:NSRange(location:0,length:(compositionEditor.string as NSString).length))
                compositionEditor.didChangeText()
                await drain()
                results["hasMarkedText"] = compositionEditor.hasMarkedText()
                results["compositionModel"] = state.wrappedValue
                results["compositionField"] = bound.field.stringValue
            }
        }
        window.close()
        var comboBoxes: [[String: Any]] = []
        for dark in [false, true] {
            for rtl in [false, true] {
                for committed in [false, true] {
                    comboBoxes.append(try await auditComboBox(dark: dark, rtl: rtl, committed: committed))
                }
            }
        }
        results["comboBoxes"] = comboBoxes
        let data = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    }
}
