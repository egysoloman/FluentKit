import AppKit
import FluentKit

@main struct PickerInteractionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for (variant, language, clock) in [("light", "en_US", FluentClockIdentifier.twelveHour),
                                         ("dark", "zh_CN", .twelveHour), ("rtl", "en_US", .twelveHour),
                                         ("arabic", "ar_SA", .twelveHour), ("24hour", "en_GB", .twentyFourHour)] {
            let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
            let context = FluentRenderContext(theme: theme, reduceMotion: true,
                layoutDirection: variant == "rtl" || variant == "arabic" ? .rightToLeft : .leftToRight,
                locale: Locale(identifier: language))
            let state = FluentState<FluentTime?>(wrappedValue: FluentTime(hour: 9, minute: 35))
            var configuredIncrement = 5
            var configuredClock = clock
            func content() -> FluentAnyView {
                FluentAnyView(FluentTimePickerView(selection: state.projectedValue, minuteIncrement: configuredIncrement,
                    clockIdentifier: configuredClock).frame(width: 242, height: 32))
            }
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 320, height: 100),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: variant == "dark" ? .darkAqua : .aqua)
            let host = FluentViewHost(content(), context: context)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            host.layoutSubtreeIfNeeded()
            let picker = descendants(host).compactMap { $0 as? FluentTimePicker }.first!
            func open() -> NSView {
                picker.performClick(nil)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                return NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(descendants).first {
                    $0.identifier?.rawValue == "FluentKit.TimePicker.Editor"
                }!
            }
            func selector(_ field: String, in editor: NSView) -> FluentLoopingSelectorControl {
                descendants(editor).compactMap { $0 as? FluentLoopingSelectorControl }.first {
                    $0.identifier?.rawValue == "FluentKit.TimePicker.\(field)"
                }!
            }
            func key(_ code: UInt16, target: NSView) {
                target.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: target.window!.windowNumber, context: nil, characters: "",
                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
            }
            func capture(_ name: String, view: NSView) throws {
                view.layoutSubtreeIfNeeded()
                precondition(descendants(view).allSatisfy { $0.frame.width >= 0 && $0.frame.height >= 0 })
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(variant)-\(name).png"))
                records.append(["variant": variant, "state": name, "committed": state.wrappedValue?.description ?? "nil",
                    "width": view.bounds.width, "height": view.bounds.height,
                    "voiceOver": "pending", "windowsComparison": "pending"])
            }
            try capture("closed", view: host)
            let editor = open()
            var controls = descendants(editor).compactMap { $0 as? FluentLoopingSelectorControl }.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
            precondition(editor.window?.firstResponder === controls[0])
            key(124, target: controls[0])
            precondition(editor.window?.firstResponder === controls[1])
            try capture("initial", view: editor.window!.contentView!)
            let hour = selector("hour", in: editor), minute = selector("minute", in: editor)
            hour.selectedIndex = (hour.selectedIndex + 1) % hour.values.count
            minute.selectedIndex = 8
            precondition(state.wrappedValue == FluentTime(hour: 9, minute: 35))
            host.update(content(), context: context)
            precondition(minute.selectedIndex == 8, "Unchanged parent updates must retain the draft")
            try capture("draft", view: editor.window!.contentView!)
            configuredClock = .twentyFourHour
            configuredIncrement = 15
            host.update(content(), context: context)
            editor.layoutSubtreeIfNeeded()
            precondition(hour.values.count == 24 && hour.selectedIndex == 10 && selector("period", in: editor).isHidden)
            precondition(minute.values.count == 4 && minute.selectedIndex == 2)
            precondition(state.wrappedValue == FluentTime(hour: 9, minute: 30))
            controls = descendants(editor).compactMap { $0 as? FluentLoopingSelectorControl }.filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
            editor.window?.makeFirstResponder(controls.last)
            editor.window?.selectNextKeyView(nil)
            precondition((editor.window?.firstResponder as? NSView)?.accessibilityLabel() == "Accept", "Tab traversal must reach Accept")
            editor.window?.selectNextKeyView(nil)
            precondition((editor.window?.firstResponder as? NSView)?.accessibilityLabel() == "Dismiss", "Tab traversal must reach Dismiss")
            editor.window?.selectNextKeyView(nil)
            precondition(editor.window?.firstResponder === controls[0])
            try capture("reconfigured", view: editor.window!.contentView!)
            state.wrappedValue = FluentTime(hour: 18, minute: 45)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            fputs("external state: \(picker.selectedTime?.description ?? "nil"), hour items: \(hour.values.count), index: \(hour.selectedIndex), minute index: \(minute.selectedIndex), increment: \(picker.minuteIncrement)\n", stderr)
            precondition(hour.selectedIndex == 18 && minute.selectedIndex == 3)
            try capture("external", view: editor.window!.contentView!)
            minute.selectedIndex = 0
            key(53, target: minute)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            precondition(editor.window == nil || editor.window?.isVisible == false)
            precondition(state.wrappedValue == FluentTime(hour: 18, minute: 45), "Escape discards the draft")
            let second = open()
            minute.selectedIndex = 1 // A retained control from the dismissed popup must be inert.
            let secondHour = selector("hour", in: second)
            secondHour.selectedIndex = 19
            key(36, target: secondHour)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            precondition(state.wrappedValue == FluentTime(hour: 19, minute: 45))
            precondition(second.window == nil || second.window?.isVisible == false)
            try capture("committed", view: host)
            picker.selectedTime = nil
            configuredClock = clock
            host.update(content(), context: context)
            try capture("empty", view: host)
            _ = open()
            picker.isEnabled = false
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
            precondition(state.wrappedValue == nil)
            precondition(picker.isAccessibilityExpanded() == false)
            try capture("disabled", view: host)
            window.close()
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
