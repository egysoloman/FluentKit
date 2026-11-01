import AppKit
import FluentKit

@main struct ComboBoxSubmissionAudit {
    private final class Model {
        @FluentState var options = ["Alpha", "Bravo", "Charlie"]
        @FluentState var selection: String? = "Alpha"
        @FluentState var text = "Alpha"
        @FluentState var replaced = false
        @FluentState var replacementSelection: String? = "Bravo"
        @FluentState var replacementText = "Custom"
        var submissions: [String] = []
        var reopen: (() -> Void)?
        let action: String
        init(_ action: String) { self.action = action }
        var currentSelection: String? { replaced ? replacementSelection : selection }
        var currentText: String { replaced ? replacementText : text }
        func submit(_ event: inout FluentComboBoxTextSubmittedEvent) {
            submissions.append(event.text)
            switch action {
            case "reject": event.handled = true
            case "insert": options.append(event.text)
            case "rebind": replaced = true
            case "reset": text = "External reset"
            case "reopen": reopen?()
            default: break
            }
        }
    }

    private struct Form: FluentView {
        let model: Model
        let always: Bool
        var body: some FluentView {
            FluentComboBox(options: model.options,
                selection: model.replaced ? model.$replacementSelection : model.$selection, mode: .editable,
                text: (model.replaced ? model.$replacementText : model.$text).textInput(.init(commitPolicy: .committedText)),
                title: { $0 }).selectionChangedTrigger(always ? .always : .committed)
                .onTextSubmitted { event in model.submit(&event) }
        }
    }

    @MainActor private static func drain() async {
        for _ in 0..<5 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
        }
    }

    @MainActor static func capture(_ window: NSWindow, to path: String) throws -> Int {
        window.displayIfNeeded(); CATransaction.flush()
        let deadline = Date().addingTimeInterval(2)
        var attempts = 0
        while Date() < deadline {
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]]
            if info?.first?[kCGWindowIsOnscreen as String] as? Bool == true {
                attempts += 1
                let shot = Process(); shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
                try shot.run(); shot.waitUntilExit()
                if shot.terminationStatus == 0 { return attempts }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        throw NSError(domain: "ComboBoxSubmissionAudit.Capture", code: 1)
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var samples: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for always in [false, true] { for opened in [false, true] {
            for action in ["accept", "reject", "insert", "rebind", "reset", "reopen"] {
                let model = Model(action)
                let host = FluentViewHost(Form(model: model, always: always),
                    context: .init(theme: .custom(colorScheme: dark ? .dark : .light), reduceMotion: true,
                        layoutDirection: rtl ? .rightToLeft : .leftToRight))
                let window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 500, height: 300),
                    styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; defer { window.close() }
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
                host.frame = NSRect(x: 50, y: 170, width: 280, height: 32)
                window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
                guard let bridge = all(host).compactMap({ $0 as? NSComboBox }).first,
                      let field = all(host).first(where: { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" }) as? NSTextField else {
                    throw NSError(domain: "ComboBoxSubmissionAudit", code: 1)
                }
                field.selectText(nil)
                guard let editor = field.currentEditor() as? NSTextView else { throw NSError(domain: "ComboBoxSubmissionAudit", code: 2) }
                let delegate = editor.delegate
                if opened { bridge.performClick(nil) }
                let oldPanel = window.childWindows?.first { $0.isVisible }
                model.reopen = { [weak bridge] in
                    if opened { bridge?.performClick(nil) }
                    bridge?.performClick(nil)
                }
                var selectedWrites: [String] = []
                let observer = model.$selection.observe { selectedWrites.append($0 ?? "<nil>") }
                defer { if let observer { model.$selection.removeObserver(observer) } }
                editor.insertText("Custom", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
                await drain()
                var row: [String: Any] = ["dark": dark, "rtl": rtl, "always": always, "open": opened, "action": action,
                    "beforeSubmissionCount": model.submissions.count, "beforeSelection": model.currentSelection ?? "<nil>"]
                func submit() {
                    NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                        isARepeat: false, keyCode: 36)!)
                }
                submit(); await drain()
                if ["accept", "reject", "insert"].contains(action) { submit(); await drain() }
                let panel = window.childWindows?.first { $0.isVisible }
                row["submissions"] = model.submissions
                row["selected"] = model.currentSelection ?? "<nil>"
                row["text"] = field.stringValue
                row["modelText"] = model.currentText
                row["selectedWrites"] = selectedWrites
                row["popupOpen"] = panel != nil
                row["newPopupPreserved"] = action != "reopen" || (panel != nil && panel !== oldPanel)
                row["editorPreserved"] = field.currentEditor() === editor && editor.delegate === delegate
                    && window.firstResponder === editor
                row["fieldPreserved"] = all(host).contains { $0 === field }
                if action == "insert", opened, !always,
                   let folder = ProcessInfo.processInfo.environment["FLUENTKIT_SUBMISSION_CAPTURE_DIR"] {
                    bridge.performClick(nil)
                    let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-insert.png"
                    row["captureAttempts"] = try capture(window, to: URL(fileURLWithPath: folder).appendingPathComponent(name).path)
                }
                samples.append(row)
            }
        } } } }
        print(String(decoding: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
