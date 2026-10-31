import AppKit
import FluentKit

@main struct CalendarDatePickerScrollingAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 12))!
        let state = FluentState(wrappedValue: date)
        let host = FluentViewHost(FluentDatePickerView(selection: state.projectedValue).frame(width: 240, height: 32),
            context: .init(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: true))
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded()
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        all(host).compactMap { $0 as? NSDatePicker }.first!.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let calendars = NSApp.windows.compactMap(\.contentView).flatMap(all).filter {
            $0.identifier?.rawValue == "FluentKit.CalendarDatePicker.Calendar"
        }
        precondition(calendars.count == 1)
        let control = calendars[0], panel = control.window!.contentView!
        precondition(control.bounds.size == NSSize(width: 310, height: 350))
        precondition(all(control).allSatisfy { !($0 is NSDatePicker) })
        let scroll = all(control).compactMap { $0 as? NSScrollView }.first!
        func capture(_ name: String) throws {
            panel.layoutSubtreeIfNeeded(); panel.displayIfNeeded(); CATransaction.flush()
            let size = panel.bounds.size
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: image)!.cgContext
            context.scaleBy(x: 2, y: 2)
            if panel.isFlipped { context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1) }
            panel.layer!.render(in: context)
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        try capture("popover-initial")
        let before = scroll.contentView.bounds.minY
        scroll.contentView.scroll(to: NSPoint(x: 0, y: before + 13)); scroll.reflectScrolledClipView(scroll.contentView)
        precondition(abs(scroll.contentView.bounds.minY - before - 13) < 0.01)
        try capture("popover-partial")
        let day = all(control).compactMap { $0 as? NSButton }.filter {
            $0.identifier?.rawValue.contains(".Day.") == true && $0.title == "12" && !$0.isHidden && !$0.visibleRect.isEmpty
        }.sorted { Int($0.identifier!.rawValue.split(separator: ".").last!)! < Int($1.identifier!.rawValue.split(separator: ".").last!)! }.first!
        day.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(calendar.isDate(state.wrappedValue, inSameDayAs: expected))
        precondition(control.window == nil || control.window?.isVisible == false)
        print("PASS: one shared 310×350 calendar; continuous 13pt scrolling; May 12 selection committed; popover dismissed")
        window.close()
    }
}
