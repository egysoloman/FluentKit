import AppKit

public enum FluentWindowLayout: String, CaseIterable, Hashable, Sendable {
    case standard
    case compactNavigation
    case minimalNavigation
    case topNavigation
    case settings
    case document
    case inspector
    case dialog
}

public enum FluentWindowTitleBarStyle: String, CaseIterable, Hashable, Sendable {
    case native
    case extended
}

public enum FluentWindowNavigationPlacement: String, CaseIterable, Hashable, Sendable {
    case none
    case automatic
    case left
    case leftCompact
    case leftMinimal
    case top

    var paneDisplayMode: FluentNavigationPaneDisplayMode? {
        switch self {
        case .none: nil
        case .automatic: .automatic
        case .left: .left
        case .leftCompact: .leftCompact
        case .leftMinimal: .leftMinimal
        case .top: .top
        }
    }
}

public enum FluentWindowPaneTogglePlacement: String, CaseIterable, Hashable, Sendable {
    case titleBar
    case navigationPane
}

public enum FluentWindowSearchPlacement: String, CaseIterable, Hashable, Sendable {
    case none
    case titleBar
    case navigationPane
}

public enum FluentWindowBackdrop: String, CaseIterable, Hashable, Sendable {
    case solid
    case mica
    /// Compatibility spelling. Persistent WindowShell backdrops resolve this to Mica; use
    /// `FluentMaterial.liquidGlass` for transient presenters.
    case liquidGlass
}

public enum FluentContentCornerStyle: String, CaseIterable, Hashable, Sendable {
    case none
    case topLeading
    case all
}

private func fluentWindowContentSurfacePath(
    in rect: CGRect,
    radius requestedRadius: CGFloat,
    cornerStyle: FluentContentCornerStyle,
    layoutDirection: FluentLayoutDirection,
    visualYAxis: FluentVisualYAxis
) -> CGPath {
    let radius = min(max(requestedRadius, 0), rect.width / 2, rect.height / 2)
    guard cornerStyle != .none, radius > 0 else {
        return CGPath(rect: rect, transform: nil)
    }
    if cornerStyle == .all {
        return CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    let topIsMinY = visualYAxis == .down
    let leadingIsMinX = layoutDirection != .rightToLeft
    let roundsMinXMinY = topIsMinY && leadingIsMinX
    let roundsMaxXMinY = topIsMinY && !leadingIsMinX
    let roundsMinXMaxY = !topIsMinY && leadingIsMinX
    let roundsMaxXMaxY = !topIsMinY && !leadingIsMinX
    let topLeftRadius = roundsMinXMinY ? radius : 0
    let topRightRadius = roundsMaxXMinY ? radius : 0
    let bottomRightRadius = roundsMaxXMaxY ? radius : 0
    let bottomLeftRadius = roundsMinXMaxY ? radius : 0

    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY))
    if topRightRadius > 0 {
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRightRadius),
            radius: topRightRadius
        )
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
    if bottomRightRadius > 0 {
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY),
            radius: bottomRightRadius
        )
    }
    path.addLine(to: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY))
    if bottomLeftRadius > 0 {
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeftRadius),
            radius: bottomLeftRadius
        )
    }
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeftRadius))
    if topLeftRadius > 0 {
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY),
            radius: topLeftRadius
        )
    }
    path.closeSubpath()
    return path
}

/// Independent window-shell axes. Layout presets supply defaults, while each axis remains
/// overridable so applications can combine native/extended title bars, horizontal/vertical
/// navigation, optional title-bar search, and either pane-toggle location.
public struct FluentWindowConfiguration: Hashable, Sendable {
    public let layout: FluentWindowLayout
    public let titleBarStyle: FluentWindowTitleBarStyle
    public let navigationPlacement: FluentWindowNavigationPlacement
    public let paneTogglePlacement: FluentWindowPaneTogglePlacement
    public let searchPlacement: FluentWindowSearchPlacement
    public let backdrop: FluentWindowBackdrop
    public let contentCornerStyle: FluentContentCornerStyle
    public let titleBarHeight: FluentTitleBarHeightMode
    public let contentTransition: FluentNavigationTransitionMode

