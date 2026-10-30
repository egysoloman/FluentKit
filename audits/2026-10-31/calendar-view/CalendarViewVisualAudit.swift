import AppKit
import FluentKit

@main struct CalendarViewVisualAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day))! }
        var records: [[String: Any]] = []
        for variant in ["light", "dark", "rtl"] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true,
                layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight, locale: calendar.locale!)
            let selection = FluentState(wrappedValue: [date(5, 10)])
            var disabled = false
            func content() -> FluentAnyView {
                FluentAnyView(FluentCalendarView(selection: selection.projectedValue, selectionMode: .multiple,
                    displayDate: date(5, 10), range: date(1, 1)...date(12, 31), calendar: calendar,
                    firstWeekday: 2, blackoutDates: [date(5, 15), date(5, 16)], isTodayHighlighted: false)
                    .frame(width: 310, height: 350).disabled(disabled))
            }
            let host = FluentViewHost(content(), context: context)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 390),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            window.contentView = host
            host.wantsLayer = true
            host.layer?.backgroundColor = theme.windowBackground.cgColor
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            host.layoutSubtreeIfNeeded()
            let native = descendants(host).first { $0.identifier?.rawValue == "FluentKit.CalendarView.Calendar" } as! NSControl
            let buttons = descendants(native).compactMap { $0 as? NSButton }
            let header = buttons.first { $0.identifier?.rawValue.hasSuffix(".Header") == true }!
            let twelve = buttons.first { $0.title == "12" && $0.identifier?.rawValue.contains(".Day.") == true }!
            func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
                native.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "",
                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
            }
            func capture(_ state: String, cells count: Int = 42) throws {
                host.update(content(), context: context)
                host.layoutSubtreeIfNeeded()
                let cells = buttons.filter { $0.identifier?.rawValue.contains(".Day.") == true && !$0.isHidden }
                precondition(cells.count == count)
                precondition(native.isEnabled == !disabled)
                if disabled { precondition(buttons.allSatisfy { !$0.isEnabled }) }
                precondition(descendants(host).allSatisfy { $0.frame.width >= 0 && $0.frame.height >= 0 })
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(state).png"))
                records.append(["variant": variant, "state": state, "header": header.title,
                    "visibleCells": cells.count, "selectedDays": selection.wrappedValue.map { calendar.component(.day, from: $0) },
                    "cellWidth": cells.first?.frame.width ?? 0, "cellHeight": cells.first?.frame.height ?? 0,
                    "voiceOver": "pending", "windowsComparison": "pending"])
            }
            try capture("month")
            let pointer = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
            twelve.mouseEntered(with: pointer)
            try capture("hover")
            twelve.performClick(nil)
            precondition(selection.wrappedValue.count == 2)
            twelve.mouseExited(with: pointer)
            try capture("selected")
            window.makeFirstResponder(twelve)
            key(115)
            key(49)
            try capture("keyboard")
            header.performClick(nil)
            try capture("year", cells: 16)
            header.performClick(nil)
            try capture("decade", cells: 16)
            key(125, modifiers: .control)
            key(125, modifiers: .control)
            disabled = true
            try capture("disabled")
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
