import AppKit
import CoreImage

public enum FluentMaterialBackend: String, Hashable, Sendable {
    case nativeGlass
    /// WinUI blend stages over cached wallpaper (Mica) or AppKit's live blur (Acrylic).
    case fluentRecipe
    case visualEffect
    case opaque
}

public final class FluentMaterialView: NSVisualEffectView {
    /// Keeps AppKit's native effect in the same light/dark appearance as the Fluent theme.
    /// Fluent controls may switch scheme without replacing the host window, so relying only on
    /// `effectiveAppearance` would leave a dark Fluent pane rendered with a light glass recipe.
    public var fluentTheme: FluentTheme? {
        didSet {
            guard oldValue != fluentTheme, !isApplyingConfiguration else { return }
            if configurationBinding != nil { resolveConfiguration() }
            else { applyThemeAppearance(); applyMaterial() }
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
        didSet {
            if !isApplyingConfiguration {
                hasExplicitFallbackColor = true
                applySurfaceColor()
            }
        }
    }
    private var hasExplicitFallbackColor = false

    public var tintColor: NSColor? {
        didSet {
            if !isApplyingConfiguration { applyResolvedTint(); applyMaterial() }
        }
    }

    public var tintOpacity: CGFloat? {
        didSet { if oldValue != tintOpacity, !isApplyingConfiguration { applyMaterial() } }
    }
    public var luminosityOpacity: CGFloat? {
        didSet { if oldValue != luminosityOpacity, !isApplyingConfiguration { applyMaterial() } }
    }

    /// Sampling scope used by visual-effect backends. System Glass manages its own sampling.
    public var preferredBlendingMode: NSVisualEffectView.BlendingMode = .behindWindow {
        didSet { if oldValue != preferredBlendingMode { applyMaterial() } }
    }

    private struct ConfigurationBinding {
        let role: FluentMaterialRole
        let preset: FluentMaterialConfiguration
        let override: FluentMaterialConfiguration?
        let fallback: ((FluentTheme) -> NSColor)?
    }
    private var configurationBinding: ConfigurationBinding?
    private var isApplyingConfiguration = false

    /// Apply a control preset, theme role, and local override, in that order. Reapplying the
    /// theme preserves this binding and content identity. Accessibility fallbacks take priority.
    public func configure(theme: FluentTheme, role: FluentMaterialRole,
        preset: FluentMaterialConfiguration = .init(),
        configuration: FluentMaterialConfiguration? = nil,
        fallback: ((FluentTheme) -> NSColor)? = nil
    ) {
        configurationBinding = ConfigurationBinding(role: role, preset: preset, override: configuration, fallback: fallback)
        isApplyingConfiguration = true
        fluentTheme = theme
        isApplyingConfiguration = false
        resolveConfiguration()
    }

    var hasConfigurationBinding: Bool { configurationBinding != nil }

    private func resolveConfiguration() {
        guard let binding = configurationBinding else { return }
        let theme = fluentTheme ?? .current
        let resolved = theme.resolvedMaterialConfiguration(for: binding.role, preset: binding.preset, override: binding.override)
        isApplyingConfiguration = true
        materialStyle = resolved.material ?? .mica
        isMaterialEnabled = theme.materialEffectsEnabled && resolved.isEnabled != false
        fallbackColor = resolved.fallbackColor ?? binding.fallback?(theme) ?? binding.role.fallback(in: theme)
        tintColor = resolved.tintColor
        tintOpacity = resolved.tintOpacity
        luminosityOpacity = resolved.luminosityOpacity
        preferredBlendingMode = resolved.blendingMode ?? binding.role.defaultBlendingMode
        isApplyingConfiguration = false
        applyThemeAppearance()
        applyMaterial()
    }

    public private(set) var resolvedBackend: FluentMaterialBackend = .visualEffect
    public static var isNativeGlassAvailable: Bool {
        NSClassFromString("NSGlassEffectView") is NSView.Type
    }

    public static var isNativeLiquidGlassAvailable: Bool {
        isNativeGlassAvailable
    }

    private let fallbackLayer = CALayer()
    // Inserted after the fallback and before content. A positive zPosition paints tint over
    // descendants in WindowServer composition, even when CALayer.render looks unaffected.
    private let tintLayer = CALayer()
    private let luminosityLayer = CALayer()
    private let noiseLayer = FluentMaterialNoiseLayer()
    private let colorBlend = CIFilter(name: "CIColorBlendMode")
    private let luminosityBlend = CIFilter(name: "CILuminosityBlendMode")
    private var appliedRecipe: FluentMaterialRecipe?
    private var wallpaperLayers: [NSScreen: CALayer] = [:]
    /// False while the wallpaper is unavailable, loading, or the window is inactive.
    public private(set) var hasWallpaperBackdrop = false
    private var isApplyingMaterial = false
    private var glassBackendView: NSView?
    private var displayOptionsObserver: NSObjectProtocol?
    private var activeWindowObservers: [NSObjectProtocol] = []

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
        tintLayer.zPosition = 0
        tintLayer.name = "FluentKit.Material.MicaTint"
        layer?.addSublayer(fallbackLayer)
        layer?.addSublayer(tintLayer)
        installRecipeLayers()
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
        tintLayer.zPosition = 0
        tintLayer.name = "FluentKit.Material.MicaTint"
        layer?.addSublayer(fallbackLayer)
        layer?.addSublayer(tintLayer)
        installRecipeLayers()
        installDisplayOptionsObserver()
        applyMaterial()
    }

