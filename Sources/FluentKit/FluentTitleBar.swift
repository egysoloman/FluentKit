import AppKit

/// Controls the visible height of a `FluentTitleBar`.
public enum FluentTitleBarHeightMode: String, CaseIterable, Hashable, Sendable {
    case automatic
    case compact
    case expanded
}

public enum FluentTitleBarBackgroundStyle: String, CaseIterable, Hashable, Sendable {
    case solid
    case transparent
}

/// Native window chrome that preserves macOS window controls while providing Fluent title content.
public struct FluentTitleBar: FluentUpdatablePrimitiveView {
    private let title: String
    private let subtitle: String?
    private let systemImageName: String?
    private let heightMode: FluentTitleBarHeightMode
    private let backgroundStyle: FluentTitleBarBackgroundStyle
    private let isBackButtonVisible: Bool
    private let isBackButtonEnabled: Bool
    private let isForwardButtonVisible: Bool
    private let isForwardButtonEnabled: Bool
    private let isPaneToggleButtonVisible: Bool
    private let isPaneOpen: FluentBinding<Bool>?
    private let extendsIntoWindowChrome: Bool
    private let onBack: (() -> Void)?
    private let onForward: (() -> Void)?
    private let onPaneToggle: (() -> Void)?
    private let leftHeader: FluentAnyView?
    private let centerContent: FluentAnyView?
    private let rightHeader: FluentAnyView?

    public init(
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        heightMode: FluentTitleBarHeightMode = .automatic,
        backgroundStyle: FluentTitleBarBackgroundStyle = .solid,
        isBackButtonVisible: Bool = false,
        isBackButtonEnabled: Bool = true,
        isForwardButtonVisible: Bool = false,
        isForwardButtonEnabled: Bool = true,
        isPaneToggleButtonVisible: Bool = false,
        isPaneOpen: FluentBinding<Bool>? = nil,
        extendsIntoWindowChrome: Bool = true,
        onBack: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        onPaneToggle: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            isPaneOpen: isPaneOpen,
            extendsIntoWindowChrome: extendsIntoWindowChrome,
            onBack: onBack,
            onForward: onForward,
            onPaneToggle: onPaneToggle,
            leftHeader: nil,
            centerContent: nil,
            rightHeader: nil
        )
    }

    public init<LeftHeader: FluentView, CenterContent: FluentView, RightHeader: FluentView>(
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        heightMode: FluentTitleBarHeightMode = .automatic,
        backgroundStyle: FluentTitleBarBackgroundStyle = .solid,
        isBackButtonVisible: Bool = false,
        isBackButtonEnabled: Bool = true,
        isForwardButtonVisible: Bool = false,
        isForwardButtonEnabled: Bool = true,
        isPaneToggleButtonVisible: Bool = false,
        isPaneOpen: FluentBinding<Bool>? = nil,
        extendsIntoWindowChrome: Bool = true,
        onBack: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        onPaneToggle: (() -> Void)? = nil,
        @FluentViewBuilder leftHeader: () -> LeftHeader,
        @FluentViewBuilder content: () -> CenterContent,
        @FluentViewBuilder rightHeader: () -> RightHeader
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            isPaneOpen: isPaneOpen,
            extendsIntoWindowChrome: extendsIntoWindowChrome,
            onBack: onBack,
            onForward: onForward,
            onPaneToggle: onPaneToggle,
            leftHeader: FluentAnyView(leftHeader()),
            centerContent: FluentAnyView(content()),
            rightHeader: FluentAnyView(rightHeader())
        )
    }

    private init(
        title: String,
        subtitle: String?,
        systemImageName: String?,
        heightMode: FluentTitleBarHeightMode,
        backgroundStyle: FluentTitleBarBackgroundStyle,
        isBackButtonVisible: Bool,
        isBackButtonEnabled: Bool,
        isForwardButtonVisible: Bool,
        isForwardButtonEnabled: Bool,
        isPaneToggleButtonVisible: Bool,
        isPaneOpen: FluentBinding<Bool>?,
        extendsIntoWindowChrome: Bool,
        onBack: (() -> Void)?,
        onForward: (() -> Void)?,
        onPaneToggle: (() -> Void)?,
        leftHeader: FluentAnyView?,
        centerContent: FluentAnyView?,
        rightHeader: FluentAnyView?
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.heightMode = heightMode
        self.backgroundStyle = backgroundStyle
        self.isBackButtonVisible = isBackButtonVisible
        self.isBackButtonEnabled = isBackButtonEnabled
        self.isForwardButtonVisible = isForwardButtonVisible
        self.isForwardButtonEnabled = isForwardButtonEnabled
        self.isPaneToggleButtonVisible = isPaneToggleButtonVisible
        self.isPaneOpen = isPaneOpen
        self.extendsIntoWindowChrome = extendsIntoWindowChrome
        self.onBack = onBack
        self.onForward = onForward
        self.onPaneToggle = onPaneToggle
        self.leftHeader = leftHeader
        self.centerContent = centerContent
        self.rightHeader = rightHeader
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentTitleBarHost(
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            isPaneOpen: isPaneOpen,
            extendsIntoWindowChrome: extendsIntoWindowChrome,
            onBack: onBack,
            onForward: onForward,
            onPaneToggle: onPaneToggle,
            leftHeader: leftHeader,
            centerContent: centerContent,
            rightHeader: rightHeader,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentTitleBarHost else { return false }
        host.update(
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            isPaneToggleButtonVisible: isPaneToggleButtonVisible,
            isPaneOpen: isPaneOpen,
            extendsIntoWindowChrome: extendsIntoWindowChrome,
            onBack: onBack,
            onForward: onForward,
            onPaneToggle: onPaneToggle,
            leftHeader: leftHeader,
            centerContent: centerContent,
            rightHeader: rightHeader,
            context: context
        )
        return true
    }
}

