import AppKit
import FluentKit
import FluentIMECore
import CRimeBridge

@MainActor private final class PinyinAuditActions: NSObject {
    let controller: SettingsWindowController
    let output: URL
    var rows: [[String: Any]] = []
    var monitors: [Any] = []
    var observers: [NSObjectProtocol] = []
    var referenceWindow: NSWindow?
    let referenceSearch = NSSearchField()
    let referenceText = NSTextField()
    init(controller: SettingsWindowController, output: URL) { self.controller = controller; self.output = output }
    func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    func rect(_ value: NSRect) -> [String: Double] {
        ["x": value.origin.x, "y": value.origin.y, "width": value.width, "height": value.height]
    }
    func capture(_ reason: String, queryCoordinates: Bool = false, eventFlags: UInt? = nil) {
        guard let window = NSApp.keyWindow ?? controller.window, let root = window.contentView else { return }
        let fields = all(root).compactMap { $0 as? NSTextField }
        guard let search = fields.first(where: { $0.currentEditor() != nil })
                ?? fields.first(where: { $0 is FluentSearchTextField })
                ?? fields.first(where: { $0 === referenceSearch }) else { return }
        let editor = search.currentEditor() as? NSTextView
        var row: [String: Any] = ["reason": reason, "uptime": ProcessInfo.processInfo.systemUptime,
            "window": rect(window.frame), "key": window.isKeyWindow, "active": NSApp.isActive,
            "client": window === referenceWindow ? (search === referenceSearch ? "native-search" : "native-text") : "actual-settings",
            "search": search.stringValue, "searchIdentity": String(describing: ObjectIdentifier(search)),
            "searchScreen": rect(window.convertToScreen(search.convert(search.bounds, to: nil))),
            "appearance": window.effectiveAppearance.name.rawValue,
            "inputSource": editor?.inputContext?.selectedKeyboardInputSource ?? "nil",
            "editorIdentity": editor.map { String(describing: ObjectIdentifier($0)) } ?? "nil",
            "marked": editor?.hasMarkedText() ?? false]
        if let eventFlags { row["eventFlags"] = eventFlags }
        if let editor {
            row["markedRange"] = NSStringFromRange(editor.markedRange())
            row["selectedRange"] = NSStringFromRange(editor.selectedRange())
            row["editorText"] = editor.string
            row["editorScreen"] = rect(window.convertToScreen(editor.convert(editor.bounds, to: nil)))
            if queryCoordinates {
                var actual = NSRange(location: NSNotFound, length: 0)
                let requested = editor.hasMarkedText() ? editor.markedRange() : editor.selectedRange()
                row["firstRect"] = rect(editor.firstRect(forCharacterRange: requested, actualRange: &actual))
                row["actualRange"] = NSStringFromRange(actual)
                row["caretRect"] = rect(editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil))
                row["availableSources"] = editor.inputContext?.keyboardInputSources ?? []
            }
        }
        rows.append(row)
        do { try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted,.sortedKeys])
            .write(to: output.appendingPathComponent("states.json"), options: .atomic) }
        catch { print(error) }
    }
    @objc func record(_ sender: Any?) { capture("manual-coordinate-query", queryCoordinates: true) }
    @objc func quit(_ sender: Any?) { capture("quit"); NSApp.stop(nil) }
    @objc func showReference(_ sender: Any?) {
        if referenceWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 400, y: 400, width: 640, height: 240),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Native AppKit — Pinyin reference"
            window.isReleasedWhenClosed = false
            let root = NSView(); window.contentView = root
            let searchLabel = NSTextField(labelWithString: "Unmodified NSSearchField")
            let textLabel = NSTextField(labelWithString: "Unmodified NSTextField")
            referenceSearch.placeholderString = "Native search"
            referenceText.placeholderString = "Native text"
            referenceSearch.font = .systemFont(ofSize: 14)
            referenceText.font = .systemFont(ofSize: 14)
            for view in [searchLabel, referenceSearch, textLabel, referenceText] {
                view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20).isActive = true
            }
            NSLayoutConstraint.activate([
                searchLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
                referenceSearch.topAnchor.constraint(equalTo: searchLabel.bottomAnchor, constant: 8),
                referenceSearch.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
                referenceSearch.heightAnchor.constraint(equalToConstant: 32),
                textLabel.topAnchor.constraint(equalTo: referenceSearch.bottomAnchor, constant: 20),
                referenceText.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8),
                referenceText.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
                referenceText.heightAnchor.constraint(equalToConstant: 32)
            ])
            referenceWindow = window
        }
        referenceWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func showSettings(_ sender: Any?) { controller.window?.makeKeyAndOrderFront(nil) }
    @objc func resizeClient(_ sender: NSMenuItem) {
        guard let window = NSApp.keyWindow else { return }
        let widths: [CGFloat] = [600, 640, 1000]
        window.setContentSize(NSSize(width: widths[sender.tag], height: window.contentView?.bounds.height ?? 680))
    }
    func install() {
        let bar = NSMenu(), item = NSMenuItem(), menu = NSMenu(title: "Pinyin client audit")
        item.submenu = menu; bar.addItem(item)
        let record = NSMenuItem(title: "Record client coordinates", action: #selector(record(_:)), keyEquivalent: "r")
        record.target = self; record.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(record)
        let reference = NSMenuItem(title: "Show native reference", action: #selector(showReference(_:)), keyEquivalent: "b")
        reference.target = self; reference.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(reference)
        let settings = NSMenuItem(title: "Show actual Settings client", action: #selector(showSettings(_:)), keyEquivalent: "s")
        settings.target = self; settings.keyEquivalentModifierMask = [.command, .shift]; menu.addItem(settings)
        for (index, width) in [600, 640, 1000].enumerated() {
            let resize = NSMenuItem(title: "Client width \(width)", action: #selector(resizeClient(_:)), keyEquivalent: String(index + 1))
            resize.target = self; resize.tag = index; resize.keyEquivalentModifierMask = [.command, .option]; menu.addItem(resize)
        }
        let quit = NSMenuItem(title: "Quit pinyin client audit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); NSApp.mainMenu = bar
        let editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        editItem.submenu = edit; bar.addItem(editItem)
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown,.leftMouseUp], handler: { [weak self] event in
            let key = event.type == .keyDown ? String(event.keyCode) : "pointer"
            DispatchQueue.main.async { [weak self] in
                guard let self, event.window === self.controller.window || event.window === self.referenceWindow else { return }
                self.capture("after input \(event.type.rawValue)/\(key)", eventFlags: event.modifierFlags.rawValue)
            }
            return event
        }) { monitors.append(monitor) }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeKeyNotification, NSTextInputContext.keyboardSelectionDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let window = note.object as? NSWindow, window !== self.controller.window && window !== self.referenceWindow { return }
                    self.capture(name.rawValue)
                }
            })
        }
    }
}

@main struct SettingsPinyinAudit {
    @MainActor static func main() throws {
        precondition(Bundle.main.bundleIdentifier == "org.fluentkit.audit.system-pinyin")
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "AuditOutput") as! String)
        let shared = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "RimeSharedDirectory") as! String)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = try RimeEngine(sharedDirectory: shared,
            userDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("FluentIME-SystemPinyinAudit-" + UUID().uuidString))
        defer { FIMFinalize() }
        let controller = try SettingsWindowController(engine: engine)
        controller.showWindow(nil); controller.window?.title = "Fluent Settings — System Pinyin Audit"
        let actions = PinyinAuditActions(controller: controller, output: output)
        actions.install(); actions.capture("opened")
        NSApp.activate(ignoringOtherApps: true)
        withExtendedLifetime(actions) { NSApp.run() }
        controller.window?.close()
    }
}