    public init(
        layout: FluentWindowLayout = .standard,
        titleBarStyle: FluentWindowTitleBarStyle? = nil,
        navigationPlacement: FluentWindowNavigationPlacement? = nil,
        paneTogglePlacement: FluentWindowPaneTogglePlacement? = nil,
        searchPlacement: FluentWindowSearchPlacement? = nil,
        backdrop: FluentWindowBackdrop? = nil,
        contentCornerStyle: FluentContentCornerStyle? = nil,
        titleBarHeight: FluentTitleBarHeightMode? = nil,
        contentTransition: FluentNavigationTransitionMode = .automatic
    ) {
        let preset = Self.preset(for: layout)
        let resolvedTitleBarStyle = titleBarStyle ?? preset.titleBarStyle
        let resolvedNavigationPlacement = navigationPlacement ?? preset.navigationPlacement
        let requestedTogglePlacement = paneTogglePlacement ?? preset.paneTogglePlacement
        let requestedSearchPlacement = searchPlacement ?? preset.searchPlacement
        self.layout = layout
        self.titleBarStyle = resolvedTitleBarStyle
        self.navigationPlacement = resolvedNavigationPlacement
        // Native AppKit title bars cannot host Fluent content. Keep a requested pane action
        // available by moving it into vertical navigation, and suppress unsupported search.
        self.paneTogglePlacement = resolvedTitleBarStyle == .native
            && requestedTogglePlacement == .titleBar
            ? .navigationPane
            : requestedTogglePlacement
        self.searchPlacement = resolvedTitleBarStyle == .native ? .none : requestedSearchPlacement
        self.backdrop = backdrop ?? preset.backdrop
        self.contentCornerStyle = contentCornerStyle ?? preset.contentCornerStyle
        self.titleBarHeight = titleBarHeight ?? preset.titleBarHeight
        self.contentTransition = contentTransition
    }

    private static func preset(for layout: FluentWindowLayout) -> FluentWindowConfigurationPreset {
        switch layout {
        case .standard:
            FluentWindowConfigurationPreset(.native, .none, .navigationPane, .none, .mica, .none, .compact)
        case .compactNavigation:
            FluentWindowConfigurationPreset(.extended, .leftCompact, .titleBar, .titleBar, .mica, .topLeading, .expanded)
        case .minimalNavigation:
            FluentWindowConfigurationPreset(.extended, .leftMinimal, .titleBar, .titleBar, .mica, .topLeading, .expanded)
        case .topNavigation:
            FluentWindowConfigurationPreset(.extended, .top, .titleBar, .titleBar, .mica, .none, .expanded)
        case .settings:
            FluentWindowConfigurationPreset(.extended, .left, .titleBar, .titleBar, .mica, .topLeading, .expanded)
        case .document:
            FluentWindowConfigurationPreset(.native, .none, .navigationPane, .none, .mica, .none, .compact)
        case .inspector:
            FluentWindowConfigurationPreset(.extended, .leftCompact, .titleBar, .none, .mica, .topLeading, .compact)
        case .dialog:
            FluentWindowConfigurationPreset(.native, .none, .navigationPane, .none, .solid, .all, .compact)
        }
    }
}

private struct FluentWindowConfigurationPreset {
    let titleBarStyle: FluentWindowTitleBarStyle
    let navigationPlacement: FluentWindowNavigationPlacement
    let paneTogglePlacement: FluentWindowPaneTogglePlacement
    let searchPlacement: FluentWindowSearchPlacement
    let backdrop: FluentWindowBackdrop
    let contentCornerStyle: FluentContentCornerStyle
    let titleBarHeight: FluentTitleBarHeightMode

