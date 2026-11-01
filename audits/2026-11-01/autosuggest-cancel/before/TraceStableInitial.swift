import AppKit
import FluentKit
private final class CycleModel {
    @FluentState var names = ["A", "B"]
    @FluentState var shown = false
    @FluentState var query = ""
    var observation: NSKeyValueObservation?
    var monitors: [Any] = []
    var observers: [NSObjectProtocol] = []
}
private struct CyclePage: FluentView {
    let model: CycleModel
    var body: some FluentView {
        FluentVStack(spacing: 20) {
            FluentButtonView("Open dialog") { model.shown = true }
            FluentHStack { FluentForEach(model.names, id: \.self) { FluentButtonView($0) } }.fluentFocusScope()
            FluentButtonView("Reorder") { model.names = ["B", "A", "C"] }
            FluentVStack {
                FluentAutoSuggestBox(model.$query, placeholder: "Search fruit", querySystemImageName: "magnifyingglass", suggestions: { _ in
                    [FluentAutoSuggestBoxSuggestion(id: "apple", title: "Apple"), FluentAutoSuggestBoxSuggestion(id: "apricot", title: "Apricot")]
                })
                FluentButtonView("After search")
            }.fluentFocusScope()
        }.padding(32).contentDialog("Modal cycle", isPresented: model.$shown,
            primaryButtonText: "OK", closeButtonText: "Cancel") {
                FluentHStack { FluentButtonView("Inside 1"); FluentButtonView("Inside 2") }
            }
    }
}
@main struct CycleApp: FluentApp {
    private let model = CycleModel()
    var body: some FluentScene {
        FluentWindowScene(title: "Keyboard cycle audit", size: NSSize(width: 600, height: 400),
            material: nil, restoration: .disabled) { CyclePage(model: model) }
    }
    func applicationDidLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let window = NSApp.windows.first { $0.title == "Keyboard cycle audit" }!
            // Reproduce automatic AppKit navigation even with an older library.
            window.autorecalculatesKeyViewLoop = true
            FluentInputDeviceTracker.shared.record(.touch, in: window)
            model.names = ["A", "C", "B"]
            func snapshot(_ phase: String) {
                func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
                guard let root = window.contentView,
                      let host = all(root).first(where: { String(describing: type(of: $0)).contains("FluentAutoSuggestBoxHost") }),
                      let path = Bundle.main.object(forInfoDictionaryKey: "AuditLogPath") as? String else { return }
                var row = ["phase": phase, "query": model.query, "childWindows": String(window.childWindows?.count ?? 0),
                    "key": String(window.isKeyWindow), "active": String(NSApp.isActive), "time": String(ProcessInfo.processInfo.systemUptime),
                    "hostBounds": NSStringFromRect(host.bounds), "hostVisible": NSStringFromRect(host.visibleRect),
                    "responder": String(describing: window.firstResponder)]
                if let field = all(host).first(where: { $0.identifier?.rawValue == "FluentKit.AutoSuggestBox.Field" }) as? NSTextField {
                    row["field"] = field.stringValue
                    row["fieldVisible"] = NSStringFromRect(field.visibleRect)
                    if let editor = field.currentEditor() as? NSTextView {
                        row["editor"] = editor.string; row["marked"] = String(editor.hasMarkedText())
                    }
                }
                for value in Mirror(reflecting: host).children {
                    if let label = value.label, ["selectedIndex", "userTypedText", "suppressPresentation"].contains(label) {
                        row[label] = String(describing: value.value)
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: row), let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile(); handle.write(data); handle.write(Data([10])); try? handle.close()
                }
            }
            for name in [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification, NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification, NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                model.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                    if let view = note.object as? NSView, view.window !== window { return }
                    snapshot(name.rawValue)
                })
            }
            if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
                snapshot("before key \(event.keyCode)")
                DispatchQueue.main.async { snapshot("after key \(event.keyCode)") }
                return event
            }) { model.monitors.append(monitor) }
            model.observation = window.observe(\.firstResponder, options: [.new]) { window, _ in
                snapshot("firstResponder changed")
                let name = (window.firstResponder as? NSButton)?.title ?? String(describing: window.firstResponder)
                guard let path = Bundle.main.object(forInfoDictionaryKey: "AuditLogPath") as? String,
                      let data = try? JSONSerialization.data(withJSONObject: ["focused": name, "device": String(describing: FluentInputDeviceTracker.shared.lastDeviceType(in: window))]) else { return }
                if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
                if let handle = FileHandle(forWritingAtPath: path) {
                    handle.seekToEndOfFile(); handle.write(data); handle.write(Data([10])); try? handle.close()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
                window.contentView!.layoutSubtreeIfNeeded()
                let b = all(window.contentView!).compactMap { $0 as? FluentButton }.first { $0.title == "B" }!
                window.makeFirstResponder(b); window.recalculateKeyViewLoop()
            }
        }
    }
}
