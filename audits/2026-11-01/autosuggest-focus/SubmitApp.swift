import AppKit
import FluentKit

private final class SubmitModel: NSObject {
    var query = ""
    @FluentState var result = "No submission"
    func log(_ event: [String: String]) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "AuditLogPath") as? String,
              let data = try? JSONSerialization.data(withJSONObject: event, options: .sortedKeys) else { return }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile(); handle.write(data); handle.write(Data([10])); try? handle.close()
        }
    }
    @objc func resetModel(_ sender: Any?) {
        query = "Pear"
        // No observable update: synchronize this closure binding when Enter submits.
        log(["phase": "external reset", "model": query])
    }
}

private struct SubmitPage: FluentView {
    let model: SubmitModel
    var body: some FluentView {
        FluentVStack(spacing: 18) {
            FluentText("Type Ap, press Down, then Cmd+Shift+R, then Enter.")
            FluentAutoSuggestBox(FluentBinding(get: { model.query }, set: { model.query = $0 }),
                placeholder: "Search fruit", suggestions: { _ in
                    [.init(id: "apple", title: "Apple"), .init(id: "apricot", title: "Apricot")]
                }, onSubmit: { text, chosen in
                    model.log(["phase": "submit", "text": text, "chosen": chosen?.title ?? "none", "model": model.query])
                    model.result = "Submitted: \(text); chosen: \(chosen?.title ?? "none")"
                })
            FluentText(model.result)
            FluentButtonView("After search")
        }.padding(24)
    }
}

@main struct SubmitApp: FluentApp {
    private let model = SubmitModel()
    var body: some FluentScene {
        FluentWindowScene(title: "AutoSuggest callback audit", size: NSSize(width: 580, height: 260),
            material: nil, restoration: .disabled) { SubmitPage(model: model) }
    }
    func applicationDidLaunch() {
        let item = NSMenuItem(title: "Audit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Audit"); item.submenu = menu
        let reset = NSMenuItem(title: "Reset model to Pear", action: #selector(SubmitModel.resetModel(_:)), keyEquivalent: "r")
        reset.target = model; reset.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(reset)
        NSApp.mainMenu?.addItem(item)
    }
}
