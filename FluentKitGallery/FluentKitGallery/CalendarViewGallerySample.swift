import AppKit
import FluentKit

struct CalendarViewGallerySample: FluentView {
    @FluentState private var selected: [Date] = []
    @FluentState private var displayDate = Date()
    @FluentState private var compact = false
    @FluentState private var japaneseEras = false

    private var japaneseCalendar: Calendar {
        var calendar = Calendar(identifier: .japanese)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    var body: some FluentView {
        FluentVStack(spacing: 12, alignment: .leading) {
            FluentText("Scroll continuously through dates. Click the heading to browse months or years.", style: .caption)
            FluentCalendarView(selection: $selected, selectionMode: .multiple, displayDate: displayDate,
                displayMode: japaneseEras ? .decade : .month, calendar: japaneseEras ? japaneseCalendar : nil,
                numberOfWeeksInView: compact ? 2 : 6).frame(width: 310)
            FluentToggleView("Two-week viewport", isOn: $compact)
            FluentToggleView("Browse Japanese era boundaries", isOn: FluentBinding(get: { japaneseEras }, set: { enabled in
                japaneseEras = enabled
                var gregorian = Calendar(identifier: .gregorian)
                gregorian.timeZone = japaneseCalendar.timeZone
                displayDate = enabled ? gregorian.date(from: DateComponents(year: 2019, month: 4, day: 30))! : Date()
            }))
            if japaneseEras {
                FluentText("2019 has separate Heisei 31 and Reiwa 1 year cells. Select either to browse its months.", style: .caption)
            }
            FluentHStack {
                FluentButtonView("Go to today") { displayDate = Date() }
                FluentButtonView("Clear selection") { selected = [] }
            }
            FluentText("Selected dates: \(selected.count)")
            FluentText("Arrow keys move focus; PageUp/PageDown preserve the date within the next scope. Ctrl+Up/Down changes level.", style: .caption)
        }
    }
}
