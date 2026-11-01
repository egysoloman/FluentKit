import AppKit
import FluentKit

@main struct ComboBoxSelectionAudit {
    @MainActor static func capture(_ window: NSWindow, to path: String) throws -> Int {
        window.displayIfNeeded()
        CATransaction.flush()
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
            // A newly ordered window can be visible to AppKit before WindowServer has a
            // readable surface. Retry this read-only capture, bounded by actual readiness.
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        throw NSError(domain: "ComboBoxSelectionAudit.Capture", code: 1)
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        var samples: [[String: Any]] = []
        for dark in [false, true] {
            for rtl in [false, true] {
                for always in [false, true] {
                    for editable in [false, true] {
                        for close in ["return", "tab", "toggle", "escape", "outside", "row"] {
                            let selected = FluentState<Int?>(wrappedValue: 1)
                            let text = FluentState(wrappedValue: "Option 1")
                            var definition = FluentComboBox(options: [0, 1, 2, 3], selection: selected.projectedValue,
                                mode: editable ? .editable : .selection, text: editable ? text.projectedValue : nil,
                                title: { "Option \($0)" })
                            definition = definition.selectionChangedTrigger(always ? .always : .committed)
                            let host = FluentViewHost(definition, context: .init(theme: .custom(colorScheme: dark ? .dark : .light),
                                reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                            let window = NSWindow(contentRect: NSRect(x: 140, y: 160, width: 500, height: 300),
                                styleMask: [.titled], backing: .buffered, defer: false)
                            window.isReleasedWhenClosed = false
                            defer { window.close() }
                            window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
                            host.frame = NSRect(x: 50, y: 170, width: 280, height: 32)
                            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
                            guard let bridge = all(host).compactMap({ $0 as? NSComboBox }).first,
                                  let field = all(host).first(where: { $0.identifier?.rawValue == "FluentKit.ComboBox.EditableText" }) as? NSTextField else {
                                throw NSError(domain: "ComboBoxSelectionAudit", code: 1)
                            }
                            bridge.performClick(nil)
                            guard let panel = window.childWindows?.first else { throw NSError(domain: "ComboBoxSelectionAudit", code: 2) }
                            let editor = field.currentEditor()
                            func key(_ code: UInt16) {
                                let owner = editable ? window : panel
                                let characters = code == 125 ? "\u{F701}" : code == 36 ? "\r" : code == 48 ? "\t" : code == 53 ? "\u{1b}" : ""
                                NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: owner.windowNumber, context: nil, characters: characters,
                                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
                            }
                            key(125)
                            let rows = panel.contentView.map { all($0).filter { $0.accessibilityRole() == .menuItem } } ?? []
                            var row: [String: Any] = ["dark": dark, "rtl": rtl, "always": always, "editable": editable, "close": close,
                                "beforeSelection": selected.wrappedValue ?? -1,
                                "selectedTitles": rows.filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() },
                                "focusedTitles": rows.filter { $0.isAccessibilityFocused() }.compactMap { $0.accessibilityTitle() },
                                "editorPreserved": !editable || (editor != nil && field.currentEditor() === editor),
                                "beforeText": field.stringValue]
                            if close == "return", let folder = ProcessInfo.processInfo.environment["FLUENTKIT_SELECTION_CAPTURE_DIR"] {
                                let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(editable ? "editable" : "selection")-\(always ? "always" : "committed")"
                                row["captureAttempts"] = try capture(editable ? window : panel,
                                    to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png").path)
                            }
                            switch close {
                            case "return": key(36)
                            case "tab": key(48)
                            case "toggle": key(118)
                            case "escape": key(53)
                            case "row":
                                row["rowPressAccepted"] = rows.first { $0.accessibilityTitle() == "Option 2" }?.accessibilityPerformPress() == true
                            default:
                                NSApp.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 450, y: 40),
                                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    eventNumber: 25, clickCount: 1, pressure: 1)!)
                            }
                            row["afterSelection"] = selected.wrappedValue ?? -1
                            row["closed"] = !panel.isVisible
                            samples.append(row)
                        }
                    }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