    init(
        _ titleBarStyle: FluentWindowTitleBarStyle,
        _ navigationPlacement: FluentWindowNavigationPlacement,
        _ paneTogglePlacement: FluentWindowPaneTogglePlacement,
        _ searchPlacement: FluentWindowSearchPlacement,
        _ backdrop: FluentWindowBackdrop,
        _ contentCornerStyle: FluentContentCornerStyle,
        _ titleBarHeight: FluentTitleBarHeightMode
    ) {
        self.titleBarStyle = titleBarStyle
        self.navigationPlacement = navigationPlacement
        self.paneTogglePlacement = paneTogglePlacement
        self.searchPlacement = searchPlacement
        self.backdrop = backdrop
        self.contentCornerStyle = contentCornerStyle
        self.titleBarHeight = titleBarHeight
    }
}

public struct FluentWindowShell<ID: Hashable>: FluentView {
    private let configuration: FluentWindowConfiguration
    private let title: String
    private let subtitle: String?
    private let systemImageName: String?
    private let isBackButtonVisible: Bool
    private let isBackButtonEnabled: Bool
    private let isForwardButtonVisible: Bool
    private let isForwardButtonEnabled: Bool
    private let onBack: (() -> Void)?
    private let onForward: (() -> Void)?
    private let items: [FluentNavigationItem<ID>]
    private let footerItems: [FluentNavigationItem<ID>]
    private let selection: FluentBinding<ID?>
    private let isPaneOpen: FluentBinding<Bool>?
    private let openPaneLength: CGFloat
    private let compactPaneLength: CGFloat
    private let rowHeight: CGFloat
    private let paneSectionTitle: String?
    private let titleBarContent: FluentAnyView?
    private let paneHeader: FluentAnyView?
    private let header: FluentAnyView
    private let content: FluentAnyView

