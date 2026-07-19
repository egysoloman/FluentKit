import AppKit

/// A date input backed by NSDatePicker with a Fluent surface and two-way binding.
public struct FluentDatePickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<Date>?
    fileprivate let date: Date
    fileprivate let minDate: Date?
    fileprivate let maxDate: Date?
    fileprivate let style: any FluentTextFieldStyle

    public init(
        selection: FluentBinding<Date>? = nil,
        date: Date = Date(),
        range: ClosedRange<Date>? = nil,
        style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()
    ) {
        self.binding = selection
        self.date = date
        minDate = range?.lowerBound
        maxDate = range?.upperBound
        self.style = style
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let picker = FluentDatePickerNative(
            date: binding?.get() ?? date,
            binding: binding,
            minDate: minDate,
            maxDate: maxDate,
            style: style
        )
        picker.theme = context.theme
        picker.fluentStyle = style
        return picker
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let picker = view as? FluentDatePickerNative else { return false }
        picker.theme = context.theme
        picker.fluentStyle = style
        picker.update(binding: binding, date: date, minDate: minDate, maxDate: maxDate, style: style)
        return true
    }

    public func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentDatePickerView {
        FluentDatePickerView(selection: binding, date: date, range: minDate.map { $0 ... (maxDate ?? $0) }, style: style)
    }
}

private final class FluentDatePickerNative: NSDatePicker, FluentControlSizeConfigurable {
    var theme: FluentTheme = .current { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var fluentStyle: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle() { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var fluentControlSize: FluentControlSize = .regular { didSet { applyTheme() } }
    private var binding: FluentBinding<Date>?
    private var observedBinding: FluentBinding<Date>?
    private var observerID: UUID?
    private var isApplyingBinding = false

    init(date: Date, binding: FluentBinding<Date>?, minDate: Date?, maxDate: Date?, style: any FluentTextFieldStyle) {
        self.binding = binding
        super.init(frame: .zero)
        datePickerStyle = .textFieldAndStepper
        datePickerElements = [.yearMonthDay]
        drawsBackground = false
        isBordered = false
        focusRingType = .none
        dateValue = date
        self.minDate = minDate
        self.maxDate = maxDate
        fluentStyle = style
        target = self
        action = #selector(valueChanged)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Date")
        installObserver()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220 * theme.density.metricScale, height: theme.controlHeight(for: fluentControlSize))
    }

    deinit {
        if let observerID { observedBinding?.removeObserver?(observerID) }
    }

    func update(binding: FluentBinding<Date>?, date: Date, minDate: Date?, maxDate: Date?, style: any FluentTextFieldStyle) {
        self.binding = binding
        self.minDate = minDate
        self.maxDate = maxDate
        self.fluentStyle = style
        let requested = binding?.get() ?? date
        if dateValue != requested {
            isApplyingBinding = true
            dateValue = requested
            isApplyingBinding = false
        }
        installObserver()
        applyTheme()
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observedBinding = binding
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isApplyingBinding, self.dateValue != value else { return }
                self.isApplyingBinding = true
                self.dateValue = value
                self.isApplyingBinding = false
            }
        }
    }

    @objc private func valueChanged() {
        guard !isApplyingBinding, let binding else { return }
        binding.set(dateValue)
        setAccessibilityValue(dateValue as NSDate)
    }

    private func applyTheme() {
        let appearance = fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: isEnabled,
                isFocused: window?.firstResponder === self,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        controlSize = fluentControlSize.appKitSize
        font = appearance.font ?? theme.typography.font(for: .body).withSize(theme.typography.font(for: .body).pointSize * fluentControlSize.metricScale)
        textColor = appearance.textColor
        invalidateIntrinsicContentSize()
        setAccessibilityValue(dateValue as NSDate)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: isEnabled,
                isFocused: window?.firstResponder === self,
                controlSize: fluentControlSize,
                theme: theme
            )
        )
        appearance.backgroundColor.setFill()
        bounds.fill()
        appearance.borderColor.setStroke()
        switch appearance.borderShape {
        case .rounded:
            let rect = bounds.insetBy(dx: appearance.borderWidth / 2, dy: appearance.borderWidth / 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: appearance.cornerRadius, yRadius: appearance.cornerRadius)
            appearance.backgroundColor.setFill()
            path.fill()
            if appearance.borderWidth > 0 {
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        case .underline:
            if appearance.borderWidth > 0 {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.minX, y: appearance.borderWidth / 2))
                path.line(to: NSPoint(x: bounds.maxX, y: appearance.borderWidth / 2))
                path.lineWidth = appearance.borderWidth
                path.stroke()
            }
        }
        super.draw(dirtyRect)
    }
}

public func FluentDatePicker(
    selection: FluentBinding<Date>? = nil,
    date: Date = Date(),
    range: ClosedRange<Date>? = nil,
    style: any FluentTextFieldStyle = FluentAutomaticTextFieldStyle()
) -> FluentDatePickerView {
    FluentDatePickerView(selection: selection, date: date, range: range, style: style)
}

/// A native color well with a Fluent binding and accessibility metadata.
public struct FluentColorPickerView: FluentUpdatablePrimitiveView {
    fileprivate let binding: FluentBinding<NSColor>?
    fileprivate let color: NSColor
    fileprivate let label: String

    public init(
        selection: FluentBinding<NSColor>? = nil,
        color: NSColor = .systemBlue,
        label: String = "Color"
    ) {
        self.binding = selection
        self.color = color
        self.label = label
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let well = FluentColorWellNative(color: binding?.get() ?? color, binding: binding, label: label)
        well.theme = context.theme
        return well
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let well = view as? FluentColorWellNative else { return false }
        well.theme = context.theme
        well.update(binding: binding, color: color, label: label)
        return true
    }
}

private final class FluentColorWellNative: NSColorWell {
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    private var binding: FluentBinding<NSColor>?
    private var observedBinding: FluentBinding<NSColor>?
    private var observerID: UUID?
    private var isApplyingBinding = false

    init(color: NSColor, binding: FluentBinding<NSColor>?, label: String) {
        self.binding = binding
        super.init(frame: .zero)
        self.color = color
        isBordered = false
        setAccessibilityRole(.colorWell)
        setAccessibilityLabel(label)
        target = self
        action = #selector(valueChanged)
        installObserver()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observerID { observedBinding?.removeObserver?(observerID) }
    }

    func update(binding: FluentBinding<NSColor>?, color: NSColor, label: String) {
        self.binding = binding
        setAccessibilityLabel(label)
        let requested = binding?.get() ?? color
        if self.color != requested {
            isApplyingBinding = true
            self.color = requested
            isApplyingBinding = false
        }
        installObserver()
        applyTheme()
    }

    private func installObserver() {
        if let observerID { observedBinding?.removeObserver?(observerID) }
        observedBinding = binding
        observerID = binding?.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isApplyingBinding, self.color != value else { return }
                self.isApplyingBinding = true
                self.color = value
                self.isApplyingBinding = false
            }
        }
    }

    @objc private func valueChanged() {
        guard !isApplyingBinding, let binding else { return }
        binding.set(color)
        setAccessibilityValue(color)
    }

    private func applyTheme() {
        setAccessibilityValue(color)
        needsDisplay = true
    }
}

public func FluentColorPicker(
    selection: FluentBinding<NSColor>? = nil,
    color: NSColor = .systemBlue,
    label: String = "Color"
) -> FluentColorPickerView {
    FluentColorPickerView(selection: selection, color: color, label: label)
}
