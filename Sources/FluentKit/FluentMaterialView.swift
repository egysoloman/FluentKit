import AppKit

public enum FluentMaterialBackend: String, Hashable, Sendable {
    case nativeGlass
    case visualEffect
    case opaque
}

public final class FluentMaterialView: NSVisualEffectView {
    /// Keeps AppKit's native effect in the same light/dark appearance as the Fluent theme.
    /// Fluent controls may switch scheme without replacing the host window, so relying only on
    /// `effectiveAppearance` would leave a dark Fluent pane rendered with a light glass recipe.
    public var fluentTheme: FluentTheme? {
        didSet {
            guard oldValue != fluentTheme else { return }
            applyThemeAppearance()
            applyMaterial()
        }
    }

    public var materialStyle: FluentMaterial {
        didSet {
            guard oldValue != materialStyle else { return }
            applyMaterial()
        }
    }

    /// Allows an application theme to turn native material effects off without removing the
    /// surface from the hierarchy. The fallback layer keeps geometry and content stable.
    public var isMaterialEnabled = true {
        didSet {
            guard oldValue != isMaterialEnabled else { return }
            applyMaterial()
        }
    }

    public var fallbackColor: NSColor = .windowBackgroundColor {
        didSet { fallbackLayer.backgroundColor = fallbackColor.cgColor }
    }

    public var tintColor: NSColor? {
        didSet {
            applyResolvedTint()
        }
    }

    public private(set) var resolvedBackend: FluentMaterialBackend = .visualEffect
    public static var isNativeGlassAvailable: Bool {
        NSClassFromString("NSGlassEffectView") is NSView.Type
    }

    public static var isNativeLiquidGlassAvailable: Bool {
        isNativeGlassAvailable
    }

    private let fallbackLayer = CALayer()
    private let tintLayer = CALayer()
    private var isApplyingMaterial = false
    private var glassBackendView: NSView?
    private var displayOptionsObserver: NSObjectProtocol?

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public init(material: FluentMaterial = .mica) {
        self.materialStyle = material
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fallbackLayer.zPosition = 0
        fallbackLayer.name = "FluentKit.Material.OpaqueFallback"
        tintLayer.zPosition = 1
        tintLayer.name = "FluentKit.Material.MicaTint"
        layer?.addSublayer(fallbackLayer)
        layer?.addSublayer(tintLayer)
        installDisplayOptionsObserver()
        applyMaterial()
    }

    public override init(frame frameRect: NSRect) {
        self.materialStyle = .mica
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fallbackLayer.zPosition = 0
        fallbackLayer.name = "FluentKit.Material.OpaqueFallback"
        tintLayer.zPosition = 1
        tintLayer.name = "FluentKit.Material.MicaTint"
        layer?.addSublayer(fallbackLayer)
        layer?.addSublayer(tintLayer)
        installDisplayOptionsObserver()
        applyMaterial()
    }

    required init?(coder: NSCoder) {
        self.materialStyle = .mica
        super.init(coder: coder)
        wantsLayer = true
        fallbackLayer.zPosition = 0
        fallbackLayer.name = "FluentKit.Material.OpaqueFallback"
        tintLayer.zPosition = 1
        tintLayer.name = "FluentKit.Material.MicaTint"
        layer?.addSublayer(fallbackLayer)
        layer?.addSublayer(tintLayer)
        installDisplayOptionsObserver()
        applyMaterial()
    }

    public override func layout() {
        super.layout()
        fallbackLayer.frame = bounds
        tintLayer.frame = bounds
        glassBackendView?.frame = bounds
    }

    private func applyMaterial() {
        guard !isApplyingMaterial else { return }
        isApplyingMaterial = true
        defer { isApplyingMaterial = false }
        let usesOpaqueFallback = !isMaterialEnabled
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let usesNativeGlass = !usesOpaqueFallback
            && (materialStyle == .mica || materialStyle == .liquidGlass)
            && Self.isNativeGlassAvailable
        resolvedBackend = usesOpaqueFallback
            ? .opaque
            : (usesNativeGlass ? .nativeGlass : .visualEffect)
        fallbackLayer.backgroundColor = fallbackColor.cgColor
        fallbackLayer.opacity = usesOpaqueFallback ? 1 : 0
        let glassView = usesNativeGlass ? resolveGlassBackendView() : glassBackendView
        glassView?.isHidden = !usesNativeGlass
        glassView?.frame = bounds
        applyResolvedTint()
        blendingMode = .behindWindow
        material = switch materialStyle {
        case .mica: .underWindowBackground
        case .acrylic: .hudWindow
        case .liquidGlass: .popover
        case .sidebar: .sidebar
        }
        tintLayer.isHidden = usesOpaqueFallback || usesNativeGlass || materialStyle == .liquidGlass
        if usesNativeGlass || usesOpaqueFallback {
            // Keep the native view alive for content and accessibility, but make its effect
            // contribution inert while the glass or opaque backend owns the surface.
            blendingMode = .withinWindow
            material = .contentBackground
        }
        state = .followsWindowActiveState
    }

