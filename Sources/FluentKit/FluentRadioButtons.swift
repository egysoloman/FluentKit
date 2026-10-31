import AppKit

/// A WinUI-compatible single-selection group. Unlike several independent `FluentRadioButtonView`
/// values, the group owns one optional selection and updates its children atomically.
public struct FluentRadioButtons<Option: Hashable>: FluentUpdatablePrimitiveView {
    private let options: [Option]
    private let selection: FluentBinding<Option?>
    private let header: String?
    private let maxColumns: Int
    private let isGroupEnabled: Bool
    private let title: (Option) -> String
    private let isOptionEnabled: (Option) -> Bool
    private let onSelectionChanged: ((Option?, Option?) -> Void)?

    public init(
        _ options: [Option],
        selection: FluentBinding<Option?>,
        header: String? = nil,
        maxColumns: Int = 1,
        isGroupEnabled: Bool = true,
        isEnabled: @escaping (Option) -> Bool = { _ in true },
        onSelectionChanged: ((Option?, Option?) -> Void)? = nil,
        title: @escaping (Option) -> String = { String(describing: $0) }
    ) {
        precondition(Set(options).count == options.count, "Fluent radio-button options must be unique")
        self.options = options
        self.selection = selection
        self.header = header
        self.maxColumns = max(1, maxColumns)
        self.isGroupEnabled = isGroupEnabled
        isOptionEnabled = isEnabled
        self.onSelectionChanged = onSelectionChanged
        self.title = title
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentRadioButtonsHost(
            options: options,
            selection: selection,
            header: header,
            maxColumns: maxColumns,
            isGroupEnabled: isGroupEnabled,
            title: title,
            isOptionEnabled: isOptionEnabled,
            onSelectionChanged: onSelectionChanged,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentRadioButtonsHost<Option> else { return false }
        host.update(
            options: options,
            selection: selection,
            header: header,
            maxColumns: maxColumns,
            isGroupEnabled: isGroupEnabled,
            title: title,
            isOptionEnabled: isOptionEnabled,
            onSelectionChanged: onSelectionChanged,
            context: context
        )
        return true
    }
}

private enum FluentRadioButtonsMetrics {
    static let columnSpacing: CGFloat = 7
    static let rowSpacing: CGFloat = 8
    static let headerBottomSpacing: CGFloat = 8
}

private final class FluentRadioButtonsHost<Option: Hashable>: NSControl,
    FluentFillWidthProviding,
    FluentRadioButtonGrouping
{
    private var options: [Option]
    private var selection: FluentBinding<Option?>
    private var header: String?
    private var maxColumns: Int
    private var title: (Option) -> String
    private var isOptionEnabled: (Option) -> Bool
    private var onSelectionChanged: ((Option?, Option?) -> Void)?
    private var context: FluentRenderContext
    private var radioButtons: [FluentRadioButton] = []
    private let headerLabel = NSTextField(labelWithString: "")
    private var observedSelection: FluentBinding<Option?>?
    private var selectionObserverID: UUID?
    private var selectionSubscriptionGeneration: UInt = 0
    private var isPublishingSelection = false
    private var appliedSelection: Option?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { radioButtons.contains(where: \.isEnabled) }
    override var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            setAccessibilityEnabled(isEnabled)
            configureHeader()
            updateButtons()
        }
    }

    init(
        options: [Option],
        selection: FluentBinding<Option?>,
        header: String?,
        maxColumns: Int,
        isGroupEnabled: Bool,
        title: @escaping (Option) -> String,
        isOptionEnabled: @escaping (Option) -> Bool,
        onSelectionChanged: ((Option?, Option?) -> Void)?,
        context: FluentRenderContext
    ) {
        self.options = options
        self.selection = selection
        self.header = header
        self.maxColumns = max(1, maxColumns)
        self.title = title
        self.isOptionEnabled = isOptionEnabled
        self.onSelectionChanged = onSelectionChanged
        self.context = context
        appliedSelection = selection.get()
        super.init(frame: .zero)
        isEnabled = isGroupEnabled
        identifier = NSUserInterfaceItemIdentifier("FluentKit.RadioButtons.Host")
        setAccessibilityRole(.radioGroup)
        setAccessibilityElement(true)
        setAccessibilityEnabled(isGroupEnabled)
        addSubview(headerLabel)
        configureHeader()
        rebuildButtons()
        installSelectionObserver()
        applySelection(appliedSelection)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeSelectionObserver() }

    override var intrinsicContentSize: NSSize {
        let layout = measureLayout(availableWidth: nil)
        return NSSize(width: layout.width, height: layout.height)
    }

    override func layout() {
        super.layout()
        let layout = measureLayout(availableWidth: max(bounds.width, 0))
        apply(layout: layout)
    }

    override func becomeFirstResponder() -> Bool {
        let target = radioButtons.first(where: { $0.isSelected && $0.isEnabled })
            ?? radioButtons.first(where: \.isEnabled)
        guard let target else { return false }
        return window?.makeFirstResponder(target) ?? false
    }

    func update(
        options: [Option],
        selection: FluentBinding<Option?>,
        header: String?,
        maxColumns: Int,
        isGroupEnabled: Bool,
        title: @escaping (Option) -> String,
        isOptionEnabled: @escaping (Option) -> Bool,
        onSelectionChanged: ((Option?, Option?) -> Void)?,
        context: FluentRenderContext
    ) {
        let optionsChanged = self.options != options
        let observationChanged = self.selection.observationIdentity != selection.observationIdentity
        if observationChanged { removeSelectionObserver() }
        self.options = options
        self.selection = selection
        self.header = header
        self.maxColumns = max(1, maxColumns)
        isEnabled = isGroupEnabled
        self.title = title
        self.isOptionEnabled = isOptionEnabled
        self.onSelectionChanged = onSelectionChanged
        self.context = context
        configureHeader()
        if optionsChanged { rebuildButtons() } else { updateButtons() }
        if observationChanged { installSelectionObserver() }
        receiveSelection(selection.get(), notify: false)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func radioButtonRequestedSelection(_ radioButton: FluentRadioButton) {
        guard isEnabled,
              let index = radioButtons.firstIndex(where: { $0 === radioButton }),
              options.indices.contains(index),
              isOptionEnabled(options[index]) else { return }
        publishSelection(options[index])
    }

    func radioButton(
        _ radioButton: FluentRadioButton,
        handleNavigationKey keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard let currentIndex = radioButtons.firstIndex(where: { $0 === radioButton }) else {
            return false
        }
        let enabledIndices = radioButtons.indices.filter { radioButtons[$0].isEnabled }
        guard enabledIndices.count > 1 else { return true }

        let targetIndex: Int?
        switch keyCode {
        case 126:
            targetIndex = enabledIndices.last(where: { $0 < currentIndex })
        case 125:
            targetIndex = enabledIndices.first(where: { $0 > currentIndex })
        case 123, 124:
            let current = radioButtons[currentIndex].frameCenter
            let wantsLeft = keyCode == 123
            targetIndex = enabledIndices
                .filter { index in
                    let delta = radioButtons[index].frameCenter.x - current.x
                    return index != currentIndex && (wantsLeft ? delta < -0.5 : delta > 0.5)
                }
                .min { lhs, rhs in
                    let left = radioButtons[lhs].frameCenter
                    let right = radioButtons[rhs].frameCenter
                    return hypot(left.x - current.x, left.y - current.y)
                        < hypot(right.x - current.x, right.y - current.y)
                }
        default:
            return false
        }

        if let targetIndex {
            let target = radioButtons[targetIndex]
            _ = window?.makeFirstResponder(target)
            if !modifiers.contains(.control) { publishSelection(options[targetIndex]) }
        }
        // WinUI keeps arrow navigation inside the group at its boundaries.
        return true
    }

    private func configureHeader() {
        headerLabel.stringValue = header ?? ""
        headerLabel.font = context.theme.typography.font(for: .body)
        headerLabel.textColor = isEnabled ? context.theme.textPrimary : context.theme.textDisabled
        headerLabel.isHidden = header?.isEmpty != false
        headerLabel.setAccessibilityElement(false)
        setAccessibilityLabel(header?.isEmpty == false ? header : nil)
    }

    private func rebuildButtons() {
        radioButtons.forEach { $0.removeFromSuperview() }
        radioButtons = options.map { option in
            let radio = FluentRadioButton(title: title(option), isSelected: false)
            radio.groupingCoordinator = self
            addSubview(radio)
            return radio
        }
        updateButtons()
        setAccessibilityChildren(radioButtons)
    }

    private func updateButtons() {
        for (index, radio) in radioButtons.enumerated() where options.indices.contains(index) {
            let option = options[index]
            radio.title = title(option)
            radio.theme = context.theme
            radio.reduceMotion = context.reduceMotion
            radio.fluentLayoutDirection = context.layoutDirection
            radio.isEnabled = isEnabled && isOptionEnabled(option)
            radio.setAccessibilityHelp("Option \(index + 1) of \(options.count)")
        }
    }

    private func publishSelection(_ newSelection: Option?) {
        let oldSelection = appliedSelection
        guard oldSelection != newSelection else { return }
        isPublishingSelection = true
        appliedSelection = newSelection
        applySelection(newSelection)
        selection.set(newSelection)
        isPublishingSelection = false
        onSelectionChanged?(oldSelection, newSelection)
    }

    private func receiveSelection(_ value: Option?, notify: Bool) {
        guard !isPublishingSelection else { return }
        let normalized = value.flatMap { options.contains($0) ? $0 : nil }
        let oldSelection = appliedSelection
        appliedSelection = normalized
        applySelection(normalized)
        if notify, oldSelection != normalized { onSelectionChanged?(oldSelection, normalized) }
    }

    private func applySelection(_ value: Option?) {
        for (index, radio) in radioButtons.enumerated() where options.indices.contains(index) {
            radio.setStateFromBinding(options[index] == value)
        }
    }

    private func installSelectionObserver() {
        selectionSubscriptionGeneration &+= 1
        let generation = selectionSubscriptionGeneration
        observedSelection = selection
        selectionObserverID = selection.observe? { [weak self] value in
            let apply = { [weak self] in
                guard let self, generation == self.selectionSubscriptionGeneration else { return }
                self.receiveSelection(value, notify: true)
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func removeSelectionObserver() {
        selectionSubscriptionGeneration &+= 1
        if let selectionObserverID { observedSelection?.removeObserver?(selectionObserverID) }
        selectionObserverID = nil
        observedSelection = nil
    }

    private struct Layout {
        let columns: Int
        let rows: Int
        let columnWidth: CGFloat
        let itemCountsPerColumn: [Int]
        let rowHeight: CGFloat
        let headerHeight: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private func measureLayout(availableWidth: CGFloat?) -> Layout {
        let count = radioButtons.count
        let headerHeight = headerLabel.isHidden ? 0 : ceil(headerLabel.intrinsicContentSize.height)
        let headerSpacing = headerLabel.isHidden ? 0 : FluentRadioButtonsMetrics.headerBottomSpacing
        guard count > 0 else {
            let width = headerLabel.isHidden ? 0 : ceil(headerLabel.intrinsicContentSize.width)
            return Layout(columns: 0, rows: 0, columnWidth: 0, itemCountsPerColumn: [], rowHeight: 0,
                          headerHeight: headerHeight, width: width, height: headerHeight)
        }
        let columnWidth = ceil(radioButtons.map(\.intrinsicContentSize.width).max() ?? 0)
        let rowHeight = ceil(radioButtons.map(\.intrinsicContentSize.height).max() ?? 32)
        let requestedColumns = min(maxColumns, count)
        let columns: Int
        if let availableWidth {
            let extraWidth = max(0, availableWidth - columnWidth)
            let pitch = columnWidth + FluentRadioButtonsMetrics.columnSpacing
            let extraColumns = pitch > 0 ? Int(floor(extraWidth / pitch)) : requestedColumns - 1
            columns = max(1, min(requestedColumns, extraColumns + 1))
        } else {
            columns = requestedColumns
        }
        let minimumPerColumn = count / columns
        let columnsWithExtraItem = count % columns
        let counts = (0..<columns).map { $0 < columnsWithExtraItem ? minimumPerColumn + 1 : minimumPerColumn }
        let rows = counts.max() ?? 0
        let contentWidth = CGFloat(columns) * columnWidth
            + CGFloat(max(0, columns - 1)) * FluentRadioButtonsMetrics.columnSpacing
        let width = max(contentWidth, headerLabel.isHidden ? 0 : ceil(headerLabel.intrinsicContentSize.width))
        let contentHeight = CGFloat(rows) * rowHeight
            + CGFloat(max(0, rows - 1)) * FluentRadioButtonsMetrics.rowSpacing
        return Layout(
            columns: columns,
            rows: rows,
            columnWidth: columnWidth,
            itemCountsPerColumn: counts,
            rowHeight: rowHeight,
            headerHeight: headerHeight,
            width: width,
            height: headerHeight + headerSpacing + contentHeight
        )
    }

    private func apply(layout: Layout) {
        let headerSpacing = headerLabel.isHidden ? 0 : FluentRadioButtonsMetrics.headerBottomSpacing
        headerLabel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: layout.headerHeight)
        guard layout.columns > 0 else { return }
        let contentTop = layout.headerHeight + headerSpacing
        var itemIndex = 0
        for column in 0..<layout.columns {
            let logicalX = CGFloat(column) * (layout.columnWidth + FluentRadioButtonsMetrics.columnSpacing)
            let resolvedX = userInterfaceLayoutDirection == .rightToLeft
                ? bounds.width - logicalX - layout.columnWidth
                : logicalX
            for row in 0..<layout.itemCountsPerColumn[column] where radioButtons.indices.contains(itemIndex) {
                let button = radioButtons[itemIndex]
                let desired = button.intrinsicContentSize
                button.frame = NSRect(
                    x: resolvedX,
                    y: contentTop + CGFloat(row) * (layout.rowHeight + FluentRadioButtonsMetrics.rowSpacing),
                    width: desired.width,
                    height: desired.height
                )
                itemIndex += 1
            }
        }
    }
}

private extension NSView {
    var frameCenter: NSPoint { NSPoint(x: frame.midX, y: frame.midY) }
}
