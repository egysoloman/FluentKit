import AppKit

/// Controls the visible height of a `FluentTitleBar`.
public enum FluentTitleBarHeightMode: CaseIterable, RawRepresentable, Hashable, Sendable {
    case automatic
    case compact
    case expanded
    case fixed(CGFloat)

    public static let allCases: [FluentTitleBarHeightMode] = [.automatic, .compact, .expanded]

    public init?(rawValue: String) {
        switch rawValue {
        case "automatic": self = .automatic
        case "compact": self = .compact
        case "expanded": self = .expanded
        default:
            guard rawValue.hasPrefix("fixed:"),
                  let value = Double(rawValue.dropFirst("fixed:".count)) else { return nil }
            self = .fixed(CGFloat(value))
        }
    }

    public var rawValue: String {
        switch self {
        case .automatic: return "automatic"
        case .compact: return "compact"
        case .expanded: return "expanded"
        case let .fixed(value): return "fixed:\(value)"
        }
    }
}

public enum FluentTitleBarBackgroundStyle: String, CaseIterable, Hashable, Sendable {
    case solid
    case transparent
}

private protocol FluentTitleBarPrimaryProviding: AnyObject {
    var isFluentTitleBarPrimary: Bool { get }
}

/// Marks one title-bar component as the primary item. The title bar keeps that item centered in
/// the complete window rather than centering it only in the space left by app identity content.
public struct FluentTitleBarPrimaryView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let isPrimary: Bool

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentTitleBarPrimaryHost(isPrimary: isPrimary)
        host.setContent(content._mount(in: context))
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentTitleBarPrimaryHost,
              let child = host.subviews.first else { return false }
        host.isPrimary = isPrimary
        let updated = content._update(child, in: context)
        if updated { host.contentDidUpdate() }
        return updated
    }
}

public extension FluentView {
    /// Gives this component primary placement when it is mounted inside a Fluent title bar.
    func titleBarPrimary(_ value: Bool = true) -> FluentTitleBarPrimaryView<Self> {
        FluentTitleBarPrimaryView(content: self, isPrimary: value)
    }
}

private final class FluentTitleBarPrimaryHost: NSView, FluentTitleBarPrimaryProviding {
    var isPrimary: Bool
    var isFluentTitleBarPrimary: Bool { isPrimary }

    init(isPrimary: Bool) {
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.Primary")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        guard let child = subviews.first else { return .zero }
        let intrinsic = child.intrinsicContentSize
        let fitting = child.fittingSize
        return NSSize(
            width: intrinsic.width == NSView.noIntrinsicMetric ? fitting.width : intrinsic.width,
            height: intrinsic.height == NSView.noIntrinsicMetric ? fitting.height : intrinsic.height
        )
    }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    func setContent(_ view: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = bounds
        invalidateIntrinsicContentSize()
    }

    func contentDidUpdate() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }
}

/// Native window chrome with selectable macOS or Windows-style system controls and Fluent content.
public struct FluentTitleBar: FluentUpdatablePrimitiveView {
    private let title: String
    private let subtitle: String?
    private let systemImageName: String?
    private let icon: FluentIconSource?
    private let heightMode: FluentTitleBarHeightMode
    private let backgroundStyle: FluentTitleBarBackgroundStyle
    private let windowControlsStyle: FluentWindowControlsStyle
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
        icon: FluentIconSource? = nil,
        heightMode: FluentTitleBarHeightMode = .automatic,
        backgroundStyle: FluentTitleBarBackgroundStyle = .solid,
        windowControlsStyle: FluentWindowControlsStyle = .macOS,
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
            icon: icon,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            windowControlsStyle: windowControlsStyle,
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
        icon: FluentIconSource? = nil,
        heightMode: FluentTitleBarHeightMode = .automatic,
        backgroundStyle: FluentTitleBarBackgroundStyle = .solid,
        windowControlsStyle: FluentWindowControlsStyle = .macOS,
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
            icon: icon,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            windowControlsStyle: windowControlsStyle,
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
        icon: FluentIconSource?,
        heightMode: FluentTitleBarHeightMode,
        backgroundStyle: FluentTitleBarBackgroundStyle,
        windowControlsStyle: FluentWindowControlsStyle,
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
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.heightMode = heightMode
        self.backgroundStyle = backgroundStyle
        self.windowControlsStyle = windowControlsStyle
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
            icon: icon,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            windowControlsStyle: windowControlsStyle,
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
            icon: icon,
            heightMode: heightMode,
            backgroundStyle: backgroundStyle,
            windowControlsStyle: windowControlsStyle,
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
    private static let leftHeaderNegativeInsetSpacing: CGFloat = 2
    private static let iconSpacing: CGFloat = 16
    private static let titleSpacing: CGFloat = 8
    private static let subtitleSpacing: CGFloat = 16
    private static let minimumDragWidth: CGFloat = 48

