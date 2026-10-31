import AppKit
import FluentKit

@main struct CalendarScrollingAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let output = URL(fileURLWithPath: CommandLine.arguments[1]); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        func capture(_ view: NSView, _ name: String) throws {
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded(); CATransaction.flush()
            let size = view.bounds.size
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: image)!.cgContext; cg.scaleBy(x: 2, y: 2)
            if view.isFlipped { cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1) }
            view.layer!.render(in: cg)
            try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        var calendar = Calendar(identifier: .gregorian); calendar.locale = Locale(identifier: "en_US"); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
        var records: [[String: Any]] = []
        for dark in [false, true] { for rtl in [false, true] { for mode in FluentCalendarDisplayMode.allCases {
            let state = FluentState(wrappedValue: [date(2026, 5, 12)])
            let context = FluentRenderContext(theme: .custom(colorScheme: dark ? .dark : .light, materialEffectsEnabled: false), reduceMotion: true, layoutDirection: rtl ? .rightToLeft : .leftToRight)
            func content() -> FluentCalendarView { FluentCalendarView(selection: state.projectedValue, selectionMode: .multiple,
                displayDate: date(2026, 5, 12), displayMode: mode, range: date(1900,1,1)...date(2200,12,31), calendar: calendar) }
            let native = content()._makeView(in: context); native.userInterfaceLayoutDirection = rtl ? .rightToLeft : .leftToRight
            let window = NSWindow(contentRect: NSRect(x: 100, y: 350, width: 350, height: 390), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let stage = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 390)); stage.wantsLayer = true
            stage.layer?.backgroundColor = (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
            window.contentView = stage; stage.addSubview(native); native.frame = NSRect(x: 20, y: 20, width: 310, height: 350)
            window.makeKeyAndOrderFront(nil); native.layoutSubtreeIfNeeded()
            let name = "\(dark ? "dark" : "light")-\(rtl ? "rtl" : "ltr")-\(mode.rawValue)"
            let scroll = all(native).first { $0 is NSScrollView } as? NSScrollView
            let initialY = scroll?.contentView.bounds.minY ?? 0
            func record(_ phase: String) throws {
                native.layoutSubtreeIfNeeded()
                let cells = all(native).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.contains(".Day.") == true }
                let visible = cells.filter { !$0.isHidden && !$0.visibleRect.isEmpty }.sorted {
                    Int($0.identifier!.rawValue.split(separator: ".").last!)! < Int($1.identifier!.rawValue.split(separator: ".").last!)!
                }
                records.append(["variant": name, "phase": phase, "hasScroll": scroll != nil,
                    "offset": scroll?.contentView.bounds.minY ?? 0, "height": scroll?.documentView?.frame.height ?? 0,
                    "realized": cells.count, "visible": visible.count, "first": visible.first?.accessibilityLabel() ?? "",
                    "header": all(native).first { $0.identifier?.rawValue.hasSuffix(".Header") == true }?.accessibilityLabel() ?? "",
                    "selected": state.wrappedValue.count])
                try capture(stage, name + "-" + phase)
            }
            try record("initial")
            scroll?.contentView.scroll(to: NSPoint(x: 0, y: initialY + 13)); if let scroll { scroll.reflectScrolledClipView(scroll.contentView) }
            try record("partial")
            if let scroll {
                let lastOffset = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(initialY + 50_000, lastOffset)))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            try record("far")
            for _ in 0..<30 { _ = content()._updateView(native, in: context) }
            try record("refresh")
            window.close()
        }}}
        var arithmetic: [[String: Any]] = []
        for (year, month, day, name) in [(2011, 12, 31, "apia-2011-december"), (2026, 5, 12, "apia-2026-may")] {
            var local = calendar; local.timeZone = TimeZone(identifier: "Pacific/Apia")!
            let selected = local.date(from: DateComponents(year: year, month: month, day: day))!
            let lower = local.date(from: DateComponents(year: 1900, month: 1, day: 1))!
            let upper = local.date(from: DateComponents(year: 2200, month: 12, day: 31))!
            let native = FluentCalendarView(selectedDates: [selected], displayDate: selected, range: lower...upper, calendar: local)
                ._makeView(in: .init(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: true))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 350, width: 310, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = native; window.makeKeyAndOrderFront(nil)
            native.layoutSubtreeIfNeeded()
            guard let scroll = all(native).compactMap({ $0 as? NSScrollView }).first else {
                window.close(); continue // Baseline builds have no continuous grid.
            }
            let cells = all(native).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.contains(".Day.") == true && !$0.isHidden && !$0.visibleRect.isEmpty }
            let formatter = DateFormatter(); formatter.calendar = local; formatter.timeZone = local.timeZone; formatter.locale = local.locale
            formatter.setLocalizedDateFormatFromTemplate("EEEE yMMMMd")
            for cell in cells {
                let date = formatter.date(from: cell.accessibilityLabel()!)!
                let expectedColumn = (local.component(.weekday, from: date) - local.firstWeekday + 7) % 7
                precondition(Int(cell.frame.midX / scroll.documentView!.bounds.width * 7) == expectedColumn, "A rendered date is under the wrong weekday")
            }
            precondition(cells.count == (year == 2011 ? 41 : 42))
            arithmetic.append(["case": name, "visible": cells.count, "weekdayColumnsCorrect": true])
            try capture(native, name); window.close()
        }
        try JSONSerialization.data(withJSONObject: arithmetic, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("date-arithmetic.json"))
        print(String(decoding: try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
