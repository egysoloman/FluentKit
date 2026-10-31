import AppKit
import FluentKit

struct CalendarViewGallerySample: FluentView {
    @FluentState private var selected: [Date] = []
    @FluentState private var displayDate = Date()
    @FluentState private var compact = false

    var body: some FluentView {
        FluentVStack(spacing: 12, alignment: .leading) {
            FluentText("Scroll continuously through dates. Click the heading to browse months or years.", style: .caption)
            FluentCalendarView(selection: $selected, selectionMode: .multiple, displayDate: displayDate,
                numberOfWeeksInView: compact ? 2 : 6).frame(width: 310)
            FluentToggleView("Two-week viewport", isOn: $compact)
            FluentHStack {
                FluentButtonView("Go to today") { displayDate = Date() }
                FluentButtonView("Clear selection") { selected = [] }
            }
            FluentText("Selected dates: \(selected.count)")
            FluentText("Arrow keys move focus; PageUp/PageDown preserve the date within the next scope. Ctrl+Up/Down changes level.", style: .caption)
        }
    }
}