    private var title: String
    private var subtitle: String?
    private var systemImageName: String?
    private var icon: FluentIconSource?
    private var heightMode: FluentTitleBarHeightMode
    private var backgroundStyle: FluentTitleBarBackgroundStyle
    private var windowControlsStyle: FluentWindowControlsStyle
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
        icon: FluentIconSource?,
        heightMode: FluentTitleBarHeightMode,
        backgroundStyle: FluentTitleBarBackgroundStyle,
        windowControlsStyle: FluentWindowControlsStyle,
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
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.heightMode = heightMode
        self.backgroundStyle = backgroundStyle
        self.windowControlsStyle = windowControlsStyle
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
        icon: FluentIconSource?,
        heightMode: FluentTitleBarHeightMode,
        backgroundStyle: FluentTitleBarBackgroundStyle,
        windowControlsStyle: FluentWindowControlsStyle,
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
        self.icon = icon ?? systemImageName.map(FluentIconSource.systemSymbol)
        self.heightMode = heightMode
        self.backgroundStyle = backgroundStyle
        self.windowControlsStyle = windowControlsStyle
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
        let rightInset = windowControlsStyle.trailingTitleBarInset
        let availableWidth = max(bounds.width - leftInset - rightInset, 0)
        let primaryHost = resolvedPrimaryHost

        func isPrimary(_ host: NSView?) -> Bool {
            guard let host, let primaryHost else { return false }
            return host === primaryHost
        }

        func physicalFrame(logicalX: CGFloat, width: CGFloat) -> NSRect {
            let x = direction == .rightToLeft
                ? bounds.width - rightInset - logicalX - width
                : leftInset + logicalX
            return NSRect(x: x, y: 0, width: max(width, 0), height: height)
        }

        func captionButtonFrame(logicalX: CGFloat) -> NSRect {
            var frame = physicalFrame(logicalX: logicalX, width: Self.buttonWidth)
            // CGRect.insetBy returns CGRect.null (infinite origin) when a transient
            // arrange slot is shorter than the margins. Keep zero-height layout finite.
            frame.origin.y = min(2, max(0, height) / 2)
            frame.size.height = max(0, height - 4)
            return frame
        }

        // WinUI gives the 40-point title-bar buttons an external 2-point margin. The margin is
        // part of the Grid column measurement, so adjacent button centers are 44 points apart;
        // treating it as an internal inset makes the surfaces both too narrow and too close.
        var leading: CGFloat = 2
        backButton.isHidden = !isBackButtonVisible
        if isBackButtonVisible {
            backButton.frame = captionButtonFrame(logicalX: leading)
            leading += Self.buttonWidth + 4
        } else {
            backButton.frame = .zero
        }
        forwardButton.isHidden = !isForwardButtonVisible
        if isForwardButtonVisible {
            forwardButton.frame = captionButtonFrame(logicalX: leading)
            leading += Self.buttonWidth + 4
        } else {
            forwardButton.frame = .zero
        }
        paneToggleButton.isHidden = !isPaneToggleButtonVisible
        if isPaneToggleButtonVisible {
            paneToggleButton.frame = captionButtonFrame(logicalX: leading)
            leading += Self.buttonWidth + 4
        } else {
            paneToggleButton.frame = .zero
        }

        // Resolve the primary frame before measuring the application identity. The primary item
        // stays centered on the physical window, but it is also an exclusion zone: title and
        // subtitle must truncate before it instead of being painted underneath the search box.
        var primaryLogicalStart: CGFloat?
        if let primaryHost {
            let centerX = bounds.midX
            let symmetricWidth = max(
                0,
                2 * min(centerX - leftInset, bounds.width - rightInset - centerX)
            )
            let naturalWidth = fittedWidth(primaryHost, maximum: symmetricWidth)
            let frame = centeredSlotFrame(
                NSRect(
                    x: floor(centerX - naturalWidth / 2),
                    y: 0,
                    width: naturalWidth,
                    height: height
                ),
                host: primaryHost
            )
            primaryHost.frame = frame
            primaryLogicalStart = direction == .rightToLeft
                ? bounds.width - rightInset - frame.maxX
                : frame.minX - leftInset
        }

        let rightWidth = isPrimary(rightHeaderHost)
            ? 0
            : fittedWidth(rightHeaderHost, maximum: min(280, availableWidth * 0.34))
        let rightStart = max(availableWidth - rightWidth, leading)
        var contentLimit = max(
            rightStart - (rightWidth > 0 ? Self.minimumDragWidth : 0),
            leading
        )
        if let primaryLogicalStart {
            contentLimit = min(contentLimit, max(primaryLogicalStart - Self.titleSpacing, leading))
        }
        if let rightHeaderHost, !isPrimary(rightHeaderHost) {
            rightHeaderHost.frame = centeredSlotFrame(
                physicalFrame(logicalX: rightStart, width: rightWidth),
                host: rightHeaderHost
            )
        }

        if let leftHeaderHost, !isPrimary(leftHeaderHost) {
            let width = min(fittedWidth(leftHeaderHost, maximum: 240), max(contentLimit - leading, 0))
            leftHeaderHost.frame = centeredSlotFrame(
                physicalFrame(logicalX: leading, width: width),
                host: leftHeaderHost
            )
            leading += width
        }

