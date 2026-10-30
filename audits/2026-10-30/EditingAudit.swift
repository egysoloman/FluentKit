import AppKit
import FluentKit

@main struct EditingAudit {
    @MainActor static func drain() async {
        for _ in 0..<5 { await withCheckedContinuation { (c: CheckedContinuation<Void,Never>) in DispatchQueue.main.async { c.resume() } } }
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
        let data = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        print(String(data:data,encoding:.utf8)!)
    }
}