    required init?(coder: NSCoder) {
        self.materialStyle = .mica
        super.init(coder: coder)
        wantsLayer = true
        fallbackLayer.zPosition = 0
        fallbackLayer.name = "FluentKit.Material.OpaqueFallback"
        tintLayer.zPosition = 0
        tintLayer.name = "FluentKit.Material.MicaTint"
        layer?.addSublayer(fallbackLayer)
        layer?.addSublayer(tintLayer)
        installRecipeLayers()
        installDisplayOptionsObserver()
        applyMaterial()
    }

    public override func layout() {
        super.layout()
        // Window zoom already animates the containing view. A second implicit bounds/position
        // animation on these layers exposes AppKit's backing color at the growing edges.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.frame = bounds
        tintLayer.frame = bounds
        luminosityLayer.frame = bounds
        noiseLayer.frame = bounds
        let hadWallpaper = hasWallpaperBackdrop
        updateWallpaperBackdrop(enabled: resolvedBackend == .fluentRecipe && resolvedMaterialStyle == .mica)
        updateWallpaperLayerFrames()
        if hadWallpaper != hasWallpaperBackdrop { applyMaterial() }
        glassBackendView?.frame = bounds
        synchronizeGlassCornerRadius()
        CATransaction.commit()
    }

    private func installRecipeLayers() {
        layerUsesCoreImageFilters = true
        fallbackLayer.masksToBounds = true
        luminosityLayer.name = "FluentKit.Material.Luminosity"
        luminosityLayer.compositingFilter = luminosityBlend
        noiseLayer.name = "FluentKit.Material.Noise"
        layer?.insertSublayer(luminosityLayer, below: tintLayer)
        layer?.insertSublayer(noiseLayer, above: tintLayer)
    }

    private func applyMaterial() {
        guard !isApplyingMaterial, !isApplyingConfiguration else { return }
        isApplyingMaterial = true
        defer { isApplyingMaterial = false }
        let style = resolvedMaterialStyle
        let usesOpaqueFallback = !isMaterialEnabled
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || (fluentTheme?.isHighContrast ?? false)
        let usesNativeGlass = !usesOpaqueFallback
            && style == .liquidGlass
            && Self.isNativeGlassAvailable
        let usesFluentRecipe = !usesOpaqueFallback && (style == .mica || style == .acrylic)
        resolvedBackend = usesOpaqueFallback
            ? .opaque
            : (usesFluentRecipe ? .fluentRecipe : (usesNativeGlass ? .nativeGlass : .visualEffect))
        applySurfaceColor()
        updateWallpaperBackdrop(enabled: usesFluentRecipe && style == .mica)
        fallbackLayer.opacity = usesOpaqueFallback || (usesFluentRecipe && style == .mica) ? 1 : 0
        let glassView = usesNativeGlass ? resolveGlassBackendView() : glassBackendView
        glassView?.isHidden = !usesNativeGlass
        glassView?.frame = bounds
        applyResolvedTint()
        let usesInertEffect = usesNativeGlass || usesOpaqueFallback || (usesFluentRecipe && style == .mica)
        let nextBlendingMode: NSVisualEffectView.BlendingMode = usesInertEffect ? .withinWindow : preferredBlendingMode
        let nextMaterial: NSVisualEffectView.Material
        if usesInertEffect { nextMaterial = .contentBackground }
        else {
            nextMaterial = switch style {
            case .automatic, .mica, .nativeMica: .underWindowBackground
            case .acrylic, .nativeAcrylic: .hudWindow
            case .liquidGlass: .popover
            case .sidebar: .sidebar
            }
        }
        // Resolve once: briefly switching an opaque/Glass surface to a live AppKit material
        // and straight back rebuilds the native effect on every ordinary content update.
        if blendingMode != nextBlendingMode { blendingMode = nextBlendingMode }
        if material != nextMaterial { material = nextMaterial }
        let drawsRecipe = usesFluentRecipe && (style == .acrylic || hasWallpaperBackdrop)
        luminosityLayer.isHidden = !drawsRecipe
        noiseLayer.isHidden = !drawsRecipe || style != .acrylic
        tintLayer.isHidden = usesOpaqueFallback || (usesFluentRecipe && !drawsRecipe) || usesNativeGlass || style == .liquidGlass
        // Nonactivating menu panels keep the editor in their owner window. Their blur must
        // follow that owner, rather than treating the panel's lack of key status as inactive.
        let effectState: NSVisualEffectView.State = usesFluentRecipe && style == .acrylic
            ? (isBackdropActive ? .active : .inactive) : .followsWindowActiveState
        if state != effectState { state = effectState }

    }