private final class FluentTitleBarHost: NSView {
    private static let compactHeight: CGFloat = 32
    private static let expandedHeight: CGFloat = 48
    private static let buttonWidth: CGFloat = 40
    private static let iconWidth: CGFloat = 16
    private static let leftHeaderSpacing: CGFloat = 14
    private static let iconSpacing: CGFloat = 16
    private static let titleSpacing: CGFloat = 8
    private static let subtitleSpacing: CGFloat = 16
    private static let minimumDragWidth: CGFloat = 48

    private var title: String
    private var subtitle: String?
    private var systemImageName: String?
    private var heightMode: FluentTitleBarHeightMode
    private var backgroundStyle: FluentTitleBarBackgroundStyle
    private var isBackButtonVisible: Bool
    private var isBackButtonEnabled: Bool
    private var isForwardButtonVisible: Bool
    private var isForwardButtonEnabled: Bool
    private var isPaneToggleButtonVisible: Bool
    private var paneOpenBinding: FluentBinding<Bool>?
    private var extendsIntoWindowChrome: Bool
    private var onBack: (() -> Void)?
    private var onForward: (() -> Void)?
    private var onPaneToggle: (() -> Void)?
    private var leftHeader: FluentAnyView?
    private var centerContent: FluentAnyView?
    private var rightHeader: FluentAnyView?
    private var context: FluentRenderContext

    private let backButton = FluentTitleBarButton(kind: .back)
    private let forwardButton = FluentTitleBarButton(kind: .forward)
    private let paneToggleButton = FluentTitleBarButton(kind: .pane)
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var leftHeaderHost: FluentViewHost<FluentAnyView>?
    private var centerContentHost: FluentViewHost<FluentAnyView>?
    private var rightHeaderHost: FluentViewHost<FluentAnyView>?

