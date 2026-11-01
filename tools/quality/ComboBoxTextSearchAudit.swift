import AppKit
import FluentKit

@main struct ComboBoxTextSearchAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let titles = ["Alpha", "Bravo", "Blue sky", "Blue sea", "Charlie"]
        var samples: [[String: Any]] = []
        for dark in [false, true] {
            for rtl in [false, true] {
                for always in [false, true] {
                    for open in [false, true] {
                        for scenario in ["prefix", "words", "escape", "disabled"] {
                            let selection = FluentState<Int?>(wrappedValue: 0)
                            let definition = FluentComboBox(options: Array(titles.indices), selection: selection.projectedValue,
                                title: { titles[$0] }).selectionChangedTrigger(always ? .always : .committed)
                                .isTextSearchEnabled(scenario != "disabled")
                            let host = FluentViewHost(definition, context: .init(theme: .custom(colorScheme: dark ? .dark : .light),
                                reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight))
                            let window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 500, height: 300),
                                styleMask: [.titled], backing: .buffered, defer: false)
                            window.isReleasedWhenClosed = false
                            defer { window.close() }
                            window.contentView?.addSubview(host); host.translatesAutoresizingMaskIntoConstraints = true
                            host.frame = NSRect(x: 50, y: 170, width: 280, height: 32)
                            window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
                            guard let bridge = all(host).compactMap({ $0 as? NSComboBox }).first else {
                                throw NSError(domain: "ComboBoxTextSearchAudit", code: 1)
                            }
                            window.makeFirstResponder(bridge)
                            if open { bridge.performClick(nil) }
                            let panel = window.childWindows?.first(where: { $0.isVisible })
                            let responder = open ? panel?.firstResponder : window.firstResponder
                            func key(_ characters: String, code: UInt16) {
                                let owner = window.childWindows?.first(where: { $0.isVisible }) ?? window
                                NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: owner.windowNumber, context: nil,
                                    characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
                            }
                            for character in scenario == "words" ? "blue se" : "c" {
                                key(String(character), code: character == " " ? 49 : 0)
                            }
                            let rows = panel?.contentView.map { all($0).filter { $0.accessibilityRole() == .menuItem } } ?? []
                            var row: [String: Any] = ["dark": dark, "rtl": rtl, "always": always, "open": open,
                                "scenario": scenario, "selection": selection.wrappedValue ?? -1,
                                "focusedTitles": rows.filter { $0.isAccessibilityFocused() }.compactMap { $0.accessibilityTitle() },
                                "selectedTitles": rows.filter { $0.isAccessibilitySelected() }.compactMap { $0.accessibilityTitle() },
                                "popupOpen": window.childWindows?.contains(where: { $0.isVisible }) == true,
                                "panelPreserved": !open || (panel != nil && window.childWindows?.contains(where: { $0 === panel && $0.isVisible }) == true),
                                "responderPreserved": responder != nil && (open ? panel?.firstResponder : window.firstResponder) === responder]
                            if scenario == "escape", open { key("\u{1b}", code: 53) }
                            row["afterSelection"] = selection.wrappedValue ?? -1
                            row["afterPopupOpen"] = window.childWindows?.contains(where: { $0.isVisible }) == true
                            samples.append(row)
                        }
                    }
                }
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
