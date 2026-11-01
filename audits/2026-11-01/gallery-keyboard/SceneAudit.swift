import AppKit
import FluentKit

private final class Model { @FluentState var showChoice = false; @FluentState var checked = false }
private struct Page: FluentView {
    let model: Model
    var body: some FluentView {
        FluentVStack {
            FluentButtonView("Stable")
            if model.showChoice { FluentCheckBoxView("Inserted", isChecked: model.$checked) }
            else { FluentButtonView("Removed") }
        }.padding(24)
    }
}
@main struct SceneAudit: FluentApp {
    private let model = Model()
    var body: some FluentScene {
        FluentWindowScene(title: "Scene keyboard audit", size: NSSize(width: 400, height: 220),
            minimumSize: NSSize(width: 300, height: 180), material: nil, restoration: .disabled) { Page(model: model) }
    }
    func applicationDidLaunch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let window = NSApp.windows.first { $0.title == "Scene keyboard audit" }!
            func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            let stable = all(window.contentView!).compactMap { $0 as? FluentButton }.first { $0.title == "Stable" }!
            _ = stable.nextValidKeyView // Build the initial window loop before replacing its page.
            model.showChoice = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.contentView!.layoutSubtreeIfNeeded()
                let check = all(window.contentView!).compactMap { $0 as? FluentCheckBox }.first!
                window.makeFirstResponder(stable); window.selectNextKeyView(nil)
                let result: [String: Any] = ["automatic": window.autorecalculatesKeyViewLoop,
                    "insertedCanFocus": check.canBecomeKeyView,
                    "reachedInserted": window.firstResponder === check,
                    "insertedHasNext": check.nextValidKeyView != nil]
                print(String(decoding: try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self))
                NSApp.terminate(nil)
            }
        }
    }
}
