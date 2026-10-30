import XCTest
@testable import FluentKit

final class CalendarViewRegressionTests: XCTestCase {
    private func calendar(_ zone: String = "UTC", firstWeekday: Int = 1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        value.locale = Locale(identifier: "en_US")
        value.firstWeekday = firstWeekday
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { self.buttons($0) }
    }
    @MainActor
    func testWeekdayTitlesFollowTheConfiguredFirstWeekday() {
        _ = NSApplication.shared
        let value = calendar(firstWeekday: 2)
        let editor = FluentCalendarPickerEditorView(selectedDate: date(2026, 5, 10, calendar: value),
            calendar: value, locale: Locale(identifier: "en_US"), timeZone: value.timeZone, onSelect: { _ in })
        let labels = editor.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
        XCTAssertEqual(labels, ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"])
    }
    @MainActor
    func testExplicitTimeZoneControlsBothGridMathAndReturnedDates() throws {
        _ = NSApplication.shared
        let utc = calendar()
        let local = calendar("America/Los_Angeles")
        var selections: [Date] = []
        let editor = FluentCalendarPickerEditorView(selectedDate: date(2026, 1, 1, calendar: utc),
            calendar: utc, locale: Locale(identifier: "en_US"), timeZone: local.timeZone,
            onSelect: { selections.append($0) })
        let first = try XCTUnwrap(buttons(editor).first {
            $0.identifier?.rawValue.hasPrefix("FluentKit.CalendarDatePicker.Day.") == true && $0.title == "1"
        })
        first.performClick(nil)
        let selected = try XCTUnwrap(selections.first)
        XCTAssertEqual(local.dateComponents([.year, .month, .day], from: selected),
            DateComponents(year: 2025, month: 12, day: 1))
    }
    @MainActor
    func testRangePreventsNavigationIntoEntirelyUnavailableMonths() throws {
        _ = NSApplication.shared
        let value = calendar()
        let editor = FluentCalendarPickerEditorView(selectedDate: date(2026, 5, 10, calendar: value),
            calendar: value, locale: Locale(identifier: "en_US"), timeZone: value.timeZone,
            minDate: date(2026, 5, 1, calendar: value), maxDate: date(2026, 5, 31, calendar: value), onSelect: { _ in })
        let previous = try XCTUnwrap(buttons(editor).first { $0.identifier?.rawValue == "FluentKit.CalendarDatePicker.PreviousMonth" })
        let next = try XCTUnwrap(buttons(editor).first { $0.identifier?.rawValue == "FluentKit.CalendarDatePicker.NextMonth" })
        XCTAssertFalse(previous.isEnabled)
        XCTAssertFalse(next.isEnabled)
    }

    private func day(_ number: Int, in view: NSView) throws -> NSButton {
        try XCTUnwrap(buttons(view).first {
            $0.identifier?.rawValue.contains(".Day.") == true && !$0.isHidden && $0.title == String(number)
        })
    }
    private func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code)!
    }
    @MainActor
    func testSelectionModesDuplicateDaysAndBlackoutReconcileTheModel() throws {
        _ = NSApplication.shared
        let c = calendar(), context = FluentRenderContext()
        let ten = date(2026, 5, 10, calendar: c), eleven = date(2026, 5, 11, calendar: c)
        let selection = FluentState(wrappedValue: [ten, ten.addingTimeInterval(3600), eleven])
        func control(_ mode: FluentCalendarSelectionMode, blackout: [Date] = []) -> FluentCalendarView {
            FluentCalendarView(selection: selection.projectedValue, selectionMode: mode,
                displayDate: ten, calendar: c, blackoutDates: blackout)
        }
        let native = control(.multiple)._makeView(in: context)
        XCTAssertEqual(selection.wrappedValue.count, 3)
        try day(10, in: native).performClick(nil)
        XCTAssertEqual(selection.wrappedValue, [eleven], "Deselecting a day removes all equivalent entries")
        try day(10, in: native).performClick(nil)
        XCTAssertEqual(selection.wrappedValue, [eleven, ten])
        XCTAssertTrue(control(.single)._updateView(native, in: context))
        XCTAssertEqual(selection.wrappedValue, [eleven], "Single mode retains the first entry")
        try day(11, in: native).performClick(nil)
        XCTAssertTrue(selection.wrappedValue.isEmpty, "Standalone single selection allows deselection")
        try day(10, in: native).performClick(nil)
        XCTAssertTrue(control(.single, blackout: [ten])._updateView(native, in: context))
        XCTAssertTrue(selection.wrappedValue.isEmpty, "New blackout dates remove selected entries")
        XCTAssertFalse(try day(10, in: native).accessibilityPerformPress())
        try day(11, in: native).performClick(nil)
        XCTAssertTrue(control(.none)._updateView(native, in: context))
        try day(12, in: native).performClick(nil)
        XCTAssertTrue(selection.wrappedValue.isEmpty)
    }
    @MainActor
    func testRangeUpdatesAndDisplayRequestsAreClampedByCalendarDay() throws {
        _ = NSApplication.shared
        let c = calendar(), context = FluentRenderContext()
        let first = date(2026, 5, 10, calendar: c), last = date(2026, 5, 20, calendar: c)
        let selection = FluentState(wrappedValue: [first, last])
        func control(_ range: ClosedRange<Date>, display: Date) -> FluentCalendarView {
            FluentCalendarView(selection: selection.projectedValue, selectionMode: .multiple,
                displayDate: display, range: range, calendar: c)
        }
        let native = try XCTUnwrap(control(first...last, display: first)._makeView(in: context) as? FluentCalendarViewNative)
        XCTAssertFalse(try day(9, in: native).isEnabled)
        XCTAssertTrue(try day(20, in: native).isEnabled)
        XCTAssertFalse(try day(21, in: native).isEnabled)
        let nextDay = date(2026, 5, 11, calendar: c)
        XCTAssertTrue(control(nextDay...last, display: first)._updateView(native, in: context))
        XCTAssertEqual(selection.wrappedValue, [last])
        XCTAssertEqual(native.model.focusedDate, nextDay)
        XCTAssertTrue(control(nextDay...last, display: date(2027, 1, 1, calendar: c))._updateView(native, in: context))
        XCTAssertEqual(native.model.displayedDate, last)
    }
    @MainActor
    func testBindingReplacementIgnoresQueuedNotificationsAndDetachesWhenRemoved() throws {
        _ = NSApplication.shared
        let c = calendar(), context = FluentRenderContext()
        let ten = date(2026, 5, 10, calendar: c), fifteen = date(2026, 5, 15, calendar: c)
        let first = FluentState(wrappedValue: [ten]), second = FluentState(wrappedValue: [fifteen])
        var changes: [[Date]] = []
        func control(_ binding: FluentBinding<[Date]>?) -> FluentCalendarView {
            FluentCalendarView(selection: binding, displayDate: ten, calendar: c,
                onSelectionChanged: { changes.append($0) })
        }
        let native = try XCTUnwrap(control(first.projectedValue)._makeView(in: context) as? FluentCalendarViewNative)
        first.wrappedValue = []
        XCTAssertTrue(control(second.projectedValue)._updateView(native, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.model.selectedDates, [fifteen])
        XCTAssertEqual(changes, [[fifteen]])
        second.wrappedValue = [ten]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.model.selectedDates, [ten])
        XCTAssertTrue(control(nil)._updateView(native, in: context))
        second.wrappedValue = []
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.model.selectedDates, [ten])
    }
    @MainActor
    func testKeyboardUsesScopeBoundariesRTLAndHierarchyWithoutSelectingOnFocus() throws {
        _ = NSApplication.shared
        let c = calendar(), context = FluentRenderContext()
        let ten = date(2026, 5, 10, calendar: c)
        let selection = FluentState(wrappedValue: [Date]())
        let native = try XCTUnwrap(FluentCalendarView(selection: selection.projectedValue,
            displayDate: ten, calendar: c)._makeView(in: context) as? FluentCalendarViewNative)
        native.keyDown(with: key(124))
        XCTAssertEqual(c.component(.day, from: native.model.focusedDate), 11)
        XCTAssertTrue(selection.wrappedValue.isEmpty)
        native.keyDown(with: key(49))
        XCTAssertEqual(c.component(.day, from: selection.wrappedValue[0]), 11)
        native.userInterfaceLayoutDirection = .rightToLeft
        native.keyDown(with: key(124))
        XCTAssertEqual(c.component(.day, from: native.model.focusedDate), 10)
        native.keyDown(with: key(115))
        XCTAssertEqual(c.component(.day, from: native.model.focusedDate), 1)
        native.keyDown(with: key(119))
        XCTAssertEqual(c.component(.day, from: native.model.focusedDate), 31)
        native.keyDown(with: key(123))
        XCTAssertEqual(c.dateComponents([.month, .day], from: native.model.displayedDate), DateComponents(month: 6, day: 1))
        native.keyDown(with: key(126, modifiers: .control))
        XCTAssertEqual(native.model.mode, .year)
        native.keyDown(with: key(126, modifiers: .control))
        XCTAssertEqual(native.model.mode, .decade)
        native.keyDown(with: key(125, modifiers: .control))
        XCTAssertEqual(native.model.mode, .year)
        native.keyDown(with: key(125, modifiers: .control))
        XCTAssertEqual(native.model.mode, .month)
    }
    @MainActor
    func testDSTGridAndThirteenMonthYearKeepCalendarDatesAndFourByFourLayout() throws {
        _ = NSApplication.shared
        let c = calendar("America/Los_Angeles"), context = FluentRenderContext()
        let native = try XCTUnwrap(FluentCalendarView(displayDate: date(2026, 3, 8, calendar: c),
            calendar: c)._makeView(in: context) as? FluentCalendarViewNative)
        let dates = native.model.cellDates
        XCTAssertEqual(dates.count, 42)
        XCTAssertTrue(dates.allSatisfy { c.component(.hour, from: $0) == 0 })
        XCTAssertTrue(zip(dates, dates.dropFirst()).contains { $1.timeIntervalSince($0) == 23 * 3600 })
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = c.timeZone
        hebrew.locale = Locale(identifier: "en_US")
        let start = date(5784, 1, 1, calendar: hebrew)
        let view = FluentCalendarView(displayDate: start, displayMode: .year, calendar: hebrew)
        XCTAssertTrue(view._updateView(native, in: context))
        native.frame = NSRect(origin: .zero, size: native.intrinsicContentSize)
        native.layoutSubtreeIfNeeded()
        let months = native.model.cellDates.filter { hebrew.component(.year, from: $0) == 5784 }
        XCTAssertEqual(months.count, 13)
        XCTAssertEqual(Set(months.map { hebrew.component(.month, from: $0) }).count, 13)
        let cells = buttons(native).filter { $0.identifier?.rawValue.contains(".Day.") == true && !$0.isHidden }
        XCTAssertEqual(cells.count, 16)
        XCTAssertEqual(Set(cells.map(\.frame.minX)).count, 4)
        XCTAssertEqual(Set(cells.map(\.frame.minY)).count, 4)
        try XCTUnwrap(buttons(native).first { $0.identifier?.rawValue.hasSuffix(".Header") == true }).performClick(nil)
        native.layoutSubtreeIfNeeded()
        native.needsLayout = false
        XCTAssertTrue(view._updateView(native, in: context))
        XCTAssertEqual(native.model.mode, .decade, "Unchanged parent values must preserve browsing")
        XCTAssertFalse(native.needsLayout, "Unrelated parent updates must not refresh the entire calendar")
        native.frame.size = .zero
        native.layoutSubtreeIfNeeded()
        XCTAssertTrue(native.subviews.allSatisfy { $0.frame.width >= 0 && $0.frame.height >= 0 })
    }

    @MainActor
    func testDisabledWrapperRestoresOnlyAvailableDatesAndArabicWeekdaysRemainDistinct() throws {
        _ = NSApplication.shared
        var c = calendar()
        c.locale = Locale(identifier: "ar_SA")
        let first = date(2026, 5, 10, calendar: c), last = date(2026, 5, 20, calendar: c)
        let selection = FluentState(wrappedValue: [first])
        func calendarView() -> FluentCalendarView {
            FluentCalendarView(selection: selection.projectedValue, displayDate: first, range: first...last, calendar: c)
        }
        let context = FluentRenderContext()
        let host = FluentViewHost(FluentAnyView(calendarView().disabled(true)), context: context)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let native = try XCTUnwrap(descendants(host).compactMap { $0 as? FluentCalendarViewNative }.first)
        XCTAssertFalse(native.isEnabled)
        XCTAssertTrue(buttons(native).allSatisfy { !$0.isEnabled })
        XCTAssertEqual(Set(native.subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)).count, 7)
        host.update(FluentAnyView(calendarView().disabled(false)), context: context)
        XCTAssertTrue(native.isEnabled)
        let dates = buttons(native).filter { $0.identifier?.rawValue.contains(".Day.") == true }
        XCTAssertEqual(dates.filter(\.isEnabled).count, 11)
        XCTAssertFalse(try XCTUnwrap(buttons(native).first { $0.identifier?.rawValue.hasSuffix(".NextMonth") == true }).isEnabled)
    }

    @MainActor
    func testDatePickerRebindingDoesNotApplyAQueuedOldModelValue() throws {
        _ = NSApplication.shared
        let c = calendar(), context = FluentRenderContext()
        let ten = date(2026, 5, 10, calendar: c), fifteen = date(2026, 5, 15, calendar: c)
        let first = FluentState(wrappedValue: ten), second = FluentState(wrappedValue: fifteen)
        let native = try XCTUnwrap(FluentDatePickerView(selection: first.projectedValue)._makeView(in: context) as? NSDatePicker)
        first.wrappedValue = date(2026, 5, 11, calendar: c)
        XCTAssertTrue(FluentDatePickerView(selection: second.projectedValue)._updateView(native, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.dateValue, fifteen)
        first.wrappedValue = ten
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.dateValue, fifteen)
        second.wrappedValue = ten
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.dateValue, ten)
        XCTAssertEqual(native.accessibilityValue() as? Date, ten)
    }

    @MainActor
    func testChineseDayLabelsAreNumbersWhileAccessibilityKeepsTheFullDate() throws {
        _ = NSApplication.shared
        var c = calendar()
        c.locale = Locale(identifier: "zh_CN")
        let view = FluentCalendarView(displayDate: date(2026, 5, 10, calendar: c), calendar: c)._makeView(in: .init())
        let twelve = try day(12, in: view)
        XCTAssertEqual(twelve.title, "12")
        XCTAssertTrue(twelve.accessibilityLabel()?.contains("2026") == true)
        XCTAssertTrue(twelve.accessibilityLabel()?.contains("12") == true)
    }
}