    private var resolvedTintColor: NSColor? {
        if let tintColor { return tintColor }
        guard materialStyle == .mica else { return nil }
        return (fluentTheme ?? .current).micaTint
    }

    private func applyResolvedTint() {
        let color = resolvedTintColor
        tintLayer.backgroundColor = color?.cgColor
        glassBackendView?.setValue(color, forKey: "tintColor")
    }

    private func resolveGlassBackendView() -> NSView? {
        if let glassBackendView { return glassBackendView }
        guard let viewType = NSClassFromString("NSGlassEffectView") as? NSView.Type else { return nil }
        let view = viewType.init(frame: bounds)
        view.identifier = NSUserInterfaceItemIdentifier("FluentKit.Material.NativeGlass")
        view.autoresizingMask = [.width, .height]
        view.setAccessibilityElement(false)
        addSubview(view, positioned: .below, relativeTo: subviews.first)
        glassBackendView = view
        applyResolvedTint()
        return view
    }

    private func installDisplayOptionsObserver() {
        displayOptionsObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in self?.applyMaterial() }
    }

    private func applyThemeAppearance() {
        appearance = fluentTheme.flatMap { fluentAppKitAppearance(for: $0) }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // NSVisualEffectView re-evaluates its native material automatically when appearance
        // changes. Reassigning `material` from this callback re-enters AppKit's material-change
        // notification and can recurse until the stack guard is hit. Theme updates still call
        // `applyMaterial()` through the explicit properties above.
        fluentNotifyAppearanceCoordinator(from: self)
        needsDisplay = true
    }

    deinit {
        if let displayOptionsObserver { NotificationCenter.default.removeObserver(displayOptionsObserver) }
    }
}

/// A declarative Fluent surface backed by the native material view. This is useful for cards,
/// teaching surfaces, and other content that should participate in the application-wide material
/// switch without replacing its content host.
public struct FluentMaterialSurface<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let role: FluentMaterialRole
    private let materialOverride: FluentMaterial?
    private let cornerRadius: CGFloat
    private let showsBorder: Bool

    public init(
        role: FluentMaterialRole = .transient,
        material: FluentMaterial? = nil,
        cornerRadius: CGFloat = 8,
        showsBorder: Bool = true,
        @FluentViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.role = role
        materialOverride = material
        self.cornerRadius = max(cornerRadius, 0)
        self.showsBorder = showsBorder
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentMaterialSurfaceHost(
            content: FluentViewHost(FluentAnyView(content), context: context),
            role: role,
            materialOverride: materialOverride,
            cornerRadius: cornerRadius,
            showsBorder: showsBorder,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentMaterialSurfaceHost else { return false }
        host.update(content: FluentAnyView(content), context: context)
        return true
    }
}

private final class FluentMaterialSurfaceHost: NSView {
    private let material: FluentMaterialView
    private let contentHost: FluentViewHost<FluentAnyView>
    private let role: FluentMaterialRole
    private let materialOverride: FluentMaterial?
    private let cornerRadius: CGFloat
    private let showsBorder: Bool

    init(
        content: FluentViewHost<FluentAnyView>,
        role: FluentMaterialRole,
        materialOverride: FluentMaterial?,
        cornerRadius: CGFloat,
        showsBorder: Bool,
        context: FluentRenderContext
    ) {
        self.contentHost = content
        self.role = role
        self.materialOverride = materialOverride
        self.cornerRadius = cornerRadius
        self.showsBorder = showsBorder
        material = FluentMaterialView(
            material: materialOverride ?? context.theme.material(for: role) ?? .liquidGlass
        )
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(
            role == .window ? "FluentKit.WindowShell.MaterialSurface" : "FluentKit.MaterialSurface"
        )
        material.identifier = NSUserInterfaceItemIdentifier(
            role == .window ? "FluentKit.WindowShell.Mica" : "FluentKit.MaterialSurface.Material"
        )
        wantsLayer = true
        material.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(contentHost)
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: material.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        apply(context: context)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { contentHost.fittingSize }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        contentHost.context = context
        contentHost.update(content)
        apply(context: context)
        invalidateIntrinsicContentSize()
    }

    private func apply(context: FluentRenderContext) {
        let materialStyle = materialOverride ?? context.theme.material(for: role) ?? .liquidGlass
        material.materialStyle = materialStyle
        material.fluentTheme = context.theme
        material.isMaterialEnabled = context.theme.materialEffectsEnabled
        material.fallbackColor = materialStyle == .mica
            ? context.theme.windowBackground
            : context.theme.flyoutSurfaceFill
        material.tintColor = materialStyle == .mica ? context.theme.micaTint : nil
        material.layer?.cornerRadius = cornerRadius
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = showsBorder ? (context.theme.isHighContrast ? 2 : 1) : 0
        material.layer?.borderColor = showsBorder ? context.theme.surfaceStrokeFlyout.cgColor : nil
    }
}