    public init<Header: FluentView, Content: FluentView>(
        configuration: FluentWindowConfiguration,
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        isBackButtonVisible: Bool = false,
        isBackButtonEnabled: Bool = true,
        isForwardButtonVisible: Bool = false,
        isForwardButtonEnabled: Bool = true,
        onBack: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        items: [FluentNavigationItem<ID>] = [],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        @FluentViewBuilder header: () -> Header,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            configuration: configuration,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            onBack: onBack,
            onForward: onForward,
            items: items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            titleBarContent: nil,
            paneHeader: nil,
            header: FluentAnyView(header()),
            content: FluentAnyView(content())
        )
    }

    public init<TitleBarContent: FluentView, Header: FluentView, Content: FluentView>(
        configuration: FluentWindowConfiguration,
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        isBackButtonVisible: Bool = false,
        isBackButtonEnabled: Bool = true,
        isForwardButtonVisible: Bool = false,
        isForwardButtonEnabled: Bool = true,
        onBack: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        items: [FluentNavigationItem<ID>] = [],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        @FluentViewBuilder titleBarContent: () -> TitleBarContent,
        @FluentViewBuilder header: () -> Header,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            configuration: configuration,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            onBack: onBack,
            onForward: onForward,
            items: items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            titleBarContent: FluentAnyView(titleBarContent()),
            paneHeader: nil,
            header: FluentAnyView(header()),
            content: FluentAnyView(content())
        )
    }

    public init<PaneHeader: FluentView, Header: FluentView, Content: FluentView>(
        configuration: FluentWindowConfiguration,
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        isBackButtonVisible: Bool = false,
        isBackButtonEnabled: Bool = true,
        isForwardButtonVisible: Bool = false,
        isForwardButtonEnabled: Bool = true,
        onBack: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        items: [FluentNavigationItem<ID>] = [],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        @FluentViewBuilder paneHeader: () -> PaneHeader,
        @FluentViewBuilder header: () -> Header,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            configuration: configuration,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            onBack: onBack,
            onForward: onForward,
            items: items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            titleBarContent: nil,
            paneHeader: FluentAnyView(paneHeader()),
            header: FluentAnyView(header()),
            content: FluentAnyView(content())
        )
    }

    public init<
        TitleBarContent: FluentView,
        PaneHeader: FluentView,
        Header: FluentView,
        Content: FluentView
    >(
        configuration: FluentWindowConfiguration,
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        isBackButtonVisible: Bool = false,
        isBackButtonEnabled: Bool = true,
        isForwardButtonVisible: Bool = false,
        isForwardButtonEnabled: Bool = true,
        onBack: (() -> Void)? = nil,
        onForward: (() -> Void)? = nil,
        items: [FluentNavigationItem<ID>] = [],
        footerItems: [FluentNavigationItem<ID>] = [],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>? = nil,
        openPaneLength: CGFloat = 320,
        compactPaneLength: CGFloat = 48,
        rowHeight: CGFloat = 40,
        paneSectionTitle: String? = nil,
        @FluentViewBuilder titleBarContent: () -> TitleBarContent,
        @FluentViewBuilder paneHeader: () -> PaneHeader,
        @FluentViewBuilder header: () -> Header,
        @FluentViewBuilder content: () -> Content
    ) {
        self.init(
            configuration: configuration,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            isBackButtonVisible: isBackButtonVisible,
            isBackButtonEnabled: isBackButtonEnabled,
            isForwardButtonVisible: isForwardButtonVisible,
            isForwardButtonEnabled: isForwardButtonEnabled,
            onBack: onBack,
            onForward: onForward,
            items: items,
            footerItems: footerItems,
            selection: selection,
            isPaneOpen: isPaneOpen,
            openPaneLength: openPaneLength,
            compactPaneLength: compactPaneLength,
            rowHeight: rowHeight,
            paneSectionTitle: paneSectionTitle,
            titleBarContent: FluentAnyView(titleBarContent()),
            paneHeader: FluentAnyView(paneHeader()),
            header: FluentAnyView(header()),
            content: FluentAnyView(content())
        )
    }

    private init(
        configuration: FluentWindowConfiguration,
        title: String,
        subtitle: String?,
        systemImageName: String?,
        isBackButtonVisible: Bool,
        isBackButtonEnabled: Bool,
        isForwardButtonVisible: Bool,
        isForwardButtonEnabled: Bool,
        onBack: (() -> Void)?,
        onForward: (() -> Void)?,
        items: [FluentNavigationItem<ID>],
        footerItems: [FluentNavigationItem<ID>],
        selection: FluentBinding<ID?>,
        isPaneOpen: FluentBinding<Bool>?,
        openPaneLength: CGFloat,
        compactPaneLength: CGFloat,
        rowHeight: CGFloat,
        paneSectionTitle: String?,
        titleBarContent: FluentAnyView?,
        paneHeader: FluentAnyView?,
        header: FluentAnyView,
        content: FluentAnyView
    ) {
        self.configuration = configuration
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.isBackButtonVisible = isBackButtonVisible
        self.isBackButtonEnabled = isBackButtonEnabled
        self.isForwardButtonVisible = isForwardButtonVisible
        self.isForwardButtonEnabled = isForwardButtonEnabled
        self.onBack = onBack
        self.onForward = onForward
        self.items = items
        self.footerItems = footerItems
        self.selection = selection
        self.isPaneOpen = isPaneOpen
        self.openPaneLength = openPaneLength
        self.compactPaneLength = compactPaneLength
        self.rowHeight = rowHeight
        self.paneSectionTitle = paneSectionTitle
        self.titleBarContent = titleBarContent
        self.paneHeader = paneHeader
        self.header = header
        self.content = content
    }

    public var body: FluentAnyView {
        let shellContent = contentTree()
        switch configuration.backdrop {
        case .solid:
            return FluentAnyView(FluentWindowSolidSurface(content: shellContent))
        case .mica, .liquidGlass:
            return FluentAnyView(
                FluentMaterialSurface(
                    role: .window,
                    material: .mica,
                    cornerRadius: 0,
                    showsBorder: false
                ) {
                    FluentWindowSharedChrome(content: shellContent)
                }
            )
        }
    }

    private func contentTree() -> FluentAnyView {
        let navigation = navigationContent()
        guard configuration.titleBarStyle == .extended else { return navigation }
        return FluentAnyView(
            FluentVStack(spacing: 0, alignment: .width) {
                titleBar()
                navigation
            }
        )
    }

    private func titleBar() -> FluentAnyView {
        let showsToggle = configuration.paneTogglePlacement == .titleBar
            && configuration.navigationPlacement != .none
            && configuration.navigationPlacement != .top
        guard configuration.searchPlacement == .titleBar, let titleBarContent else {
            return FluentAnyView(
                FluentTitleBar(
                    title: title,
                    subtitle: subtitle,
                    systemImageName: systemImageName,
                    heightMode: configuration.titleBarHeight,
                    backgroundStyle: .transparent,
                    isBackButtonVisible: isBackButtonVisible,
                    isBackButtonEnabled: isBackButtonEnabled,
                    isForwardButtonVisible: isForwardButtonVisible,
                    isForwardButtonEnabled: isForwardButtonEnabled,
                    isPaneToggleButtonVisible: showsToggle,
                    isPaneOpen: isPaneOpen,
                    onBack: onBack,
                    onForward: onForward
                )
            )
        }
        return FluentAnyView(
            FluentTitleBar(
                title: title,
                subtitle: subtitle,
                systemImageName: systemImageName,
                heightMode: configuration.titleBarHeight,
                backgroundStyle: .transparent,
                isBackButtonVisible: isBackButtonVisible,
                isBackButtonEnabled: isBackButtonEnabled,
                isForwardButtonVisible: isForwardButtonVisible,
                isForwardButtonEnabled: isForwardButtonEnabled,
                isPaneToggleButtonVisible: showsToggle,
                isPaneOpen: isPaneOpen,
                onBack: onBack,
                onForward: onForward,
                leftHeader: { FluentEmptyView() },
                content: { titleBarContent },
                rightHeader: { FluentEmptyView() }
            )
        )
    }

    private func navigationContent() -> FluentAnyView {
        guard let paneDisplayMode = configuration.navigationPlacement.paneDisplayMode else {
            return FluentAnyView(
                FluentWindowContentSurface(cornerStyle: configuration.contentCornerStyle) {
                    FluentWindowPageLayout(header: header, content: content)
                }
            )
        }
        let showsPaneToggle = configuration.paneTogglePlacement == .navigationPane
            && paneDisplayMode != .top
        return FluentAnyView(
            FluentNavigationView(
                items,
                footerItems: footerItems,
                selection: selection,
                isPaneOpen: isPaneOpen,
                paneDisplayMode: paneDisplayMode,
                isPaneToggleButtonVisible: showsPaneToggle,
                openPaneLength: openPaneLength,
                compactPaneLength: compactPaneLength,
                rowHeight: rowHeight,
                paneSectionTitle: paneSectionTitle,
                contentTransition: configuration.contentTransition,
                paneMaterialOwnership: .inherited,
                paneHeader: { paneHeader ?? FluentAnyView(FluentEmptyView()) },
                // Keep the page header outside NavigationView's transition presenter. The
                // presenter then moves only the viewport below it, while this surface owns the
                // shell's leading corner and remains visually fixed during navigation.
                header: {
                    FluentWindowContentSurface(cornerStyle: configuration.contentCornerStyle) {
                        header
                    }
                },
                content: {
                    FluentWindowContentSurface(cornerStyle: .none) {
                        content
                    }
                }
            )
        )
    }
}

