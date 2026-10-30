import AppKit

public enum FluentInfoBarCloseReason: Hashable, Sendable {
    case closeButton
    case programmatic
}

public enum FluentInfoBarSeverity: Hashable, Sendable {
    case informational
    case success
    case warning
    case error
}

public final class FluentInfoBarClosingEventArgs {
    public let reason: FluentInfoBarCloseReason
    public var cancel = false

    init(reason: FluentInfoBarCloseReason) {
        self.reason = reason
    }
}

/// WinUI-style inline status notification. The action and custom-content regions remain native
/// Fluent views, while the host mirrors InfoBar's adaptive horizontal/vertical panel layout.
public struct FluentInfoBarView<Action: FluentView, Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let isOpen: FluentBinding<Bool>
    fileprivate let title: String
    fileprivate let message: String
    fileprivate let severity: FluentInfoBarSeverity
    fileprivate let isIconVisible: Bool
    fileprivate let systemImageName: String?
    fileprivate let isClosable: Bool
    fileprivate let action: Action
    fileprivate let content: Content
    fileprivate let hasAction: Bool
    fileprivate let hasContent: Bool
    fileprivate let onCloseButtonClick: (() -> Void)?
    fileprivate let onClosing: ((FluentInfoBarClosingEventArgs) -> Void)?
    fileprivate let onClosed: ((FluentInfoBarCloseReason) -> Void)?
    fileprivate let onOpened: (() -> Void)?

    public init(
        isOpen: FluentBinding<Bool>,
        title: String = "",
        message: String = "",
        severity: FluentInfoBarSeverity = .informational,
        isIconVisible: Bool = true,
        systemImageName: String? = nil,
        isClosable: Bool = true,
        onCloseButtonClick: (() -> Void)? = nil,
        onClosing: ((FluentInfoBarClosingEventArgs) -> Void)? = nil,
        onClosed: ((FluentInfoBarCloseReason) -> Void)? = nil,
        onOpened: (() -> Void)? = nil,
        @FluentViewBuilder action: () -> Action,
        @FluentViewBuilder content: () -> Content
    ) {
        self.isOpen = isOpen
        self.title = title
        self.message = message
        self.severity = severity
        self.isIconVisible = isIconVisible
        self.systemImageName = systemImageName
        self.isClosable = isClosable
        self.onCloseButtonClick = onCloseButtonClick
        self.onClosing = onClosing
        self.onClosed = onClosed
        self.onOpened = onOpened
        self.action = action()
        self.content = content()
        hasAction = !(Action.self == FluentEmptyView.self)
        hasContent = !(Content.self == FluentEmptyView.self)
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let actionView = action._mount(in: context)
        let contentView = content._mount(in: context)
        let host = FluentInfoBarHost(
            isOpen: isOpen,
            title: title,
            message: message,
            severity: severity,
            isIconVisible: isIconVisible,
            systemImageName: systemImageName,
            isClosable: isClosable,
            actionView: actionView,
            hasAction: hasAction,
            contentView: contentView,
            hasContent: hasContent,
            onCloseButtonClick: onCloseButtonClick,
            onClosing: onClosing,
            onClosed: onClosed,
            onOpened: onOpened,
            context: context
        )
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentInfoBarHost,
              action._update(host.actionView, in: context),
              content._update(host.contentView, in: context) else { return false }
        host.update(
            isOpen: isOpen,
            title: title,
            message: message,
            severity: severity,
            isIconVisible: isIconVisible,
            systemImageName: systemImageName,
            isClosable: isClosable,
            hasAction: hasAction,
            hasContent: hasContent,
            onCloseButtonClick: onCloseButtonClick,
            onClosing: onClosing,
            onClosed: onClosed,
            onOpened: onOpened,
            context: context
        )
        return true
    }
}