    private func applySurfaceColor() {
        if resolvedBackend == .fluentRecipe {
            let dark = (fluentTheme ?? .current).isDark
            let component: CGFloat = resolvedMaterialStyle == .mica
                ? (dark ? 32 : 243)
                : (dark ? 44 : 252)
            fallbackLayer.backgroundColor = configurationBinding != nil || hasExplicitFallbackColor
                ? opaqueFallbackColor(fallbackColor)
                : NSColor(srgbRed: component / 255, green: component / 255, blue: component / 255, alpha: 1).cgColor
        } else {
            let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || (fluentTheme?.isHighContrast ?? false)
            let color: NSColor
            if highContrast {
                let theme = (fluentTheme ?? .current).with(contrast: .high)
                let role = configurationBinding?.role ?? .transient
                color = role.fallback(in: theme)
            } else { color = fallbackColor }
            fallbackLayer.backgroundColor = resolvedBackend == .opaque ? opaqueFallbackColor(color) : resolvedCGColor(color)
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activeWindowObservers.forEach(NotificationCenter.default.removeObserver)
        activeWindowObservers.removeAll()
        if window != nil {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification,
                         NSWindow.didChangeBackingPropertiesNotification, NSWindow.didChangeOcclusionStateNotification] {
                // A child panel can be attached to its parent after this view is mounted.
                activeWindowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self, let changed = note.object as? NSWindow,
                          self.isBackdropOwner(changed) else { return }
                    self.applyMaterial()
                })
            }
        }
        applyMaterial()
    }

    private var isBackdropActive: Bool {
        guard window != nil else { return true }
        var owner = window
        while let current = owner {
            if current.isKeyWindow { return true }
            owner = current.parent
        }
        return false
    }

    private func isBackdropOwner(_ candidate: NSWindow) -> Bool {
        var owner = window
        while let current = owner {
            if current === candidate { return true }
            owner = current.parent
        }
        return false
    }

    func wallpaperBackdropDidChange() {
        guard resolvedBackend == .fluentRecipe, resolvedMaterialStyle == .mica else { return }
        applyMaterial()
    }

    private func updateWallpaperBackdrop(enabled: Bool) {
        let source = FluentWallpaperBackdrop.shared
        guard enabled, isBackdropActive, let window else {
            source.unsubscribe(self)
            wallpaperLayers.values.forEach { $0.removeFromSuperlayer() }
            wallpaperLayers.removeAll()
            hasWallpaperBackdrop = false
            return
        }
        source.subscribe(self)
        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        let screens = NSScreen.screens.filter { $0.frame.intersects(screenRect) }
        let available = !screens.isEmpty && screens.allSatisfy { source.image(for: $0) != nil }
        for screen in Array(wallpaperLayers.keys) where !available || !screens.contains(screen) {
            wallpaperLayers.removeValue(forKey: screen)?.removeFromSuperlayer()
        }
        hasWallpaperBackdrop = available
        guard available else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for screen in screens {
            let backdrop = wallpaperLayers[screen] ?? CALayer()
            if backdrop.superlayer == nil { fallbackLayer.addSublayer(backdrop) }
            backdrop.name = "FluentKit.Material.Wallpaper"
            let image = source.image(for: screen)
            if (backdrop.contents as AnyObject?) !== image { backdrop.contents = image }
            wallpaperLayers[screen] = backdrop
        }
        updateWallpaperLayerFrames()
        CATransaction.commit()
    }

    private func updateWallpaperLayerFrames() {
        guard let window else { return }
        for (screen, backdrop) in wallpaperLayers {
            backdrop.frame = convert(window.convertFromScreen(screen.frame), from: nil)
        }
        let scale = window.backingScaleFactor
        if noiseLayer.contentsScale != scale {
            noiseLayer.contentsScale = scale
            noiseLayer.setNeedsDisplay()
        }
    }

    private var resolvedMaterialStyle: FluentMaterial {
        materialStyle == .automatic
            ? ((fluentTheme ?? .current).resolvedMaterialConfiguration(for: .window).material ?? .mica)
            : materialStyle
    }

    private var resolvedTintColor: NSColor? {
        if let tintColor { return tintColor }
        guard resolvedMaterialStyle == .mica || resolvedMaterialStyle == .nativeMica else { return nil }
        return (fluentTheme ?? .current).micaTint
    }

    private func applyResolvedTint() {
        if resolvedBackend == .fluentRecipe {
            let recipe = FluentMaterialRecipe(material: resolvedMaterialStyle, dark: (fluentTheme ?? .current).isDark,
                tint: tintColor, tintOpacity: tintOpacity, luminosityOpacity: luminosityOpacity)
            if appliedRecipe != recipe {
                appliedRecipe = recipe
                tintLayer.compositingFilter = colorBlend
                let alpha = recipe.color.alphaComponent
                tintLayer.backgroundColor = resolvedCGColor(recipe.color.withAlphaComponent(alpha * recipe.tintOpacity))
                luminosityLayer.backgroundColor = resolvedCGColor(recipe.color.withAlphaComponent(alpha * recipe.luminosityOpacity))
                noiseLayer.opacity = recipe.noiseOpacity
                noiseLayer.setNeedsDisplay()
            }
            return
        }
        appliedRecipe = nil
        tintLayer.compositingFilter = nil
        let color = resolvedTintColor
        tintLayer.backgroundColor = color.map(resolvedCGColor)
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
        synchronizeGlassCornerRadius()
        applyResolvedTint()
        return view
    }

    private func synchronizeGlassCornerRadius() {
        guard let glassBackendView else { return }
        let radius = layer?.cornerRadius ?? 0
        if (glassBackendView.value(forKey: "cornerRadius") as? NSNumber)?.doubleValue != Double(radius) {
            glassBackendView.setValue(radius, forKey: "cornerRadius")
        }
    }

    private func installDisplayOptionsObserver() {
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in self?.applyMaterial() }
    }

    private func applyThemeAppearance() {
        appearance = fluentTheme.flatMap { fluentAppKitAppearance(for: $0) }
    }

    private func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private func opaqueFallbackColor(_ color: NSColor) -> CGColor {
        let resolved = resolvedCGColor(color)
        guard resolved.alpha < 1 else { return resolved }
        let base = resolvedCGColor((fluentTheme ?? .current).windowBackground)
        guard resolved.alpha > 0 else { return base.copy(alpha: 1) ?? base }
        let foreground = NSColor(cgColor: resolved)?.usingColorSpace(.sRGB) ?? .black
        let background = NSColor(cgColor: base)?.usingColorSpace(.sRGB) ?? .black
        let alpha = foreground.alphaComponent
        // Preserve one color space through blending and construction. Reinterpreting device
        // components as calibrated RGB changes the shade again, even for a clear override.
        return NSColor(srgbRed: foreground.redComponent * alpha + background.redComponent * (1 - alpha),
            green: foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
            blue: foreground.blueComponent * alpha + background.blueComponent * (1 - alpha), alpha: 1).cgColor
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // NSVisualEffectView re-evaluates its native material automatically when appearance
        // changes. Reassigning `material` from this callback re-enters AppKit's material-change
        // notification and can recurse until the stack guard is hit. Theme updates still call
        // `applyMaterial()` through the explicit properties above.
        fluentNotifyAppearanceCoordinator(from: self)
        applySurfaceColor()
        applyResolvedTint()
        needsDisplay = true
    }

    deinit {
        FluentWallpaperBackdrop.shared.unsubscribe(self)
        activeWindowObservers.forEach(NotificationCenter.default.removeObserver)
        if let displayOptionsObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver) }
    }
}

