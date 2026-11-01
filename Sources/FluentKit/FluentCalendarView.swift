import AppKit

public enum FluentCalendarSelectionMode: String, CaseIterable, Sendable {
    case none, single, multiple
}

public enum FluentCalendarDisplayMode: String, CaseIterable, Sendable {
    case month, year, decade
}

/// An embedded calendar with day selection and virtualized Month / Year / Decade scrolling.
/// Dates are compared by calendar day in the configured time zone. Multiple selection retains
/// duplicate model entries; activating a selected day removes every equivalent entry.
/// `displayDate` and `displayMode` are initial values and subsequent change requests: browsing
/// survives parent updates that repeat the same values. Without a binding, `selectedDates`
/// follows the same rule. A bound selection is synchronized after range/mode/blackout changes.
/// `numberOfWeeksInView` sets the month viewport (2...8, default 6; outliers are clamped).
/// Omitted date bounds use January 1 (Gregorian current year - 100) and December 31 (+100)
/// in the configured time zone. Supply an explicit range to browse beyond these defaults.
/// Month/year items split at era boundaries; decade scopes stay within one era and begin
/// with years 1–9. Keyboard navigation and drilling into a partial year retain valid dates.
public struct FluentCalendarView: FluentUpdatablePrimitiveView {
    private let selection: FluentBinding<[Date]>?
    private let selectedDates: [Date]
    private let selectionMode: FluentCalendarSelectionMode
    private let displayDate: Date?
    private let displayMode: FluentCalendarDisplayMode
    private let range: ClosedRange<Date>?
    private let calendar: Calendar?
    private let firstWeekday: Int?
    private let blackoutDates: [Date]
    private let isTodayHighlighted: Bool
    private let numberOfWeeksInView: Int
    private let onSelectionChanged: (([Date]) -> Void)?

    public init(
        selection: FluentBinding<[Date]>? = nil,
        selectedDates: [Date] = [],
        selectionMode: FluentCalendarSelectionMode = .single,
        displayDate: Date? = nil,
        displayMode: FluentCalendarDisplayMode = .month,
        range: ClosedRange<Date>? = nil,
        calendar: Calendar? = nil,
        firstWeekday: Int? = nil,
        blackoutDates: [Date] = [],
        isTodayHighlighted: Bool = true,
        numberOfWeeksInView: Int = 6,
        onSelectionChanged: (([Date]) -> Void)? = nil
    ) {
        self.selection = selection
        self.selectedDates = selectedDates
        self.selectionMode = selectionMode
        self.displayDate = displayDate
        self.displayMode = displayMode
        self.range = range
        self.calendar = calendar
        self.firstWeekday = firstWeekday
        self.blackoutDates = blackoutDates
        self.isTodayHighlighted = isTodayHighlighted
        self.numberOfWeeksInView = min(8, max(2, numberOfWeeksInView))
        self.onSelectionChanged = onSelectionChanged
    }

    public var body: NeverFluentView { NeverFluentView() }

    private func configuration(in context: FluentRenderContext) -> FluentCalendarConfiguration {
        var calendar = self.calendar ?? .current
        if self.calendar?.locale == nil { calendar.locale = context.locale }
        if let firstWeekday { calendar.firstWeekday = min(7, max(1, firstWeekday)) }
        return FluentCalendarConfiguration(calendar: calendar, selectionMode: selectionMode,
            minDate: range?.lowerBound, maxDate: range?.upperBound, blackoutDates: blackoutDates,
            isTodayHighlighted: isTodayHighlighted, numberOfWeeksInView: numberOfWeeksInView)
    }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentCalendarViewNative(configuration: configuration(in: context),
            selection: selection, selectedDates: selectedDates, displayDate: displayDate,
            displayMode: displayMode, theme: context.theme, onSelectionChanged: onSelectionChanged)
        view.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let view = view as? FluentCalendarViewNative else { return false }
        view.userInterfaceLayoutDirection = context.layoutDirection.appKitValue
        view.update(configuration: configuration(in: context), selection: selection,
            selectedDates: selectedDates, displayDate: displayDate, displayMode: displayMode,
            theme: context.theme, onSelectionChanged: onSelectionChanged)
        return true
    }
}