public func FluentInfoBar(
    isOpen: FluentBinding<Bool>,
    title: String = "",
    message: String = "",
    severity: FluentInfoBarSeverity = .informational,
    isIconVisible: Bool = true,
    systemImageName: String? = nil,
    isClosable: Bool = true,
    onCloseButtonClick: (() -> Void)? = nil,
    onClosing: ((FluentInfoBarClosingEventArgs) -> Void)? = nil,
    onClosed: ((FluentInfoBarCloseReason) -> Void)? = nil,
    onOpened: (() -> Void)? = nil
) -> FluentInfoBarView<FluentEmptyView, FluentEmptyView> {
    FluentInfoBarView(
        isOpen: isOpen,
        title: title,
        message: message,
        severity: severity,
        isIconVisible: isIconVisible,
        systemImageName: systemImageName,
        isClosable: isClosable,
        onCloseButtonClick: onCloseButtonClick,
        onClosing: onClosing,
        onClosed: onClosed,
        onOpened: onOpened,
        action: { FluentEmptyView() },
        content: { FluentEmptyView() }
    )
}

public func FluentInfoBar<Action: FluentView>(
    isOpen: FluentBinding<Bool>,
    title: String = "",
    message: String = "",
    severity: FluentInfoBarSeverity = .informational,
    isIconVisible: Bool = true,
    systemImageName: String? = nil,
    isClosable: Bool = true,
    onCloseButtonClick: (() -> Void)? = nil,
    onClosing: ((FluentInfoBarClosingEventArgs) -> Void)? = nil,
    onClosed: ((FluentInfoBarCloseReason) -> Void)? = nil,
    onOpened: (() -> Void)? = nil,
    @FluentViewBuilder action: () -> Action
) -> FluentInfoBarView<Action, FluentEmptyView> {
    FluentInfoBarView(
        isOpen: isOpen,
        title: title,
        message: message,
        severity: severity,
        isIconVisible: isIconVisible,
        systemImageName: systemImageName,
        isClosable: isClosable,
        onCloseButtonClick: onCloseButtonClick,
        onClosing: onClosing,
        onClosed: onClosed,
        onOpened: onOpened,
        action: action,
        content: { FluentEmptyView() }
    )
}

public func FluentInfoBar<Action: FluentView, Content: FluentView>(
    isOpen: FluentBinding<Bool>,
    title: String = "",
    message: String = "",
    severity: FluentInfoBarSeverity = .informational,
    isIconVisible: Bool = true,
    systemImageName: String? = nil,
    isClosable: Bool = true,
    onCloseButtonClick: (() -> Void)? = nil,
    onClosing: ((FluentInfoBarClosingEventArgs) -> Void)? = nil,
    onClosed: ((FluentInfoBarCloseReason) -> Void)? = nil,
    onOpened: (() -> Void)? = nil,
    @FluentViewBuilder action: () -> Action,
    @FluentViewBuilder content: () -> Content
) -> FluentInfoBarView<Action, Content> {
    FluentInfoBarView(
        isOpen: isOpen,
        title: title,
        message: message,
        severity: severity,
        isIconVisible: isIconVisible,
        systemImageName: systemImageName,
        isClosable: isClosable,
        onCloseButtonClick: onCloseButtonClick,
        onClosing: onClosing,
        onClosed: onClosed,
        onOpened: onOpened,
        action: action,
        content: content
    )
}

private final class FluentInfoBarHost: NSView, FluentFillWidthProviding {
    private enum Metrics {
        static let minimumHeight: CGFloat = 48
        static let leadingPadding: CGFloat = 16
        static let iconSize: CGFloat = 16
        static let iconTop: CGFloat = 16
        static let iconTrailing: CGFloat = 14
        static let panelTrailing: CGFloat = 16
        static let closeSize: CGFloat = 38
        static let closeMargin: CGFloat = 5
        static let horizontalMessageSpacing: CGFloat = 12
        static let horizontalActionSpacing: CGFloat = 16
        static let horizontalTextTop: CGFloat = 14
        static let horizontalActionTop: CGFloat = 8
        static let verticalTop: CGFloat = 14
        static let verticalMessageSpacing: CGFloat = 4
        static let verticalActionSpacing: CGFloat = 12
        static let verticalBottom: CGFloat = 18
    }

