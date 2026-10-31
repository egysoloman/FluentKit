import AppKit

/// Transactional looping columns shared with the closed TimePicker's locale presentation.
final class FluentTimePickerEditorView: NSView {
    private(set) var time: FluentTime
    private var minuteIncrement: Int
    private var clockIdentifier: FluentClockIdentifier
    private var locale: Locale
    private var theme: FluentTheme
    private let onChange: (FluentTime) -> Void
    var onAccept: (() -> Void)?
    var onDismiss: (() -> Void)?
    weak var followingKeyView: NSView?
    weak var lastFooterKeyView: NSView?
    private var hourValues: [Int] = []
    private var minuteValues: [Int] = []
    private let highlight = NSView()
    private let firstDivider = NSView()
    private let secondDivider = NSView()
    private let hourSelector = FluentLoopingSelectorControl()
    private let minuteSelector = FluentLoopingSelectorControl()
    private let periodSelector = FluentLoopingSelectorControl()
    private var presentation: FluentTimePickerPresentation { .init(clock: clockIdentifier, locale: locale) }
    private var orderedSelectors: [FluentLoopingSelectorControl] {
        presentation.fields(rightToLeft: userInterfaceLayoutDirection == .rightToLeft).map(selector)
    }
    init(time: FluentTime, minuteIncrement: Int, clockIdentifier: FluentClockIdentifier,
         locale: Locale, theme: FluentTheme, onChange: @escaping (FluentTime) -> Void) {
        let increment = (0...59).contains(minuteIncrement) ? minuteIncrement : 1
        self.time = time.adjusted(toMinuteIncrement: increment)
        self.minuteIncrement = increment
        self.clockIdentifier = clockIdentifier
        self.locale = locale
        self.theme = theme
        self.onChange = onChange
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.TimePicker.Editor")
        highlight.wantsLayer = true
        addSubview(highlight)
        for field in [FluentTimePickerPresentation.Field.hour, .minute, .period] {
            let control = selector(field)
            control.identifier = NSUserInterfaceItemIdentifier("FluentKit.TimePicker.\(field.rawValue)")
            control.setAccessibilityLabel(field.rawValue.capitalized)
            control.itemHeight = 40
            control.onSelectionChanged = { [weak self] _ in self?.emitPending() }
            addSubview(control)
        }
        for divider in [firstDivider, secondDivider] { divider.wantsLayer = true; addSubview(divider) }
        updateTheme(theme)
        updateItems()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: 242, height: 357) }
    private func selector(_ field: FluentTimePickerPresentation.Field) -> FluentLoopingSelectorControl {
        switch field { case .hour: return hourSelector; case .minute: return minuteSelector; case .period: return periodSelector }
    }
    func update(time: FluentTime, minuteIncrement: Int, clockIdentifier: FluentClockIdentifier,
                locale: Locale, theme: FluentTheme) {
        let increment = (0...59).contains(minuteIncrement) ? minuteIncrement : 1
        let adjusted = time.adjusted(toMinuteIncrement: increment)
        let changed = self.time != adjusted || self.minuteIncrement != increment
            || self.clockIdentifier != clockIdentifier || self.locale != locale
        self.time = adjusted
        self.minuteIncrement = increment
        self.clockIdentifier = clockIdentifier
        self.locale = locale
        if self.theme != theme { updateTheme(theme) }
        if changed { updateItems() }
    }
    private func updateItems() {
        let style = presentation
        hourValues = style.usesTwelveHour ? [12] + Array(1...11) : Array(0..<24)
        minuteValues = minuteIncrement == 0 ? [0] : Array(stride(from: 0, to: 60, by: minuteIncrement))
        let hour = style.usesTwelveHour ? (time.hour % 12 == 0 ? 12 : time.hour % 12) : time.hour
        hourSelector.setItems(hourValues.map { style.number($0) }, selection: hourValues.firstIndex(of: hour) ?? 0, looping: true)
        minuteSelector.setItems(minuteValues.map { style.number($0, digits: 2) },
            selection: minuteValues.firstIndex(of: time.minute) ?? 0, looping: minuteIncrement != 0)
        periodSelector.setItems(style.periods, selection: time.hour < 12 ? 0 : 1, looping: false)
        let periodHadFocus = window?.firstResponder === periodSelector
        periodSelector.isHidden = !style.usesTwelveHour
        secondDivider.isHidden = !style.usesTwelveHour
        if periodHadFocus, periodSelector.isHidden { window?.makeFirstResponder(hourSelector) }
        setAccessibilityChildren(orderedSelectors)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let ordered = orderedSelectors
        let count = CGFloat(ordered.count)
        let dividerWidth = min(2, max(0, bounds.width / max(1, count - 1)))
        let width = max(0, (bounds.width - (count - 1) * dividerWidth) / count)
        highlight.frame = NSRect(x: min(4, bounds.width / 2), y: max(0, bounds.midY - 20),
            width: max(0, bounds.width - 8), height: min(40, bounds.height))
        highlight.layer?.cornerRadius = theme.buttonCornerRadius
        for (index, control) in ordered.enumerated() {
            control.frame = NSRect(x: CGFloat(index) * (width + dividerWidth), y: 0, width: width, height: max(0, bounds.height))
            control.nextKeyView = index + 1 < ordered.count ? ordered[index + 1] : followingKeyView
        }
        firstDivider.frame = NSRect(x: width, y: 0, width: dividerWidth, height: max(0, bounds.height))
        secondDivider.frame = NSRect(x: width * 2 + dividerWidth, y: 0, width: dividerWidth, height: max(0, bounds.height))
        lastFooterKeyView?.nextKeyView = ordered.first
        setAccessibilityChildren(ordered)
    }
    func focusFirstSelector() { window?.makeFirstResponder(orderedSelectors.first) }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 36: onAccept?()
        case 53: onDismiss?()
        case 123, 124:
            let selectors = orderedSelectors
            if let index = selectors.firstIndex(where: { window?.firstResponder === $0 }) {
                let next = index + (event.keyCode == 124 ? 1 : -1)
                if selectors.indices.contains(next) { window?.makeFirstResponder(selectors[next]) }
            }
        default: super.keyDown(with: event)
        }
    }
    func updateTheme(_ theme: FluentTheme) {
        self.theme = theme
        highlight.layer?.backgroundColor = theme.loopingSelectorItemSelectedBackground.cgColor
        for divider in [firstDivider, secondDivider] { divider.layer?.backgroundColor = theme.divider.cgColor }
        for control in [hourSelector, minuteSelector, periodSelector] {
            control.theme = theme
            control.foreground = theme.loopingSelectorItemForeground
            control.selectedForeground = theme.loopingSelectorItemSelectedForeground
            control.secondaryForeground = theme.textSecondary
        }
        needsDisplay = true
    }
    private func emitPending() {
        let hourOption = hourValues[hourSelector.selectedIndex]
        let hour = presentation.usesTwelveHour ? (hourOption % 12) + (periodSelector.selectedIndex == 1 ? 12 : 0) : hourOption
        time = FluentTime(hour: hour, minute: minuteValues[minuteSelector.selectedIndex])
        onChange(time)
    }
}