private struct FluentWindowSharedChrome: FluentUpdatablePrimitiveView {
    let content: FluentAnyView

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        FluentWindowSharedChromeHost(content: content, context: context)
    }

    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentWindowSharedChromeHost else { return false }
        host.update(content: content, context: context)
        return true
    }
}

private struct FluentWindowSolidSurface: FluentUpdatablePrimitiveView {
    let content: FluentAnyView

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        FluentWindowSolidSurfaceHost(content: content, context: context)
    }

    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentWindowSolidSurfaceHost else { return false }
        host.update(content: content, context: context)
        return true
    }
}

private final class FluentWindowSolidSurfaceHost: NSView {
    private let contentHost: FluentViewHost<FluentAnyView>

    init(content: FluentAnyView, context: FluentRenderContext) {
        contentHost = FluentViewHost(content, context: context)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.WindowShell.SolidSurface")
        wantsLayer = true
        addSubview(contentHost)
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        apply(theme: context.theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        contentHost.context = context
        contentHost.update(content)
        apply(theme: context.theme)
    }

    private func apply(theme: FluentTheme) {
        layer?.backgroundColor = theme.windowBackground.cgColor
    }
}

private final class FluentWindowSharedChromeHost: NSView {
    private let contentHost: FluentViewHost<FluentAnyView>
    private let tintLayer = CALayer()
    private let tintMaskLayer = CAShapeLayer()
    private var context: FluentRenderContext
    private var windowObservers: [NSObjectProtocol] = []
    private var displayOptionsObserver: NSObjectProtocol?
    private var isWindowActive = true