    private struct LayoutResult {
        var titleFrame = NSRect.zero
        var messageFrame = NSRect.zero
        var actionFrame = NSRect.zero
        var contentFrame = NSRect.zero
        var iconFrame = NSRect.zero
        var closeFrame = NSRect.zero
        var height: CGFloat = 0
        var isVertical = false
    }

    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let standardIcon = FluentInfoBarSeverityIconView()
    private let customIcon = NSImageView()
    private let closeButton = FluentInfoBarCloseButton()
    private let actionPresenter = NSView()
    private(set) var actionView: NSView
    private(set) var contentView: NSView
    private var binding: FluentBinding<Bool>
    private var observedBinding: FluentBinding<Bool>?
    private var bindingObserverID: UUID?
    private var context: FluentRenderContext
    private var title: String
    private var message: String
    private var severity: FluentInfoBarSeverity
    private var isIconVisible: Bool
    private var systemImageName: String?
    private var isClosable: Bool
    private var hasAction: Bool
    private var hasContent: Bool
    private var currentIsOpen: Bool
    private var isWritingBinding = false
    private var onCloseButtonClick: (() -> Void)?
    private var onClosing: ((FluentInfoBarClosingEventArgs) -> Void)?
    private var onClosed: ((FluentInfoBarCloseReason) -> Void)?
    private var onOpened: (() -> Void)?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        guard currentIsOpen else { return NSSize(width: 360, height: 0) }
        let width = bounds.width > 1 ? bounds.width : 560
        return NSSize(width: 360, height: measuredLayout(for: width).height)
    }

    init(
        isOpen: FluentBinding<Bool>,
        title: String,
        message: String,
        severity: FluentInfoBarSeverity,
        isIconVisible: Bool,
        systemImageName: String?,
        isClosable: Bool,
        actionView: NSView,
        hasAction: Bool,
        contentView: NSView,
        hasContent: Bool,
        onCloseButtonClick: (() -> Void)?,
        onClosing: ((FluentInfoBarClosingEventArgs) -> Void)?,
        onClosed: ((FluentInfoBarCloseReason) -> Void)?,
        onOpened: (() -> Void)?,
        context: FluentRenderContext
    ) {
        binding = isOpen
        self.title = title
        self.message = message
        self.severity = severity
        self.isIconVisible = isIconVisible
        self.systemImageName = systemImageName
        self.isClosable = isClosable
        self.actionView = actionView
        self.hasAction = hasAction
        self.contentView = contentView
        self.hasContent = hasContent
        self.onCloseButtonClick = onCloseButtonClick
        self.onClosing = onClosing
        self.onClosed = onClosed
        self.onOpened = onOpened
        self.context = context
        currentIsOpen = isOpen.get()
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar")
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = context.theme.designTokens.controlCornerRadius
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription("status")

        titleLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar.Title")
        messageLabel.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar.Message")
        standardIcon.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar.StandardIcon")
        customIcon.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar.CustomIcon")
        closeButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar.CloseButton")
        actionPresenter.identifier = NSUserInterfaceItemIdentifier("FluentKit.InfoBar.ActionPresenter")
        actionView.identifier = actionView.identifier ?? NSUserInterfaceItemIdentifier("FluentKit.InfoBar.Action")
        contentView.identifier = contentView.identifier ?? NSUserInterfaceItemIdentifier("FluentKit.InfoBar.Content")

        [titleLabel, messageLabel, standardIcon, customIcon, actionPresenter, contentView, closeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            addSubview($0)
        }
        actionView.translatesAutoresizingMaskIntoConstraints = true
        actionPresenter.addSubview(actionView)
        customIcon.imageScaling = .scaleProportionallyDown
        customIcon.setAccessibilityElement(false)
        standardIcon.setAccessibilityElement(false)
        titleLabel.setAccessibilityElement(false)
        messageLabel.setAccessibilityElement(false)
        closeButton.onInvoke = { [weak self] in self?.closeFromButton() }

        configureLabels()
        installBindingObserver()
        refreshAppearance()
        applyOpenState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let bindingObserverID { observedBinding?.removeObserver(bindingObserverID) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        guard currentIsOpen else { return }
        let result = measuredLayout(for: bounds.width)
        titleLabel.frame = mirrored(result.titleFrame)
        messageLabel.frame = mirrored(result.messageFrame)
        actionPresenter.frame = mirrored(result.actionFrame)
        let actionSize = measuredView(actionView, width: actionPresenter.bounds.width)
        actionView.frame = NSRect(
            x: userInterfaceLayoutDirection == .rightToLeft
                ? max(actionPresenter.bounds.width - actionSize.width, 0)
                : 0,
            y: 0,
            width: min(actionSize.width, actionPresenter.bounds.width),
            height: min(actionSize.height, actionPresenter.bounds.height)
        )
        contentView.frame = mirrored(result.contentFrame)
        standardIcon.frame = mirrored(result.iconFrame)
        customIcon.frame = mirrored(result.iconFrame)
        closeButton.frame = mirrored(result.closeFrame)
        titleLabel.preferredMaxLayoutWidth = result.titleFrame.width
        messageLabel.preferredMaxLayoutWidth = result.messageFrame.width
        actionView.layoutSubtreeIfNeeded()
        contentView.layoutSubtreeIfNeeded()
    }

    func update(
        isOpen: FluentBinding<Bool>,
        title: String,
        message: String,
        severity: FluentInfoBarSeverity,
        isIconVisible: Bool,
        systemImageName: String?,
        isClosable: Bool,
        hasAction: Bool,
        hasContent: Bool,
        onCloseButtonClick: (() -> Void)?,
        onClosing: ((FluentInfoBarClosingEventArgs) -> Void)?,
        onClosed: ((FluentInfoBarCloseReason) -> Void)?,
        onOpened: (() -> Void)?,
        context: FluentRenderContext
    ) {
        binding = isOpen
        self.title = title
        self.message = message
        self.severity = severity
        self.isIconVisible = isIconVisible
        self.systemImageName = systemImageName
        self.isClosable = isClosable
        self.hasAction = hasAction
        self.hasContent = hasContent
        self.onCloseButtonClick = onCloseButtonClick
        self.onClosing = onClosing
        self.onClosed = onClosed
        self.onOpened = onOpened
        self.context = context
        installBindingObserver()
        configureLabels()
        refreshAppearance()
        if isOpen.get() != currentIsOpen {
            transition(to: isOpen.get(), reason: .programmatic, writesBinding: false)
        } else {
            applyOpenState()
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func configureLabels() {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        titleLabel.font = .systemFont(ofSize: 14 * context.theme.typography.scale, weight: .semibold)
        messageLabel.font = .systemFont(ofSize: 14 * context.theme.typography.scale, weight: .regular)
        titleLabel.textColor = context.theme.textPrimary
        messageLabel.textColor = context.theme.textPrimary
        titleLabel.maximumNumberOfLines = 0
        messageLabel.maximumNumberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        messageLabel.lineBreakMode = .byWordWrapping
        titleLabel.isHidden = title.isEmpty
        messageLabel.isHidden = message.isEmpty
    }

    private func refreshAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = context.theme.infoBarBackground(for: severity).cgColor
        layer?.borderColor = context.theme.cardStroke.cgColor
        layer?.borderWidth = context.theme.isHighContrast ? 2 : 1
        layer?.cornerRadius = context.theme.designTokens.controlCornerRadius
        CATransaction.commit()
        standardIcon.severity = severity
        standardIcon.theme = context.theme
        closeButton.theme = context.theme
        customIcon.contentTintColor = context.theme.infoBarIconFill(for: severity)
        if let systemImageName {
            customIcon.image = NSImage(
                systemSymbolName: systemImageName,
                accessibilityDescription: severity.accessibilityName
            )?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        } else {
            customIcon.image = nil
        }
        updateAccessibility()
    }

    private func installBindingObserver() {
        let identityChanged = observedBinding?.observationIdentity != binding.observationIdentity
            || (observedBinding?.observationIdentity == nil) != (binding.observationIdentity == nil)
        guard identityChanged || observedBinding == nil else { return }
        if let bindingObserverID { observedBinding?.removeObserver(bindingObserverID) }
        observedBinding = binding
        bindingObserverID = binding.observe { [weak self] value in
            guard let self, !self.isWritingBinding else { return }
            self.transition(to: value, reason: .programmatic, writesBinding: false)
        }
    }

    private func closeFromButton() {
        guard isClosable, currentIsOpen else { return }
        onCloseButtonClick?()
        transition(to: false, reason: .closeButton, writesBinding: true)
    }

    private func transition(
        to open: Bool,
        reason: FluentInfoBarCloseReason,
        writesBinding: Bool
    ) {
        guard open != currentIsOpen else { return }
        if !open {
            let args = FluentInfoBarClosingEventArgs(reason: reason)
            onClosing?(args)
            if args.cancel {
                writeBinding(true)
                return
            }
        }

        currentIsOpen = open
        if writesBinding { writeBinding(open) }
        applyOpenState()
        if open {
            onOpened?()
            announceOpened()
        } else {
            onClosed?(reason)
        }
    }

    private func writeBinding(_ value: Bool) {
        guard binding.get() != value else { return }
        isWritingBinding = true
        binding.set(value)
        isWritingBinding = false
    }

    private func applyOpenState() {
        isHidden = !currentIsOpen
        setAccessibilityElement(currentIsOpen)
        actionPresenter.isHidden = !currentIsOpen || !hasAction
        actionView.isHidden = !currentIsOpen || !hasAction
        contentView.isHidden = !currentIsOpen || !hasContent
        standardIcon.isHidden = !currentIsOpen || !isIconVisible || systemImageName != nil
        customIcon.isHidden = !currentIsOpen || !isIconVisible || systemImageName == nil
        closeButton.isHidden = !currentIsOpen || !isClosable
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        superview?.needsLayout = true
        needsLayout = true
        updateAccessibility()
    }

    private func updateAccessibility() {
        let parts = [severity.accessibilityName, title, message].filter { !$0.isEmpty }
        setAccessibilityLabel(parts.joined(separator: ". "))
        setAccessibilityHelp(message)
    }

    private func announceOpened() {
        let parts = [severity.accessibilityName, title, message].filter { !$0.isEmpty }
        let priority: FluentAccessibilityAnnouncementPriority = switch severity {
        case .warning, .error: .high
        case .informational, .success: .medium
        }
        FluentAccessibility.announce(parts.joined(separator: ". "), priority: priority, from: self)
    }

    private func measuredLayout(for proposedWidth: CGFloat) -> LayoutResult {
        let width = max(proposedWidth, 120)
        var result = LayoutResult()
        let closeSpan = isClosable ? Metrics.closeSize + 2 * Metrics.closeMargin : 0
        let iconSpan = isIconVisible ? Metrics.iconSize + Metrics.iconTrailing : 0
        let contentX = Metrics.leadingPadding + iconSpan
        let available = max(
            width - contentX - closeSpan - Metrics.panelTrailing,
            24
        )
        let titleNatural = title.isEmpty ? .zero : measuredText(titleLabel, width: 10_000)
        let messageNatural = message.isEmpty ? .zero : measuredText(messageLabel, width: 10_000)
        let actionSize = hasAction ? measuredView(actionView, width: available) : .zero
        let contentSize = hasContent ? measuredView(contentView, width: available) : .zero
        let itemCount = [!title.isEmpty, !message.isEmpty, hasAction].filter { $0 }.count
        var horizontalWidth: CGFloat = 0
        if !title.isEmpty { horizontalWidth += titleNatural.width }
        if !message.isEmpty {
            if horizontalWidth > 0 { horizontalWidth += Metrics.horizontalMessageSpacing }
            horizontalWidth += messageNatural.width
        }
        if hasAction {
            if horizontalWidth > 0 { horizontalWidth += Metrics.horizontalActionSpacing }
            horizontalWidth += actionSize.width
        }
        let tallestHorizontal = max(
            !title.isEmpty ? titleNatural.height + Metrics.horizontalTextTop : 0,
            !message.isEmpty ? messageNatural.height + Metrics.horizontalTextTop : 0,
            hasAction ? actionSize.height + Metrics.horizontalActionTop : 0
        )
        let horizontal = itemCount > 1
            && horizontalWidth <= available
            && tallestHorizontal <= Metrics.minimumHeight
        result.isVertical = !horizontal

        var bannerBottom: CGFloat = 0
        if horizontal {
            var x = contentX
            if !title.isEmpty {
                result.titleFrame = NSRect(x: x, y: Metrics.horizontalTextTop, width: titleNatural.width, height: titleNatural.height)
                x = result.titleFrame.maxX
            }
            if !message.isEmpty {
                if x > contentX { x += Metrics.horizontalMessageSpacing }
                let messageWidth = hasAction
                    ? messageNatural.width
                    : max(messageNatural.width, available - (x - contentX))
                result.messageFrame = NSRect(
                    x: x,
                    y: Metrics.horizontalTextTop,
                    width: messageWidth,
                    height: messageNatural.height
                )
                x += messageWidth
            }
            if hasAction {
                if x > contentX { x += Metrics.horizontalActionSpacing }
                result.actionFrame = NSRect(
                    x: x,
                    y: Metrics.horizontalActionTop,
                    width: max(actionSize.width, available - (x - contentX)),
                    height: actionSize.height
                )
            }
            bannerBottom = tallestHorizontal
        } else if itemCount > 0 {
            var y = Metrics.verticalTop
            if !title.isEmpty {
                let size = measuredText(titleLabel, width: available)
                result.titleFrame = NSRect(x: contentX, y: y, width: available, height: size.height)
                y = result.titleFrame.maxY
            }
            if !message.isEmpty {
                if y > Metrics.verticalTop { y += Metrics.verticalMessageSpacing }
                let size = measuredText(messageLabel, width: available)
                result.messageFrame = NSRect(x: contentX, y: y, width: available, height: size.height)
                y = result.messageFrame.maxY
            }
            if hasAction {
                if y > Metrics.verticalTop { y += Metrics.verticalActionSpacing }
                result.actionFrame = NSRect(x: contentX, y: y, width: actionSize.width, height: actionSize.height)
                y = result.actionFrame.maxY
            }
            bannerBottom = y + Metrics.verticalBottom
        }

        if hasContent {
            if itemCount == 0 {
                let y = max((Metrics.minimumHeight - contentSize.height) / 2, 0)
                result.contentFrame = NSRect(x: contentX, y: y, width: available, height: contentSize.height)
                result.height = max(Metrics.minimumHeight, contentSize.height)
            } else {
                let y = max(Metrics.minimumHeight, bannerBottom)
                result.contentFrame = NSRect(x: contentX, y: y, width: available, height: contentSize.height)
                result.height = max(Metrics.minimumHeight, y + contentSize.height)
            }
        } else {
            result.height = max(Metrics.minimumHeight, bannerBottom)
        }
        if isIconVisible {
            result.iconFrame = NSRect(
                x: Metrics.leadingPadding,
                y: Metrics.iconTop,
                width: Metrics.iconSize,
                height: Metrics.iconSize
            )
        }
        if isClosable {
            result.closeFrame = NSRect(
                x: width - Metrics.closeMargin - Metrics.closeSize,
                y: Metrics.closeMargin,
                width: Metrics.closeSize,
                height: Metrics.closeSize
            )
        }
        return result
    }

    private func measuredText(_ label: NSTextField, width: CGFloat) -> NSSize {
        let rect = label.attributedStringValue.boundingRect(
            with: NSSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(width: ceil(min(rect.width, width)), height: ceil(rect.height))
    }

    private func measuredView(_ view: NSView, width: CGFloat) -> NSSize {
        let intrinsic = view.intrinsicContentSize
        let fitting = view.fittingSize
        let resolvedWidth = intrinsic.width != NSView.noIntrinsicMetric && intrinsic.width > 0
            ? intrinsic.width
            : (fitting.width > 0 ? fitting.width : width)
        let resolvedHeight = intrinsic.height != NSView.noIntrinsicMetric && intrinsic.height > 0
            ? intrinsic.height
            : max(fitting.height, view.frame.height)
        return NSSize(width: min(max(resolvedWidth, 0), width), height: max(resolvedHeight, 0))
    }

    private func mirrored(_ frame: NSRect) -> NSRect {
        guard userInterfaceLayoutDirection == .rightToLeft, frame != .zero else { return frame }
        return NSRect(
            x: bounds.width - frame.maxX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }
}

private extension FluentInfoBarSeverity {
    var accessibilityName: String {
        switch self {
        case .informational: return "Informational"
        case .success: return "Success"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var symbolName: String {
        switch self {
        case .informational: return "info"
        case .success: return "checkmark"
        case .warning: return "exclamationmark"
        case .error: return "xmark"
        }
    }
}

private final class FluentInfoBarSeverityIconView: NSView {
    var severity: FluentInfoBarSeverity = .informational { didSet { needsDisplay = true } }
    var theme: FluentTheme = .current { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let diameter = min(bounds.width, bounds.height)
        let circle = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        theme.infoBarIconFill(for: severity).setFill()
        NSBezierPath(ovalIn: circle).fill()
        guard let symbol = NSImage(
            systemSymbolName: severity.symbolName,
            accessibilityDescription: nil
        ) else { return }
        let foreground = theme.isHighContrast ? theme.textOnAccent : NSColor.white
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(.init(hierarchicalColor: foreground))
        guard let configured = symbol.withSymbolConfiguration(configuration) else { return }
        let symbolSize = configured.size
        let target = NSRect(
            x: bounds.midX - symbolSize.width / 2,
            y: bounds.midY - symbolSize.height / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        configured.draw(
            in: target,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            // AppKit compensates for the top-down destination when this is true. Passing false
            // renders asymmetric SF Symbols (notably the exclamation mark) upside down.
            respectFlipped: true,
            hints: nil
        )
    }
}

private final class FluentInfoBarCloseButton: NSButton {
    var theme: FluentTheme = .current { didSet { refreshAppearance() } }
    var onInvoke: (() -> Void)?
    private var hovering = false
    private var pressing = false

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 4
        image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close"
        )?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        target = self
        action = #selector(invoke)
        setAccessibilityRole(.button)
        fluentSetDefaultAccessibilityTitle("Close")
        fluentSetDefaultToolTip("Close")
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        refreshAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressing = false
        refreshAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        pressing = true
        refreshAppearance()
        super.mouseDown(with: event)
        pressing = false
        refreshAppearance()
    }

    private func refreshAppearance() {
        contentTintColor = theme.textPrimary
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = (pressing
            ? theme.subtleFillTertiary
            : (hovering ? theme.subtleFillSecondary : NSColor.clear)).cgColor
        CATransaction.commit()
    }

    @objc private func invoke() {
        onInvoke?()
    }
}