    private var observedPaneOpen: FluentBinding<Bool>?
    private var paneOpenObserverID: UUID?
    private weak var configuredWindow: NSWindow?
    private var originalWindowConfiguration: WindowConfiguration?
    private var activeObservers: [NSObjectProtocol] = []
    private var isWindowActive = true
    private var lastAppliedWindowTitle: String?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: resolvedHeight)
    }

    init(
        title: String,
        subtitle: String?,
        systemImageName: String?,
        heightMode: FluentTitleBarHeightMode,
        backgroundStyle: FluentTitleBarBackgroundStyle,
        isBackButtonVisible: Bool,
        isBackButtonEnabled: Bool,
        isForwardButtonVisible: Bool,
        isForwardButtonEnabled: Bool,
        isPaneToggleButtonVisible: Bool,
        isPaneOpen: FluentBinding<Bool>?,
        extendsIntoWindowChrome: Bool,
        onBack: (() -> Void)?,
        onForward: (() -> Void)?,
        onPaneToggle: (() -> Void)?,
        leftHeader: FluentAnyView?,
        centerContent: FluentAnyView?,
        rightHeader: FluentAnyView?,
        context: FluentRenderContext
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.heightMode = heightMode
        self.backgroundStyle = backgroundStyle
        self.isBackButtonVisible = isBackButtonVisible
        self.isBackButtonEnabled = isBackButtonEnabled
        self.isForwardButtonVisible = isForwardButtonVisible
        self.isForwardButtonEnabled = isForwardButtonEnabled
        self.isPaneToggleButtonVisible = isPaneToggleButtonVisible
        paneOpenBinding = isPaneOpen
        self.extendsIntoWindowChrome = extendsIntoWindowChrome
        self.onBack = onBack
        self.onForward = onForward
        self.onPaneToggle = onPaneToggle
        self.leftHeader = leftHeader
        self.centerContent = centerContent
        self.rightHeader = rightHeader
        self.context = context
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar")
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)

        backButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.Back")
        forwardButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.Forward")
        paneToggleButton.identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.PaneToggle")
        backButton.onInvoke = { [weak self] in self?.onBack?() }
        forwardButton.onInvoke = { [weak self] in self?.onForward?() }
        paneToggleButton.onInvoke = { [weak self] in self?.togglePane() }

        iconView.identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.Icon")
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        configureLabel(titleLabel, identifier: "FluentKit.TitleBar.Title")
        configureLabel(subtitleLabel, identifier: "FluentKit.TitleBar.Subtitle")

        addSubview(backButton)
        addSubview(forwardButton)
        addSubview(paneToggleButton)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        reconcileSlot(&leftHeaderHost, content: leftHeader, identifier: "FluentKit.TitleBar.LeftHeader")
        reconcileSlot(&centerContentHost, content: centerContent, identifier: "FluentKit.TitleBar.Content")
        reconcileSlot(&rightHeaderHost, content: rightHeader, identifier: "FluentKit.TitleBar.RightHeader")
        installPaneObserver()
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        title: String,
        subtitle: String?,
        systemImageName: String?,
        heightMode: FluentTitleBarHeightMode,
        backgroundStyle: FluentTitleBarBackgroundStyle,
        isBackButtonVisible: Bool,
        isBackButtonEnabled: Bool,
        isForwardButtonVisible: Bool,
        isForwardButtonEnabled: Bool,
        isPaneToggleButtonVisible: Bool,
        isPaneOpen: FluentBinding<Bool>?,
        extendsIntoWindowChrome: Bool,
        onBack: (() -> Void)?,
        onForward: (() -> Void)?,
        onPaneToggle: (() -> Void)?,
        leftHeader: FluentAnyView?,
        centerContent: FluentAnyView?,
        rightHeader: FluentAnyView?,
        context: FluentRenderContext
    ) {
        let oldHeight = resolvedHeight
        removePaneObserver()
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.heightMode = heightMode
        self.backgroundStyle = backgroundStyle
        self.isBackButtonVisible = isBackButtonVisible
        self.isBackButtonEnabled = isBackButtonEnabled
        self.isForwardButtonVisible = isForwardButtonVisible
        self.isForwardButtonEnabled = isForwardButtonEnabled
        self.isPaneToggleButtonVisible = isPaneToggleButtonVisible
        paneOpenBinding = isPaneOpen
        self.extendsIntoWindowChrome = extendsIntoWindowChrome
        self.onBack = onBack
        self.onForward = onForward
        self.onPaneToggle = onPaneToggle
        self.leftHeader = leftHeader
        self.centerContent = centerContent
        self.rightHeader = rightHeader
        self.context = context
        reconcileSlot(&leftHeaderHost, content: leftHeader, identifier: "FluentKit.TitleBar.LeftHeader")
        reconcileSlot(&centerContentHost, content: centerContent, identifier: "FluentKit.TitleBar.Content")
        reconcileSlot(&rightHeaderHost, content: rightHeader, identifier: "FluentKit.TitleBar.RightHeader")
        installPaneObserver()
        if oldHeight != resolvedHeight { invalidateIntrinsicContentSize() }
        applyWindowConfigurationIfNeeded()
        refreshAppearance()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detachWindowConfiguration()
        attachWindowConfiguration()
    }

    override func layout() {
        super.layout()
        let height = min(resolvedHeight, bounds.height)
        let direction = context.layoutDirection
        let leftInset = physicalLeftInset()
        let rightInset: CGFloat = 0
        let availableWidth = max(bounds.width - leftInset - rightInset, 0)

        func physicalFrame(logicalX: CGFloat, width: CGFloat) -> NSRect {
            let x = direction == .rightToLeft
                ? bounds.width - rightInset - logicalX - width
                : leftInset + logicalX
            return NSRect(x: x, y: 0, width: max(width, 0), height: height)
        }

        var leading: CGFloat = 2
        backButton.isHidden = !isBackButtonVisible
        if isBackButtonVisible {
            backButton.frame = physicalFrame(logicalX: leading, width: Self.buttonWidth)
            leading += Self.buttonWidth
        } else {
            backButton.frame = .zero
        }
        forwardButton.isHidden = !isForwardButtonVisible
        if isForwardButtonVisible {
            forwardButton.frame = physicalFrame(logicalX: leading, width: Self.buttonWidth)
            leading += Self.buttonWidth
        } else {
            forwardButton.frame = .zero
        }
        paneToggleButton.isHidden = !isPaneToggleButtonVisible
        if isPaneToggleButtonVisible {
            paneToggleButton.frame = physicalFrame(logicalX: leading, width: Self.buttonWidth)
            leading += Self.buttonWidth
        } else {
            paneToggleButton.frame = .zero
        }

        let rightWidth = fittedWidth(rightHeaderHost, maximum: min(280, availableWidth * 0.34))
        let rightStart = max(availableWidth - rightWidth, leading)
        let contentLimit = max(
            rightStart - (rightWidth > 0 ? Self.minimumDragWidth : 0),
            leading
        )
        if let rightHeaderHost {
            rightHeaderHost.frame = centeredSlotFrame(
                physicalFrame(logicalX: rightStart, width: rightWidth),
                host: rightHeaderHost
            )
        }

        if let leftHeaderHost {
            let width = min(fittedWidth(leftHeaderHost, maximum: 240), max(contentLimit - leading, 0))
            leftHeaderHost.frame = centeredSlotFrame(
                physicalFrame(logicalX: leading, width: width),
                host: leftHeaderHost
            )
            leading += width
            if width > 0 { leading += min(Self.leftHeaderSpacing, max(contentLimit - leading, 0)) }
        }

        // WinUI treats title-bar content as interactive chrome. Reserve its requested width before
        // fitting the optional app identity so a narrow window truncates the title instead of the
        // SearchBox or another center control.
        let centerContentWidth = fittedWidth(
            centerContentHost,
            maximum: max(contentLimit - leading, 0)
        )
        let centerSpacing = centerContentWidth > 0 ? Self.titleSpacing : 0
        let identityLimit = max(contentLimit - centerContentWidth - centerSpacing, leading)

        let hasIcon = systemImageName?.isEmpty == false
        iconView.isHidden = !hasIcon || identityLimit - leading < Self.iconWidth
        if !iconView.isHidden {
            iconView.frame = centeredRect(in: physicalFrame(logicalX: leading, width: Self.iconWidth), size: NSSize(width: 16, height: 16))
            leading += Self.iconWidth
            leading += min(Self.iconSpacing, max(identityLimit - leading, 0))
        } else {
            iconView.frame = .zero
        }

        let titleNaturalWidth = measuredWidth(of: title, in: titleLabel)
        let titleWidth = min(titleNaturalWidth, max(identityLimit - leading, 0))
        titleLabel.frame = centeredLabelFrame(physicalFrame(logicalX: leading, width: titleWidth), label: titleLabel)
        titleLabel.isHidden = title.isEmpty || titleWidth <= 0
        leading += titleWidth
        if titleWidth > 0 { leading += min(Self.titleSpacing, max(identityLimit - leading, 0)) }

        let subtitleNaturalWidth = measuredWidth(of: subtitle ?? "", in: subtitleLabel)
        let subtitleWidth = min(subtitleNaturalWidth, max(identityLimit - leading, 0))
        subtitleLabel.frame = centeredLabelFrame(physicalFrame(logicalX: leading, width: subtitleWidth), label: subtitleLabel)
        subtitleLabel.isHidden = subtitle?.isEmpty != false || subtitleWidth <= 0
        leading += subtitleWidth
        if subtitleWidth > 0 { leading += min(Self.subtitleSpacing, max(identityLimit - leading, 0)) }

        if let centerContentHost {
            let contentWidth = min(
                centerContentWidth,
                max(contentLimit - leading, 0)
            )
            let contentX = leading + max((contentLimit - leading - contentWidth) / 2, 0)
            centerContentHost.frame = centeredSlotFrame(
                physicalFrame(logicalX: contentX, width: contentWidth),
                host: centerContentHost
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if backgroundStyle == .solid {
            context.theme.windowBackground.setFill()
            dirtyRect.fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === backButton || hit === forwardButton || hit === paneToggleButton { return hit }
        if let control = hit as? NSControl,
           control.isEnabled,
           !(control is NSTextField && !(control as! NSTextField).isEditable && !(control as! NSTextField).isSelectable) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            performTitleBarDoubleClick(on: window)
        } else {
            window.performDrag(with: event)
        }
    }

    private var resolvedHeight: CGFloat {
        switch heightMode {
        case .compact: return Self.compactHeight
        case .expanded: return Self.expandedHeight
        case .automatic:
            return leftHeader == nil && centerContent == nil && rightHeader == nil
                ? Self.compactHeight
                : Self.expandedHeight
        }
    }

    private func configureLabel(_ label: NSTextField, identifier: String) {
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
    }

    private func reconcileSlot(
        _ host: inout FluentViewHost<FluentAnyView>?,
        content: FluentAnyView?,
        identifier: String
    ) {
        guard let content else {
            host?.removeFromSuperview()
            host = nil
            return
        }
        if let host {
            host.context = context
            host.update(content)
        } else {
            let newHost = FluentViewHost(content, context: context)
            newHost.identifier = NSUserInterfaceItemIdentifier(identifier)
            newHost.translatesAutoresizingMaskIntoConstraints = true
            addSubview(newHost)
            host = newHost
        }
    }

    private func refreshAppearance() {
        let theme = context.theme
        let activeAlpha: CGFloat = isWindowActive ? 1 : 0.5
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        let titleFont = theme.typography.font(for: .caption)
        titleLabel.font = NSFont.systemFont(ofSize: titleFont.pointSize, weight: .semibold)
        subtitleLabel.font = titleFont
        titleLabel.textColor = isWindowActive ? theme.textPrimary : theme.textSecondary
        subtitleLabel.textColor = isWindowActive ? theme.textSecondary : theme.textDisabled
        if let systemImageName,
           let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: title) {
            let size = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let color = NSImage.SymbolConfiguration(
                hierarchicalColor: isWindowActive ? theme.textPrimary : theme.textSecondary
            )
            iconView.image = image.withSymbolConfiguration(size.applying(color))
        } else {
            iconView.image = nil
        }
        backButton.update(
            theme: theme,
            layoutDirection: context.layoutDirection,
            isActive: isWindowActive,
            isEnabled: isBackButtonEnabled,
            accessibilityValue: nil
        )
        forwardButton.update(
            theme: theme,
            layoutDirection: context.layoutDirection,
            isActive: isWindowActive,
            isEnabled: isForwardButtonEnabled,
            accessibilityValue: nil
        )
        let paneValue = paneOpenBinding.map { $0.get() ? "Expanded" : "Collapsed" }
        paneToggleButton.update(
            theme: theme,
            layoutDirection: context.layoutDirection,
            isActive: isWindowActive,
            isEnabled: true,
            accessibilityValue: paneValue
        )
        leftHeaderHost?.alphaValue = activeAlpha
        centerContentHost?.alphaValue = activeAlpha
        rightHeaderHost?.alphaValue = activeAlpha
        setAccessibilityLabel(title)
        needsDisplay = true
        needsLayout = true
        syncWindowTitle()
    }

    private func fittedWidth(_ host: FluentViewHost<FluentAnyView>?, maximum: CGFloat) -> CGFloat {
        guard let host else { return 0 }
        let width = host.fittingSize.width
        return min(max(width.isFinite ? width : 0, 0), max(maximum, 0))
    }

    private func centeredSlotFrame(_ frame: NSRect, host: NSView) -> NSRect {
        let height = min(max(host.fittingSize.height, 0), frame.height)
        return NSRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
    }

    private func centeredLabelFrame(_ frame: NSRect, label: NSTextField) -> NSRect {
        let height = min(max(label.intrinsicContentSize.height, 0), frame.height)
        return NSRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
    }

    private func measuredWidth(of text: String, in label: NSTextField) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = label.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 8
    }

    private func centeredRect(in frame: NSRect, size: NSSize) -> NSRect {
        NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func physicalLeftInset() -> CGFloat {
        guard extendsIntoWindowChrome, let window, window.styleMask.contains(.titled) else { return 0 }
        var maximumX: CGFloat = 0
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), !button.isHidden else { continue }
            let frame = button.convert(button.bounds, to: self)
            guard frame.maxY > bounds.minY, frame.minY < bounds.maxY else { continue }
            maximumX = max(maximumX, frame.maxX)
        }
        return maximumX > 0 ? maximumX + 8 : 0
    }

    private func togglePane() {
        if let paneOpenBinding { paneOpenBinding.set(!paneOpenBinding.get()) }
        onPaneToggle?()
        refreshAppearance()
    }

    private func installPaneObserver() {
        observedPaneOpen = paneOpenBinding
        paneOpenObserverID = paneOpenBinding?.observe { [weak self] _ in self?.refreshAppearance() }
    }

    private func removePaneObserver() {
        if let paneOpenObserverID { observedPaneOpen?.removeObserver(paneOpenObserverID) }
        observedPaneOpen = nil
        paneOpenObserverID = nil
    }

    private func attachWindowConfiguration() {
        guard let window else { return }
        configuredWindow = window
        let center = NotificationCenter.default
        activeObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.setWindowActive(true)
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.setWindowActive(false)
            }
        ]
        isWindowActive = !window.isVisible || window.isKeyWindow
        applyWindowConfigurationIfNeeded()
        refreshAppearance()
    }

    private func applyWindowConfigurationIfNeeded() {
        guard let window = configuredWindow, window.styleMask.contains(.titled) else { return }
        if extendsIntoWindowChrome, originalWindowConfiguration == nil {
            originalWindowConfiguration = WindowConfiguration(
                styleMask: window.styleMask,
                titlebarAppearsTransparent: window.titlebarAppearsTransparent,
                titleVisibility: window.titleVisibility,
                titlebarSeparatorStyle: window.titlebarSeparatorStyle,
                title: window.title
            )
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        } else if !extendsIntoWindowChrome, originalWindowConfiguration != nil {
            restoreWindowConfiguration(window)
        }
        syncWindowTitle()
        needsLayout = true
    }

    private func syncWindowTitle() {
        guard let window = configuredWindow, !title.isEmpty, window.title != title else { return }
        window.title = title
        lastAppliedWindowTitle = title
    }

    private func setWindowActive(_ active: Bool) {
        guard isWindowActive != active else { return }
        isWindowActive = active
        refreshAppearance()
    }

    private func detachWindowConfiguration() {
        activeObservers.forEach(NotificationCenter.default.removeObserver)
        activeObservers.removeAll()
        if let window = configuredWindow { restoreWindowConfiguration(window) }
        configuredWindow = nil
    }

    private func restoreWindowConfiguration(_ window: NSWindow) {
        guard let configuration = originalWindowConfiguration else { return }
        window.styleMask = configuration.styleMask
        window.titlebarAppearsTransparent = configuration.titlebarAppearsTransparent
        window.titleVisibility = configuration.titleVisibility
        window.titlebarSeparatorStyle = configuration.titlebarSeparatorStyle
        if window.title == lastAppliedWindowTitle { window.title = configuration.title }
        originalWindowConfiguration = nil
        lastAppliedWindowTitle = nil
    }

    private func performTitleBarDoubleClick(on window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.miniaturize(nil)
        case "None": break
        default: window.zoom(nil)
        }
    }

    deinit {
        removePaneObserver()
        detachWindowConfiguration()
    }
}