        // TitleBar::UpdateLeftHeaderSpacing has two source states. When Back and PaneToggle have
        // equal visibility it keeps the regular 14-point column; when only one is visible it uses
        // the 2-point negative-inset column. This column exists even without a custom LeftHeader.
        let leftHeaderPadding = isBackButtonVisible == isPaneToggleButtonVisible
            ? Self.leftHeaderSpacing
            : Self.leftHeaderNegativeInsetSpacing
        leading += min(leftHeaderPadding, max(contentLimit - leading, 0))

        // WinUI treats title-bar content as interactive chrome. Reserve its requested width before
        // fitting the optional app identity so a narrow window truncates the title instead of the
        // SearchBox or another center control.
        let centerContentWidth = isPrimary(centerContentHost)
            ? 0
            : fittedWidth(centerContentHost, maximum: max(contentLimit - leading, 0))
        let centerSpacing = centerContentWidth > 0 ? Self.titleSpacing : 0
        let identityLimit = max(contentLimit - centerContentWidth - centerSpacing, leading)

        let hasIcon = icon != nil
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

        if let centerContentHost, !isPrimary(centerContentHost) {
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
        if let control = hit as? NSControl, control.isEnabled {
            if let label = control as? NSTextField, !label.isEditable, !label.isSelectable { return self }
            return control
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
        case let .fixed(height): return max(1, height)
        case .automatic:
            let slotHosts = [leftHeaderHost, centerContentHost, rightHeaderHost].compactMap { $0 }
            guard !slotHosts.isEmpty else { return Self.compactHeight }
            let fittedContentHeight = slotHosts.reduce(CGFloat(0)) { partial, host in
                let height = host.fittingSize.height
                return max(partial, height.isFinite ? height : 0)
            }
            return max(Self.expandedHeight, ceil(fittedContentHeight) + 12)
        }
    }

    /// Only one primary item participates in centered placement. Content is the natural default
    /// priority, followed by the leading and trailing slots, making duplicate markers stable.
    private var resolvedPrimaryHost: FluentViewHost<FluentAnyView>? {
        [centerContentHost, leftHeaderHost, rightHeaderHost]
            .compactMap { $0 }
            .first(where: containsPrimaryMarker)
    }

    private func containsPrimaryMarker(_ view: NSView) -> Bool {
        if let marker = view as? FluentTitleBarPrimaryProviding,
           marker.isFluentTitleBarPrimary {
            return true
        }
        return view.subviews.contains(where: containsPrimaryMarker)
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
            host.update(content, context: context)
        } else {
            let newHost = FluentViewHost(content, context: context)
            newHost.identifier = NSUserInterfaceItemIdentifier(identifier)
            newHost.translatesAutoresizingMaskIntoConstraints = true
            addSubview(newHost)
            host = newHost
        }
    }

    private func refreshAppearance() {
        fluentSetLocalization(locale: context.locale, bundle: context.localizationBundle)
        let theme = context.theme
        let activeAlpha: CGFloat = isWindowActive ? 1 : 0.5
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        let titleFont = theme.typography.font(for: .caption)
        titleLabel.font = titleFont
        subtitleLabel.font = titleFont
        titleLabel.textColor = isWindowActive ? theme.textPrimary : theme.textSecondary
        subtitleLabel.textColor = isWindowActive ? theme.textSecondary : theme.textDisabled
        iconView.image = icon?.image(pointSize: 16, color: isWindowActive ? theme.textPrimary : theme.textSecondary,
                                     layoutDirection: context.layoutDirection.appKitValue)
        iconView.imageScaling = .scaleProportionallyDown
        backButton.update(
            theme: theme,
            layoutDirection: context.layoutDirection,
            isActive: isWindowActive,
            reduceMotion: context.reduceMotion,
            isEnabled: isBackButtonEnabled,
            accessibilityValue: nil
        )
        forwardButton.update(
            theme: theme,
            layoutDirection: context.layoutDirection,
            isActive: isWindowActive,
            reduceMotion: context.reduceMotion,
            isEnabled: isForwardButtonEnabled,
            accessibilityValue: nil
        )
        let paneValue = paneOpenBinding.map { fluentControlString($0.get() ? "Expanded" : "Collapsed") }
        paneToggleButton.update(
            theme: theme,
            layoutDirection: context.layoutDirection,
            isActive: isWindowActive,
            reduceMotion: context.reduceMotion,
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
                windowControlsStyle: window.fluentWindowControlsStyle,
                title: window.title
            )
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        } else if !extendsIntoWindowChrome, originalWindowConfiguration != nil {
            restoreWindowConfiguration(window)
        }
        window.applyFluentWindowControlsStyle(
            windowControlsStyle,
            titleBarHeight: resolvedHeight,
            hostedIn: extendsIntoWindowChrome ? self : nil
        )
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
        window.applyFluentWindowControlsStyle(configuration.windowControlsStyle)
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
    let windowControlsStyle: FluentWindowControlsStyle
    let title: String
}
