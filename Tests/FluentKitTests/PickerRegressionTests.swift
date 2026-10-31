import XCTest
@testable import FluentKit

final class PickerRegressionTests: XCTestCase {
    @MainActor
    func testTimePickerRejectsQueuedNotificationsAfterRebinding() throws {
        _ = NSApplication.shared
        let first = FluentState<FluentTime?>(wrappedValue: FluentTime(hour: 9, minute: 0))
        let second = FluentState<FluentTime?>(wrappedValue: FluentTime(hour: 15, minute: 0))
        let context = FluentRenderContext(reduceMotion: true)
        let native = try XCTUnwrap(FluentTimePickerView(selection: first.projectedValue)._makeView(in: context) as? FluentTimePicker)
        first.wrappedValue = FluentTime(hour: 10, minute: 0)
        XCTAssertTrue(FluentTimePickerView(selection: second.projectedValue)._updateView(native, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.selectedTime, second.wrappedValue)
    }
    @MainActor
    func testDatePickerRejectsQueuedNotificationsAfterRebinding() throws {
        _ = NSApplication.shared
        let first = FluentState<Date?>(wrappedValue: Date(timeIntervalSince1970: 1_800_000_000))
        let second = FluentState<Date?>(wrappedValue: Date(timeIntervalSince1970: 1_900_000_000))
        let context = FluentRenderContext(reduceMotion: true)
        let native = try XCTUnwrap(FluentWinUIDatePickerView(selection: first.projectedValue)._makeView(in: context) as? FluentWinUIDatePickerControl)
        first.wrappedValue = Date(timeIntervalSince1970: 1_810_000_000)
        XCTAssertTrue(FluentWinUIDatePickerView(selection: second.projectedValue)._updateView(native, in: context))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(native.selectedDate, second.wrappedValue)
    }
    @MainActor
    func testBoundNullWinsOverFallbackAndMinuteCoercionWritesBack() throws {
        _ = NSApplication.shared
        let time = FluentState<FluentTime?>(wrappedValue: nil)
        let date = FluentState<Date?>(wrappedValue: nil)
        let context = FluentRenderContext()
        let picker = try XCTUnwrap(FluentTimePickerView(selection: time.projectedValue,
            time: FluentTime(hour: 8, minute: 0), minuteIncrement: 5)._makeView(in: context) as? FluentTimePicker)
        XCTAssertNil(picker.selectedTime)
        let datePicker = try XCTUnwrap(FluentWinUIDatePickerView(selection: date.projectedValue,
            date: Date())._makeView(in: context) as? FluentWinUIDatePickerControl)
        XCTAssertNil(datePicker.selectedDate)
        time.wrappedValue = FluentTime(hour: 9, minute: 37)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(picker.selectedTime, FluentTime(hour: 9, minute: 35))
        XCTAssertEqual(time.wrappedValue, picker.selectedTime)
    }
    @MainActor
    func testZeroMinuteDoesNotLoopAndPeriodIsLocalizedAndPlacedByPattern() throws {
        _ = NSApplication.shared
        let editor = FluentTimePickerEditorView(time: FluentTime(hour: 13, minute: 0), minuteIncrement: 0,
            clockIdentifier: .twelveHour, locale: Locale(identifier: "zh_CN"), theme: .current, onChange: { _ in })
        editor.frame = NSRect(origin: .zero, size: editor.intrinsicContentSize)
        editor.layoutSubtreeIfNeeded()
        let selectors = editor.subviews.compactMap { $0 as? FluentLoopingSelectorControl }
        let minute = try XCTUnwrap(selectors.first { $0.values.count == 1 })
        let period = try XCTUnwrap(selectors.first { $0.values.count == 2 })
        XCTAssertFalse(minute.shouldLoop)
        XCTAssertEqual(period.values, ["上午", "下午"])
        XCTAssertEqual(period.frame.minX, 0, "Chinese 12-hour patterns put the period first")
    }

    @MainActor
    func testConfigurationAndBindingReplacementAreAppliedAtomically() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext()
        let first = FluentState<FluentTime?>(wrappedValue: FluentTime(hour: 9, minute: 35))
        let second = FluentState<FluentTime?>(wrappedValue: FluentTime(hour: 15, minute: 45))
        let time = try XCTUnwrap(FluentTimePickerView(selection: first.projectedValue, minuteIncrement: 5)._makeView(in: context) as? FluentTimePicker)
        XCTAssertTrue(FluentTimePickerView(selection: second.projectedValue, minuteIncrement: 30)._updateView(time, in: context))
        XCTAssertEqual(time.selectedTime, FluentTime(hour: 15, minute: 30))
        XCTAssertEqual(second.wrappedValue, time.selectedTime)
        XCTAssertEqual(first.wrappedValue, FluentTime(hour: 9, minute: 35))
        let calendar = Calendar(identifier: .gregorian)
        func date(_ year: Int) -> Date { calendar.date(from: DateComponents(year: year, month: 6, day: 15))! }
        let oldDate = FluentState<Date?>(wrappedValue: date(2020)), newDate = FluentState<Date?>(wrappedValue: date(2030))
        let picker = try XCTUnwrap(FluentWinUIDatePickerView(selection: oldDate.projectedValue)._makeView(in: context) as? FluentWinUIDatePickerControl)
        XCTAssertTrue(FluentWinUIDatePickerView(selection: newDate.projectedValue, minYear: date(2025), maxYear: date(2035))._updateView(picker, in: context))
        XCTAssertEqual(picker.selectedDate, date(2030))
        XCTAssertEqual(newDate.wrappedValue, date(2030))
        picker.date = date(2010)
        XCTAssertEqual(picker.date, picker.selectedDate, "The Date alias must agree with the coerced SelectedDate")
        XCTAssertEqual(calendar.component(.year, from: try XCTUnwrap(newDate.wrappedValue)), 2025)
    }
    @MainActor
    func testLiveEditorChangesPreserveIdentityAndUpdateClockMinutesAndLabels() throws {
        _ = NSApplication.shared
        var changes: [FluentTime] = []
        let editor = FluentTimePickerEditorView(time: FluentTime(hour: 13, minute: 37), minuteIncrement: 5,
            clockIdentifier: .twelveHour, locale: Locale(identifier: "en_US"), theme: .current, onChange: { changes.append($0) })
        let controls = editor.subviews.compactMap { $0 as? FluentLoopingSelectorControl }
        let hour = try XCTUnwrap(controls.first { $0.identifier?.rawValue.hasSuffix(".hour") == true })
        let minute = try XCTUnwrap(controls.first { $0.identifier?.rawValue.hasSuffix(".minute") == true })
        let period = try XCTUnwrap(controls.first { $0.identifier?.rawValue.hasSuffix(".period") == true })
        XCTAssertEqual(editor.time, FluentTime(hour: 13, minute: 35))
        editor.update(time: FluentTime(hour: 20, minute: 59), minuteIncrement: 15,
            clockIdentifier: .twentyFourHour, locale: Locale(identifier: "zh_CN"), theme: .current)
        XCTAssertEqual(hour.values.count, 24)
        XCTAssertEqual(hour.values[hour.selectedIndex], "20")
        XCTAssertEqual(minute.values, ["00", "15", "30", "45"])
        XCTAssertEqual(minute.selectedIndex, 3)
        XCTAssertTrue(period.isHidden)
        XCTAssertTrue(changes.isEmpty, "Programmatic reconfiguration is not a user edit")
        minute.selectedIndex = 1
        XCTAssertEqual(changes, [FluentTime(hour: 20, minute: 15)])
        editor.update(time: editor.time, minuteIncrement: 0, clockIdentifier: .twelveHour,
            locale: Locale(identifier: "zh_CN"), theme: .current)
        XCTAssertEqual(minute.values, ["00"])
        XCTAssertFalse(minute.shouldLoop)
        XCTAssertFalse(period.isHidden)
        editor.frame = NSRect(origin: .zero, size: editor.intrinsicContentSize)
        editor.layoutSubtreeIfNeeded()
        XCTAssertLessThan(period.frame.minX, hour.frame.minX)
        XCTAssertTrue(editor.subviews.contains { $0 === minute })
        editor.frame.size = .zero
        editor.layoutSubtreeIfNeeded()
        XCTAssertTrue(editor.subviews.allSatisfy { $0.frame.width >= 0 && $0.frame.height >= 0 })
    }
    @MainActor
    func testClosedAndFlyoutLocalePresentationAndRTLNumericPairAgree() throws {
        _ = NSApplication.shared
        let time = FluentTime(hour: 13, minute: 5)
        let context = FluentRenderContext(locale: Locale(identifier: "zh_CN"))
        let native = try XCTUnwrap(FluentTimePickerView(time: time, clockIdentifier: .twelveHour)._makeView(in: context) as? FluentTimePicker)
        XCTAssertEqual(native.displayColumns, ["下午", "1", "05"])
        let english = FluentTimePickerPresentation(clock: .twelveHour, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(english.fields(rightToLeft: true), [.period, .hour, .minute])
        let arabic = FluentTimePickerPresentation(clock: .twelveHour, locale: Locale(identifier: "ar_SA"))
        XCTAssertEqual(arabic.fields(rightToLeft: false), [.period, .hour, .minute])
        XCTAssertNotEqual(arabic.number(5, digits: 2), "05")
        XCTAssertEqual(FluentTimePickerPresentation(clock: .system, locale: Locale(identifier: "en_GB")).usesTwelveHour, false)
    }
}