/// A declarative Fluent surface backed by the native material view. This is useful for cards,
/// teaching surfaces, and other content that should participate in the application-wide material
/// switch without replacing its content host.
public struct FluentMaterialSurface<Content: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let role: FluentMaterialRole
    private let materialOverride: FluentMaterial?
    private let configuration: FluentMaterialConfiguration?
    private let preset: FluentMaterialConfiguration
    private let cornerRadius: CGFloat
    private let showsBorder: Bool

    public init(
        role: FluentMaterialRole = .transient,
        material: FluentMaterial? = nil,
        configuration: FluentMaterialConfiguration? = nil,
        preset: FluentMaterialConfiguration = .init(),
        cornerRadius: CGFloat = 8,
        showsBorder: Bool = true,
        @FluentViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.role = role
        materialOverride = material
        self.configuration = configuration
        self.preset = preset
        self.cornerRadius = max(cornerRadius, 0)
        self.showsBorder = showsBorder
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentMaterialSurfaceHost(
            content: FluentViewHost(FluentAnyView(content), context: context),
            role: role,
            materialOverride: materialOverride,
            configuration: configuration,
            preset: preset,
            cornerRadius: cornerRadius,
            showsBorder: showsBorder,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentMaterialSurfaceHost else { return false }
        host.update(content: FluentAnyView(content), role: role, materialOverride: materialOverride,
                    configuration: configuration, preset: preset, cornerRadius: cornerRadius, showsBorder: showsBorder, context: context)
        return true
    }
}