    override var isFlipped: Bool { true }

    init(content: FluentAnyView, context: FluentRenderContext) {
        contentHost = FluentViewHost(content, context: context)
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.WindowShell.SharedChromeHost")
        wantsLayer = true
        tintLayer.name = "FluentKit.WindowShell.SharedChromeTint"
        tintMaskLayer.fillRule = .evenOdd
        tintLayer.mask = tintMaskLayer
        layer?.addSublayer(tintLayer)
        addSubview(contentHost)
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installDisplayOptionsObserver()
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isWindowActive = window?.isKeyWindow ?? true
        installWindowObservers()
        applyAppearance()
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        updateTintMask()
    }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        self.context = context
        contentHost.context = context
        contentHost.update(content)
        applyAppearance()
        needsLayout = true
    }

    fileprivate func contentSurfaceGeometryDidChange() {
        updateTintMask()
    }

    private func applyAppearance() {
        tintLayer.backgroundColor = context.theme.windowChromeTint.cgColor
        tintLayer.opacity = isWindowActive ? 1 : 0.78
        tintLayer.isHidden = !context.theme.materialEffectsEnabled
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private func updateTintMask() {
        let surfaces = contentSurfaces(in: contentHost)
        guard !surfaces.isEmpty else {
            tintMaskLayer.path = nil
            return
        }
        let path = CGMutablePath()
        path.addRect(bounds)
        for surface in surfaces {
            guard let contentPath = surface.clipPath(convertedTo: self) else { continue }
            path.addPath(contentPath)
        }
        tintMaskLayer.frame = bounds
        tintMaskLayer.path = path
    }

    private func contentSurfaces(in view: NSView) -> [FluentWindowContentSurfaceHost] {
        let current = (view as? FluentWindowContentSurfaceHost).map { [$0] } ?? []
        return current + view.subviews.flatMap(contentSurfaces)
    }

    private func installWindowObservers() {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        guard let window else { return }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
                [weak self] _ in
                self?.isWindowActive = true
                self?.applyAppearance()
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) {
                [weak self] _ in
                self?.isWindowActive = false
                self?.applyAppearance()
            }
        ]
    }

    private func installDisplayOptionsObserver() {
        displayOptionsObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in self?.applyAppearance() }
    }

    deinit {
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let displayOptionsObserver { NotificationCenter.default.removeObserver(displayOptionsObserver) }
    }
}

private struct FluentWindowPageLayout: FluentUpdatablePrimitiveView {
    let header: FluentAnyView
    let content: FluentAnyView

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        FluentWindowPageLayoutHost(header: header, content: content, context: context)
    }

    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentWindowPageLayoutHost else { return false }
        host.update(header: header, content: content, context: context)
        return true
    }
}

private final class FluentWindowPageLayoutHost: NSView {
    private let headerHost: FluentViewHost<FluentAnyView>
    private let contentHost: FluentViewHost<FluentAnyView>

    override var isFlipped: Bool { true }

    init(header: FluentAnyView, content: FluentAnyView, context: FluentRenderContext) {
        headerHost = FluentViewHost(header, context: context)
        contentHost = FluentViewHost(content, context: context)
        super.init(frame: .zero)

        headerHost.setContentHuggingPriority(.required, for: .vertical)
        headerHost.setContentCompressionResistancePriority(.required, for: .vertical)
        contentHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentHost.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        addSubview(headerHost)
        addSubview(contentHost)
        headerHost.translatesAutoresizingMaskIntoConstraints = false
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerHost.topAnchor.constraint(equalTo: topAnchor),
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: headerHost.bottomAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(header: FluentAnyView, content: FluentAnyView, context: FluentRenderContext) {
        headerHost.context = context
        contentHost.context = context
        headerHost.update(header)
        contentHost.update(content)
    }
}

private struct FluentWindowContentSurface<Content: FluentView>: FluentUpdatablePrimitiveView {
    let cornerStyle: FluentContentCornerStyle
    let content: Content

