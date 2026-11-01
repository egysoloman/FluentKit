import AppKit
import FluentKit
private final class WindowModel {
    @FluentState var changed = false
    @FluentState var checked = false
    @FluentState var presented = false
}
private struct WindowPage: FluentView {
    let model: WindowModel
    var body: some FluentView {
        FluentVStack {
            FluentButtonView("Stable")
            if model.changed { FluentCheckBoxView("Inserted", isChecked: model.$checked) }
            else { FluentButtonView("Removed") }
        }.padding(24)
    }
}
@main struct WindowAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2)) }
        var results: [[String: Any]] = []
        func inspect(_ window: NSWindow, model: WindowModel, kind: String) {
            settle(); window.contentView!.layoutSubtreeIfNeeded()
            let stable = all(window.contentView!).compactMap { $0 as? FluentButton }.first { $0.title == "Stable" }!
            _ = stable.nextValidKeyView
            model.changed = true; settle(); window.contentView!.layoutSubtreeIfNeeded()
            let check = all(window.contentView!).compactMap { $0 as? FluentCheckBox }.first!
            window.makeFirstResponder(stable); window.selectNextKeyView(nil)
            results.append(["kind": kind, "automatic": window.autorecalculatesKeyViewLoop,
                "reachedInserted": window.firstResponder === check, "insertedHasNext": check.nextValidKeyView != nil])
        }
        let model = WindowModel()
        let root = FluentViewHost(FluentText("Parent").sheet(isPresented: model.$presented,
            title: "Keyboard sheet", size: NSSize(width: 400, height: 220)) { WindowPage(model: model) },
            context: .init(reduceMotion: true))
        let parent = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false; parent.contentView = root; parent.makeKeyAndOrderFront(nil)
        settle(); model.presented = true; settle()
        let sheet = NSApp.windows.first { $0.title == "Keyboard sheet" }!
        inspect(sheet, model: model, kind: "sheet")
        model.presented = false; settle(); parent.close()
        let tabModel = WindowModel()
        let tabs = FluentWindowTabCoordinator(configuration: .init(material: nil, showsAddTabButton: false,
            context: .init(reduceMotion: true)))
        let group = tabs.open(FluentWindowTab(id: "audit", title: "Keyboard tab") { WindowPage(model: tabModel) })
        inspect(tabs.window(for: group)!, model: tabModel, kind: "tab-window")
        tabs.close(groupID: group)
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
