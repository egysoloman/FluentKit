import AppKit
import FluentKit

@main struct CalendarDatePickerPopoverAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let state = FluentState(wrappedValue: date)
        let host = FluentViewHost(FluentDatePickerView(selection: state.projectedValue).frame(width: 240, height: 32),
            context: .init(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: true))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let picker = descendants(host).compactMap { $0 as? NSDatePicker }.first!
        picker.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let calendars = NSApp.windows.compactMap(\.contentView).flatMap(descendants).filter {
            $0.identifier?.rawValue == "FluentKit.CalendarDatePicker.Calendar"
        }
        fputs("calendar count: \(calendars.count)\n", stderr)
        precondition(calendars.count == 1, "A visible picker must present exactly one shared calendar")
        let calendar = calendars[0]
        fputs("calendar bounds: \(calendar.bounds)\n", stderr)
        precondition(calendar.bounds.width == 310 && calendar.bounds.height == 350)
        precondition(descendants(calendar).filter { $0 is NSDatePicker }.isEmpty)
        let panel = calendar.window!.contentView!
        let image = panel.bitmapImageRepForCachingDisplay(in: panel.bounds)!
        panel.cacheDisplay(in: panel.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: output)
        let day = descendants(calendar).compactMap { $0 as? NSButton }.first { $0.title == "12" }!
        day.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        fputs("selected: \(state.wrappedValue), window visible: \(calendar.window?.isVisible.description ?? "nil")\n", stderr)
        precondition(Calendar.current.component(.day, from: state.wrappedValue) == 12)
        precondition(calendar.window == nil || calendar.window?.isVisible == false)
        print("PASS: shared calendar 310×350, popover \(panel.bounds.size), selection committed and popover dismissed")
        window.close()
    }
}