private final class FluentMaterialSurfaceHost: NSView {
    private let material: FluentMaterialView
    private let contentHost: FluentViewHost<FluentAnyView>
    private var role: FluentMaterialRole
    private var materialOverride: FluentMaterial?
    private var configuration: FluentMaterialConfiguration?
    private var preset: FluentMaterialConfiguration
    private var cornerRadius: CGFloat
    private var showsBorder: Bool

    init(
        content: FluentViewHost<FluentAnyView>,
        role: FluentMaterialRole,
        materialOverride: FluentMaterial?,
        configuration: FluentMaterialConfiguration?,
        preset: FluentMaterialConfiguration,
        cornerRadius: CGFloat,
        showsBorder: Bool,
        context: FluentRenderContext
    ) {
        self.contentHost = content
        self.role = role
        self.materialOverride = materialOverride
        self.configuration = configuration
        self.preset = preset
        self.cornerRadius = cornerRadius
        self.showsBorder = showsBorder
        let local = FluentMaterialConfiguration(material: materialOverride).merging(configuration)
        material = FluentMaterialView(material: context.theme.resolvedMaterialConfiguration(
            for: role, preset: preset, override: local).material ?? .mica)
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

    func update(content: FluentAnyView, role: FluentMaterialRole, materialOverride: FluentMaterial?,
                configuration: FluentMaterialConfiguration?, preset: FluentMaterialConfiguration, cornerRadius: CGFloat, showsBorder: Bool,
                context: FluentRenderContext) {
        self.role = role
        self.materialOverride = materialOverride
        self.configuration = configuration
        self.preset = preset
        self.cornerRadius = cornerRadius
        self.showsBorder = showsBorder
        contentHost.update(content, context: context)
        apply(context: context)
        invalidateIntrinsicContentSize()
    }

    private func apply(context: FluentRenderContext) {
        let local = FluentMaterialConfiguration(material: materialOverride).merging(configuration)
        material.configure(theme: context.theme, role: role, preset: preset, configuration: local)
        material.layer?.cornerRadius = cornerRadius
        material.needsLayout = true
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = showsBorder ? (context.theme.isHighContrast ? 2 : 1) : 0
        material.layer?.borderColor = showsBorder ? context.theme.surfaceStrokeFlyout.cgColor : nil
    }
}

public extension FluentView {
    /// Adds a material behind transparent content without replacing the content host. Existing
    /// opaque control fills remain explicit; cards can choose material through their own API.
    func materialBackground(_ material: FluentMaterial? = nil,
        configuration: FluentMaterialConfiguration? = nil, role: FluentMaterialRole = .container,
        cornerRadius: CGFloat = 8, showsBorder: Bool = true
    ) -> FluentMaterialSurface<Self> {
        FluentMaterialSurface(role: role, material: material, configuration: configuration,
            cornerRadius: cornerRadius, showsBorder: showsBorder) { self }
    }
}