private struct WindowConfiguration {
    let styleMask: NSWindow.StyleMask
    let titlebarAppearsTransparent: Bool
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let title: String
}

private final class FluentTitleBarButton: NSButton {
    enum Kind {
        case back
        case forward
        case pane
    }

    let kind: Kind
    var onInvoke: (() -> Void)?
    private var theme: FluentTheme = .current
    private var layoutDirection: FluentLayoutDirection = .leftToRight
    private var isWindowActive = true
    private var pointerOver = false
    private var pressed = false
    private let chevronLayer = FluentChevronPrimitiveLayer()

    override var acceptsFirstResponder: Bool { isEnabled }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        if kind != .pane {
            chevronLayer.name = kind == .back
                ? "FluentKit.TitleBar.BackChevron"
                : "FluentKit.TitleBar.ForwardChevron"
            layer?.addSublayer(chevronLayer)
        }
        target = self
        action = #selector(invoke)
        setAccessibilityRole(.button)
        let label = switch kind {
        case .back: "Back"
        case .forward: "Forward"
        case .pane: "Navigation"
        }
        setAccessibilityTitle(label)
        toolTip = label
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        theme: FluentTheme,
        layoutDirection: FluentLayoutDirection,
        isActive: Bool,
        isEnabled: Bool,
        accessibilityValue: String?
    ) {
        self.theme = theme
        self.layoutDirection = layoutDirection
        isWindowActive = isActive
        self.isEnabled = isEnabled
        setAccessibilityEnabled(isEnabled)
        setAccessibilityValue(accessibilityValue)
        needsDisplay = true
        updateBackChevron(animated: false)
    }

    override func layout() {
        super.layout()
        updateBackChevron(animated: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackChevron(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        pointerOver = true
        needsDisplay = true
        updateBackChevron(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        pressed = false
        needsDisplay = true
        updateBackChevron(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
        updateBackChevron(animated: true)
        super.mouseDown(with: event)
        pressed = false
        pointerOver = bounds.contains(convert(event.locationInWindow, from: nil))
        needsDisplay = true
        updateBackChevron(animated: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { performClick(nil) } else { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isHidden else { return false }
        performClick(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let surface = bounds.insetBy(dx: 2, dy: 2)
        let background: NSColor
        if !isEnabled {
            background = theme.buttonBackground(for: .disabled)
        } else if pressed {
            background = theme.controlFillTertiary
        } else if pointerOver {
            background = theme.controlFillSecondary
        } else {
            background = .clear
        }
        background.setFill()
        NSBezierPath(roundedRect: surface, xRadius: 4, yRadius: 4).fill()

        let color = !isEnabled
            ? theme.textDisabled
            : (isWindowActive ? theme.textPrimary : theme.textSecondary)
        if kind == .pane,
           let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: accessibilityTitle()) {
            let point = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let tint = NSImage.SymbolConfiguration(hierarchicalColor: color)
            image.withSymbolConfiguration(point.applying(tint))?.draw(
                in: NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
            )
        }
        if window?.firstResponder === self {
            theme.accent.setStroke()
            let focus = NSBezierPath(roundedRect: surface.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            focus.lineWidth = theme.focusStrokeWidth
            focus.stroke()
        }
    }

    private func updateBackChevron(animated: Bool) {
        guard kind != .pane, bounds.width > 0, bounds.height > 0 else { return }
        let state: FluentControlState = !isEnabled
            ? .disabled
            : (pressed ? .pressed : (pointerOver ? .pointerOver : .normal))
        let color = !isEnabled
            ? theme.textDisabled
            : (isWindowActive ? theme.textPrimary : theme.textSecondary)
        let direction: FluentChevronDirection
        switch (kind, layoutDirection) {
        case (.back, .rightToLeft), (.forward, .leftToRight), (.forward, .system):
            direction = .right
        default:
            direction = .left
        }
        chevronLayer.update(
            frame: NSRect(x: bounds.midX - 6, y: bounds.midY - 6, width: 12, height: 12),
            color: color,
            state: state,
            visual: .directional,
            direction: direction,
            backingScale: window?.backingScaleFactor,
            animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @objc private func invoke() { if isEnabled { onInvoke?() } }
}