    init(cornerStyle: FluentContentCornerStyle, @FluentViewBuilder content: () -> Content) {
        self.cornerStyle = cornerStyle
        self.content = content()
    }

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        FluentWindowContentSurfaceHost(
            content: FluentViewHost(FluentAnyView(content), context: context),
            cornerStyle: cornerStyle,
            context: context
        )
    }

    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentWindowContentSurfaceHost else { return false }
        host.update(content: FluentAnyView(content), cornerStyle: cornerStyle, context: context)
        return true
    }
}

private final class FluentWindowContentSurfaceHost: NSView {
    private let contentHost: FluentViewHost<FluentAnyView>
    private let contentClipMask = CAShapeLayer()
    private var cornerStyle: FluentContentCornerStyle
    private var context: FluentRenderContext

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { contentHost.fittingSize }

    init(
        content: FluentViewHost<FluentAnyView>,
        cornerStyle: FluentContentCornerStyle,
        context: FluentRenderContext
    ) {
        contentHost = content
        self.cornerStyle = cornerStyle
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.WindowShell.ContentSurface")
        wantsLayer = true
        contentClipMask.name = "FluentKit.WindowShell.ContentSurfaceClip"
        contentClipMask.fillColor = NSColor.black.cgColor
        layer?.mask = contentClipMask
        addSubview(contentHost)
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        applyCornerGeometry()
        notifySharedChromeGeometryChanged()
    }

    func update(
        content: FluentAnyView,
        cornerStyle: FluentContentCornerStyle,
        context: FluentRenderContext
    ) {
        self.cornerStyle = cornerStyle
        self.context = context
        contentHost.context = context
        contentHost.update(content)
        applyAppearance()
        applyCornerGeometry()
    }

    private func applyAppearance() {
        layer?.backgroundColor = context.theme.layerFill.cgColor
    }

    private func applyCornerGeometry() {
        guard let layer else { return }
        let radius = cornerStyle == .none
            ? 0
            : min(context.theme.cardCornerRadius, bounds.width / 2, bounds.height / 2)
        let clipPath = fluentWindowContentSurfacePath(
            in: bounds,
            radius: radius,
            cornerStyle: cornerStyle,
            layoutDirection: context.layoutDirection,
            visualYAxis: .resolved(for: layer, fallbackView: self)
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = 0
        contentClipMask.frame = bounds
        contentClipMask.path = clipPath
        CATransaction.commit()
    }

    fileprivate func clipPath(convertedTo target: NSView) -> CGPath? {
        guard let path = contentClipMask.path, bounds.width > 0, bounds.height > 0 else { return nil }
        let sourceMin = bounds.origin
        let sourceMax = CGPoint(x: bounds.maxX, y: bounds.maxY)
        let targetMin = convert(sourceMin, to: target)
        let targetMax = convert(sourceMax, to: target)
        var transform = CGAffineTransform(
            a: (targetMax.x - targetMin.x) / bounds.width,
            b: 0,
            c: 0,
            d: (targetMax.y - targetMin.y) / bounds.height,
            tx: targetMin.x - sourceMin.x * ((targetMax.x - targetMin.x) / bounds.width),
            ty: targetMin.y - sourceMin.y * ((targetMax.y - targetMin.y) / bounds.height)
        )
        return path.copy(using: &transform)
    }

    private func notifySharedChromeGeometryChanged() {
        var ancestor = superview
        while let view = ancestor {
            if let chrome = view as? FluentWindowSharedChromeHost {
                chrome.contentSurfaceGeometryDidChange()
                return
            }
            ancestor = view.superview
        }
    }
}
