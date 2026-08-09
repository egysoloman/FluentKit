import AppKit
import FluentKit
import Darwin
import UniformTypeIdentifiers

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func drainMainQueue() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
}

@discardableResult
func waitUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.005,
    _ condition: () -> Bool
) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    repeat {
        if condition() { return true }
        RunLoop.main.run(until: min(Date(timeIntervalSinceNow: pollInterval), deadline))
    } while Date() < deadline
    return condition()
}

func firstLabel(in view: NSView) -> NSTextField? {
    if let label = view as? NSTextField, !label.isEditable { return label }
    return view.subviews.lazy.compactMap(firstLabel).first
}

func firstButton(in view: NSView) -> FluentButton? {
    if let button = view as? FluentButton { return button }
    return view.subviews.lazy.compactMap(firstButton).first
}

func firstRepeatButton(in view: NSView) -> FluentRepeatButton? {
    if let button = view as? FluentRepeatButton { return button }
    return view.subviews.lazy.compactMap(firstRepeatButton).first
}

func firstNumberBox(in view: NSView) -> FluentNumberBoxControl? {
    if let numberBox = view as? FluentNumberBoxControl { return numberBox }
    return view.subviews.lazy.compactMap(firstNumberBox).first
}

func firstToggleButton(in view: NSView) -> FluentToggleButton? {
    if let button = view as? FluentToggleButton { return button }
    return view.subviews.lazy.compactMap(firstToggleButton).first
}

func firstToggle(in view: NSView) -> FluentToggle? {
    if let toggle = view as? FluentToggle { return toggle }
    return view.subviews.lazy.compactMap(firstToggle).first
}

func firstCheckBox(in view: NSView) -> FluentCheckBox? {
    if let checkBox = view as? FluentCheckBox { return checkBox }
    return view.subviews.lazy.compactMap(firstCheckBox).first
}

func firstRadioButton(in view: NSView) -> FluentRadioButton? {
    if let radio = view as? FluentRadioButton { return radio }
    return view.subviews.lazy.compactMap(firstRadioButton).first
}

func firstSegmentedControl(in view: NSView) -> NSSegmentedControl? {
    if let segmented = view as? NSSegmentedControl { return segmented }
    return view.subviews.lazy.compactMap(firstSegmentedControl).first
}

func layers(named name: String, in view: NSView) -> [CALayer] {
    func collect(_ layer: CALayer) -> [CALayer] {
        var matches = layer.name == name ? [layer] : []
        if let mask = layer.mask { matches.append(contentsOf: collect(mask)) }
        for child in layer.sublayers ?? [] { matches.append(contentsOf: collect(child)) }
        return matches
    }
    var matches = view.layer.map(collect) ?? []
    for child in view.subviews { matches.append(contentsOf: layers(named: name, in: child)) }
    return matches
}

func firstSlider(in view: NSView) -> FluentSlider? {
    if let slider = view as? FluentSlider { return slider }
    return view.subviews.lazy.compactMap(firstSlider).first
}

func firstProgressBar(in view: NSView) -> FluentProgressBar? {
    if let progress = view as? FluentProgressBar { return progress }
    return view.subviews.lazy.compactMap(firstProgressBar).first
}

func firstLayer(named name: String, in view: NSView) -> CALayer? {
    func search(_ layer: CALayer) -> CALayer? {
        if layer.name == name { return layer }
        if let mask = layer.mask, let match = search(mask) { return match }
        return layer.sublayers?.lazy.compactMap(search).first
    }
    if let layer = view.layer, let match = search(layer) { return match }
    return view.subviews.lazy.compactMap { firstLayer(named: name, in: $0) }.first
}

func pathVertices(_ path: CGPath?) -> [CGPoint] {
    guard let path else { return [] }
    var points: [CGPoint] = []
    path.applyWithBlock { elementPointer in
        let element = elementPointer.pointee
        switch element.type {
        case .moveToPoint, .addLineToPoint:
            points.append(element.points[0])
        case .addQuadCurveToPoint:
            points.append(element.points[1])
        case .addCurveToPoint:
            points.append(element.points[2])
        case .closeSubpath:
            break
        @unknown default:
            break
        }
    }
    return points
}

func chevronPointsVisuallyDown(_ points: [CGPoint], in layer: CALayer?) -> Bool {
    guard let layer, points.count == 3 else { return false }
    // FluentAnimatedChevronLayer owns a stable top-down path. Its AppKit host may be flipped
    // independently, so inspecting `isGeometryFlipped` here would reintroduce the cold-start bug.
    return !layer.isGeometryFlipped
        && points[1].y > points[0].y
        && points[1].y > points[2].y
}

func translationMovesVisuallyDown(_ offset: CGFloat, in layer: CALayer?) -> Bool {
    guard let layer else { return false }
    return !layer.isGeometryFlipped && offset > 0
}

func elevationGradientMatchesVisualEdge(
    _ layer: CAGradientLayer,
    edge: FluentElevationBorderEdge,
    extent: CGFloat = 3,
    hostView: NSView? = nil
) -> Bool {
    // A WindowShell can flip the backing layer inherited by a control without changing the
    // control's own AppKit coordinate system. Validate against the local view when available.
    let hostIsFlipped = hostView?.isFlipped ?? (layer.superlayer?.isGeometryFlipped ?? false)
    let visualBottom: CGFloat = hostIsFlipped ? 1 : 0
    let visualTop: CGFloat = hostIsFlipped ? 0 : 1
    let visualDownSign: CGFloat = hostIsFlipped ? 1 : -1
    let expectedStart = edge == .bottom ? visualBottom : visualTop
    let expectedDirection = edge == .bottom ? -visualDownSign : visualDownSign
    let actualDirection = layer.endPoint.y - layer.startPoint.y
    return abs(layer.startPoint.y - expectedStart) < 0.001
        && actualDirection * expectedDirection > 0
        && abs(abs(actualDirection) * layer.bounds.height - extent) < 0.001
}

func pathBoundsUseContainedAntialiasing(
    _ pathBounds: CGRect,
    in bounds: CGRect,
    backingScale: CGFloat
) -> Bool {
    let inset = 0.5 / max(backingScale, 1)
    return abs(pathBounds.minX - (bounds.minX + inset)) < 0.001
        && abs(pathBounds.minY - (bounds.minY + inset)) < 0.001
        && abs(pathBounds.maxX - (bounds.maxX - inset)) < 0.001
        && abs(pathBounds.maxY - (bounds.maxY - inset)) < 0.001
}

func colorMatches(_ color: CGColor?, _ expected: NSColor, tolerance: CGFloat = 0.001) -> Bool {
    guard let color,
          let actual = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB),
          let target = expected.usingColorSpace(.deviceRGB) else { return false }
    return abs(actual.redComponent - target.redComponent) < tolerance
        && abs(actual.greenComponent - target.greenComponent) < tolerance
        && abs(actual.blueComponent - target.blueComponent) < tolerance
        && abs(actual.alphaComponent - target.alphaComponent) < tolerance
}

func timingFunctionMatches(
    _ actual: CAMediaTimingFunction?,
    _ expected: CAMediaTimingFunction,
    tolerance: Float = 0.0001
) -> Bool {
    guard let actual else { return false }
    for index in 0...3 {
        var actualPoint = [Float](repeating: 0, count: 2)
        var expectedPoint = [Float](repeating: 0, count: 2)
        actual.getControlPoint(at: index, values: &actualPoint)
        expected.getControlPoint(at: index, values: &expectedPoint)
        guard abs(actualPoint[0] - expectedPoint[0]) < tolerance,
              abs(actualPoint[1] - expectedPoint[1]) < tolerance else { return false }
    }
    return true
}

func keyframeAnimation(
    for keyPath: String,
    in group: CAAnimationGroup?
) -> CAKeyframeAnimation? {
    group?.animations?.compactMap { $0 as? CAKeyframeAnimation }.first { $0.keyPath == keyPath }
}

func firstSecureTextField(in view: NSView) -> NSSecureTextField? {
    if let field = view as? NSSecureTextField { return field }
    return view.subviews.lazy.compactMap(firstSecureTextField).first
}

func firstSearchField(in view: NSView) -> NSSearchField? {
    if let field = view as? NSSearchField { return field }
    return view.subviews.lazy.compactMap(firstSearchField).first
}

func firstComboBox(in view: NSView) -> NSComboBox? {
    if let comboBox = view as? NSComboBox { return comboBox }
    return view.subviews.lazy.compactMap(firstComboBox).first
}

func firstView(withAccessibilityTitle title: String, in view: NSView) -> NSView? {
    if view.accessibilityTitle() == title { return view }
    return view.subviews.lazy.compactMap { firstView(withAccessibilityTitle: title, in: $0) }.first
}

func firstView(withAccessibilityRole role: NSAccessibility.Role, in view: NSView) -> NSView? {
    if view.accessibilityRole() == role { return view }
    return view.subviews.lazy.compactMap { firstView(withAccessibilityRole: role, in: $0) }.first
}

func firstView(identifier: String, in view: NSView) -> NSView? {
    if view.identifier?.rawValue == identifier { return view }
    return view.subviews.lazy.compactMap { firstView(identifier: identifier, in: $0) }.first
}

func firstMaterialView(in view: NSView) -> FluentMaterialView? {
    if let material = view as? FluentMaterialView { return material }
    return view.subviews.lazy.compactMap(firstMaterialView).first
}

func materialViews(in view: NSView) -> [FluentMaterialView] {
    var materials: [FluentMaterialView] = []
    if let material = view as? FluentMaterialView { materials.append(material) }
    for child in view.subviews { materials.append(contentsOf: materialViews(in: child)) }
    return materials
}

func views(identifier: String, in view: NSView) -> [NSView] {
    var matches = view.identifier?.rawValue == identifier ? [view] : []
    for child in view.subviews { matches.append(contentsOf: views(identifier: identifier, in: child)) }
    return matches
}

func firstStepper(in view: NSView) -> NSStepper? {
    if let stepper = view as? NSStepper { return stepper }
    return view.subviews.lazy.compactMap(firstStepper).first
}

func firstFluentTextField(in view: NSView) -> FluentTextField? {
    if let field = view as? FluentTextField { return field }
    return view.subviews.lazy.compactMap(firstFluentTextField).first
}

func labels(in view: NSView) -> [NSTextField] {
    var result: [NSTextField] = []
    if let label = view as? NSTextField, !label.isEditable { result.append(label) }
    for child in view.subviews { result.append(contentsOf: labels(in: child)) }
    return result
}

func firstSplitView(in view: NSView) -> NSSplitView? {
    if let splitView = view as? NSSplitView { return splitView }
    return view.subviews.lazy.compactMap(firstSplitView).first
}

func bitmapHasVisibleVariation(_ bitmap: NSBitmapImageRep) -> Bool {
    var sampledColors = Set<Int>()
    let horizontalStep = max(bitmap.pixelsWide / 48, 1)
    let verticalStep = max(bitmap.pixelsHigh / 36, 1)
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: verticalStep) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: horizontalStep) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let red = Int((color.redComponent * 255).rounded())
            let green = Int((color.greenComponent * 255).rounded())
            let blue = Int((color.blueComponent * 255).rounded())
            let alpha = Int((color.alphaComponent * 255).rounded())
            sampledColors.insert((red << 24) | (green << 16) | (blue << 8) | alpha)
            if sampledColors.count >= 8 { return true }
        }
    }
    return false
}

func renderedColor(in view: NSView, at point: NSPoint) -> NSColor? {
    guard view.bounds.width > 0,
          view.bounds.height > 0,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
    let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
    let x = min(max(Int((point.x - view.bounds.minX) * scaleX), 0), bitmap.pixelsWide - 1)
    let y = min(max(Int((point.y - view.bounds.minY) * scaleY), 0), bitmap.pixelsHigh - 1)
    return bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
}

func renderedBackgroundAlpha(in view: NSView) -> CGFloat {
    renderedColor(in: view, at: NSPoint(x: 6, y: view.bounds.midY))?.alphaComponent ?? 0
}

struct ValidationButtonStyle: FluentButtonStyle {
    func appearance(for configuration: FluentButtonStyleConfiguration) -> FluentButtonAppearance {
        FluentButtonAppearance(
            backgroundColor: .systemPink,
            foregroundColor: .white,
            borderColor: .systemPink,
            borderWidth: 2,
            cornerRadius: 3,
            contentInsets: NSEdgeInsets(top: 9, left: 30, bottom: 9, right: 30),
            focusRingColor: .systemPink
        )
    }
}

struct ValidationToggleStyle: FluentToggleStyle {
    func appearance(for configuration: FluentToggleStyleConfiguration) -> FluentToggleAppearance {
        FluentToggleAppearance(
            trackColor: .systemPurple,
            trackBorderColor: .systemPurple,
            knobColor: .white,
            labelColor: configuration.theme.textPrimary,
            knobShadowColor: .clear,
            trackSize: CGSize(width: 48, height: 24),
            knobDiameter: 20,
            labelSpacing: 16
        )
    }
}

struct ValidationSliderStyle: FluentSliderStyle {
    func appearance(for configuration: FluentSliderStyleConfiguration) -> FluentSliderAppearance {
        FluentSliderAppearance(
            trackColor: .darkGray,
            fillColor: .systemPurple,
            knobColor: .systemPurple,
            haloColor: .systemPurple.withAlphaComponent(0.2),
            trackHeight: 6,
            knobDiameter: 20,
            haloDiameter: 28
        )
    }
}

struct ValidationTextFieldStyle: FluentTextFieldStyle {
    func appearance(for configuration: FluentTextFieldStyleConfiguration) -> FluentTextFieldAppearance {
        FluentTextFieldAppearance(
            backgroundColor: .clear,
            textColor: configuration.theme.textPrimary,
            borderColor: .systemPurple,
            borderWidth: 2,
            cornerRadius: 0,
            borderShape: .underline,
            font: .systemFont(ofSize: 17)
        )
    }
}

struct ValidationProgressStyle: FluentProgressStyle {
    func appearance(for configuration: FluentProgressStyleConfiguration) -> FluentProgressAppearance {
        FluentProgressAppearance(
            trackColor: .darkGray,
            progressColor: .systemPurple,
            trackHeight: 8,
            cornerRadius: 4
        )
    }
}

struct ValidationCheckBoxStyle: FluentCheckBoxStyle {
    func appearance(for configuration: FluentCheckBoxStyleConfiguration) -> FluentCheckBoxAppearance {
        FluentCheckBoxAppearance(
            boxSize: 24,
            cornerRadius: 5,
            fillColor: .systemPurple,
            borderColor: .systemPurple,
            borderWidth: 2,
            markColor: .white,
            labelColor: configuration.theme.textPrimary,
            labelFont: .systemFont(ofSize: 16),
            labelSpacing: 10
        )
    }
}

struct ValidationRadioButtonStyle: FluentRadioButtonStyle {
    func appearance(for configuration: FluentRadioButtonStyleConfiguration) -> FluentRadioButtonAppearance {
        FluentRadioButtonAppearance(
            diameter: 24,
            fillColor: .systemPurple,
            borderColor: .systemPurple,
            borderWidth: 2,
            dotColor: .white,
            labelColor: configuration.theme.textPrimary,
            labelFont: .systemFont(ofSize: 16),
            labelSpacing: 10
        )
    }
}

struct ValidationSegmentedStyle: FluentSegmentedStyle {
    func appearance(for configuration: FluentSegmentedStyleConfiguration) -> FluentSegmentedAppearance {
        FluentSegmentedAppearance(
            backgroundColor: .darkGray,
            selectedSegmentColor: .systemPurple,
            borderColor: .systemPurple,
            borderWidth: 2,
            cornerRadius: 5,
            font: .systemFont(ofSize: 15),
            segmentStyle: .rounded
        )
    }
}

struct ValidationStepperStyle: FluentStepperStyle {
    func appearance(for configuration: FluentStepperStyleConfiguration) -> FluentStepperAppearance {
        FluentStepperAppearance(
            labelColor: configuration.theme.textPrimary,
            labelFont: .systemFont(ofSize: 17),
            spacing: 12,
            valueFieldWidth: 110,
            textFieldStyle: ValidationTextFieldStyle()
        )
    }
}

let observable = FluentObservable(10)
var observed: [Int] = []
let token = observable.observe({ observed.append($0) }, notifyImmediately: false)
observable.value = 12
require(observed == [12], "observable delivers updates")
observable.removeObserver(token)
observable.value = 14
require(observed == [12], "observer removal works")

let binding = FluentBinding(get: { observable.value }, set: { observable.value = $0 })
let mapped = binding.map({ $0 > 10 }, { $0 ? 20 : 0 })
require(mapped.get() == true, "mapped binding reads transformed value")
mapped.set(false)
require(observable.value == 0, "mapped binding writes through inverse transform")

let theme = FluentTheme.custom(accent: .systemBlue, material: .acrylic)
switch theme.material {
case .acrylic: break
default: require(false, "custom theme stores material")
}
require(theme.buttonCornerRadius > 0, "theme exposes control metrics")
let aquaAppearance = NSAppearance(named: .aqua)!
let darkAquaAppearance = NSAppearance(named: .darkAqua)!
let requestedSystemStore = FluentThemeStore(
    preference: .system,
    resolvedTheme: FluentTheme.custom(colorScheme: .light)
)
require(
    requestedSystemStore.preference == .system
        && requestedSystemStore.resolvedTheme.colorScheme != .system,
    "theme store separates requested System preference from its actual resolved theme"
)
require(
    requestedSystemStore.resolve(using: darkAquaAppearance).colorScheme == .dark
        && requestedSystemStore.resolve(using: aquaAppearance).colorScheme == .light,
    "the single theme resolver maps AppKit appearance to actual Light/Dark themes"
)
requestedSystemStore.preference = .dark
require(
    requestedSystemStore.preference == .dark
        && requestedSystemStore.resolvedTheme.colorScheme == .dark,
    "manual Dark preference uses the same resolved downstream path"
)
let defaultContextTheme = FluentRenderContext(theme: FluentTheme()).theme
require(defaultContextTheme.colorScheme != .system, "render contexts never pass an unresolved System theme to controls")
require(
    theme.material(for: .transient) == .liquidGlass
        && theme.material(for: .navigation) == .mica
        && theme.material(for: .window) == .mica
        && theme.materialEffectsEnabled,
    "theme keeps Liquid Glass transient while persistent navigation and window surfaces use Mica"
)
let expectedLiquidGlassBackend: FluentMaterialBackend = if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
    .opaque
} else if FluentMaterialView.isNativeLiquidGlassAvailable {
    .nativeGlass
} else {
    .visualEffect
}
let nativeGlassProbe = FluentMaterialView(material: .liquidGlass)
nativeGlassProbe.frame = NSRect(x: 0, y: 0, width: 180, height: 80)
nativeGlassProbe.layoutSubtreeIfNeeded()
require(
    nativeGlassProbe.resolvedBackend == expectedLiquidGlassBackend
        && nativeGlassProbe.state == .followsWindowActiveState,
    "Liquid Glass selects the native runtime backend when available and follows window active state"
)
require(
    (expectedLiquidGlassBackend != .nativeGlass)
        || firstView(identifier: "FluentKit.Material.NativeGlass", in: nativeGlassProbe)?.frame == nativeGlassProbe.bounds,
    "native Liquid Glass fills the Fluent material surface without replacing its content host"
)
let micaProbeTheme = FluentTheme.custom(colorScheme: .light)
let micaProbe = FluentMaterialView(material: .mica)
micaProbe.fluentTheme = micaProbeTheme
micaProbe.frame = NSRect(x: 0, y: 0, width: 180, height: 80)
micaProbe.layoutSubtreeIfNeeded()
require(
    micaProbe.resolvedBackend == expectedLiquidGlassBackend
        && micaProbe.state == .followsWindowActiveState
        && micaProbe.tintColor == nil
        && firstLayer(named: "FluentKit.Material.MicaTint", in: micaProbe)?.backgroundColor != nil
        && (micaProbe.resolvedBackend != .visualEffect || micaProbe.material == .underWindowBackground),
    "Mica selects Glass at runtime or underWindowBackground without a version check and supplies its theme tint"
)
micaProbe.isMaterialEnabled = false
require(
    micaProbe.resolvedBackend == .opaque
        && firstLayer(named: "FluentKit.Material.MicaTint", in: micaProbe)?.isHidden == true
        && firstLayer(named: "FluentKit.Material.OpaqueFallback", in: micaProbe)?.opacity == 1,
    "Mica disables both Glass and tint when the single opaque fallback owns the surface"
)
nativeGlassProbe.isMaterialEnabled = false
require(
    nativeGlassProbe.resolvedBackend == .opaque
        && firstView(identifier: "FluentKit.Material.NativeGlass", in: nativeGlassProbe)?.isHidden != false,
    "the global material switch moves Liquid Glass to the opaque accessibility backend"
)
let visualEffectProbe = FluentMaterialView(material: .sidebar)
require(
    visualEffectProbe.resolvedBackend == (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .opaque : .visualEffect)
        && visualEffectProbe.state == .followsWindowActiveState
        && (visualEffectProbe.resolvedBackend != .visualEffect || visualEffectProbe.blendingMode == .behindWindow),
    "legacy sidebar material uses a semantic behind-window visual-effect fallback"
)
let effectsDisabledTheme = theme.with(materialEffectsEnabled: false)
require(
    effectsDisabledTheme.material(for: .transient) == nil
        && effectsDisabledTheme.material(for: .navigation) == nil
        && effectsDisabledTheme.material(for: .window) == nil
        && !effectsDisabledTheme.materialEffectsEnabled,
    "theme-level material switch disables transient, navigation, and window effects"
)
let regularDesignTokens = FluentDesignTokens()
let compactDesignTokens = FluentDesignTokens(density: .compact)
require(regularDesignTokens.controlHeight == 32, "design tokens expose the regular control height")
require(regularDesignTokens.controlCornerRadius == 4, "design tokens expose the Fluent control radius")
require(regularDesignTokens.cardCornerRadius == 8, "design tokens expose the overlay and card radius")
require(regularDesignTokens.navigationPaneWidth == 240, "design tokens expose the navigation pane width")
require(compactDesignTokens.controlHeight < regularDesignTokens.controlHeight, "design tokens scale with semantic density")
let derivedTheme = theme.with(accent: .systemPink).with(material: .sidebar)
require(derivedTheme.accent == .systemPink, "theme derives a new accent while preserving other values")
require(derivedTheme.material == .sidebar, "theme derives a new material while preserving other values")
require(derivedTheme.density == theme.density && derivedTheme.contrast == theme.contrast, "theme derivation preserves density and contrast")
require(derivedTheme.materialEffectsEnabled == theme.materialEffectsEnabled, "theme derivation preserves the global material switch")
let horizontalDivider = FluentDivider()._mount(in: FluentRenderContext(theme: theme))
let verticalDivider = FluentDivider(orientation: .vertical)._mount(in: FluentRenderContext(theme: theme))
require(
    horizontalDivider.constraints.contains { $0.firstAttribute == .height && $0.constant == 1 },
    "horizontal divider fixes its thickness without constraining width"
)
require(
    verticalDivider.constraints.contains { $0.firstAttribute == .width && $0.constant == 1 },
    "vertical divider fixes its thickness without constraining height"
)

let compactHighContrastTheme = FluentTheme.custom(
    accent: .systemOrange,
    material: .acrylic,
    density: .compact,
    contrast: .high
)
require(compactHighContrastTheme.density == .compact, "theme stores semantic density")
require(compactHighContrastTheme.contrast == .high, "theme stores explicit contrast mode")
require(compactHighContrastTheme.isHighContrast, "high contrast theme resolves its semantic contrast")
require(compactHighContrastTheme.controlHeight < theme.controlHeight, "compact density reduces control metrics")
let standardSelectionTheme = FluentTheme.custom(contrast: .standard, typography: FluentTypography(scale: 1))
let highContrastSelectionTheme = FluentTheme.custom(contrast: .high, typography: FluentTypography(scale: 1.4))
let sourceLightTheme = FluentTheme.custom(contrast: .standard, colorScheme: .light)
let sourceDarkTheme = FluentTheme.custom(contrast: .standard, colorScheme: .dark)
require(
    colorMatches(
        highContrastSelectionTheme.menuItemBackground(for: .pointerOver).cgColor,
        .selectedContentBackgroundColor
    )
        && colorMatches(
            highContrastSelectionTheme.menuItemBackground(for: .pressed).cgColor,
            .selectedContentBackgroundColor
        )
        && colorMatches(
            highContrastSelectionTheme.menuItemForeground(for: .pointerOver).cgColor,
            .selectedMenuItemTextColor
        )
        && colorMatches(
            highContrastSelectionTheme.menuItemForeground(for: .disabled).cgColor,
            .disabledControlTextColor
        )
        && colorMatches(
            highContrastSelectionTheme.menuAcceleratorForeground(for: .normal).cgColor,
            .textColor
        )
        && colorMatches(
            highContrastSelectionTheme.menuAcceleratorForeground(for: .pressed).cgColor,
            .selectedMenuItemTextColor
        ),
    "High Contrast MenuFlyout resources map system Highlight, HighlightText, GrayText, and WindowText"
)
require(
    colorMatches(
        standardSelectionTheme.menuItemBackground(for: .pointerOver).cgColor,
        standardSelectionTheme.subtleFillSecondary
    )
        && colorMatches(
            standardSelectionTheme.menuItemBackground(for: .pressed).cgColor,
            standardSelectionTheme.subtleFillTertiary
        )
        && colorMatches(
            standardSelectionTheme.menuItemForeground(for: .normal).cgColor,
            standardSelectionTheme.textPrimary
        )
        && colorMatches(
            standardSelectionTheme.menuAcceleratorForeground(for: .normal).cgColor,
            standardSelectionTheme.textSecondary
        ),
    "standard MenuFlyout resources preserve the Light/Dark subtle-fill hierarchy"
)
require(
    colorMatches(sourceDarkTheme.windowBackground.cgColor, NSColor(calibratedWhite: 32.0 / 255.0, alpha: 1))
        && colorMatches(sourceLightTheme.windowBackground.cgColor, NSColor(calibratedWhite: 243.0 / 255.0, alpha: 1)),
    "Light and Dark window backgrounds map SolidBackgroundFillColorBase exactly"
)
require(
    colorMatches(sourceDarkTheme.textPrimary.cgColor, .white)
        && colorMatches(sourceDarkTheme.textSecondary.cgColor, NSColor(calibratedWhite: 1, alpha: 197.0 / 255.0))
        && colorMatches(sourceDarkTheme.textTertiary.cgColor, NSColor(calibratedWhite: 1, alpha: 135.0 / 255.0))
        && colorMatches(sourceDarkTheme.textDisabled.cgColor, NSColor(calibratedWhite: 1, alpha: 93.0 / 255.0)),
    "Dark text hierarchy maps TextFillColorPrimary/Secondary/Tertiary/Disabled exactly"
)
require(
    colorMatches(sourceLightTheme.textPrimary.cgColor, NSColor(calibratedWhite: 0, alpha: 228.0 / 255.0))
        && colorMatches(sourceLightTheme.textSecondary.cgColor, NSColor(calibratedWhite: 0, alpha: 158.0 / 255.0)),
    "Light primary and secondary text retain source alpha instead of precomposited gray"
)
require(
    colorMatches(sourceDarkTheme.textOnAccent.cgColor, .black)
        && colorMatches(sourceLightTheme.textOnAccent.cgColor, .white),
    "TextOnAccentFillColorPrimary switches from black in Dark to white in Light"
)
require(
    colorMatches(
        FluentTheme.defaultAccent.cgColor,
        NSColor(calibratedRed: 0, green: 120.0 / 255.0, blue: 212.0 / 255.0, alpha: 1)
    )
        && colorMatches(
            sourceDarkTheme.accentFillDefault.cgColor,
            NSColor(calibratedRed: 118.0 / 255.0, green: 185.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)
        )
        && colorMatches(
            sourceLightTheme.accentFillDefault.cgColor,
            NSColor(calibratedRed: 0, green: 90.0 / 255.0, blue: 158.0 / 255.0, alpha: 1)
        ),
    "SystemAccentColor and AccentFillColorDefault use the source fallback palette"
)
require(
    colorMatches(sourceDarkTheme.accentTextPrimary.cgColor, NSColor(
        calibratedRed: 166.0 / 255.0,
        green: 216.0 / 255.0,
        blue: 1,
        alpha: 1
    ))
        && colorMatches(sourceLightTheme.accentTextPrimary.cgColor, NSColor(
            calibratedRed: 0,
            green: 66.0 / 255.0,
            blue: 117.0 / 255.0,
            alpha: 1
        )),
    "AccentTextFillColorPrimary resolves Light3 in Dark and Dark2 in Light"
)
require(
    colorMatches(sourceDarkTheme.controlStroke.cgColor, NSColor(calibratedWhite: 1, alpha: 18.0 / 255.0))
        && colorMatches(sourceDarkTheme.controlStrokeStrong.cgColor, NSColor(calibratedWhite: 1, alpha: 139.0 / 255.0))
        && colorMatches(sourceDarkTheme.divider.cgColor, NSColor(calibratedWhite: 1, alpha: 21.0 / 255.0)),
    "Dark default, strong, and divider strokes use the Common theme resources"
)
require(
    colorMatches(sourceDarkTheme.cardFill.cgColor, NSColor(calibratedWhite: 1, alpha: 13.0 / 255.0))
        && colorMatches(sourceDarkTheme.cardStroke.cgColor, NSColor(calibratedWhite: 0, alpha: 25.0 / 255.0))
        && colorMatches(
            sourceDarkTheme.layerFill.cgColor,
            NSColor(
                calibratedRed: 58.0 / 255.0,
                green: 58.0 / 255.0,
                blue: 58.0 / 255.0,
                alpha: 76.0 / 255.0
            )
        ),
    "Dark card and layer surfaces retain source color channels and alpha"
)
let standardCheckBoxAppearance = FluentAutomaticCheckBoxStyle().appearance(
    for: FluentCheckBoxStyleConfiguration(isChecked: false, isEnabled: true, isPointerOver: false, controlSize: .regular, theme: standardSelectionTheme)
)
let highContrastCheckBoxAppearance = FluentAutomaticCheckBoxStyle().appearance(
    for: FluentCheckBoxStyleConfiguration(isChecked: false, isEnabled: true, isPointerOver: false, controlSize: .regular, theme: highContrastSelectionTheme)
)
require(highContrastCheckBoxAppearance.borderWidth > standardCheckBoxAppearance.borderWidth, "high contrast increases check box border emphasis")
require(highContrastCheckBoxAppearance.labelFont.pointSize > standardCheckBoxAppearance.labelFont.pointSize, "theme typography scales check box labels")
let highContrastSegmentedAppearance = FluentAutomaticSegmentedStyle().appearance(
    for: FluentSegmentedStyleConfiguration(selectedIndex: 0, isEnabled: true, controlSize: .regular, theme: highContrastSelectionTheme)
)
require(highContrastSegmentedAppearance.borderWidth > standardCheckBoxAppearance.borderWidth, "high contrast increases segmented border emphasis")
let standardButtonAppearance = FluentAutomaticButtonStyle().appearance(
    for: FluentButtonStyleConfiguration(title: "Standard", theme: standardSelectionTheme)
)
let highContrastButtonAppearance = FluentAutomaticButtonStyle().appearance(
    for: FluentButtonStyleConfiguration(title: "High contrast", theme: highContrastSelectionTheme)
)
require(highContrastButtonAppearance.borderWidth > standardButtonAppearance.borderWidth, "high contrast increases button border emphasis")
require(highContrastButtonAppearance.focusRingWidth > standardButtonAppearance.focusRingWidth, "high contrast increases button focus emphasis")
let standardToggleAppearance = FluentAutomaticToggleStyle().appearance(
    for: FluentToggleStyleConfiguration(isOn: false, isEnabled: true, isPointerOver: false, controlSize: .regular, theme: standardSelectionTheme)
)
let highContrastToggleAppearance = FluentAutomaticToggleStyle().appearance(
    for: FluentToggleStyleConfiguration(isOn: false, isEnabled: true, isPointerOver: false, controlSize: .regular, theme: highContrastSelectionTheme)
)
require(highContrastToggleAppearance.trackBorderWidth > standardToggleAppearance.trackBorderWidth, "high contrast increases toggle border emphasis")
let hoverToggleAppearance = FluentAutomaticToggleStyle().appearance(
    for: FluentToggleStyleConfiguration(isOn: false, isEnabled: true, isPointerOver: true, controlSize: .regular, theme: standardSelectionTheme)
)
let pressedToggleAppearance = FluentAutomaticToggleStyle().appearance(
    for: FluentToggleStyleConfiguration(isOn: false, isEnabled: true, isPointerOver: true, isPressed: true, controlSize: .regular, theme: standardSelectionTheme)
)
let onToggleAppearance = FluentAutomaticToggleStyle().appearance(
    for: FluentToggleStyleConfiguration(isOn: true, isEnabled: true, isPointerOver: false, controlSize: .regular, theme: standardSelectionTheme)
)
require(
    standardToggleAppearance.trackSize == CGSize(width: 40, height: 20)
        && standardToggleAppearance.knobSize == CGSize(width: 12, height: 12),
    "ToggleSwitch normal state preserves the WinUI 40x20 track and 12x12 knob"
)
require(
    hoverToggleAppearance.knobSize == CGSize(width: 14, height: 14),
    "ToggleSwitch pointer-over state expands the knob to 14x14"
)
require(
    pressedToggleAppearance.knobSize == CGSize(width: 17, height: 14),
    "ToggleSwitch pressed and dragging states use the 17x14 knob"
)
require(
    onToggleAppearance.trackBorderWidth == 0,
    "ToggleSwitch standard On state uses the source template's borderless accent track"
)
let standardSliderAppearance = FluentAutomaticSliderStyle().appearance(
    for: FluentSliderStyleConfiguration(valueFraction: 0.5, isEnabled: true, isPointerOver: false, isDragging: false, controlSize: .regular, theme: standardSelectionTheme)
)
let highContrastSliderAppearance = FluentAutomaticSliderStyle().appearance(
    for: FluentSliderStyleConfiguration(valueFraction: 0.5, isEnabled: true, isPointerOver: false, isDragging: false, controlSize: .regular, theme: highContrastSelectionTheme)
)
require(highContrastSliderAppearance.trackHeight > standardSliderAppearance.trackHeight, "high contrast increases slider track emphasis")
require(highContrastSliderAppearance.knobDiameter > standardSliderAppearance.knobDiameter, "high contrast increases slider thumb emphasis")
let standardFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(isEnabled: true, isFocused: false, controlSize: .regular, theme: standardSelectionTheme)
)
let focusedFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(isEnabled: true, isFocused: true, controlSize: .regular, theme: standardSelectionTheme)
)
let hoveredFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(
        isEnabled: true,
        isFocused: false,
        isPointerOver: true,
        controlSize: .regular,
        theme: standardSelectionTheme
    )
)
let focusedHoveredFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(
        isEnabled: true,
        isFocused: true,
        isPointerOver: true,
        controlSize: .regular,
        theme: standardSelectionTheme
    )
)
let highContrastFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(isEnabled: true, isFocused: false, controlSize: .regular, theme: highContrastSelectionTheme)
)
require(highContrastFieldAppearance.borderWidth > standardFieldAppearance.borderWidth, "high contrast increases text field border emphasis")
require(
    colorMatches(hoveredFieldAppearance.backgroundColor.cgColor, standardSelectionTheme.controlFillSecondary),
    "TextBox PointerOver uses TextControlBackgroundPointerOver"
)
require(
    colorMatches(focusedHoveredFieldAppearance.backgroundColor.cgColor, focusedFieldAppearance.backgroundColor),
    "TextBox Focused takes precedence over PointerOver"
)
require(
    focusedFieldAppearance.focusIndicatorWidth == 2
        && focusedFieldAppearance.borderShape == .rounded,
    "focused TextBox uses a dedicated 2pt bottom accent indicator"
)
let lightFocusedFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(
        isEnabled: true,
        isFocused: true,
        controlSize: .regular,
        theme: sourceLightTheme
    )
)
let darkFocusedFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(
        isEnabled: true,
        isFocused: true,
        controlSize: .regular,
        theme: sourceDarkTheme
    )
)
require(
    colorMatches(lightFocusedFieldAppearance.focusIndicatorColor?.cgColor, sourceLightTheme.accentDark1)
        && colorMatches(darkFocusedFieldAppearance.focusIndicatorColor?.cgColor, sourceDarkTheme.accentLight2),
    "TextBox resolves the source Dark1 Light focus stroke and Light2 Dark focus stroke"
)
require(
    standardFieldAppearance.borderGradientLocations == [0.5, 1]
        && standardFieldAppearance.borderGradientEdge == .bottom
        && standardFieldAppearance.borderGradientExtent == 2
        && standardFieldAppearance.borderGradientColors?.count == 2,
    "TextBox uses the source TextControlElevationBorderBrush two-point bottom extent"
)
require(
    focusedFieldAppearance.borderGradientColors?.count == 2
        && colorMatches(
            focusedFieldAppearance.borderGradientColors?.first?.cgColor,
            standardFieldAppearance.borderGradientColors?.first ?? .clear
        )
        && colorMatches(
            focusedFieldAppearance.borderGradientColors?.last?.cgColor,
            standardFieldAppearance.borderGradientColors?.last ?? .clear
        ),
    "focused TextBox keeps one base elevation ring and replaces only its 2pt bottom edge"
)
require(
    colorMatches(standardFieldAppearance.borderGradientColors?.first?.cgColor, standardSelectionTheme.controlStrokeStrong)
        && colorMatches(standardFieldAppearance.borderGradientColors?.last?.cgColor, standardSelectionTheme.controlStrokeDefault),
    "TextBox uses TextControl elevation colors instead of Button elevation colors"
)
let standardProgressAppearance = FluentAutomaticProgressStyle().appearance(
    for: FluentProgressStyleConfiguration(valueFraction: 0.5, theme: standardSelectionTheme)
)
let highContrastProgressAppearance = FluentAutomaticProgressStyle().appearance(
    for: FluentProgressStyleConfiguration(valueFraction: 0.5, theme: highContrastSelectionTheme)
)
require(highContrastProgressAppearance.trackHeight > standardProgressAppearance.trackHeight, "high contrast increases progress track emphasis")
let standardCardAppearance = FluentAutomaticCardStyle().appearance(for: standardSelectionTheme)
let highContrastCardAppearance = FluentAutomaticCardStyle().appearance(for: highContrastSelectionTheme)
require(highContrastCardAppearance.strokeWidth > standardCardAppearance.strokeWidth, "high contrast increases card boundary emphasis")

var capturedThemeDensity: FluentThemeDensity?
var capturedThemeContrast: FluentThemeContrast?
var capturedThemeColorScheme: FluentThemeColorScheme?
struct ThemeVariantProbe: FluentPrimitiveView {
    let capture: (FluentRenderContext) -> Void

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        capture(context)
        return NSView()
    }
}
let themeVariantView = ThemeVariantProbe { context in
    capturedThemeDensity = context.theme.density
    capturedThemeContrast = context.theme.contrast
    capturedThemeColorScheme = context.theme.colorScheme
}
.fluentDensity(.compact)
.fluentContrast(.high)
.fluentColorScheme(.dark)
_ = themeVariantView._mount(in: FluentRenderContext(theme: theme))
require(capturedThemeDensity == .compact, "density environment reaches nested content")
require(capturedThemeContrast == .high, "contrast environment reaches nested content")
require(capturedThemeColorScheme == .dark, "color scheme environment reaches nested content")

let styledButton = FluentButtonView("Styled", style: ValidationButtonStyle())
let styledButtonView = styledButton._mount(in: FluentRenderContext(theme: compactHighContrastTheme)) as? FluentButton
require(styledButtonView?.fluentStyle != nil, "button style mounts on the native button")
require((styledButtonView?.intrinsicContentSize.width ?? 0) > 80, "button style content insets affect intrinsic metrics")
let compactButton = FluentButtonView("Density")._mount(
    in: FluentRenderContext(theme: theme.with(density: .compact))
) as? FluentButton
let spaciousButton = FluentButtonView("Density")._mount(
    in: FluentRenderContext(theme: theme.with(density: .spacious))
) as? FluentButton
require(
    (compactButton?.intrinsicContentSize.height ?? 0) < (spaciousButton?.intrinsicContentSize.height ?? 0),
    "theme density changes native button metrics"
)

let styledButtonTitle = FluentObservable("First")
struct StyledButtonProbe: FluentView {
    let title: FluentObservable<String>

    var body: FluentButtonView {
        FluentButtonView(title.value).buttonStyle(ValidationButtonStyle())
    }
}
let styledButtonHost = FluentViewHost(StyledButtonProbe(title: styledButtonTitle))
let nativeStyledButton = firstButton(in: styledButtonHost)
styledButtonTitle.value = "Second"
drainMainQueue()
require(firstButton(in: styledButtonHost) === nativeStyledButton, "styled button updates preserve native identity")
require(nativeStyledButton?.title == "Second", "styled button updates declarative title in place")

let cardContent = NSView()
let styledCard = FluentCard(contentView: cardContent, style: FluentElevatedCardStyle())
styledCard.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
styledCard.layoutSubtreeIfNeeded()
require(abs(cardContent.frame.minX - 20) < 0.001, "card style applies horizontal content inset")
require(styledCard.intrinsicContentSize.height >= 36, "card forwards content and style insets as intrinsic height")
styledCard.style = FluentPlainCardStyle()
styledCard.layoutSubtreeIfNeeded()
require(abs(cardContent.frame.minX) < 0.001, "card style updates content inset in place")

let styledToggleState = FluentState(wrappedValue: true)
let styledToggleHost = FluentViewHost(
    FluentToggleView("Styled toggle", isOn: styledToggleState.projectedValue)
        .toggleStyle(ValidationToggleStyle())
)
let nativeStyledToggle = firstToggle(in: styledToggleHost)
require(nativeStyledToggle?.fluentStyle != nil, "toggle style mounts on the native toggle")
require((nativeStyledToggle?.intrinsicContentSize.width ?? 0) > 48, "toggle style metrics affect intrinsic width")
styledToggleState.wrappedValue = false
drainMainQueue()
require(firstToggle(in: styledToggleHost) === nativeStyledToggle, "styled toggle binding updates preserve native identity")
require(nativeStyledToggle?.isOn == false, "styled toggle binding updates native state")

func toggleMouseEvent(
    _ type: NSEvent.EventType,
    at point: NSPoint,
    in view: NSView,
    eventNumber: Int
) -> NSEvent {
    let location = view.convert(point, to: nil)
    guard let event = NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: view.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(type) ? 0 : 1
    ) else {
        fatalError("could not create ToggleSwitch validation event")
    }
    return event
}

func sliderKeyEvent(_ keyCode: UInt16, in view: NSView, eventNumber: Int) -> NSEvent {
    guard let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: view.window?.windowNumber ?? 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    ) else {
        fatalError("could not create Slider validation key event")
    }
    return event
}

func toggleButtonKeyEvent(
    _ type: NSEvent.EventType,
    keyCode: UInt16,
    in view: NSView,
    eventNumber: Int
) -> NSEvent {
    guard let event = NSEvent.keyEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: view.window?.windowNumber ?? 0,
        context: nil,
        characters: keyCode == 49 ? " " : "\r",
        charactersIgnoringModifiers: keyCode == 49 ? " " : "\r",
        isARepeat: false,
        keyCode: keyCode
    ) else {
        fatalError("could not create ToggleButton validation key event")
    }
    return event
}

let automaticToggleButtonStyle = FluentAutomaticToggleButtonStyle()
let toggleButtonOffAppearance = automaticToggleButtonStyle.appearance(
    for: FluentToggleButtonStyleConfiguration(
        title: "Off",
        selectionState: .off,
        controlState: .normal,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let toggleButtonOnAppearance = automaticToggleButtonStyle.appearance(
    for: FluentToggleButtonStyleConfiguration(
        title: "On",
        selectionState: .on,
        controlState: .normal,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let toggleButtonOnPressedAppearance = automaticToggleButtonStyle.appearance(
    for: FluentToggleButtonStyleConfiguration(
        title: "On",
        selectionState: .on,
        controlState: .pressed,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let toggleButtonMixedAppearance = automaticToggleButtonStyle.appearance(
    for: FluentToggleButtonStyleConfiguration(
        title: "Mixed",
        selectionState: .mixed,
        controlState: .normal,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let toggleButtonDisabledAppearance = automaticToggleButtonStyle.appearance(
    for: FluentToggleButtonStyleConfiguration(
        title: "Disabled",
        selectionState: .on,
        controlState: .normal,
        isEnabled: false,
        controlSize: .regular,
        theme: theme
    )
)
require(
    colorMatches(toggleButtonOffAppearance.backgroundColor.cgColor, theme.buttonBackground(for: .normal))
        && toggleButtonOffAppearance.borderGradientColors?.count == 2,
    "ToggleButton Normal maps to ControlFillColorDefault and ControlElevationBorderBrush"
)
require(
    colorMatches(toggleButtonOnAppearance.backgroundColor.cgColor, theme.accentFill(for: .normal))
        && colorMatches(toggleButtonOnAppearance.foregroundColor.cgColor, theme.textOnAccent)
        && toggleButtonOnAppearance.borderGradientColors?.count == 2,
    "ToggleButton Checked maps to AccentFillColorDefault and AccentControlElevationBorderBrush"
)
require(
    colorMatches(toggleButtonOnPressedAppearance.backgroundColor.cgColor, theme.accentFill(for: .pressed))
        && colorMatches(toggleButtonOnPressedAppearance.foregroundColor.cgColor, theme.textOnAccentSecondary)
        && toggleButtonOnPressedAppearance.borderGradientColors == nil,
    "ToggleButton CheckedPressed maps to tertiary accent fill without elevation"
)
require(
    colorMatches(toggleButtonMixedAppearance.backgroundColor.cgColor, theme.buttonBackground(for: .normal)),
    "ToggleButton Indeterminate uses its source-defined unaccented surface"
)
require(
    colorMatches(toggleButtonDisabledAppearance.backgroundColor.cgColor, theme.accentFill(for: .disabled))
        && colorMatches(toggleButtonDisabledAppearance.foregroundColor.cgColor, theme.textOnAccentDisabled),
    "ToggleButton CheckedDisabled maps to disabled accent resources"
)

let interactiveToggleButtonState = FluentState(wrappedValue: FluentToggleButtonState.off)
var interactiveToggleButtonCommits: [FluentToggleButtonState] = []
let interactiveToggleButtonObserver = interactiveToggleButtonState.observe {
    interactiveToggleButtonCommits.append($0)
}
interactiveToggleButtonCommits.removeAll()
let interactiveToggleButtonHost = FluentViewHost(
    FluentToggleButtonView("Toggle button", state: interactiveToggleButtonState.projectedValue),
    context: FluentRenderContext(theme: theme, reduceMotion: false)
)
let interactiveToggleButtonWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
interactiveToggleButtonWindow.contentView = interactiveToggleButtonHost
interactiveToggleButtonHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
interactiveToggleButtonWindow.orderFront(nil)
interactiveToggleButtonHost.layoutSubtreeIfNeeded()
guard let interactiveToggleButton = firstToggleButton(in: interactiveToggleButtonHost),
      let interactiveToggleButtonBorder = firstLayer(
        named: "FluentKit.ToggleButton.ElevationBorder",
        in: interactiveToggleButtonHost
      ) as? CAGradientLayer else {
    fatalError("ToggleButton validation hierarchy did not mount")
}
require(
    interactiveToggleButton.selectionState == .off,
    "mounted ToggleButton reads its initial binding state"
)
require(
    interactiveToggleButton.accessibilityRole() == .checkBox
        && interactiveToggleButton.accessibilityValue() as? String == "Off",
    "mounted ToggleButton exposes native toggle accessibility"
)
require(
    interactiveToggleButton.intrinsicContentSize.height == theme.controlHeight,
    "ToggleButton preserves the WinUI 32pt default control height"
)
require(
    elevationGradientMatchesVisualEdge(
        interactiveToggleButtonBorder,
        edge: .bottom,
        hostView: interactiveToggleButton
    ),
    "ToggleButton resolves its visual elevation edge before pointer interaction"
)
interactiveToggleButtonState.wrappedValue = .on
drainMainQueue()
require(
    firstToggleButton(in: interactiveToggleButtonHost) === interactiveToggleButton
        && interactiveToggleButton.selectionState == .on,
    "ToggleButton binding updates preserve native identity"
)
interactiveToggleButtonState.wrappedValue = .off
drainMainQueue()
interactiveToggleButtonCommits.removeAll()

let toggleButtonPoint = NSPoint(x: interactiveToggleButton.bounds.midX, y: interactiveToggleButton.bounds.midY)
interactiveToggleButton.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: toggleButtonPoint, in: interactiveToggleButton, eventNumber: 12)
)
interactiveToggleButton.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: toggleButtonPoint, in: interactiveToggleButton, eventNumber: 13)
)
require(
    interactiveToggleButton.selectionState == .off
        && interactiveToggleButtonCommits.isEmpty
        && colorMatches(interactiveToggleButton.layer?.backgroundColor, theme.buttonBackground(for: .pressed)),
    "ToggleButton mouseDown enters Pressed without committing"
)
let toggleButtonBackgroundAnimation = interactiveToggleButton.layer?.animation(
    forKey: "fluent.toggleButton.background"
)
require(
    abs((toggleButtonBackgroundAnimation?.duration ?? 0) - FluentMotion.controlFaster.duration) < 0.0001,
    "ToggleButton surface transitions use the WinUI 83ms BrushTransition"
)
let toggleButtonOutsidePoint = NSPoint(x: -20, y: interactiveToggleButton.bounds.midY)
interactiveToggleButton.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: toggleButtonOutsidePoint, in: interactiveToggleButton, eventNumber: 14)
)
require(
    interactiveToggleButton.selectionState == .off && interactiveToggleButtonCommits.isEmpty,
    "ToggleButton release-outside cancels activation"
)
interactiveToggleButton.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: toggleButtonPoint, in: interactiveToggleButton, eventNumber: 15)
)
interactiveToggleButton.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: toggleButtonPoint, in: interactiveToggleButton, eventNumber: 16)
)
drainMainQueue()
require(
    interactiveToggleButton.selectionState == .on && interactiveToggleButtonCommits == [.on],
    "ToggleButton release-inside commits exactly once"
)
require(
    colorMatches(interactiveToggleButton.layer?.backgroundColor, theme.accentFill(for: .pointerOver))
        && interactiveToggleButtonBorder.colors?.count == 2,
    "ToggleButton CheckedPointerOver applies accent fill and elevation resources"
)

interactiveToggleButtonState.wrappedValue = .off
drainMainQueue()
interactiveToggleButtonCommits.removeAll()
interactiveToggleButtonWindow.makeFirstResponder(interactiveToggleButton)
interactiveToggleButton.keyDown(
    with: toggleButtonKeyEvent(.keyDown, keyCode: 49, in: interactiveToggleButton, eventNumber: 17)
)
require(
    interactiveToggleButton.selectionState == .off && interactiveToggleButtonCommits.isEmpty,
    "ToggleButton Space enters Pressed before committing"
)
interactiveToggleButton.keyUp(
    with: toggleButtonKeyEvent(.keyUp, keyCode: 49, in: interactiveToggleButton, eventNumber: 18)
)
drainMainQueue()
require(
    interactiveToggleButton.selectionState == .on && interactiveToggleButtonCommits == [.on],
    "ToggleButton Space release uses the same single-commit path"
)

interactiveToggleButton.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: toggleButtonPoint, in: interactiveToggleButton, eventNumber: 19)
)
interactiveToggleButtonState.wrappedValue = .off
drainMainQueue()
interactiveToggleButton.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: toggleButtonPoint, in: interactiveToggleButton, eventNumber: 20)
)
require(
    interactiveToggleButton.selectionState == .off,
    "external ToggleButton binding updates cancel an in-flight pointer activation"
)
require(
    interactiveToggleButton.accessibilityPerformPress()
        && interactiveToggleButton.selectionState == .on
        && interactiveToggleButton.accessibilityValue() as? String == "On",
    "ToggleButton accessibility press uses the shared activation path"
)
interactiveToggleButton.isEnabled = false
require(
    !interactiveToggleButton.accessibilityPerformPress(),
    "disabled ToggleButton rejects accessibility activation"
)
interactiveToggleButtonState.observableValue.removeObserver(interactiveToggleButtonObserver)
interactiveToggleButtonWindow.orderOut(nil)

let threeStateToggleButton = FluentToggleButton(title: "Three state", state: .on, allowsMixedState: true)
threeStateToggleButton.frame = NSRect(x: 0, y: 0, width: 160, height: 32)
threeStateToggleButton.layoutSubtreeIfNeeded()
require(
    threeStateToggleButton.accessibilityPerformPress()
        && threeStateToggleButton.selectionState == .mixed
        && threeStateToggleButton.accessibilityValue() as? String == "Mixed",
    "three-state ToggleButton cycles Checked to Indeterminate"
)
let threeStateGlyph = firstLayer(named: "FluentKit.ToggleButton.StateGlyph", in: threeStateToggleButton) as? CAShapeLayer
require(
    threeStateGlyph?.opacity == 1
        && pathVertices(threeStateGlyph?.path).count == 2,
    "three-state ToggleButton gives Indeterminate a visible dash while retaining the source surface"
)
require(
    threeStateToggleButton.accessibilityPerformPress() && threeStateToggleButton.selectionState == .off,
    "three-state ToggleButton cycles Indeterminate to Unchecked"
)
require(
    threeStateGlyph?.opacity == 0,
    "three-state ToggleButton removes its state glyph when returning to Unchecked"
)

let reducedToggleButtonState = FluentState(wrappedValue: FluentToggleButtonState.off)
let reducedToggleButtonHost = FluentViewHost(
    FluentToggleButtonView("Reduced", state: reducedToggleButtonState.projectedValue),
    context: FluentRenderContext(theme: theme, reduceMotion: true)
)
reducedToggleButtonHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
reducedToggleButtonHost.layoutSubtreeIfNeeded()
guard let reducedToggleButton = firstToggleButton(in: reducedToggleButtonHost) else {
    fatalError("Reduce Motion ToggleButton did not mount")
}
reducedToggleButton.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: reducedToggleButton.bounds.midX, y: reducedToggleButton.bounds.midY),
        in: reducedToggleButton,
        eventNumber: 21
    )
)
require(
    reducedToggleButton.layer?.animationKeys()?.isEmpty != false,
    "ToggleButton Reduce Motion reaches PointerOver without allocating animations"
)

let automaticRepeatButtonStyle = FluentAutomaticRepeatButtonStyle()
let repeatButtonNormalAppearance = automaticRepeatButtonStyle.appearance(
    for: FluentRepeatButtonStyleConfiguration(
        title: "Repeat",
        controlState: .normal,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let repeatButtonPointerAppearance = automaticRepeatButtonStyle.appearance(
    for: FluentRepeatButtonStyleConfiguration(
        title: "Repeat",
        controlState: .pointerOver,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let repeatButtonPressedAppearance = automaticRepeatButtonStyle.appearance(
    for: FluentRepeatButtonStyleConfiguration(
        title: "Repeat",
        controlState: .pressed,
        isEnabled: true,
        controlSize: .regular,
        theme: theme
    )
)
let repeatButtonDisabledAppearance = automaticRepeatButtonStyle.appearance(
    for: FluentRepeatButtonStyleConfiguration(
        title: "Repeat",
        controlState: .normal,
        isEnabled: false,
        controlSize: .regular,
        theme: theme
    )
)
require(
    colorMatches(repeatButtonNormalAppearance.backgroundColor.cgColor, theme.buttonBackground(for: .normal))
        && repeatButtonNormalAppearance.borderGradientColors?.count == 2
        && repeatButtonNormalAppearance.borderGradientEdge == .bottom,
    "RepeatButton Normal maps to ControlFillColorDefault and ControlElevationBorderBrush"
)
require(
    colorMatches(repeatButtonPointerAppearance.backgroundColor.cgColor, theme.buttonBackground(for: .pointerOver))
        && repeatButtonPointerAppearance.borderGradientColors?.count == 2,
    "RepeatButton PointerOver maps to ControlFillColorSecondary and elevation resources"
)
require(
    colorMatches(repeatButtonPressedAppearance.backgroundColor.cgColor, theme.buttonBackground(for: .pressed))
        && colorMatches(repeatButtonPressedAppearance.foregroundColor.cgColor, theme.buttonForeground(for: .pressed))
        && repeatButtonPressedAppearance.borderGradientColors == nil,
    "RepeatButton Pressed maps to tertiary fill and the ordinary control stroke"
)
require(
    colorMatches(repeatButtonDisabledAppearance.backgroundColor.cgColor, theme.buttonBackground(for: .disabled))
        && colorMatches(repeatButtonDisabledAppearance.foregroundColor.cgColor, theme.buttonForeground(for: .disabled)),
    "RepeatButton Disabled maps to disabled control resources"
)

let repeatButtonTitle = FluentObservable("Hold")
struct RepeatButtonIdentityProbe: FluentView {
    let title: FluentObservable<String>
    let action: () -> Void

    var body: FluentRepeatButtonView {
        FluentRepeatButtonView(title.value, action: action)
    }
}
let repeatButtonIdentityHost = FluentViewHost(
    RepeatButtonIdentityProbe(title: repeatButtonTitle, action: {})
)
let nativeIdentityRepeatButton = firstRepeatButton(in: repeatButtonIdentityHost)
repeatButtonTitle.value = "Keep holding"
drainMainQueue()
require(
    firstRepeatButton(in: repeatButtonIdentityHost) === nativeIdentityRepeatButton
        && nativeIdentityRepeatButton?.title == "Keep holding",
    "RepeatButton declarative updates preserve native identity"
)

var repeatButtonInvocations = 0
let interactiveRepeatButtonHost = FluentViewHost(
    FluentRepeatButtonView("Hold +", delay: 0.040, interval: 0.020) {
        repeatButtonInvocations += 1
    },
    context: FluentRenderContext(theme: theme, reduceMotion: false)
)
let interactiveRepeatButtonWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
interactiveRepeatButtonWindow.contentView = interactiveRepeatButtonHost
interactiveRepeatButtonHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
interactiveRepeatButtonWindow.orderFront(nil)
interactiveRepeatButtonHost.layoutSubtreeIfNeeded()
guard let interactiveRepeatButton = firstRepeatButton(in: interactiveRepeatButtonHost),
      let repeatButtonElevationBorder = firstLayer(
        named: "FluentKit.RepeatButton.ElevationBorder",
        in: interactiveRepeatButtonHost
      ) as? CAGradientLayer,
      let repeatButtonFocus = firstLayer(
        named: "FluentKit.RepeatButton.FocusRing",
        in: interactiveRepeatButtonHost
      ) else {
    fatalError("RepeatButton validation hierarchy did not mount")
}
require(
    FluentRepeatButton.defaultDelay == 0.500
        && FluentRepeatButton.defaultInterval == 0.033
        && interactiveRepeatButton.intrinsicContentSize.height == theme.controlHeight
        && interactiveRepeatButton.accessibilityRole() == .button,
    "RepeatButton exposes the WinUI 500ms/33ms defaults, Button geometry, and native role"
)
require(
    elevationGradientMatchesVisualEdge(
        repeatButtonElevationBorder,
        edge: .bottom,
        hostView: interactiveRepeatButton
    ),
    "RepeatButton resolves its visual elevation edge before pointer interaction"
)
let repeatButtonPoint = NSPoint(
    x: interactiveRepeatButton.bounds.midX,
    y: interactiveRepeatButton.bounds.midY
)
interactiveRepeatButton.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: repeatButtonPoint, in: interactiveRepeatButton, eventNumber: 22)
)
interactiveRepeatButton.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: repeatButtonPoint, in: interactiveRepeatButton, eventNumber: 23)
)
require(
    repeatButtonInvocations == 1
        && colorMatches(interactiveRepeatButton.layer?.backgroundColor, theme.buttonBackground(for: .pressed)),
    "RepeatButton uses ClickMode Press and enters Pressed before its delay"
)
let repeatButtonBackgroundAnimation = interactiveRepeatButton.layer?.animation(
    forKey: "fluent.repeatButton.background"
)
require(
    abs((repeatButtonBackgroundAnimation?.duration ?? 0) - FluentMotion.controlFaster.duration) < 0.0001,
    "RepeatButton background uses the source 83ms BrushTransition"
)
require(
    waitUntil(timeout: 0.20) { repeatButtonInvocations >= 3 },
    "RepeatButton invokes after its delay and continues at its interval"
)

let repeatButtonOutsidePoint = NSPoint(x: -20, y: interactiveRepeatButton.bounds.midY)
interactiveRepeatButton.mouseDragged(
    with: toggleMouseEvent(
        .leftMouseDragged,
        at: repeatButtonOutsidePoint,
        in: interactiveRepeatButton,
        eventNumber: 24
    )
)
let repeatCountOutside = repeatButtonInvocations
require(
    !waitUntil(timeout: 0.080) { repeatButtonInvocations != repeatCountOutside },
    "RepeatButton stops repeating while a pressed pointer is outside"
)
interactiveRepeatButton.mouseDragged(
    with: toggleMouseEvent(
        .leftMouseDragged,
        at: repeatButtonPoint,
        in: interactiveRepeatButton,
        eventNumber: 25
    )
)
require(
    repeatButtonInvocations == repeatCountOutside,
    "RepeatButton pointer re-entry restarts the delay without an extra immediate click"
)
require(
    waitUntil(timeout: 0.16) { repeatButtonInvocations > repeatCountOutside },
    "RepeatButton resumes after the restarted delay"
)
interactiveRepeatButton.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: repeatButtonPoint, in: interactiveRepeatButton, eventNumber: 26)
)
let repeatCountAfterPointerRelease = repeatButtonInvocations
require(
    !waitUntil(timeout: 0.080) { repeatButtonInvocations != repeatCountAfterPointerRelease },
    "RepeatButton pointer release cancels its interval timer"
)

repeatButtonInvocations = 0
interactiveRepeatButtonWindow.makeFirstResponder(interactiveRepeatButton)
interactiveRepeatButton.keyDown(
    with: toggleButtonKeyEvent(.keyDown, keyCode: 49, in: interactiveRepeatButton, eventNumber: 27)
)
require(
    repeatButtonInvocations == 1 && repeatButtonFocus.opacity == 1,
    "RepeatButton Space presses immediately and reveals keyboard focus"
)
require(
    waitUntil(timeout: 0.20) { repeatButtonInvocations >= 3 },
    "RepeatButton Space follows the same delayed repeat path"
)
interactiveRepeatButton.keyUp(
    with: toggleButtonKeyEvent(.keyUp, keyCode: 49, in: interactiveRepeatButton, eventNumber: 28)
)
let repeatCountAfterKeyRelease = repeatButtonInvocations
require(
    !waitUntil(timeout: 0.080) { repeatButtonInvocations != repeatCountAfterKeyRelease },
    "RepeatButton Space release cancels repeating"
)
repeatButtonInvocations = 0
interactiveRepeatButton.keyDown(
    with: toggleButtonKeyEvent(.keyDown, keyCode: 36, in: interactiveRepeatButton, eventNumber: 29)
)
require(
    repeatButtonInvocations == 1
        && !waitUntil(timeout: 0.080) { repeatButtonInvocations != 1 },
    "RepeatButton Return invokes once without starting Space repeat behavior"
)
repeatButtonInvocations = 0
interactiveRepeatButton.keyDown(
    with: toggleButtonKeyEvent(.keyDown, keyCode: 49, in: interactiveRepeatButton, eventNumber: 30)
)
interactiveRepeatButton.keyDown(
    with: toggleButtonKeyEvent(.keyDown, keyCode: 53, in: interactiveRepeatButton, eventNumber: 31)
)
require(
    repeatButtonInvocations == 1
        && !waitUntil(timeout: 0.080) { repeatButtonInvocations != 1 },
    "RepeatButton Escape cancels an active keyboard repeat"
)
interactiveRepeatButton.keyDown(
    with: toggleButtonKeyEvent(.keyDown, keyCode: 49, in: interactiveRepeatButton, eventNumber: 32)
)
_ = interactiveRepeatButtonWindow.makeFirstResponder(nil)
let repeatCountAfterFocusLoss = repeatButtonInvocations
require(
    !waitUntil(timeout: 0.080) { repeatButtonInvocations != repeatCountAfterFocusLoss },
    "RepeatButton focus loss cancels an active keyboard repeat"
)
require(
    interactiveRepeatButton.accessibilityPerformPress()
        && repeatButtonInvocations == repeatCountAfterFocusLoss + 1,
    "RepeatButton accessibility press invokes exactly once"
)
interactiveRepeatButton.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: repeatButtonPoint, in: interactiveRepeatButton, eventNumber: 33)
)
interactiveRepeatButton.isEnabled = false
let repeatCountAfterDisable = repeatButtonInvocations
require(
    !waitUntil(timeout: 0.080) { repeatButtonInvocations != repeatCountAfterDisable }
        && !interactiveRepeatButton.accessibilityPerformPress(),
    "disabling RepeatButton cancels active repetition and rejects activation"
)
interactiveRepeatButton.isEnabled = true
repeatButtonInvocations = 0
interactiveRepeatButton.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: repeatButtonPoint, in: interactiveRepeatButton, eventNumber: 34)
)
interactiveRepeatButton.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: repeatButtonPoint, in: interactiveRepeatButton, eventNumber: 35)
)
interactiveRepeatButtonWindow.contentView = NSView()
let repeatCountAfterRemoval = repeatButtonInvocations
require(
    !waitUntil(timeout: 0.080) { repeatButtonInvocations != repeatCountAfterRemoval },
    "removing RepeatButton from its window cancels active repetition"
)
interactiveRepeatButtonWindow.orderOut(nil)

var callbackRemovalCount = 0
let callbackRemovalButton = FluentRepeatButton(title: "Remove", delay: 0.020, interval: 0.010)
let callbackRemovalWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 120, height: 32),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
callbackRemovalButton.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
callbackRemovalWindow.contentView = callbackRemovalButton
callbackRemovalWindow.orderFront(nil)
callbackRemovalButton.onClick = {
    callbackRemovalCount += 1
    callbackRemovalWindow.contentView = NSView()
}
callbackRemovalButton.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: 60, y: 16),
        in: callbackRemovalButton,
        eventNumber: 36
    )
)
require(
    callbackRemovalCount == 1
        && !waitUntil(timeout: 0.060) { callbackRemovalCount != 1 },
    "RepeatButton does not schedule a tick after its callback removes it from the window"
)
callbackRemovalWindow.orderOut(nil)

let reducedRepeatButtonHost = FluentViewHost(
    FluentRepeatButtonView("Reduced") {},
    context: FluentRenderContext(theme: theme, reduceMotion: true)
)
reducedRepeatButtonHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
reducedRepeatButtonHost.layoutSubtreeIfNeeded()
guard let reducedRepeatButton = firstRepeatButton(in: reducedRepeatButtonHost) else {
    fatalError("Reduce Motion RepeatButton did not mount")
}
reducedRepeatButton.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: reducedRepeatButton.bounds.midX, y: reducedRepeatButton.bounds.midY),
        in: reducedRepeatButton,
        eventNumber: 37
    )
)
require(
    reducedRepeatButton.layer?.animationKeys()?.isEmpty != false,
    "RepeatButton Reduce Motion reaches PointerOver without allocating animations"
)

let interactiveToggleState = FluentState(wrappedValue: false)
var interactiveToggleCommits: [Bool] = []
let interactiveToggleObserver = interactiveToggleState.observe { interactiveToggleCommits.append($0) }
interactiveToggleCommits.removeAll()
let interactiveToggleHost = FluentViewHost(
    FluentToggleView("Notifications", isOn: interactiveToggleState.projectedValue),
    context: FluentRenderContext(reduceMotion: false)
)
let interactiveToggleWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
interactiveToggleWindow.contentView = interactiveToggleHost
interactiveToggleHost.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
interactiveToggleWindow.orderFront(nil)
interactiveToggleHost.layoutSubtreeIfNeeded()
guard let interactiveToggle = firstToggle(in: interactiveToggleHost),
      let interactiveTrack = firstLayer(named: "FluentKit.Toggle.Track", in: interactiveToggleHost),
      let interactiveKnob = firstLayer(named: "FluentKit.Toggle.Knob", in: interactiveToggleHost),
      let interactiveFocus = firstLayer(named: "FluentKit.Toggle.FocusRing", in: interactiveToggleHost) else {
    fatalError("ToggleSwitch validation hierarchy did not mount")
}
require(
    interactiveTrack.frame.size == CGSize(width: 40, height: 20)
        && interactiveKnob.frame.size == CGSize(width: 12, height: 12),
    "mounted ToggleSwitch starts with exact normal geometry"
)

let togglePoint = NSPoint(x: interactiveToggle.bounds.maxX - 30, y: interactiveToggle.bounds.midY)
interactiveToggle.mouseEntered(with: toggleMouseEvent(.mouseMoved, at: togglePoint, in: interactiveToggle, eventNumber: 1))
require(
    interactiveKnob.bounds.size == CGSize(width: 14, height: 14),
    "mounted ToggleSwitch applies pointer-over knob geometry"
)
interactiveToggle.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: togglePoint, in: interactiveToggle, eventNumber: 2))
require(
    !interactiveToggleState.wrappedValue && interactiveToggleCommits.isEmpty,
    "ToggleSwitch mouseDown enters Pressed without committing the binding"
)
require(
    interactiveKnob.bounds.size == CGSize(width: 17, height: 14),
    "ToggleSwitch Pressed applies the 17x14 target geometry"
)
let pressedBoundsAnimation = interactiveKnob.animation(forKey: "fluent.toggle.knob.bounds") as? CABasicAnimation
require(
    abs((pressedBoundsAnimation?.duration ?? 0) - 0.083) < 0.0001
        && pressedBoundsAnimation?.timingFunction != nil,
    "ToggleSwitch state geometry uses the 83ms control-fast-out-slow-in motion"
)
interactiveToggle.layout()
require(
    interactiveKnob.animation(forKey: "fluent.toggle.knob.bounds") != nil,
    "same-bounds ToggleSwitch layout does not overwrite an active state animation"
)
interactiveToggle.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: togglePoint, in: interactiveToggle, eventNumber: 3))
let toggleRepositionAnimation = interactiveKnob.animation(forKey: "fluent.toggle.knob.position") as? CABasicAnimation
let toggleReleaseBoundsAnimation = interactiveKnob.animation(forKey: "fluent.toggle.knob.bounds") as? CABasicAnimation
require(
    abs((toggleRepositionAnimation?.duration ?? 0) - FluentMotion.controlFast.duration) < 0.0001
        && abs((toggleReleaseBoundsAnimation?.duration ?? 0) - FluentMotion.controlFaster.duration) < 0.0001,
    "ToggleSwitch uses 167ms reposition motion while its common-state geometry remains 83ms"
)
drainMainQueue()
require(
    interactiveToggleState.wrappedValue && interactiveToggleCommits == [true],
    "ToggleSwitch release-inside commits its binding exactly once"
)
require(
    interactiveKnob.animation(forKey: "fluent.toggle.knob.position") != nil,
    "ToggleSwitch keeps release motion alive across its binding-driven declarative update"
)
require(
    interactiveTrack.borderWidth == 0,
    "mounted ToggleSwitch On state removes the generic AppKit-style track border"
)
interactiveToggleWindow.makeFirstResponder(interactiveToggle)
require(interactiveFocus.opacity == 0, "ToggleSwitch hides focus visuals after pointer focus")
interactiveToggle.keyDown(with: sliderKeyEvent(53, in: interactiveToggle, eventNumber: 3))
require(interactiveFocus.opacity == 1, "ToggleSwitch renders a custom keyboard focus ring")

let dragStart = NSPoint(x: interactiveToggle.bounds.maxX - 10, y: interactiveToggle.bounds.midY)
let dragEnd = NSPoint(x: interactiveToggle.bounds.maxX - 35, y: interactiveToggle.bounds.midY)
interactiveToggle.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: dragStart, in: interactiveToggle, eventNumber: 4))
let pressedOnKnobX = interactiveKnob.frame.minX
interactiveToggle.mouseDragged(with: toggleMouseEvent(.leftMouseDragged, at: dragEnd, in: interactiveToggle, eventNumber: 5))
require(
    interactiveToggleState.wrappedValue
        && interactiveKnob.bounds.size == CGSize(width: 17, height: 14)
        && interactiveKnob.frame.minX < pressedOnKnobX,
    "ToggleSwitch dragging moves the pressed knob directly without committing early"
)
interactiveToggle.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: dragEnd, in: interactiveToggle, eventNumber: 6))
drainMainQueue()
require(
    !interactiveToggleState.wrappedValue && interactiveToggleCommits == [true, false],
    "ToggleSwitch drag release resolves direction and commits once"
)

interactiveToggle.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: togglePoint, in: interactiveToggle, eventNumber: 7))
let outsidePoint = NSPoint(x: -20, y: interactiveToggle.bounds.midY)
interactiveToggle.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: outsidePoint, in: interactiveToggle, eventNumber: 8))
require(
    !interactiveToggleState.wrappedValue && interactiveToggleCommits == [true, false],
    "ToggleSwitch release-outside cancels a non-drag click"
)

interactiveToggle.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: dragStart, in: interactiveToggle, eventNumber: 9))
interactiveToggle.mouseDragged(with: toggleMouseEvent(.leftMouseDragged, at: dragEnd, in: interactiveToggle, eventNumber: 10))
interactiveToggleState.wrappedValue = true
drainMainQueue()
interactiveToggle.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: dragEnd, in: interactiveToggle, eventNumber: 11))
require(
    interactiveToggleState.wrappedValue,
    "external ToggleSwitch binding updates cancel an in-flight drag without a stale commit"
)
require(
    interactiveToggle.accessibilityPerformPress() && !interactiveToggleState.wrappedValue,
    "ToggleSwitch accessibility press uses the same single-commit path"
)
interactiveToggle.isEnabled = false
require(
    !interactiveToggle.accessibilityPerformPress() && !interactiveToggleState.wrappedValue,
    "disabled ToggleSwitch rejects accessibility activation"
)
interactiveToggleState.observableValue.removeObserver(interactiveToggleObserver)
interactiveToggleWindow.orderOut(nil)

let rtlToggleState = FluentState(wrappedValue: false)
let rtlToggleHost = FluentViewHost(
    FluentToggleView("RTL", isOn: rtlToggleState.projectedValue),
    context: FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
)
rtlToggleHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
rtlToggleHost.layoutSubtreeIfNeeded()
guard let rtlToggle = firstToggle(in: rtlToggleHost),
      let rtlTrack = firstLayer(named: "FluentKit.Toggle.Track", in: rtlToggleHost),
      let rtlKnob = firstLayer(named: "FluentKit.Toggle.Knob", in: rtlToggleHost) else {
    fatalError("RTL ToggleSwitch validation hierarchy did not mount")
}
let rtlOffX = rtlKnob.frame.minX
rtlToggleState.wrappedValue = true
drainMainQueue()
require(
    rtlTrack.frame.minX == 0 && rtlKnob.frame.minX < rtlOffX,
    "ToggleSwitch mirrors track placement and On direction in RTL"
)

let reducedToggleState = FluentState(wrappedValue: false)
let reducedToggleHost = FluentViewHost(
    FluentToggleView("Reduced motion", isOn: reducedToggleState.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
reducedToggleHost.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
reducedToggleHost.layoutSubtreeIfNeeded()
let reducedToggleKnob = firstLayer(named: "FluentKit.Toggle.Knob", in: reducedToggleHost)
reducedToggleState.wrappedValue = true
drainMainQueue()
require(
    reducedToggleKnob?.animationKeys()?.isEmpty != false,
    "ToggleSwitch Reduce Motion updates final geometry without allocating animations"
)

let styledSliderState = FluentState(wrappedValue: 0.4)
let styledSliderHost = FluentViewHost(
    FluentSliderView(value: styledSliderState.projectedValue)
        .sliderStyle(ValidationSliderStyle())
)
let nativeStyledSlider = firstSlider(in: styledSliderHost)
require(nativeStyledSlider?.fluentStyle != nil, "slider style mounts on the native slider")
styledSliderState.wrappedValue = 0.8
drainMainQueue()
require(firstSlider(in: styledSliderHost) === nativeStyledSlider, "styled slider binding updates preserve native identity")
require(abs((nativeStyledSlider?.value ?? 0) - 0.8) < 0.0001, "styled slider binding updates native value")

let interactiveSliderState = FluentState(wrappedValue: 0.25)
let interactiveSliderHost = FluentViewHost(
    FluentSliderView(value: interactiveSliderState.projectedValue),
    context: FluentRenderContext(reduceMotion: false)
)
let interactiveSliderWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
interactiveSliderWindow.contentView = interactiveSliderHost
interactiveSliderHost.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
interactiveSliderWindow.orderFront(nil)
interactiveSliderHost.layoutSubtreeIfNeeded()
guard let interactiveSlider = firstSlider(in: interactiveSliderHost),
      let sliderTrack = firstLayer(named: "FluentKit.Slider.Track", in: interactiveSliderHost),
      let sliderFill = firstLayer(named: "FluentKit.Slider.Fill", in: interactiveSliderHost),
      let sliderOuterThumb = firstLayer(named: "FluentKit.Slider.OuterThumb", in: interactiveSliderHost),
      let sliderInnerThumb = firstLayer(named: "FluentKit.Slider.InnerThumb", in: interactiveSliderHost),
      let sliderFocus = firstLayer(named: "FluentKit.Slider.FocusRing", in: interactiveSliderHost) else {
    fatalError("Slider validation hierarchy did not mount")
}
require(
    sliderTrack.bounds.height == 4
        && sliderOuterThumb.bounds.size == CGSize(width: 18, height: 18)
        && sliderInnerThumb.bounds.size == CGSize(width: 12, height: 12),
    "mounted Slider starts with exact track and two-layer thumb geometry"
)
require(sliderFill.bounds.width > 0, "mounted Slider renders its current-value fill")

let sliderHoverPoint = NSPoint(x: interactiveSlider.bounds.midX, y: interactiveSlider.bounds.midY)
interactiveSlider.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: sliderHoverPoint, in: interactiveSlider, eventNumber: 20)
)
require(
    sliderInnerThumb.bounds.size == CGSize(width: 14, height: 14),
    "Slider PointerOver grows only the inner thumb to 14pt"
)
let sliderHoverAnimation = sliderInnerThumb.animation(forKey: "fluent.slider.inner.bounds") as? CABasicAnimation
require(
    abs((sliderHoverAnimation?.duration ?? 0) - 0.250) < 0.0001
        && sliderHoverAnimation?.timingFunction != nil,
    "Slider PointerOver uses the 250ms control-fast-out-slow-in motion"
)
interactiveSlider.layout()
require(
    sliderInnerThumb.animation(forKey: "fluent.slider.inner.bounds") != nil,
    "same-bounds Slider layout preserves an active thumb-state animation"
)

let sliderPressPoint = NSPoint(x: interactiveSlider.bounds.width * 0.72, y: interactiveSlider.bounds.midY)
interactiveSlider.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: sliderPressPoint, in: interactiveSlider, eventNumber: 21)
)
require(
    abs(interactiveSliderState.wrappedValue - 0.72) < 0.03,
    "Slider mouseDown updates its bound value directly"
)
require(
    sliderInnerThumb.bounds.size == CGSize(width: 10, height: 10),
    "Slider Pressed contracts only the inner thumb to 10pt"
)
let sliderPressedAnimation = sliderInnerThumb.animation(forKey: "fluent.slider.inner.bounds") as? CABasicAnimation
require(
    abs((sliderPressedAnimation?.duration ?? 0) - 0.250) < 0.0001,
    "Slider Pressed geometry uses the 250ms state motion"
)
require(
    sliderOuterThumb.animationKeys()?.isEmpty != false,
    "Slider thumb position updates directly without Core Animation interpolation"
)

let sliderDragPoint = NSPoint(x: interactiveSlider.bounds.width * 0.90, y: interactiveSlider.bounds.midY)
let pressedSliderX = sliderOuterThumb.frame.minX
interactiveSlider.mouseDragged(
    with: toggleMouseEvent(.leftMouseDragged, at: sliderDragPoint, in: interactiveSlider, eventNumber: 22)
)
require(
    interactiveSliderState.wrappedValue > 0.85 && sliderOuterThumb.frame.minX > pressedSliderX,
    "Slider dragging moves its bound value and thumb position directly"
)
interactiveSlider.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: sliderDragPoint, in: interactiveSlider, eventNumber: 23)
)
require(
    sliderInnerThumb.bounds.size == CGSize(width: 14, height: 14),
    "Slider release-inside returns to PointerOver geometry"
)
interactiveSlider.mouseExited(
    with: toggleMouseEvent(.mouseMoved, at: NSPoint(x: -10, y: 20), in: interactiveSlider, eventNumber: 24)
)
let sliderNormalAnimation = sliderInnerThumb.animation(forKey: "fluent.slider.inner.bounds") as? CABasicAnimation
require(
    sliderInnerThumb.bounds.size == CGSize(width: 12, height: 12)
        && abs((sliderNormalAnimation?.duration ?? 0) - 0.167) < 0.0001,
    "Slider Normal uses 12pt inner geometry and the 167ms return motion"
)

interactiveSliderWindow.makeFirstResponder(interactiveSlider)
require(sliderFocus.opacity == 0, "Slider hides focus visuals after pointer focus")
let keyboardStart = interactiveSlider.value
interactiveSlider.keyDown(with: sliderKeyEvent(123, in: interactiveSlider, eventNumber: 25))
require(interactiveSlider.value < keyboardStart && sliderFocus.opacity == 1, "Slider Left Arrow decrements in LTR and reveals keyboard focus")
interactiveSlider.keyDown(with: sliderKeyEvent(115, in: interactiveSlider, eventNumber: 26))
require(interactiveSlider.value == 0, "Slider Home moves to its logical minimum")
interactiveSlider.keyDown(with: sliderKeyEvent(119, in: interactiveSlider, eventNumber: 27))
require(interactiveSlider.value == 1, "Slider End moves to its logical maximum")

interactiveSlider.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: sliderHoverPoint, in: interactiveSlider, eventNumber: 28)
)
interactiveSliderState.wrappedValue = 0.35
drainMainQueue()
interactiveSlider.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: sliderDragPoint, in: interactiveSlider, eventNumber: 29)
)
require(
    abs(interactiveSlider.value - 0.35) < 0.0001,
    "external Slider binding updates cancel an in-flight drag without stale input"
)

interactiveSlider.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: sliderDragPoint, in: interactiveSlider, eventNumber: 30)
)
interactiveSlider.cancelOperation(nil)
require(
    abs(interactiveSlider.value - 0.35) < 0.0001,
    "Slider Escape cancellation restores the value from interaction start"
)
let accessibilityStart = interactiveSlider.value
require(
    interactiveSlider.accessibilityPerformIncrement()
        && interactiveSlider.value > accessibilityStart
        && interactiveSlider.accessibilityPerformDecrement()
        && abs(interactiveSlider.value - accessibilityStart) < 0.0001,
    "Slider accessibility increment and decrement share the bounded step path"
)
interactiveSlider.isEnabled = false
let disabledSliderValue = interactiveSlider.value
require(
    sliderInnerThumb.bounds.size == CGSize(width: 14, height: 14)
        && !interactiveSlider.accessibilityPerformIncrement()
        && interactiveSlider.value == disabledSliderValue,
    "disabled Slider uses 14pt inner geometry and rejects accessibility input"
)
interactiveSliderWindow.orderOut(nil)

let rtlSliderState = FluentState(wrappedValue: 0.0)
let rtlSliderHost = FluentViewHost(
    FluentSliderView(value: rtlSliderState.projectedValue),
    context: FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
)
rtlSliderHost.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
rtlSliderHost.layoutSubtreeIfNeeded()
guard let rtlSlider = firstSlider(in: rtlSliderHost),
      let rtlSliderOuterThumb = firstLayer(named: "FluentKit.Slider.OuterThumb", in: rtlSliderHost) else {
    fatalError("RTL Slider validation hierarchy did not mount")
}
let rtlMinimumX = rtlSliderOuterThumb.frame.minX
rtlSlider.keyDown(with: sliderKeyEvent(123, in: rtlSlider, eventNumber: 31))
require(
    rtlSlider.value > 0 && rtlSliderOuterThumb.frame.minX < rtlMinimumX,
    "Slider mirrors its logical direction and Left Arrow behavior in RTL"
)
rtlSlider.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: 9, y: rtlSlider.bounds.midY),
        in: rtlSlider,
        eventNumber: 32
    )
)
rtlSlider.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: 9, y: rtlSlider.bounds.midY),
        in: rtlSlider,
        eventNumber: 33
    )
)
require(rtlSlider.value > 0.99, "Slider maps the physical left endpoint to maximum in RTL")

let reducedSliderState = FluentState(wrappedValue: 0.5)
let reducedSliderHost = FluentViewHost(
    FluentSliderView(value: reducedSliderState.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
reducedSliderHost.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
reducedSliderHost.layoutSubtreeIfNeeded()
guard let reducedSlider = firstSlider(in: reducedSliderHost),
      let reducedSliderInnerThumb = firstLayer(named: "FluentKit.Slider.InnerThumb", in: reducedSliderHost) else {
    fatalError("Reduce Motion Slider validation hierarchy did not mount")
}
reducedSlider.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: reducedSlider.bounds.midX, y: reducedSlider.bounds.midY),
        in: reducedSlider,
        eventNumber: 34
    )
)
require(
    reducedSliderInnerThumb.bounds.size == CGSize(width: 14, height: 14)
        && reducedSliderInnerThumb.animationKeys()?.isEmpty != false,
    "Slider Reduce Motion reaches PointerOver geometry without allocating animations"
)

let styledTextState = FluentState(wrappedValue: "styled")
let styledTextHost = FluentViewHost(
    FluentTextFieldView(text: styledTextState.projectedValue, placeholder: "Styled input")
        .textFieldStyle(ValidationTextFieldStyle())
)
let nativeStyledTextField = firstFluentTextField(in: styledTextHost)
require(nativeStyledTextField?.fluentStyle != nil, "text field style mounts on the native field")
require(
    nativeStyledTextField?.usesSingleLineMode == true
        && nativeStyledTextField?.maximumNumberOfLines == 1
        && nativeStyledTextField?.cell?.wraps == false
        && nativeStyledTextField?.cell?.isScrollable == true,
    "TextBox explicitly uses the shared one-line scrolling cell protocol"
)
styledTextState.wrappedValue = "updated"
drainMainQueue()
require(firstFluentTextField(in: styledTextHost) === nativeStyledTextField, "styled text field updates preserve native identity")
require(nativeStyledTextField?.stringValue == "updated", "styled text field binding updates native text")

let styledProgressValue = FluentObservable(0.35)
struct StyledProgressProbe: FluentView {
    let value: FluentObservable<Double>

    var body: FluentProgressBar {
        FluentProgressBar(value: value.value).progressStyle(ValidationProgressStyle())
    }
}
let styledProgressHost = FluentViewHost(StyledProgressProbe(value: styledProgressValue))
let nativeStyledProgress = firstProgressBar(in: styledProgressHost)
require(nativeStyledProgress?.fluentStyle is ValidationProgressStyle, "progress style mounts on the native progress bar")
require(nativeStyledProgress?.intrinsicContentSize.height == 8, "progress style controls intrinsic track height")
styledProgressValue.value = 0.8
drainMainQueue()
require(firstProgressBar(in: styledProgressHost) === nativeStyledProgress, "styled progress updates preserve native identity")
require(abs((nativeStyledProgress?.value ?? 0) - 0.8) < 0.0001, "styled progress updates declarative value in place")
let progressAccessibilityValue = (nativeStyledProgress?.accessibilityValue() as? NSNumber)?.doubleValue ?? -1
require(abs(progressAccessibilityValue - 0.8) < 0.0001, "progress updates expose the current accessibility value")

let progressHost = FluentViewHost(
    FluentProgressBar(value: 0.25),
    context: FluentRenderContext(reduceMotion: false)
)
let progressWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 240, height: 32),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
progressWindow.contentView = progressHost
progressHost.frame = NSRect(x: 0, y: 0, width: 240, height: 32)
progressWindow.orderFront(nil)
progressHost.layoutSubtreeIfNeeded()
guard let progress = firstProgressBar(in: progressHost),
      let progressTrack = firstLayer(named: "FluentKit.ProgressBar.Track", in: progressHost),
      let progressDeterminate = firstLayer(named: "FluentKit.ProgressBar.Determinate", in: progressHost),
      let progressPrimary = firstLayer(named: "FluentKit.ProgressBar.Indeterminate.Primary", in: progressHost),
      let progressSecondary = firstLayer(named: "FluentKit.ProgressBar.Indeterminate.Secondary", in: progressHost) else {
    fatalError("ProgressBar validation hierarchy did not mount")
}
require(
    progressTrack.frame.height == 1
        && progressDeterminate.frame.height == 3
        && abs(progressDeterminate.bounds.width - 60) < 0.001,
    "ProgressBar starts with source-derived 1pt track, 3pt indicator, and determinate width"
)
progress.value = 0.75
let progressValueAnimation = progressDeterminate.animation(forKey: "fluent.progress.value") as? CABasicAnimation
require(
    abs((progressValueAnimation?.duration ?? 0) - 0.250) < 0.0001
        && abs((progressValueAnimation?.fromValue as? CGFloat ?? -1) - 60) < 0.001
        && abs((progressValueAnimation?.toValue as? CGFloat ?? -1) - 180) < 0.001,
    "ProgressBar value uses presentation-sampled 250ms reposition motion"
)
progress.layout()
require(
    progressDeterminate.animation(forKey: "fluent.progress.value") != nil,
    "same-bounds ProgressBar layout preserves active value motion"
)
progress.isIndeterminate = true
require(
    progressPrimary.animation(forKey: "fluent.progress.indeterminate.primary") != nil
        && progressSecondary.animation(forKey: "fluent.progress.indeterminate.secondary") != nil
        && progressDeterminate.opacity == 0,
    "normal indeterminate ProgressBar uses stable dual-layer motion"
)
progress.progressState = .paused
require(
        progressSecondary.animation(forKey: "fluent.progress.indeterminate.settle") != nil
        && progress.accessibilityValue() as? String == "Indeterminate"
        && progress.accessibilityHelp() == "Paused",
    "paused ProgressBar settles and exposes its state to accessibility"
)
progress.progressState = .error
require(
    progress.accessibilityHelp() == "Error"
        && progressSecondary.backgroundColor != nil,
    "error ProgressBar exposes error state and keeps a stable indicator layer"
)

let reducedProgressHost = FluentViewHost(
    FluentProgressBar(value: 0.5),
    context: FluentRenderContext(reduceMotion: true)
)
reducedProgressHost.frame = NSRect(x: 0, y: 0, width: 240, height: 32)
reducedProgressHost.layoutSubtreeIfNeeded()
guard let reducedProgress = firstProgressBar(in: reducedProgressHost),
      let reducedProgressDeterminate = firstLayer(named: "FluentKit.ProgressBar.Determinate", in: reducedProgressHost) else {
    fatalError("Reduce Motion ProgressBar validation hierarchy did not mount")
}
reducedProgress.value = 0.9
reducedProgress.isIndeterminate = true
require(
    reducedProgressDeterminate.animationKeys()?.isEmpty != false
        && firstLayer(named: "FluentKit.ProgressBar.Indeterminate.Primary", in: reducedProgressHost)?.animationKeys()?.isEmpty != false,
    "ProgressBar Reduce Motion reaches the final state without allocating animations"
)

let rtlProgressHost = FluentViewHost(
    FluentProgressBar(value: 0.25),
    context: FluentRenderContext(reduceMotion: true, layoutDirection: .rightToLeft)
)
rtlProgressHost.frame = NSRect(x: 0, y: 0, width: 240, height: 32)
rtlProgressHost.layoutSubtreeIfNeeded()
guard let rtlProgress = firstProgressBar(in: rtlProgressHost),
      let rtlDeterminate = firstLayer(named: "FluentKit.ProgressBar.Determinate", in: rtlProgressHost) else {
    fatalError("RTL ProgressBar validation hierarchy did not mount")
}
require(
    abs(rtlDeterminate.frame.maxX - rtlProgress.bounds.maxX) < 0.001,
    "RTL ProgressBar fills from the trailing edge"
)

let styledCheckBoxState = FluentState(wrappedValue: true)
let styledCheckBoxHost = FluentViewHost(
    FluentCheckBoxView("Styled check box", isChecked: styledCheckBoxState.projectedValue)
        .checkBoxStyle(ValidationCheckBoxStyle())
)
let nativeStyledCheckBox = firstCheckBox(in: styledCheckBoxHost)
require(nativeStyledCheckBox?.fluentStyle is ValidationCheckBoxStyle, "check box style mounts on the native control")
require((nativeStyledCheckBox?.intrinsicContentSize.height ?? 0) >= 26, "check box style metrics affect intrinsic height")
styledCheckBoxState.wrappedValue = false
drainMainQueue()
require(firstCheckBox(in: styledCheckBoxHost) === nativeStyledCheckBox, "styled check box updates preserve native identity")
require(nativeStyledCheckBox?.isChecked == false, "check box binding updates native state")
require(nativeStyledCheckBox?.accessibilityValue() as? String == "Off", "check box binding updates accessibility state")
nativeStyledCheckBox?.isChecked = true
require(styledCheckBoxState.wrappedValue, "check box interaction writes back to its binding")

let styledRadioState = FluentState(wrappedValue: false)
let styledRadioHost = FluentViewHost(
    FluentRadioButtonView("Styled radio", isSelected: styledRadioState.projectedValue)
        .radioButtonStyle(ValidationRadioButtonStyle())
)
let nativeStyledRadio = firstRadioButton(in: styledRadioHost)
require(nativeStyledRadio?.fluentStyle is ValidationRadioButtonStyle, "radio style mounts on the native control")
require((nativeStyledRadio?.intrinsicContentSize.height ?? 0) >= 26, "radio style metrics affect intrinsic height")
styledRadioState.wrappedValue = true
drainMainQueue()
require(firstRadioButton(in: styledRadioHost) === nativeStyledRadio, "styled radio updates preserve native identity")
require(nativeStyledRadio?.isSelected == true, "radio binding updates native state")
require(nativeStyledRadio?.accessibilityValue() as? String == "On", "radio binding updates accessibility state")
nativeStyledRadio?.isSelected = false
require(!styledRadioState.wrappedValue, "radio interaction writes back to its binding")

let interactiveCheckBoxState = FluentState(wrappedValue: false)
var interactiveCheckBoxCommits: [Bool] = []
let interactiveCheckBoxObserver = interactiveCheckBoxState.observe {
    interactiveCheckBoxCommits.append($0)
}
interactiveCheckBoxCommits.removeAll()
let interactiveCheckBoxHost = FluentViewHost(
    FluentCheckBoxView("Completed", isChecked: interactiveCheckBoxState.projectedValue),
    context: FluentRenderContext(reduceMotion: false)
)
let interactiveCheckBoxWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
interactiveCheckBoxWindow.contentView = interactiveCheckBoxHost
interactiveCheckBoxHost.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
interactiveCheckBoxWindow.orderFront(nil)
interactiveCheckBoxHost.layoutSubtreeIfNeeded()
guard let interactiveCheckBox = firstCheckBox(in: interactiveCheckBoxHost),
      let checkBoxBox = firstLayer(named: "FluentKit.CheckBox.Box", in: interactiveCheckBoxHost),
      let checkBoxGlyph = firstLayer(named: "FluentKit.CheckBox.Glyph", in: interactiveCheckBoxHost) as? CAShapeLayer,
      let checkBoxFocus = firstLayer(named: "FluentKit.CheckBox.FocusRing", in: interactiveCheckBoxHost) else {
    fatalError("CheckBox validation hierarchy did not mount")
}
require(
    checkBoxBox.bounds.size == CGSize(width: 20, height: 20)
        && checkBoxGlyph.strokeEnd == 0
        && checkBoxGlyph.opacity == 0,
    "mounted CheckBox starts with exact 20pt box and hidden stable glyph"
)
let checkBoxPoint = NSPoint(x: 10, y: interactiveCheckBox.bounds.midY)
interactiveCheckBox.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 40)
)
interactiveCheckBox.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 41)
)
require(
    !interactiveCheckBoxState.wrappedValue && interactiveCheckBoxCommits.isEmpty,
    "CheckBox mouseDown enters Pressed without committing its binding"
)
interactiveCheckBox.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 42)
)
drainMainQueue()
require(
    interactiveCheckBoxState.wrappedValue && interactiveCheckBoxCommits == [true],
    "CheckBox release-inside commits its binding exactly once"
)
require(
    checkBoxGlyph.strokeEnd == 1 && checkBoxGlyph.opacity == 1,
    "CheckBox selected state exposes the stable check glyph"
)
let checkBoxOnAnimation = checkBoxGlyph.animation(forKey: "fluent.checkbox.glyph.strokeEnd") as? CABasicAnimation
require(
    abs((checkBoxOnAnimation?.duration ?? 0) - 19.0 / 60.0) < 0.0001
        && checkBoxOnAnimation?.timingFunction != nil,
    "CheckBox reveal uses the source-derived 19-frame glyph motion"
)
interactiveCheckBox.layout()
require(
    checkBoxGlyph.animation(forKey: "fluent.checkbox.glyph.strokeEnd") != nil,
    "same-bounds CheckBox layout preserves active glyph motion"
)

interactiveCheckBox.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 43)
)
interactiveCheckBox.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 44)
)
let checkBoxOffAnimation = checkBoxGlyph.animation(forKey: "fluent.checkbox.glyph.strokeEnd") as? CABasicAnimation
drainMainQueue()
require(
    !interactiveCheckBoxState.wrappedValue
        && interactiveCheckBoxCommits == [true, false]
        && abs((checkBoxOffAnimation?.duration ?? 0) - 4.0 / 60.0) < 0.0001,
    "CheckBox clear uses the source-derived four-frame glyph motion"
)

let outsideChoicePoint = NSPoint(x: -20, y: interactiveCheckBox.bounds.midY)
interactiveCheckBox.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 45)
)
interactiveCheckBox.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: outsideChoicePoint, in: interactiveCheckBox, eventNumber: 46)
)
require(
    !interactiveCheckBoxState.wrappedValue && interactiveCheckBoxCommits == [true, false],
    "CheckBox release-outside cancels without committing"
)

interactiveCheckBox.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 47)
)
interactiveCheckBoxState.wrappedValue = true
drainMainQueue()
interactiveCheckBox.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: checkBoxPoint, in: interactiveCheckBox, eventNumber: 48)
)
require(
    interactiveCheckBoxState.wrappedValue,
    "external CheckBox binding updates cancel Pressed without a stale toggle"
)
interactiveCheckBoxWindow.makeFirstResponder(interactiveCheckBox)
require(checkBoxFocus.opacity == 0, "CheckBox hides focus visuals after pointer focus")
interactiveCheckBox.keyDown(with: sliderKeyEvent(49, in: interactiveCheckBox, eventNumber: 49))
require(!interactiveCheckBoxState.wrappedValue && checkBoxFocus.opacity == 1, "CheckBox Space commits through the keyboard path and reveals focus")
require(
    interactiveCheckBox.accessibilityPerformPress() && interactiveCheckBoxState.wrappedValue,
    "CheckBox accessibility press commits through the same path"
)
interactiveCheckBox.isEnabled = false
require(
    !interactiveCheckBox.accessibilityPerformPress() && interactiveCheckBoxState.wrappedValue,
    "disabled CheckBox rejects accessibility activation"
)
interactiveCheckBoxState.observableValue.removeObserver(interactiveCheckBoxObserver)
interactiveCheckBoxWindow.orderOut(nil)

let interactiveRadioState = FluentState(wrappedValue: false)
var interactiveRadioCommits: [Bool] = []
let interactiveRadioObserver = interactiveRadioState.observe { interactiveRadioCommits.append($0) }
interactiveRadioCommits.removeAll()
let interactiveRadioHost = FluentViewHost(
    FluentRadioButtonView("Primary", isSelected: interactiveRadioState.projectedValue),
    context: FluentRenderContext(reduceMotion: false)
)
let interactiveRadioWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
interactiveRadioWindow.contentView = interactiveRadioHost
interactiveRadioHost.frame = NSRect(x: 0, y: 0, width: 220, height: 40)
interactiveRadioWindow.orderFront(nil)
interactiveRadioHost.layoutSubtreeIfNeeded()
guard let interactiveRadio = firstRadioButton(in: interactiveRadioHost),
      let radioOuter = firstLayer(named: "FluentKit.RadioButton.Outer", in: interactiveRadioHost),
      let radioDot = firstLayer(named: "FluentKit.RadioButton.Dot", in: interactiveRadioHost),
      let radioPressedDot = firstLayer(named: "FluentKit.RadioButton.PressedDot", in: interactiveRadioHost),
      let radioFocus = firstLayer(named: "FluentKit.RadioButton.FocusRing", in: interactiveRadioHost) else {
    fatalError("RadioButton validation hierarchy did not mount")
}
require(
    radioOuter.bounds.size == CGSize(width: 20, height: 20)
        && radioDot.bounds.size == CGSize(width: 12, height: 12)
        && radioDot.opacity == 0
        && radioPressedDot.bounds.size == CGSize(width: 4, height: 4),
    "mounted RadioButton starts with exact outer, dot, and pressed-feedback geometry"
)
let radioPoint = NSPoint(x: 10, y: interactiveRadio.bounds.midY)
interactiveRadio.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: radioPoint, in: interactiveRadio, eventNumber: 50)
)
require(
    radioDot.bounds.size == CGSize(width: 14, height: 14),
    "RadioButton PointerOver applies the 14pt dot target"
)
interactiveRadio.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: radioPoint, in: interactiveRadio, eventNumber: 51)
)
require(
    !interactiveRadioState.wrappedValue
        && interactiveRadioCommits.isEmpty
        && radioDot.bounds.size == CGSize(width: 10, height: 10)
        && radioPressedDot.bounds.size == CGSize(width: 10, height: 10)
        && radioPressedDot.opacity == 1,
    "unselected RadioButton Pressed shows feedback without committing"
)
let radioPressedAnimation = radioPressedDot.animation(forKey: "fluent.radio.pressedDot.bounds") as? CABasicAnimation
require(
    abs((radioPressedAnimation?.duration ?? 0) - 0.167) < 0.0001
        && radioPressedAnimation?.timingFunction != nil,
    "RadioButton pressed feedback expands with the 167ms source motion"
)
interactiveRadio.layout()
require(
    radioPressedDot.animation(forKey: "fluent.radio.pressedDot.bounds") != nil,
    "same-bounds RadioButton layout preserves active pressed motion"
)
interactiveRadio.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: radioPoint, in: interactiveRadio, eventNumber: 52)
)
drainMainQueue()
require(
    interactiveRadioState.wrappedValue
        && interactiveRadioCommits == [true]
        && radioDot.opacity == 1
        && radioDot.bounds.size == CGSize(width: 14, height: 14),
    "RadioButton release-inside selects once and returns to PointerOver geometry"
)
let radioSelectedAnimation = radioDot.animation(forKey: "fluent.radio.dot.bounds") as? CABasicAnimation
require(
    abs((radioSelectedAnimation?.duration ?? 0) - 0.250) < 0.0001,
    "RadioButton selected PointerOver dot uses the 250ms state motion"
)

interactiveRadio.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: radioPoint, in: interactiveRadio, eventNumber: 53)
)
interactiveRadio.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: radioPoint, in: interactiveRadio, eventNumber: 54)
)
require(
    interactiveRadioState.wrappedValue && interactiveRadioCommits == [true],
    "selecting an already-selected RadioButton does not emit a duplicate commit"
)
interactiveRadioState.wrappedValue = false
drainMainQueue()
interactiveRadio.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: radioPoint, in: interactiveRadio, eventNumber: 55)
)
interactiveRadio.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: outsideChoicePoint, in: interactiveRadio, eventNumber: 56)
)
require(!interactiveRadioState.wrappedValue, "RadioButton release-outside cancels selection")
interactiveRadio.mouseDown(
    with: toggleMouseEvent(.leftMouseDown, at: radioPoint, in: interactiveRadio, eventNumber: 57)
)
interactiveRadioState.wrappedValue = true
drainMainQueue()
interactiveRadio.mouseUp(
    with: toggleMouseEvent(.leftMouseUp, at: radioPoint, in: interactiveRadio, eventNumber: 58)
)
require(
    interactiveRadioState.wrappedValue,
    "external RadioButton binding updates cancel Pressed without a stale selection"
)
interactiveRadioState.wrappedValue = false
drainMainQueue()
interactiveRadioWindow.makeFirstResponder(interactiveRadio)
require(radioFocus.opacity == 0, "RadioButton hides focus visuals after pointer focus")
interactiveRadio.keyDown(with: sliderKeyEvent(49, in: interactiveRadio, eventNumber: 59))
require(interactiveRadioState.wrappedValue && radioFocus.opacity == 1, "RadioButton Space selects through the keyboard path and reveals focus")
interactiveRadio.isEnabled = false
require(
    radioDot.bounds.size == CGSize(width: 14, height: 14)
        && !interactiveRadio.accessibilityPerformPress(),
    "disabled RadioButton uses 14pt dot geometry and rejects accessibility activation"
)
interactiveRadioState.observableValue.removeObserver(interactiveRadioObserver)
interactiveRadioWindow.orderOut(nil)

let rtlCheckBoxState = FluentState(wrappedValue: true)
let rtlCheckBoxHost = FluentViewHost(
    FluentCheckBoxView("RTL check", isChecked: rtlCheckBoxState.projectedValue),
    context: FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
)
rtlCheckBoxHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
rtlCheckBoxHost.layoutSubtreeIfNeeded()
guard let rtlCheckBox = firstCheckBox(in: rtlCheckBoxHost),
      let rtlCheckBoxBox = firstLayer(named: "FluentKit.CheckBox.Box", in: rtlCheckBoxHost) else {
    fatalError("RTL CheckBox validation hierarchy did not mount")
}
require(
    rtlCheckBoxBox.frame.midX > rtlCheckBox.bounds.midX,
    "CheckBox mirrors its glyph and label placement in RTL"
)

let rtlRadioState = FluentState(wrappedValue: true)
let rtlRadioHost = FluentViewHost(
    FluentRadioButtonView("RTL radio", isSelected: rtlRadioState.projectedValue),
    context: FluentRenderContext(reduceMotion: false, layoutDirection: .rightToLeft)
)
rtlRadioHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
rtlRadioHost.layoutSubtreeIfNeeded()
guard let rtlRadio = firstRadioButton(in: rtlRadioHost),
      let rtlRadioOuter = firstLayer(named: "FluentKit.RadioButton.Outer", in: rtlRadioHost) else {
    fatalError("RTL RadioButton validation hierarchy did not mount")
}
require(
    rtlRadioOuter.frame.midX > rtlRadio.bounds.midX,
    "RadioButton mirrors its glyph and label placement in RTL"
)

let reducedCheckBoxState = FluentState(wrappedValue: false)
let reducedCheckBoxHost = FluentViewHost(
    FluentCheckBoxView("Reduced check", isChecked: reducedCheckBoxState.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
reducedCheckBoxHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
reducedCheckBoxHost.layoutSubtreeIfNeeded()
let reducedCheckBoxGlyph = firstLayer(named: "FluentKit.CheckBox.Glyph", in: reducedCheckBoxHost)
reducedCheckBoxState.wrappedValue = true
drainMainQueue()
require(
    reducedCheckBoxGlyph?.animationKeys()?.isEmpty != false,
    "CheckBox Reduce Motion reaches selected geometry without allocating animations"
)

let reducedRadioState = FluentState(wrappedValue: true)
let reducedRadioHost = FluentViewHost(
    FluentRadioButtonView("Reduced radio", isSelected: reducedRadioState.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
reducedRadioHost.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
reducedRadioHost.layoutSubtreeIfNeeded()
guard let reducedRadio = firstRadioButton(in: reducedRadioHost),
      let reducedRadioDot = firstLayer(named: "FluentKit.RadioButton.Dot", in: reducedRadioHost) else {
    fatalError("Reduce Motion RadioButton validation hierarchy did not mount")
}
reducedRadio.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: 10, y: reducedRadio.bounds.midY),
        in: reducedRadio,
        eventNumber: 60
    )
)
require(
    reducedRadioDot.bounds.size == CGSize(width: 14, height: 14)
        && reducedRadioDot.animationKeys()?.isEmpty != false,
    "RadioButton Reduce Motion reaches PointerOver geometry without allocating animations"
)

let styledSegmentState = FluentState(wrappedValue: 0)
let styledSegmentHost = FluentViewHost(
    FluentSegmentedControl(["First", "Second"], selection: styledSegmentState.projectedValue)
        .segmentedStyle(ValidationSegmentedStyle())
)
let segmentedMotionWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 240, height: 32),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
segmentedMotionWindow.contentView = styledSegmentHost
segmentedMotionWindow.orderFront(nil)
styledSegmentHost.layoutSubtreeIfNeeded()
let nativeStyledSegmented = firstSegmentedControl(in: styledSegmentHost)
require(nativeStyledSegmented?.font?.pointSize == 15, "segmented style applies semantic font metrics")
nativeStyledSegmented?.layoutSubtreeIfNeeded()
let segmentedSelectionIndicators = nativeStyledSegmented?.subviews.filter {
    $0.identifier?.rawValue == "FluentKit.Segmented.SelectionIndicator"
} ?? []
let segmentedSelectionIndicator = segmentedSelectionIndicators.first
let segmentedLabels = nativeStyledSegmented?.subviews.compactMap { view -> NSTextField? in
    guard view.identifier?.rawValue.hasPrefix("FluentKit.Segmented.Label.") == true else { return nil }
    return view as? NSTextField
}.sorted { ($0.identifier?.rawValue ?? "") < ($1.identifier?.rawValue ?? "") } ?? []
let expectedSegmentIndicatorWidth = (nativeStyledSegmented?.bounds.width ?? 0) / 2 - 4
require(
    segmentedSelectionIndicators.count == 1
        && abs((segmentedSelectionIndicator?.frame.width ?? 0) - expectedSegmentIndicatorWidth) < 0.001,
    "segmented control keeps one shared inset selection indicator"
)
guard let segmentedOuterBorder = firstLayer(named: "FluentKit.Segmented.OuterBorder", in: nativeStyledSegmented ?? styledSegmentHost) as? CAShapeLayer,
      let segmentedOuterBorderPath = segmentedOuterBorder.path else {
    fatalError("segmented outer border overlay did not mount")
}
let segmentedBorderOverlay = nativeStyledSegmented?.subviews.first {
    $0.identifier?.rawValue == "FluentKit.Segmented.BorderOverlay"
}
let segmentedSubviewOrder = nativeStyledSegmented?.subviews ?? []
let segmentedIndicatorIndex = segmentedSelectionIndicator.flatMap { segmentedSubviewOrder.firstIndex(of: $0) }
let segmentedOverlayIndex = segmentedBorderOverlay.flatMap { segmentedSubviewOrder.firstIndex(of: $0) }
require(
    segmentedOuterBorder.fillRule == .evenOdd
        && segmentedOuterBorder.superlayer === segmentedBorderOverlay?.layer
        && (segmentedOverlayIndex ?? -1) > (segmentedIndicatorIndex ?? Int.max)
        && segmentedOuterBorder.fillColor != NSColor.clear.cgColor
        && segmentedOuterBorder.strokeColor == nil
        && segmentedOuterBorder.lineWidth == 0
        && abs(segmentedOuterBorderPath.boundingBox.minX - (nativeStyledSegmented?.bounds.minX ?? 0)) < 0.001
        && abs(segmentedOuterBorderPath.boundingBox.minY - (nativeStyledSegmented?.bounds.minY ?? 0)) < 0.001
        && abs(segmentedOuterBorderPath.boundingBox.maxX - (nativeStyledSegmented?.bounds.maxX ?? 0)) < 0.001
        && abs(segmentedOuterBorderPath.boundingBox.maxY - (nativeStyledSegmented?.bounds.maxY ?? 0)) < 0.001,
    "segmented selection cannot cover or clip the topmost inside fill-ring border"
)
require(
    segmentedLabels.count == 2
        && segmentedLabels[0].stringValue == "First"
        && segmentedLabels[1].stringValue == "Second",
    "segmented control has one Fluent-owned text presenter per native segment"
)
let originalSegmentedLabelIdentities = segmentedLabels.map(ObjectIdentifier.init)
styledSegmentState.wrappedValue = 1
drainMainQueue()
require(firstSegmentedControl(in: styledSegmentHost) === nativeStyledSegmented, "styled segmented updates preserve native identity")
require(nativeStyledSegmented?.selectedSegment == 1, "segmented binding updates native selection")
require(nativeStyledSegmented?.accessibilityValue() as? Int == 1, "segmented selection updates accessibility value")
let updatedSegmentedLabelIdentities = nativeStyledSegmented?.subviews.compactMap { view -> NSTextField? in
    guard view.identifier?.rawValue.hasPrefix("FluentKit.Segmented.Label.") == true else { return nil }
    return view as? NSTextField
}.sorted { ($0.identifier?.rawValue ?? "") < ($1.identifier?.rawValue ?? "") }.map(ObjectIdentifier.init) ?? []
require(
    updatedSegmentedLabelIdentities == originalSegmentedLabelIdentities,
    "segmented reconciliation preserves compatible Fluent label identities"
)
let segmentedSelectionAnimation = segmentedSelectionIndicator?.layer?
    .animation(forKey: "fluent.segmented.selection") as? CAAnimationGroup
require(
    abs((segmentedSelectionAnimation?.duration ?? 0) - FluentMotion.controlFast.duration) < 0.000_001,
    "segmented selection uses the source-derived 167ms control-fast duration"
)
require(
    segmentedSelectionAnimation?.animations?.compactMap { ($0 as? CAPropertyAnimation)?.keyPath } == ["position", "bounds"],
    "segmented selection keeps presentation position and bounds synchronized without scale or opacity choreography"
)
nativeStyledSegmented?.layout()
require(
    segmentedSelectionIndicator?.layer?.animation(forKey: "fluent.segmented.selection") != nil,
    "same-bounds segmented layout preserves the active presentation animation"
)
if let nativeStyledSegmented {
    nativeStyledSegmented.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 16), in: nativeStyledSegmented, eventNumber: 70))
    nativeStyledSegmented.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: NSPoint(x: 20, y: 16), in: nativeStyledSegmented, eventNumber: 71))
}
require(styledSegmentState.wrappedValue == 0, "segmented interaction writes back to its binding")

styledSegmentState.wrappedValue = 1
drainMainQueue()
if let nativeStyledSegmented {
    nativeStyledSegmented.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 16), in: nativeStyledSegmented, eventNumber: 72))
    nativeStyledSegmented.mouseDragged(with: toggleMouseEvent(.leftMouseDragged, at: NSPoint(x: -20, y: 16), in: nativeStyledSegmented, eventNumber: 73))
    nativeStyledSegmented.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: NSPoint(x: -20, y: 16), in: nativeStyledSegmented, eventNumber: 74))
}
require(styledSegmentState.wrappedValue == 1, "segmented release outside cancels the pending selection")
segmentedMotionWindow.orderOut(nil)

let rtlSegmentState = FluentState(wrappedValue: 1)
let rtlSegmentHost = FluentViewHost(
    FluentSegmentedControl(["First", "Second", "Third"], selection: rtlSegmentState.projectedValue),
    context: FluentRenderContext(layoutDirection: .rightToLeft)
)
let rtlSegmentWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 270, height: 32),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
rtlSegmentWindow.contentView = rtlSegmentHost
rtlSegmentWindow.orderFront(nil)
rtlSegmentHost.layoutSubtreeIfNeeded()
guard let rtlSegmented = firstSegmentedControl(in: rtlSegmentHost) else {
    fatalError("RTL segmented validation hierarchy did not mount")
}
rtlSegmented.layoutSubtreeIfNeeded()
let rtlFirstLabel = rtlSegmented.subviews.first {
    $0.identifier?.rawValue == "FluentKit.Segmented.Label.0"
}
let rtlThirdLabel = rtlSegmented.subviews.first {
    $0.identifier?.rawValue == "FluentKit.Segmented.Label.2"
}
require(
    (rtlFirstLabel?.frame.minX ?? 0) > (rtlThirdLabel?.frame.minX ?? 0),
    "segmented RTL layout mirrors logical label order"
)
rtlSegmented.mouseDown(with: toggleMouseEvent(.leftMouseDown, at: NSPoint(x: 250, y: 16), in: rtlSegmented, eventNumber: 75))
rtlSegmented.mouseUp(with: toggleMouseEvent(.leftMouseUp, at: NSPoint(x: 250, y: 16), in: rtlSegmented, eventNumber: 76))
require(rtlSegmentState.wrappedValue == 0, "segmented RTL hit testing maps the right edge to the first logical item")
rtlSegmented.keyDown(with: sliderKeyEvent(123, in: rtlSegmented, eventNumber: 77))
require(rtlSegmentState.wrappedValue == 1, "segmented RTL left arrow advances in visual order")
rtlSegmentWindow.orderOut(nil)

let reducedSegmentState = FluentState(wrappedValue: 0)
let reducedSegmentHost = FluentViewHost(
    FluentSegmentedControl(["First", "Second"], selection: reducedSegmentState.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
reducedSegmentHost.frame = NSRect(x: 0, y: 0, width: 240, height: 32)
reducedSegmentHost.layoutSubtreeIfNeeded()
let reducedSegmentIndicator = reducedSegmentHost.subviews.lazy.compactMap { control -> NSView? in
    (control as? NSSegmentedControl)?.subviews.first {
        $0.identifier?.rawValue == "FluentKit.Segmented.SelectionIndicator"
    }
}.first
reducedSegmentState.wrappedValue = 1
drainMainQueue()
require(
    reducedSegmentIndicator?.layer?.animation(forKey: "fluent.segmented.selection") == nil,
    "segmented Reduce Motion reaches selected geometry without allocating animations"
)

let selectorItems = [
    FluentSelectorBarItem(value: 0, title: "Grid", systemImage: "square.grid.2x2"),
    FluentSelectorBarItem(value: 1, title: "Disabled", isEnabled: false),
    FluentSelectorBarItem(value: 2, title: "List", systemImage: "list.bullet")
]
let selectorState = FluentState(wrappedValue: 0)
let selectorHost = FluentViewHost(
    FluentSelectorBar(selectorItems, selection: selectorState.projectedValue)
)
let selectorWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
selectorWindow.contentView = selectorHost
selectorWindow.orderFront(nil)
selectorHost.layoutSubtreeIfNeeded()
guard let selectorBar = firstView(identifier: "FluentKit.SelectorBar", in: selectorHost) else {
    fatalError("SelectorBar validation hierarchy did not mount")
}
let selectorItemViews = views(identifier: "FluentKit.SelectorBar.Item", in: selectorBar)
require(firstSegmentedControl(in: selectorHost) == nil, "SelectorBar uses a dedicated AppKit host instead of NSSegmentedControl")
require(selectorBar.accessibilityRole() == .radioGroup, "SelectorBar exposes radio-group accessibility semantics")
require(
    selectorItemViews.count == 3
        && selectorItemViews.allSatisfy { $0.accessibilityRole() == .radioButton },
    "SelectorBar exposes one radio-button accessibility child per item"
)
let selectorPills = layers(named: "FluentKit.SelectorBar.ItemPill", in: selectorBar)
require(selectorPills.count == 3, "SelectorBar gives every item an independent selection pill")
require(
    selectorPills.allSatisfy { $0.bounds.size == CGSize(width: 4, height: 3) },
    "SelectorBar item pills preserve the source 4 by 3 base geometry"
)
require(
    abs(selectorPills[0].transform.m11 - 4) < 0.001
        && selectorPills[0].opacity == 1
        && selectorPills.dropFirst().allSatisfy { $0.opacity == 0 },
    "SelectorBar selection expands only the selected item's own pill"
)
let originalSelectorIdentities = Dictionary(
    uniqueKeysWithValues: selectorItemViews.compactMap { view in
        view.accessibilityTitle().map { ($0, ObjectIdentifier(view)) }
    }
)
selectorState.wrappedValue = 2
drainMainQueue()
guard let selectedListItem = firstView(withAccessibilityTitle: "List", in: selectorBar),
      let selectedListPill = firstLayer(named: "FluentKit.SelectorBar.ItemPill", in: selectedListItem) else {
    fatalError("SelectorBar selected item did not expose its pill")
}
let selectorPillScaleAnimation = selectedListPill.animation(forKey: "fluent.selectorbar.pill.scale") as? CABasicAnimation
let selectorPillOpacityAnimation = selectedListPill.animation(forKey: "fluent.selectorbar.pill.opacity") as? CABasicAnimation
require(
    abs((selectorPillScaleAnimation?.duration ?? 0) - FluentMotion.controlFast.duration) < 0.000_001
        && abs((selectorPillOpacityAnimation?.duration ?? 0) - FluentMotion.controlFast.duration) < 0.000_001,
    "SelectorBar pill scale and opacity use the source-derived 167ms duration"
)
require(selectorState.wrappedValue == 2, "SelectorBar observes external binding changes")
selectorHost.update(
    FluentSelectorBar([selectorItems[2], selectorItems[0], selectorItems[1]], selection: selectorState.projectedValue)
)
selectorHost.layoutSubtreeIfNeeded()
let reorderedSelectorItems = views(identifier: "FluentKit.SelectorBar.Item", in: selectorHost)
require(
    reorderedSelectorItems.allSatisfy { view in
        guard let title = view.accessibilityTitle(), let identity = originalSelectorIdentities[title] else { return false }
        return ObjectIdentifier(view) == identity
    },
    "SelectorBar reordering preserves compatible item identities"
)
guard let reorderedListItem = firstView(withAccessibilityTitle: "List", in: selectorHost) else {
    fatalError("SelectorBar reordered item did not mount")
}
reorderedListItem.keyDown(with: sliderKeyEvent(124, in: reorderedListItem, eventNumber: 78))
require(selectorState.wrappedValue == 0, "SelectorBar arrows change selection and skip disabled items")
selectorWindow.orderOut(nil)

let rtlSelectorState = FluentState(wrappedValue: 1)
let rtlSelectorHost = FluentViewHost(
    FluentSelectorBar([
        FluentSelectorBarItem(value: 0, title: "First"),
        FluentSelectorBarItem(value: 1, title: "Second"),
        FluentSelectorBarItem(value: 2, title: "Third")
    ], selection: rtlSelectorState.projectedValue),
    context: FluentRenderContext(layoutDirection: .rightToLeft)
)
rtlSelectorHost.frame = NSRect(x: 0, y: 0, width: 260, height: 64)
rtlSelectorHost.layoutSubtreeIfNeeded()
guard let rtlFirstSelectorItem = firstView(withAccessibilityTitle: "First", in: rtlSelectorHost),
      let rtlSecondSelectorItem = firstView(withAccessibilityTitle: "Second", in: rtlSelectorHost),
      let rtlThirdSelectorItem = firstView(withAccessibilityTitle: "Third", in: rtlSelectorHost) else {
    fatalError("RTL SelectorBar validation hierarchy did not mount")
}
require(rtlFirstSelectorItem.frame.minX > rtlThirdSelectorItem.frame.minX, "SelectorBar mirrors item order in RTL")
rtlSecondSelectorItem.keyDown(with: sliderKeyEvent(123, in: rtlSecondSelectorItem, eventNumber: 79))
require(rtlSelectorState.wrappedValue == 2, "SelectorBar RTL left arrow advances in visual order")

let optionalSelectorState = FluentState<Int?>(wrappedValue: nil)
let optionalSelectorHost = FluentViewHost(
    FluentSelectorBar([
        FluentSelectorBarItem(value: 0, title: "Grid"),
        FluentSelectorBarItem(value: 1, title: "List")
    ], selection: optionalSelectorState.projectedValue)
)
optionalSelectorHost.frame = NSRect(x: 0, y: 0, width: 180, height: 64)
optionalSelectorHost.layoutSubtreeIfNeeded()
require(
    layers(named: "FluentKit.SelectorBar.ItemPill", in: optionalSelectorHost).allSatisfy { $0.opacity == 0 },
    "SelectorBar optional binding preserves a valid empty selection"
)

let reducedSelectorState = FluentState(wrappedValue: 0)
let reducedSelectorHost = FluentViewHost(
    FluentSelectorBar([
        FluentSelectorBarItem(value: 0, title: "Grid"),
        FluentSelectorBarItem(value: 1, title: "List")
    ], selection: reducedSelectorState.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
reducedSelectorHost.frame = NSRect(x: 0, y: 0, width: 180, height: 64)
reducedSelectorHost.layoutSubtreeIfNeeded()
reducedSelectorState.wrappedValue = 1
drainMainQueue()
guard let reducedListItem = firstView(withAccessibilityTitle: "List", in: reducedSelectorHost),
      let reducedSelectorPill = firstLayer(named: "FluentKit.SelectorBar.ItemPill", in: reducedListItem) else {
    fatalError("Reduce Motion SelectorBar validation hierarchy did not mount")
}
require(
    reducedSelectorPill.transform.m11 == 4
        && reducedSelectorPill.opacity == 1
        && reducedSelectorPill.animationKeys()?.isEmpty != false,
    "SelectorBar Reduce Motion reaches selected geometry without allocating animations"
)

let themeStore = FluentThemeStore(FluentTheme.custom(colorScheme: .light, typography: FluentTypography(scale: 1)))
struct ThemeStoreProbe: FluentView {
    let store: FluentThemeStore

    var body: FluentThemeStoreView<FluentTextView> {
        FluentText("Semantic title", style: .title).fluentTheme(store)
    }
}
let themeStoreHost = FluentViewHost(ThemeStoreProbe(store: themeStore))
let nativeThemeLabel = firstLabel(in: themeStoreHost)
require(nativeThemeLabel?.font?.pointSize == 22, "semantic text style resolves through the theme typography")
themeStore.theme = themeStore.theme
    .with(colorScheme: .dark)
    .with(typography: FluentTypography(scale: 1.5))
drainMainQueue()
require(firstLabel(in: themeStoreHost) === nativeThemeLabel, "theme store updates preserve native label identity")
require((nativeThemeLabel?.font?.pointSize ?? 0) > 30, "theme store typography updates semantic text in place")
let semanticTextRed = nativeThemeLabel?.textColor?.usingColorSpace(.deviceRGB)?.redComponent ?? 0
require(semanticTextRed > 0.8, "theme store color scheme updates semantic text color")

let text = FluentText("identity").fluentID("stable")
_ = text
require(true, "stable identity modifier is available")

let modifier = FluentText("modifier").padding(8).opacity(0.75).disabled(false)
let modifierView = modifier._mount(in: FluentRenderContext())
require(modifierView.subviews.first?.alphaValue == 0.75, "opacity modifier applies alpha")

let accessible = FluentText("Accessible").accessibilityLabel("Accessible label").accessibilityRole(.group)
require(accessible._mount(in: FluentRenderContext()).accessibilityLabel() == "Accessible label", "accessibility label applies")

let hiddenAccessible = FluentText("Decorative")
    .accessibilityHidden()
    .accessibilityLabel("Decorative label")
let hiddenAccessibleView = hiddenAccessible._mount(in: FluentRenderContext())
require(hiddenAccessibleView.isAccessibilityElement() == false, "accessibility modifiers preserve hidden state when composed")

let accessibilityValueView = FluentNativeView(NSView())
    .accessibilityRole(.group)
    .accessibilityValue("Decorative value")
    ._mount(in: FluentRenderContext())
require(accessibilityValueView.accessibilityValue() as? String == "Decorative value", "accessibility value applies to semantic containers")

let rows = FluentForEach([1, 2, 3], id: { $0 }) { value in
    FluentText("row \(value)")
}
let forEachHost = rows._mount(in: FluentRenderContext())
require(forEachHost.subviews.count == 1, "for-each mounts a reusable host")
let forEachStack = forEachHost.subviews.first as? NSStackView
require(forEachStack?.arrangedSubviews.count == 3, "for-each mounts one native row per element")
require(forEachHost.accessibilityChildren()?.count == 3, "for-each exposes rows as accessibility children")
let originalRowViews = forEachStack?.arrangedSubviews ?? []
let reorderedForEach = FluentForEach([3, 1, 4], id: { $0 }) { value in
    FluentText("row \(value)")
}
require(reorderedForEach._update(forEachHost, in: FluentRenderContext()), "for-each updates a compatible collection in place")
let reorderedStack = forEachHost.subviews.first as? NSStackView
require(reorderedStack?.arrangedSubviews.count == 3, "for-each preserves row count after mutation")
require(reorderedStack?.arrangedSubviews[0] === originalRowViews[2], "for-each reuses the row that moved to the first position")
require(reorderedStack?.arrangedSubviews[1] === originalRowViews[0], "for-each preserves identity for a moved row")
require(reorderedStack?.arrangedSubviews[2] !== originalRowViews[1], "for-each removes deleted identity and mounts inserted identity")
require(forEachHost.accessibilityChildren()?.count == 3, "for-each refreshes accessibility children after mutation")
let preDuplicateViews = reorderedStack?.arrangedSubviews ?? []
let duplicateForEach = FluentForEach([3, 3, 4], id: { $0 }) { value in
    FluentText("duplicate \(value)")
}
require(duplicateForEach._update(forEachHost, in: FluentRenderContext()), "for-each accepts duplicate IDs with a deterministic rebuild fallback")
let duplicateStack = forEachHost.subviews.first as? NSStackView
require(duplicateStack?.arrangedSubviews.count == 3, "for-each rebuild fallback preserves duplicate row count")
require(duplicateStack?.arrangedSubviews[0] !== preDuplicateViews[0], "duplicate IDs do not reuse an ambiguous native row")

let largeSiblingGroup = FluentVStack(spacing: 1) {
    FluentText("1"); FluentText("2"); FluentText("3"); FluentText("4")
    FluentText("5"); FluentText("6"); FluentText("7"); FluentText("8")
    FluentText("9"); FluentText("10"); FluentText("11"); FluentText("12")
    FluentText("13"); FluentText("14")
}
let largeSiblingView = largeSiblingGroup._mount(in: FluentRenderContext())
require((largeSiblingView as? NSStackView)?.arrangedSubviews.count == 14, "view builder supports more than twelve sibling views")

let scrollView = FluentScrollView(.vertical) {
    FluentVStack(spacing: 4) {
        FluentText("Scrollable heading")
        FluentText("Initial value")
    }
}
let mountedScrollView = scrollView._mount(in: FluentRenderContext())
guard let nativeScrollView = mountedScrollView as? NSScrollView,
      let originalScrollDocument = nativeScrollView.documentView else {
    require(false, "scroll view mounts an NSScrollView with a document view")
    fatalError()
}
require(nativeScrollView.hasVerticalScroller, "vertical scroll view enables its vertical scroller")
require(!nativeScrollView.hasHorizontalScroller, "vertical scroll view disables its horizontal scroller")
let updatedScrollView = FluentScrollView(.vertical) {
    FluentVStack(spacing: 4) {
        FluentText("Scrollable heading")
        FluentText("Updated value")
    }
}
require(updatedScrollView._update(nativeScrollView, in: FluentRenderContext()), "scroll view updates compatible document content in place")
require(nativeScrollView.documentView === originalScrollDocument, "scroll view preserves native document identity during compatible updates")
require(firstLabel(in: originalScrollDocument)?.stringValue == "Scrollable heading", "scroll document remains mounted after its content updates")

let reactiveValue = FluentObservable(1)
struct ReactiveLabel: FluentView {
    let value: FluentObservable<Int>
    var body: FluentTextView { FluentText("Value: \(value.value)") }
}
let reactiveHost = FluentViewHost(ReactiveLabel(value: reactiveValue))
require(firstLabel(in: reactiveHost)?.stringValue == "Value: 1", "host mounts observable content")
reactiveValue.value = 2
reactiveValue.value = 3
drainMainQueue()
require(firstLabel(in: reactiveHost)?.stringValue == "Value: 3", "host automatically refreshes observed dependencies")

struct ErasedRoot: FluentView {
    var body: FluentAnyView { FluentAnyView(FluentText("Erased root")) }
}
let erasedRootHost = FluentViewHost(ErasedRoot())
require(firstLabel(in: erasedRootHost)?.stringValue == "Erased root", "type-erased root view mounts without recursion")

let editorText = FluentState(wrappedValue: "Initial notes")
let textEditor = FluentTextEditor(editorText.projectedValue, placeholder: "Notes", minimumHeight: 96)
let textEditorView = textEditor._mount(in: FluentRenderContext())
require(textEditorView === textEditor, "text editor mounts as its native AppKit host")
require(textEditor.textView.string == "Initial notes", "text editor reads its initial binding value")
require(textEditor.textView.accessibilityRole() == NSAccessibility.Role.textArea, "text editor exposes native multiline accessibility semantics")
require(textEditor.intrinsicContentSize.height == 96, "text editor honors its declarative minimum height")
require(
    textEditor.textView.isVerticallyResizable
        && !textEditor.textView.isHorizontallyResizable
        && textEditor.textView.textContainer?.widthTracksTextView == true
        && textEditor.textView.textContainer?.maximumNumberOfLines == 0,
    "TextEditor remains a wrapping multiline editor outside the shared single-line protocol"
)
textEditor.textView.string = "Edited notes"
textEditor.commitText()
require(editorText.wrappedValue == "Edited notes", "text editor writes native edits through its binding")
editorText.wrappedValue = "External notes"
drainMainQueue()
require(textEditor.textView.string == "External notes", "text editor reflects external binding updates")

let richText = FluentState(wrappedValue: NSAttributedString(string: "Hello Fluent Hello"))
let richSelection = FluentState(wrappedValue: FluentTextSelection(location: 0, length: 5))
let richEditor = FluentRichTextEditor(
    richText.projectedValue,
    selection: richSelection.projectedValue,
    placeholder: "Compose",
    minimumHeight: 110
)
let richView = richEditor._mount(in: FluentRenderContext())
require(richView === richEditor, "rich editor mounts as its native AppKit host")
require(richEditor.textView.string == "Hello Fluent Hello", "rich editor reads attributed text binding")
require(richEditor.textView.accessibilityRole() == NSAccessibility.Role.textArea, "rich editor exposes multiline accessibility semantics")
require(richEditor.intrinsicContentSize.height == 110, "rich editor honors minimum height")
require(richEditor.find("hello").map { $0.location } == [0, 13], "rich editor finds case-insensitive matches")
var repeatedSelectionValue = FluentTextSelection(location: 0, length: 0)
var repeatedSelectionWrites = 0
let repeatedSelectionBinding = FluentBinding<FluentTextSelection>(
    get: { repeatedSelectionValue },
    set: {
        repeatedSelectionValue = $0
        repeatedSelectionWrites += 1
    }
)
let repeatedSelectionEditor = FluentRichTextEditor(
    FluentBinding(get: { NSAttributedString(string: "Selection stress") }, set: { _ in }),
    selection: repeatedSelectionBinding,
    minimumHeight: 80
)
_ = repeatedSelectionEditor._mount(in: FluentRenderContext())
let repeatedInitialRange = repeatedSelectionEditor.textView.selectedRange()
repeatedSelectionValue = FluentTextSelection(
    location: repeatedInitialRange.location,
    length: repeatedInitialRange.length
)
repeatedSelectionWrites = 0
for _ in 0..<1_000 {
    repeatedSelectionEditor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
}
require(
    repeatedSelectionWrites == 0,
    "rich editor ignores repeated selection callbacks for an unchanged range"
)
repeatedSelectionEditor.textView.setSelectedRange(NSRange(location: 0, length: 4))
repeatedSelectionEditor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
for _ in 0..<1_000 {
    repeatedSelectionEditor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
}
require(
    repeatedSelectionWrites == 0,
    "rich editor defers a new selection update until the current RunLoop turn settles"
)
drainMainQueue()
require(
    repeatedSelectionWrites == 1,
    "rich editor publishes one binding update for a new range and suppresses duplicate callbacks"
)
var coalescedSelectionValue = FluentTextSelection(location: 0, length: 0)
var coalescedSelectionWrites = 0
let coalescedSelectionEditor = FluentRichTextEditor(
    FluentBinding(get: { NSAttributedString(string: String(repeating: "Drag ", count: 80)) }, set: { _ in }),
    selection: FluentBinding(
        get: { coalescedSelectionValue },
        set: {
            coalescedSelectionValue = $0
            coalescedSelectionWrites += 1
        }
    ),
    minimumHeight: 80
)
_ = coalescedSelectionEditor._mount(in: FluentRenderContext())
for index in 1...250 {
    coalescedSelectionEditor.textView.setSelectedRange(NSRange(location: 0, length: index))
    coalescedSelectionEditor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
}
require(coalescedSelectionWrites == 0, "rich editor does not synchronously publish every drag-selection callback")
drainMainQueue()
require(
    coalescedSelectionWrites == 1
        && coalescedSelectionValue == FluentTextSelection(location: 0, length: 250),
    "rich editor coalesces a drag-selection burst to its final range"
)
let observedSelectionState = FluentState(wrappedValue: FluentTextSelection(location: 0, length: 0))
let observedSelectionEditor = FluentRichTextEditor(
    FluentBinding(get: { NSAttributedString(string: String(repeating: "Selection ", count: 40)) }, set: { _ in }),
    selection: observedSelectionState.projectedValue,
    minimumHeight: 80
)
_ = observedSelectionEditor._mount(in: FluentRenderContext())
for index in 1...250 {
    observedSelectionEditor.textView.setSelectedRange(NSRange(location: 0, length: index))
    observedSelectionEditor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
}
observedSelectionEditor.textView.delegate = nil
observedSelectionEditor.textView.setSelectedRange(NSRange(location: 0, length: 0))
observedSelectionEditor.textView.delegate = observedSelectionEditor
drainMainQueue()
require(
    observedSelectionEditor.textView.selectedRange() == NSRange(location: 0, length: 0),
    "rich editor does not queue and replay locally published drag-selection ranges"
)
richEditor.textView.setSelectedRange(NSRange(location: 0, length: 5))
richEditor.toggleBold()
let boldFont = richEditor.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
require(boldFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "rich editor applies bold to the selected range")
richEditor.setFontSize(18)
let resizedFont = richEditor.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
require(resizedFont?.pointSize == 18, "rich editor applies a font size to the selection")
richEditor.textView.setSelectedRange(NSRange(location: 0, length: 5))
richEditor.replaceSelection(with: NSAttributedString(string: "Hi"))
require(richText.wrappedValue.string == "Hi Fluent Hello", "rich editor writes replacement text through its binding")
require(richSelection.wrappedValue == FluentTextSelection(location: 2, length: 0), "rich editor keeps selection binding synchronized")
require(richEditor.replaceAll("hello", with: "World") == 1, "rich editor replaces all remaining matches")
require(richText.wrappedValue.string == "Hi Fluent World", "rich editor commits replace-all output")
richText.wrappedValue = NSAttributedString(string: "External rich text")
drainMainQueue()
require(richEditor.textView.string == "External rich text", "rich editor reflects external attributed binding updates")
richSelection.wrappedValue = FluentTextSelection(location: 9, length: 4)
drainMainQueue()
require(richEditor.textView.selectedRange() == NSRange(location: 9, length: 4), "rich editor reflects external selection binding updates")
richEditor.textView.setSelectedRange(NSRange(location: 0, length: 8))
richEditor.perform(.toggleBold)
require(richEditor.formattingState.bold == .on, "rich text formatting state reports an enabled trait")
richEditor.perform(.toggleBold)
require(richEditor.formattingState.bold == .off, "rich text formatting command toggles an enabled trait off")
richEditor.textView.setSelectedRange(NSRange(location: 0, length: 4))
richEditor.perform(.toggleItalic)
richEditor.textView.setSelectedRange(NSRange(location: 0, length: 8))
require(richEditor.formattingState.italic == .mixed, "rich text formatting state reports mixed selections")
richEditor.perform(.alignment(.center))
require(richEditor.formattingState.alignment == .center, "rich text formatting command applies paragraph alignment")
richEditor.perform(.clearFormatting)
require(richEditor.formattingState.italic == .off, "clear-formatting command removes font traits")
let attachment = FluentTextAttachment(
    id: "validation-attachment",
    data: Data([0x46, 0x4b]),
    typeIdentifier: "public.data",
    filename: "sample.bin",
    accessibilityLabel: "Validation attachment"
)
richEditor.textView.setSelectedRange(NSRange(location: richEditor.textView.string.utf16.count, length: 0))
richEditor.insertAttachment(attachment)
let attachmentOccurrences = richEditor.attachments()
require(attachmentOccurrences.count == 1, "rich editor enumerates inserted text attachments")
require(attachmentOccurrences.first?.attachment.id == attachment.id, "text attachment preserves its stable ID")
require(attachmentOccurrences.first?.attachment.data == attachment.data, "text attachment preserves its payload")
require(attachmentOccurrences.first?.attachment.accessibilityLabel == "Validation attachment", "text attachment preserves its accessibility label")
require(richText.wrappedValue.attribute(.attachment, at: richText.wrappedValue.length - 1, effectiveRange: nil) is NSTextAttachment, "attachment insertion commits attributed content to the binding")
require(richEditor.removeAttachment(id: attachment.id), "rich editor removes a text attachment by stable ID")
require(richEditor.attachments().isEmpty, "text attachment removal updates native storage")
require(!richEditor.removeAttachment(id: attachment.id), "removing an absent text attachment reports no mutation")

let secureText = FluentState(wrappedValue: "initial-secret")
let secureView = FluentSecureField(secureText.projectedValue, placeholder: "Password")
    .textFieldStyle(ValidationTextFieldStyle())
    ._mount(in: FluentRenderContext())
let secureField = firstSecureTextField(in: secureView)
var secureTitleRect: NSRect?
require(secureField?.stringValue == "initial-secret", "secure field reads its initial binding value")
require((secureField as? FluentSecureTextField)?.fluentStyle is ValidationTextFieldStyle, "secure field receives the shared text field style")
require(
    secureField?.usesSingleLineMode == true
        && secureField?.maximumNumberOfLines == 1
        && secureField?.cell?.wraps == false
        && secureField?.cell?.isScrollable == true,
    "PasswordBox uses the shared one-line scrolling cell protocol"
)
if let secureField, let cell = secureField.cell {
    secureField.frame = NSRect(x: 0, y: 0, width: 280, height: 32)
    let titleRect = cell.titleRect(forBounds: secureField.bounds)
    secureTitleRect = titleRect
    require(
        titleRect.minY >= secureField.bounds.minY
            && titleRect.maxY <= secureField.bounds.maxY
            && titleRect.midY < secureField.bounds.midY,
        "secure field keeps the full native line box inside the source-asymmetric 32pt Fluent content region"
    )
}
secureText.wrappedValue = "external-secret"
drainMainQueue()
require(secureField?.stringValue == "external-secret", "secure field reflects external binding updates")
secureField?.stringValue = "edited-secret"
if let secureField, let delegate = secureField.delegate {
    delegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: secureField))
}
drainMainQueue()
require(secureText.wrappedValue == "edited-secret", "secure field writes native edits through its binding")

var coalescedSingleLineValue = ""
var coalescedSingleLineWrites = 0
let coalescedSingleLineBinding = FluentBinding<String>(
    get: { coalescedSingleLineValue },
    set: {
        coalescedSingleLineValue = $0
        coalescedSingleLineWrites += 1
    }
)
let coalescedSingleLineHost = FluentBoundTextField(coalescedSingleLineBinding)
for index in 1...250 {
    coalescedSingleLineHost.field.stringValue = "Value \(index)"
    coalescedSingleLineHost.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: coalescedSingleLineHost.field)
    )
}
require(
    coalescedSingleLineWrites == 0 && coalescedSingleLineHost.field.stringValue == "Value 250",
    "single-line native editing remains immediate without synchronously refreshing the declarative tree"
)
drainMainQueue()
require(
    coalescedSingleLineWrites == 1 && coalescedSingleLineValue == "Value 250",
    "single-line input coalesces an edit callback burst to one final binding publication"
)

let textGeometryField = FluentTextField(placeholder: "Geometry")
textGeometryField.stringValue = "0123456789"
textGeometryField.frame = NSRect(x: 20, y: 20, width: 240, height: 32)
let textGeometryRoot = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 80))
textGeometryRoot.addSubview(textGeometryField)
let textGeometryWindow = NSWindow(
    contentRect: textGeometryRoot.bounds,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
textGeometryWindow.contentView = textGeometryRoot
textGeometryWindow.makeKeyAndOrderFront(nil)
_ = textGeometryWindow.makeFirstResponder(textGeometryField)
textGeometryField.selectText(nil)
drainMainQueue()
guard let textGeometryEditor = textGeometryField.currentEditor() as? NSTextView,
      let textGeometryEditorHost = textGeometryEditor.superview,
      let textGeometryCell = textGeometryField.cell else {
    fatalError("TextBox did not create a shared native field editor")
}
let initialTextGeometry = textGeometryCell.titleRect(forBounds: textGeometryField.bounds)
let initialEditorRectInControl = textGeometryEditor.convert(textGeometryEditor.bounds, to: textGeometryField)
require(
    abs(initialEditorRectInControl.minX - initialTextGeometry.minX) <= 0.5
        && abs(initialEditorRectInControl.minY - initialTextGeometry.minY) <= 0.5
        && abs(initialEditorRectInControl.width - initialTextGeometry.width) <= 0.5
        && abs(initialEditorRectInControl.height - initialTextGeometry.height) <= 0.5
        && textGeometryEditor.textContainer?.lineFragmentPadding == 0
        && textGeometryEditor.textContainerInset == .zero,
    "TextBox drawing, placeholder, editor, caret, and selection share one content rectangle "
        + "(content: \(initialTextGeometry), editor: \(textGeometryEditor.frame), "
        + "editorInControl: \(initialEditorRectInControl), host: \(textGeometryEditorHost.frame), padding: "
        + "\(String(describing: textGeometryEditor.textContainer?.lineFragmentPadding)))"
)
let preservedTextSelection = NSRange(location: 2, length: 4)
textGeometryEditor.setSelectedRange(preservedTextSelection)
textGeometryField.setFrameSize(NSSize(width: 340, height: 40))
textGeometryRoot.layoutSubtreeIfNeeded()
drainMainQueue()
let resizedTextGeometry = textGeometryCell.titleRect(forBounds: textGeometryField.bounds)
let resizedEditorRectInControl = textGeometryEditor.convert(textGeometryEditor.bounds, to: textGeometryField)
require(
    textGeometryEditor.selectedRange() == preservedTextSelection
        && abs(resizedEditorRectInControl.minX - resizedTextGeometry.minX) <= 0.5
        && abs(resizedEditorRectInControl.minY - resizedTextGeometry.minY) <= 0.5
        && abs(resizedEditorRectInControl.width - resizedTextGeometry.width) <= 0.5
        && abs(resizedEditorRectInControl.height - resizedTextGeometry.height) <= 0.5,
    "TextBox resize updates the field-editor viewport without resetting the active selection "
        + "(content: \(resizedTextGeometry), editor: \(textGeometryEditor.frame), "
        + "editorInControl: \(resizedEditorRectInControl), host: \(textGeometryEditorHost.frame), "
        + "selection: \(textGeometryEditor.selectedRange()))"
)
textGeometryWindow.orderOut(nil)

let searchText = FluentState(wrappedValue: "")
var searchSubmits = 0
let searchView = FluentSearchField(
    searchText.projectedValue,
    placeholder: "Filter",
    style: ValidationTextFieldStyle(),
    onSubmit: { searchSubmits += 1 }
)._mount(in: FluentRenderContext())
let searchField = firstSearchField(in: searchView)
require(searchField?.placeholderString == "Filter", "search field preserves its placeholder")
require((searchField as? FluentSearchTextField)?.fluentStyle is ValidationTextFieldStyle, "search field receives the shared text field style")
require(
    searchField?.usesSingleLineMode == true
        && searchField?.maximumNumberOfLines == 1
        && searchField?.cell?.wraps == false
        && searchField?.cell?.isScrollable == true,
    "SearchBox uses the shared one-line scrolling cell protocol"
)
if let searchField, let cell = searchField.cell as? NSSearchFieldCell {
    searchField.frame = NSRect(x: 0, y: 0, width: 280, height: 32)
    let textRect = cell.searchTextRect(forBounds: searchField.bounds)
    let iconRect = cell.searchButtonRect(forBounds: searchField.bounds)
    require(
        abs(iconRect.midY - searchField.bounds.midY) <= 0.5,
        "SearchBox keeps its search adornment geometrically centered"
    )
    require(
        textRect.minX >= iconRect.maxX + 3,
        "SearchBox reserves a stable content gap after the native search icon column"
    )
    if let secureTitleRect {
        require(
            abs(secureTitleRect.midY - textRect.midY) <= 2,
            "PasswordBox and SearchBox retain the same source-derived native text baseline"
        )
    }
}
let ordinarySearchState = FluentState(wrappedValue: "")
let ordinarySearchView = FluentSearchField(
    ordinarySearchState.projectedValue,
    placeholder: "Ordinary search"
)._mount(in: FluentRenderContext())
let ordinarySearchField = firstSearchField(in: ordinarySearchView) as? FluentSearchTextField
let ordinarySearchAppearance = ordinarySearchField.map { field in
    field.fluentStyle.appearance(
        for: FluentTextFieldStyleConfiguration(
            isEnabled: field.isEnabled,
            isFocused: false,
            isPointerOver: false,
            controlSize: field.fluentControlSize,
            theme: field.theme
        )
    )
}
require(
    ordinarySearchAppearance.map {
        abs($0.cornerRadius - (ordinarySearchField?.theme.designTokens.controlCornerRadius ?? 0)) < 0.001
    } == true,
    "ordinary SearchBox resolves WinUI ControlCornerRadius through the shared automatic TextControl style"
)
searchField?.stringValue = "fluent"
if let searchField, let delegate = searchField.delegate {
    delegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: searchField))
}
drainMainQueue()
require(searchText.wrappedValue == "fluent", "search field writes native edits through its binding")
searchText.wrappedValue = "external-filter"
drainMainQueue()
require(searchField?.stringValue == "external-filter", "search field reflects external binding updates")
if let searchField, let action = searchField.action {
    require(NSApp.sendAction(action, to: searchField.target, from: searchField), "search field sends its submit action")
}
require(searchSubmits == 1, "search field invokes submit callback")
if let searchField, let cell = searchField.cell as? NSSearchFieldCell {
    let searchEditingWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    searchView.frame = NSRect(x: 20, y: 20, width: 280, height: 32)
    searchEditingWindow.contentView = searchView
    let searchAppearanceCoordinator = FluentAppearanceCoordinator(
        theme: theme.with(colorScheme: .light)
    )
    searchAppearanceCoordinator.attach(to: searchEditingWindow)
    searchEditingWindow.makeKeyAndOrderFront(nil)
    _ = searchEditingWindow.makeFirstResponder(searchField)
    searchField.selectText(nil)
    drainMainQueue()
    guard let editor = searchField.currentEditor() as? NSTextView,
          let editorSuperview = editor.superview else {
        fatalError("SearchBox did not create a native field editor")
    }
    require(
        !editor.isVerticallyResizable
            && editor.isHorizontallyResizable
            && editor.textContainer?.maximumNumberOfLines == 1
            && editor.textContainer?.lineBreakMode == .byClipping
            && editor.textContainer?.widthTracksTextView == false
            && editor.textContainer?.heightTracksTextView == true,
        "single-line controls configure the shared AppKit field editor without replacing it"
    )
    let searchTheme = (searchField as? FluentSearchTextField)?.theme ?? .current
    require(
        colorMatches(editor.insertionPointColor.cgColor, searchTheme.textCaret),
        "SearchBox field editor uses the source-derived TextControl caret color (actual: \(String(describing: editor.insertionPointColor.usingColorSpace(.deviceRGB))), expected: \(String(describing: searchTheme.textCaret.usingColorSpace(.deviceRGB))))"
    )
    require(
        !editor.drawsBackground
            && colorMatches(editor.textColor?.cgColor, searchTheme.textPrimary)
            && colorMatches(
                (editor.typingAttributes[.foregroundColor] as? NSColor)?.cgColor,
                searchTheme.textPrimary
            ),
        "SearchBox field editor reapplies Fluent foreground and transparent background after AppKit setup"
    )
    require(
        colorMatches(
            (editor.selectedTextAttributes[.backgroundColor] as? NSColor)?.cgColor,
            searchTheme.textSelectionBackground
        ) && colorMatches(
            (editor.selectedTextAttributes[.foregroundColor] as? NSColor)?.cgColor,
            searchTheme.textSelectionForeground
        ),
        "SearchBox field editor uses the WinUI selection highlight and selected-text colors"
    )
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    let caretScreenRect = editor.firstRect(
        forCharacterRange: NSRange(location: 0, length: 0),
        actualRange: nil
    )
    let expectedTextRect = cell.searchTextRect(forBounds: searchField.bounds)
    let expectedTextScreenRect = searchEditingWindow.convertToScreen(
        searchField.convert(expectedTextRect, to: nil)
    )
    require(
        abs(caretScreenRect.minX - expectedTextScreenRect.minX) <= 1
            && abs(caretScreenRect.midY - expectedTextScreenRect.midY) <= 1,
        "SearchBox caret uses the same content geometry as placeholder text (caret: \(caretScreenRect), expected: \(expectedTextScreenRect), editor: \(editor.frame), superview: \(editorSuperview.frame))"
    )
    let searchIconRect = cell.searchButtonRect(forBounds: searchField.bounds)
    require(
        abs(searchIconRect.midY - expectedTextRect.midY) <= 0.5,
        "SearchBox icon, caret, and edited text share one vertical center"
    )

    editor.setSelectedRange(NSRange(location: 0, length: min(4, editor.string.utf16.count)))
    searchField.rightMouseDown(
        with: toggleMouseEvent(
            .rightMouseDown,
            at: NSPoint(x: expectedTextRect.minX + 12, y: expectedTextRect.midY),
            in: searchField,
            eventNumber: 91
        )
    )
    require(
        waitUntil(timeout: 0.20) { searchEditingWindow.childWindows?.count == 1 },
        "SearchBox replaces the AppKit context menu with an application-owned text command flyout"
    )
    if let commandPanel = searchEditingWindow.childWindows?.first,
       let commandPresenter = commandPanel.contentView.flatMap({
           firstView(withAccessibilityRole: .menu, in: $0)
       }) {
        let commandSurface = commandPanel.contentView.flatMap(firstMaterialView)
        require(
            commandSurface?.materialStyle == .liquidGlass
                && commandSurface?.isMaterialEnabled == true,
            "TextCommandBarFlyout uses the global Liquid Glass transient surface"
        )
        let overlayCornerRadius = (searchField as? FluentSearchTextField)?.theme.designTokens.cardCornerRadius ?? 8
        require(
            commandPanel.contentView?.layer?.masksToBounds == true
                && abs((commandPanel.contentView?.layer?.cornerRadius ?? 0) - overlayCornerRadius) < 0.001
                && commandSurface?.layer?.masksToBounds == true
                && abs((commandSurface?.layer?.cornerRadius ?? 0) - overlayCornerRadius) < 0.001,
            "TextCommandBarFlyout clips material and commands once at the source OverlayCornerRadius"
        )
        let textCommandEntrance = commandPanel.contentView?.layer?.animation(
            forKey: "fluent.popup.textCommandBar.open.opacity"
        ) as? CABasicAnimation
        require(
            abs((textCommandEntrance?.duration ?? 0) - FluentMotion.commandBarFlyoutOpen.duration) < 0.0001
                && (textCommandEntrance?.fromValue as? NSNumber)?.doubleValue == 0
                && (textCommandEntrance?.toValue as? NSNumber)?.doubleValue == 1
                && timingFunctionMatches(
                    textCommandEntrance?.timingFunction,
                    FluentMotion.commandBarFlyoutOpen.curve.timingFunction
                ),
            "TextCommandBarFlyout uses the shared coordinator for the source 83ms linear whole-presenter entrance"
        )
        let commandTitles = Set(
            (commandPresenter.accessibilityChildren() ?? []).compactMap {
                ($0 as? NSView)?.accessibilityTitle()
            }
        )
        require(
            commandTitles.contains("Cut")
                && commandTitles.contains("Copy")
                && commandTitles.contains("Select All")
                && !commandTitles.contains("More"),
            "mouse TextCommandBarFlyout places available editing commands in the secondary row presenter"
        )
        let commandRows = (commandPresenter.accessibilityChildren() ?? []).compactMap { $0 as? NSView }
        require(
            commandPresenter.identifier?.rawValue == "FluentKit.TextCommandBarFlyout"
                && commandRows.allSatisfy {
                    abs($0.frame.height - 32) < 0.001
                        && abs($0.frame.minX - 4) < 0.001
                        && abs($0.frame.maxX - (commandPresenter.bounds.maxX - 4)) < 0.001
                },
            "mouse TextCommandBarFlyout uses source secondary-command row geometry (panel: \(commandPanel.frame), children: \(commandRows.map { ($0.accessibilityTitle() ?? "", $0.frame) }))"
        )
        require(
            commandPanel.frame.width < searchField.bounds.width,
            "text command flyout uses CommandBarFlyout content width instead of matching the TextBox host"
        )
        let commandDarkTheme = theme.with(colorScheme: .dark)
        searchAppearanceCoordinator.updateTheme(commandDarkTheme)
        drainMainQueue()
        require(
            commandPanel.contentView.flatMap(firstMaterialView) === commandSurface
                && commandSurface?.fluentTheme == commandDarkTheme
                && colorMatches(
                    firstLayer(named: "FluentKit.Material.OpaqueFallback", in: commandSurface ?? NSView())?.backgroundColor,
                    commandDarkTheme.flyoutSurfaceFill
                )
                && commandPanel.contentView?.layer?.animation(
                    forKey: "fluent.popup.textCommandBar.open.opacity"
                ) == nil,
            "TextCommandBarFlyout updates in place and settles its entrance during a window appearance change"
        )
        searchAppearanceCoordinator.updateTheme(theme.with(colorScheme: .light))
        drainMainQueue()
        commandPresenter.keyDown(with: sliderKeyEvent(53, in: commandPresenter, eventNumber: 92))
    } else {
        fatalError("SearchBox text command flyout did not expose a custom presenter")
    }
    require(
        waitUntil(timeout: 0.20) { searchEditingWindow.childWindows?.isEmpty != false },
        "text command flyout dismisses through the shared Fluent keyboard path"
    )

    searchField.rightMouseDown(
        with: toggleMouseEvent(
            .leftMouseDown,
            at: NSPoint(x: expectedTextRect.minX + 12, y: expectedTextRect.midY),
            in: searchField,
            eventNumber: 95
        )
    )
    require(
        waitUntil(timeout: 0.20) { searchEditingWindow.childWindows?.count == 1 },
        "TextCommandBarFlyout supports an input-device-preferred primary command composition"
    )
    if let primaryPanel = searchEditingWindow.childWindows?.first,
       let primaryPresenter = primaryPanel.contentView.flatMap({
           firstView(withAccessibilityRole: .menu, in: $0)
       }) {
        let primaryChildren = (primaryPresenter.accessibilityChildren() ?? []).compactMap { $0 as? NSView }
        let primaryTitles = Set(primaryChildren.compactMap { $0.accessibilityTitle() })
        require(
            primaryTitles.contains("Cut")
                && primaryTitles.contains("Copy")
                && primaryTitles.contains("More")
                && !primaryTitles.contains("Select All")
                && primaryChildren.allSatisfy {
                    abs($0.frame.width - 40) < 0.001 && abs($0.frame.height - 40) < 0.001
                },
            "TextCommandBarFlyout renders direct editing commands and More in source 40pt primary slots"
        )
        let collapsedHeight = primaryPanel.frame.height
        let moreButton = primaryChildren.first { $0.accessibilityTitle() == "More" }
        require(moreButton?.accessibilityPerformPress() == true, "TextCommandBarFlyout More expands secondary commands")
        let expansionClip = primaryPanel.contentView.flatMap {
            firstLayer(named: "FluentKit.TextCommandBarFlyout.ExpansionClip", in: $0)
        }
        let expansionAnimation = expansionClip?.animation(
            forKey: "fluent.popup.textCommandBar.expand.clip"
        ) as? CABasicAnimation
        require(
            expansionAnimation?.keyPath == "path"
                && abs((expansionAnimation?.duration ?? 0) - FluentMotion.controlNormal.duration) < 0.0001
                && timingFunctionMatches(
                    expansionAnimation?.timingFunction,
                    FluentMotion.controlNormal.curve.timingFunction
                ),
            "TextCommandBarFlyout More uses the source 250ms collapsed-to-expanded clip timeline"
        )
        require(
            waitUntil(timeout: 0.30) {
                let titles = Set(
                    (primaryPresenter.accessibilityChildren() ?? []).compactMap {
                        ($0 as? NSView)?.accessibilityTitle()
                    }
                )
                return titles.contains("Select All") && primaryPanel.frame.height > collapsedHeight
            },
            "TextCommandBarFlyout expansion adds secondary rows and grows the complete panel"
        )
        primaryPresenter.keyDown(with: sliderKeyEvent(53, in: primaryPresenter, eventNumber: 96))
    } else {
        fatalError("TextCommandBarFlyout did not expose its primary command composition")
    }
    require(
        waitUntil(timeout: 0.20) { searchEditingWindow.childWindows?.isEmpty != false },
        "expanded TextCommandBarFlyout dismisses immediately"
    )

    if let secureField {
        secureView.frame = NSRect(x: 20, y: 20, width: 280, height: 32)
        searchEditingWindow.contentView = secureView
        _ = searchEditingWindow.makeFirstResponder(secureField)
        secureField.selectText(nil)
        drainMainQueue()
        if let secureEditor = secureField.currentEditor() as? NSTextView {
            secureEditor.setSelectedRange(NSRange(location: 0, length: secureEditor.string.utf16.count))
        }
        secureField.rightMouseDown(
            with: toggleMouseEvent(
                .rightMouseDown,
                at: NSPoint(x: 24, y: secureField.bounds.midY),
                in: secureField,
                eventNumber: 93
            )
        )
        require(
            waitUntil(timeout: 0.20) { searchEditingWindow.childWindows?.count == 1 },
            "PasswordBox presents its restricted text command flyout"
        )
        if let securePresenter = searchEditingWindow.childWindows?.first?.contentView.flatMap({
            firstView(withAccessibilityRole: .menu, in: $0)
        }) {
            let secureTitles = Set(
                (securePresenter.accessibilityChildren() ?? []).compactMap {
                    ($0 as? NSView)?.accessibilityTitle()
                }
            )
            require(
                !secureTitles.contains("Cut")
                    && !secureTitles.contains("Copy")
                    && secureTitles.contains("Select All"),
                "PasswordBox follows WinUI by withholding Cut and Copy while retaining Select All"
            )
            securePresenter.keyDown(with: sliderKeyEvent(53, in: securePresenter, eventNumber: 94))
        } else {
            fatalError("PasswordBox text command flyout did not expose a custom presenter")
        }
    }
    searchEditingWindow.orderOut(nil)
}

enum ValidationOption: String, Hashable { case first, second, third }
let comboSelection = FluentState<ValidationOption?>(wrappedValue: .second)
let comboView = FluentComboBox(
    options: [.first, .second, .third],
    selection: comboSelection.projectedValue,
    style: ValidationTextFieldStyle(),
    title: { $0.rawValue.capitalized }
)._mount(in: FluentRenderContext())
let nativeComboBox = firstComboBox(in: comboView)
require(nativeComboBox?.indexOfSelectedItem == 1, "combo box resolves stable selection to its native index")
require(nativeComboBox?.font?.pointSize == 17, "combo box receives the shared semantic field font")
nativeComboBox?.selectItem(at: 2)
if let combo = nativeComboBox {
    let comboDelegate: NSComboBoxDelegate? = combo.delegate
    if let comboDelegate {
        comboDelegate.comboBoxSelectionDidChange?(Notification(name: NSComboBox.selectionDidChangeNotification, object: combo))
    }
}
require(comboSelection.wrappedValue == .third, "combo box writes selected stable value")
let comboFlyoutWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
comboView.frame = NSRect(x: 20, y: 40, width: 220, height: 34)
comboFlyoutWindow.contentView = comboView
let comboAppearanceTheme = theme.with(colorScheme: .light)
let comboAppearanceCoordinator = FluentAppearanceCoordinator(theme: comboAppearanceTheme)
comboAppearanceCoordinator.attach(to: comboFlyoutWindow)
comboFlyoutWindow.center()
comboFlyoutWindow.makeKeyAndOrderFront(nil)
comboView.layoutSubtreeIfNeeded()
guard let comboElevationBorder = firstLayer(
    named: "FluentKit.ComboBox.ElevationBorder",
    in: comboView
) as? CAGradientLayer,
      let comboElevationMask = comboElevationBorder.mask as? CAShapeLayer,
      let comboElevationPath = comboElevationMask.path else {
    fatalError("ComboBox elevation border did not mount")
}
let comboElevationBounds = comboElevationPath.boundingBox
require(
    comboElevationMask.fillRule == .evenOdd
        && pathBoundsUseContainedAntialiasing(
            comboElevationBounds,
            in: comboView.bounds,
            backingScale: comboElevationBorder.contentsScale
        ),
    "ComboBox keeps its elevation antialiasing inside every host edge"
)
require(
    comboElevationBorder.locations?.map(\.doubleValue) == [0.33, 1],
    "ComboBox uses the shared Button ControlElevationBorderBrush stop positions"
)
require(
    elevationGradientMatchesVisualEdge(
        comboElevationBorder,
        edge: .bottom,
        hostView: comboView
    ),
    "ComboBox uses the source three-point extent at its visual elevation edge"
)
let coldComboChevron = firstLayer(
    named: "FluentKit.ComboBox.Chevron",
    in: comboView
) as? CAShapeLayer
let coldComboChevronPoints = pathVertices(coldComboChevron?.path)
require(
    chevronPointsVisuallyDown(coldComboChevronPoints, in: coldComboChevron),
    "ComboBox points its cold-start chevron visually down before hover"
)
guard let comboFocusPill = firstLayer(named: "FluentKit.ComboBox.FocusPill", in: comboView) else {
    fatalError("ComboBox focus Pill did not mount")
}
guard let comboFocusHighlight = firstLayer(named: "FluentKit.ComboBox.FocusHighlight", in: comboView) else {
    fatalError("ComboBox focus Highlight did not mount")
}
guard let nativeComboBox else { fatalError("ComboBox native control did not mount") }
require(
    nativeComboBox.usesSingleLineMode
        && nativeComboBox.maximumNumberOfLines == 1
        && nativeComboBox.cell?.wraps == false
        && nativeComboBox.cell?.isScrollable == true,
    "selection ComboBox uses the shared one-line scrolling cell protocol"
)
nativeComboBox.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: nativeComboBox.bounds.midX, y: nativeComboBox.bounds.midY),
        in: nativeComboBox,
        eventNumber: 69
    )
)
require(
    translationMovesVisuallyDown(
        coldComboChevron?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0,
        in: coldComboChevron
    ),
    "ComboBox press moves the shared chevron along the stable visual-down axis"
)
require(
    comboFlyoutWindow.childWindows?.isEmpty != false,
    "pointer-down only enters the ComboBox pressed state without presenting its popup"
)
require(
    comboFocusPill.opacity == 0
        && comboFocusPill.frame.size == CGSize(width: 3, height: 16),
    "pointer-focused ComboBox keeps the source-derived Pill hidden"
)
require(
    comboFocusHighlight.opacity == 0
        && comboFocusHighlight.frame == comboView.bounds.insetBy(dx: -4, dy: -4)
        && comboFocusHighlight.borderWidth == 2
        && comboFocusHighlight.cornerRadius == 7,
    "pointer-focused ComboBox preserves keyboard-highlight geometry without displaying it"
)
nativeComboBox.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: nativeComboBox.bounds.midX, y: nativeComboBox.bounds.midY),
        in: nativeComboBox,
        eventNumber: 70
    )
)
drainMainQueue()
require(comboFlyoutWindow.childWindows?.count == 1, "combo box opens an application-owned flyout panel")
if let comboPanelContent = comboFlyoutWindow.childWindows?.first?.contentView {
    comboPanelContent.layoutSubtreeIfNeeded()
    require(firstView(withAccessibilityRole: .menu, in: comboPanelContent) != nil, "combo box popup exposes its dedicated menu semantics")
    require(
        firstMaterialView(in: comboPanelContent)?.materialStyle == .liquidGlass
            && firstMaterialView(in: comboPanelContent)?.isMaterialEnabled == true,
        "ComboBox popup uses the global Liquid Glass transient surface"
    )
    require(
        comboFlyoutWindow.childWindows?.first?.hasShadow == false,
        "ComboBox popup does not stack a native black panel shadow around its opaque surface"
    )
    require(
        comboPanelContent.layer?.borderWidth == 0,
        "ComboBox popup keeps one opaque edge owner without a second CALayer stroke"
    )
    let comboBorderLayer = firstLayer(named: "FluentKit.ComboBoxPopup.PopupBorder", in: comboPanelContent)
    let comboPresenterLayer = firstLayer(named: "FluentKit.ComboBoxPopup.Presenter", in: comboPanelContent)
    let comboClipLayer = firstLayer(named: "FluentKit.ComboBoxPopup.RevealClip", in: comboPanelContent)
    let comboBorderEntrance = comboBorderLayer?.animation(forKey: "fluent.popup.border.open") as? CABasicAnimation
    let comboPresenterEntrance = comboPresenterLayer?.animation(forKey: "fluent.popup.presenter.open") as? CABasicAnimation
    let comboMaskBoundsEntrance = comboClipLayer?.animation(forKey: "fluent.popup.reveal.bounds") as? CABasicAnimation
    let comboMaskPositionEntrance = comboClipLayer?.animation(forKey: "fluent.popup.reveal.position") as? CABasicAnimation
    let comboClosedMaskBounds = (comboMaskBoundsEntrance?.fromValue as? NSValue)?.rectValue
    let comboClosedMaskPosition = (comboMaskPositionEntrance?.fromValue as? NSValue)?.pointValue
    let comboOpenMaskBounds = (comboMaskBoundsEntrance?.toValue as? NSValue)?.rectValue
    let comboOpenMaskPosition = (comboMaskPositionEntrance?.toValue as? NSValue)?.pointValue
    require(
        comboBorderEntrance == nil
            && comboPresenterEntrance == nil
            && comboMaskBoundsEntrance?.keyPath == "bounds"
            && comboMaskPositionEntrance?.keyPath == "position"
            && abs((comboMaskBoundsEntrance?.duration ?? 0) - FluentMotion.comboBoxOpen.duration) < 0.0001,
        "ComboBox popup runs SplitOpen on the popup clip without MenuFlyout presenter translation"
    )
    guard let selectedRow = firstView(withAccessibilityTitle: "Third", in: comboPanelContent),
          let selectionPill = firstLayer(named: "FluentKit.ComboBoxItem.SelectionPill", in: comboPanelContent) else {
        fatalError("ComboBox selected-item Pill did not mount")
    }
    require(
        selectionPill.frame.size == CGSize(width: 3, height: 16),
        "selected ComboBoxItem exposes the source-derived 3 x 16 leading Pill"
    )
    require(
        selectedRow.isAccessibilitySelected(),
        "opening ComboBox highlights its current bound selection"
    )
    let selectedRowInPopup = selectedRow.convert(selectedRow.bounds, to: comboPanelContent)
    let popupHeight = comboPanelContent.bounds.height
    let baseClosedHeight = popupHeight * 0.5
    let selectedOffsetFromCenter = abs(selectedRowInPopup.midY - popupHeight / 2)
    let maximumClosedOffset = popupHeight * 0.25
    let expectedClosedHeight = selectedOffsetFromCenter > maximumClosedOffset
        ? baseClosedHeight + 2 * (baseClosedHeight / 2 - (popupHeight / 2 - selectedOffsetFromCenter))
        : baseClosedHeight
    require(
        abs((comboClosedMaskPosition?.y ?? -CGFloat.infinity) - selectedRowInPopup.midY) < 0.001
            && comboOpenMaskPosition == comboClosedMaskPosition
            && abs((comboClosedMaskBounds?.height ?? 0) - expectedClosedHeight) < 0.001
            && abs((comboOpenMaskBounds?.height ?? 0) - (popupHeight + selectedOffsetFromCenter * 2)) < 0.001,
        "ComboBox SplitOpen keeps its source-derived clip centered on the original selected item"
    )
    if let unselectedRow = firstView(withAccessibilityTitle: "First", in: comboPanelContent) {
        unselectedRow.updateTrackingAreas()
        unselectedRow.updateTrackingAreas()
        require(
            unselectedRow.trackingAreas.count == 1,
            "ComboBoxItem keeps exactly one tracking area across repeated layout updates"
        )
        unselectedRow.mouseEntered(
            with: toggleMouseEvent(
                .mouseMoved,
                at: NSPoint(x: 20, y: 16),
                in: unselectedRow,
                eventNumber: 70
            )
        )
        require(
            comboSelection.wrappedValue == .third
                && selectedRow.isAccessibilitySelected()
                && !unselectedRow.isAccessibilitySelected(),
            "pointer-over does not move ComboBox selection or its Pill before commit"
        )
        if let secondRow = firstView(withAccessibilityTitle: "Second", in: comboPanelContent),
           let firstBackground = firstLayer(named: "FluentKit.ComboBoxItem.Background", in: unselectedRow),
           let secondBackground = firstLayer(named: "FluentKit.ComboBoxItem.Background", in: secondRow) {
            secondRow.mouseEntered(
                with: toggleMouseEvent(
                    .mouseMoved,
                    at: NSPoint(x: 20, y: 16),
                    in: secondRow,
                    eventNumber: 71
                )
            )
            require(
                colorMatches(firstBackground.backgroundColor, .clear)
                    && colorMatches(secondBackground.backgroundColor, comboAppearanceTheme.subtleFillSecondary),
                "ComboBox popup owns one PointerOver row and clears the previous row immediately"
            )
            secondRow.mouseExited(
                with: toggleMouseEvent(
                    .mouseMoved,
                    at: NSPoint(x: -1, y: -1),
                    in: secondRow,
                    eventNumber: 72
                )
            )
        }
        unselectedRow.mouseExited(
            with: toggleMouseEvent(
                .mouseMoved,
                at: NSPoint(x: -1, y: -1),
                in: unselectedRow,
                eventNumber: 71
            )
        )
    }
    if let selectedRowWindow = selectedRow.window {
        let comboScreenRect = comboFlyoutWindow.convertToScreen(comboView.convert(comboView.bounds, to: nil))
        let selectedScreenRect = selectedRowWindow.convertToScreen(selectedRow.convert(selectedRow.bounds, to: nil))
        require(
            abs(comboScreenRect.midY - selectedScreenRect.midY) < 1,
            "ComboBox popup centers its current selection over the closed control"
        )
    }
    let comboPopupDarkTheme = theme.with(colorScheme: .dark)
    comboAppearanceCoordinator.updateTheme(comboPopupDarkTheme)
    drainMainQueue()
    let updatedComboMaterial = firstMaterialView(in: comboPanelContent)
    require(
        updatedComboMaterial?.fluentTheme == comboPopupDarkTheme
            && colorMatches(comboBorderLayer?.borderColor, comboPopupDarkTheme.surfaceStrokeFlyout)
            && comboClipLayer?.animationKeys()?.isEmpty != false
            && comboBorderLayer?.animationKeys()?.isEmpty != false,
        "ComboBox popup updates its material and rows after settling the shared entrance timeline"
    )
    comboAppearanceCoordinator.updateTheme(theme.with(colorScheme: .light))
    drainMainQueue()
    selectedRow.mouseDown(
        with: toggleMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 16), in: selectedRow, eventNumber: 72)
    )
    let pillPressAnimation = selectionPill.animation(forKey: "fluent.combobox.pill.frame") as? CABasicAnimation
    require(
        selectionPill.frame.height == 10
            && abs((pillPressAnimation?.duration ?? 0) - 0.167) < 0.0001,
        "pressed ComboBoxItem compresses its Pill to 62.5% over 167ms (row: \(String(describing: type(of: selectedRow))), height: \(selectionPill.frame.height), animation: \(String(describing: pillPressAnimation?.duration)))"
    )
    selectedRow.mouseUp(
        with: toggleMouseEvent(.leftMouseUp, at: NSPoint(x: 20, y: 16), in: selectedRow, eventNumber: 73)
    )
    require(
        comboPanelContent.layer?.animation(forKey: "fluent.combobox.popup.surface.close") == nil
            && comboFlyoutWindow.childWindows?.isEmpty != false,
        "ComboBox item commit removes the popup immediately without exit animation"
    )
}
nativeComboBox.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: nativeComboBox.bounds.midX, y: nativeComboBox.bounds.midY),
        in: nativeComboBox,
        eventNumber: 74
    )
)
nativeComboBox.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: nativeComboBox.bounds.midX, y: nativeComboBox.bounds.midY),
        in: nativeComboBox,
        eventNumber: 75
    )
)
drainMainQueue()
require(comboFlyoutWindow.childWindows?.count == 1, "ComboBox reopens for Escape dismissal validation")
if let escapeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
    if let panel = comboFlyoutWindow.childWindows?.first,
       let presenter = panel.contentView.flatMap({ firstView(withAccessibilityRole: .menu, in: $0) }) {
        presenter.keyDown(with: escapeEvent)
    }
}
require(
    comboFlyoutWindow.childWindows?.isEmpty != false,
    "ComboBox Escape dismissal removes the popup immediately"
)
comboFlyoutWindow.orderOut(nil)

let editableComboText = FluentState(wrappedValue: "Second")
let editableComboSelection = FluentState<ValidationOption?>(wrappedValue: .second)
let editableComboView = FluentComboBox(
    options: [.first, .second, .third],
    selection: editableComboSelection.projectedValue,
    mode: .editable,
    text: editableComboText.projectedValue,
    title: { $0.rawValue.capitalized }
)._mount(in: FluentRenderContext())
editableComboView.frame = NSRect(x: 20, y: 40, width: 220, height: 34)
let editableComboWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
editableComboWindow.contentView = editableComboView
editableComboWindow.center()
editableComboWindow.makeKeyAndOrderFront(nil)
editableComboView.layoutSubtreeIfNeeded()
guard let editableNativeCombo = firstComboBox(in: editableComboView) else {
    fatalError("Editable ComboBox did not mount")
}
let editableFaceplate = editableComboView.subviews.first { view in
    guard let field = view as? NSTextField else { return false }
    return field.isEditable && field !== editableNativeCombo
}
require(
    editableNativeCombo.isEditable
        && editableNativeCombo.alphaValue == 0
        && (editableFaceplate as? NSTextField)?.isEditable == true,
    "editable ComboBox exposes a native text editor without the NSComboBox button chrome"
)
guard let editableTextField = editableFaceplate as? NSTextField else {
    fatalError("Editable ComboBox text faceplate did not mount")
}
require(
    editableTextField.usesSingleLineMode
        && editableTextField.maximumNumberOfLines == 1
        && editableTextField.cell?.wraps == false
        && editableTextField.cell?.isScrollable == true,
    "editable ComboBox input uses the shared one-line scrolling cell protocol"
)
guard let editableElevationBorder = firstLayer(
    named: "FluentKit.ComboBox.ElevationBorder",
    in: editableComboView
) else {
    fatalError("Editable ComboBox Button elevation did not mount")
}
_ = editableComboWindow.makeFirstResponder(nil)
editableTextField.delegate?.controlTextDidEndEditing?(
    Notification(name: NSControl.textDidEndEditingNotification, object: editableTextField)
)
require(
    !editableElevationBorder.isHidden,
    "unfocused editable ComboBox starts with Button-like elevation chrome"
)
editableTextField.delegate?.controlTextDidBeginEditing?(
    Notification(name: NSControl.textDidBeginEditingNotification, object: editableTextField)
)
require(
    editableElevationBorder.isHidden,
    "editing an editable ComboBox replaces Button elevation with TextControl chrome"
)
editableTextField.delegate?.controlTextDidEndEditing?(
    Notification(name: NSControl.textDidEndEditingNotification, object: editableTextField)
)
require(
    !editableElevationBorder.isHidden,
    "ending editable ComboBox text editing restores Button-like elevation chrome"
)
editableTextField.stringValue = "Custom"
editableTextField.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: editableTextField))
drainMainQueue()
require(
    waitUntil(timeout: 0.20) {
        editableComboText.wrappedValue == "Custom" && editableComboSelection.wrappedValue == nil
    },
    "editable ComboBox writes arbitrary text without selecting an option "
        + "(text: \(editableComboText.wrappedValue), selection: \(String(describing: editableComboSelection.wrappedValue)))"
)
editableTextField.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: editableTextField.bounds.maxX - 8, y: editableTextField.bounds.midY),
        in: editableTextField,
        eventNumber: 75
    )
)
require(
    editableComboWindow.childWindows?.isEmpty != false,
    "editable ComboBox glyph pointer-down does not present before release"
)
editableTextField.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: editableTextField.bounds.maxX - 8, y: editableTextField.bounds.midY),
        in: editableTextField,
        eventNumber: 76
    )
)
drainMainQueue()
require(editableComboWindow.childWindows?.count == 1, "editable ComboBox opens from its dedicated glyph column")
require(
    editableElevationBorder.isHidden,
    "an open editable ComboBox uses the TextControl faceplate instead of stale Button elevation"
)
if let editablePanel = editableComboWindow.childWindows?.first,
   let editablePanelContent = editablePanel.contentView {
    let anchorRect = editableComboWindow.convertToScreen(editableComboView.convert(editableComboView.bounds, to: nil))
    require(editablePanel.frame.maxY <= anchorRect.minY + 1, "editable ComboBox popup opens below the text field")
    require(
        {
            let clip = firstLayer(named: "FluentKit.ComboBoxPopup.RevealClip", in: editablePanelContent)
            let boundsAnimation = clip?.animation(forKey: "fluent.popup.reveal.bounds") as? CABasicAnimation
            let positionAnimation = clip?.animation(forKey: "fluent.popup.reveal.position") as? CABasicAnimation
            let closedPosition = (positionAnimation?.fromValue as? NSValue)?.pointValue
            let openPosition = (positionAnimation?.toValue as? NSValue)?.pointValue
            return boundsAnimation != nil
                && closedPosition == openPosition
                && (closedPosition?.y ?? 0) > editablePanelContent.bounds.maxY
        }(),
        "editable ComboBox reveals from the external TextBox faceplate baseline"
    )
}
guard let firstEditableRow = editableComboWindow.childWindows?.first?.contentView.flatMap({ firstView(withAccessibilityTitle: "First", in: $0) }) else {
    fatalError("Editable ComboBox first row did not mount")
}
require(firstEditableRow.accessibilityPerformPress(), "editable ComboBox item exposes a press action")
require(
    editableComboText.wrappedValue == "First" && editableComboSelection.wrappedValue == .first,
    "editable ComboBox commits an option into both text and selection (text=\(editableComboText.wrappedValue), selection=\(String(describing: editableComboSelection.wrappedValue)))"
)
require(editableComboWindow.childWindows?.isEmpty != false, "editable ComboBox dismisses immediately after item commit")
editableComboWindow.orderOut(nil)

let reducedMotionComboSelection = FluentState<ValidationOption?>(wrappedValue: .first)
let reducedMotionComboView = FluentComboBox(
    options: [.first, .second, .third],
    selection: reducedMotionComboSelection.projectedValue,
    title: { $0.rawValue.capitalized }
)._mount(in: FluentRenderContext(reduceMotion: true))
let reducedMotionComboWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
reducedMotionComboView.frame = NSRect(x: 20, y: 40, width: 220, height: 34)
reducedMotionComboWindow.contentView = reducedMotionComboView
reducedMotionComboWindow.center()
reducedMotionComboWindow.makeKeyAndOrderFront(nil)
reducedMotionComboView.layoutSubtreeIfNeeded()
guard let reducedMotionNativeCombo = firstComboBox(in: reducedMotionComboView) else {
    fatalError("Reduce Motion ComboBox did not mount")
}
reducedMotionNativeCombo.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: reducedMotionNativeCombo.bounds.midX, y: reducedMotionNativeCombo.bounds.midY),
        in: reducedMotionNativeCombo,
        eventNumber: 74
    )
)
reducedMotionNativeCombo.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: reducedMotionNativeCombo.bounds.midX, y: reducedMotionNativeCombo.bounds.midY),
        in: reducedMotionNativeCombo,
        eventNumber: 75
    )
)
drainMainQueue()
guard waitUntil(timeout: 0.25, {
    reducedMotionComboWindow.childWindows?.first?.contentView != nil
}), let reducedMotionComboPanelContent = reducedMotionComboWindow.childWindows?.first?.contentView else {
    fatalError("Reduce Motion ComboBox popup did not present")
}
require(
        firstLayer(named: "FluentKit.ComboBoxPopup.PopupBorder", in: reducedMotionComboPanelContent)?
        .animation(forKey: "fluent.popup.border.open") == nil
        && firstLayer(named: "FluentKit.ComboBoxPopup.Presenter", in: reducedMotionComboPanelContent)?
            .animation(forKey: "fluent.popup.presenter.open") == nil
        && firstLayer(named: "FluentKit.ComboBoxPopup.RevealClip", in: reducedMotionComboPanelContent)?
            .animation(forKey: "fluent.popup.reveal.bounds") == nil
        && firstLayer(named: "FluentKit.ComboBoxPopup.RevealClip", in: reducedMotionComboPanelContent)?
            .animation(forKey: "fluent.popup.reveal.position") == nil,
    "ComboBox Reduce Motion reaches final popup geometry without entrance animation"
)
if let escapeEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "\u{1b}",
    charactersIgnoringModifiers: "\u{1b}",
    isARepeat: false,
    keyCode: 53
), let presenter = firstView(withAccessibilityRole: .menu, in: reducedMotionComboPanelContent) {
    presenter.keyDown(with: escapeEvent)
}
require(
    reducedMotionComboWindow.childWindows?.isEmpty != false,
    "ComboBox dismissal remains immediate under Reduce Motion"
)
reducedMotionComboWindow.orderOut(nil)

let reducedCombo = FluentComboBox(
    options: [.first, .second],
    selection: comboSelection.projectedValue,
    style: ValidationTextFieldStyle(),
    title: { $0.rawValue.capitalized }
)
require(reducedCombo._update(comboView, in: FluentRenderContext()), "combo box updates options in place")
drainMainQueue()
require(comboSelection.wrappedValue == nil, "combo box clears selection when its stable option is removed")
require(nativeComboBox.indexOfSelectedItem == -1, "combo box clears native selection when its option is removed")

let quantity = FluentState(wrappedValue: 2)
let stepperView = FluentStepper("Quantity", value: quantity.projectedValue, in: 1...5, step: 1)
    .stepperStyle(ValidationStepperStyle())
    ._mount(in: FluentRenderContext())
let nativeStepper = firstStepper(in: stepperView)
let stepperField = firstFluentTextField(in: stepperView)
let stepperLabel = firstLabel(in: stepperView)
require(nativeStepper?.doubleValue == 2, "stepper reads its initial integer binding")
require(
    stepperField?.usesSingleLineMode == true
        && stepperField?.maximumNumberOfLines == 1
        && stepperField?.cell?.wraps == false,
    "Stepper value editor inherits the shared single-line TextBox protocol"
)
require(stepperField?.fluentStyle is ValidationTextFieldStyle, "stepper applies its nested field style")
require(stepperLabel?.font?.pointSize == 17, "stepper style applies semantic label metrics")
quantity.wrappedValue = 99
drainMainQueue()
require(quantity.wrappedValue == 5, "stepper clamps external integer binding to its range")
require(nativeStepper?.doubleValue == 5, "stepper synchronizes its native value after clamping")
stepperField?.stringValue = "not-a-number"
if let stepperField, let delegate = stepperField.delegate {
    delegate.controlTextDidEndEditing?(Notification(name: NSControl.textDidEndEditingNotification, object: stepperField))
}
require(quantity.wrappedValue == 5, "stepper rejects invalid text and restores the current value")
nativeStepper?.doubleValue = 4
if let nativeStepper, let action = nativeStepper.action {
    require(NSApp.sendAction(action, to: nativeStepper.target, from: nativeStepper), "stepper sends its native increment action")
}
require(quantity.wrappedValue == 4, "stepper writes native changes through an integer binding")

let numberBoxQuantity = FluentState(wrappedValue: 3)
let numberBoxView = FluentNumberBox(
    "Items",
    value: numberBoxQuantity.projectedValue,
    in: 1...12,
    spinButtonPlacement: .inline
)._mount(in: FluentRenderContext(theme: sourceLightTheme))
guard let mountedNumberBox = firstNumberBox(in: numberBoxView) else {
    fatalError("declarative NumberBox did not mount")
}
require(
    mountedNumberBox.textField.usesSingleLineMode
        && mountedNumberBox.textField.maximumNumberOfLines == 1
        && mountedNumberBox.textField.cell?.wraps == false,
    "NumberBox editor inherits the shared single-line TextBox protocol"
)
let numberBoxWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
numberBoxView.frame = NSRect(
    x: 20,
    y: 20,
    width: 280,
    height: mountedNumberBox.intrinsicContentSize.height
)
numberBoxWindow.contentView = numberBoxView
numberBoxWindow.makeKeyAndOrderFront(nil)
numberBoxView.layoutSubtreeIfNeeded()
require(
    abs(mountedNumberBox.textField.frame.width - (mountedNumberBox.bounds.width - 72)) < 0.001
        && mountedNumberBox.incrementButton.frame.size == CGSize(width: 32, height: 24)
        && mountedNumberBox.decrementButton.frame.size == CGSize(width: 32, height: 24)
        && mountedNumberBox.decrementButton.frame.maxX == mountedNumberBox.incrementButton.frame.minX
        && mountedNumberBox.decrementButton.systemImageName == "chevron.down"
        && mountedNumberBox.incrementButton.systemImageName == "chevron.up",
    "NumberBox Inline uses the source 72pt column with visual decrement-left/increment-right buttons "
        + "(host: \(numberBoxView.frame), control: \(mountedNumberBox.frame), text: \(mountedNumberBox.textField.frame), "
        + "up: \(mountedNumberBox.incrementButton.frame), down: \(mountedNumberBox.decrementButton.frame))"
)
require(
    mountedNumberBox.incrementButton.systemImagePointSize == 12
        && mountedNumberBox.incrementButton.accessibilityPerformPress()
        && numberBoxQuantity.wrappedValue == 4,
    "NumberBox inline increment commits through its declarative integer binding"
)
require(
    mountedNumberBox.decrementButton.accessibilityPerformPress()
        && numberBoxQuantity.wrappedValue == 3,
    "NumberBox inline decrement commits through its declarative integer binding"
)
numberBoxQuantity.wrappedValue = 99
drainMainQueue()
require(
    numberBoxQuantity.wrappedValue == 12
        && mountedNumberBox.value == 12
        && !mountedNumberBox.incrementButton.isEnabled,
    "NumberBox normalizes an external binding and disables the increment button at Maximum"
)
mountedNumberBox.fluentLayoutDirection = .rightToLeft
mountedNumberBox.layoutSubtreeIfNeeded()
require(
    mountedNumberBox.decrementButton.frame.minX > mountedNumberBox.incrementButton.frame.minX
        && mountedNumberBox.textField.frame.minX == 72,
    "NumberBox mirrors the inline spin column and text content in RTL"
)
numberBoxWindow.orderOut(nil)

let floatingNumberBox = FluentNumberBoxControl(
    value: 2,
    range: 0...5,
    spinButtonPlacement: .hidden
)
floatingNumberBox.textField.stringValue = ""
floatingNumberBox.commitEditing()
require(
    floatingNumberBox.value.isNaN && floatingNumberBox.textField.stringValue.isEmpty,
    "NumberBox maps an empty TextBox to NaN like ValidateInput"
)
floatingNumberBox.value = 2
floatingNumberBox.textField.stringValue = "not-a-number"
floatingNumberBox.commitEditing()
require(
    floatingNumberBox.value == 2 && floatingNumberBox.textField.stringValue == "2",
    "InvalidInputOverwritten restores the formatted current NumberBox value"
)
floatingNumberBox.validationMode = .disabled
floatingNumberBox.textField.stringValue = "9"
floatingNumberBox.commitEditing()
require(
    floatingNumberBox.value == 9
        && floatingNumberBox.incrementButton.isEnabled
        && floatingNumberBox.decrementButton.isEnabled,
    "NumberBox ValidationMode disabled retains out-of-range values and both step directions"
)
floatingNumberBox.validationMode = .invalidInputOverwritten
floatingNumberBox.isWrapEnabled = true
floatingNumberBox.value = 5
require(
    floatingNumberBox.accessibilityPerformIncrement() && floatingNumberBox.value == 0,
    "NumberBox wraps Maximum to Minimum when IsWrapEnabled"
)

let compactNumberBox = FluentNumberBoxControl(
    value: 2,
    range: 0...5,
    spinButtonPlacement: .compact
)
compactNumberBox.theme = sourceDarkTheme
compactNumberBox.frame = NSRect(x: 20, y: 20, width: 220, height: 32)
let compactNumberBoxWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 280, height: 72),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
compactNumberBoxWindow.contentView = compactNumberBox
compactNumberBoxWindow.makeKeyAndOrderFront(nil)
compactNumberBox.layoutSubtreeIfNeeded()
let compactPopupIndicator = firstView(
    identifier: "FluentKit.NumberBox.PopupIndicator",
    in: compactNumberBox
)
require(
    compactNumberBox.incrementButton.isHidden
        && compactNumberBox.decrementButton.isHidden
        && compactPopupIndicator?.isHidden == false
        && compactNumberBox.textField.frame.width == compactNumberBox.bounds.width - 32,
    "NumberBox Compact reserves one 32pt indicator column and hides inline RepeatButtons "
        + "(control: \(compactNumberBox.frame), text: \(compactNumberBox.textField.frame), "
        + "upHidden: \(compactNumberBox.incrementButton.isHidden), downHidden: \(compactNumberBox.decrementButton.isHidden), "
        + "indicator: \(String(describing: compactPopupIndicator?.frame)))"
)
_ = compactNumberBoxWindow.makeFirstResponder(compactNumberBox.textField)
compactNumberBox.textField.selectText(nil)
compactNumberBox.controlTextDidBeginEditing(
    Notification(name: NSControl.textDidBeginEditingNotification, object: compactNumberBox.textField)
)
require(
    waitUntil(timeout: 0.20) { compactNumberBoxWindow.childWindows?.count == 1 },
    "NumberBox Compact opens its spin-button popup when the InputBox receives focus"
)
guard let compactPanel = compactNumberBoxWindow.childWindows?.first,
      let compactPopupContent = compactPanel.contentView,
      let compactIncrement = firstView(
        identifier: "FluentKit.NumberBox.PopupIncrement",
        in: compactPopupContent
      ) as? FluentRepeatButton,
      let compactDecrement = firstView(
        identifier: "FluentKit.NumberBox.PopupDecrement",
        in: compactPopupContent
      ) as? FluentRepeatButton else {
    fatalError("NumberBox Compact popup hierarchy did not mount")
}
require(
    compactPanel.frame.size == CGSize(width: 48, height: 88)
        && !compactPanel.hasShadow
        && compactPopupContent.layer?.borderWidth == 1
        && compactIncrement.frame == NSRect(x: 6, y: 6, width: 36, height: 36)
        && compactDecrement.frame == NSRect(x: 6, y: 46, width: 36, height: 36)
        && compactIncrement.systemImagePointSize == 16,
    "NumberBox Compact popup uses the source 6pt padding, 36pt buttons, 4pt gap, and one opaque edge "
        + "(panel: \(compactPanel.frame), border: \(String(describing: compactPopupContent.layer?.borderWidth)), "
        + "up: \(compactIncrement.frame), down: \(compactDecrement.frame), icon: \(String(describing: compactIncrement.systemImagePointSize)))"
)
require(
    compactIncrement.accessibilityPerformPress() && compactNumberBox.value == 3,
    "NumberBox Compact popup RepeatButton increments without moving text focus"
)
compactNumberBox.controlTextDidEndEditing(
    Notification(name: NSControl.textDidEndEditingNotification, object: compactNumberBox.textField)
)
require(
    compactNumberBoxWindow.childWindows?.isEmpty != false,
    "NumberBox Compact removes its popup immediately when editing focus ends"
)
compactNumberBoxWindow.orderOut(nil)

let smallButton = FluentButtonView("Small", role: .primary).controlSize(.small)._mount(in: FluentRenderContext())
let largeButton = FluentButtonView("Large", role: .destructive).controlSize(.large)._mount(in: FluentRenderContext())
let smallNativeButton = firstButton(in: smallButton)
let largeNativeButton = firstButton(in: largeButton)
require(smallNativeButton?.role == .primary, "button view preserves its primary role")
require(largeNativeButton?.role == .destructive, "button view preserves its destructive role")
require(smallNativeButton?.fluentControlSize == .small, "controlSize modifier applies small metrics to native controls")
require(largeNativeButton?.fluentControlSize == .large, "controlSize modifier applies large metrics to native controls")

let formValue = FluentState(wrappedValue: "")
let formField = FluentFormField(
    "Display name",
    help: "Shown to collaborators",
    validation: .error("A name is required"),
    required: true
) {
    FluentTextFieldView(text: formValue.projectedValue, placeholder: "Name")
}
let formFieldView = formField._mount(in: FluentRenderContext())
let formLabels = labels(in: formFieldView).map(\.stringValue)
require(formLabels.contains("Display name *"), "form field renders its required title")
require(formLabels.contains("A name is required"), "form field renders validation feedback")
require(formFieldView.accessibilityRole() == NSAccessibility.Role.group, "form field exposes group accessibility semantics")
require(formFieldView.accessibilityValue() as? String == "Invalid", "form field exposes validation state to accessibility")
let validFormField = FluentFormField(
    "Display name",
    validation: .success("Looks good"),
    required: true
) { FluentTextFieldView(text: formValue.projectedValue, placeholder: "Name") }
require(validFormField._update(formFieldView, in: FluentRenderContext()), "form field updates validation state in place")
require(formFieldView.accessibilityValue() as? String == "Valid", "form field refreshes accessibility validation state")

var defaultActionCount = 0
var cancelActionCount = 0
var defaultEnabled = true
let keyboardView = FluentText("Keyboard actions")
    .fluentDefaultAction(isEnabled: { defaultEnabled }) { defaultActionCount += 1 }
    .fluentCancelAction { cancelActionCount += 1 }
    ._mount(in: FluentRenderContext())
if let returnEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
    require(keyboardView.performKeyEquivalent(with: returnEvent), "default keyboard action consumes Return")
}
if let escapeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
    require(keyboardView.performKeyEquivalent(with: escapeEvent), "cancel keyboard action consumes Escape")
}
require(defaultActionCount == 1 && cancelActionCount == 1, "keyboard actions invoke their callbacks")
defaultEnabled = false
if let returnEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
    require(!keyboardView.performKeyEquivalent(with: returnEvent), "disabled default keyboard action passes through")
}

let selectedID = FluentState<String?>(wrappedValue: "General")
let listRows = [FluentText("General"), FluentText("Privacy"), FluentText("About")]
let listHost = FluentViewHost(FluentList(rows: listRows, id: { $0.value }, selectionID: selectedID.projectedValue))
let listMotionWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
listMotionWindow.contentView = listHost
listMotionWindow.orderFront(nil)
listHost.layoutSubtreeIfNeeded()
let listSelectionIndicator = firstLayer(named: "FluentKit.List.SelectionIndicator", in: listHost)
let previousListSelectionIndicator = firstLayer(named: "FluentKit.List.PreviousSelectionIndicator", in: listHost)
require(listSelectionIndicator?.opacity == 1, "single-selection list exposes one shared selection indicator")
require(previousListSelectionIndicator?.opacity == 0, "single-selection list keeps its outgoing indicator hidden at rest")
require(
    listSelectionIndicator?.frame.size == NSSize(width: 3, height: 16)
        && listSelectionIndicator?.cornerRadius == 2,
    "list selection indicator uses the NavigationView 3 x 16 geometry"
)
let listCollection = listSelectionIndicator?.superlayer?.delegate as? NSCollectionView
let initiallySelectedListRow = listCollection?.item(at: IndexPath(item: 0, section: 0))?.view
require(
    listSelectionIndicator.map { indicator in
        initiallySelectedListRow.map { abs(indicator.frame.midY - $0.frame.midY) < 0.5 } == true
    } == true,
    "single-selection list indicator aligns with the selected row geometry"
)
if let firstHoverRow = listCollection?.item(at: IndexPath(item: 1, section: 0))?.view,
   let secondHoverRow = listCollection?.item(at: IndexPath(item: 2, section: 0))?.view {
    firstHoverRow.updateTrackingAreas()
    firstHoverRow.updateTrackingAreas()
    secondHoverRow.updateTrackingAreas()
    secondHoverRow.updateTrackingAreas()
    require(
        firstHoverRow.trackingAreas.count == 1 && secondHoverRow.trackingAreas.count == 1,
        "FluentList rows keep one visible-rect tracking area across repeated layout updates"
    )
    let firstRestingAlpha = renderedBackgroundAlpha(in: firstHoverRow)
    let secondRestingAlpha = renderedBackgroundAlpha(in: secondHoverRow)
    firstHoverRow.mouseEntered(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: 12, y: firstHoverRow.bounds.midY),
            in: firstHoverRow,
            eventNumber: 85
        )
    )
    let firstHoverAlpha = renderedBackgroundAlpha(in: firstHoverRow)
    secondHoverRow.mouseEntered(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: 12, y: secondHoverRow.bounds.midY),
            in: secondHoverRow,
            eventNumber: 86
        )
    )
    require(
        firstHoverAlpha > firstRestingAlpha + 0.01
            && abs(renderedBackgroundAlpha(in: firstHoverRow) - firstRestingAlpha) < 0.01
            && renderedBackgroundAlpha(in: secondHoverRow) > secondRestingAlpha + 0.01,
        "FluentList owns one PointerOver row and clears the previous reusable row immediately"
    )
    secondHoverRow.mouseExited(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: -1, y: -1),
            in: secondHoverRow,
            eventNumber: 87
        )
    )
}
let rtlListHost = FluentViewHost(
    FluentList(rows: listRows, id: { $0.value }, selectionID: selectedID.projectedValue),
    context: FluentRenderContext(layoutDirection: .rightToLeft)
)
let rtlListWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
rtlListWindow.contentView = rtlListHost
rtlListWindow.orderFront(nil)
rtlListHost.layoutSubtreeIfNeeded()
let rtlListSelectionIndicator = firstLayer(named: "FluentKit.List.SelectionIndicator", in: rtlListHost)
let rtlListCollection = rtlListSelectionIndicator?.superlayer?.delegate as? NSCollectionView
require(
    rtlListSelectionIndicator.map { $0.frame.minX > (rtlListCollection?.bounds.midX ?? 0) } == true,
    "right-to-left list places the shared selection indicator on the leading edge"
)
let reducedListSelection = FluentState<String?>(wrappedValue: "General")
let reducedListHost = FluentViewHost(
    FluentList(rows: listRows, id: { $0.value }, selectionID: reducedListSelection.projectedValue),
    context: FluentRenderContext(reduceMotion: true)
)
let reducedListWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
reducedListWindow.contentView = reducedListHost
reducedListHost.frame = NSRect(x: 0, y: 0, width: 260, height: 180)
reducedListWindow.orderFront(nil)
reducedListHost.layoutSubtreeIfNeeded()
drainMainQueue()
reducedListSelection.wrappedValue = "Privacy"
drainMainQueue()
let reducedListIndicatorAfterSelection = firstLayer(
    named: "FluentKit.List.SelectionIndicator",
    in: reducedListHost
)
let reducedPreviousListIndicatorAfterSelection = firstLayer(
    named: "FluentKit.List.PreviousSelectionIndicator",
    in: reducedListHost
)
let reducedListCollection = reducedListIndicatorAfterSelection?.superlayer?.delegate as? NSCollectionView
let reducedSelectedRow = reducedListCollection?.item(at: IndexPath(item: 1, section: 0))?.view
let reducedIndicatorCenter = reducedListIndicatorAfterSelection?.frame.midY
let reducedRowCenter = reducedSelectedRow?.frame.midY
require(
    reducedListIndicatorAfterSelection?.animation(forKey: "fluent.navigation.selection") == nil
        && reducedPreviousListIndicatorAfterSelection?.animation(forKey: "fluent.navigation.selection.outgoing") == nil,
    "Reduce Motion snaps both navigation indicators without allocating animations"
)
require(
    reducedIndicatorCenter.map { indicator in
        reducedRowCenter.map { abs(indicator - $0) < 0.5 } == true
    } == true,
    "Reduce Motion preserves final navigation indicator alignment (indicator: \(String(describing: reducedIndicatorCenter)), row: \(String(describing: reducedRowCenter)), collection: \(String(describing: reducedListCollection?.bounds)), selected: \(String(describing: reducedListCollection?.selectionIndexPaths)))"
)
selectedID.wrappedValue = "Privacy"
drainMainQueue()
let downwardIncomingGroup = listSelectionIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
require(
    downwardIncomingGroup != nil
        && previousListSelectionIndicator?.animation(forKey: "fluent.navigation.selection.outgoing") == nil,
    "stable-ID list selection animates one continuous navigation indicator"
)
require(
    downwardIncomingGroup?.duration == FluentMotion.navigationIndicator.duration,
    "navigation indicator uses the 600ms motion token"
)
let downwardPosition = keyframeAnimation(for: "position", in: downwardIncomingGroup)
let downwardBounds = keyframeAnimation(for: "bounds.size", in: downwardIncomingGroup)
let downwardStart = (downwardPosition?.values?.first as? NSValue)?.pointValue.y
let downwardConnected = (downwardPosition?.values?[1] as? NSValue)?.pointValue.y
let downwardEnd = (downwardPosition?.values?.last as? NSValue)?.pointValue.y
require(
    downwardPosition?.values?.count == 3
        && downwardPosition?.keyTimes == [0, NSNumber(value: 1.0 / 3.0), 1]
        && downwardStart.map { start in
            downwardConnected.map { connected in
                downwardEnd.map { start < connected && connected < $0 } == true
            } == true
        } == true,
    "navigation indicator moves continuously through the connected midpoint"
)
require(
    downwardBounds?.values?.count == 3
        && ((downwardBounds?.values?[1] as? NSValue)?.sizeValue.height ?? 0)
            > ((downwardBounds?.values?.last as? NSValue)?.sizeValue.height ?? 0),
    "navigation indicator stretches and settles on the same moving layer"
)
selectedID.wrappedValue = "General"
drainMainQueue()
let upwardIncomingGroup = listSelectionIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
let upwardPosition = keyframeAnimation(for: "position", in: upwardIncomingGroup)
let upwardStart = (upwardPosition?.values?.first as? NSValue)?.pointValue.y
let upwardConnected = (upwardPosition?.values?[1] as? NSValue)?.pointValue.y
let upwardEnd = (upwardPosition?.values?.last as? NSValue)?.pointValue.y
require(
    upwardPosition?.values?.count == 3
        && upwardStart.map { start in
            upwardConnected.map { connected in
                upwardEnd.map { start > connected && connected > $0 } == true
            } == true
        } == true,
    "upward navigation indicator follows the same continuous midpoint path"
)

selectedID.wrappedValue = "Privacy"
drainMainQueue()
selectedID.wrappedValue = "About"
drainMainQueue()
let currentRapidIndicator = firstLayer(named: "FluentKit.List.SelectionIndicator", in: listHost)
let rapidlyUpdatedIndicator = currentRapidIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
let rapidPosition = keyframeAnimation(for: "position", in: rapidlyUpdatedIndicator)
let rapidEnd = (rapidPosition?.values?.last as? NSValue)?.pointValue.y
let currentRapidCollection = currentRapidIndicator?.superlayer?.delegate as? NSCollectionView
let aboutRow = currentRapidCollection?.item(at: IndexPath(item: 2, section: 0))?.view
require(
    rapidEnd.map { end in
        aboutRow.map { abs(end - $0.frame.midY) < 0.5 } == true
    } == true,
    "rapid navigation changes restart toward the latest requested row (end: \(String(describing: rapidEnd)), row: \(String(describing: aboutRow?.frame.midY)), values: \(String(describing: rapidPosition?.values)), indicator: \(String(describing: currentRapidIndicator?.frame)))"
)
selectedID.wrappedValue = "General"
drainMainQueue()
let insertedRows = [FluentText("General"), FluentText("Privacy"), FluentText("About"), FluentText("Updates")]
listHost.update(FluentList(rows: insertedRows, id: { $0.value }, selectionID: selectedID.projectedValue))
drainMainQueue()
require(selectedID.wrappedValue == "General", "stable-ID list selection survives insertion")
let removedUnselectedRows = [FluentText("General"), FluentText("About"), FluentText("Updates")]
listHost.update(FluentList(rows: removedUnselectedRows, id: { $0.value }, selectionID: selectedID.projectedValue))
drainMainQueue()
require(selectedID.wrappedValue == "General", "stable-ID list selection survives removing another row")
let reorderedRows = [FluentText("About"), FluentText("General"), FluentText("Privacy")]
listHost.update(FluentList(rows: reorderedRows, id: { $0.value }, selectionID: selectedID.projectedValue))
drainMainQueue()
require(selectedID.wrappedValue == "General", "stable-ID list selection survives reordering")
let deletedSelectedRows = [FluentText("About"), FluentText("Privacy")]
listHost.update(FluentList(rows: deletedSelectedRows, id: { $0.value }, selectionID: selectedID.projectedValue))
drainMainQueue()
require(selectedID.wrappedValue == nil, "stable-ID list clears selection when selected row is removed")
let duplicateIDRows = [FluentText("Duplicate"), FluentText("Duplicate")]
listHost.update(FluentList(rows: duplicateIDRows, id: { $0.value }, selectionID: selectedID.projectedValue))
drainMainQueue()
require(selectedID.wrappedValue == nil, "duplicate row IDs fall back without inventing a selection")
listMotionWindow.orderOut(nil)
rtlListWindow.orderOut(nil)

let multipleSelection = FluentState(wrappedValue: Set(["General", "Privacy"]))
let multipleRows = [FluentText("General"), FluentText("Privacy"), FluentText("About")]
let multipleList = FluentList(
    rows: multipleRows,
    id: { $0.value },
    selectionIDs: multipleSelection.projectedValue
)
let multipleListView = multipleList._mount(in: FluentRenderContext())
multipleListView.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
multipleListView.layoutSubtreeIfNeeded()
drainMainQueue()
func firstCollectionView(in view: NSView) -> NSCollectionView? {
    if let collection = view as? NSCollectionView { return collection }
    return view.subviews.lazy.compactMap(firstCollectionView).first
}
require(firstCollectionView(in: multipleListView)?.selectionIndexPaths.count == 2, "multi-select list applies all selected IDs to its native collection")
let reorderedMultipleRows = [FluentText("About"), FluentText("Privacy"), FluentText("General")]
let reorderedMultipleList = FluentList(
    rows: reorderedMultipleRows,
    id: { $0.value },
    selectionIDs: multipleSelection.projectedValue
)
require(reorderedMultipleList._update(multipleListView, in: FluentRenderContext()), "multi-select list updates compatible data in place")
drainMainQueue()
require(multipleSelection.wrappedValue == Set(["General", "Privacy"]), "multi-select list preserves selection IDs through reordering")
let reducedMultipleRows = [FluentText("About"), FluentText("General")]
let reducedMultipleList = FluentList(
    rows: reducedMultipleRows,
    id: { $0.value },
    selectionIDs: multipleSelection.projectedValue
)
require(reducedMultipleList._update(multipleListView, in: FluentRenderContext()), "multi-select list accepts row deletion in place")
drainMainQueue()
require(multipleSelection.wrappedValue == Set(["General"]), "multi-select list removes selection IDs deleted from the data")

let moveToEnd = FluentListMoveIntent(sourceIndexes: IndexSet([1, 2]), destination: 5)
require(
    moveToEnd.applying(to: ["A", "B", "C", "D", "E"]) == ["A", "D", "E", "B", "C"],
    "list move intent keeps source order when moving multiple rows to the end"
)
let moveTowardStart = FluentListMoveIntent(sourceIndexes: IndexSet(integer: 3), destination: 1)
require(
    moveTowardStart.applying(to: ["A", "B", "C", "D", "E"]) == ["A", "D", "B", "C", "E"],
    "list move intent uses pre-removal insertion offsets when moving toward the start"
)

var collectionSnapshot = FluentCollectionSnapshot<String, Int>()
collectionSnapshot.appendSections(["primary", "archive"])
collectionSnapshot.appendItems([1, 2, 3], toSection: "primary")
collectionSnapshot.appendItems([4], toSection: "archive")
require(collectionSnapshot.sectionIdentifiers == ["primary", "archive"], "collection snapshot preserves section ordering")
require(collectionSnapshot.itemIdentifiers == [1, 2, 3, 4], "collection snapshot flattens item ordering deterministically")
collectionSnapshot.moveItem(2, after: 4)
require(collectionSnapshot.itemIdentifiers(inSection: "primary") == [1, 3], "collection snapshot removes a cross-section moved item")
require(collectionSnapshot.itemIdentifiers(inSection: "archive") == [4, 2], "collection snapshot inserts a cross-section moved item")
collectionSnapshot.insertItems([5], before: 4)
collectionSnapshot.deleteItems([1])
require(collectionSnapshot.itemIdentifiers == [3, 5, 4, 2], "collection snapshot supports stable insertion and deletion")
var updatedCollectionSnapshot = collectionSnapshot
updatedCollectionSnapshot.moveSection("archive", before: "primary")
updatedCollectionSnapshot.moveItem(2, before: 5)
let sectionDifference = updatedCollectionSnapshot.sectionDifference(from: collectionSnapshot)
let itemDifference = updatedCollectionSnapshot.itemDifference(from: collectionSnapshot, inSection: "archive")
require(!sectionDifference.isEmpty, "collection snapshot reports section moves")
require(!itemDifference.isEmpty, "collection snapshot reports item moves")

struct ValidationTableRow: Equatable {
    let id: Int
    let name: String
    let status: String
}
let tableSelection = FluentState<Int?>(wrappedValue: 2)
let tableRows = [
    ValidationTableRow(id: 1, name: "Alpha", status: "Ready"),
    ValidationTableRow(id: 2, name: "Beta", status: "Running"),
    ValidationTableRow(id: 3, name: "Gamma", status: "Paused")
]
let validationTable = FluentTable(
    rows: tableRows,
    id: { $0.id },
    selectionID: tableSelection.projectedValue
) {
    FluentTableColumn("name", title: "Name", width: 160) { row in
        FluentText(row.name)
    }
    FluentTableColumn("status", title: "Status", width: 120) { row in
        FluentText(row.status)
    }
}
let validationTableView = validationTable._mount(in: FluentRenderContext())
validationTableView.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
validationTableView.layoutSubtreeIfNeeded()
func firstTableView(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    return view.subviews.lazy.compactMap(firstTableView).first
}
let nativeTable = firstTableView(in: validationTableView)
require(nativeTable?.numberOfColumns == 2, "table mounts every declarative column")
require(nativeTable?.numberOfRows == 3, "table diffable data source exposes every row")
require(nativeTable?.selectedRow == 1, "table resolves stable single selection to the native row index")
let reorderedTableRows = [tableRows[2], tableRows[0], tableRows[1]]
let reorderedTable = FluentTable(
    rows: reorderedTableRows,
    id: { $0.id },
    selectionID: tableSelection.projectedValue
) {
    FluentTableColumn("name", title: "Name", width: 160) { row in FluentText(row.name) }
    FluentTableColumn("status", title: "State", width: 120) { row in FluentText(row.status) }
}
require(reorderedTable._update(validationTableView, in: FluentRenderContext()), "table updates compatible row data in place")
drainMainQueue()
require(tableSelection.wrappedValue == 2, "table preserves stable selection through row reordering")
require(nativeTable?.selectedRow == 2, "table remaps native selection after row reordering")

let tableSelections = FluentState(wrappedValue: Set([1, 3]))
let multiTable = FluentTable(
    rows: tableRows,
    id: { $0.id },
    selectionIDs: tableSelections.projectedValue
) {
    FluentTableColumn("name", title: "Name") { row in FluentText(row.name) }
}
let multiTableView = multiTable._mount(in: FluentRenderContext())
multiTableView.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
multiTableView.layoutSubtreeIfNeeded()
require(firstTableView(in: multiTableView)?.selectedRowIndexes.count == 2, "table applies stable multi-selection to NSTableView")
let reducedTableRows = [tableRows[0], tableRows[1]]
let reducedTable = FluentTable(
    rows: reducedTableRows,
    id: { $0.id },
    selectionIDs: tableSelections.projectedValue
) {
    FluentTableColumn("name", title: "Name") { row in FluentText(row.name) }
}
require(reducedTable._update(multiTableView, in: FluentRenderContext()), "table accepts stable row deletion in place")
drainMainQueue()
require(tableSelections.wrappedValue == Set([1]), "table removes deleted IDs from multi-selection")

let outlineSelection = FluentState<String?>(wrappedValue: "alpha")
let outlineNodes = [
    FluentOutlineNode(id: "projects", children: [
        FluentOutlineNode(id: "alpha") { FluentText("Alpha") },
        FluentOutlineNode(id: "beta") { FluentText("Beta") }
    ]) { FluentText("Projects") },
    FluentOutlineNode(id: "archive", children: [
        FluentOutlineNode(id: "history") { FluentText("History") }
    ]) { FluentText("Archive") }
]
let validationOutline = FluentOutline(nodes: outlineNodes, selectionID: outlineSelection.projectedValue)
let validationOutlineView = validationOutline._mount(in: FluentRenderContext())
validationOutlineView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
validationOutlineView.layoutSubtreeIfNeeded()
func firstOutlineView(in view: NSView) -> NSOutlineView? {
    if let outline = view as? NSOutlineView { return outline }
    return view.subviews.lazy.compactMap(firstOutlineView).first
}
let nativeOutline = firstOutlineView(in: validationOutlineView)
require(nativeOutline?.numberOfRows == 4, "outline exposes roots and automatically expands ancestors of the selected child")
require(nativeOutline?.selectedRow == 1, "outline maps a stable child ID to its native row")
if let archiveItem = nativeOutline?.item(atRow: 3) {
    nativeOutline?.expandItem(archiveItem)
}
require(nativeOutline?.numberOfRows == 5, "outline expands native hierarchy rows")
let reorderedOutlineNodes = [
    FluentOutlineNode(id: "projects", children: [
        FluentOutlineNode(id: "beta") { FluentText("Beta updated") },
        FluentOutlineNode(id: "alpha") { FluentText("Alpha updated") }
    ]) { FluentText("Projects") },
    FluentOutlineNode(id: "archive", children: [
        FluentOutlineNode(id: "history") { FluentText("History updated") }
    ]) { FluentText("Archive") }
]
let reorderedOutline = FluentOutline(nodes: reorderedOutlineNodes, selectionID: outlineSelection.projectedValue)
require(reorderedOutline._update(validationOutlineView, in: FluentRenderContext()), "outline updates a compatible hierarchy in place")
require(nativeOutline?.numberOfRows == 5, "outline preserves expanded node IDs across hierarchy updates")
require(nativeOutline?.selectedRow == 2, "outline remaps stable selection after sibling reordering")
let reducedOutlineNodes = [
    FluentOutlineNode(id: "projects", children: [
        FluentOutlineNode(id: "beta") { FluentText("Beta") }
    ]) { FluentText("Projects") },
    FluentOutlineNode(id: "archive") { FluentText("Archive") }
]
let reducedOutline = FluentOutline(nodes: reducedOutlineNodes, selectionID: outlineSelection.projectedValue)
require(reducedOutline._update(validationOutlineView, in: FluentRenderContext()), "outline accepts stable node deletion in place")
require(outlineSelection.wrappedValue == nil, "outline clears selection when the selected node is deleted")

let collectionItemStyle = FluentAutomaticCollectionItemStyle()
let collectionTheme = FluentTheme.custom(colorScheme: .light)
let listNormalAppearance = collectionItemStyle.appearance(
    for: FluentCollectionItemStyleConfiguration(
        layoutKind: .list,
        theme: collectionTheme
    )
)
let listSelectedAppearance = collectionItemStyle.appearance(
    for: FluentCollectionItemStyleConfiguration(
        layoutKind: .list,
        isSelected: true,
        theme: collectionTheme
    )
)
let listSelectedPressedAppearance = collectionItemStyle.appearance(
    for: FluentCollectionItemStyleConfiguration(
        layoutKind: .list,
        controlState: .pressed,
        isSelected: true,
        theme: collectionTheme
    )
)
let gridSelectedAppearance = collectionItemStyle.appearance(
    for: FluentCollectionItemStyleConfiguration(
        layoutKind: .adaptiveGrid,
        isSelected: true,
        theme: collectionTheme
    )
)
let disabledListAppearance = collectionItemStyle.appearance(
    for: FluentCollectionItemStyleConfiguration(
        layoutKind: .list,
        isEnabled: false,
        theme: collectionTheme
    )
)
require(
    colorMatches(listNormalAppearance.backgroundColor.cgColor, .clear)
        && listNormalAppearance.contentInsets.left == 16
        && listNormalAppearance.contentInsets.right == 12
        && listNormalAppearance.cornerRadius == 4,
    "ListViewItem style maps transparent normal fill, 16/12 padding, and 4pt corners"
)
require(
    colorMatches(listSelectedAppearance.backgroundColor.cgColor, collectionTheme.subtleFillSecondary)
        && listSelectedAppearance.selectionIndicatorSize == NSSize(width: 3, height: 16)
        && listSelectedAppearance.selectionIndicatorLeadingMargin == 4,
    "ListViewItem selected state maps its subtle fill and 3x16 leading indicator"
)
require(
    colorMatches(listSelectedPressedAppearance.backgroundColor.cgColor, collectionTheme.subtleFillSecondary)
        && abs(listSelectedPressedAppearance.selectionIndicatorPressedScale - 0.625) < 0.001,
    "ListViewItem pressed-selected state compresses the indicator from 16pt to 10pt"
)
require(
    colorMatches(gridSelectedAppearance.backgroundColor.cgColor, collectionTheme.subtleFillTertiary)
        && gridSelectedAppearance.outerBorderWidth == 2
        && gridSelectedAppearance.innerBorderWidth == 1
        && colorMatches(gridSelectedAppearance.outerBorderColor.cgColor, collectionTheme.accentFillDefault)
        && colorMatches(gridSelectedAppearance.innerBorderColor.cgColor, collectionTheme.controlSolidFill),
    "GridViewItem selected state uses a 2pt accent edge and 1pt solid inner edge"
)
require(
    disabledListAppearance.contentOpacity == 0.3,
    "collection item disabled content uses the source 0.3 opacity"
)

var sectionedSnapshot = FluentCollectionSnapshot<String, Int>()
sectionedSnapshot.appendSections(["active", "recent"])
sectionedSnapshot.appendItems([1, 2, 3], toSection: "active")
sectionedSnapshot.appendItems([4, 5], toSection: "recent")
let collectionSelections = FluentState(wrappedValue: Set([2, 5]))
let sectionedCollection = FluentCollection(
    snapshot: sectionedSnapshot,
    layout: .adaptiveGrid(minimumItemWidth: 120, itemHeight: 72, spacing: 8),
    selectionIDs: collectionSelections.projectedValue,
    isEnabled: { $0 != 4 }
) { item in
    FluentText("Item \(item)")
} header: { section in
    FluentText(section.capitalized, weight: .semibold)
}
let sectionedCollectionView = sectionedCollection._mount(in: FluentRenderContext(theme: collectionTheme))
sectionedCollectionView.frame = NSRect(x: 0, y: 0, width: 420, height: 260)
sectionedCollectionView.layoutSubtreeIfNeeded()
drainMainQueue()
let nativeSectionedCollection = firstCollectionView(in: sectionedCollectionView)
require(nativeSectionedCollection?.numberOfSections == 2, "sectioned collection mounts every snapshot section")
require(nativeSectionedCollection?.numberOfItems(inSection: 0) == 3, "sectioned collection mounts items in their declared section")
require(nativeSectionedCollection?.selectionIndexPaths.count == 2, "sectioned collection applies stable multi-selection")
require(
    nativeSectionedCollection?.focusRingType == NSFocusRingType.none,
    "collection suppresses duplicate AppKit focus chrome"
)
let sectionedFlowLayout = nativeSectionedCollection?.collectionViewLayout as? NSCollectionViewFlowLayout
require(sectionedFlowLayout?.headerReferenceSize.height == 34, "sectioned collection reserves native supplementary header space")
require((sectionedFlowLayout?.itemSize.width ?? 0) >= 120, "adaptive grid resolves a usable native item width")
require(
    abs((sectionedFlowLayout?.headerReferenceSize.width ?? 0) - 416) <= 1,
    "collection supplementary headers resolve against the current viewport width"
)
let visibleSectionedLabels = nativeSectionedCollection?.visibleItems().flatMap { labels(in: $0.view) } ?? []
require(
    visibleSectionedLabels.contains { $0.stringValue == "Item 1" },
    "sectioned collection mounts declarative content in visible cells"
)
require(
    visibleSectionedLabels.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 },
    "sectioned collection lays out visible declarative cell content"
)
if let selectedGridItem = nativeSectionedCollection?.item(at: IndexPath(item: 1, section: 0)),
   let gridSurface = firstLayer(named: "FluentKit.CollectionItem.Surface", in: selectedGridItem.view),
   let gridOuterBorder = firstLayer(named: "FluentKit.CollectionItem.GridOuterBorder", in: selectedGridItem.view) as? CAShapeLayer,
   let gridInnerBorder = firstLayer(named: "FluentKit.CollectionItem.GridInnerBorder", in: selectedGridItem.view) as? CAShapeLayer,
   let gridIndicator = firstLayer(named: "FluentKit.CollectionItem.SelectionIndicator", in: selectedGridItem.view) {
    require(
        colorMatches(gridSurface.backgroundColor, collectionTheme.subtleFillTertiary)
            && !gridOuterBorder.isHidden
            && !gridInnerBorder.isHidden
            && gridIndicator.isHidden
            && gridSurface.zPosition < 0
            && gridOuterBorder.zPosition > 0
            && gridInnerBorder.zPosition > gridOuterBorder.zPosition,
        "adaptive-grid cells keep selected GridViewItem chrome above content without a ListView pill"
    )
} else {
    fatalError("selected GridViewItem chrome did not mount")
}

var sizingSnapshot = FluentCollectionSnapshot<String, Int>()
sizingSnapshot.appendSections(["sizing"])
sizingSnapshot.appendItems(Array(0..<8), toSection: "sizing")
let sizingCollection = FluentCollection(
    snapshot: sizingSnapshot,
    layout: .adaptiveGrid(minimumItemWidth: 120, itemHeight: 112, spacing: 8)
) { item in
    FluentText("Sizing \(item)").frame(height: 96)
}
let sizingCollectionView = sizingCollection._mount(in: FluentRenderContext(theme: collectionTheme))
sizingCollectionView.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
sizingCollectionView.layoutSubtreeIfNeeded()
drainMainQueue()
guard let nativeSizingCollection = firstCollectionView(in: sizingCollectionView),
      let narrowFirstAttributes = nativeSizingCollection.collectionViewLayout?.layoutAttributesForItem(
        at: IndexPath(item: 0, section: 0)
      ),
      let narrowFourthAttributes = nativeSizingCollection.collectionViewLayout?.layoutAttributesForItem(
        at: IndexPath(item: 3, section: 0)
      ),
      let sizingItem = nativeSizingCollection.item(at: IndexPath(item: 0, section: 0)) else {
    fatalError("collection sizing validation did not resolve native layout attributes")
}
func descendantConstraints(in view: NSView) -> [NSLayoutConstraint] {
    view.constraints + view.subviews.flatMap(descendantConstraints)
}
let idealHeightConstraints = descendantConstraints(in: sizingItem.view).filter {
    $0.identifier == "FluentKit.IdealHeight"
}
require(
    abs(sizingItem.view.frame.height - 112) <= 0.5
        && idealHeightConstraints.contains {
            abs($0.constant - 96) <= 0.001 && $0.priority == .defaultHigh
        }
        && !idealHeightConstraints.contains { $0.priority == .required },
    "collection cell owns the 112pt item height while nested frame heights remain overridable ideals"
)
require(
    abs(narrowFirstAttributes.frame.minY - narrowFourthAttributes.frame.minY) > 1,
    "adaptive collection uses multiple rows at the narrow viewport"
)
sizingCollectionView.setFrameSize(NSSize(width: 720, height: 300))
sizingCollectionView.layoutSubtreeIfNeeded()
drainMainQueue()
guard let wideFirstAttributes = nativeSizingCollection.collectionViewLayout?.layoutAttributesForItem(
        at: IndexPath(item: 0, section: 0)
      ),
      let wideFourthAttributes = nativeSizingCollection.collectionViewLayout?.layoutAttributesForItem(
        at: IndexPath(item: 3, section: 0)
      ),
      let sizingFlowLayout = nativeSizingCollection.collectionViewLayout as? NSCollectionViewFlowLayout else {
    fatalError("resized collection did not produce updated layout attributes")
}
require(
    abs(wideFirstAttributes.frame.minY - wideFourthAttributes.frame.minY) <= 0.5
        && sizingFlowLayout.itemSize.width >= 120,
    "adaptive collection recomputes columns and item frames from the resized viewport"
)
if let disabledGridItem = nativeSectionedCollection?.item(at: IndexPath(item: 0, section: 1)) {
    require(
        disabledGridItem.view.isAccessibilityEnabled() == false
            && abs((disabledGridItem.view.subviews.first?.alphaValue ?? 1) - 0.3) < 0.001,
        "disabled collection items retain native accessibility state and source content opacity"
    )
}

var reducedSectionedSnapshot = sectionedSnapshot
reducedSectionedSnapshot.moveSection("recent", before: "active")
reducedSectionedSnapshot.deleteItems([2])
let updatedSectionedCollection = FluentCollection(
    snapshot: reducedSectionedSnapshot,
    layout: .adaptiveGrid(minimumItemWidth: 120, itemHeight: 72, spacing: 8),
    selectionIDs: collectionSelections.projectedValue
) { item in
    FluentText("Updated \(item)")
} header: { section in
    FluentText(section.uppercased(), weight: .semibold)
}
require(
    updatedSectionedCollection._update(sectionedCollectionView, in: FluentRenderContext()),
    "sectioned collection applies compatible diffable updates in place"
)
drainMainQueue()
require(collectionSelections.wrappedValue == Set([5]), "sectioned collection trims deleted IDs from multi-selection")
require(nativeSectionedCollection?.numberOfItems(inSection: 0) == 2, "section moves preserve each section's item membership")

var visualListSnapshot = FluentCollectionSnapshot<String, Int>()
visualListSnapshot.appendSections(["rows"])
visualListSnapshot.appendItems([10, 11, 12], toSection: "rows")
let visualListSelection = FluentState<Int?>(wrappedValue: 11)
let visualList = FluentCollection(
    snapshot: visualListSnapshot,
    layout: .list(),
    selectionID: visualListSelection.projectedValue,
    isEnabled: { $0 != 12 }
) { item in
    FluentText("Visual row \(item)")
}
let visualListHost = visualList._mount(in: FluentRenderContext(theme: collectionTheme))
let visualListWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
visualListWindow.contentView = visualListHost
visualListHost.frame = visualListWindow.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 320, height: 160)
visualListWindow.makeKeyAndOrderFront(nil)
visualListHost.layoutSubtreeIfNeeded()
drainMainQueue()
guard let nativeVisualList = firstCollectionView(in: visualListHost),
      let selectedListItem = nativeVisualList.item(at: IndexPath(item: 1, section: 0)),
      let selectedListSurface = firstLayer(named: "FluentKit.CollectionItem.Surface", in: selectedListItem.view),
      let selectedListIndicator = firstLayer(named: "FluentKit.CollectionItem.SelectionIndicator", in: selectedListItem.view),
      let listGridBorder = firstLayer(named: "FluentKit.CollectionItem.GridOuterBorder", in: selectedListItem.view) else {
    fatalError("selected ListViewItem chrome did not mount")
}
let visualListFlow = nativeVisualList.collectionViewLayout as? NSCollectionViewFlowLayout
selectedListItem.view.layoutSubtreeIfNeeded()
require(
    visualListFlow?.itemSize.height == 40
        && visualListFlow?.minimumLineSpacing == 0
        && colorMatches(selectedListSurface.backgroundColor, collectionTheme.subtleFillSecondary),
    "ListViewItem uses the source 40pt row and selected subtle surface"
)
require(
    abs(selectedListIndicator.frame.width - 3) < 0.001
        && abs(selectedListIndicator.frame.height - 16) < 0.001
        && abs(selectedListIndicator.frame.minX - 4) < 0.001
        && selectedListIndicator.opacity == 1
        && listGridBorder.isHidden,
    "ListViewItem owns a 3x16 leading pill and does not reuse GridView selection borders"
)
let selectedListContentAlignmentRect = selectedListItem.view.subviews.first.map {
    $0.alignmentRect(forFrame: $0.frame)
}
require(
    abs((selectedListContentAlignmentRect?.minX ?? 0) - 16) < 0.5,
    "ListViewItem content alignment rect begins at the source 16pt leading inset"
)
if let disabledListItem = nativeVisualList.item(at: IndexPath(item: 2, section: 0)) {
    require(
        disabledListItem.view.isAccessibilityEnabled() == false
            && abs((disabledListItem.view.subviews.first?.alphaValue ?? 1) - 0.3) < 0.001,
        "ListViewItem exposes disabled state without accepting pointer selection"
    )
}
visualListSelection.wrappedValue = 10
var capturedListOpacityAnimation: CABasicAnimation?
var capturedListScaleAnimation: CABasicAnimation?
var capturedListBackgroundAnimation: CABasicAnimation?
require(
    waitUntil(timeout: 0.12, pollInterval: 0.001) {
        guard let newlySelectedItem = nativeVisualList.item(at: IndexPath(item: 0, section: 0)),
              let animatedSurface = firstLayer(
                  named: "FluentKit.CollectionItem.Surface",
                  in: newlySelectedItem.view
              ),
              let animatedIndicator = firstLayer(
                  named: "FluentKit.CollectionItem.SelectionIndicator",
                  in: newlySelectedItem.view
              ) else { return false }
        capturedListBackgroundAnimation = animatedSurface.animation(
            forKey: "fluent.collectionItem.background"
        ) as? CABasicAnimation
        capturedListOpacityAnimation = animatedIndicator.animation(
            forKey: "fluent.collectionItem.indicator.opacity"
        ) as? CABasicAnimation
        capturedListScaleAnimation = animatedIndicator.animation(
            forKey: "fluent.collectionItem.indicator.scale"
        ) as? CABasicAnimation
        return capturedListBackgroundAnimation != nil
            && capturedListOpacityAnimation != nil
            && capturedListScaleAnimation != nil
    },
    "ListViewItem creates selection-indicator opacity and scale animations"
)
if let newlySelectedItem = nativeVisualList.item(at: IndexPath(item: 0, section: 0)),
   firstLayer(
       named: "FluentKit.CollectionItem.SelectionIndicator",
       in: newlySelectedItem.view
   ) != nil {
    require(
        capturedListOpacityAnimation?.duration == FluentMotion.controlFaster.duration
            && capturedListScaleAnimation?.duration == FluentMotion.collectionSelectionReveal.duration
            && capturedListBackgroundAnimation?.duration == FluentMotion.controlFaster.duration,
        "ListViewItem selection uses coordinated background, 83ms opacity, and 167ms scale animations"
    )
}
visualListSelection.wrappedValue = 11
drainMainQueue()
visualListSelection.wrappedValue = 10
drainMainQueue()
visualListSelection.wrappedValue = 11
drainMainQueue()
guard let interruptedSelectedItem = nativeVisualList.item(at: IndexPath(item: 1, section: 0)),
      let interruptedIndicator = firstLayer(
          named: "FluentKit.CollectionItem.SelectionIndicator",
          in: interruptedSelectedItem.view
      ) else {
    fatalError("interrupted ListViewItem selection did not retain its native cell")
}
require(
    interruptedIndicator.animation(forKey: "fluent.collectionItem.indicator.scale") != nil
        && nativeVisualList.selectionIndexPaths == Set([IndexPath(item: 1, section: 0)]),
    "ListViewItem selection interruption keeps one presentation-sampled scale animation and final target"
)
require(
    waitUntil(timeout: 0.50) {
        interruptedIndicator.animationKeys()?.isEmpty != false
            && interruptedIndicator.opacity == 1
    },
    "ListViewItem selection interruption commits the final pill state after the shared timeline"
)
visualListWindow.orderOut(nil)

let rtlVisualListSelection = FluentState<Int?>(wrappedValue: 10)
let rtlVisualList = FluentCollection(
    snapshot: visualListSnapshot,
    layout: .list(),
    selectionID: rtlVisualListSelection.projectedValue
) { item in
    FluentText("RTL row \(item)")
}
let rtlVisualListHost = rtlVisualList._mount(
    in: FluentRenderContext(theme: collectionTheme, layoutDirection: .rightToLeft)
)
rtlVisualListHost.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
rtlVisualListHost.layoutSubtreeIfNeeded()
drainMainQueue()
if let rtlCollection = firstCollectionView(in: rtlVisualListHost),
   let rtlItem = rtlCollection.item(at: IndexPath(item: 0, section: 0)),
   let rtlIndicator = firstLayer(named: "FluentKit.CollectionItem.SelectionIndicator", in: rtlItem.view) {
    require(
        abs(rtlIndicator.frame.maxX - (rtlItem.view.bounds.maxX - 4)) < 0.001,
        "RTL ListViewItem mirrors its selection indicator to the leading edge"
    )
}

let reducedCollectionSelection = FluentState<Int?>(wrappedValue: 10)
let reducedCollection = FluentCollection(
    snapshot: visualListSnapshot,
    layout: .list(),
    selectionID: reducedCollectionSelection.projectedValue
) { item in
    FluentText("Reduced row \(item)")
}
let reducedCollectionHost = reducedCollection._mount(
    in: FluentRenderContext(theme: collectionTheme, reduceMotion: true)
)
let reducedCollectionWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
reducedCollectionWindow.contentView = reducedCollectionHost
reducedCollectionHost.frame = reducedCollectionWindow.contentView?.bounds
    ?? NSRect(x: 0, y: 0, width: 320, height: 160)
reducedCollectionWindow.makeKeyAndOrderFront(nil)
reducedCollectionHost.layoutSubtreeIfNeeded()
drainMainQueue()
reducedCollectionSelection.wrappedValue = 11
drainMainQueue()
if let reducedNativeCollection = firstCollectionView(in: reducedCollectionHost),
   let reducedItem = reducedNativeCollection.item(at: IndexPath(item: 1, section: 0)),
   let reducedIndicator = firstLayer(
       named: "FluentKit.CollectionItem.SelectionIndicator",
       in: reducedItem.view
   ) {
    require(
        reducedIndicator.opacity == 1
            && reducedIndicator.animation(forKey: "fluent.collectionItem.indicator.opacity") == nil
            && reducedIndicator.animation(forKey: "fluent.collectionItem.indicator.scale") == nil
            && reducedItem.view.layer?.sublayers?.first(where: {
                $0.name == "FluentKit.CollectionItem.Surface"
            })?.animation(forKey: "fluent.collectionItem.background") == nil,
        "ListViewItem Reduce Motion snaps selection without allocating indicator animations"
    )
}
reducedCollectionWindow.orderOut(nil)

var largeSnapshot = FluentCollectionSnapshot<String, Int>()
largeSnapshot.appendSections(["large"])
largeSnapshot.appendItems(Array(0..<5_000), toSection: "large")
let benchmarkStart = Date.timeIntervalSinceReferenceDate
let largeCollectionView = FluentCollection(snapshot: largeSnapshot) { item in
    FluentText("Row \(item)")
}._mount(in: FluentRenderContext())
largeCollectionView.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
largeCollectionView.layoutSubtreeIfNeeded()
let benchmarkDuration = Date.timeIntervalSinceReferenceDate - benchmarkStart
let nativeLargeCollection = firstCollectionView(in: largeCollectionView)
require(nativeLargeCollection?.numberOfItems(inSection: 0) == 5_000, "large collection exposes its complete diffable snapshot")
require((nativeLargeCollection?.visibleItems().count ?? 5_000) < 5_000, "large collection virtualizes native item hosts")
require(benchmarkDuration < 10, "5,000-item collection benchmark completes within the smoke-test budget")

let focused = FluentState(wrappedValue: true)
let focusWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let focusButton = FluentButton(title: "Focusable")
let focusHost = FluentViewHost(focusButton.focused(focused.projectedValue))
focusWindow.contentView = focusHost
drainMainQueue()
require(focusWindow.firstResponder === focusButton, "focus binding requests focus for nested responder")
focusWindow.makeFirstResponder(nil)
drainMainQueue()
require(focused.wrappedValue == false, "focus binding reflects responder loss")

let initialFocusRoot = FluentVStack(spacing: 4) {
    FluentButton(title: "Initial focus")
    FluentButton(title: "Second focus")
}.fluentInitialFocus()
let initialFocusWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let initialFocusHost = FluentViewHost(initialFocusRoot)
initialFocusWindow.contentView = initialFocusHost
initialFocusWindow.makeKeyAndOrderFront(nil)
drainMainQueue()
let initialFocusButton = firstButton(in: initialFocusHost)
require(initialFocusWindow.firstResponder === initialFocusButton, "initial focus requests the first focusable native descendant")
let existingResponder = FluentButton(title: "Existing responder")
let existingRoot = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
existingRoot.addSubview(existingResponder)
existingResponder.frame = NSRect(x: 12, y: 12, width: 180, height: 32)
let existingResponderWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
existingResponderWindow.contentView = existingRoot
existingResponderWindow.makeKeyAndOrderFront(nil)
_ = existingResponderWindow.makeFirstResponder(existingResponder)
let conservativeInitialFocus = FluentViewHost(FluentButton(title: "Do not steal").fluentInitialFocus())
existingRoot.addSubview(conservativeInitialFocus)
conservativeInitialFocus.frame = existingResponderWindow.contentView?.bounds ?? .zero
drainMainQueue()
require(existingResponderWindow.firstResponder === existingResponder, "initial focus does not displace an existing responder")

let focusScopeRoot = FluentHStack(spacing: 8) {
    FluentButton(title: "Scope one")
    FluentButton(title: "Scope two")
}.fluentFocusScope()
let focusScopeHost = focusScopeRoot._mount(in: FluentRenderContext())
let scopeButtons = focusScopeHost.subviews
    .flatMap { subview in
        var buttons: [FluentButton] = []
        func collect(_ view: NSView) {
            if let button = view as? FluentButton { buttons.append(button) }
            view.subviews.forEach(collect)
        }
        collect(subview)
        return buttons
    }
require(scopeButtons.count == 2, "focus scope exposes all focusable native descendants")
require(scopeButtons[0].nextKeyView === scopeButtons[1], "focus scope links the first key view to the second")
require(scopeButtons[1].nextKeyView === scopeButtons[0], "focus scope closes the key-view loop")

let restorationDefaults = UserDefaults(suiteName: "FluentKitValidation.\(UUID().uuidString)")!
let restorationStore = FluentRestorationStore(defaults: restorationDefaults, namespace: "validation")
require(restorationStore.value(forKey: "missing", as: Int.self) == nil, "restoration store treats missing values as absent")
require(restorationStore.set(42, forKey: "answer"), "restoration store encodes Codable values")
require(restorationStore.value(forKey: "answer", as: Int.self) == 42, "restoration store decodes Codable values")
let restoredCounter = FluentRestoredState<Int>(wrappedValue: 3, "counter", store: restorationStore)
require(restoredCounter.wrappedValue == 3, "restored state uses its declared initial value")
restoredCounter.wrappedValue = 9
require(restorationStore.value(forKey: "counter", as: Int.self) == 9, "restored state persists mutations")
let reloadedCounter = FluentRestoredState<Int>(wrappedValue: 0, "counter", store: restorationStore)
require(reloadedCounter.wrappedValue == 9, "restored state reloads a persisted value")
var restoredObserved = 0
let restoredObserver = reloadedCounter.projectedValue.observe { restoredObserved = $0 }
reloadedCounter.projectedValue.wrappedValue = 11
require(reloadedCounter.wrappedValue == 11 && restoredObserved == 11, "restored state projected binding writes and observes")
if let restoredObserver { reloadedCounter.projectedValue.removeObserver(restoredObserver) }
require(restoredCounter.wrappedValue == 11, "restored state synchronizes matching keys within one store")
reloadedCounter.reset()
require(reloadedCounter.wrappedValue == 0, "restored state reset restores its declared default")
require(restoredCounter.wrappedValue == 3, "restored state reset synchronizes other wrappers to their own defaults")
restorationDefaults.set(Data("invalid".utf8), forKey: "validation.corrupt")
require(restorationStore.value(forKey: "corrupt", as: Int.self) == nil, "restoration store ignores invalid encoded data")
restorationStore.removeValue(forKey: "answer")
require(restorationStore.value(forKey: "answer", as: Int.self) == nil, "restoration store removes one value")
restorationStore.removeAll()
require(restorationStore.value(forKey: "counter", as: Int.self) == nil, "restoration store removes its namespace")

struct RestoredStateSyntaxFixture {
    @FluentRestoredState("syntax", store: restorationStore) var value = 4
}
var restoredSyntaxFixture = RestoredStateSyntaxFixture()
require(restoredSyntaxFixture.value == 4, "restored state supports property-wrapper declaration syntax")
restoredSyntaxFixture.value = 6
require(restorationStore.value(forKey: "syntax", as: Int.self) == 6, "property-wrapper assignment persists restored state")

struct RestoredStateLabel: FluentView {
    let state: FluentRestoredState<Int>
    var body: FluentTextView { FluentText("Restored: \(state.wrappedValue)") }
}
let reactiveRestoredState = FluentRestoredState<Int>(wrappedValue: 2, "reactive", store: restorationStore)
let reactiveRestoredHost = FluentViewHost(RestoredStateLabel(state: reactiveRestoredState))
require(firstLabel(in: reactiveRestoredHost)?.stringValue == "Restored: 2", "restored state participates in dependency tracking")
reactiveRestoredState.wrappedValue = 7
drainMainQueue()
require(firstLabel(in: reactiveRestoredHost)?.stringValue == "Restored: 7", "restored state refreshes dependent views")

let migrationDefaults = UserDefaults(suiteName: "FluentKitMigrationValidation.\(UUID().uuidString)")!
let migrationStore = FluentRestorationStore(defaults: migrationDefaults, namespace: "migration")
require(migrationStore.set("Ada", forKey: "displayName"), "migration fixture stores its legacy value")
let migratedProfileName = FluentRestoredState(wrappedValue: "Unknown", "profileName", store: migrationStore)
let migrator = FluentStateMigrator(
    targetVersion: 2,
    steps: [
        FluentStateMigrationStep(from: 0, to: 1) { context in
            require(context.renameValue(fromKey: "displayName", toKey: "profileName"), "migration context renames encoded values")
        },
        FluentStateMigrationStep(from: 1, to: 2) { context in
            let profile = context.value(forKey: "profileName", as: String.self) ?? "Unknown"
            try context.set(profile.uppercased(), forKey: "profileName")
            try context.set([String](), forKey: "recentFiles")
        }
    ]
)
let migrationResult = try migrator.migrate(migrationStore)
require(migrationResult == FluentStateMigrationResult(fromVersion: 0, toVersion: 2, didMigrate: true), "state migrator reports the applied version range")
require(migrationStore.value(forKey: "displayName", as: String.self) == nil, "state migration removes renamed legacy keys")
require(migrationStore.value(forKey: "profileName", as: String.self) == "ADA", "state migration transforms staged values")
require(migrationStore.value(forKey: "recentFiles", as: [String].self) == [], "state migration adds values for the new schema")
require(migrationStore.value(forKey: "__schemaVersion", as: Int.self) == 2, "state migration commits its schema version")
require(migratedProfileName.wrappedValue == "ADA", "migration commit refreshes existing restored-state observers")
let repeatedMigrationResult = try migrator.migrate(migrationStore)
require(!repeatedMigrationResult.didMigrate, "state migrations are idempotent at the target version")

enum ValidationMigrationFailure: Error { case stop }
let rollbackDefaults = UserDefaults(suiteName: "FluentKitMigrationRollback.\(UUID().uuidString)")!
let rollbackStore = FluentRestorationStore(defaults: rollbackDefaults, namespace: "rollback")
require(rollbackStore.set("Original", forKey: "value"), "migration rollback fixture stores its value")
let failingMigrator = FluentStateMigrator(
    targetVersion: 1,
    steps: [FluentStateMigrationStep(from: 0, to: 1) { context in
        try context.set("Partial", forKey: "value")
        throw ValidationMigrationFailure.stop
    }]
)
do {
    _ = try failingMigrator.migrate(rollbackStore)
    require(false, "failing migrations must throw")
} catch ValidationMigrationFailure.stop {}
require(rollbackStore.value(forKey: "value", as: String.self) == "Original", "failed migrations leave stored values unchanged")
require(rollbackStore.value(forKey: "__schemaVersion", as: Int.self) == nil, "failed migrations do not advance the schema version")

let accessibilityGroup = FluentText("Semantic value").accessibilityGroup(label: "Settings group")
let accessibilityGroupHost = accessibilityGroup._mount(in: FluentRenderContext())
require(accessibilityGroupHost.isAccessibilityElement(), "accessibility group exposes a semantic host")
require(accessibilityGroupHost.accessibilityChildren()?.count == 1, "accessibility group exposes its visual content as a child")
let updatedAccessibilityGroup = FluentText("Updated semantic value").accessibilityGroup(label: "Updated group")
require(updatedAccessibilityGroup._update(accessibilityGroupHost, in: FluentRenderContext()), "accessibility group updates compatibly")
require(accessibilityGroupHost.accessibilityLabel() == "Updated group", "accessibility group refreshes semantic metadata")
require(accessibilityGroupHost.accessibilityChildren()?.count == 1, "accessibility group preserves its child tree after update")

let semanticCombined = FluentHStack(spacing: 4) {
    FluentText("First", style: .body).accessibilityLabel("First value")
    FluentText("Second", style: .body).accessibilityLabel("Second value")
}.accessibilityElement(children: .combine, label: "Combined values")
let semanticCombinedView = semanticCombined._mount(in: FluentRenderContext())
require(semanticCombinedView.accessibilityRole() == .group, "semantic combine exposes a stable group element")
require(semanticCombinedView.accessibilityLabel() == "Combined values", "semantic combine preserves its explicit label")
require(semanticCombinedView.accessibilityChildren()?.isEmpty == true, "semantic combine hides descendants from the accessibility tree")

var customActionInvocations = 0
let customActionView = FluentButtonView("Archive")
    .accessibilityActions([
        FluentAccessibilityAction("Archive item") { customActionInvocations += 1 }
    ])
    ._mount(in: FluentRenderContext())
require(customActionView.accessibilityCustomActions()?.count == 1, "custom accessibility actions attach to the native element")
require(customActionView.accessibilityCustomActions()?.first?.handler?() == true, "custom accessibility action returns its execution status")
require(customActionInvocations == 1, "custom accessibility action invokes its Swift closure")

let dynamicAccessibilityLabel = FluentState(wrappedValue: "Initial label")
let dynamicAccessibilityView = FluentText("Visual value")
    .accessibilityLabel(dynamicAccessibilityLabel.projectedValue)
    ._mount(in: FluentRenderContext())
require(firstLabel(in: dynamicAccessibilityView)?.accessibilityLabel() == "Initial label", "dynamic accessibility label reads its initial binding")
dynamicAccessibilityLabel.wrappedValue = "Updated label"
drainMainQueue()
require(firstLabel(in: dynamicAccessibilityView)?.accessibilityLabel() == "Updated label", "dynamic accessibility label updates without remounting")

let rotorContent = FluentVStack(spacing: 4) {
    FluentText("Heading one", style: .headline).accessibilityIdentifier("rotor.one")
    FluentText("Heading two", style: .headline).accessibilityIdentifier("rotor.two")
}.accessibilityRotor(FluentAccessibilityRotor("Headings", entries: [
    FluentAccessibilityRotorEntry(identifier: "rotor.one", label: "Heading one"),
    FluentAccessibilityRotorEntry(identifier: "rotor.two", label: "Heading two")
]))
let rotorView = rotorContent._mount(in: FluentRenderContext())
require(rotorView.accessibilityCustomRotors().count == 1, "custom rotor attaches to the semantic root")
if let rotor = rotorView.accessibilityCustomRotors().first,
   let delegate = rotor.itemSearchDelegate {
    let parameters = NSAccessibilityCustomRotor.SearchParameters()
    parameters.searchDirection = .next
    parameters.filterString = "heading"
    require(delegate.rotor(rotor, resultFor: parameters)?.customLabel == "Heading one", "custom rotor resolves the first filtered entry")
}

let focusAnnouncementContent = FluentButtonView("Focus target")
    .accessibilityAnnounceOnFocus("Focus target is ready")
let focusAnnouncementView = focusAnnouncementContent._mount(in: FluentRenderContext())
let focusAnnouncementWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
focusAnnouncementWindow.contentView = focusAnnouncementView
focusAnnouncementWindow.orderFront(nil)
focusAnnouncementWindow.layoutIfNeeded()
let focusTarget = firstView(withAccessibilityTitle: "Focus target", in: focusAnnouncementView)
require(focusTarget != nil, "focus announcement preserves the wrapped native control")
if let focusTarget { _ = focusAnnouncementWindow.makeFirstResponder(focusTarget) }
drainMainQueue()
focusAnnouncementWindow.orderOut(nil)

let localizedView = FluentLocalizedText("validation.greeting", defaultValue: "Hello from FluentKit", style: .body)
    ._mount(in: FluentRenderContext(locale: Locale(identifier: "en_US")))
require(firstLabel(in: localizedView)?.stringValue == "Hello from FluentKit", "localized text uses its default value when no table entry exists")

let rtlHost = FluentViewHost(
    FluentText("RTL"),
    context: FluentRenderContext(layoutDirection: .rightToLeft)
)
require(rtlHost.userInterfaceLayoutDirection == .rightToLeft, "render context propagates right-to-left direction to the host")

let invalidAccessibilityButton = NSButton(frame: .zero)
invalidAccessibilityButton.setAccessibilityElement(true)
invalidAccessibilityButton.setAccessibilityRole(.button)
invalidAccessibilityButton.setAccessibilityLabel("")
let auditIssues = FluentAccessibilityAudit.run(on: invalidAccessibilityButton)
require(auditIssues.contains { $0.severity == .error }, "accessibility audit reports unlabeled interactive elements")
let duplicateAccessibilityRoot = NSView(frame: .zero)
let duplicateA = NSView(frame: .zero)
let duplicateB = NSView(frame: .zero)
[duplicateA, duplicateB].forEach {
    $0.setAccessibilityElement(true)
    $0.setAccessibilityIdentifier("duplicate")
    duplicateAccessibilityRoot.addSubview($0)
}
require(FluentAccessibilityAudit.run(on: duplicateAccessibilityRoot).contains { $0.message.contains("duplicates") }, "accessibility audit reports duplicate identifiers")

var commandBarInvocationCount = 0
var commandBarToggleValue = true
let commandBarFlyout = FluentCommandBarFlyout(
    theme: theme,
    reduceMotion: false,
    primaryCommands: {
        FluentCommandBarItem("Favorite", systemImageName: "star") {}
        FluentCommandBarItem.separator
        FluentCommandBarItem.toggle(
            "Bold",
            systemImageName: "bold",
            isOn: true
        ) { commandBarToggleValue = $0 }
    },
    secondaryCommands: {
        FluentCommandBarItem(
            "Archive",
            systemImageName: "archivebox",
            keyEquivalent: "a",
            keyModifiers: [.command, .shift]
        ) { commandBarInvocationCount += 1 }
        FluentCommandBarItem.separator
        FluentCommandBarItem("Disabled", isEnabled: false) {}
    }
)
require(
    commandBarFlyout.primaryCommands.count == 3
        && commandBarFlyout.secondaryCommands.count == 3
        && commandBarFlyout.primaryCommands[1].kind == .separator
        && commandBarFlyout.primaryCommands[2].kind == .toggle(isOn: true)
        && commandBarFlyout.secondaryCommands[0].accelerator == "⇧⌘A",
    "CommandBarFlyout exposes WinUI-style PrimaryCommands, SecondaryCommands, toggle, separator, and accelerator models"
)
let commandBarWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let commandBarAnchor = NSButton(frame: NSRect(x: 20, y: 80, width: 140, height: 32))
commandBarWindow.contentView = commandBarAnchor
commandBarWindow.center()
commandBarWindow.orderFront(nil)
commandBarFlyout.present(relativeTo: commandBarAnchor)
let commandBarPanel = commandBarWindow.childWindows?.first
let commandBarContent = commandBarPanel?.contentView
let commandBarPresenter = commandBarContent.flatMap { firstView(withAccessibilityRole: .menu, in: $0) }
let collapsedCommandBarHeight = commandBarPanel?.frame.height ?? 0
let collapsedCommandBarChildren = (commandBarPresenter?.accessibilityChildren() ?? []).compactMap { $0 as? NSView }
require(
    commandBarFlyout.isPresented
        && commandBarPresenter?.identifier?.rawValue == "FluentKit.CommandBarFlyout"
        && firstMaterialView(in: commandBarContent ?? NSView())?.materialStyle == .liquidGlass
        && Set(collapsedCommandBarChildren.compactMap { $0.accessibilityTitle() }) == Set(["Favorite", "Bold", "More"])
        && collapsedCommandBarChildren.allSatisfy { abs($0.frame.width - 40) < 0.001 },
    "CommandBarFlyout opens its compact primary bar on the shared Liquid Glass presenter"
)
require(
    collapsedCommandBarChildren.first { $0.accessibilityTitle() == "Bold" }?.accessibilityValue() as? String == "On"
        && views(identifier: "FluentKit.CommandBarFlyout.Separator", in: commandBarPresenter ?? NSView()).count == 1,
    "CommandBarFlyout exposes checked toggle semantics and the source vertical AppBarSeparator"
)
let commandBarMoreButton = collapsedCommandBarChildren.first { $0.accessibilityTitle() == "More" }
require(commandBarMoreButton?.accessibilityPerformPress() == true, "CommandBarFlyout More expands SecondaryCommands")
let commandBarExpansionClip = commandBarContent.flatMap {
    firstLayer(named: "FluentKit.TextCommandBarFlyout.ExpansionClip", in: $0)
}
let commandBarExpansionAnimation = commandBarExpansionClip?.animation(
    forKey: "fluent.popup.textCommandBar.expand.clip"
) as? CABasicAnimation
require(
    commandBarExpansionAnimation?.keyPath == "path"
        && abs((commandBarExpansionAnimation?.duration ?? 0) - FluentMotion.controlNormal.duration) < 0.0001
        && timingFunctionMatches(
            commandBarExpansionAnimation?.timingFunction,
            FluentMotion.controlNormal.curve.timingFunction
        ),
    "CommandBarFlyout reuses the source 250ms collapsed-to-expanded clip timeline"
)
require(
    waitUntil(timeout: 0.30) {
        (commandBarPanel?.frame.height ?? 0) > collapsedCommandBarHeight
            && firstView(withAccessibilityTitle: "Archive", in: commandBarPresenter ?? NSView()) != nil
            && views(identifier: "FluentKit.CommandBarFlyout.Separator", in: commandBarPresenter ?? NSView()).count == 2
    },
    "CommandBarFlyout expansion commits secondary rows and the horizontal overflow separator"
)
let archiveCommandBarRow = firstView(withAccessibilityTitle: "Archive", in: commandBarPresenter ?? NSView())
require(archiveCommandBarRow?.accessibilityPerformPress() == true, "CommandBarFlyout secondary command is invokable")
require(
    commandBarInvocationCount == 1
        && !commandBarFlyout.isPresented
        && commandBarWindow.childWindows?.isEmpty != false,
    "CommandBarFlyout command execution dismisses the complete panel immediately"
)

let alwaysExpandedCommandBar = FluentCommandBarFlyout(
    primaryCommands: [FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") {}],
    secondaryCommands: [FluentCommandBarItem("Select all") {}],
    alwaysExpanded: true,
    theme: theme,
    reduceMotion: true
)
alwaysExpandedCommandBar.present(relativeTo: commandBarAnchor)
let alwaysExpandedPresenter = commandBarWindow.childWindows?.first?.contentView.flatMap {
    firstView(withAccessibilityRole: .menu, in: $0)
}
let alwaysExpandedTitles = Set(
    (alwaysExpandedPresenter?.accessibilityChildren() ?? []).compactMap { ($0 as? NSView)?.accessibilityTitle() }
)
require(
    alwaysExpandedTitles == Set(["Copy", "Select all"])
        && !alwaysExpandedTitles.contains("More"),
    "CommandBarFlyout AlwaysExpanded opens PrimaryCommands and SecondaryCommands without a More button"
)
alwaysExpandedCommandBar.dismiss()
require(commandBarToggleValue, "constructing a checked CommandBarFlyout toggle does not mutate external state")

let attachedCommandBarButtonView = FluentButtonView("Attached command bar")
    .commandBarFlyout {
        FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") {}
    } secondaryCommands: {
        FluentCommandBarItem("Select all") {}
    }
guard let attachedCommandBarButton = attachedCommandBarButtonView._mount(
    in: FluentRenderContext(theme: theme, reduceMotion: true)
) as? FluentButton else {
    fatalError("attached CommandBarFlyout did not mount a FluentButton")
}
attachedCommandBarButton.frame = NSRect(x: 20, y: 80, width: 160, height: 32)
commandBarWindow.contentView = attachedCommandBarButton
attachedCommandBarButton.performClick(nil)
drainMainQueue()
require(
    commandBarWindow.childWindows?.count == 1
        && attachedCommandBarButton.accessibilityRole() == .popUpButton
        && attachedCommandBarButton.accessibilityValue() as? String == "Open",
    "FluentButtonView attaches and publishes a public CommandBarFlyout without Gallery-owned presentation code"
)
attachedCommandBarButton.performClick(nil)
require(
    commandBarWindow.childWindows?.isEmpty != false
        && attachedCommandBarButton.accessibilityValue() as? String == "Closed",
    "clicking the attached CommandBarFlyout Button again dismisses the existing presenter immediately"
)
commandBarWindow.orderOut(nil)

let menuWrapped = FluentButtonView("Contextual").contextMenu {
    FluentMenuItem("Open") {}
    FluentMenuItem.separator
}
let contextMenuHost = menuWrapped._mount(in: FluentRenderContext())
require(contextMenuHost.subviews.count == 1, "context menu keeps content mounted")
let contextMenuWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
contextMenuHost.frame = contextMenuWindow.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 220, height: 80)
contextMenuWindow.contentView = contextMenuHost
contextMenuWindow.makeKeyAndOrderFront(nil)
contextMenuHost.layoutSubtreeIfNeeded()
let contextClickPoint = NSPoint(x: contextMenuHost.bounds.midX, y: contextMenuHost.bounds.midY)
contextMenuHost.rightMouseDown(
    with: toggleMouseEvent(.rightMouseDown, at: contextClickPoint, in: contextMenuHost, eventNumber: 80)
)
drainMainQueue()
require(
    contextMenuWindow.childWindows?.count == 1,
    "context-menu host routes right-clicks into the custom application flyout"
)
if let contextPresenter = contextMenuWindow.childWindows?.first?.contentView.flatMap({
    firstView(withAccessibilityRole: .menu, in: $0)
}) {
    contextPresenter.keyDown(with: sliderKeyEvent(53, in: contextPresenter, eventNumber: 81))
}
drainMainQueue()
contextMenuWindow.orderOut(nil)

let leftClickMenuWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let leftClickMenuButton = FluentDropDownButton(
    title: "Open menu",
    items: [FluentMenuItem("First") {}, FluentMenuItem("Second") {}]
)
leftClickMenuButton.frame = NSRect(x: 20, y: 20, width: 140, height: 32)
leftClickMenuWindow.contentView = leftClickMenuButton
leftClickMenuWindow.center()
leftClickMenuWindow.makeKeyAndOrderFront(nil)
leftClickMenuButton.layoutSubtreeIfNeeded()
guard let dropDownElevationBorder = firstLayer(
    named: "FluentKit.DropDownButton.ElevationBorder",
    in: leftClickMenuButton
) as? CAGradientLayer, let dropDownElevationMask = dropDownElevationBorder.mask as? CAShapeLayer,
   let dropDownElevationPath = dropDownElevationMask.path else {
    fatalError("DropDownButton elevation border did not mount")
}
let dropDownElevationBounds = dropDownElevationPath.boundingBox
require(
    dropDownElevationMask.fillRule == .evenOdd
        && pathBoundsUseContainedAntialiasing(
            dropDownElevationBounds,
            in: leftClickMenuButton.bounds,
            backingScale: dropDownElevationBorder.contentsScale
        ),
    "DropDownButton keeps its elevation antialiasing inside every host edge"
)
require(
    dropDownElevationBorder.locations?.map(\.doubleValue) == [0.33, 1],
    "DropDownButton reuses the Button ControlElevationBorderBrush stop positions"
)
require(
    elevationGradientMatchesVisualEdge(
        dropDownElevationBorder,
        edge: .bottom,
        hostView: leftClickMenuButton
    ),
    "DropDownButton reuses the source ControlElevationBorderBrush absolute three-point extent"
)
let coldDropDownChevron = firstLayer(
    named: "FluentKit.DropDownButton.Chevron",
    in: leftClickMenuButton
) as? CAShapeLayer
let coldDropDownChevronPoints = pathVertices(coldDropDownChevron?.path)
require(
    chevronPointsVisuallyDown(coldDropDownChevronPoints, in: coldDropDownChevron),
    "DropDownButton points its cold-start chevron visually down before hover"
)
leftClickMenuButton.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 82
    )
)
require(
    translationMovesVisuallyDown(
        coldDropDownChevron?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0,
        in: coldDropDownChevron
    ),
    "DropDownButton press moves the shared chevron along the stable visual-down axis"
)
require(
    leftClickMenuWindow.childWindows?.isEmpty != false,
    "DropDownButton pointer-down only enters Pressed and moves its chevron"
)
let pressedDropDownChevron = firstLayer(named: "FluentKit.DropDownButton.Chevron", in: leftClickMenuButton)
require(
    abs((pressedDropDownChevron?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0)) > 1,
    "DropDownButton pointer-down moves the animated chevron toward the visual bottom"
)
let pressedChevronAnimation = pressedDropDownChevron?.animation(forKey: "fluent.chevron.press")
let sameDropDownTheme = leftClickMenuButton.theme
leftClickMenuButton.theme = sameDropDownTheme
require(
    pressedChevronAnimation != nil
        && pressedDropDownChevron?.animation(forKey: "fluent.chevron.press") != nil,
    "DropDownButton ignores an equal theme update while its chevron press animation is active"
)
leftClickMenuButton.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 83
    )
)
drainMainQueue()
require(
    leftClickMenuWindow.childWindows?.count == 1,
    "DropDownButton opens its flyout only after pointer release inside"
)
require(
    leftClickMenuButton.isFlyoutPresented
        && leftClickMenuButton.accessibilityValue() as? String == "Open",
    "DropDownButton publishes its open state after the attached MenuFlyout presents"
)
require(
    abs((pressedDropDownChevron?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0)) < 0.001,
    "DropDownButton restores its chevron before presenting the flyout"
)
if let menuPanel = leftClickMenuWindow.childWindows?.first {
    let buttonScreenRect = leftClickMenuWindow.convertToScreen(
        leftClickMenuButton.convert(leftClickMenuButton.bounds, to: nil)
    )
    require(
        menuPanel.frame.maxY <= buttonScreenRect.minY - 1,
        "FluentDropDownButton places its flyout below the button without overlap"
    )
    require(
        menuPanel.frame.width >= leftClickMenuButton.bounds.width,
        "DropDownButton flyout is never narrower than its owner"
    )
}
let firstDropDownPanel = leftClickMenuWindow.childWindows?.first
leftClickMenuButton.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 84
    )
)
require(
    leftClickMenuWindow.childWindows?.isEmpty != false
        && firstDropDownPanel?.contentView?.layer?.animation(forKey: "fluent.menu.surface.close") == nil,
    "clicking an open DropDownButton removes the flyout immediately without exit animation"
)
require(
    !leftClickMenuButton.isFlyoutPresented
        && leftClickMenuButton.accessibilityValue() as? String == "Closed",
    "DropDownButton clears its open state when toggling the attached MenuFlyout closed"
)
leftClickMenuButton.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 85
    )
)
drainMainQueue()
require(
    leftClickMenuWindow.childWindows?.isEmpty != false,
    "the release completing an open-trigger dismissal does not recreate the flyout"
)
leftClickMenuButton.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 86
    )
)
leftClickMenuButton.mouseDragged(
    with: toggleMouseEvent(
        .leftMouseDragged,
        at: NSPoint(x: -20, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 87
    )
)
leftClickMenuButton.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: -20, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 88
    )
)
drainMainQueue()
require(
    leftClickMenuWindow.childWindows?.isEmpty != false,
    "dragging a DropDownButton press outside cancels presentation"
)
leftClickMenuButton.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 89
    )
)
leftClickMenuButton.mouseUp(
    with: toggleMouseEvent(
        .leftMouseUp,
        at: NSPoint(x: leftClickMenuButton.bounds.midX, y: leftClickMenuButton.bounds.midY),
        in: leftClickMenuButton,
        eventNumber: 90
    )
)
drainMainQueue()
require(leftClickMenuButton.isFlyoutPresented, "DropDownButton can reopen after a canceled press")
leftClickMenuButton.isEnabled = false
require(
    leftClickMenuWindow.childWindows?.isEmpty != false
        && !leftClickMenuButton.isFlyoutPresented,
    "disabling DropDownButton immediately closes its attached MenuFlyout"
)
leftClickMenuButton.isEnabled = true
leftClickMenuWindow.orderOut(nil)

let attachedFlyoutWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
var attachedButtonInvocations = 0
let attachedFlyoutView = FluentButtonView("Attached flyout") {
    attachedButtonInvocations += 1
}.flyout {
    FluentMenuItem("Attached item") {}
}
guard let attachedFlyoutButton = attachedFlyoutView._mount(in: FluentRenderContext()) as? FluentButton else {
    fatalError("button-owned flyout did not mount as FluentButton")
}
attachedFlyoutButton.frame = NSRect(x: 20, y: 20, width: 150, height: 32)
attachedFlyoutWindow.contentView = attachedFlyoutButton
attachedFlyoutWindow.center()
attachedFlyoutWindow.makeKeyAndOrderFront(nil)
attachedFlyoutButton.performClick(nil)
drainMainQueue()
require(attachedButtonInvocations == 1, "Button.Flyout preserves the button's primary action")
require(
    attachedFlyoutWindow.childWindows?.count == 1,
    "declarative Button.Flyout opens an application-owned menu from the button"
)
require(
    attachedFlyoutButton.controlState != .pressed,
    "Button.Flyout releases its owner after the opening click instead of latching Pressed"
)
let firstAttachedPanel = attachedFlyoutWindow.childWindows?.first
attachedFlyoutButton.performClick(nil)
drainMainQueue()
require(
    attachedButtonInvocations == 2
        && attachedFlyoutWindow.childWindows?.isEmpty != false
        && firstAttachedPanel?.contentView?.layer?.animation(forKey: "fluent.menu.surface.close") == nil,
    "clicking an open Button.Flyout closes it immediately without recreating the presenter"
)
attachedFlyoutButton.performClick(nil)
drainMainQueue()
require(
    attachedButtonInvocations == 3
        && attachedFlyoutWindow.childWindows?.count == 1
        && attachedFlyoutButton.controlState != .pressed,
    "Button.Flyout can reopen on a later click while the owner remains released"
)
if let attachedPresenter = attachedFlyoutWindow.childWindows?.first?.contentView.flatMap({
    firstView(withAccessibilityRole: .menu, in: $0)
}) {
    attachedPresenter.keyDown(with: sliderKeyEvent(53, in: attachedPresenter, eventNumber: 84))
}
require(
    waitUntil(timeout: 0.20) { attachedFlyoutWindow.childWindows?.isEmpty != false },
    "Button.Flyout dismisses through the shared MenuFlyout keyboard path"
)
require(
    attachedFlyoutButton.controlState != .pressed,
    "Button.Flyout clears the owner's open visual state after dismissal"
)
attachedFlyoutWindow.orderOut(nil)

let menuFlyoutWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let menuFlyoutAnchor = NSButton(frame: NSRect(x: 20, y: 20, width: 120, height: 32))
menuFlyoutWindow.contentView = menuFlyoutAnchor
menuFlyoutWindow.center()
menuFlyoutWindow.orderFront(nil)
var nestedMenuInvocations = 0
let nestedMenuItem = FluentMenuItem.submenu("More", systemImageName: "ellipsis.circle") {
    FluentMenuItem("Rename", systemImageName: "pencil") { nestedMenuInvocations += 1 }
    FluentMenuItem("Manage access", systemImageName: "person.2") {}
}
require(
    nestedMenuItem.hasSubmenu
        && nestedMenuItem.submenu.count == 2
        && nestedMenuItem.systemImageName == "ellipsis.circle",
    "menu model preserves nested declarative items and their system-icon slot"
)
let menuFlyout = FluentMenuFlyout(items: [
    FluentMenuItem("Open", systemImageName: "doc", keyEquivalent: "o") {},
    nestedMenuItem,
    .separator,
    FluentMenuItem("Checked", systemImageName: "checkmark.circle", state: .on) {},
    FluentMenuItem("Zebra") {},
    FluentMenuItem("Disabled", isEnabled: false) {}
], reduceMotion: false)
menuFlyout.present(relativeTo: menuFlyoutAnchor)
require(menuFlyout.isPresented, "application menu flyout presents its custom panel")
require(menuFlyoutWindow.childWindows?.count == 1, "application menu flyout attaches its panel to the owning window")
let rootMenuPanel = menuFlyoutWindow.childWindows?.first
require(
    rootMenuPanel?.hasShadow == false,
    "MenuFlyout does not stack a native black panel shadow around its opaque surface"
)
if let rootMenuContent = rootMenuPanel?.contentView {
    require(
        firstMaterialView(in: rootMenuContent)?.materialStyle == .liquidGlass
            && firstMaterialView(in: rootMenuContent)?.isMaterialEnabled == true,
        "MenuFlyout uses the global Liquid Glass transient surface"
    )
}
require(
    rootMenuPanel?.contentView?.layer?.borderWidth == 0,
    "MenuFlyout keeps one opaque edge owner without a second CALayer stroke"
)
let rootMenuAnimationRootLayer = rootMenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.AnimationRoot", in: $0)
}
let rootMenuBorderLayer = rootMenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.PopupBorder", in: $0)
}
let rootMenuPresenterLayer = rootMenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.Presenter", in: $0)
}
let rootMenuClipLayer = rootMenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.RevealClip", in: $0)
}
let rootMenuBorderEntrance = rootMenuBorderLayer?.animation(forKey: "fluent.popup.border.open") as? CABasicAnimation
let rootMenuAnimationRootEntrance = rootMenuAnimationRootLayer?.animation(forKey: "fluent.popup.animationRoot.open") as? CABasicAnimation
let rootMenuClosedAnimationRoot = (rootMenuAnimationRootEntrance?.fromValue as? NSValue)?.caTransform3DValue
let rootMenuClipEntrance = rootMenuClipLayer?.animation(forKey: "fluent.popup.clip.open") as? CABasicAnimation
let rootMenuClosedClip = (rootMenuClipEntrance?.fromValue as? NSValue)?.caTransform3DValue
let rootMenuClosedBorder = (rootMenuBorderEntrance?.fromValue as? NSValue)?.caTransform3DValue
let rootMenuHeight = rootMenuPanel?.contentView?.bounds.height ?? 0
require(
    rootMenuBorderEntrance?.keyPath == "transform"
        && rootMenuAnimationRootEntrance?.keyPath == "transform"
        && rootMenuPresenterLayer?.animation(forKey: "fluent.popup.presenter.open") == nil
        && rootMenuClipEntrance?.keyPath == "transform"
        && abs((rootMenuBorderEntrance?.duration ?? 0) - FluentMotion.menuOpen.duration) < 0.0001
        && abs((rootMenuAnimationRootEntrance?.duration ?? 0) - FluentMotion.menuOpen.duration) < 0.0001
        && abs((rootMenuClipEntrance?.duration ?? 0) - FluentMotion.menuOpen.duration) < 0.0001
        && timingFunctionMatches(rootMenuBorderEntrance?.timingFunction, FluentMotion.menuOpen.curve.timingFunction)
        && timingFunctionMatches(rootMenuAnimationRootEntrance?.timingFunction, FluentMotion.menuOpen.curve.timingFunction)
        && timingFunctionMatches(rootMenuClipEntrance?.timingFunction, FluentMotion.menuOpen.curve.timingFunction),
    "root MenuFlyout submits border, complete presenter root, and inverse clip on one timeline"
)
require(
    abs((rootMenuClosedAnimationRoot?.m42 ?? 0) - rootMenuHeight * 0.5) < 0.0001
        && abs((rootMenuClosedClip?.m42 ?? 0) + rootMenuHeight * 0.5) < 0.0001
        && abs((rootMenuClosedAnimationRoot?.m42 ?? 0) + (rootMenuClosedClip?.m42 ?? 0)) < 0.0001
        && abs((rootMenuClosedBorder?.m22 ?? 0) - 0.5) < 0.0001
        && abs((rootMenuClosedBorder?.m42 ?? 0) - rootMenuHeight * 0.5) < 0.0001
        && rootMenuClipLayer?.superlayer === rootMenuAnimationRootLayer,
    "below-anchor MenuFlyout keeps its adjacent border edge fixed while moving the presenter downward "
        + "(height: \(rootMenuHeight), border: \(String(describing: rootMenuClosedBorder)))"
)
let rootMenuPresenter = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityRole: .menu, in: $0) }
require(rootMenuPresenter?.accessibilityChildren()?.count == 5, "menu accessibility tree excludes separators and includes every actionable row")
rootMenuPresenter?.layoutSubtreeIfNeeded()
let rootMenuIcons = rootMenuPanel?.contentView.map {
    views(identifier: "FluentKit.Menu.Item.Icon", in: $0)
} ?? []
require(
    rootMenuIcons.count == 3
        && rootMenuIcons.allSatisfy {
            abs($0.frame.minX - 39) < 0.001
                && abs($0.frame.width - 16) < 0.001
                && abs($0.frame.height - 16) < 0.001
        },
    "MenuFlyout applies source 28pt check/icon placeholders and a stable 16pt icon slot"
)
let openMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Open", in: $0) }
require(
    openMenuRow?.accessibilityHelp() == "Keyboard shortcut ⌘O",
    "MenuFlyout exposes the rendered accelerator through native accessibility"
)
let moreMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "More", in: $0) }
let checkedMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Checked", in: $0) }
let disabledMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Disabled", in: $0) }
require(moreMenuRow?.accessibilityRole() == .menuItem, "submenu row exposes the native menu-item role")
require(moreMenuRow?.accessibilityValue() as? String == "Submenu", "submenu row announces its expandable state")
require(moreMenuRow?.accessibilityHelp() == "Opens a submenu", "submenu row exposes an accessibility hint")
require(checkedMenuRow?.accessibilityValue() as? String == "Selected", "checked menu row exposes its selected state")
require(disabledMenuRow?.isAccessibilityEnabled() == false, "disabled menu row exposes disabled semantics")
if let openMenuRow, let checkedMenuRow {
    openMenuRow.updateTrackingAreas()
    openMenuRow.updateTrackingAreas()
    checkedMenuRow.updateTrackingAreas()
    checkedMenuRow.updateTrackingAreas()
    require(
        openMenuRow.trackingAreas.count == 1 && checkedMenuRow.trackingAreas.count == 1,
        "MenuFlyout rows keep one visible-rect tracking area across repeated layout updates"
    )
    let openRestingAlpha = renderedBackgroundAlpha(in: openMenuRow)
    let checkedRestingAlpha = renderedBackgroundAlpha(in: checkedMenuRow)
    openMenuRow.mouseEntered(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: 12, y: openMenuRow.bounds.midY),
            in: openMenuRow,
            eventNumber: 91
        )
    )
    let openHoverAlpha = renderedBackgroundAlpha(in: openMenuRow)
    checkedMenuRow.mouseEntered(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: 12, y: checkedMenuRow.bounds.midY),
            in: checkedMenuRow,
            eventNumber: 92
        )
    )
    require(
        openHoverAlpha > openRestingAlpha + 0.01
            && abs(renderedBackgroundAlpha(in: openMenuRow) - openRestingAlpha) < 0.01
            && renderedBackgroundAlpha(in: checkedMenuRow) > checkedRestingAlpha + 0.01,
        "MenuFlyout owns one transient PointerOver row without a persistent selected fill"
    )
    checkedMenuRow.mouseExited(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: -1, y: -1),
            in: checkedMenuRow,
            eventNumber: 93
        )
    )
}
if let typeaheadEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6) {
    rootMenuPresenter?.keyDown(with: typeaheadEvent)
}
let zebraMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Zebra", in: $0) }
require(zebraMenuRow?.isAccessibilitySelected() == true, "menu type-ahead selects the first enabled title prefix")
if let hoverEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0), let moreMenuRow {
    moreMenuRow.mouseEntered(with: hoverEvent)
}
require(rootMenuPanel?.childWindows?.isEmpty != false, "submenu hover is deferred rather than opening synchronously")
require(
    waitUntil(timeout: 0.30) { rootMenuPanel?.childWindows?.count == 1 },
    "submenu opens after the Fluent hover delay"
)
let submenuPanel = rootMenuPanel?.childWindows?.first
let submenuAnimationRootLayer = submenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.AnimationRoot", in: $0)
}
let submenuBorderLayer = submenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.PopupBorder", in: $0)
}
let submenuPresenterLayer = submenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.Presenter", in: $0)
}
let submenuClipLayer = submenuPanel?.contentView.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.RevealClip", in: $0)
}
let submenuBorderEntrance = submenuBorderLayer?.animation(forKey: "fluent.popup.border.open") as? CABasicAnimation
let submenuAnimationRootEntrance = submenuAnimationRootLayer?.animation(forKey: "fluent.popup.animationRoot.open") as? CABasicAnimation
let submenuClosedAnimationRoot = (submenuAnimationRootEntrance?.fromValue as? NSValue)?.caTransform3DValue
let submenuClipEntrance = submenuClipLayer?.animation(forKey: "fluent.popup.clip.open") as? CABasicAnimation
let submenuClosedClip = (submenuClipEntrance?.fromValue as? NSValue)?.caTransform3DValue
let submenuClosedBorder = (submenuBorderEntrance?.fromValue as? NSValue)?.caTransform3DValue
let submenuHeight = submenuPanel?.contentView?.bounds.height ?? 0
if let submenuPanel, let moreMenuRow, let rowWindow = moreMenuRow.window {
    let rowScreenRect = rowWindow.convertToScreen(moreMenuRow.convert(moreMenuRow.bounds, to: nil))
    require(
        submenuPanel.frame.minX >= rowScreenRect.maxX - 3,
        "LTR submenu opens from the trailing side of its source row"
    )
}
require(
    submenuBorderEntrance?.keyPath == "transform"
        && submenuAnimationRootEntrance?.keyPath == "transform"
        && submenuPresenterLayer?.animation(forKey: "fluent.popup.presenter.open") == nil
        && submenuClipEntrance?.keyPath == "transform"
        && abs((submenuBorderEntrance?.duration ?? 0) - FluentMotion.submenuOpen.duration) < 0.0001
        && abs((submenuAnimationRootEntrance?.duration ?? 0) - FluentMotion.submenuOpen.duration) < 0.0001
        && abs((submenuClipEntrance?.duration ?? 0) - FluentMotion.submenuOpen.duration) < 0.0001
        && timingFunctionMatches(submenuBorderEntrance?.timingFunction, FluentMotion.submenuOpen.curve.timingFunction)
        && timingFunctionMatches(submenuAnimationRootEntrance?.timingFunction, FluentMotion.submenuOpen.curve.timingFunction)
        && timingFunctionMatches(submenuClipEntrance?.timingFunction, FluentMotion.submenuOpen.curve.timingFunction),
    "submenu submits border, complete presenter root, and inverse clip on one timeline"
)
require(
    abs((submenuClosedAnimationRoot?.m42 ?? 0) - submenuHeight * 0.67) < 0.0001
        && abs((submenuClosedClip?.m42 ?? 0) + submenuHeight * 0.67) < 0.0001
        && abs((submenuClosedAnimationRoot?.m42 ?? 0) + (submenuClosedClip?.m42 ?? 0)) < 0.0001
        && abs((submenuClosedBorder?.m22 ?? 0) - 0.33) < 0.0001
        && abs((submenuClosedBorder?.m42 ?? 0) - submenuHeight * 0.67) < 0.0001
        && submenuClipLayer?.superlayer === submenuAnimationRootLayer,
    "submenu preserves the source translation and pins its 33% border to the adjacent edge"
)
let submenuPresenter = submenuPanel?.contentView.flatMap { firstView(withAccessibilityRole: .menu, in: $0) }
require(submenuPresenter?.accessibilityChildren()?.count == 2, "submenu exposes its own menu accessibility tree")
let renameMenuRow = submenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Rename", in: $0) }
require(renameMenuRow?.accessibilityPerformPress() == true, "submenu item supports the accessibility press action")
require(nestedMenuInvocations == 1, "submenu action invokes its declarative closure exactly once")
require(
    rootMenuPanel?.contentView?.layer?.animation(forKey: "fluent.menu.surface.close") == nil
        && menuFlyoutWindow.childWindows?.isEmpty != false
        && !menuFlyout.isPresented,
    "MenuFlyout item commit removes the complete hierarchy immediately without exit animation"
)
menuFlyout.dismiss(animated: false)
require(menuFlyoutWindow.childWindows?.isEmpty != false, "dismissing a menu removes its complete submenu hierarchy")

menuFlyoutAnchor.userInterfaceLayoutDirection = .rightToLeft
let rtlMenuFlyout = FluentMenuFlyout(items: [nestedMenuItem])
rtlMenuFlyout.present(relativeTo: menuFlyoutAnchor)
let rtlAnchorRect = menuFlyoutWindow.convertToScreen(menuFlyoutAnchor.convert(menuFlyoutAnchor.bounds, to: nil))
    if let rtlPanel = menuFlyoutWindow.childWindows?.first {
    require(abs(rtlPanel.frame.maxX - rtlAnchorRect.maxX) < 2, "RTL root menu aligns its trailing edge to the anchor")
    if let rtlMoreRow = rtlPanel.contentView.flatMap({ firstView(withAccessibilityTitle: "More", in: $0) }) {
        rtlMoreRow.layoutSubtreeIfNeeded()
        let rtlIcon = views(identifier: "FluentKit.Menu.Item.Icon", in: rtlMoreRow).first
        require(
            rtlIcon.map { abs($0.frame.maxX - (rtlMoreRow.bounds.maxX - 11)) < 0.001 } == true,
            "RTL MenuFlyout moves the icon placeholder to logical leading without mirroring the icon"
        )
        rtlMoreRow.mouseEntered(
            with: toggleMouseEvent(
                .mouseMoved,
                at: NSPoint(x: rtlMoreRow.bounds.midX, y: rtlMoreRow.bounds.midY),
                in: rtlMoreRow,
                eventNumber: 86
            )
        )
        require(
            waitUntil(timeout: 0.30) { rtlPanel.childWindows?.count == 1 },
            "RTL submenu opens after the shared hover delay"
        )
        if let rtlSubmenuPanel = rtlPanel.childWindows?.first, let rowWindow = rtlMoreRow.window {
            let rtlRowScreenRect = rowWindow.convertToScreen(rtlMoreRow.convert(rtlMoreRow.bounds, to: nil))
            let rtlRootTransform = rtlSubmenuPanel.contentView.flatMap {
                firstLayer(named: "FluentKit.MenuFlyout.AnimationRoot", in: $0)
            }?.animation(forKey: "fluent.popup.animationRoot.open") as? CABasicAnimation
            let rtlClipTransform = rtlSubmenuPanel.contentView.flatMap {
                firstLayer(named: "FluentKit.MenuFlyout.RevealClip", in: $0)
            }?.animation(forKey: "fluent.popup.clip.open") as? CABasicAnimation
            let rtlRootFrom = (rtlRootTransform?.fromValue as? NSValue)?.caTransform3DValue
            let rtlClipFrom = (rtlClipTransform?.fromValue as? NSValue)?.caTransform3DValue
            require(
                rtlSubmenuPanel.frame.maxX <= rtlRowScreenRect.minX + 3
                    && abs((rtlRootFrom?.m42 ?? 0) + (rtlClipFrom?.m42 ?? 0)) < 0.0001,
                "RTL submenu opens from the leading side with inverse root/clip motion "
                    + "(submenu=\(rtlSubmenuPanel.frame), row=\(rtlRowScreenRect), "
                    + "root=\(rtlRootFrom?.m42 ?? .nan), clip=\(rtlClipFrom?.m42 ?? .nan))"
            )
        }
    }
}
rtlMenuFlyout.dismiss(animated: false)
menuFlyoutAnchor.userInterfaceLayoutDirection = .leftToRight
require(!menuFlyout.isPresented, "application menu flyout clears its presented state on dismissal")
require(menuFlyoutWindow.childWindows?.isEmpty != false, "application menu flyout removes its child panel on dismissal")
let reducedMenuFlyout = FluentMenuFlyout(
    items: [FluentMenuItem("Reduced") {}],
    reduceMotion: true
)
reducedMenuFlyout.present(relativeTo: menuFlyoutAnchor)
let reducedMenuPanel = menuFlyoutWindow.childWindows?.first
require(
    reducedMenuPanel?.contentView.flatMap {
        firstLayer(named: "FluentKit.MenuFlyout.PopupBorder", in: $0)
    }?.animation(forKey: "fluent.popup.border.open") == nil
        && reducedMenuPanel?.contentView.flatMap {
            firstLayer(named: "FluentKit.MenuFlyout.AnimationRoot", in: $0)
        }?.animation(forKey: "fluent.popup.animationRoot.open") == nil,
    "MenuFlyout Reduce Motion reaches final surface geometry without entrance animation"
)
reducedMenuFlyout.dismiss(animated: true)
require(
    menuFlyoutWindow.childWindows?.isEmpty != false,
    "MenuFlyout dismissal remains immediate under Reduce Motion"
)

// Force the presenter above its anchor so the reverse MenuPopupThemeTransition path is exercised.
// The normal fixture opens below the anchor and therefore only covered the positive-y branch.
let menuVisibleFrame = menuFlyoutWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
menuFlyoutWindow.setFrameOrigin(
    NSPoint(x: menuVisibleFrame.midX - menuFlyoutWindow.frame.width / 2, y: menuVisibleFrame.minY + 4)
)
menuFlyoutWindow.orderFront(nil)
let aboveMenuFlyout = FluentMenuFlyout(
    items: [FluentMenuItem("Above") {}, FluentMenuItem("Another item") {}],
    reduceMotion: false
)
aboveMenuFlyout.present(relativeTo: menuFlyoutAnchor)
let aboveMenuPanel = menuFlyoutWindow.childWindows?.first
let aboveMenuContent = aboveMenuPanel?.contentView
let aboveMenuAnchorRect = menuFlyoutWindow.convertToScreen(menuFlyoutAnchor.convert(menuFlyoutAnchor.bounds, to: nil))
let aboveMenuBorder = aboveMenuContent.flatMap { firstLayer(named: "FluentKit.MenuFlyout.PopupBorder", in: $0) }
let aboveMenuRoot = aboveMenuContent.flatMap { firstLayer(named: "FluentKit.MenuFlyout.AnimationRoot", in: $0) }
let aboveMenuClip = aboveMenuContent.flatMap { firstLayer(named: "FluentKit.MenuFlyout.RevealClip", in: $0) }
let aboveMenuBorderAnimation = aboveMenuBorder?.animation(forKey: "fluent.popup.border.open") as? CABasicAnimation
let aboveMenuRootAnimation = aboveMenuRoot?.animation(forKey: "fluent.popup.animationRoot.open") as? CABasicAnimation
let aboveMenuClipAnimation = aboveMenuClip?.animation(forKey: "fluent.popup.clip.open") as? CABasicAnimation
let aboveMenuBorderFrom = (aboveMenuBorderAnimation?.fromValue as? NSValue)?.caTransform3DValue
let aboveMenuRootFrom = (aboveMenuRootAnimation?.fromValue as? NSValue)?.caTransform3DValue
let aboveMenuClipFrom = (aboveMenuClipAnimation?.fromValue as? NSValue)?.caTransform3DValue
let aboveMenuHeight = aboveMenuContent?.bounds.height ?? 0
require(
    aboveMenuPanel != nil
        && (aboveMenuPanel?.frame.minY ?? -CGFloat.infinity) >= aboveMenuAnchorRect.maxY - 1
        && aboveMenuRootAnimation?.keyPath == "transform"
        && aboveMenuBorderAnimation?.keyPath == "transform"
        && aboveMenuClipAnimation?.keyPath == "transform"
        && timingFunctionMatches(aboveMenuBorderAnimation?.timingFunction, FluentMotion.menuOpen.curve.timingFunction)
        && timingFunctionMatches(aboveMenuRootAnimation?.timingFunction, FluentMotion.menuOpen.curve.timingFunction)
        && timingFunctionMatches(aboveMenuClipAnimation?.timingFunction, FluentMotion.menuOpen.curve.timingFunction)
        && abs((aboveMenuRootFrom?.m42 ?? 0) + aboveMenuHeight * 0.5) < 0.0001
        && abs((aboveMenuClipFrom?.m42 ?? 0) - aboveMenuHeight * 0.5) < 0.0001
        && abs((aboveMenuRootFrom?.m42 ?? 0) + (aboveMenuClipFrom?.m42 ?? 0)) < 0.0001
        && abs((aboveMenuBorderFrom?.m22 ?? 0) - 0.5) < 0.0001
        && abs(aboveMenuBorderFrom?.m42 ?? 1) < 0.0001,
    "MenuFlyout mirrors the complete root and inverse clip geometry above its anchor "
        + "(panel=\(String(describing: aboveMenuPanel?.frame)), anchor=\(aboveMenuAnchorRect), "
        + "root=\(aboveMenuRootFrom?.m42 ?? .nan), clip=\(aboveMenuClipFrom?.m42 ?? .nan), "
        + "borderScale=\(aboveMenuBorderFrom?.m22 ?? .nan))"
)
aboveMenuFlyout.dismiss(animated: false)
require(menuFlyoutWindow.childWindows?.isEmpty != false, "above-anchor MenuFlyout dismisses immediately")
menuFlyoutWindow.orderOut(nil)

let highContrastMenuWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let highContrastMenuAnchor = NSButton(frame: NSRect(x: 20, y: 120, width: 140, height: 32))
highContrastMenuWindow.contentView = highContrastMenuAnchor
highContrastMenuWindow.center()
highContrastMenuWindow.orderFront(nil)
let highContrastMenuTheme = FluentTheme.custom(contrast: .high, colorScheme: .light)
let highContrastMenu = FluentMenuFlyout(
    items: [
        FluentMenuItem("Highlight", systemImageName: "star", keyEquivalent: "h") {},
        FluentMenuItem("Unavailable", isEnabled: false) {}
    ],
    theme: highContrastMenuTheme,
    reduceMotion: true
)
highContrastMenu.present(relativeTo: highContrastMenuAnchor)
let highContrastMenuPanel = highContrastMenuWindow.childWindows?.first
let highContrastMenuContent = highContrastMenuPanel?.contentView
let highContrastMenuRow = highContrastMenuContent.flatMap {
    firstView(withAccessibilityTitle: "Highlight", in: $0)
}
highContrastMenuRow?.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: 6, y: 16),
        in: highContrastMenuRow ?? highContrastMenuAnchor,
        eventNumber: 87
    )
)
highContrastMenuRow?.displayIfNeeded()
let highContrastMenuIcon = highContrastMenuRow.flatMap {
    views(identifier: "FluentKit.Menu.Item.Icon", in: $0).first as? NSImageView
}
let highContrastMenuBorder = highContrastMenuContent.flatMap {
    firstLayer(named: "FluentKit.MenuFlyout.PopupBorder", in: $0)
}
require(
    highContrastMenuBorder?.borderWidth == 2
        && colorMatches(highContrastMenuBorder?.borderColor, highContrastMenuTheme.controlStrokeStrong),
    "High Contrast MenuFlyout owns the source 2pt SystemColorWindowText presenter border"
)
require(
    colorMatches(highContrastMenuIcon?.contentTintColor?.cgColor, .selectedMenuItemTextColor),
    "High Contrast MenuFlyout applies HighlightText to its hovered icon slot"
)
highContrastMenu.dismiss(animated: false)
highContrastMenuWindow.orderOut(nil)

let teachingTipPresented = FluentState(wrappedValue: false)
var teachingTipDismissals = 0
let teachingTipAnchor = FluentButtonView("Teaching tip anchor")
    .teachingTip(
        isPresented: teachingTipPresented.projectedValue,
        placement: .top,
        size: NSSize(width: 280, height: 120),
        onDismiss: { teachingTipDismissals += 1 }
    ) {
        FluentText("Initial teaching tip")
    }
let teachingTipHost = FluentViewHost(
    teachingTipAnchor,
    context: FluentRenderContext(reduceMotion: true)
)
let teachingTipAnchorIdentity = firstButton(in: teachingTipHost)
let teachingTipWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
teachingTipWindow.contentView = teachingTipHost
teachingTipWindow.orderFront(nil)
teachingTipPresented.wrappedValue = true
drainMainQueue()
require(teachingTipHost.subviews.count == 1, "teaching tip keeps its anchor content mounted")
require(firstButton(in: teachingTipHost) === teachingTipAnchorIdentity, "teaching tip presentation preserves anchor native identity")
require(
    waitUntil(timeout: 0.20) { teachingTipWindow.childWindows?.count == 1 },
    "teaching tip presents an application-owned child panel"
)
require(
    teachingTipWindow.childWindows?.first?.contentView?.accessibilityLabel() == "Teaching tip",
    "teaching tip exposes a semantic presentation group"
)
let reduceMotionTeachingTipChrome = teachingTipWindow.childWindows?.first?.contentView
require(
    teachingTipWindow.childWindows?.first?.alphaValue == 1
        && reduceMotionTeachingTipChrome?.layer?.opacity == 1
        && reduceMotionTeachingTipChrome?.layer?.animationKeys()?.isEmpty != false,
    "Reduce Motion TeachingTip resolves one chrome-layer transition without a panel opacity animator"
)
let updatedTeachingTip = FluentButtonView("Teaching tip anchor")
    .teachingTip(
        isPresented: teachingTipPresented.projectedValue,
        placement: .bottom,
        size: NSSize(width: 300, height: 128),
        onDismiss: { teachingTipDismissals += 1 }
    ) {
        FluentText("Updated teaching tip")
    }
require(
    updatedTeachingTip._update(teachingTipHost.subviews[0], in: FluentRenderContext(reduceMotion: true)),
    "teaching tip updates compatible anchor and presented content in place"
)
drainMainQueue()
require(
    firstLabel(in: teachingTipWindow.childWindows?.first?.contentView ?? NSView())?.stringValue == "Updated teaching tip",
    "teaching tip refreshes presented declarative content"
)
teachingTipPresented.wrappedValue = false
drainMainQueue()
require(teachingTipWindow.childWindows?.isEmpty != false, "teaching tip removes its child panel when binding becomes false")
require(teachingTipDismissals == 1, "teaching tip reports completed dismissal once")
teachingTipWindow.orderOut(nil)

let animatedTeachingTipPresented = FluentState(wrappedValue: false)
var animatedTeachingTipDismissals = 0
let animatedTeachingTipHost = FluentButtonView("Animated teaching tip anchor")
    .teachingTip(
        isPresented: animatedTeachingTipPresented.projectedValue,
        placement: .top,
        size: NSSize(width: 280, height: 120),
        onDismiss: { animatedTeachingTipDismissals += 1 }
    ) {
        FluentText("Animated teaching tip")
    }
    ._mount(in: FluentRenderContext(reduceMotion: false))
let animatedTeachingTipWindow = NSWindow(
    contentRect: NSRect(x: 120, y: 120, width: 360, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
animatedTeachingTipWindow.contentView = animatedTeachingTipHost
animatedTeachingTipWindow.orderFront(nil)
animatedTeachingTipPresented.wrappedValue = true
drainMainQueue()
guard let animatedTeachingTipPanel = animatedTeachingTipWindow.childWindows?.first,
      let animatedTeachingTipChrome = animatedTeachingTipPanel.contentView,
      let animatedTeachingTipLayer = animatedTeachingTipChrome.layer,
      let teachingTipOpacity = animatedTeachingTipLayer.animation(
        forKey: "fluent.teachingTip.opacity"
      ) as? CABasicAnimation,
      let teachingTipTransform = animatedTeachingTipLayer.animation(
        forKey: "fluent.teachingTip.transform"
      ) as? CABasicAnimation,
      let teachingTipShadow = animatedTeachingTipLayer.animation(
        forKey: "fluent.teachingTip.shadow"
      ) as? CABasicAnimation else {
    require(false, "animated TeachingTip submits opacity, transform, and shadow as one layer batch")
    fatalError("unreachable")
}
require(
    animatedTeachingTipPanel.alphaValue == 1
        && teachingTipOpacity.duration == FluentMotion.teachingTipOpen.duration
        && teachingTipTransform.duration == FluentMotion.teachingTipOpen.duration
        && teachingTipShadow.duration == FluentMotion.teachingTipOpen.duration
        && timingFunctionMatches(teachingTipOpacity.timingFunction, FluentMotion.teachingTipOpen.curve.timingFunction)
        && timingFunctionMatches(teachingTipTransform.timingFunction, FluentMotion.teachingTipOpen.curve.timingFunction)
        && timingFunctionMatches(teachingTipShadow.timingFunction, FluentMotion.teachingTipOpen.curve.timingFunction),
    "TeachingTip coordinates chrome opacity, transform, and shadow on one motion timeline"
)
require(
    animatedTeachingTipChrome.identifier?.rawValue == "FluentKit.TeachingTip.Chrome",
    "TeachingTip keeps its tail in the independently drawn chrome surface"
)
if let compactValue = teachingTipTransform.fromValue as? NSValue {
    let compact = compactValue.caTransform3DValue
    let bounds = animatedTeachingTipLayer.bounds
    let anchor = CGPoint(
        x: bounds.minX + bounds.width * animatedTeachingTipLayer.anchorPoint.x,
        y: bounds.minY + bounds.height * animatedTeachingTipLayer.anchorPoint.y
    )
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let transformedCenter = CGPoint(
        x: anchor.x + (center.x - anchor.x) * compact.m11 + compact.m41,
        y: anchor.y + (center.y - anchor.y) * compact.m22 + compact.m42
    )
    require(
        abs(compact.m11 - FluentMotion.teachingTipOpen.scale) <= 0.001
            && abs(transformedCenter.x - center.x) <= 0.001
            && abs((transformedCenter.y - center.y) + FluentMotion.teachingTipOpen.distance) <= 0.001,
        "TeachingTip compensates AppKit's panel-content anchor and scales around the chrome center"
    )
} else {
    require(false, "TeachingTip exposes its compact transform for center-geometry validation")
}
let teachingTipFrameDuringOpen = animatedTeachingTipPanel.frame
animatedTeachingTipHost.needsLayout = true
animatedTeachingTipHost.layoutSubtreeIfNeeded()
require(
    animatedTeachingTipPanel.frame == teachingTipFrameDuringOpen,
    "TeachingTip host layout does not reposition the child panel during its coordinated transition"
)
animatedTeachingTipPresented.wrappedValue = false
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
animatedTeachingTipPresented.wrappedValue = true
require(
    waitUntil(timeout: 0.40) {
        animatedTeachingTipWindow.childWindows?.first === animatedTeachingTipPanel
            && animatedTeachingTipLayer.opacity == 1
    },
    "TeachingTip reverses a closing transition from its presentation state without replacing the panel"
)
require(
    animatedTeachingTipDismissals == 0,
    "a cancelled TeachingTip close completion cannot dismiss the newly reopened presentation"
)
animatedTeachingTipPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.30) { animatedTeachingTipWindow.childWindows?.isEmpty != false },
    "TeachingTip removes the panel only after the active coordinated close completes"
)
require(animatedTeachingTipDismissals == 1, "TeachingTip invokes onDismiss once for the completed close generation")
animatedTeachingTipWindow.orderOut(nil)

let popoverPresented = FluentState(wrappedValue: false)
var popoverDismissals = 0
let popoverAnchor = FluentButtonView("Popover anchor")
    .popover(
        isPresented: popoverPresented.projectedValue,
        placement: .bottom,
        size: NSSize(width: 280, height: 180),
        onDismiss: { popoverDismissals += 1 }
    ) {
        FluentText("Initial popover content")
    }
let popoverHost = popoverAnchor._mount(in: FluentRenderContext(reduceMotion: true))
let popoverWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
popoverWindow.contentView = popoverHost
popoverWindow.makeKeyAndOrderFront(nil)
popoverPresented.wrappedValue = true
drainMainQueue()
guard let popoverMaterial = NSApp.windows.lazy.compactMap({ firstView(identifier: "FluentKit.Popover.Content", in: $0.contentView ?? NSView()) as? FluentMaterialView }).first else {
    require(false, "declarative popover presents a Liquid Glass content host")
    fatalError("unreachable")
}
let popoverContentWindow = popoverMaterial.window
require(popoverContentWindow != nil && popoverContentWindow !== popoverWindow, "popover content is hosted in a native NSPopover window")
require(popoverMaterial.isMaterialEnabled, "popover content enables the theme material surface")
require(
    waitUntil(timeout: 0.5) {
        popoverMaterial.window?.contentView?.frame.size == NSSize(width: 280, height: 180)
    },
    "popover honors its initial requested content size (window: \(popoverMaterial.window?.contentView?.frame.size ?? .zero), material: \(popoverMaterial.frame.size), parent: \(popoverMaterial.superview?.frame.size ?? .zero), fitting: \(popoverMaterial.superview?.fittingSize ?? .zero))"
)
let popoverMaterialIdentity = popoverMaterial
let updatedPopover = FluentButtonView("Popover anchor")
    .popover(
        isPresented: popoverPresented.projectedValue,
        placement: .trailing,
        size: NSSize(width: 280, height: 180),
        onDismiss: { popoverDismissals += 1 }
    ) {
        FluentText("Updated popover content")
    }
require(
    updatedPopover._update(popoverHost, in: FluentRenderContext(theme: .current.with(materialEffectsEnabled: false), reduceMotion: true)),
    "popover updates its compatible anchor and content in place"
)
drainMainQueue()
guard let updatedPopoverMaterial = NSApp.windows.lazy.compactMap({ firstView(identifier: "FluentKit.Popover.Content", in: $0.contentView ?? NSView()) as? FluentMaterialView }).first else {
    require(false, "popover keeps its content host during update")
    fatalError("unreachable")
}
require(updatedPopoverMaterial === popoverMaterialIdentity, "popover preserves its native content identity during updates")
require(!updatedPopoverMaterial.isMaterialEnabled, "popover updates the global material switch in place")
require(
    firstLabel(in: updatedPopoverMaterial.window?.contentView ?? NSView())?.stringValue == "Updated popover content",
    "popover refreshes declarative content in place (labels: \(labels(in: updatedPopoverMaterial.window?.contentView ?? NSView()).map(\.stringValue)))"
)
require(
    waitUntil(timeout: 0.5) {
        updatedPopoverMaterial.window?.contentView?.frame.size == NSSize(width: 280, height: 180)
    },
    "popover preserves its content size during same-geometry updates (actual: \(updatedPopoverMaterial.window?.contentView?.frame.size ?? .zero), contentMin: \(updatedPopoverMaterial.window?.contentMinSize ?? .zero), min: \(updatedPopoverMaterial.window?.minSize ?? .zero))"
)
let resizedPopover = FluentButtonView("Popover anchor")
    .popover(
        isPresented: popoverPresented.projectedValue,
        placement: .trailing,
        size: NSSize(width: 320, height: 200),
        onDismiss: { popoverDismissals += 1 }
    ) {
        FluentText("Resized popover content")
    }
require(resizedPopover._update(popoverHost, in: FluentRenderContext(theme: .current.with(materialEffectsEnabled: false), reduceMotion: true)), "popover accepts a geometry update")
require(
    waitUntil(timeout: 0.5) {
        NSApp.windows.contains { window in
            guard let material = firstView(identifier: "FluentKit.Popover.Content", in: window.contentView ?? NSView()) as? FluentMaterialView else { return false }
            return material !== popoverMaterialIdentity && material.window?.contentView?.frame.size == NSSize(width: 320, height: 200)
        }
    },
    "popover replaces its native presenter when AppKit cannot resize a live content controller"
)
popoverPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.5) {
        popoverDismissals == 1 && NSApp.windows.allSatisfy {
            !$0.isVisible || firstView(identifier: "FluentKit.Popover.Content", in: $0.contentView ?? NSView()) == nil
        }
    },
    "popover closes its native window when the binding becomes false"
)
require(popoverDismissals == 1, "popover invokes onDismiss exactly once (actual: \(popoverDismissals))")
popoverWindow.orderOut(nil)

let dialogPresented = FluentState(wrappedValue: false)
let dialog = FluentText("Dialog host").confirmationDialog("Confirm", isPresented: dialogPresented.projectedValue) {
    FluentDialogAction("OK")
}
require(dialog._mount(in: FluentRenderContext()).subviews.count == 1, "confirmation dialog keeps content mounted")

let sheetPresented = FluentState(wrappedValue: false)
let sheet = FluentText("Sheet host")
    .sheet(isPresented: sheetPresented.projectedValue, title: "Editor", size: NSSize(width: 420, height: 280)) {
        FluentText("Sheet content")
    }
let sheetView = sheet._mount(in: FluentRenderContext())
require(sheetView.subviews.count == 1, "sheet keeps its presenting content mounted")
let sheetContentIdentity = sheetView.subviews.first
let updatedSheet = FluentText("Updated sheet host")
    .sheet(isPresented: sheetPresented.projectedValue, title: "Updated editor", size: NSSize(width: 460, height: 300)) {
        FluentText("Updated sheet content")
    }
require(updatedSheet._update(sheetView, in: FluentRenderContext()), "sheet updates compatible presenting content in place")
require(sheetView.subviews.first === sheetContentIdentity, "sheet preserves the presenting native host during updates")
require(sheetPresented.wrappedValue == false, "sheet does not present until its binding is enabled")

let sheetDismissals = FluentState(wrappedValue: false)
var sheetDismissalCount = 0
let coordinatedSheet = FluentButtonView("Sheet focus anchor")
    .sheet(
        isPresented: sheetDismissals.projectedValue,
        title: "Coordinated editor",
        size: NSSize(width: 420, height: 280),
        onDismiss: { sheetDismissalCount += 1 }
    ) {
        FluentText("Coordinated sheet content")
    }
let coordinatedSheetView = coordinatedSheet._mount(in: FluentRenderContext())
let coordinatedSheetWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
coordinatedSheetWindow.contentView = coordinatedSheetView
coordinatedSheetWindow.makeKeyAndOrderFront(nil)
sheetDismissals.wrappedValue = true
drainMainQueue()
guard let attachedSheet = coordinatedSheetWindow.attachedSheet else {
    require(false, "sheet coordinator attaches the native sheet after binding presentation")
    fatalError("unreachable")
}
require(attachedSheet.title == "Coordinated editor", "sheet coordinator applies its title on presentation")
require(
    attachedSheet.contentRect(forFrameRect: attachedSheet.frame).size == NSSize(width: 420, height: 280),
    "sheet coordinator applies its requested content size (actual: \(attachedSheet.contentRect(forFrameRect: attachedSheet.frame).size))"
)
let updatedCoordinatedSheet = FluentButtonView("Sheet focus anchor")
    .sheet(
        isPresented: sheetDismissals.projectedValue,
        title: "Updated coordinated editor",
        size: NSSize(width: 460, height: 300)
    ) {
        FluentText("Updated coordinated sheet content")
    }
require(
    updatedCoordinatedSheet._update(coordinatedSheetView, in: FluentRenderContext(theme: .current.with(materialEffectsEnabled: false))),
    "sheet coordinator updates a presented sheet in place"
)
drainMainQueue()
require(coordinatedSheetWindow.attachedSheet === attachedSheet, "sheet updates preserve the attached native window")
require(attachedSheet.title == "Updated coordinated editor", "sheet updates refresh its title in place")
require(
    attachedSheet.contentRect(forFrameRect: attachedSheet.frame).size == NSSize(width: 460, height: 300),
    "sheet updates refresh its content size in place (actual: \(attachedSheet.contentRect(forFrameRect: attachedSheet.frame).size))"
)
require(
    firstMaterialView(in: attachedSheet.contentView ?? NSView())?.isMaterialEnabled == false,
    "sheet updates propagate the global material switch"
)
sheetDismissals.wrappedValue = false
drainMainQueue()
require(coordinatedSheetWindow.attachedSheet == nil, "sheet coordinator dismisses the native sheet from its binding")
require(sheetDismissalCount == 1, "sheet coordinator invokes onDismiss once for a completed dismissal")
coordinatedSheetWindow.orderOut(nil)

let queuedSheetPresented = FluentState(wrappedValue: false)
let queuedConfirmationPresented = FluentState(wrappedValue: false)
let mixedPresentationHost = FluentButtonView("Mixed presentation anchor")
    .sheet(isPresented: queuedSheetPresented.projectedValue, title: "Queued sheet", size: NSSize(width: 360, height: 220)) {
        FluentText("First presentation")
    }
    .confirmationDialog(
        "Queued confirmation",
        isPresented: queuedConfirmationPresented.projectedValue,
        message: "Second presentation"
    ) {
        FluentDialogAction("OK")
    }
    ._mount(in: FluentRenderContext())
let mixedPresentationWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
mixedPresentationWindow.contentView = mixedPresentationHost
mixedPresentationWindow.orderFront(nil)
queuedSheetPresented.wrappedValue = true
queuedConfirmationPresented.wrappedValue = true
drainMainQueue()
let firstMixedSheet = mixedPresentationWindow.attachedSheet
require(firstMixedSheet?.title == "Queued sheet", "custom Sheet wins the first requested window presentation slot")
queuedSheetPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.5) {
        guard let attached = mixedPresentationWindow.attachedSheet else { return false }
        return attached !== firstMixedSheet
    },
    "ConfirmationDialog waits until the custom Sheet releases the window"
)
let secondMixedSheet = mixedPresentationWindow.attachedSheet
require(
    labels(in: secondMixedSheet?.contentView ?? NSView()).contains { $0.stringValue == "Queued confirmation" },
    "queued ConfirmationDialog preserves its native NSAlert content"
)
queuedConfirmationPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.5) { mixedPresentationWindow.attachedSheet == nil },
    "mixed presentation queue dismisses its current native sheet"
)
mixedPresentationWindow.orderOut(nil)

let contentDialogPresented = FluentState(wrappedValue: false)
let contentDialogLightTheme = FluentTheme.current.with(colorScheme: .light)
let contentDialogDarkTheme = FluentTheme.current.with(colorScheme: .dark)
let contentDialogAppearanceCoordinator = FluentAppearanceCoordinator(theme: contentDialogLightTheme)

do {
    let previousApplicationAppearance = NSApp.appearance
    let systemAppearanceWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let systemAppearanceCoordinator = FluentAppearanceCoordinator(theme: FluentTheme())
    systemAppearanceCoordinator.attach(to: systemAppearanceWindow)
    let systemThemeStore = FluentThemeStore(FluentTheme())
    systemAppearanceCoordinator.bind(to: systemThemeStore)
    let systemThemeHost = FluentViewHost(
        FluentText("System appearance probe").fluentTheme(systemThemeStore),
        context: FluentRenderContext(
            theme: systemAppearanceCoordinator.theme,
            appearanceCoordinator: systemAppearanceCoordinator
        )
    )
    systemAppearanceWindow.contentView = systemThemeHost
    var resolvedThemes: [FluentTheme] = []
    let registration = systemAppearanceCoordinator.register(owner: systemAppearanceWindow) {
        resolvedThemes.append($0)
    }
    systemAppearanceWindow.makeKeyAndOrderFront(nil)
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let resolvedDark = waitUntil(timeout: 0.35) {
        systemAppearanceCoordinator.theme.colorScheme == .dark
    }
    NSApp.appearance = NSAppearance(named: .aqua)
    let resolvedLight = waitUntil(timeout: 0.35) {
        systemAppearanceCoordinator.theme.colorScheme == .light
    }
    require(
        resolvedDark && resolvedLight
            && resolvedThemes.contains(where: { $0.colorScheme == .dark })
            && resolvedThemes.contains(where: { $0.colorScheme == .light })
            && firstLabel(in: systemThemeHost)?.textColor?.isEqual(systemAppearanceCoordinator.theme.textPrimary) == true,
        "system appearance coordinator resolves and broadcasts automatic Light/Dark changes without rebinding recursion"
    )
    systemAppearanceCoordinator.unregister(registration)
    systemAppearanceWindow.orderOut(nil)
    NSApp.appearance = previousApplicationAppearance
    drainMainQueue()
}

do {
    let manualThemeWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let manualCoordinator = FluentAppearanceCoordinator(theme: FluentTheme())
    manualCoordinator.attach(to: manualThemeWindow)
    let manualStore = FluentThemeStore(
        preference: .system,
        resolvedTheme: manualCoordinator.resolvedTheme
    )
    manualCoordinator.bind(to: manualStore)
    let initialGeneration = manualCoordinator.themeGeneration
    manualStore.preference = .dark
    require(
        manualCoordinator.preference == .dark
            && manualCoordinator.resolvedTheme.colorScheme == .dark
            && manualCoordinator.themeGeneration > initialGeneration,
        "manual Dark preference uses the same coordinator transaction and advances theme generation"
    )
    manualStore.preference = .light
    require(
        manualCoordinator.preference == .light
            && manualCoordinator.resolvedTheme.colorScheme == .light,
        "manual Light preference updates the resolved window theme"
    )
    manualStore.preference = .system
    require(
        manualCoordinator.preference == .system
            && manualCoordinator.resolvedTheme.colorScheme != .system,
        "returning to System preserves the requested preference without leaking it into controls"
    )
    manualThemeWindow.orderOut(nil)
}

do {
    let transactionWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let transactionRoot = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
    let directButton = FluentButton(title: "Direct")
    directButton.frame = NSRect(x: 20, y: 100, width: 120, height: 32)
    let directMaterial = FluentMaterialView(material: .mica)
    directMaterial.frame = NSRect(x: 160, y: 20, width: 160, height: 120)
    transactionRoot.addSubview(directButton)
    transactionRoot.addSubview(directMaterial)
    transactionWindow.contentView = transactionRoot

    let transactionCoordinator = FluentAppearanceCoordinator(theme: FluentTheme.current.with(colorScheme: .light))
    transactionCoordinator.attach(to: transactionWindow)
    var transactionEvents: [String] = []
    let firstOwner = NSObject()
    let secondOwner = NSObject()
    let lateOwner = NSObject()
    var secondRegistration: UUID?
    _ = transactionCoordinator.register(
        owner: firstOwner,
        updateImmediately: false,
        prepareForAppearanceChange: { transactionEvents.append("prepare-first") }
    ) { _ in
        transactionEvents.append("apply-first")
        if let secondRegistration { transactionCoordinator.unregister(secondRegistration) }
        _ = transactionCoordinator.register(owner: lateOwner, updateImmediately: false) { _ in
            transactionEvents.append("apply-late")
        }
    }
    secondRegistration = transactionCoordinator.register(
        owner: secondOwner,
        updateImmediately: false,
        prepareForAppearanceChange: { transactionEvents.append("prepare-second") }
    ) { _ in
        transactionEvents.append("apply-second")
    }
    let lightEventCount = transactionEvents.count
    transactionCoordinator.updateTheme(FluentTheme.current.with(colorScheme: .dark))
    drainMainQueue()
    require(
        transactionEvents == ["prepare-first", "prepare-second", "apply-first", "apply-second"],
        "appearance changes use a stable registration snapshot and prepare every participant before apply"
    )
    transactionCoordinator.updateTheme(FluentTheme.current.with(colorScheme: .dark))
    drainMainQueue()
    require(
        transactionEvents.count == lightEventCount + 4,
        "a resolved theme that did not change does not broadcast a second appearance transaction"
    )
    let darkButtonAppearance = FluentAutomaticButtonStyle().appearance(
        for: FluentButtonStyleConfiguration(
            title: directButton.title,
            role: directButton.role,
            controlState: .normal,
            isEnabled: true,
            theme: transactionCoordinator.theme
        )
    )
    require(
        directButton.theme == transactionCoordinator.theme
            && colorMatches(directButton.layer?.backgroundColor, darkButtonAppearance.backgroundColor)
            && directMaterial.fluentTheme == transactionCoordinator.theme
            && directMaterial.fallbackColor.isEqual(transactionCoordinator.theme.windowBackground),
        "direct AppKit Fluent controls and material layers receive the coordinator theme in place"
    )
    transactionWindow.orderOut(nil)
}

var contentDialogClosingCount = 0
var contentDialogCancelNextClose = true
var contentDialogDeferNextClose = false
var contentDialogDeferral: FluentContentDialogClosingDeferral?
var contentDialogClosedResults: [FluentContentDialogResult] = []
let contentDialogHost = FluentButtonView("Content dialog focus anchor")
    .contentDialog(
        "Save changes?",
        isPresented: contentDialogPresented.projectedValue,
        primaryButtonText: "Save",
        secondaryButtonText: "Don't save",
        closeButtonText: "Cancel",
        defaultButton: .primary,
        onClosing: { args in
            contentDialogClosingCount += 1
            if contentDialogCancelNextClose {
                contentDialogCancelNextClose = false
                args.isCancelled = true
            } else if contentDialogDeferNextClose {
                contentDialogDeferNextClose = false
                contentDialogDeferral = args.getDeferral()
            }
        },
        onClosed: { contentDialogClosedResults.append($0) }
    ) {
        FluentText("The document has unsaved changes.")
    }
    ._mount(in: FluentRenderContext(
        theme: contentDialogLightTheme,
        reduceMotion: false,
        appearanceCoordinator: contentDialogAppearanceCoordinator
    ))
let contentDialogWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
contentDialogWindow.contentView = contentDialogHost
contentDialogAppearanceCoordinator.attach(to: contentDialogWindow)
contentDialogWindow.makeKeyAndOrderFront(nil)
guard let contentDialogFocusAnchor = firstButton(in: contentDialogHost) else {
    require(false, "ContentDialog preserves its presenting button")
    fatalError("unreachable")
}
contentDialogWindow.makeFirstResponder(contentDialogFocusAnchor)
contentDialogPresented.wrappedValue = true
require(
    waitUntil(timeout: 0.30) {
        firstView(identifier: "FluentKit.ContentDialog.Overlay", in: contentDialogWindow.contentView ?? NSView()) != nil
    },
    "ContentDialog presents an in-window modal overlay from its binding"
)
guard let contentDialogOverlay = firstView(
    identifier: "FluentKit.ContentDialog.Overlay",
    in: contentDialogWindow.contentView ?? NSView()
), let contentDialogSurface = firstView(
    identifier: "FluentKit.ContentDialog.Surface",
    in: contentDialogOverlay
), let contentDialogDimming = firstView(
    identifier: "FluentKit.ContentDialog.DimmingLayer",
    in: contentDialogOverlay
), let contentDialogMaterial = firstMaterialView(in: contentDialogSurface),
      let contentDialogContentSurface = firstView(
        identifier: "FluentKit.ContentDialog.ContentSurface",
        in: contentDialogSurface
      ),
      let contentDialogCommandSurface = firstView(
        identifier: "FluentKit.ContentDialog.CommandSurface",
        in: contentDialogSurface
      ),
      let contentDialogCommandSeparator = firstView(
        identifier: "FluentKit.ContentDialog.CommandSeparator",
        in: contentDialogSurface
      ),
      let contentDialogPrimary = firstView(
        identifier: "FluentKit.ContentDialog.primary",
        in: contentDialogSurface
      ) as? FluentButton else {
    require(false, "ContentDialog builds its dimming, material, and action surfaces")
    fatalError("unreachable")
}
let contentDialogSecondary = firstView(withAccessibilityTitle: "Don't save", in: contentDialogSurface)
let contentDialogClose = firstView(withAccessibilityTitle: "Cancel", in: contentDialogSurface)
contentDialogWindow.contentView?.layoutSubtreeIfNeeded()
require(
    contentDialogSurface.frame.width >= 446 && contentDialogSurface.frame.width <= 548
        && contentDialogSurface.frame.height >= 184 && contentDialogSurface.frame.height <= 756,
    "ContentDialog applies the WinUI min/max geometry (actual: \(contentDialogSurface.frame))"
)
let contentDialogSurfaceBounds = contentDialogSurface.bounds.insetBy(dx: 0.5, dy: 0.5)
let contentDialogActionViews = [contentDialogPrimary, contentDialogSecondary, contentDialogClose].compactMap { $0 }
let contentDialogOpeningFrame = contentDialogSurface.frame
let contentDialogOpeningLayerFrame = contentDialogSurface.layer?.frame ?? .zero
let contentDialogOpeningPresentationFrame = contentDialogSurface.layer?.presentation()?.frame
    ?? contentDialogOpeningLayerFrame
let contentDialogInitialScaleAnimation = contentDialogSurface.layer?.animation(
    forKey: "fluent.contentDialog.scale"
) as? CABasicAnimation
let contentDialogInitialTransform = (contentDialogInitialScaleAnimation?.fromValue as? NSValue)?
    .caTransform3DValue
let contentDialogInitialPivot = CGPoint(
    x: contentDialogSurface.layer?.bounds.midX ?? 0,
    y: contentDialogSurface.layer?.bounds.midY ?? 0
)
let contentDialogInitialAnchor = CGPoint(
    x: (contentDialogSurface.layer?.bounds.minX ?? 0)
        + (contentDialogSurface.layer?.bounds.width ?? 0) * (contentDialogSurface.layer?.anchorPoint.x ?? 0),
    y: (contentDialogSurface.layer?.bounds.minY ?? 0)
        + (contentDialogSurface.layer?.bounds.height ?? 0) * (contentDialogSurface.layer?.anchorPoint.y ?? 0)
)
let contentDialogInitialTranslation = CGPoint(
    x: (contentDialogInitialPivot.x - contentDialogInitialAnchor.x) * (1 - 1.05),
    y: (contentDialogInitialPivot.y - contentDialogInitialAnchor.y) * (1 - 1.05)
)
require(
    contentDialogActionViews.count == 3
        && contentDialogActionViews.allSatisfy {
            contentDialogSurfaceBounds.contains($0.convert($0.bounds, to: contentDialogSurface))
        },
    "ContentDialog keeps every command button fully inside its clipped surface"
)
require(
    abs(contentDialogOpeningLayerFrame.minX - contentDialogOpeningFrame.minX) < 0.001
        && abs(contentDialogOpeningLayerFrame.minY - contentDialogOpeningFrame.minY) < 0.001
        && abs(contentDialogOpeningLayerFrame.width - contentDialogOpeningFrame.width) < 0.001
        && abs(contentDialogOpeningLayerFrame.height - contentDialogOpeningFrame.height) < 0.001
        && abs(contentDialogOpeningPresentationFrame.midX - contentDialogOpeningFrame.midX) < 0.001
        && abs(contentDialogOpeningPresentationFrame.midY - contentDialogOpeningFrame.midY) < 0.001
        && abs((contentDialogInitialScaleAnimation?.duration ?? 0) - FluentMotion.contentDialogOpen.duration) < 0.001
        && contentDialogInitialScaleAnimation?.keyPath == "transform"
        && abs((contentDialogInitialTransform?.m11 ?? 0) - 1.05) < 0.001
        && abs((contentDialogInitialTransform?.m22 ?? 0) - 1.05) < 0.001
        && abs((contentDialogInitialTransform?.m41 ?? .nan) - contentDialogInitialTranslation.x) < 0.001
        && abs((contentDialogInitialTransform?.m42 ?? .nan) - contentDialogInitialTranslation.y) < 0.001,
    "ContentDialog preserves its model frame and visual center while installing the 1.05 opening scale"
)
require(
    contentDialogMaterial.materialStyle == .liquidGlass
        && contentDialogMaterial.isMaterialEnabled
        && contentDialogMaterial.layer?.cornerRadius == 0
        && contentDialogSurface.layer?.cornerRadius == 8
        && contentDialogSurface.layer?.masksToBounds == true
        && colorMatches(
            contentDialogContentSurface.layer?.backgroundColor,
            contentDialogLightTheme.contentDialogContentFill
        )
        && colorMatches(
            contentDialogCommandSurface.layer?.backgroundColor,
            contentDialogLightTheme.contentDialogCommandFill
        )
        && colorMatches(
            contentDialogCommandSeparator.layer?.backgroundColor,
            contentDialogLightTheme.divider
        )
        && colorMatches(
            contentDialogDimming.layer?.backgroundColor,
            contentDialogLightTheme.contentDialogSmokeFill
        ),
    "ContentDialog uses one 8pt outer clip, black smoke, and separate content/command surfaces"
)
contentDialogAppearanceCoordinator.updateTheme(contentDialogDarkTheme)
drainMainQueue()
require(
    firstView(
        identifier: "FluentKit.ContentDialog.Overlay",
        in: contentDialogWindow.contentView ?? NSView()
    ) === contentDialogOverlay
        && colorMatches(
            contentDialogContentSurface.layer?.backgroundColor,
            contentDialogDarkTheme.contentDialogContentFill
        )
        && colorMatches(
            contentDialogCommandSurface.layer?.backgroundColor,
            contentDialogDarkTheme.contentDialogCommandFill
        )
        && colorMatches(
            contentDialogDimming.layer?.backgroundColor,
            contentDialogDarkTheme.contentDialogSmokeFill
        ),
    "ContentDialog updates its presented surfaces in place with the window appearance coordinator"
)
require(
    labels(in: contentDialogSurface).first(where: { $0.stringValue == "Save changes?" })?.font?.pointSize == 20,
    "ContentDialog uses WinUI's 20pt title typography"
)
require(
    contentDialogPrimary.role == .primary
        && contentDialogPrimary.keyEquivalent == "\r",
    "ContentDialog applies the configured default button"
)
let contentDialogScaleAnimation = contentDialogSurface.layer?.animation(
    forKey: "fluent.contentDialog.scale"
) as? CABasicAnimation
let contentDialogOpacityAnimation = contentDialogSurface.layer?.animation(
    forKey: "fluent.contentDialog.opacity"
) as? CABasicAnimation
let contentDialogDimmingAnimation = contentDialogDimming.layer?.animation(
    forKey: "fluent.contentDialog.dimming"
) as? CABasicAnimation
require(
    contentDialogScaleAnimation == nil
        && contentDialogOpacityAnimation == nil
        && contentDialogDimmingAnimation == nil
        && abs((contentDialogSurface.layer?.presentation()?.transform.m11 ?? 1) - 1) < 0.001
        && abs((contentDialogSurface.layer?.presentation()?.transform.m22 ?? 1) - 1) < 0.001
        && contentDialogSurface.layer?.opacity == 1
        && contentDialogDimming.layer?.opacity == 1,
    "ContentDialog settles its opening timeline before applying a new appearance"
)
require(
    contentDialogSurface.layer?.animationKeys()?.isEmpty != false
        && contentDialogDimming.layer?.animationKeys()?.isEmpty != false,
    "ContentDialog leaves no stale opacity or dimming animation after an appearance change"
)
require(
    waitUntil(timeout: 0.35) { contentDialogWindow.firstResponder === contentDialogPrimary },
    "ContentDialog moves focus to the default button after its opening transition"
)
contentDialogWindow.contentView?.layoutSubtreeIfNeeded()
require(
    contentDialogSurface.frame == contentDialogOpeningFrame
        && contentDialogActionViews.allSatisfy {
            contentDialogSurfaceBounds.contains($0.convert($0.bounds, to: contentDialogSurface))
        },
    "ContentDialog commits its complete command layout before motion and does not resize when opening ends"
)

contentDialogPrimary.performClick(nil)
drainMainQueue()
require(
    contentDialogClosingCount == 1
        && contentDialogPresented.wrappedValue
        && firstView(identifier: "FluentKit.ContentDialog.Overlay", in: contentDialogWindow.contentView ?? NSView()) === contentDialogOverlay
        && contentDialogPrimary.isEnabled
        && contentDialogClosedResults.isEmpty,
    "ContentDialog closing validation can cancel a button dismissal without replacing the presenter"
)

contentDialogDeferNextClose = true
contentDialogPrimary.performClick(nil)
drainMainQueue()
require(
    contentDialogClosingCount == 2
        && contentDialogDeferral != nil
        && contentDialogPresented.wrappedValue
        && !contentDialogPrimary.isEnabled,
    "ContentDialog keeps its overlay open and disables actions while a closing deferral is pending"
)
contentDialogDeferral?.complete()
contentDialogDeferral = nil
require(!contentDialogPresented.wrappedValue, "ContentDialog commits its binding only after the closing deferral completes")
let contentDialogCloseScale = contentDialogSurface.layer?.animation(
    forKey: "fluent.contentDialog.scale"
) as? CABasicAnimation
require(
    abs((contentDialogCloseScale?.duration ?? 0) - FluentMotion.contentDialogClose.duration) < 0.001,
    "ContentDialog closing scale uses WinUI's 167ms transition and replaces the opening timeline"
)
require(
    waitUntil(timeout: 0.40) {
        firstView(identifier: "FluentKit.ContentDialog.Overlay", in: contentDialogWindow.contentView ?? NSView()) == nil
    },
    "ContentDialog removes its overlay after the coordinated closing transition"
)
require(
    contentDialogClosedResults == [.primary]
        && contentDialogWindow.firstResponder === contentDialogFocusAnchor,
    "ContentDialog reports its result once and restores the pre-dialog focus"
)

contentDialogPresented.wrappedValue = true
require(
    waitUntil(timeout: 0.30) {
        firstView(identifier: "FluentKit.ContentDialog.Overlay", in: contentDialogWindow.contentView ?? NSView()) != nil
    },
    "ContentDialog can be presented again after its coordinator slot is released"
)
guard let interruptedContentDialogOverlay = firstView(
    identifier: "FluentKit.ContentDialog.Overlay",
    in: contentDialogWindow.contentView ?? NSView()
), let interruptedContentDialogSurface = firstView(
    identifier: "FluentKit.ContentDialog.Surface",
    in: interruptedContentDialogOverlay
) else {
    require(false, "reopened ContentDialog exposes its transition surface")
    fatalError("unreachable")
}
contentDialogPresented.wrappedValue = false
var observedInterruptedCloseTransform: CATransform3D?
var observedInterruptedCloseKeyPath: String?
let observedInterruptedCloseAnimation = waitUntil(timeout: 0.50) {
    guard let animation = interruptedContentDialogSurface.layer?.animation(
        forKey: "fluent.contentDialog.scale"
    ) as? CABasicAnimation else { return false }
    guard let transform = (animation.toValue as? NSValue)?.caTransform3DValue else { return false }
    observedInterruptedCloseTransform = transform
    observedInterruptedCloseKeyPath = animation.keyPath
    guard let layer = interruptedContentDialogSurface.layer else { return false }
    let pivot = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
    let anchor = CGPoint(
        x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
        y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y
    )
    return animation.keyPath == "transform"
        && abs(transform.m11 - 1.05) < 0.001
        && abs(transform.m22 - 1.05) < 0.001
        && abs(transform.m41 - (pivot.x - anchor.x) * (1 - 1.05)) < 0.001
        && abs(transform.m42 - (pivot.y - anchor.y) * (1 - 1.05)) < 0.001
}
require(
    observedInterruptedCloseAnimation,
    "ContentDialog replaces an in-flight opening scale with its closing scale "
        + "(keyPath: \(String(describing: observedInterruptedCloseKeyPath)), "
        + "transform: \(String(describing: observedInterruptedCloseTransform)), "
        + "bounds: \(String(describing: interruptedContentDialogSurface.layer?.bounds)), "
        + "anchor: \(String(describing: interruptedContentDialogSurface.layer?.anchorPoint)), "
        + "closingCount: \(contentDialogClosingCount), presented: \(contentDialogPresented.wrappedValue), "
        + "overlay: \(interruptedContentDialogSurface.superview != nil))"
)
contentDialogPresented.wrappedValue = true
require(
    waitUntil(timeout: 0.70) {
        guard let current = firstView(
            identifier: "FluentKit.ContentDialog.Overlay",
            in: contentDialogWindow.contentView ?? NSView()
        ) else { return false }
        return current !== interruptedContentDialogOverlay
    },
    "ContentDialog reopens with a new generation after an interrupted presentation closes"
)
contentDialogPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.40) {
        firstView(identifier: "FluentKit.ContentDialog.Overlay", in: contentDialogWindow.contentView ?? NSView()) == nil
    },
    "ContentDialog stale opening completions cannot retain or restore an older overlay"
)
require(
    contentDialogClosedResults == [.primary, .none, .none],
    "ContentDialog reports each completed rapid dismissal exactly once"
)
contentDialogWindow.orderOut(nil)

let reducedContentDialogPresented = FluentState(wrappedValue: true)
var reducedContentDialogResult: FluentContentDialogResult?
let reducedContentDialogHost = FluentText("Reduced dialog host")
    .contentDialog(
        "",
        isPresented: reducedContentDialogPresented.projectedValue,
        onClosed: { reducedContentDialogResult = $0 }
    ) {
        FluentText("No transition should be allocated.")
    }
    ._mount(in: FluentRenderContext(
        theme: FluentTheme.current.with(materialEffectsEnabled: false),
        reduceMotion: true
    ))
let reducedContentDialogWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
reducedContentDialogWindow.contentView = reducedContentDialogHost
reducedContentDialogWindow.orderFront(nil)
guard waitUntil(timeout: 0.30, {
    firstView(identifier: "FluentKit.ContentDialog.Overlay", in: reducedContentDialogWindow.contentView ?? NSView()) != nil
}), let reducedContentDialogOverlay = firstView(
    identifier: "FluentKit.ContentDialog.Overlay",
    in: reducedContentDialogWindow.contentView ?? NSView()
), let reducedContentDialogSurface = firstView(
    identifier: "FluentKit.ContentDialog.Surface",
    in: reducedContentDialogOverlay
) else {
    require(false, "reduced-motion ContentDialog presents its final state")
    fatalError("unreachable")
}
require(
    reducedContentDialogSurface.layer?.animationKeys()?.isEmpty != false
        && firstMaterialView(in: reducedContentDialogSurface)?.resolvedBackend == .opaque
        && firstButton(in: reducedContentDialogSurface) == nil,
    "ContentDialog honors Reduce Motion, the opaque fallback, and the no-command layout state"
)
reducedContentDialogPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.20) {
        firstView(identifier: "FluentKit.ContentDialog.Overlay", in: reducedContentDialogWindow.contentView ?? NSView()) == nil
    },
    "reduced-motion ContentDialog dismisses without allocating a transition"
)
require(
    reducedContentDialogResult == FluentContentDialogResult.none,
    "programmatic ContentDialog dismissal reports the WinUI none result"
)
reducedContentDialogWindow.orderOut(nil)

let serializedSheetPresented = FluentState(wrappedValue: false)
let serializedContentDialogPresented = FluentState(wrappedValue: false)
let serializedPresentationHost = FluentText("Serialized presentation host")
    .sheet(
        isPresented: serializedSheetPresented.projectedValue,
        title: "First sheet",
        size: NSSize(width: 380, height: 240)
    ) {
        FluentText("Sheet owns the first coordinator slot")
    }
    .contentDialog(
        "Queued ContentDialog",
        isPresented: serializedContentDialogPresented.projectedValue,
        closeButtonText: "Close"
    ) {
        FluentText("This appears after the native sheet closes.")
    }
    ._mount(in: FluentRenderContext(reduceMotion: true))
let serializedPresentationWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
serializedPresentationWindow.contentView = serializedPresentationHost
serializedPresentationWindow.orderFront(nil)
serializedSheetPresented.wrappedValue = true
require(
    waitUntil(timeout: 0.30) { serializedPresentationWindow.attachedSheet != nil },
    "native Sheet acquires the first shared presentation slot"
)
serializedContentDialogPresented.wrappedValue = true
drainMainQueue()
require(
    firstView(
        identifier: "FluentKit.ContentDialog.Overlay",
        in: serializedPresentationWindow.contentView ?? NSView()
    ) == nil,
    "ContentDialog remains queued while a native Sheet owns the window presentation slot"
)
serializedSheetPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.50) {
        serializedPresentationWindow.attachedSheet == nil
            && firstView(
                identifier: "FluentKit.ContentDialog.Overlay",
                in: serializedPresentationWindow.contentView ?? NSView()
            ) != nil
    },
    "ContentDialog presents after the native Sheet releases the shared coordinator slot"
)
serializedContentDialogPresented.wrappedValue = false
require(
    waitUntil(timeout: 0.20) {
        firstView(
            identifier: "FluentKit.ContentDialog.Overlay",
            in: serializedPresentationWindow.contentView ?? NSView()
        ) == nil
    },
    "serialized ContentDialog releases the shared coordinator after dismissal"
)
serializedPresentationWindow.orderOut(nil)

let expanded = FluentState(wrappedValue: true)
let disclosure = FluentDisclosureGroup("Advanced", isExpanded: expanded.projectedValue) {
    FluentText("Advanced content")
}
let disclosureView = disclosure._mount(in: FluentRenderContext())
require(disclosureView.subviews.count == 1, "disclosure group mounts a native host")
require(expanded.wrappedValue, "disclosure binding starts expanded")

let settingsToggleState = FluentState(wrappedValue: true)
var settingsNavigationInvocations = 0
let settingsSection = FluentSettingsSection("General", description: "Application defaults") {
    FluentSettingsCard(
        "Launch at login",
        description: "Start FluentKit when you sign in",
        systemImageName: "arrow.up.right.square"
    ) {
        FluentToggleView("Launch at login", isOn: settingsToggleState.projectedValue)
    }
    FluentSettingsCard(
        "Keyboard shortcuts",
        description: "Customize commands",
        systemImageName: "command",
        onActivate: { settingsNavigationInvocations += 1 }
    )
}
let settingsSectionView = settingsSection._mount(in: FluentRenderContext())
require(
    firstView(identifier: "FluentKit.Settings.Section", in: settingsSectionView) === settingsSectionView,
    "SettingsSection mounts one shared settings surface"
)
require(
    firstToggle(in: settingsSectionView) != nil
        && firstView(identifier: "FluentKit.Settings.Card", in: settingsSectionView) != nil,
    "SettingsCard keeps an arbitrary trailing Fluent control mounted in the row"
)
let settingsWidthStack = (FluentVStack(spacing: 8) {
    FluentAnyView(settingsSection)
}._mount(in: FluentRenderContext()) as? NSStackView)!
settingsWidthStack.frame = NSRect(x: 0, y: 0, width: 460, height: 600)
settingsWidthStack.layoutSubtreeIfNeeded()
let settingsWidthSection = settingsWidthStack.arrangedSubviews.first
let settingsWidthCard = settingsWidthSection.flatMap {
    firstView(identifier: "FluentKit.Settings.Card", in: $0)
}
let settingsWidthCards = settingsWidthSection.map {
    views(identifier: "FluentKit.Settings.Card", in: $0)
} ?? []
require(
    settingsWidthSection?.frame.width == settingsWidthStack.bounds.width
        && settingsWidthCard?.frame.width == settingsWidthSection?.frame.width
        && settingsWidthCards.count == 2
        && settingsWidthCards.allSatisfy {
            abs($0.frame.width - (settingsWidthSection?.frame.width ?? 0)) <= 0.5
        },
    "SettingsSection and SettingsCard fill the parent column without Gallery width patches"
)
let paddedSettingsStack = (FluentVStack(spacing: 8) {
    FluentAnyView(FluentAnyView(settingsSection).padding(12))
}._mount(in: FluentRenderContext()) as? NSStackView)!
paddedSettingsStack.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
paddedSettingsStack.layoutSubtreeIfNeeded()
let paddedSettingsWrapper = paddedSettingsStack.arrangedSubviews.first
let paddedSettingsSection = paddedSettingsWrapper.flatMap {
    firstView(identifier: "FluentKit.Settings.Section", in: $0)
}
require(
    abs((paddedSettingsWrapper?.frame.width ?? 0) - paddedSettingsStack.bounds.width) <= 0.5
        && abs((paddedSettingsSection?.frame.width ?? 0) - (paddedSettingsStack.bounds.width - 24)) <= 0.5,
    "Settings fill-width propagates through Padding without a fixed page width"
)
let scrollingSettingsStack = (FluentVStack(spacing: 8) {
    FluentAnyView(FluentScrollView(.vertical) {
        FluentAnyView(settingsSection)
    }.frame(height: 180))
}._mount(in: FluentRenderContext()) as? NSStackView)!
scrollingSettingsStack.frame = NSRect(x: 0, y: 0, width: 560, height: 180)
scrollingSettingsStack.layoutSubtreeIfNeeded()
let scrollingSettingsHost = scrollingSettingsStack.arrangedSubviews.first
let scrollingSettingsScroll = scrollingSettingsHost?.subviews.first as? NSScrollView
let scrollingSettingsSection = scrollingSettingsScroll?.documentView.flatMap {
    firstView(identifier: "FluentKit.Settings.Section", in: $0)
}
require(
    abs((scrollingSettingsHost?.frame.width ?? 0) - scrollingSettingsStack.bounds.width) <= 0.5
        && abs((scrollingSettingsScroll?.frame.width ?? 0) - scrollingSettingsStack.bounds.width) <= 0.5
        && abs((scrollingSettingsSection?.frame.width ?? 0) - (scrollingSettingsScroll?.contentView.bounds.width ?? 0)) <= 0.5,
    "Settings fill-width propagates through vertical ScrollView and its viewport"
)
let settingsComboSelection = FluentState<ValidationOption?>(wrappedValue: .first)
let mappedSettingsComboSelection = settingsComboSelection.projectedValue.map({ $0 }, { $0 })
var settingsComboCardActivations = 0
let settingsComboSection = FluentSettingsSection("Selection", description: "Nested control geometry") {
    FluentSettingsCard(
        "Preferred option",
        description: "The trailing control owns its pointer interaction",
        systemImageName: "list.bullet",
        onActivate: { settingsComboCardActivations += 1 }
    ) {
        FluentComboBox(
            options: [ValidationOption.first, .second, .third],
            selection: mappedSettingsComboSelection,
            title: { $0.rawValue.capitalized }
        )
        .frame(width: 160)
    }
}
let settingsComboContext = FluentRenderContext(theme: theme.with(colorScheme: .light))
let settingsComboSectionView = settingsComboSection._mount(in: settingsComboContext)
let settingsComboWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
let settingsComboRoot = NSView(frame: settingsComboWindow.contentView?.bounds ?? .zero)
settingsComboWindow.contentView = settingsComboRoot
settingsComboRoot.addSubview(settingsComboSectionView)
settingsComboSectionView.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    settingsComboSectionView.leadingAnchor.constraint(equalTo: settingsComboRoot.leadingAnchor, constant: 20),
    settingsComboSectionView.trailingAnchor.constraint(equalTo: settingsComboRoot.trailingAnchor, constant: -20),
    settingsComboSectionView.topAnchor.constraint(equalTo: settingsComboRoot.topAnchor, constant: 20),
    settingsComboSectionView.bottomAnchor.constraint(lessThanOrEqualTo: settingsComboRoot.bottomAnchor, constant: -20)
])
settingsComboWindow.makeKeyAndOrderFront(nil)
settingsComboRoot.layoutSubtreeIfNeeded()
guard let settingsComboCard = firstView(identifier: "FluentKit.Settings.Card", in: settingsComboSectionView),
      let settingsActionContainer = firstView(
          identifier: "FluentKit.Settings.ActionContainer",
          in: settingsComboCard
      ),
      let settingsComboLayout = firstView(identifier: "FluentKit.LayoutContainer", in: settingsActionContainer),
      let settingsComboHost = firstView(identifier: "FluentKit.ComboBox.Host", in: settingsComboLayout),
      let settingsNativeCombo = firstView(
          identifier: "FluentKit.ComboBox.NativeBridge",
          in: settingsComboHost
      ) as? NSComboBox else {
    fatalError("SettingsCard ComboBox validation tree did not mount")
}
require(
    abs(settingsComboLayout.intrinsicContentSize.width - 160) <= 0.5
        && abs(settingsComboLayout.intrinsicContentSize.height - theme.controlHeight) <= 0.5,
    "width-only FluentLayoutContainer forwards the ComboBox natural control height"
)
require(
    settingsActionContainer.bounds.insetBy(dx: -0.5, dy: -0.5).contains(settingsComboLayout.frame)
        && settingsComboLayout.bounds.insetBy(dx: -0.5, dy: -0.5).contains(settingsComboHost.frame)
        && settingsComboHost.bounds.insetBy(dx: -0.5, dy: -0.5).contains(settingsNativeCombo.frame)
        && settingsActionContainer.frame.height + 0.5 >= settingsComboLayout.fittingSize.height,
    "SettingsCard action slot, LayoutContainer, ComboBoxHost, and native bridge share one vertical extent "
        + "(action: \(settingsActionContainer.bounds), layout: \(settingsComboLayout.frame)/\(settingsComboLayout.fittingSize), "
        + "host: \(settingsComboHost.frame), native: \(settingsNativeCombo.frame))"
)
let settingsComboPoint = NSPoint(x: settingsComboHost.bounds.midX, y: settingsComboHost.bounds.midY)
let settingsComboPointInCard = settingsComboCard.convert(
    settingsComboHost.convert(settingsComboPoint, to: nil),
    from: nil
)
let settingsComboPointForHitTest = settingsComboCard.superview.map {
    settingsComboCard.convert(settingsComboPointInCard, to: $0)
} ?? settingsComboPointInCard
require(
    settingsComboCard.hitTest(settingsComboPointForHitTest) === settingsComboHost,
    "SettingsCard preserves AppKit hit-testing for the nested ComboBox action subtree"
)
settingsComboHost.updateTrackingAreas()
settingsComboHost.updateTrackingAreas()
require(settingsComboHost.trackingAreas.count == 1, "selection ComboBoxHost owns one stable tracking area")
settingsComboHost.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: settingsComboPoint, in: settingsComboHost, eventNumber: 743)
)
require(
    settingsComboWindow.childWindows?.isEmpty != false,
    "SettingsCard ComboBox mouse-down enters pressed state without opening early"
)
let settingsComboOutsidePoint = NSPoint(x: settingsComboHost.bounds.maxX + 12, y: settingsComboPoint.y)
settingsComboHost.mouseDragged(with:
    toggleMouseEvent(
        .leftMouseDragged,
        at: settingsComboOutsidePoint,
        in: settingsComboHost,
        eventNumber: 744
    )
)
settingsComboHost.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: settingsComboOutsidePoint, in: settingsComboHost, eventNumber: 745)
)
require(
    settingsComboWindow.childWindows?.isEmpty != false,
    "selection ComboBoxHost cancels a press released outside its closed faceplate"
)
settingsComboHost.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: settingsComboPoint, in: settingsComboHost, eventNumber: 746)
)
settingsComboHost.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: settingsComboPoint, in: settingsComboHost, eventNumber: 747)
)
drainMainQueue()
require(
    settingsComboWindow.childWindows?.count == 1 && settingsComboCardActivations == 0,
    "selection ComboBoxHost opens its popup without activating the containing SettingsCard "
        + "(children: \(settingsComboWindow.childWindows?.count ?? -1), card activations: \(settingsComboCardActivations))"
)
let darkSettingsComboContext = FluentRenderContext(theme: theme.with(colorScheme: .dark))
require(
    settingsComboSection._update(settingsComboSectionView, in: darkSettingsComboContext)
        && settingsComboWindow.childWindows?.count == 1,
    "an equivalent mapped binding and theme update preserve an already-open ComboBox popup"
)
guard let settingsSecondRow = settingsComboWindow.childWindows?.first?.contentView.flatMap({
    firstView(withAccessibilityTitle: "Second", in: $0)
}) else {
    fatalError("SettingsCard ComboBox popup row did not mount")
}
let settingsSecondPoint = NSPoint(x: settingsSecondRow.bounds.midX, y: settingsSecondRow.bounds.midY)
settingsSecondRow.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: settingsSecondPoint, in: settingsSecondRow, eventNumber: 745)
)
settingsSecondRow.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: settingsSecondPoint, in: settingsSecondRow, eventNumber: 746)
)
drainMainQueue()
require(
    settingsComboSelection.wrappedValue == .second
        && settingsNativeCombo.stringValue == "Second"
        && settingsComboWindow.childWindows?.isEmpty != false,
    "a real popup-row click updates the binding and closed ComboBox faceplate before dismissal"
)
settingsComboWindow.setContentSize(NSSize(width: 720, height: 240))
settingsComboRoot.layoutSubtreeIfNeeded()
require(
    abs(settingsComboSectionView.frame.width - (settingsComboRoot.bounds.width - 40)) <= 0.5
        && abs(settingsComboCard.frame.width - settingsComboSectionView.frame.width) <= 0.5
        && settingsActionContainer.bounds.insetBy(dx: -0.5, dy: -0.5).contains(settingsComboLayout.frame)
        && settingsComboLayout.bounds.insetBy(dx: -0.5, dy: -0.5).contains(settingsComboHost.frame)
        && abs(
            settingsActionContainer.convert(settingsActionContainer.bounds, to: settingsComboCard).maxX
                - (settingsComboCard.bounds.maxX - 16)
        ) <= 0.5,
    "SettingsSection remains full-width, right-aligns its action, and preserves nested ComboBox geometry after resize"
)
let resizedSettingsComboPoint = NSPoint(x: settingsComboHost.bounds.midX, y: settingsComboHost.bounds.midY)
settingsComboHost.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: resizedSettingsComboPoint, in: settingsComboHost, eventNumber: 747)
)
settingsComboHost.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: resizedSettingsComboPoint, in: settingsComboHost, eventNumber: 748)
)
drainMainQueue()
require(
    settingsComboWindow.childWindows?.count == 1,
    "SettingsCard ComboBox remains clickable after resize"
)
if let settingsThirdRow = settingsComboWindow.childWindows?.first?.contentView.flatMap({
    firstView(withAccessibilityTitle: "Third", in: $0)
}) {
    let point = NSPoint(x: settingsThirdRow.bounds.midX, y: settingsThirdRow.bounds.midY)
    settingsThirdRow.mouseDown(with:
        toggleMouseEvent(.leftMouseDown, at: point, in: settingsThirdRow, eventNumber: 749)
    )
    settingsThirdRow.mouseUp(with:
        toggleMouseEvent(.leftMouseUp, at: point, in: settingsThirdRow, eventNumber: 750)
    )
}
drainMainQueue()
require(
    settingsComboSelection.wrappedValue == .third
        && settingsComboWindow.childWindows?.isEmpty != false,
    "SettingsCard ComboBox commits through the same Host-owned path after resize"
)
settingsComboWindow.orderOut(nil)

let appearanceCommitCoordinator = FluentAppearanceCoordinator(
    theme: theme.with(colorScheme: .light)
)
let appearanceCommitSelection = FluentState<String?>(wrappedValue: "Light")
let appearanceCommitBinding = FluentBinding<String?>(
    get: { appearanceCommitSelection.wrappedValue },
    set: { value in
        appearanceCommitSelection.wrappedValue = value
        appearanceCommitCoordinator.updateTheme(
            theme.with(colorScheme: value == "Dark" ? .dark : .light)
        )
    }
)
let appearanceCommitHost = FluentViewHost(
    FluentComboBox(options: ["Light", "Dark"], selection: appearanceCommitBinding),
    context: FluentRenderContext(
        theme: appearanceCommitCoordinator.theme,
        appearanceCoordinator: appearanceCommitCoordinator
    )
)
let appearanceCommitWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
appearanceCommitWindow.contentView = appearanceCommitHost
appearanceCommitCoordinator.attach(to: appearanceCommitWindow)
appearanceCommitWindow.makeKeyAndOrderFront(nil)
appearanceCommitHost.frame = appearanceCommitWindow.contentView?.bounds ?? .zero
appearanceCommitHost.layoutSubtreeIfNeeded()
guard let appearanceCommitCombo = firstView(
    identifier: "FluentKit.ComboBox.Host",
    in: appearanceCommitHost
) else {
    fatalError("appearance-changing ComboBox did not mount")
}
let appearanceCommitPoint = NSPoint(
    x: appearanceCommitCombo.bounds.midX,
    y: appearanceCommitCombo.bounds.midY
)
appearanceCommitCombo.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: appearanceCommitPoint, in: appearanceCommitCombo, eventNumber: 755)
)
appearanceCommitCombo.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: appearanceCommitPoint, in: appearanceCommitCombo, eventNumber: 756)
)
guard let appearanceDarkRow = appearanceCommitWindow.childWindows?.first?.contentView.flatMap({
    firstView(withAccessibilityTitle: "Dark", in: $0)
}) else {
    fatalError("appearance-changing ComboBox popup did not mount")
}
let appearanceDarkPoint = NSPoint(x: appearanceDarkRow.bounds.midX, y: appearanceDarkRow.bounds.midY)
appearanceDarkRow.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: appearanceDarkPoint, in: appearanceDarkRow, eventNumber: 757)
)
appearanceDarkRow.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: appearanceDarkPoint, in: appearanceDarkRow, eventNumber: 758)
)
drainMainQueue()
require(
    appearanceCommitSelection.wrappedValue == "Dark"
        && appearanceCommitCoordinator.theme.colorScheme == .dark
        && appearanceCommitWindow.childWindows?.isEmpty != false,
    "ComboBox survives a synchronous window-appearance change from its popup row and dismisses once"
)
appearanceCommitWindow.orderOut(nil)

let settingsExpanderState = FluentState(wrappedValue: false)
let settingsExpander = FluentSettingsExpander(
    "Advanced",
    description: "Additional options",
    systemImageName: "slider.horizontal.3",
    isExpanded: settingsExpanderState.projectedValue
) {
    FluentSettingsSection {
        FluentSettingsCard("Diagnostics", description: "Verbose logging")
    }
}
let settingsExpanderView = settingsExpander._mount(in: FluentRenderContext())
settingsExpanderView.layoutSubtreeIfNeeded()
let collapsedSettingsHeight = settingsExpanderView.fittingSize.height
settingsExpanderState.wrappedValue = true
drainMainQueue()
settingsExpanderView.layoutSubtreeIfNeeded()
let expandedSettingsHeight = settingsExpanderView.fittingSize.height
let hasSettingsExpanderHeader = firstView(
    identifier: "FluentKit.Settings.Expander.Header",
    in: settingsExpanderView
) != nil
require(
    hasSettingsExpanderHeader && expandedSettingsHeight > collapsedSettingsHeight,
    "SettingsExpander exposes an accessible header and expands its child content "
        + "(header: \(hasSettingsExpanderHeader), collapsed: \(collapsedSettingsHeight), "
        + "expanded: \(expandedSettingsHeight))"
)
let settingsExpanderHeader = firstView(
    identifier: "FluentKit.Settings.Expander.Header",
    in: settingsExpanderView
)
if let settingsExpanderHeader,
   let settingsChevron = firstLayer(named: "FluentKit.Settings.Chevron", in: settingsExpanderHeader) {
    let expectedChevronCenterX = settingsExpanderHeader.userInterfaceLayoutDirection == .rightToLeft
        ? settingsExpanderHeader.bounds.minX + 20
        : settingsExpanderHeader.bounds.maxX - 20
    require(
        settingsChevron.bounds.size == NSSize(width: 12, height: 12)
            && abs(settingsChevron.position.x - expectedChevronCenterX) <= 0.5
            && abs(settingsChevron.position.y - settingsExpanderHeader.bounds.midY) <= 0.5,
        "SettingsExpander centers the WinUI 12pt chevron in its 40pt trailing alignment slot "
            + "(bounds: \(settingsChevron.bounds), position: \(settingsChevron.position), "
            + "header: \(settingsExpanderHeader.bounds), expectedX: \(expectedChevronCenterX))"
    )
} else {
    require(false, "SettingsExpander exposes its shared semantic chevron primitive")
}
require(
    settingsExpanderHeader?.accessibilityPerformPress() == true
        && !settingsExpanderState.wrappedValue,
    "SettingsExpander header press writes the collapsed state through its binding"
)
settingsExpanderView.layoutSubtreeIfNeeded()
require(
    settingsExpanderView.fittingSize.height <= collapsedSettingsHeight + 1,
    "detached SettingsExpander collapses its clipped viewport from the real header interaction"
)
require(
    settingsExpanderHeader?.accessibilityPerformPress() == true
        && settingsExpanderState.wrappedValue,
    "SettingsExpander header press can expand again without a second local state path"
)
let settingsExpanderWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
settingsExpanderWindow.contentView = settingsExpanderView
settingsExpanderWindow.makeKeyAndOrderFront(nil)
settingsExpanderView.frame = NSRect(x: 0, y: 0, width: 460, height: 220)
settingsExpanderState.wrappedValue = false
drainMainQueue()
if let settingsExpanderHeader {
    let clickPoint = NSPoint(x: settingsExpanderHeader.bounds.midX, y: settingsExpanderHeader.bounds.midY)
    settingsExpanderHeader.mouseDown(
        with: toggleMouseEvent(.leftMouseDown, at: clickPoint, in: settingsExpanderHeader, eventNumber: 741)
    )
    settingsExpanderHeader.mouseUp(
        with: toggleMouseEvent(.leftMouseUp, at: clickPoint, in: settingsExpanderHeader, eventNumber: 742)
    )
    require(
        settingsExpanderState.wrappedValue,
        "SettingsExpander toggles through a real mouse-down/mouse-up row click"
    )
    settingsExpanderState.wrappedValue = false
    drainMainQueue()
}
settingsExpanderState.wrappedValue = true
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
let reversingExpanderHeight = settingsExpanderView.fittingSize.height
settingsExpanderState.wrappedValue = false
require(
    waitUntil(timeout: 0.35) { settingsExpanderView.fittingSize.height <= collapsedSettingsHeight + 1 },
    "SettingsExpander reverses from its current presentation height without leaving content visible"
)
require(
    reversingExpanderHeight > collapsedSettingsHeight,
    "SettingsExpander exposes a measurable viewport while its height animation is active"
)
settingsExpanderWindow.orderOut(nil)
require(settingsToggleState.wrappedValue, "SettingsCard action state remains owned by its child control")

let hostedSettingsExpanderState = FluentState(wrappedValue: true)
var hostedSettingsMenuInvocations = 0
let hostedSettingsRoot = FluentViewHost(
    FluentScrollView(.vertical) {
        FluentVStack(spacing: 18) {
            FluentAnyView(FluentSettingsExpander(
                "Interactive sample",
                description: "Complete Gallery host path",
                systemImageName: "play.circle",
                isExpanded: hostedSettingsExpanderState.projectedValue
            ) {
                FluentButtonView("Open hosted menu").flyout {
                    FluentMenuItem("Hosted action") { hostedSettingsMenuInvocations += 1 }
                }
                .padding(24)
            })
        }
        .padding(NSEdgeInsets(top: 24, left: 32, bottom: 40, right: 32))
    }
)
let hostedSettingsWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
hostedSettingsWindow.contentView = hostedSettingsRoot
hostedSettingsRoot.frame = NSRect(x: 0, y: 0, width: 720, height: 420)
hostedSettingsWindow.makeKeyAndOrderFront(nil)
hostedSettingsRoot.layoutSubtreeIfNeeded()
drainMainQueue()
guard let hostedHeader = firstView(
    identifier: "FluentKit.Settings.Expander.Header",
    in: hostedSettingsRoot
), let hostedViewport = firstView(
    identifier: "FluentKit.Settings.Expander.Viewport",
    in: hostedSettingsRoot
) else {
    fatalError("complete SettingsExpander host path did not mount")
}
let hostedHeaderPoint = NSPoint(x: hostedHeader.bounds.midX, y: hostedHeader.bounds.midY)
let hostedRootPoint = hostedHeader.convert(hostedHeaderPoint, to: hostedSettingsRoot)
let hostedHitTarget = hostedSettingsRoot.hitTest(hostedRootPoint)
let hostedExpanderHost = firstView(
    identifier: "FluentKit.Settings.Expander",
    in: hostedSettingsRoot
)
require(
    hostedHitTarget === hostedHeader,
    "FluentScrollView and FluentVStack route a Gallery header click to SettingsExpander "
        + "(point: \(hostedRootPoint), header: \(hostedHeader.frame), "
        + "expander: \(String(describing: hostedExpanderHost?.frame))/\(String(describing: hostedExpanderHost?.bounds)), "
        + "headerInExpander: \(String(describing: hostedExpanderHost.map { hostedHeader.convert(hostedHeader.bounds, to: $0) })), "
        + "target: \(String(describing: hostedHitTarget)), targetID: \(String(describing: hostedHitTarget?.identifier)), "
        + "targetIsHeaderStack: \(hostedHitTarget === hostedHeader.superview), "
        + "targetIsExpanderParent: \(hostedHitTarget === hostedExpanderHost?.superview))"
)
hostedHeader.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: hostedHeaderPoint, in: hostedHeader, eventNumber: 751)
)
hostedHeader.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: hostedHeaderPoint, in: hostedHeader, eventNumber: 752)
)
require(
    !hostedSettingsExpanderState.wrappedValue
        && waitUntil(timeout: 0.35) { hostedViewport.frame.height <= 0.5 },
    "SettingsExpander collapses through the complete ScrollView/VStack/ViewHost event path"
)
guard let refreshedHostedHeader = firstView(
    identifier: "FluentKit.Settings.Expander.Header",
    in: hostedSettingsRoot
) else {
    fatalError("hosted SettingsExpander header disappeared after collapse")
}
let refreshedHostedPoint = NSPoint(
    x: refreshedHostedHeader.bounds.midX,
    y: refreshedHostedHeader.bounds.midY
)
refreshedHostedHeader.mouseDown(with:
    toggleMouseEvent(.leftMouseDown, at: refreshedHostedPoint, in: refreshedHostedHeader, eventNumber: 753)
)
refreshedHostedHeader.mouseUp(with:
    toggleMouseEvent(.leftMouseUp, at: refreshedHostedPoint, in: refreshedHostedHeader, eventNumber: 754)
)
require(
    hostedSettingsExpanderState.wrappedValue
        && waitUntil(timeout: 0.50) {
            guard let content = hostedViewport.subviews.last else { return false }
            let intrinsic = content.intrinsicContentSize.height
            let desired = intrinsic == NSView.noIntrinsicMetric ? content.fittingSize.height : intrinsic
            return hostedViewport.frame.height >= desired + 20 - 0.5
        },
    "SettingsExpander expands again without replacing its header or losing hit-testing"
)
guard let hostedMenuButton = firstView(
    withAccessibilityTitle: "Open hosted menu",
    in: hostedSettingsRoot
) as? NSButton else {
    fatalError("hosted SettingsExpander flyout button did not mount")
}
let hostedMenuPoint = hostedMenuButton.convert(
    NSPoint(x: hostedMenuButton.bounds.midX, y: hostedMenuButton.bounds.midY),
    to: hostedSettingsRoot
)
let hostedMenuHitTarget = hostedSettingsRoot.hitTest(hostedMenuPoint)
require(
    hostedMenuHitTarget === hostedMenuButton,
    "expanded SettingsExpander routes content clicks to its nested flyout button "
        + "(point: \(hostedMenuPoint), button: \(hostedMenuButton.frame)/\(hostedMenuButton.bounds), "
        + "viewport: \(hostedViewport.frame)/\(hostedViewport.bounds), "
        + "target: \(String(describing: hostedMenuHitTarget)), "
        + "targetID: \(String(describing: hostedMenuHitTarget?.identifier)))"
)
hostedMenuButton.performClick(nil)
require(
    waitUntil(timeout: 0.20) { hostedSettingsWindow.childWindows?.count == 1 },
    "a button flyout opens from inside the complete SettingsExpander host path"
)
guard let hostedMenuRow = hostedSettingsWindow.childWindows?.first?.contentView.flatMap({
    firstView(withAccessibilityTitle: "Hosted action", in: $0)
}) else {
    fatalError("hosted SettingsExpander menu row did not mount")
}
require(
    hostedMenuRow.accessibilityPerformPress()
        && waitUntil(timeout: 0.20) { hostedSettingsMenuInvocations == 1 },
    "the nested MenuFlyout remains clickable and invokes its action"
)
hostedSettingsWindow.orderOut(nil)

let scrollExpanderState = FluentState(wrappedValue: true)
let scrollExpanderHost = FluentViewHost(
    FluentScrollView(.vertical) {
        FluentVStack(spacing: 18) {
            FluentSettingsSection("Overview") {
                FluentSettingsCard("Coverage", description: "Top-aligned reference card")
            }
            FluentSettingsExpander(
                "Interactive sample",
                isExpanded: scrollExpanderState.projectedValue
            ) {
                FluentText("Expanded sample content")
                    .padding(24)
            }
            FluentSettingsSection("Source identity") {
                FluentSettingsCard("Source", description: "Following content")
            }
        }
        .padding(NSEdgeInsets(top: 24, left: 32, bottom: 40, right: 32))
    },
    context: FluentRenderContext(reduceMotion: true)
)
let scrollExpanderWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
scrollExpanderWindow.contentView = scrollExpanderHost
scrollExpanderHost.frame = scrollExpanderWindow.contentView?.bounds ?? .zero
scrollExpanderWindow.makeKeyAndOrderFront(nil)
scrollExpanderHost.layoutSubtreeIfNeeded()
drainMainQueue()
let expandedScrollCards = views(identifier: "FluentKit.Settings.Card", in: scrollExpanderHost)
guard let expandedCoverageCard = expandedScrollCards.first,
      let expandedSourceCard = expandedScrollCards.last,
      expandedCoverageCard !== expandedSourceCard else {
    fatalError("scroll-alignment Settings cards did not mount")
}
let expandedCoverageFrame = expandedCoverageCard.convert(expandedCoverageCard.bounds, to: scrollExpanderHost)
let expandedSourceFrame = expandedSourceCard.convert(expandedSourceCard.bounds, to: scrollExpanderHost)
scrollExpanderState.wrappedValue = false
drainMainQueue()
scrollExpanderHost.layoutSubtreeIfNeeded()
let collapsedScrollCards = views(identifier: "FluentKit.Settings.Card", in: scrollExpanderHost)
guard let collapsedCoverageCard = collapsedScrollCards.first,
      let collapsedSourceCard = collapsedScrollCards.last,
      collapsedCoverageCard !== collapsedSourceCard else {
    fatalError("collapsed scroll-alignment Settings cards disappeared")
}
let collapsedCoverageFrame = collapsedCoverageCard.convert(collapsedCoverageCard.bounds, to: scrollExpanderHost)
let collapsedSourceFrame = collapsedSourceCard.convert(collapsedSourceCard.bounds, to: scrollExpanderHost)
require(
    abs(collapsedCoverageFrame.minY - expandedCoverageFrame.minY) <= 0.5
        && abs(collapsedSourceFrame.midY - collapsedCoverageFrame.midY)
            < abs(expandedSourceFrame.midY - expandedCoverageFrame.midY) - 20,
    "vertical ScrollView keeps collapsed expander content top-packed instead of distributing empty space above it "
        + "(coverage expanded/collapsed: \(expandedCoverageFrame)/\(collapsedCoverageFrame), "
        + "source expanded/collapsed: \(expandedSourceFrame)/\(collapsedSourceFrame))"
)
scrollExpanderWindow.orderOut(nil)

let mode = FluentState(wrappedValue: 1)
let segmented = FluentSegmentedControl(["One", "Two", "Three"], selection: mode.projectedValue)
let segmentedView = segmented._mount(in: FluentRenderContext())
require(segmentedView is NSSegmentedControl, "segmented control mounts native AppKit control")
require((segmentedView as? NSSegmentedControl)?.selectedSegment == 1, "segmented control reads selection binding")

var commandInvocations = 0
let commandWrapped = FluentText("Commands").fluentCommandGroups {
    FluentCommandGroup("Editing") {
        FluentCommand("Focus", keyEquivalent: "f") { commandInvocations += 1 }
    }
}
let commandView = commandWrapped._mount(in: FluentRenderContext())
require(commandView.subviews.count == 1, "commands keep content mounted")
if let commandEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [.command],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "f",
    charactersIgnoringModifiers: "f",
    isARepeat: false,
    keyCode: 3
) {
    require(commandView.performKeyEquivalent(with: commandEvent), "command consumes matching key equivalent")
}
require(commandInvocations == 1, "command group invokes matching action")

var appCommandInvocations = 0
var appCommandEnabled = true
let applicationCommands = [
    FluentCommandGroup("File") {
        FluentCommand("Export", keyEquivalent: "e", modifiers: [.command, .shift], isEnabled: { appCommandEnabled }) {
            appCommandInvocations += 1
        }
    },
    FluentCommandGroup("View") {
        FluentCommand("Refresh", keyEquivalent: "r") {}
    }
]
let mainMenuCoordinator = FluentMainMenuCoordinator(applicationName: "Validation App", groups: applicationCommands)
require(mainMenuCoordinator.menu.title == "Validation App", "main menu preserves application title")
require(
    mainMenuCoordinator.menu.items.map { $0.submenu?.title ?? "" }
        == ["Validation App", "File", "Edit", "View", "Window", "Help"],
    "main menu owns the standard App, File, Edit, View, Window, and Help structure"
)
let fileMenu = mainMenuCoordinator.menu.items[1].submenu
require(fileMenu?.title == "File", "main menu preserves command group title")
require(
    fileMenu?.items.contains { $0.action == #selector(NSDocumentController.newDocument(_:)) } == true
        && fileMenu?.items.contains { $0.action == #selector(NSDocumentController.openDocument(_:)) } == true
        && fileMenu?.items.contains { $0.action == #selector(NSWindow.performClose(_:)) } == true,
    "File menu keeps New, Open, and Close on the native responder chain"
)
let editMenu = mainMenuCoordinator.menu.items[2].submenu
require(
    editMenu?.items.contains { $0.action.map(NSStringFromSelector) == "undo:" } == true
        && editMenu?.items.contains { $0.action.map(NSStringFromSelector) == "redo:" } == true
        && editMenu?.items.contains { $0.action == #selector(NSText.cut(_:)) } == true
        && editMenu?.items.contains { $0.action == #selector(NSText.copy(_:)) } == true
        && editMenu?.items.contains { $0.action == #selector(NSText.paste(_:)) } == true
        && editMenu?.items.contains { $0.action == #selector(NSText.selectAll(_:)) } == true,
    "Edit menu routes Undo, clipboard, and selection commands through AppKit responders"
)
let exportItem = fileMenu?.items.first { $0.title == "Export" }
require(exportItem?.keyEquivalent == "e", "main menu preserves command key equivalent")
require(exportItem?.keyEquivalentModifierMask == [.command, .shift], "main menu preserves command modifiers")
require(exportItem.map(mainMenuCoordinator.perform) == true, "main menu performs an enabled command")
require(appCommandInvocations == 1, "main menu invokes the declarative action")
appCommandEnabled = false
mainMenuCoordinator.menuNeedsUpdate(mainMenuCoordinator.menu)
require(exportItem?.isEnabled == false, "main menu refreshes dynamic enabled state")
require(exportItem.map(mainMenuCoordinator.perform) == false, "main menu refuses to perform a disabled command")
mainMenuCoordinator.update(groups: [])
require(
    mainMenuCoordinator.menu.items.count == 6
        && mainMenuCoordinator.menu.items[1].submenu?.items.contains { $0.title == "Export" } == false,
    "main menu update removes stale declarative commands while preserving standard menus"
)

let pickedDate = FluentState(wrappedValue: Date(timeIntervalSince1970: 1_700_000_000))
let datePicker = FluentDatePicker(selection: pickedDate.projectedValue)
let styledDatePicker = datePicker.textFieldStyle(ValidationTextFieldStyle())
let dateTheme = FluentTheme.custom(colorScheme: .light)
let dateView = styledDatePicker._mount(in: FluentRenderContext(theme: dateTheme))
require(dateView is NSDatePicker, "date picker mounts native AppKit control")
require((dateView as? NSDatePicker)?.dateValue == pickedDate.wrappedValue, "date picker reads selection binding")
require((dateView as? NSDatePicker)?.font?.pointSize == 17, "date picker receives the shared semantic field font")
if let nativeDatePicker = dateView as? NSDatePicker {
    require(nativeDatePicker.datePickerStyle == .textField, "calendar date picker keeps native text-field interaction")
    require(nativeDatePicker.datePickerMode == .single, "calendar date picker keeps a single native date selection")
    require(!nativeDatePicker.isBordered && !nativeDatePicker.drawsBackground, "calendar date picker removes native AppKit chrome")
    if #available(macOS 10.15.4, *) {
        require(!nativeDatePicker.presentsCalendarOverlay, "calendar date picker does not depend on AppKit's private overlay hit region")
    }
}
let datePickerWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
dateView.frame = NSRect(x: 20, y: 24, width: 220, height: 32)
datePickerWindow.contentView = dateView
datePickerWindow.makeKeyAndOrderFront(nil)
dateView.layoutSubtreeIfNeeded()
guard let dateElevationBorder = firstLayer(
    named: "FluentKit.CalendarDatePicker.ElevationBorder",
    in: dateView
) as? CAGradientLayer,
      let dateElevationMask = dateElevationBorder.mask as? CAShapeLayer,
      let dateElevationPath = dateElevationMask.path else {
    fatalError("CalendarDatePicker elevation border did not mount")
}
let dateElevationBounds = dateElevationPath.boundingBox
require(
    dateElevationMask.fillRule == .evenOdd
        && pathBoundsUseContainedAntialiasing(
            dateElevationBounds,
            in: dateView.bounds,
            backingScale: dateElevationBorder.contentsScale
        ),
    "CalendarDatePicker keeps its elevation antialiasing inside every host edge"
)
require(
    dateElevationBorder.locations?.map(\.doubleValue) == [0.33, 1]
        && elevationGradientMatchesVisualEdge(
            dateElevationBorder,
            edge: .bottom,
            hostView: dateView
        ),
    "CalendarDatePicker uses the source three-point brush at its visual elevation edge"
)
require(
    dateElevationBorder.contentsScale == datePickerWindow.backingScaleFactor
        && dateElevationMask.contentsScale == datePickerWindow.backingScaleFactor,
    "CalendarDatePicker resolves its elevation edge on the window backing scale"
)
dateView.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: dateView.bounds.midX, y: dateView.bounds.midY),
        in: dateView,
        eventNumber: 97
    )
)
require(
    colorMatches(dateView.layer?.backgroundColor, dateTheme.buttonBackground(for: .pointerOver)),
    "CalendarDatePicker maps pointer-over to the source secondary control fill"
)
require(
    dateView.layer?.animationKeys()?.isEmpty != false
        && dateElevationBorder.animationKeys()?.isEmpty != false,
    "CalendarDatePicker applies its source discrete visual-state setters without invented motion"
)
dateView.mouseDown(
    with: toggleMouseEvent(
        .leftMouseDown,
        at: NSPoint(x: dateView.bounds.midX, y: dateView.bounds.midY),
        in: dateView,
        eventNumber: 98
    )
)
drainMainQueue()
require(
    datePickerWindow.childWindows?.first?.contentView?.identifier?.rawValue
        == "FluentKit.CalendarDatePicker.Popover",
    "CalendarDatePicker opens a native calendar popover from a primary click anywhere on its surface"
)
require(
    datePickerWindow.childWindows?.first?.contentView?.subviews.contains { $0 is NSDatePicker } == true,
    "CalendarDatePicker popover keeps native clock-and-calendar selection behavior"
)
datePickerWindow.childWindows?.first?.performClose(nil)
drainMainQueue()
if let nativeDatePicker = dateView as? NSDatePicker {
    nativeDatePicker.isEnabled = false
    require(
        colorMatches(dateView.layer?.backgroundColor, dateTheme.buttonBackground(for: .disabled)),
        "CalendarDatePicker maps disabled state to the source disabled control fill"
    )
}
datePickerWindow.orderOut(nil)

let pickedColor = FluentState(wrappedValue: NSColor.systemBlue)
let colorPicker = FluentColorPicker(selection: pickedColor.projectedValue, label: "Accent color")
let colorView = colorPicker._mount(in: FluentRenderContext())
require(colorView is NSColorWell, "color picker mounts native AppKit control")
require((colorView as? NSColorWell)?.color == pickedColor.wrappedValue, "color picker reads selection binding")

let groupedAccessibility = FluentVStack(spacing: 4) {
    FluentText("Group label")
    FluentButton(title: "Group action")
}.accessibilityGroup(label: "Settings group", identifier: "settings-group")
let groupedView = groupedAccessibility._mount(in: FluentRenderContext())
require(groupedView.isAccessibilityElement(), "accessibility group is an element")
require(groupedView.accessibilityChildren()?.count == 1, "accessibility group exposes composed child hierarchy")

var toolbarInvocations = 0
let toolbarRoot = FluentText("Toolbar host").toolbar {
    FluentToolbarItem("save", label: "Save", toolTip: "Save changes") {
        FluentButtonView("Save") { toolbarInvocations += 1 }
    }
    FluentToolbarItem.space
}
let toolbarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
let toolbarHost = FluentViewHost(toolbarRoot)
toolbarWindow.contentView = toolbarHost
toolbarWindow.makeKeyAndOrderFront(nil)
drainMainQueue()
require(toolbarWindow.toolbar != nil, "toolbar modifier attaches an NSToolbar to the containing window")
require(toolbarWindow.toolbar?.items.count == 2, "toolbar creates declarative items")
if let button = toolbarWindow.toolbar?.items.first?.view?.subviews.first as? FluentButton {
    button.performClick(nil)
}
require(toolbarInvocations == 1, "toolbar item preserves declarative action")

let tabViewSelection = FluentState(wrappedValue: 0)
var tabViewAddCount = 0
var tabViewItemCloseCount = 0
var tabViewCloseRequests: [Int] = []
var tabViewMoveRequests: [(Int, Int)] = []
let tabViewItems = [
    FluentTabItem(
        id: "home",
        title: "Home",
        systemImage: "house",
        onCloseRequested: { tabViewItemCloseCount += 1 }
    ) { FluentText("Home content") },
    FluentTabItem(
        id: "disabled",
        title: "Disabled",
        systemImage: "nosign",
        isEnabled: false
    ) { FluentText("Disabled content") },
    FluentTabItem(
        id: "logs",
        title: "Logs",
        systemImage: "doc.text",
        isClosable: false
    ) { FluentText("Logs content") }
]
let sourceMappedTabView = FluentTabView(
    items: tabViewItems,
    selectedIndex: tabViewSelection.projectedValue,
    tabWidthMode: .equal,
    closeButtonOverlayMode: .always,
    isAddTabButtonVisible: true,
    onAddTabButtonClick: { tabViewAddCount += 1 },
    onTabCloseRequested: { tabViewCloseRequests.append($0) },
    onTabMoveRequested: { tabViewMoveRequests.append(($0, $1)) }
)
.tabStripHeader { FluentText("Workspace") }
.tabStripFooter { FluentText("Synced") }
let tabViewHost = sourceMappedTabView._mount(in: FluentRenderContext(theme: theme, reduceMotion: false))
let tabViewWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 620, height: 260),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
tabViewWindow.contentView = tabViewHost
tabViewHost.frame = NSRect(x: 0, y: 0, width: 620, height: 260)
tabViewWindow.orderFront(nil)
tabViewHost.layoutSubtreeIfNeeded()
guard let nativeTabView = firstView(identifier: "FluentKit.TabView", in: tabViewHost) else {
    fatalError("TabView validation hierarchy did not mount")
}
let mountedTabItems = views(identifier: "FluentKit.TabView.Tab", in: nativeTabView)
require(
    nativeTabView.accessibilityRole() == .radioGroup
        && mountedTabItems.count == 3
        && mountedTabItems.allSatisfy { $0.accessibilityRole() == .radioButton },
    "TabView exposes one native radio-button accessibility child per tab"
)
require(
    mountedTabItems.allSatisfy { abs($0.frame.width - mountedTabItems[0].frame.width) < 0.001 && $0.frame.height == 32 },
    "TabView Equal mode uses source 32pt headers with equal clamped widths"
)
require(
    firstView(identifier: "FluentKit.TabView.Header", in: nativeTabView) != nil
        && firstView(identifier: "FluentKit.TabView.Footer", in: nativeTabView) != nil,
    "TabView mounts source-equivalent strip header and footer slots"
)
require(
    mountedTabItems[0].accessibilityValue() as? String == "On"
        && mountedTabItems[1].isAccessibilityEnabled() == false,
    "TabView publishes selected and disabled item semantics"
)
let originalHomeTabIdentity = ObjectIdentifier(mountedTabItems[0])
tabViewSelection.wrappedValue = 2
drainMainQueue()
tabViewHost.layoutSubtreeIfNeeded()
require(
    mountedTabItems[2].accessibilityValue() as? String == "On"
        && firstView(identifier: "FluentKit.TabView.Content.2", in: nativeTabView)?.isHidden == false
        && firstView(identifier: "FluentKit.TabView.Content.0", in: nativeTabView)?.isHidden == true,
    "TabView external selection swaps the stable declarative content presenter"
)
require(
    firstView(identifier: "FluentKit.TabView.Content.2", in: nativeTabView)?.layer?.animationKeys()?.isEmpty != false,
    "TabView selection directly swaps content like the source TabContentPresenter"
)
require(
    !mountedTabItems[1].accessibilityPerformPress() && tabViewSelection.wrappedValue == 2,
    "TabView rejects selection of a disabled tab"
)
require(
    mountedTabItems[0].accessibilityPerformPress() && tabViewSelection.wrappedValue == 0,
    "TabView accessibility press writes selection through the binding"
)
guard let closeHomeTab = firstView(withAccessibilityTitle: "Close Home", in: nativeTabView),
      let addTabButton = firstView(withAccessibilityTitle: "Add new tab", in: nativeTabView) else {
    fatalError("TabView action buttons did not mount")
}
require(
    closeHomeTab.accessibilityPerformPress()
        && tabViewItemCloseCount == 1
        && tabViewCloseRequests == [0],
    "TabView close raises both item and parent close-request callbacks"
)
require(
    addTabButton.accessibilityPerformPress() && tabViewAddCount == 1,
    "TabView add button uses the native accessibility invocation path"
)
let compactTabView = FluentTabView(
    items: tabViewItems,
    selectedIndex: tabViewSelection.projectedValue,
    tabWidthMode: .compact,
    closeButtonOverlayMode: .onPointerOver,
    isAddTabButtonVisible: true,
    onAddTabButtonClick: { tabViewAddCount += 1 },
    onTabCloseRequested: { tabViewCloseRequests.append($0) },
    onTabMoveRequested: { tabViewMoveRequests.append(($0, $1)) }
)
require(
    compactTabView._update(tabViewHost, in: FluentRenderContext(theme: theme, reduceMotion: false)),
    "TabView accepts compatible declarative updates in place"
)
tabViewHost.layoutSubtreeIfNeeded()
let compactTabItems = views(identifier: "FluentKit.TabView.Tab", in: tabViewHost)
require(
    ObjectIdentifier(compactTabItems[0]) == originalHomeTabIdentity
        && compactTabItems[0].frame.width >= 100
        && compactTabItems[2].frame.width == 48,
    "TabView preserves stable tab identity and applies source Compact icon-only width"
)
require(
    compactTabItems.contains {
        abs(($0.layer?.animation(forKey: "fluent.tabview.reorder")?.duration ?? 0) - 0.2) < 0.000_001
    },
    "TabView width and order changes use the source 200ms item transition"
)

let rapidTabSelection = FluentState(wrappedValue: 0)
let makeRapidTabItems: (Int) -> [FluentTabItem] = { count in
    (0..<count).map { index in
        FluentTabItem(id: index, title: "Document \(index)", systemImage: "doc") {
            FluentText("Document content \(index)")
        }
    }
}
let rapidTabHost = FluentTabView(
    items: makeRapidTabItems(1),
    selectedIndex: rapidTabSelection.projectedValue,
    tabWidthMode: .equal,
    isAddTabButtonVisible: true
)._mount(in: FluentRenderContext(theme: theme, reduceMotion: false))
let rapidTabWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 606, height: 180),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
rapidTabWindow.contentView = rapidTabHost
rapidTabHost.frame = NSRect(x: 0, y: 0, width: 606, height: 180)
rapidTabWindow.orderFront(nil)
rapidTabHost.layoutSubtreeIfNeeded()
for count in 2...18 {
    let nextRapidTabView = FluentTabView(
        items: makeRapidTabItems(count),
        selectedIndex: rapidTabSelection.projectedValue,
        tabWidthMode: .equal,
        isAddTabButtonVisible: true
    )
    require(
        nextRapidTabView._update(
            rapidTabHost,
            in: FluentRenderContext(theme: theme, reduceMotion: false)
        ),
        "TabView accepts rapid successive insert updates in place"
    )
    rapidTabSelection.wrappedValue = count - 1
    rapidTabHost.layoutSubtreeIfNeeded()

    let rapidTabs = views(identifier: "FluentKit.TabView.Tab", in: rapidTabHost)
    let orderedRapidTabs = rapidTabs.sorted { $0.frame.minX < $1.frame.minX }
    let rapidTabKeys = rapidTabs.map { Set($0.layer?.animationKeys() ?? []) }
    require(
        rapidTabs.count == count
            && Set(rapidTabs.map(ObjectIdentifier.init)).count == count
            && zip(orderedRapidTabs, orderedRapidTabs.dropFirst()).allSatisfy {
                $0.0.frame.maxX <= $0.1.frame.minX + 0.001
            },
        "TabView rapid insertion keeps one non-overlapping model container per stable ID"
    )
    require(
        rapidTabKeys.allSatisfy {
            !$0.contains("fluent.tabview.insert.position")
                && !($0.contains("fluent.tabview.insert.opacity") && $0.contains("fluent.tabview.reorder"))
        },
        "TabView insertion fades only and never stacks entrance translation with FLIP reorder"
    )
    require(
        firstView(withAccessibilityTitle: "Document \(count - 1)", in: rapidTabHost)?
            .layer?.animation(forKey: "fluent.tabview.insert.opacity") != nil,
        "TabView gives exactly the newly inserted tab the source-compatible fade entrance"
    )
}
rapidTabWindow.orderOut(nil)

guard let controlTabEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [.control],
    timestamp: 80,
    windowNumber: tabViewWindow.windowNumber,
    context: nil,
    characters: "\t",
    charactersIgnoringModifiers: "\t",
    isARepeat: false,
    keyCode: 48
) else {
    fatalError("could not create TabView Ctrl+Tab validation event")
}
compactTabItems[0].keyDown(with: controlTabEvent)
require(
    tabViewSelection.wrappedValue == 2,
    "TabView Ctrl+Tab wraps through enabled tabs and skips disabled tabs"
)
guard let reorderTabEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [.option, .shift],
    timestamp: 81,
    windowNumber: tabViewWindow.windowNumber,
    context: nil,
    characters: NSRightArrowFunctionKey.description,
    charactersIgnoringModifiers: NSRightArrowFunctionKey.description,
    isARepeat: false,
    keyCode: 124
) else {
    fatalError("could not create TabView reorder validation event")
}
compactTabItems[0].keyDown(with: reorderTabEvent)
require(
    tabViewMoveRequests.count == 1
        && tabViewMoveRequests[0].0 == 0
        && tabViewMoveRequests[0].1 == 1,
    "TabView Option+Shift+Arrow exposes the source keyboard reorder request"
)

let overflowingTabItems = (0..<6).map { index in
    FluentTabItem(id: index, title: "Document \(index)", systemImage: "doc") {
        FluentText("Document content \(index)")
    }
}
let overflowingTabHost = FluentTabView(
    items: overflowingTabItems,
    tabWidthMode: .equal,
    isAddTabButtonVisible: true
)._mount(in: FluentRenderContext(theme: theme))
overflowingTabHost.frame = NSRect(x: 0, y: 0, width: 330, height: 180)
overflowingTabHost.layoutSubtreeIfNeeded()
require(
    firstView(withAccessibilityTitle: "Scroll tabs left", in: overflowingTabHost)?.isHidden == false
        && firstView(withAccessibilityTitle: "Scroll tabs right", in: overflowingTabHost)?.isHidden == false,
    "TabView exposes source-sized scroll controls when minimum tab widths overflow"
)

let reducedTabHost = FluentTabView(
    items: Array(tabViewItems.prefix(2)),
    selectedIndex: FluentBinding(get: { 0 }, set: { _ in }),
    isAddTabButtonVisible: false
)._mount(in: FluentRenderContext(theme: theme, reduceMotion: true))
reducedTabHost.frame = NSRect(x: 0, y: 0, width: 360, height: 180)
reducedTabHost.layoutSubtreeIfNeeded()
let expandedReducedTabView = FluentTabView(
    items: tabViewItems,
    selectedIndex: FluentBinding(get: { 0 }, set: { _ in }),
    tabWidthMode: .compact,
    isAddTabButtonVisible: false
)
require(
    expandedReducedTabView._update(
        reducedTabHost,
        in: FluentRenderContext(theme: theme, reduceMotion: true)
    ),
    "Reduce Motion TabView accepts stable updates"
)
reducedTabHost.layoutSubtreeIfNeeded()
require(
    views(identifier: "FluentKit.TabView.Tab", in: reducedTabHost).allSatisfy {
        $0.layer?.animationKeys()?.isEmpty != false
    },
    "TabView Reduce Motion applies add and reorder changes without allocating animations"
)

let rtlTabHost = FluentTabView(
    items: Array(tabViewItems.prefix(2)),
    selectedIndex: FluentBinding(get: { 0 }, set: { _ in }),
    isAddTabButtonVisible: false
)._mount(in: FluentRenderContext(theme: theme, layoutDirection: .rightToLeft))
rtlTabHost.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
rtlTabHost.layoutSubtreeIfNeeded()
let rtlTabItems = views(identifier: "FluentKit.TabView.Tab", in: rtlTabHost)
require(
    rtlTabItems.count == 2 && rtlTabItems[0].frame.minX > rtlTabItems[1].frame.minX,
    "TabView mirrors logical tab order in RTL"
)
tabViewWindow.orderOut(nil)

let navigationPath = FluentState<[AnyHashable]>(wrappedValue: [])
struct ValidationNavigationItem {
    let id: String
    let title: String
}
let navigationItems = [
    ValidationNavigationItem(id: "home", title: "Home"),
    ValidationNavigationItem(id: "library", title: "Library"),
    ValidationNavigationItem(id: "settings", title: "Settings")
]
let navigationSelection = FluentState<String?>(wrappedValue: "library")
let navigationSidebarVisible = FluentState(wrappedValue: true)
let navigationSplit = FluentNavigationSplitView(
    navigationItems,
    id: \.id,
    selection: navigationSelection.projectedValue,
    isSidebarVisible: navigationSidebarVisible.projectedValue,
    sidebarWidth: 180...320,
    idealSidebarWidth: 220
) { item in
    FluentText(item.title)
} detail: { item in
    FluentText("Detail: \(item.title)")
} placeholder: {
    FluentText("No destination")
}
let navigationSplitView = navigationSplit._mount(in: FluentRenderContext())
navigationSplitView.frame = NSRect(x: 0, y: 0, width: 680, height: 300)
navigationSplitView.layoutSubtreeIfNeeded()
drainMainQueue()
navigationSplitView.layoutSubtreeIfNeeded()
let nativeNavigationSplit = firstSplitView(in: navigationSplitView)
require(nativeNavigationSplit?.subviews.count == 2, "navigation split view mounts sidebar and detail columns")
require(nativeNavigationSplit?.subviews.count == 2, "navigation split view initially exposes both columns")
require(labels(in: navigationSplitView).contains { $0.stringValue == "Detail: Library" }, "navigation split view resolves its initial stable selection")
navigationSelection.wrappedValue = "settings"
drainMainQueue()
require(labels(in: navigationSplitView).contains { $0.stringValue == "Detail: Settings" }, "external navigation selection updates the detail column")
navigationSidebarVisible.wrappedValue = false
drainMainQueue()
require(navigationSidebarVisible.wrappedValue == false, "sidebar visibility binding accepts collapse state")
navigationSidebarVisible.wrappedValue = true
drainMainQueue()
navigationSplitView.layoutSubtreeIfNeeded()
require(navigationSidebarVisible.wrappedValue == true, "sidebar visibility binding accepts restore state")
let reducedNavigationSplit = FluentNavigationSplitView(
    Array(navigationItems.prefix(2)),
    id: \.id,
    selection: navigationSelection.projectedValue,
    isSidebarVisible: navigationSidebarVisible.projectedValue,
    sidebarWidth: 180...320,
    idealSidebarWidth: 220
) { item in
    FluentText(item.title)
} detail: { item in
    FluentText("Detail: \(item.title)")
} placeholder: {
    FluentText("No destination")
}
require(reducedNavigationSplit._update(navigationSplitView, in: FluentRenderContext()), "navigation split view updates compatible content in place")
drainMainQueue()
require(firstSplitView(in: navigationSplitView) === nativeNavigationSplit, "navigation split view preserves its native split host during updates")
require(navigationSelection.wrappedValue == nil, "navigation split view clears selection when its destination is removed")
require(labels(in: navigationSplitView).contains { $0.stringValue == "No destination" }, "navigation split view shows placeholder content after selection is cleared")

let navigationViewItems = [
    FluentNavigationItem(id: "home", title: "Home", systemImageName: "house"),
    FluentNavigationItem(id: "library", title: "Library", systemImageName: "books.vertical"),
    FluentNavigationItem(id: "disabled", title: "Disabled", systemImageName: "nosign", isEnabled: false)
]
let navigationViewFooterItems = [
    FluentNavigationItem(id: "settings", title: "Settings", systemImageName: "gearshape")
]

struct NavigationPageProbe: FluentView {
    let selection: FluentState<String?>
    let transition: FluentNavigationTransitionMode

    var body: FluentNavigationView<String> {
        let page = selection.wrappedValue ?? "none"
        return FluentNavigationView(
            [
                FluentNavigationItem(id: "home", title: "Home", systemImageName: "house"),
                FluentNavigationItem(id: "library", title: "Library", systemImageName: "books.vertical"),
                FluentNavigationItem(id: "controls", title: "Controls", systemImageName: "slider.horizontal.3")
            ],
            selection: selection.projectedValue,
            paneDisplayMode: .top,
            contentTransition: transition
        ) {
            FluentText("Navigation page \(page)")
        }
    }
}

let navigationViewSelection = FluentState<String?>(wrappedValue: "home")
let navigationViewPaneOpen = FluentState(wrappedValue: true)
let reusableNavigation = FluentNavigationView(
    navigationViewItems,
    footerItems: navigationViewFooterItems,
    selection: navigationViewSelection.projectedValue,
    isPaneOpen: navigationViewPaneOpen.projectedValue,
    paneDisplayMode: .left,
    openPaneLength: 280,
    paneSectionTitle: "Explore",
    selectionIndicatorMode: .jump
) {
    FluentText("FluentKit")
        .padding(NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 12))
} content: {
    FluentText("Navigation content")
}
let reusableNavigationHost = FluentViewHost(reusableNavigation)
let reusableNavigationWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 520),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
reusableNavigationWindow.contentView = reusableNavigationHost
reusableNavigationHost.frame = NSRect(x: 0, y: 0, width: 900, height: 520)
reusableNavigationWindow.orderFront(nil)
reusableNavigationHost.layoutSubtreeIfNeeded()
drainMainQueue()
reusableNavigationHost.layoutSubtreeIfNeeded()
let reusablePane = firstView(identifier: "FluentKit.NavigationView.Pane", in: reusableNavigationHost)
let reusableContent = firstView(identifier: "FluentKit.NavigationView.Content", in: reusableNavigationHost)
let reusableSectionHeader = firstView(identifier: "FluentKit.NavigationView.SectionHeader", in: reusableNavigationHost)
let reusableToggle = firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: reusableNavigationHost) as? NSButton
let reusableIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: reusableNavigationHost)
require(
    reusablePane.flatMap(firstMaterialView)?.materialStyle == .mica
        && reusablePane.flatMap(firstMaterialView)?.isMaterialEnabled == true,
    "standalone NavigationView pane uses the global persistent Mica surface"
)
let reusablePreviousIndicator = firstLayer(named: "FluentKit.NavigationView.PreviousSelectionIndicator", in: reusableNavigationHost)
require(
    abs((reusablePane?.frame.width ?? 0) - 280) < 0.5
        && abs((reusableContent?.frame.minX ?? 0) - 280) < 0.5,
    "NavigationView left mode reserves the configured open pane length"
)
if let reusablePane, let paneMaterial = firstMaterialView(in: reusablePane) {
    require(
        paneMaterial.frame == reusablePane.bounds,
        "NavigationView standalone Mica surface fills the pane coordinate space"
    )
}
require(
    reusableIndicator?.frame.size == NSSize(width: 3, height: 16)
        && reusablePreviousIndicator?.opacity == 0,
    "NavigationView exposes the shared vertical indicator geometry"
)
if let reusablePane,
   let homeButton = firstView(withAccessibilityTitle: "Home", in: reusableNavigationHost),
   let reusableIndicator {
    let homeFrame = homeButton.convert(homeButton.bounds, to: reusablePane)
    require(
        abs(reusableIndicator.frame.midY - homeFrame.midY) < 0.5
            && abs(reusableIndicator.frame.minX - (homeFrame.minX + 2)) < 0.5,
        "NavigationView commits the first item frame and indicator frame in one layout pass"
    )
}
require(
    FluentNavigationSelectionIndicatorMode.allCases == [.jump, .continuous, .adaptive],
    "NavigationView publicly exposes jump, continuous, and adaptive indicator modes"
)
require(
    FluentWindowConfiguration(
        layout: .settings,
        selectionIndicatorMode: .continuous
    ).selectionIndicatorMode == .continuous,
    "WindowShell forwards the public NavigationView selection-indicator mode"
)

let indicatorModeItems = (0..<8).map {
    FluentNavigationItem(id: "mode-row-\($0)", title: "Mode row \($0)", systemImageName: "circle")
}
func indicatorModeNavigation(
    selection: FluentState<String?>,
    mode: FluentNavigationSelectionIndicatorMode
) -> FluentNavigationView<String> {
    FluentNavigationView(
        indicatorModeItems,
        selection: selection.projectedValue,
        paneDisplayMode: .left,
        openPaneLength: 220,
        selectionIndicatorMode: mode
    ) {
        FluentText("Indicator mode")
    }
}
func mountIndicatorModeNavigation(
    selection: FluentState<String?>,
    mode: FluentNavigationSelectionIndicatorMode,
    reduceMotion: Bool = false
) -> (FluentViewHost<FluentNavigationView<String>>, NSWindow) {
    let host = FluentViewHost(
        indicatorModeNavigation(selection: selection, mode: mode),
        context: FluentRenderContext(reduceMotion: reduceMotion)
    )
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    drainMainQueue()
    return (host, window)
}

let jumpModeSelection = FluentState<String?>(wrappedValue: "mode-row-0")
let (jumpModeHost, jumpModeWindow) = mountIndicatorModeNavigation(
    selection: jumpModeSelection,
    mode: .jump
)
let jumpModeIndicator = firstLayer(
    named: "FluentKit.NavigationView.SelectionIndicator",
    in: jumpModeHost
)
let jumpModePrevious = firstLayer(
    named: "FluentKit.NavigationView.PreviousSelectionIndicator",
    in: jumpModeHost
)
jumpModeSelection.wrappedValue = "mode-row-7"
drainMainQueue()
let jumpModeGroup = jumpModeIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
let jumpModeOutgoingGroup = jumpModePrevious?.animation(
    forKey: "fluent.navigation.selection.outgoing"
) as? CAAnimationGroup
let jumpModeIncomingHeight = (keyframeAnimation(
    for: "bounds.size",
    in: jumpModeGroup
)?.values?[1] as? NSValue)?.sizeValue.height
let jumpModeIncomingStartHeight = (keyframeAnimation(
    for: "bounds.size",
    in: jumpModeGroup
)?.values?[0] as? NSValue)?.sizeValue.height
let jumpModeIncomingFinalHeight = (keyframeAnimation(
    for: "bounds.size",
    in: jumpModeGroup
)?.values?.last as? NSValue)?.sizeValue.height
let jumpModeOutgoingHeight = (keyframeAnimation(
    for: "bounds.size",
    in: jumpModeOutgoingGroup
)?.values?[1] as? NSValue)?.sizeValue.height
let jumpModeIncomingCenter = (keyframeAnimation(
    for: "position",
    in: jumpModeGroup
)?.values?[1] as? NSValue)?.pointValue
let jumpModeOutgoingCenter = (keyframeAnimation(
    for: "position",
    in: jumpModeOutgoingGroup
)?.values?[1] as? NSValue)?.pointValue
let jumpModeSegmentGap: CGFloat? = {
    guard let jumpModeIncomingCenter, let jumpModeOutgoingCenter else { return nil }
    return abs(jumpModeIncomingCenter.y - jumpModeOutgoingCenter.y)
        - (jumpModeIncomingHeight ?? 0) / 2
        - (jumpModeOutgoingHeight ?? 0) / 2
}()
require(
    jumpModeOutgoingGroup != nil
        && abs((jumpModeGroup?.duration ?? 0) - 0.6) < 0.000_1
        && jumpModeIncomingStartHeight == jumpModeIncomingHeight
        && jumpModeIncomingHeight.flatMap { intermediate in
            jumpModeIncomingFinalHeight.map { intermediate > $0 }
        } == true
        && jumpModeOutgoingHeight.map { $0 <= 56.001 } == true
        && jumpModeSegmentGap.map { $0 > 1 } == true
        && keyframeAnimation(for: "opacity", in: jumpModeGroup) != nil
        && keyframeAnimation(for: "opacity", in: jumpModeOutgoingGroup) != nil,
    "jump NavigationView mode expands the source mask, then contracts the destination mask"
)

let continuousModeSelection = FluentState<String?>(wrappedValue: "mode-row-0")
let (continuousModeHost, continuousModeWindow) = mountIndicatorModeNavigation(
    selection: continuousModeSelection,
    mode: .continuous
)
let continuousModeIndicator = firstLayer(
    named: "FluentKit.NavigationView.SelectionIndicator",
    in: continuousModeHost
)
let continuousModePrevious = firstLayer(
    named: "FluentKit.NavigationView.PreviousSelectionIndicator",
    in: continuousModeHost
)
let continuousSourceFrame = continuousModeIndicator?.frame ?? .zero
continuousModeSelection.wrappedValue = "mode-row-7"
drainMainQueue()
let continuousIncomingGroup = continuousModeIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
let continuousOutgoingGroup = continuousModePrevious?.animation(
    forKey: "fluent.navigation.selection.outgoing"
) as? CAAnimationGroup
let continuousConnectedHeight = (keyframeAnimation(
    for: "bounds.size",
    in: continuousIncomingGroup
)?.values?[1] as? NSValue)?.sizeValue.height
let continuousOpacity = keyframeAnimation(for: "opacity", in: continuousOutgoingGroup)
let continuousFullSpan = continuousSourceFrame.union(continuousModeIndicator?.frame ?? .zero).height
require(
    continuousIncomingGroup != nil
        && continuousOutgoingGroup == nil
        && continuousConnectedHeight.map { $0 <= 56.001 } == true
        && continuousConnectedHeight.map { $0 < continuousFullSpan } == true
        && continuousOpacity == nil,
    "continuous NavigationView mode keeps one connected compact rail"
)

let adaptiveModeSelection = FluentState<String?>(wrappedValue: "mode-row-0")
let (adaptiveModeHost, adaptiveModeWindow) = mountIndicatorModeNavigation(
    selection: adaptiveModeSelection,
    mode: .adaptive
)
let adaptiveModePrevious = firstLayer(
    named: "FluentKit.NavigationView.PreviousSelectionIndicator",
    in: adaptiveModeHost
)
adaptiveModeSelection.wrappedValue = "mode-row-1"
drainMainQueue()
require(
    adaptiveModePrevious?.animation(forKey: "fluent.navigation.selection.outgoing") == nil,
    "adaptive NavigationView mode stays continuous for a nearby destination"
)
adaptiveModeSelection.wrappedValue = "mode-row-7"
drainMainQueue()
require(
    adaptiveModePrevious?.animation(forKey: "fluent.navigation.selection.outgoing") != nil,
    "adaptive NavigationView mode switches to the two-rail jump for a distant destination"
)

let reducedIndicatorModeSelection = FluentState<String?>(wrappedValue: "mode-row-0")
let (reducedIndicatorModeHost, reducedIndicatorModeWindow) = mountIndicatorModeNavigation(
    selection: reducedIndicatorModeSelection,
    mode: .continuous,
    reduceMotion: true
)
let reducedIndicatorModeCurrent = firstLayer(
    named: "FluentKit.NavigationView.SelectionIndicator",
    in: reducedIndicatorModeHost
)
let reducedIndicatorModePrevious = firstLayer(
    named: "FluentKit.NavigationView.PreviousSelectionIndicator",
    in: reducedIndicatorModeHost
)
reducedIndicatorModeSelection.wrappedValue = "mode-row-7"
drainMainQueue()
require(
    reducedIndicatorModeCurrent?.animation(forKey: "fluent.navigation.selection") == nil
        && reducedIndicatorModePrevious?.animation(forKey: "fluent.navigation.selection.outgoing") == nil,
    "NavigationView indicator modes all snap directly to their target under Reduce Motion"
)
jumpModeWindow.orderOut(nil)
continuousModeWindow.orderOut(nil)
adaptiveModeWindow.orderOut(nil)
reducedIndicatorModeWindow.orderOut(nil)

let navigationItemButtons = views(identifier: "FluentKit.NavigationView.Item", in: reusableNavigationHost)
navigationItemButtons.forEach {
    $0.updateTrackingAreas()
    $0.updateTrackingAreas()
}
require(
    navigationItemButtons.allSatisfy { $0.trackingAreas.count == 1 },
    "NavigationView items keep one visible-rect tracking area across repeated layout updates"
)
if let libraryButton = firstView(withAccessibilityTitle: "Library", in: reusableNavigationHost),
   let settingsButton = firstView(withAccessibilityTitle: "Settings", in: reusableNavigationHost) {
    let libraryRestingAlpha = renderedBackgroundAlpha(in: libraryButton)
    let settingsRestingAlpha = renderedBackgroundAlpha(in: settingsButton)
    libraryButton.mouseEntered(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: 12, y: libraryButton.bounds.midY),
            in: libraryButton,
            eventNumber: 88
        )
    )
    let libraryHoverAlpha = renderedBackgroundAlpha(in: libraryButton)
    settingsButton.mouseEntered(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: 12, y: settingsButton.bounds.midY),
            in: settingsButton,
            eventNumber: 89
        )
    )
    require(
        libraryHoverAlpha > libraryRestingAlpha + 0.01
            && abs(renderedBackgroundAlpha(in: libraryButton) - libraryRestingAlpha) < 0.01
            && renderedBackgroundAlpha(in: settingsButton) > settingsRestingAlpha + 0.01,
        "NavigationView owns one PointerOver destination across primary and footer presenters"
    )
    settingsButton.mouseExited(
        with: toggleMouseEvent(
            .mouseMoved,
            at: NSPoint(x: -1, y: -1),
            in: settingsButton,
            eventNumber: 90
        )
    )
}
require(
    navigationItemButtons.count == 4,
    "NavigationView mounts primary and footer items through one presenter"
)
require(
    reusableSectionHeader?.frame.height == 40
        && reusableSectionHeader?.layer?.masksToBounds == true
        && reusableSectionHeader?.isHidden == false,
    "NavigationView section text is hosted in a clipped 40pt WinUI header region"
)
navigationViewSelection.wrappedValue = "settings"
drainMainQueue()
let footerIncoming = reusableIndicator?.animation(forKey: "fluent.navigation.selection") as? CAAnimationGroup
require(
    footerIncoming != nil
        && reusablePreviousIndicator?.animation(forKey: "fluent.navigation.selection.outgoing") != nil,
    "jump NavigationView animates the outgoing and incoming rails between primary and footer destinations"
)
if let reusablePane,
   let settingsButton = firstView(withAccessibilityTitle: "Settings", in: reusableNavigationHost),
   let reusableIndicator,
   let footerIncoming {
    let settingsFrame = settingsButton.convert(settingsButton.bounds, to: reusablePane)
    let targetCenterY = settingsFrame.midY
    let animatedCenterY = keyframeAnimation(for: "position", in: footerIncoming)?.values?.last
        .flatMap { ($0 as? NSValue)?.pointValue.y }
    require(
        abs(reusableIndicator.frame.midY - targetCenterY) < 0.5
            && animatedCenterY.map { abs($0 - targetCenterY) < 0.5 } == true,
        "NavigationView indicator animation ends on the selected footer row center"
    )
}
require(
    firstView(withAccessibilityTitle: "Settings", in: reusableNavigationHost)?.accessibilityValue() as? String == "Selected",
    "NavigationView synchronizes selected accessibility state"
)
let selectionBeforeDisabledActivation = navigationViewSelection.wrappedValue
(firstView(withAccessibilityTitle: "Disabled", in: reusableNavigationHost) as? NSButton)?.performClick(nil)
drainMainQueue()
require(
    navigationViewSelection.wrappedValue == selectionBeforeDisabledActivation,
    "NavigationView disabled destinations cannot change selection"
)
navigationViewSelection.wrappedValue = "home"
drainMainQueue()
RunLoop.main.run(until: Date(timeIntervalSinceNow: FluentMotion.navigationIndicator.duration + 0.02))
reusableToggle?.performClick(nil)
let paneCloseAnimation = reusablePane?.layer?.animation(forKey: "fluent.navigation.pane.frame")
let paneIndicatorReposition = reusableIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
let sectionRepositionAnimation = firstView(
    identifier: "FluentKit.NavigationView.PrimaryScroll",
    in: reusableNavigationHost
)?.layer?.animation(forKey: "fluent.navigation.header.frame") as? CAAnimationGroup
let sectionHeaderAnimation = reusablePane.flatMap { pane in
    labels(in: pane).first { $0.stringValue == "Explore" }
}?.layer?.animation(forKey: "fluent.navigation.header.opacity")
drainMainQueue()
require(
    navigationViewPaneOpen.wrappedValue == false
        && abs((reusablePane?.frame.width ?? 0) - 48) < 0.5
        && abs((reusableContent?.frame.minX ?? 0) - 48) < 0.5,
    "NavigationView left mode closes to the 48pt compact rail"
)
require(
    paneCloseAnimation != nil,
    "NavigationView pane close uses explicit completion-trackable frame motion"
)
require(
    sectionHeaderAnimation != nil,
    "NavigationView fades its section text through the header transition"
)
require(
    sectionRepositionAnimation?.animations?.compactMap { ($0 as? CAPropertyAnimation)?.keyPath }
        == ["position", "bounds.size"]
        && abs((sectionRepositionAnimation?.duration ?? 0) - FluentMotion.navigationHeaderClose.duration) < 0.0001
        && paneIndicatorReposition?.animations?.compactMap { ($0 as? CAPropertyAnimation)?.keyPath }
            == ["position", "bounds.size"]
        && abs((paneIndicatorReposition?.duration ?? 0) - FluentMotion.navigationHeaderClose.duration) < 0.0001,
    "NavigationView closes items and their selection rail through the same source-derived 100ms transition"
)
require(
    reusableSectionHeader?.isHidden == true
        && reusableSectionHeader?.frame.height == 0
        && reusablePane.flatMap { pane in labels(in: pane).first { $0.stringValue == "Explore" } }?.isHidden == true,
    "NavigationView removes the header region before the compact pane can clip its text"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: FluentMotion.navigationHeaderClose.duration + 0.03))
require(
    reusablePane.flatMap { pane in labels(in: pane).first { $0.stringValue == "Explore" } }?.isHidden == true,
    "NavigationView collapses section text after the header fade completes"
)
require(
    (firstView(withAccessibilityTitle: "Home", in: reusableNavigationHost) as? NSButton)?.toolTip == "Home"
        && (firstView(withAccessibilityTitle: "Settings", in: reusableNavigationHost) as? NSButton)?.toolTip == "Settings",
    "NavigationView keeps compact item presenters after a manually closed left pane settles"
)
if let reusablePane,
   let selectedButton = firstView(withAccessibilityTitle: "Home", in: reusableNavigationHost),
   let reusableIndicator {
    let selectedFrame = selectedButton.convert(selectedButton.bounds, to: reusablePane)
    require(
        abs(reusableIndicator.frame.midY - selectedFrame.midY) < 0.5,
        "NavigationView keeps the selected primary indicator aligned while collapsed"
    )
}
reusableToggle?.performClick(nil)
drainMainQueue()
let sectionHeaderOpenAnimation = reusablePane.flatMap { pane in
    labels(in: pane).first { $0.stringValue == "Explore" }
}?.layer?.animation(forKey: "fluent.navigation.header.opacity") as? CAKeyframeAnimation
require(
    navigationViewPaneOpen.wrappedValue == true && abs((reusablePane?.frame.width ?? 0) - 280) < 0.5,
    "rapid NavigationView pane reversal settles on the latest requested state"
)
require(
    sectionHeaderOpenAnimation?.values?.count == 3
        && sectionHeaderOpenAnimation?.keyTimes == [0, 0.5, 1]
        && sectionHeaderOpenAnimation?.timingFunctions?.count == 2
        && sectionHeaderOpenAnimation?.timingFunction == nil,
    "NavigationView header opens with the source-derived delayed 200ms opacity sequence"
)
if let reusablePane,
   let selectedButton = firstView(withAccessibilityTitle: "Home", in: reusableNavigationHost),
   let reusableIndicator {
    let selectedFrame = selectedButton.convert(selectedButton.bounds, to: reusablePane)
    require(
        abs(reusableIndicator.frame.midY - selectedFrame.midY) < 0.5,
        "NavigationView recomputes the selected indicator after pane reopen"
    )
}

let scrollingItems = (0..<12).map {
    FluentNavigationItem(id: "row-\($0)", title: "Row \($0)", systemImageName: "circle")
}
let scrollingSelection = FluentState<String?>(wrappedValue: "row-0")
let scrollingNavigation = FluentNavigationView(
    scrollingItems,
    selection: scrollingSelection.projectedValue,
    paneDisplayMode: .left,
    openPaneLength: 220,
    paneSectionTitle: nil
) {
    FluentText("Scrolling content")
}
let scrollingHost = FluentViewHost(scrollingNavigation)
let scrollingWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 220),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
scrollingWindow.contentView = scrollingHost
scrollingHost.frame = NSRect(x: 0, y: 0, width: 640, height: 220)
scrollingWindow.orderFront(nil)
scrollingHost.layoutSubtreeIfNeeded()
let primaryScroll = firstView(identifier: "FluentKit.NavigationView.PrimaryScroll", in: scrollingHost) as? NSScrollView
let scrollingIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: scrollingHost)
scrollingSelection.wrappedValue = "row-5"
drainMainQueue()
if let primaryScroll,
   let rowButton = firstView(withAccessibilityTitle: "Row 5", in: scrollingHost) as? NSButton,
   let scrollingIndicator {
    primaryScroll.contentView.scroll(to: NSPoint(x: 0, y: max(rowButton.frame.minY - 12, 0)))
    primaryScroll.reflectScrolledClipView(primaryScroll.contentView)
    drainMainQueue()
    if let pane = firstView(identifier: "FluentKit.NavigationView.Pane", in: scrollingHost) {
        let rowFrame = rowButton.convert(rowButton.bounds, to: pane)
        require(
            abs(scrollingIndicator.frame.midY - rowFrame.midY) < 0.5,
            "NavigationView refreshes the indicator from stable document coordinates after scrolling"
        )
    }
}
scrollingWindow.orderOut(nil)

let automaticSelection = FluentState<String?>(wrappedValue: "home")
let automaticPaneOpen = FluentState(wrappedValue: true)
var automaticDisplayModes: [FluentNavigationViewDisplayMode] = []
let automaticNavigation = FluentNavigationView(
    navigationViewItems,
    selection: automaticSelection.projectedValue,
    isPaneOpen: automaticPaneOpen.projectedValue,
    paneDisplayMode: .automatic,
    onDisplayModeChange: { automaticDisplayModes.append($0) }
) {
    FluentText("Adaptive content")
}
let automaticHost = FluentViewHost(automaticNavigation)
let automaticWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
automaticWindow.contentView = automaticHost
automaticHost.frame = NSRect(x: 0, y: 0, width: 800, height: 420)
automaticWindow.orderFront(nil)
automaticHost.layoutSubtreeIfNeeded()
let automaticPane = firstView(identifier: "FluentKit.NavigationView.Pane", in: automaticHost)
let automaticContent = firstView(identifier: "FluentKit.NavigationView.Content", in: automaticHost)
let automaticPaneMaterial = firstView(
    identifier: "FluentKit.NavigationView.PaneMaterial",
    in: automaticHost
) as? FluentMaterialView
require(
    automaticDisplayModes.last == .compact
        && automaticPaneOpen.wrappedValue == false
        && abs((automaticPane?.frame.width ?? 0) - 48) < 0.5,
    "NavigationView Auto resolves 800pt to closed Compact mode"
)
require(
    automaticPaneMaterial?.materialStyle == .mica
        && automaticPane.map(materialViews(in:))?.count == 1,
    "a standalone NavigationView automatically owns one persistent Mica pane surface"
)
automaticHost.frame = NSRect(x: 0, y: 0, width: 1_200, height: 420)
automaticHost.layoutSubtreeIfNeeded()
require(
    automaticDisplayModes.last == .expanded
        && automaticPaneOpen.wrappedValue == true
        && abs((automaticPane?.frame.width ?? 0) - 320) < 0.5,
    "NavigationView Auto resolves the 1008pt threshold to Expanded mode"
)
automaticHost.frame = NSRect(x: 0, y: 0, width: 500, height: 420)
automaticHost.layoutSubtreeIfNeeded()
let minimalToggle = firstView(identifier: "FluentKit.NavigationView.MinimalPaneToggle", in: automaticHost)
require(
    automaticDisplayModes.last == .minimal
        && automaticPaneOpen.wrappedValue == false
        && abs((automaticPane?.frame.width ?? -1)) < 0.5
        && abs((automaticContent?.frame.minX ?? -1)) < 0.5
        && minimalToggle?.isHidden == false,
    "NavigationView Auto resolves below 641pt to Minimal mode with an external toggle"
)
(minimalToggle as? NSButton)?.performClick(nil)
drainMainQueue()
let automaticDismissLayer = firstView(identifier: "FluentKit.NavigationView.DismissLayer", in: automaticHost)
require(
    automaticPaneOpen.wrappedValue == true
        && abs((automaticPane?.frame.width ?? 0) - 320) < 0.5
        && automaticDismissLayer?.isHidden == false,
    "Minimal NavigationView opens an overlay pane without moving content"
)
let automaticPaneToggle = firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: automaticHost) as? NSButton
automaticPaneToggle?.performClick(nil)
drainMainQueue()
let dismissAnimation = automaticDismissLayer?.layer?.animation(forKey: "fluent.navigation.dimming") as? CABasicAnimation
require(
    automaticPaneOpen.wrappedValue == false
        && (dismissAnimation?.toValue as? NSNumber)?.doubleValue == 0,
    "Minimal NavigationView fades its dismiss layer through the pane close motion"
)

let topSelection = FluentState<String?>(wrappedValue: "home")
let topNavigation = FluentNavigationView(
    Array(navigationViewItems.prefix(2)),
    footerItems: navigationViewFooterItems,
    selection: topSelection.projectedValue,
    paneDisplayMode: .top
) {
    FluentText("Top content")
}
let topHost = FluentViewHost(topNavigation)
let topWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
topWindow.contentView = topHost
topHost.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
topWindow.orderFront(nil)
topHost.layoutSubtreeIfNeeded()
let topPane = firstView(identifier: "FluentKit.NavigationView.Pane", in: topHost)
let topContent = firstView(identifier: "FluentKit.NavigationView.Content", in: topHost)
let topIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: topHost)
require(
    abs((topPane?.frame.height ?? 0) - 48) < 0.5
        && abs((topContent?.frame.height ?? 0) - 372) < 0.5
        && topIndicator?.frame.size == NSSize(width: 16, height: 3),
    "NavigationView Top mode reserves a 48pt bar and uses a horizontal indicator"
)
topSelection.wrappedValue = "library"
drainMainQueue()
let topIndicatorGroup = topIndicator?.animation(forKey: "fluent.navigation.selection") as? CAAnimationGroup
let topPosition = keyframeAnimation(for: "position", in: topIndicatorGroup)
let topBounds = keyframeAnimation(for: "bounds.size", in: topIndicatorGroup)
let topIntermediateWidth = ((topBounds?.values?[1] as? NSValue)?.sizeValue.width ?? -1)
let topFinalWidth = ((topBounds?.values?.last as? NSValue)?.sizeValue.width ?? -1)
require(
    topPosition?.values?.count == 3
        && topBounds?.values?.count == 3
        && (topIntermediateWidth > topFinalWidth || abs(topIntermediateWidth) < 0.001)
        && topFinalWidth > 0,
    "Top NavigationView uses horizontal connected motion or the adaptive two-phase jump"
)

let overflowItems = [
    FluentNavigationItem(id: "overview", title: "Overview", systemImageName: "square.grid.2x2"),
    FluentNavigationItem(id: "controls", title: "Controls", systemImageName: "slider.horizontal.3"),
    FluentNavigationItem(id: "inputs", title: "Inputs and forms", systemImageName: "keyboard"),
    FluentNavigationItem(id: "collections", title: "Collections", systemImageName: "square.grid.3x3")
]
let overflowSelection = FluentState<String?>(wrappedValue: "collections")
let overflowNavigation = FluentNavigationView(
    overflowItems,
    selection: overflowSelection.projectedValue,
    paneDisplayMode: .top
) {
    FluentText("Overflow content")
}
let overflowHost = FluentViewHost(overflowNavigation)
let overflowWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
overflowWindow.contentView = overflowHost
overflowHost.frame = NSRect(x: 0, y: 0, width: 360, height: 320)
overflowWindow.orderFront(nil)
overflowHost.layoutSubtreeIfNeeded()
let overflowButton = firstView(identifier: "FluentKit.NavigationView.Overflow", in: overflowHost) as? NSButton
let overflowIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: overflowHost)
require(
    overflowButton?.isHidden == false
        && overflowButton?.accessibilityValue() as? String == "Contains selected item"
        && abs((overflowIndicator?.frame.midX ?? 0) - (overflowButton?.frame.midX ?? -1)) < 0.5,
    "Top NavigationView routes hidden selection and its indicator through More"
)
overflowButton?.performClick(nil)
drainMainQueue()
let overflowMenuItem = overflowWindow.childWindows?
    .compactMap(\.contentView)
    .compactMap { firstView(withAccessibilityTitle: "Inputs and forms", in: $0) }
    .first
require(
    overflowMenuItem?.accessibilityPerformPress() == true,
    "Top NavigationView overflow presents hidden destinations through FluentMenuFlyout"
)
drainMainQueue()
require(
    overflowSelection.wrappedValue == "inputs",
    "Top NavigationView overflow actions update the shared selection binding"
)

let rtlOverflowSelection = FluentState<String?>(wrappedValue: "collections")
let rtlOverflowNavigation = FluentNavigationView(
    overflowItems,
    selection: rtlOverflowSelection.projectedValue,
    paneDisplayMode: .top
) {
    FluentText("RTL overflow content")
}
let rtlOverflowHost = FluentViewHost(
    rtlOverflowNavigation,
    context: FluentRenderContext(layoutDirection: .rightToLeft)
)
let rtlOverflowWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
rtlOverflowWindow.contentView = rtlOverflowHost
rtlOverflowHost.frame = NSRect(x: 0, y: 0, width: 360, height: 320)
rtlOverflowWindow.orderFront(nil)
rtlOverflowHost.layoutSubtreeIfNeeded()
let rtlOverflowButton = firstView(identifier: "FluentKit.NavigationView.Overflow", in: rtlOverflowHost)
let rtlVisibleItem = views(identifier: "FluentKit.NavigationView.Item", in: rtlOverflowHost).first { !$0.isHidden }
require(
    (rtlOverflowButton?.frame.maxX ?? 0) <= (rtlVisibleItem?.frame.minX ?? -1),
    "Top NavigationView mirrors the More and visible-item ordering in RTL"
)

let reducedPaneOpen = FluentState(wrappedValue: false)
let reducedNavigationView = FluentNavigationView(
    navigationViewItems,
    selection: FluentState<String?>(wrappedValue: "home").projectedValue,
    isPaneOpen: reducedPaneOpen.projectedValue,
    paneDisplayMode: .leftCompact,
    paneSectionTitle: "Explore"
) {
    FluentText("Reduced motion content")
}
let reducedNavigationViewHost = FluentViewHost(
    reducedNavigationView,
    context: FluentRenderContext(reduceMotion: true)
)
let reducedNavigationWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
reducedNavigationWindow.contentView = reducedNavigationViewHost
reducedNavigationViewHost.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
reducedNavigationWindow.orderFront(nil)
reducedNavigationViewHost.layoutSubtreeIfNeeded()
let reducedPane = firstView(identifier: "FluentKit.NavigationView.Pane", in: reducedNavigationViewHost)
let reducedSectionHeader = firstView(identifier: "FluentKit.NavigationView.SectionHeader", in: reducedNavigationViewHost)
(firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: reducedNavigationViewHost) as? NSButton)?.performClick(nil)
drainMainQueue()
require(
    reducedPaneOpen.wrappedValue == true
        && reducedPane?.layer?.animation(forKey: "fluent.navigation.pane.frame") == nil
        && reducedSectionHeader?.layer?.animation(forKey: "fluent.navigation.header.opacity") == nil
        && reducedSectionHeader?.isHidden == false
        && reducedSectionHeader?.frame.height == 40,
    "NavigationView Reduce Motion snaps pane geometry without allocating frame animation"
)

let rtlCompactSelection = FluentState<String?>(wrappedValue: "home")
let rtlCompactNavigation = FluentNavigationView(
    navigationViewItems,
    selection: rtlCompactSelection.projectedValue,
    isPaneOpen: FluentState(wrappedValue: false).projectedValue,
    paneDisplayMode: .leftCompact,
    paneSectionTitle: "Explore"
) {
    FluentText("RTL compact content")
}
let rtlCompactHost = FluentViewHost(
    rtlCompactNavigation,
    context: FluentRenderContext(
        theme: FluentTheme.custom(contrast: .high, colorScheme: .light),
        reduceMotion: true,
        layoutDirection: .rightToLeft
    )
)
let rtlCompactWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
rtlCompactWindow.contentView = rtlCompactHost
rtlCompactHost.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
rtlCompactWindow.orderFront(nil)
rtlCompactHost.layoutSubtreeIfNeeded()
let rtlCompactPane = firstView(identifier: "FluentKit.NavigationView.Pane", in: rtlCompactHost)
let rtlCompactHome = firstView(withAccessibilityTitle: "Home", in: rtlCompactHost)
let rtlCompactIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: rtlCompactHost)
let rtlCompactHeader = firstView(identifier: "FluentKit.NavigationView.SectionHeader", in: rtlCompactHost)
if let rtlCompactPane, let rtlCompactHome, let rtlCompactIndicator {
    let itemFrame = rtlCompactHome.convert(rtlCompactHome.bounds, to: rtlCompactPane)
    require(
        abs(rtlCompactPane.frame.minX - 712) < 0.5
            && abs(rtlCompactHome.frame.minX - 4) < 0.5
            && abs(rtlCompactHome.frame.width - 40) < 0.5
            && abs(rtlCompactIndicator.frame.maxX - (itemFrame.maxX - 2)) < 0.5
            && rtlCompactHeader?.isHidden == true,
        "RTL compact NavigationView keeps the 48pt rail, right-edge indicator, and hidden header aligned"
    )
}

let pageTransitionSelection = FluentState<String?>(wrappedValue: "home")
let pageTransitionHost = FluentViewHost(
    NavigationPageProbe(selection: pageTransitionSelection, transition: .slide)
)
let pageTransitionWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
pageTransitionWindow.contentView = pageTransitionHost
pageTransitionHost.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
pageTransitionWindow.orderFront(nil)
pageTransitionHost.layoutSubtreeIfNeeded()
pageTransitionSelection.wrappedValue = "library"
drainMainQueue()
let pagePresenter = firstView(identifier: "FluentKit.NavigationView.Content", in: pageTransitionHost)
let forwardEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: pageTransitionHost)
let forwardOutgoing = forwardEntries.first
let forwardIncoming = forwardEntries.last
let pageIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: pageTransitionHost)
require(
    forwardEntries.count == 2,
    "NavigationView retains outgoing and incoming pages while its owned transition is active"
)
require(
    forwardOutgoing?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil
        && forwardOutgoing?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil
        && forwardIncoming?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil
        && forwardIncoming?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil,
    "NavigationView page transitions use explicit coordinated opacity and transform animations"
)
let forwardTransform = forwardIncoming?.layer?
    .animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation
let forwardOffset = (forwardTransform?.fromValue as? NSValue)?.caTransform3DValue.m41
require(
    forwardOffset.map { $0 > 0 } == true,
    "forward Top navigation enters from the source-recommended trailing direction"
)
require(
    pageIndicator?.animation(forKey: "fluent.navigation.selection") != nil
        && pagePresenter?.layer?.animation(forKey: "fluent.navigation.page.cleanup") != nil,
    "NavigationView selection-indicator and page-transition coordinators run without overwriting each other"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
let entrancePhaseEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: pageTransitionHost)
require(
    entrancePhaseEntries.count == 1
        && entrancePhaseEntries[0].layer?.animation(forKey: "fluent.navigation.page.transform") != nil,
    "NavigationView removes the outgoing page after 150ms while the incoming 300ms phase continues"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.30))
require(
    views(identifier: "FluentKit.NavigationView.ContentEntry", in: pageTransitionHost).count == 1
        && labels(in: pageTransitionHost).contains { $0.stringValue == "Navigation page library" },
    "NavigationView completion removes the outgoing page and keeps the selected destination"
)

pageTransitionSelection.wrappedValue = "home"
drainMainQueue()
let backwardEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: pageTransitionHost)
let backwardOutgoingTransform = backwardEntries.first?.layer?
    .animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation
let backwardOffset = (backwardOutgoingTransform?.toValue as? NSValue)?.caTransform3DValue.m41
require(
    backwardOffset.map { $0 > 0 } == true,
    "backward Top navigation reverses the outgoing Slide direction"
)
pageTransitionSelection.wrappedValue = "library"
drainMainQueue()
pageTransitionSelection.wrappedValue = "controls"
drainMainQueue()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.55))
require(
    views(identifier: "FluentKit.NavigationView.ContentEntry", in: pageTransitionHost).count == 1
        && labels(in: pageTransitionHost).contains { $0.stringValue == "Navigation page controls" },
    "rapid NavigationView selection changes settle on one final page without stale entries"
)

let entranceSelection = FluentState<String?>(wrappedValue: "home")
let entranceHost = FluentViewHost(
    NavigationPageProbe(selection: entranceSelection, transition: .entrance)
)
let entranceWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
entranceWindow.contentView = entranceHost
entranceHost.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
entranceWindow.orderFront(nil)
entranceHost.layoutSubtreeIfNeeded()
entranceSelection.wrappedValue = "library"
drainMainQueue()
let entranceForwardEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: entranceHost)
let entranceForwardOutgoing = entranceForwardEntries.first
let entranceForwardIncoming = entranceForwardEntries.last
let entranceForwardTransform = entranceForwardIncoming?.layer?
    .animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation
let entranceForwardOffset = (entranceForwardTransform?.fromValue as? NSValue)?.caTransform3DValue.m42
require(
    entranceForwardOutgoing?.layer?.animation(forKey: "fluent.navigation.page.transform") == nil
        && entranceForwardOutgoing?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil
        && entranceForwardOffset.map { $0 < 0 } == true,
    "Entrance forward follows WinUI: outgoing fades while incoming starts below the page"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.50))
entranceSelection.wrappedValue = "home"
drainMainQueue()
let entranceBackwardEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: entranceHost)
let entranceBackwardOutgoing = entranceBackwardEntries.first
let entranceBackwardIncoming = entranceBackwardEntries.last
let entranceBackwardTransform = entranceBackwardOutgoing?.layer?
    .animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation
let entranceBackwardOffset = (entranceBackwardTransform?.toValue as? NSValue)?.caTransform3DValue.m42
require(
    entranceBackwardOffset.map { $0 < 0 } == true
        && entranceBackwardIncoming?.layer?.animation(forKey: "fluent.navigation.page.transform") == nil
        && entranceBackwardIncoming?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil,
    "Entrance backward follows WinUI: outgoing moves below while incoming only fades in"
)
entranceWindow.orderOut(nil)

let reducedPageSelection = FluentState<String?>(wrappedValue: "home")
let reducedPageHost = FluentViewHost(
    NavigationPageProbe(selection: reducedPageSelection, transition: .slide),
    context: FluentRenderContext(reduceMotion: true)
)
reducedPageSelection.wrappedValue = "library"
drainMainQueue()
let reducedPageEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: reducedPageHost)
require(
    reducedPageEntries.count == 1
        && reducedPageEntries[0].layer?.animationKeys()?.isEmpty != false,
    "NavigationView Reduce Motion replaces page content without allocating transition animations"
)

let suppressedPageSelection = FluentState<String?>(wrappedValue: "home")
let suppressedPageHost = FluentViewHost(
    NavigationPageProbe(selection: suppressedPageSelection, transition: .suppress)
)
suppressedPageSelection.wrappedValue = "library"
drainMainQueue()
let suppressedPageEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: suppressedPageHost)
require(
    suppressedPageEntries.count == 1
        && suppressedPageEntries[0].layer?.animationKeys()?.isEmpty != false,
    "NavigationView suppress mode uses an empty structural transition"
)
pageTransitionWindow.orderOut(nil)

let bottomUpSelection = FluentState<String?>(wrappedValue: "home")
let bottomUpHost = FluentViewHost(
    NavigationPageProbe(selection: bottomUpSelection, transition: .bottomUp)
)
let bottomUpWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
bottomUpWindow.contentView = bottomUpHost
bottomUpHost.frame = NSRect(x: 0, y: 0, width: 760, height: 420)
bottomUpWindow.orderFront(nil)
bottomUpHost.layoutSubtreeIfNeeded()
bottomUpSelection.wrappedValue = "library"
drainMainQueue()
let bottomUpEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: bottomUpHost)
let bottomUpIncoming = bottomUpEntries.last
let bottomUpOutgoing = bottomUpEntries.first
let bottomUpIncomingFrom = (bottomUpIncoming?.layer?.animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation)
    .flatMap { ($0.fromValue as? NSValue)?.caTransform3DValue.m42 }
let bottomUpOutgoingTo = (bottomUpOutgoing?.layer?.animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation)
    .flatMap { ($0.toValue as? NSValue)?.caTransform3DValue.m42 }
require(
    (bottomUpIncomingFrom ?? 0) < 0
        && (bottomUpOutgoingTo ?? 0) > 0,
    "Gallery-style bottomUp navigation always brings the incoming page from below"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
bottomUpSelection.wrappedValue = "home"
drainMainQueue()
let bottomUpBackwardEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: bottomUpHost)
let bottomUpBackwardIncoming = bottomUpBackwardEntries.last
let bottomUpBackwardFrom = (bottomUpBackwardIncoming?.layer?.animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation)
    .flatMap { ($0.fromValue as? NSValue)?.caTransform3DValue.m42 }
require(
    (bottomUpBackwardFrom ?? 0) < 0,
    "Gallery-style bottomUp keeps its lower-edge entrance when navigating backward"
)
let transitionThemeScheme: FluentThemeColorScheme = bottomUpHost.context.theme.isDark ? .light : .dark
bottomUpHost.context = FluentRenderContext(
    theme: bottomUpHost.context.theme.with(colorScheme: transitionThemeScheme)
)
drainMainQueue()
let bottomUpEntriesAfterThemeChange = views(
    identifier: "FluentKit.NavigationView.ContentEntry",
    in: bottomUpHost
)
require(
    bottomUpEntriesAfterThemeChange.count == 1
        && bottomUpEntriesAfterThemeChange[0].layer?.animationKeys()?.isEmpty != false,
    "NavigationView settles an active page transition before applying a new window theme"
)
bottomUpWindow.orderOut(nil)

navigationViewSelection.wrappedValue = "settings"
drainMainQueue()
let invalidNavigation = FluentNavigationView(
    Array(navigationViewItems.prefix(1)),
    selection: navigationViewSelection.projectedValue,
    paneDisplayMode: .left
) {
    FluentText("Updated navigation content")
}
reusableNavigationHost.update(invalidNavigation)
drainMainQueue()
require(
    navigationViewSelection.wrappedValue == nil,
    "NavigationView clears selection when its stable destination is removed"
)

let titleBarPaneOpen = FluentState(wrappedValue: true)
var titleBarBackInvocations = 0
var titleBarForwardInvocations = 0
var titleBarPaneInvocations = 0
let compactTitleBar = FluentTitleBar(
    title: "Workspace",
    subtitle: "Compact",
    heightMode: .compact,
    isBackButtonVisible: true,
    isBackButtonEnabled: true,
    isForwardButtonVisible: true,
    isForwardButtonEnabled: true,
    isPaneToggleButtonVisible: true,
    isPaneOpen: titleBarPaneOpen.projectedValue,
    onBack: { titleBarBackInvocations += 1 },
    onForward: { titleBarForwardInvocations += 1 },
    onPaneToggle: { titleBarPaneInvocations += 1 }
)
let compactTitleBarView = compactTitleBar._mount(in: FluentRenderContext())
require(
    abs(compactTitleBarView.intrinsicContentSize.height - 32) < 0.5,
    "TitleBar compact mode exposes the 32pt chrome height"
)
let titleBarWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
titleBarWindow.title = "Original title"
titleBarWindow.titlebarAppearsTransparent = false
titleBarWindow.titleVisibility = .visible
titleBarWindow.contentView = compactTitleBarView
titleBarWindow.orderFront(nil)
compactTitleBarView.layoutSubtreeIfNeeded()
drainMainQueue()
let titleBarBackButton = firstView(identifier: "FluentKit.TitleBar.Back", in: compactTitleBarView) as? NSButton
let titleBarForwardButton = firstView(identifier: "FluentKit.TitleBar.Forward", in: compactTitleBarView) as? NSButton
let titleBarPaneButton = firstView(identifier: "FluentKit.TitleBar.PaneToggle", in: compactTitleBarView) as? NSButton
let titleBarTitleLabel = firstView(identifier: "FluentKit.TitleBar.Title", in: compactTitleBarView) as? NSTextField
require(
    titleBarWindow.styleMask.contains(.fullSizeContentView)
        && titleBarWindow.titleVisibility == .hidden
        && titleBarWindow.titlebarAppearsTransparent
        && titleBarWindow.standardWindowButton(.closeButton) != nil
        && titleBarWindow.standardWindowButton(.miniaturizeButton) != nil
        && titleBarWindow.standardWindowButton(.zoomButton) != nil,
    "TitleBar paints custom full-size chrome while preserving native macOS window controls"
)
require(titleBarWindow.title == "Workspace", "TitleBar synchronizes the native window title")
NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: titleBarWindow)
require(
    titleBarTitleLabel?.textColor?.isEqual(FluentTheme.current.textPrimary) == true,
    "TitleBar uses active-window foreground semantics"
)
NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: titleBarWindow)
require(
    titleBarTitleLabel?.textColor?.isEqual(FluentTheme.current.textSecondary) == true,
    "TitleBar uses inactive-window foreground semantics"
)
titleBarBackButton?.performClick(nil)
titleBarForwardButton?.performClick(nil)
titleBarPaneButton?.performClick(nil)
drainMainQueue()
require(titleBarBackInvocations == 1, "TitleBar back button routes its declarative action")
require(titleBarForwardInvocations == 1, "TitleBar forward button routes its declarative action")
require(
    !titleBarPaneOpen.wrappedValue
        && titleBarPaneInvocations == 1
        && titleBarPaneButton?.accessibilityValue() as? String == "Collapsed",
    "TitleBar pane button updates its binding, callback, and accessibility value"
)
if let closeButton = titleBarWindow.standardWindowButton(.closeButton) {
    let closeFrame = closeButton.convert(closeButton.bounds, to: compactTitleBarView)
    require(
        (titleBarBackButton?.frame.minX ?? 0) > closeFrame.maxX,
        "left-to-right TitleBar content excludes the native traffic-light region"
    )
}
let updatedCompactTitleBar = FluentTitleBar(
    title: "Updated workspace",
    heightMode: .compact,
    isBackButtonVisible: true,
    isPaneToggleButtonVisible: true,
    isPaneOpen: titleBarPaneOpen.projectedValue,
    onBack: { titleBarBackInvocations += 1 },
    onPaneToggle: { titleBarPaneInvocations += 1 }
)
require(
    updatedCompactTitleBar._update(compactTitleBarView, in: FluentRenderContext()),
    "TitleBar reconciles compatible declarative updates in place"
)
require(
    titleBarWindow.title == "Updated workspace",
    "TitleBar keeps the native window title synchronized after declarative updates"
)

let expandedTitleBar = FluentTitleBar(
    title: "FluentKit",
    subtitle: "Gallery",
    heightMode: .automatic,
    isBackButtonVisible: true,
    leftHeader: { FluentText("Left slot") },
    content: { FluentText("Center slot") },
    rightHeader: { FluentButtonView("Action") }
)
let expandedTitleBarView = expandedTitleBar._mount(
    in: FluentRenderContext(layoutDirection: .rightToLeft)
)
expandedTitleBarView.frame = NSRect(x: 0, y: 0, width: 720, height: 48)
expandedTitleBarView.layoutSubtreeIfNeeded()
let expandedBackButton = firstView(identifier: "FluentKit.TitleBar.Back", in: expandedTitleBarView)
let expandedRightHeader = firstView(identifier: "FluentKit.TitleBar.RightHeader", in: expandedTitleBarView)
require(
    abs(expandedTitleBarView.intrinsicContentSize.height - 48) < 0.5,
    "TitleBar automatic mode expands to 48pt when declarative slots are present"
)
require(
    firstView(identifier: "FluentKit.TitleBar.LeftHeader", in: expandedTitleBarView) != nil
        && firstView(identifier: "FluentKit.TitleBar.Content", in: expandedTitleBarView) != nil
        && expandedRightHeader != nil,
    "TitleBar mounts left, centered, and right declarative content slots"
)
require(
    (expandedBackButton?.frame.minX ?? 0) > (expandedRightHeader?.frame.maxX ?? 0),
    "TitleBar mirrors leading controls and trailing content in right-to-left layout"
)

titleBarWindow.contentView = NSView(frame: titleBarWindow.contentLayoutRect)
drainMainQueue()
require(
    !titleBarWindow.styleMask.contains(.fullSizeContentView)
        && !titleBarWindow.titlebarAppearsTransparent
        && titleBarWindow.titleVisibility == .visible
        && titleBarWindow.title == "Original title",
    "TitleBar restores the prior native window configuration when detached"
)
titleBarWindow.orderOut(nil)

let shellSelection = FluentState<String?>(wrappedValue: "home")
let shellPaneOpen = FluentState(wrappedValue: true)
let shellSearch = FluentState(wrappedValue: "")
var shellBackInvocations = 0
let settingsShellConfiguration = FluentWindowConfiguration(
    layout: .settings,
    paneTogglePlacement: .titleBar,
    searchPlacement: .titleBar,
    contentTransition: .bottomUp
)
let settingsShell = FluentWindowShell<String>(
    configuration: settingsShellConfiguration,
    title: "Shell gallery",
    systemImageName: "square.grid.2x2",
    isBackButtonVisible: true,
    onBack: { shellBackInvocations += 1 },
    items: [
        FluentNavigationItem(id: "home", title: "Home", systemImageName: "house"),
        FluentNavigationItem(id: "library", title: "Library", systemImageName: "books.vertical")
    ],
    selection: shellSelection.projectedValue,
    isPaneOpen: shellPaneOpen.projectedValue,
    openPaneLength: 240,
    paneSectionTitle: "Explore",
    titleBarContent: {
        FluentSearchField(shellSearch.projectedValue, placeholder: "Search controls")
            .frame(width: 360, height: 32)
    },
    paneHeader: { FluentText("Workspace") },
    header: { FluentText("Page heading") },
    content: { FluentText("Page content") }
)
let settingsShellHost = FluentViewHost(settingsShell)
let settingsShellWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
)
settingsShellWindow.isOpaque = false
settingsShellWindow.backgroundColor = .clear
settingsShellWindow.contentView = settingsShellHost
settingsShellHost.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
settingsShellWindow.makeKeyAndOrderFront(nil)
settingsShellHost.layoutSubtreeIfNeeded()
drainMainQueue()
settingsShellHost.layoutSubtreeIfNeeded()
let shellTitleBar = firstView(identifier: "FluentKit.TitleBar", in: settingsShellHost)
let shellBackButton = firstView(identifier: "FluentKit.TitleBar.Back", in: settingsShellHost)
let shellTitleBarToggle = firstView(identifier: "FluentKit.TitleBar.PaneToggle", in: settingsShellHost)
let shellPaneToggle = firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: settingsShellHost)
let shellPane = firstView(identifier: "FluentKit.NavigationView.Pane", in: settingsShellHost)
let shellContentSurfaces = views(identifier: "FluentKit.WindowShell.ContentSurface", in: settingsShellHost)
let shellHeaderSurface = shellContentSurfaces.first {
    labels(in: $0).contains { $0.stringValue == "Page heading" }
}
let shellContentSurface = shellContentSurfaces.first {
    labels(in: $0).contains { $0.stringValue == "Page content" }
}
require(
    settingsShellConfiguration.titleBarStyle == .extended
        && settingsShellConfiguration.navigationPlacement == .left
        && settingsShellConfiguration.searchPlacement == .titleBar
        && settingsShellConfiguration.contentCornerStyle == .topLeading,
    "Settings WindowShell preset resolves independent title-bar, navigation, search, and content axes"
)
require(
    shellTitleBar != nil
        && firstSearchField(in: settingsShellHost) != nil
        && shellBackButton?.isHidden == false
        && shellTitleBarToggle?.isHidden == false
        && shellTitleBarToggle?.frame.width == 40
        && shellPaneToggle?.isHidden == true,
    "WindowShell places optional search and the pane toggle in the extended title bar"
)
require(
    shellPane.map(labels(in:))?.contains { $0.stringValue == "Workspace" } == true,
    "WindowShell exposes NavigationView pane-header content through its public initializer"
)
require(
    shellBackButton?.accessibilityPerformPress() == true && shellBackInvocations == 1,
    "WindowShell forwards its public Back state and accessibility action into the extended title bar"
)
require(
    shellTitleBarToggle?.accessibilityPerformPress() == true && !shellPaneOpen.wrappedValue,
    "WindowShell title-bar pane toggle updates the shared pane binding through accessibility"
)
shellPaneOpen.wrappedValue = true
drainMainQueue()
let shellNavigationContent = firstView(identifier: "FluentKit.NavigationView.Content", in: settingsShellHost)
let shellMaterials = materialViews(in: settingsShellHost)
let shellMaterial = firstView(identifier: "FluentKit.WindowShell.Mica", in: settingsShellHost) as? FluentMaterialView
let shellPaneMaterials = shellPane.map(materialViews(in:)) ?? []
require(
    shellPane?.frame.width == 240
        && (shellContentSurface?.layer?.mask as? CAShapeLayer)?.path != nil
        && shellContentSurface?.layer?.cornerRadius == 0
        && shellContentSurface?.layer?.backgroundColor != nil
        && shellNavigationContent?.layer?.backgroundColor == nil
        && settingsShellConfiguration.backdrop == .mica
        && shellMaterials.count == 1
        && shellPaneMaterials.isEmpty
        && shellMaterial?.materialStyle == .mica
        && shellMaterial?.resolvedBackend == expectedLiquidGlassBackend
        && shellMaterial?.state == .followsWindowActiveState
        && shellMaterial?.tintColor?.isEqual(FluentTheme.current.micaTint) == true
        && firstLayer(named: "FluentKit.Material.MicaTint", in: shellMaterial ?? NSView()) != nil
        && firstLayer(named: "FluentKit.WindowShell.SharedChromeTint", in: settingsShellHost) != nil,
    "WindowShell owns one tinted Mica while ContentSurface solely owns its fill and top-leading clip"
)
require(
    shellTitleBar?.layer?.backgroundColor == nil
        && shellPane?.layer?.backgroundColor == nil
        && firstView(identifier: "FluentKit.NavigationView.PaneMaterial", in: settingsShellHost) == nil,
    "WindowShell title bar and navigation pane inherit one continuous backdrop without a second sampler"
)
if let chromeHost = firstView(identifier: "FluentKit.WindowShell.SharedChromeHost", in: settingsShellHost),
   let shellTitleBar,
   let shellContentSurface,
   let chromeTint = firstLayer(named: "FluentKit.WindowShell.SharedChromeTint", in: settingsShellHost),
   let chromeMask = chromeTint.mask as? CAShapeLayer,
   let chromePath = chromeMask.path {
    let titleRect = chromeHost.convert(shellTitleBar.bounds, from: shellTitleBar)
    let contentRect = chromeHost.convert(shellContentSurface.bounds, from: shellContentSurface)
    require(
        chromePath.contains(
            NSPoint(x: titleRect.midX, y: titleRect.midY),
            using: .evenOdd
        )
            && !chromePath.contains(
                NSPoint(x: contentRect.midX, y: contentRect.midY),
                using: .evenOdd
            ),
        "SharedChromeTint covers title and pane chrome while excluding the ContentSurface"
    )
} else {
    require(false, "WindowShell exposes one geometry-masked SharedChromeTint layer")
}
if let sharedChromeTint = firstLayer(named: "FluentKit.WindowShell.SharedChromeTint", in: settingsShellHost) {
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: settingsShellWindow)
    drainMainQueue()
    let activeOpacity = sharedChromeTint.opacity
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: settingsShellWindow)
    drainMainQueue()
    let inactiveOpacity = sharedChromeTint.opacity
    require(
        activeOpacity == 1 && inactiveOpacity < activeOpacity,
        "WindowShell updates its one SharedChromeTint together with the active-state Mica backdrop"
    )
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: settingsShellWindow)
    drainMainQueue()
}
require(
    shellHeaderSurface.map(labels(in:))?.contains { $0.stringValue == "Page heading" } == true
        && shellContentSurface.map(labels(in:))?.contains { $0.stringValue == "Page content" } == true
        && shellHeaderSurface !== shellContentSurface,
    "WindowShell keeps the page header fixed above an independently clipped ContentSurface viewport"
)
shellSelection.wrappedValue = "library"
drainMainQueue()
let shellTransitionEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: settingsShellHost)
require(
    shellTransitionEntries.count == 2
        && shellTransitionEntries.last?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil
        && shellHeaderSurface?.layer?.animationKeys()?.isEmpty != false,
    "WindowShell limits bottomUp page motion to the viewport while keeping its header stationary"
)
shellSelection.wrappedValue = "home"
drainMainQueue()
settingsShellWindow.setContentSize(NSSize(width: 560, height: 560))
settingsShellHost.frame = NSRect(x: 0, y: 0, width: 560, height: 560)
settingsShellHost.layoutSubtreeIfNeeded()
drainMainQueue()
settingsShellHost.layoutSubtreeIfNeeded()
if let shellTitleBar, let shellSearchField = firstSearchField(in: settingsShellHost) {
    let searchFrame = shellSearchField.convert(shellSearchField.bounds, to: shellTitleBar)
    let titleBarAppearance = (shellSearchField as? FluentSearchTextField).map { field in
        field.fluentStyle.appearance(
            for: FluentTextFieldStyleConfiguration(
                isEnabled: field.isEnabled,
                isFocused: false,
                isPointerOver: false,
                controlSize: field.fluentControlSize,
                theme: field.theme
            )
        )
    }
    require(
        searchFrame.minX >= shellTitleBar.bounds.minX - 0.5
            && searchFrame.maxX <= shellTitleBar.bounds.maxX + 0.5,
        "WindowShell keeps a 360pt title-bar SearchBox inside a 560pt window"
    )
    require(
        titleBarAppearance.map { titleBar in
            ordinarySearchAppearance.map { ordinary in
                abs(titleBar.cornerRadius - ordinary.cornerRadius) < 0.001
                    && abs(titleBar.cornerRadius - 4) < 0.001
            } ?? false
        } == true,
        "title-bar and ordinary SearchBox share the same WinUI 4pt ControlCornerRadius without shell overrides"
    )
} else {
    require(false, "WindowShell exposes the title bar and SearchBox for narrow-layout validation")
}
settingsShellWindow.orderOut(nil)

let paneToggleShellConfiguration = FluentWindowConfiguration(
    layout: .settings,
    paneTogglePlacement: .navigationPane,
    searchPlacement: FluentWindowSearchPlacement.none
)
let paneToggleShell = FluentWindowShell<String>(
    configuration: paneToggleShellConfiguration,
    title: "Pane toggle shell",
    isBackButtonVisible: true,
    items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
    selection: shellSelection.projectedValue,
    isPaneOpen: shellPaneOpen.projectedValue,
    paneHeader: { FluentText("Navigation header") },
    header: { FluentText("Pane heading") },
    content: { FluentText("Pane content") }
)
let shellModeHost = FluentViewHost(paneToggleShell)
let shellModeWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
)
let originalShellModeStyleMask = shellModeWindow.styleMask
shellModeWindow.contentView = shellModeHost
shellModeHost.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
shellModeWindow.orderFront(nil)
shellModeHost.layoutSubtreeIfNeeded()
drainMainQueue()
shellModeHost.layoutSubtreeIfNeeded()
let extendedPaneToggle = firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: shellModeHost)
require(
    paneToggleShellConfiguration.titleBarStyle == .extended
        && paneToggleShellConfiguration.searchPlacement == .none
        && firstView(identifier: "FluentKit.TitleBar", in: shellModeHost) != nil
        && firstSearchField(in: shellModeHost) == nil,
    "WindowShell supports an extended title bar without optional search content"
)
let hiddenExtendedTitleToggle = firstView(identifier: "FluentKit.TitleBar.PaneToggle", in: shellModeHost)
require(
    hiddenExtendedTitleToggle?.isHidden == true && extendedPaneToggle?.isHidden == false,
    "WindowShell keeps the toggle in vertical navigation when requested "
        + "(titleHidden=\(String(describing: hiddenExtendedTitleToggle?.isHidden)), "
        + "paneHidden=\(String(describing: extendedPaneToggle?.isHidden)), "
        + "paneFrame=\(String(describing: extendedPaneToggle?.frame)))"
)
require(
    extendedPaneToggle?.accessibilityPerformPress() == true && !shellPaneOpen.wrappedValue,
    "WindowShell navigation-pane toggle owns the same pane binding as the title-bar variant"
)
shellPaneOpen.wrappedValue = true
drainMainQueue()

let nativeNavigationConfiguration = FluentWindowConfiguration(
    layout: .settings,
    titleBarStyle: .native,
    navigationPlacement: .left,
    paneTogglePlacement: .titleBar,
    searchPlacement: .titleBar
)
require(
    nativeNavigationConfiguration.titleBarStyle == .native
        && nativeNavigationConfiguration.paneTogglePlacement == .navigationPane
        && nativeNavigationConfiguration.searchPlacement == .none,
    "WindowShell normalizes unsupported native title-bar content without dropping the pane action"
)
let nativeNavigationShell = FluentWindowShell<String>(
    configuration: nativeNavigationConfiguration,
    title: "Native navigation shell",
    items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
    selection: shellSelection.projectedValue,
    isPaneOpen: shellPaneOpen.projectedValue,
    titleBarContent: {
        FluentSearchField(shellSearch.projectedValue, placeholder: "Ignored native search")
    },
    paneHeader: { FluentText("Native pane header") },
    header: { FluentText("Native heading") },
    content: { FluentText("Native content") }
)
shellModeHost.update(nativeNavigationShell)
drainMainQueue()
shellModeHost.layoutSubtreeIfNeeded()
require(
    firstView(identifier: "FluentKit.TitleBar", in: shellModeHost) == nil
        && firstSearchField(in: shellModeHost) == nil
        && firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: shellModeHost)?.isHidden == false
        && !shellModeWindow.styleMask.contains(.fullSizeContentView)
        && shellModeWindow.styleMask == originalShellModeStyleMask
        && shellModeWindow.titleVisibility == .visible,
    "WindowShell switches to native AppKit chrome and preserves a usable navigation-pane toggle"
)
shellModeHost.update(paneToggleShell)
drainMainQueue()
shellModeHost.layoutSubtreeIfNeeded()
require(
    firstView(identifier: "FluentKit.TitleBar", in: shellModeHost) != nil
        && shellModeWindow.styleMask.contains(.fullSizeContentView)
        && shellModeWindow.titleVisibility == .hidden,
    "WindowShell can re-enter extended chrome after a native-title-bar state"
)
shellModeWindow.orderOut(nil)

let topShellConfiguration = FluentWindowConfiguration(layout: .topNavigation)
let topShell = FluentWindowShell<String>(
    configuration: topShellConfiguration,
    title: "Top shell",
    items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
    selection: shellSelection.projectedValue,
    isPaneOpen: shellPaneOpen.projectedValue,
    header: { FluentEmptyView() },
    content: { FluentText("Top content") }
)
let topShellHost = FluentViewHost(topShell)
topShellHost.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
topShellHost.layoutSubtreeIfNeeded()
require(
    topShellConfiguration.navigationPlacement == .top
        && topShellConfiguration.backdrop == .mica
        && firstView(identifier: "FluentKit.NavigationView.Pane", in: topShellHost)?.frame.height == 48
        && firstView(identifier: "FluentKit.TitleBar.PaneToggle", in: topShellHost)?.isHidden == true
        && firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: topShellHost)?.isHidden == true
        && materialViews(in: topShellHost).count == 1
        && firstView(identifier: "FluentKit.NavigationView.PaneMaterial", in: topShellHost) == nil,
    "WindowShell supports Top Navigation without changing or duplicating its Mica surface"
)

for layout in [FluentWindowLayout.compactNavigation, .minimalNavigation] {
    let configuration = FluentWindowConfiguration(layout: layout)
    let shell = FluentWindowShell<String>(
        configuration: configuration,
        title: "\(layout.rawValue) shell",
        items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
        selection: shellSelection.projectedValue,
        isPaneOpen: shellPaneOpen.projectedValue,
        header: { FluentEmptyView() },
        content: { FluentText("Mode content") }
    )
    let host = FluentViewHost(shell)
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
    host.layoutSubtreeIfNeeded()
    require(
        configuration.backdrop == .mica
            && materialViews(in: host).count == 1
            && firstView(identifier: "FluentKit.WindowShell.Mica", in: host) != nil
            && firstView(identifier: "FluentKit.NavigationView.PaneMaterial", in: host) == nil,
        "\(layout.rawValue) WindowShell inherits the same single Mica without a mode-specific sampler"
    )
}

let opaqueShellTheme = FluentTheme.current.with(materialEffectsEnabled: false)
let opaqueShellHost = FluentViewHost(
    settingsShell,
    context: FluentRenderContext(theme: opaqueShellTheme)
)
opaqueShellHost.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
opaqueShellHost.layoutSubtreeIfNeeded()
let opaqueShellMaterial = firstView(
    identifier: "FluentKit.WindowShell.Mica",
    in: opaqueShellHost
) as? FluentMaterialView
require(
    materialViews(in: opaqueShellHost).count == 1
        && opaqueShellMaterial?.resolvedBackend == .opaque
        && firstLayer(
            named: "FluentKit.Material.MicaTint",
            in: opaqueShellMaterial ?? NSView()
        )?.isHidden == true
        && firstLayer(
            named: "FluentKit.WindowShell.SharedChromeTint",
            in: opaqueShellHost
        )?.isHidden == true,
    "WindowShell's material switch replaces the whole backdrop with one opaque surface"
)

for colorScheme in [FluentThemeColorScheme.light, .dark] {
    let schemeTheme = FluentTheme.custom(colorScheme: colorScheme)
    let schemeHost = FluentViewHost(
        settingsShell,
        context: FluentRenderContext(theme: schemeTheme)
    )
    schemeHost.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
    schemeHost.layoutSubtreeIfNeeded()
    let schemeMaterial = firstView(
        identifier: "FluentKit.WindowShell.Mica",
        in: schemeHost
    ) as? FluentMaterialView
    let schemeChromeTint = firstLayer(
        named: "FluentKit.WindowShell.SharedChromeTint",
        in: schemeHost
    )
    require(
        materialViews(in: schemeHost).count == 1
            && schemeMaterial?.tintColor?.isEqual(schemeTheme.micaTint) == true
            && colorMatches(schemeChromeTint?.backgroundColor, schemeTheme.windowChromeTint)
            && schemeTheme.windowChromeTint.alphaComponent > 0.22,
        "\(colorScheme) WindowShell keeps one Mica and one visible shared chrome tint"
    )
}

let solidShellConfiguration = FluentWindowConfiguration(layout: .settings, backdrop: .solid)
let solidShell = FluentWindowShell<String>(
    configuration: solidShellConfiguration,
    title: "Solid shell",
    items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
    selection: shellSelection.projectedValue,
    isPaneOpen: shellPaneOpen.projectedValue,
    header: { FluentEmptyView() },
    content: { FluentText("Solid content") }
)
let solidShellTheme = FluentTheme.custom(colorScheme: .dark)
let solidShellHost = FluentViewHost(
    solidShell,
    context: FluentRenderContext(theme: solidShellTheme)
)
solidShellHost.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
solidShellHost.layoutSubtreeIfNeeded()
require(
    materialViews(in: solidShellHost).isEmpty
        && colorMatches(
            firstView(identifier: "FluentKit.WindowShell.SolidSurface", in: solidShellHost)?.layer?.backgroundColor,
            solidShellTheme.windowBackground
        )
        && firstView(identifier: "FluentKit.NavigationView.PaneMaterial", in: solidShellHost) == nil,
    "solid WindowShell owns one root fill while its title bar and pane remain inherited"
)

let nativeShellConfiguration = FluentWindowConfiguration(layout: .document)
let nativeShell = FluentWindowShell<String>(
    configuration: nativeShellConfiguration,
    title: "Document",
    selection: shellSelection.projectedValue,
    header: { FluentEmptyView() },
    content: { FluentText("Document content") }
)
let nativeShellView = nativeShell._mount(in: FluentRenderContext())
require(
    nativeShellConfiguration.titleBarStyle == .native
        && nativeShellConfiguration.navigationPlacement == .none
        && firstView(identifier: "FluentKit.TitleBar", in: nativeShellView) == nil
        && firstView(identifier: "FluentKit.NavigationView.Pane", in: nativeShellView) == nil,
    "WindowShell preserves the native-title-bar, navigation-free document composition"
)

let navigation = FluentNavigationStack(
    path: navigationPath.projectedValue,
    root: { FluentText("Root screen") },
    title: { String(describing: $0) },
    destination: { route in FluentAnyView(FluentText("Route: \(route)")) }
)
let navigationView = navigation._mount(in: FluentRenderContext())
let navigationWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
navigationWindow.contentView = navigationView
navigationView.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
navigationWindow.orderFront(nil)
navigationView.layoutSubtreeIfNeeded()
require(navigationView.subviews.count == 1, "navigation stack mounts a native host")
navigationPath.wrappedValue = [AnyHashable("detail")]
let navigationPushStarted = waitUntil(timeout: 0.15, pollInterval: 0.001) {
    let entries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: navigationView)
    return entries.count == 2
        && entries.last?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil
        && entries.last?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil
}
require(navigationPath.wrappedValue == [AnyHashable("detail")], "navigation path binding accepts pushed routes")
let navigationPushEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: navigationView)
require(
    navigationPushStarted
        && navigationPushEntries.count == 2
        && navigationPushEntries.last?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil
        && navigationPushEntries.last?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil,
    "NavigationStack push uses the shared coordinated page presenter "
        + "(entries: \(navigationPushEntries.count), animations: "
        + "\(navigationPushEntries.map { $0.layer?.animationKeys() ?? [] }))"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.50))
navigationPath.wrappedValue = []
let navigationPopStarted = waitUntil(timeout: 0.15, pollInterval: 0.001) {
    let entries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: navigationView)
    return entries.count == 2
        && entries.first?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil
        && entries.last?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil
}
let navigationPopEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: navigationView)
let navigationPopOutgoing = navigationPopEntries.first?.layer?
    .animation(forKey: "fluent.navigation.page.transform") as? CABasicAnimation
require(
    navigationPopStarted
        && navigationPopEntries.count == 2
        && navigationPopOutgoing != nil
        && navigationPopEntries.last?.layer?.animation(forKey: "fluent.navigation.page.opacity") != nil,
    "NavigationStack pop preserves outgoing and incoming pages while reversing the shared transition "
        + "(entries: \(navigationPopEntries.count), animations: "
        + "\(navigationPopEntries.map { $0.layer?.animationKeys() ?? [] }))"
)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.50))
navigationPath.wrappedValue = [AnyHashable("detail")]
drainMainQueue()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.50))
navigationPath.wrappedValue = [AnyHashable("detail"), AnyHashable("detail")]
let duplicateRouteTransitionStarted = waitUntil(timeout: 0.15, pollInterval: 0.001) {
    let entries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: navigationView)
    return entries.count == 2
        && entries.last?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil
}
let duplicateRouteEntries = views(identifier: "FluentKit.NavigationView.ContentEntry", in: navigationView)
require(
    duplicateRouteTransitionStarted
        && duplicateRouteEntries.count == 2
        && duplicateRouteEntries.last?.layer?.animation(forKey: "fluent.navigation.page.transform") != nil,
    "NavigationStack treats duplicate route values at different depths as distinct pages "
        + "(entries: \(duplicateRouteEntries.count), animations: "
        + "\(duplicateRouteEntries.map { $0.layer?.animationKeys() ?? [] }))"
)
navigationWindow.orderOut(nil)

let linkPath = FluentState<[AnyHashable]>(wrappedValue: [])
let link = FluentNavigationLink("settings", path: linkPath.projectedValue) {
    FluentText("Open settings")
}
let linkView = link._mount(in: FluentRenderContext())
require(linkView.accessibilityRole() == NSAccessibility.Role.button, "navigation link mounts an activatable semantic host")
if let linkEvent = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "\\r",
    charactersIgnoringModifiers: "\\r",
    isARepeat: false,
    keyCode: 36
) {
    linkView.keyDown(with: linkEvent)
}
require(linkPath.wrappedValue == [AnyHashable("settings")], "navigation link appends its route")

let descriptorPath = FluentState<[AnyHashable]>(wrappedValue: [])
let descriptorNavigation = FluentNavigationStack(
    path: descriptorPath.projectedValue,
    root: { FluentText("Descriptor root") },
    transition: .crossFade,
    destination: { route in
        FluentNavigationDestination(title: "Screen \(route)") {
            FluentText("Descriptor route \(route)")
        }
    }
)
let descriptorView = descriptorNavigation._mount(in: FluentRenderContext())
require(descriptorView.subviews.count == 1, "navigation destination descriptor mounts")
descriptorPath.wrappedValue = [AnyHashable("settings")]
drainMainQueue()
require(descriptorPath.wrappedValue == [AnyHashable("settings")], "descriptor navigation accepts route changes")

struct ArticleRoute: Hashable, Codable {
    let id: Int
}
struct ProfileRoute: Hashable, Codable {
    let name: String
}
let destinationRegistry = FluentNavigationDestinationRegistry()
destinationRegistry.register(ArticleRoute.self) { route in
    FluentNavigationDestination(title: "Article \(route.id)") { FluentText("Article body \(route.id)") }
}
destinationRegistry.register(ProfileRoute.self) { route in
    FluentNavigationDestination(title: "Profile \(route.name)") { FluentText("Profile body \(route.name)") }
}
require(destinationRegistry.contains(ArticleRoute.self), "navigation registry records a concrete route type")
require(destinationRegistry.contains(ProfileRoute.self), "navigation registry records multiple route types")
let articleDestination = destinationRegistry.resolve(AnyHashable(ArticleRoute(id: 7)))
require(articleDestination?.title == "Article 7", "navigation registry resolves the matching route handler")
require(destinationRegistry.resolve(AnyHashable(ProfileRoute(name: "Ada")))?.title == "Profile Ada", "navigation registry keeps route handlers type isolated")
destinationRegistry.register(ArticleRoute.self) { route in
    FluentNavigationDestination(title: "Updated article \(route.id)") { FluentText("Updated article \(route.id)") }
}
require(destinationRegistry.resolve(AnyHashable(ArticleRoute(id: 7)))?.title == "Updated article 7", "navigation registry replacement has deterministic override semantics")
let unknownRoute = AnyHashable("legacy-route")
require(destinationRegistry.resolve(unknownRoute) == nil, "navigation registry returns nil for an unregistered route")
require(FluentNavigationDestinationRegistry.unavailableDestination(for: unknownRoute).title == "Unavailable", "navigation registry provides an explicit safe fallback destination")
require(destinationRegistry.count == 2, "navigation registry exposes its concrete handler count")
require(destinationRegistry.unregister(ProfileRoute.self), "navigation registry removes one concrete handler")
require(!destinationRegistry.contains(ProfileRoute.self), "navigation registry reports an unregistered type after removal")
destinationRegistry.register(ProfileRoute.self) { route in
    FluentNavigationDestination(title: "Profile \(route.name)") { FluentText("Profile body \(route.name)") }
}

var typedNavigationPath = FluentNavigationPath<ArticleRoute>()
typedNavigationPath.append(ArticleRoute(id: 1))
typedNavigationPath.append(ArticleRoute(id: 2))
require(typedNavigationPath.last?.id == 2 && typedNavigationPath.count == 2, "typed navigation path supports push and count")
require(typedNavigationPath.popLast()?.id == 2 && typedNavigationPath.count == 1, "typed navigation path supports pop")
typedNavigationPath.append(ArticleRoute(id: 2))
let encodedNavigationPath = try! JSONEncoder().encode(typedNavigationPath)
let decodedNavigationPath = try! JSONDecoder().decode(FluentNavigationPath<ArticleRoute>.self, from: encodedNavigationPath)
require(decodedNavigationPath == typedNavigationPath, "typed navigation path round-trips through Codable")
require(restorationStore.set(typedNavigationPath, forKey: "navigation.path"), "typed navigation path persists in restoration store")
require(restorationStore.value(forKey: "navigation.path", as: FluentNavigationPath<ArticleRoute>.self) == typedNavigationPath, "typed navigation path restores in original order")
let restoredNavigationState = FluentRestoredState<FluentNavigationPath<ArticleRoute>>(
    wrappedValue: FluentNavigationPath<ArticleRoute>(),
    "navigation.restored",
    store: restorationStore
)
restoredNavigationState.wrappedValue = typedNavigationPath
let reloadedNavigationState = FluentRestoredState<FluentNavigationPath<ArticleRoute>>(
    wrappedValue: FluentNavigationPath<ArticleRoute>(),
    "navigation.restored",
    store: restorationStore
)
require(reloadedNavigationState.wrappedValue == typedNavigationPath, "restored state reconstructs the complete typed navigation order")

let typedPathState = FluentState(wrappedValue: FluentNavigationPath<ArticleRoute>([ArticleRoute(id: 10)]))
let typedNavigation = FluentNavigationStack(
    path: typedPathState.projectedValue,
    root: { FluentText("Typed root") },
    registry: destinationRegistry,
    transition: .none
)
let typedNavigationView = typedNavigation._mount(in: FluentRenderContext())
let typedNavigationHost = typedNavigationView.subviews.first
typedPathState.wrappedValue.append(ArticleRoute(id: 11))
drainMainQueue()
require(typedPathState.wrappedValue.elements.map(\.id) == [10, 11], "typed navigation stack accepts route pushes through its binding")
require(typedNavigation._update(typedNavigationView, in: FluentRenderContext()), "typed navigation stack updates in place")
require(typedNavigationView.subviews.first === typedNavigationHost, "typed navigation stack preserves its native host identity")
let typedLinkPath = FluentState(wrappedValue: FluentNavigationPath<ArticleRoute>())
let typedLink = FluentNavigationLink(ArticleRoute(id: 22), path: typedLinkPath.projectedValue) { FluentText("Open article") }
let typedLinkView = typedLink._mount(in: FluentRenderContext())
if let typedLinkEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
    typedLinkView.keyDown(with: typedLinkEvent)
}
require(typedLinkPath.wrappedValue.elements == [ArticleRoute(id: 22)], "typed navigation link appends to a Codable path")
let unknownPathState = FluentState(wrappedValue: FluentNavigationPath<ArticleRoute>([ArticleRoute(id: 99)]))
let unknownNavigation = FluentNavigationStack(
    path: unknownPathState.projectedValue,
    root: { FluentText("Fallback root") },
    registry: FluentNavigationDestinationRegistry(),
    transition: .none
)
_ = unknownNavigation._mount(in: FluentRenderContext())
require(unknownPathState.wrappedValue.last?.id == 99, "unregistered typed routes remain stable in navigation state")

let inspectorVisible = FluentState(wrappedValue: true)
let inspector = FluentInspector(
    isPresented: inspectorVisible.projectedValue,
    width: 180...300,
    idealWidth: 220,
    content: {
        FluentText("Editor content")
    },
    inspector: {
        FluentVStack(spacing: 6) {
            FluentText("Inspector", weight: .semibold)
            FluentText("Properties", color: FluentTheme.current.textSecondary)
        }
    }
)
let inspectorView = inspector._mount(in: FluentRenderContext())
inspectorView.frame = NSRect(x: 0, y: 0, width: 720, height: 320)
inspectorView.layoutSubtreeIfNeeded()
drainMainQueue()
inspectorView.layoutSubtreeIfNeeded()
let nativeInspectorSplit = firstSplitView(in: inspectorView)
require(nativeInspectorSplit?.subviews.count == 2, "inspector mounts content and trailing pane in one native split view")
require(labels(in: inspectorView).contains { $0.stringValue == "Inspector" }, "inspector renders declarative trailing content")
let inspectorSplitIdentity = nativeInspectorSplit
inspectorVisible.wrappedValue = false
drainMainQueue()
require(inspectorVisible.wrappedValue == false, "inspector visibility binding accepts collapse state")
inspectorVisible.wrappedValue = true
drainMainQueue()
inspectorView.layoutSubtreeIfNeeded()
require(inspectorVisible.wrappedValue == true, "inspector visibility binding restores the pane")
require(firstSplitView(in: inspectorView) === inspectorSplitIdentity, "inspector preserves its native split host across visibility changes")
let updatedInspector = FluentInspector(
    isPresented: inspectorVisible.projectedValue,
    width: 200...340,
    idealWidth: 260,
    content: { FluentText("Updated content") },
    inspector: { FluentText("Updated inspector") }
)
require(updatedInspector._update(inspectorView, in: FluentRenderContext()), "inspector updates compatible content in place")
require(firstSplitView(in: inspectorView) === inspectorSplitIdentity, "inspector preserves native split identity during declarative updates")

var capturedReduceMotion = false
struct ReduceMotionProbe: FluentPrimitiveView {
    let capture: (FluentRenderContext) -> Void

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        capture(context)
        return NSView()
    }
}
let reducedMotionView = ReduceMotionProbe { capturedReduceMotion = $0.reduceMotion }
    .fluentReduceMotion(true)
let reducedMotionHost = reducedMotionView._mount(in: FluentRenderContext())
_ = reducedMotionHost
require(capturedReduceMotion, "reduce-motion environment reaches nested content")
var reducedAnimationDuration = -1.0
struct ReducedAnimationProbe: FluentPrimitiveView {
    let capture: (FluentRenderContext) -> Void

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        capture(context)
        return NSView()
    }
}
let reducedAnimation = ReducedAnimationProbe { reducedAnimationDuration = $0.animationDuration }
    .fluentReduceMotion(true)
    .fluentAnimationDuration(0.42)
_ = reducedAnimation._mount(in: FluentRenderContext())
require(abs(reducedAnimationDuration - 0.42) < 0.0001, "reduce-motion preserves configured duration for descendants")
let linearCurve = FluentAnimationTransaction(duration: 0.18, curve: .linear)
require(abs(linearCurve.duration - 0.18) < 0.0001, "animation curve initializer preserves duration")
let easedMidpoint = FluentAnimationCurve.easeIn.progress(at: 0.5)
require(easedMidpoint > 0 && easedMidpoint < 0.5, "animation curve exposes deterministic eased progress sampling")
require(abs(linearCurve.progress(at: 0.5) - 0.5) < 0.001, "animation transaction samples its cubic timing function")
let directMotion = FluentAnimationCurve.cubicBezier(.direct)
let directMidpoint = directMotion.progress(at: 0.5)
require(directMidpoint > 0.5 && directMidpoint < 1, "custom cubic-bezier curves expose deterministic progress sampling")
require(
    FluentVisualState.forControlState(.pointerOver) == [.normal, .pointerOver]
        && FluentVisualState.forControlState(.pressed).primaryControlState == .pressed
        && FluentVisualState.forControlState(.disabled).primaryControlState == .disabled,
    "shared visual-state mapping preserves common-state combinations and precedence"
)
let visualStateCoordinator = FluentVisualStateCoordinator(state: .normal, reduceMotion: false)
var recordedVisualTransition: FluentVisualStateTransition?
visualStateCoordinator.transition(to: [.normal, .pointerOver], animated: true, motion: FluentMotion.controlFaster) {
    recordedVisualTransition = $0
}
require(
    recordedVisualTransition?.changed == true
        && recordedVisualTransition?.isAnimated == true
        && recordedVisualTransition?.to.primaryControlState == .pointerOver,
    "shared visual-state coordinator emits an animated named-state transition"
)
visualStateCoordinator.transition(to: [.normal, .pointerOver], animated: true, motion: FluentMotion.controlFaster) {
    recordedVisualTransition = $0
}
require(
    recordedVisualTransition?.changed == false && recordedVisualTransition?.isAnimated == false,
    "shared visual-state coordinator does not animate an unchanged state"
)
visualStateCoordinator.reduceMotion = true
visualStateCoordinator.transition(to: [.normal, .pressed], animated: true, motion: FluentMotion.controlFaster) {
    recordedVisualTransition = $0
}
require(
    recordedVisualTransition?.changed == true && recordedVisualTransition?.isAnimated == false,
    "shared visual-state coordinator suppresses motion under Reduce Motion"
)

let stateButtonTheme = FluentTheme.custom(colorScheme: .light)
let subtlePointerOverAppearance = FluentBorderlessButtonStyle().appearance(
    for: FluentButtonStyleConfiguration(
        title: "Subtle",
        role: .standard,
        controlState: .pointerOver,
        isEnabled: true,
        theme: stateButtonTheme
    )
)
let outlinePointerOverAppearance = FluentOutlineButtonStyle().appearance(
    for: FluentButtonStyleConfiguration(
        title: "Outline",
        role: .standard,
        controlState: .pointerOver,
        isEnabled: true,
        theme: stateButtonTheme
    )
)
require(
    colorMatches(subtlePointerOverAppearance.backgroundColor.cgColor, stateButtonTheme.subtleFillSecondary),
    "Borderless Button PointerOver uses the WinUI SubtleFillColorSecondary brush"
)
require(
    colorMatches(outlinePointerOverAppearance.backgroundColor.cgColor, stateButtonTheme.subtleFillSecondary),
    "Outline Button PointerOver uses the WinUI SubtleFillColorSecondary brush"
)

let subtleButtonView = FluentButtonView("Subtle")
    .buttonStyle(FluentBorderlessButtonStyle())
let subtleButtonHost = subtleButtonView._mount(
    in: FluentRenderContext(theme: stateButtonTheme, reduceMotion: true)
)
guard let subtleButton = subtleButtonHost as? FluentButton else {
    fatalError("Borderless Button did not mount as FluentButton")
}
subtleButton.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
let subtleButtonPoint = NSPoint(x: subtleButton.bounds.midX, y: subtleButton.bounds.midY)
subtleButton.mouseEntered(
    with: toggleMouseEvent(.mouseMoved, at: subtleButtonPoint, in: subtleButton, eventNumber: 210)
)
require(
    subtleButton.controlState == .pointerOver
        && colorMatches(subtleButton.layer?.backgroundColor, stateButtonTheme.subtleFillSecondary),
    "mounted Borderless Button renders PointerOver instead of remaining transparent"
)
require(
    subtleButtonView._update(subtleButton, in: FluentRenderContext(theme: stateButtonTheme, reduceMotion: true))
        && subtleButton.controlState == .pointerOver
        && colorMatches(subtleButton.layer?.backgroundColor, stateButtonTheme.subtleFillSecondary),
    "declarative Button updates preserve an active Borderless PointerOver state"
)

let outlineButton = FluentButton(title: "Outline")
outlineButton.theme = stateButtonTheme
outlineButton.reduceMotion = true
outlineButton.fluentStyle = FluentOutlineButtonStyle()
outlineButton.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
outlineButton.mouseEntered(
    with: toggleMouseEvent(
        .mouseMoved,
        at: NSPoint(x: outlineButton.bounds.midX, y: outlineButton.bounds.midY),
        in: outlineButton,
        eventNumber: 211
    )
)
require(
    outlineButton.controlState == .pointerOver
        && colorMatches(outlineButton.layer?.backgroundColor, stateButtonTheme.subtleFillSecondary),
    "mounted Outline Button renders PointerOver while retaining its outline"
)

let stateButton = FluentButton(title: "State probe")
stateButton.theme = stateButtonTheme
stateButton.frame = NSRect(x: 0, y: 0, width: 140, height: 32)
let stateButtonWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 180, height: 72),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
stateButtonWindow.contentView?.addSubview(stateButton)
stateButtonWindow.orderFront(nil)
stateButton.layoutSubtreeIfNeeded()
guard let initialElevation = firstLayer(
    named: "FluentKit.Button.ElevationBorder",
    in: stateButton
) as? CAGradientLayer else {
    fatalError("FluentButton elevation layer did not mount")
}
require(
    !initialElevation.isHidden
        && (initialElevation.mask as? CAShapeLayer)?.path != nil
        && elevationGradientMatchesVisualEdge(initialElevation, edge: .bottom, hostView: stateButton),
    "FluentButton resolves the light-theme bottom elevation geometry before its first pointer event"
)
let initialElevationStart = initialElevation.startPoint
let initialElevationEnd = initialElevation.endPoint
stateButton.controlState = .pointerOver
require(
    colorMatches(stateButton.layer?.backgroundColor, stateButtonTheme.buttonBackground(for: .pointerOver))
        && initialElevation.startPoint == initialElevationStart
        && initialElevation.endPoint == initialElevationEnd,
    "FluentButton maps PointerOver through the shared visual-state coordinator"
)
stateButton.controlState = .pressed
require(
    colorMatches(stateButton.layer?.backgroundColor, stateButtonTheme.buttonBackground(for: .pressed)),
    "FluentButton maps Pressed through the shared visual-state coordinator"
)
stateButton.layer?.removeAllAnimations()
stateButton.controlState = .pressed
require(
    stateButton.layer?.animationKeys()?.isEmpty != false,
    "FluentButton does not allocate a transition when its state is unchanged"
)
stateButton.reduceMotion = true
stateButton.controlState = .normal
stateButton.controlState = .pointerOver
require(
    stateButton.layer?.animationKeys()?.isEmpty != false
        && firstLayer(named: "FluentKit.Button.ElevationBorder", in: stateButton)?.animationKeys()?.isEmpty != false,
    "FluentButton clears background and elevation motion under Reduce Motion"
)
let reducedButtonHost = FluentButtonView("Reduced", action: {})
    ._mount(in: FluentRenderContext(reduceMotion: true))
require(
    (reducedButtonHost as? FluentButton)?.reduceMotion == true,
    "declarative FluentButtonView forwards Reduce Motion to its native button"
)
stateButtonWindow.orderOut(nil)
require(abs(FluentMotion.controlFaster.duration - 0.083) < 0.0001, "control-faster motion preserves its exact duration")
require(abs(FluentMotion.controlFast.duration - 0.167) < 0.0001, "control-fast motion preserves its exact duration")
require(abs(FluentMotion.controlNormal.duration - 0.250) < 0.0001, "control-normal motion preserves its exact duration")
require(
    FluentMotion.collectionSelectionOpacity.duration == FluentMotion.controlFaster.duration
        && FluentMotion.collectionSelectionOpacity.curve == .linear
        && FluentMotion.collectionSelectionReveal.duration == FluentMotion.controlFast.duration
        && FluentMotion.collectionSelectionPress.duration == FluentMotion.controlFast.duration,
    "collection selection motion tokens preserve separate opacity, reveal, and press timelines"
)
require(
    abs(FluentMotion.menuOpen.duration - 0.250) < 0.0001
        && FluentMotion.menuOpen.curve == .controlFastOutSlowIn
        && FluentMotion.menuOpen.scale == 0.5,
    "root-menu motion preserves its 250ms curve and 50% closed geometry"
)
require(
    abs(FluentMotion.submenuOpen.duration - 0.250) < 0.0001
        && FluentMotion.submenuOpen.scale == 0.33,
    "submenu motion preserves its 250ms and 33% closed geometry"
)
require(abs(FluentMotion.connectedDefault.duration - 0.300) < 0.0001, "connected motion preserves its exact duration")
require(abs(FluentMotion.navigationIndicator.duration - 0.600) < 0.0001, "navigation indicator preserves its exact duration")
require(FluentMotion.connectedGravity.distance == 80 && abs(FluentMotion.connectedGravity.scale - 1.1) < 0.0001, "gravity connected motion preserves distance and peak scale")
require(FluentMotion.teachingTipOpen.curve == .direct, "teaching-tip open motion uses the direct curve")
require(FluentMotion.teachingTipClose.curve == .contract, "teaching-tip close motion uses the contract curve")
require(FluentMotion.teachingTipOpen.distance == 8 && FluentMotion.teachingTipOpen.scale == 0.97, "teaching-tip open motion carries presentation geometry")
require(FluentMotion.teachingTipClose.distance == 8 && FluentMotion.teachingTipClose.scale == 0.97, "teaching-tip close motion mirrors presentation geometry")
require(FluentMatchedGeometryConfiguration.automatic.motion.duration == FluentMotion.connectedDefault.duration, "automatic matched geometry uses default connected motion")
require(FluentMatchedGeometryConfiguration.direct.motion.duration == FluentMotion.connectedDirect.duration, "direct matched geometry uses direct connected motion")
require(
    FluentMatchedGeometryConfiguration.gravity.motion.distance == FluentMotion.connectedGravity.distance
        && FluentMatchedGeometryConfiguration.gravity.motion.scale == FluentMotion.connectedGravity.scale,
    "gravity matched geometry exposes gravity distance and scale"
)
require(abs(CGFloat.interpolate(from: 2, to: 6, fraction: 0.25) - 3) < 0.0001, "interpolatable scalar samples between values")
require(abs(CGFloat.interpolate(from: 2, to: 6, fraction: 1.1) - 6.4) < 0.0001, "numeric interpolation extrapolates spring overshoot")
let midpointColor = NSColor.interpolate(
    from: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
    to: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.5),
    fraction: 0.5
).usingColorSpace(.extendedSRGB)
require(abs((midpointColor?.redComponent ?? 0) - 0.5) < 0.001, "color interpolation samples red in extended sRGB")
require(abs((midpointColor?.blueComponent ?? 0) - 0.5) < 0.001, "color interpolation samples blue in extended sRGB")
require(abs((midpointColor?.alphaComponent ?? 0) - 0.75) < 0.001, "color interpolation includes alpha")
let midpointTransform = CGAffineTransform.interpolate(
    from: .identity,
    to: CGAffineTransform(translationX: 20, y: -10),
    fraction: 0.5
)
require(abs(midpointTransform.tx - 10) < 0.0001 && abs(midpointTransform.ty + 5) < 0.0001, "transform interpolation samples every matrix component")
let keyframeTimeline = FluentKeyframeAnimation<CGFloat>(
    keyframes: [
        FluentKeyframe(offset: 0, value: 0),
        FluentKeyframe(offset: 0.5, value: 1),
        FluentKeyframe(offset: 1, value: 0.25)
    ],
    duration: 0.06,
    curve: .linear
)
require(abs(keyframeTimeline.value(at: 0.25, from: 0) - 0.5) < 0.0001, "keyframe timeline interpolates its first segment")
require(abs(keyframeTimeline.value(at: 0.75, from: 0) - 0.625) < 0.0001, "keyframe timeline interpolates its final segment")
let duplicateKeyframeTimeline = FluentKeyframeAnimation<CGFloat>(
    keyframes: [
        FluentKeyframe(offset: 0, value: 0),
        FluentKeyframe(offset: 0.5, value: 0.25),
        FluentKeyframe(offset: 0.5, value: 0.8),
        FluentKeyframe(offset: 1, value: 1)
    ],
    curve: .linear
)
require(duplicateKeyframeTimeline.keyframes.count == 3, "duplicate keyframe offsets normalize to one definition")
require(abs(duplicateKeyframeTimeline.value(at: 0.5, from: 0) - 0.8) < 0.0001, "later duplicate keyframes override earlier definitions")

let animatedScalar = FluentAnimatedValue<CGFloat>(0)
var animatedSamples: [CGFloat] = []
let animatedObserver = animatedScalar.observable.observe({ animatedSamples.append($0) }, notifyImmediately: false)
var scalarAnimationCompleted = false
animatedScalar.set(1, animation: FluentAnimationTransaction(duration: 0.30, curve: .linear), reduceMotion: false) {
    scalarAnimationCompleted = true
}
require(
    waitUntil(timeout: 0.18) {
        animatedScalar.isAnimating && animatedScalar.value > 0 && animatedScalar.value < 1
    },
    "animated value reports an active display-driven intermediate sample"
)
require(waitUntil(timeout: 0.80) { !animatedScalar.isAnimating }, "animated value finishes within its motion window")
require(abs(animatedScalar.value - 1) < 0.0001, "animated value lands exactly on its target")
require(!animatedScalar.isAnimating && scalarAnimationCompleted, "animated value completes and releases its timer")
require(animatedSamples.count >= 2, "animated value observers receive multiple sampled values")
animatedScalar.observable.removeObserver(animatedObserver)

struct AnimatedScalarLabel: FluentView {
    let value: FluentAnimatedValue<CGFloat>
    var body: FluentTextView { FluentText("Animated: \(Int(value.value * 100))") }
}
let trackedAnimatedValue = FluentAnimatedValue<CGFloat>(0)
let trackedAnimatedHost = FluentViewHost(AnimatedScalarLabel(value: trackedAnimatedValue))
trackedAnimatedValue.set(1, animation: FluentAnimationTransaction(duration: 0.04, curve: .linear), reduceMotion: false)
require(
    waitUntil(timeout: 0.50) { firstLabel(in: trackedAnimatedHost)?.stringValue == "Animated: 100" },
    "animated values participate in declarative dependency tracking"
)

struct TransformDependencyProbe: FluentView {
    let progress: FluentObservable<CGFloat>

    var body: FluentTransformView<FluentTextView> {
        FluentText("Transform child").offset(x: progress.value * 20)
    }
}
let transformProgress = FluentObservable<CGFloat>(0)
let transformHost = FluentViewHost(TransformDependencyProbe(progress: transformProgress))
let nativeTransformHost = transformHost.subviews.first
let nativeTransformChild = nativeTransformHost?.subviews.first
transformProgress.value = 0.5
drainMainQueue()
require(transformHost.subviews.first === nativeTransformHost, "transform updates preserve their native container identity")
require(transformHost.subviews.first?.subviews.first === nativeTransformChild, "transform updates preserve native child identity")
require(abs((transformHost.subviews.first?.layer?.affineTransform().tx ?? 0) - 10) < 0.0001, "transform updates apply dependency-driven matrix changes in place")

let springValue = FluentAnimatedValue<CGFloat>(0)
var springCompleted = false
let spring = FluentSpringAnimation(stiffness: 220, damping: 22)
require(spring.settlingDuration >= 0.12 && spring.settlingDuration <= 3, "spring exposes a bounded settling duration")
springValue.set(1, spring: spring, reduceMotion: false) { springCompleted = true }
require(
    waitUntil(timeout: 0.18) { springValue.isAnimating && springValue.value != 0 },
    "spring animation publishes a moving value"
)
springValue.finish()
require(abs(springValue.value - 1) < 0.0001 && springCompleted, "finishing a spring writes its exact target and completion")
let overshootingSpringValue = FluentAnimatedValue<CGFloat>(0)
var overshootingSpringSamples: [CGFloat] = []
let overshootingSpringObserver = overshootingSpringValue.observable.observe(
    { overshootingSpringSamples.append($0) },
    notifyImmediately: false
)
overshootingSpringValue.set(1, spring: FluentSpringAnimation(stiffness: 240, damping: 4), reduceMotion: false)
require(
    waitUntil(timeout: 0.55) { overshootingSpringSamples.contains { $0 > 1.01 } },
    "underdamped springs publish overshooting value samples"
)
overshootingSpringValue.stop()
overshootingSpringValue.observable.removeObserver(overshootingSpringObserver)

let reducedKeyframeValue = FluentAnimatedValue<CGFloat>(0)
var reducedKeyframesCompleted = false
reducedKeyframeValue.animate(using: keyframeTimeline, reduceMotion: true) { reducedKeyframesCompleted = true }
require(abs(reducedKeyframeValue.value - 0.25) < 0.0001, "reduced motion resolves keyframes to their final value immediately")
require(!reducedKeyframeValue.isAnimating && reducedKeyframesCompleted, "reduced keyframes complete without allocating a timer")

final class ValidationTransitionCoordinateView: NSView {
    private let usesFlippedCoordinates: Bool

    override var isFlipped: Bool { usesFlippedCoordinates }

    init(flipped: Bool, page: Int) {
        usesFlippedCoordinates = flipped
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        identifier = NSUserInterfaceItemIdentifier("Validation.TransitionCoordinate.\(page)")
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct LogicalEdgeTransitionLeaf: FluentPrimitiveView {
    let page: Int
    let flipped: Bool

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        ValidationTransitionCoordinateView(flipped: flipped, page: page)
    }
}

struct LogicalEdgeTransitionProbe: FluentView {
    let page: FluentObservable<Int>
    let flipped: Bool
    let edge: FluentTransitionEdge

    var body: FluentTransitionView<LogicalEdgeTransitionLeaf> {
        LogicalEdgeTransitionLeaf(page: page.value, flipped: flipped)
            .transition(
                .move(edge: edge),
                animation: FluentAnimationTransaction(duration: 0.30, curve: .linear)
            )
    }
}

func logicalEdgeEntranceOffset(flipped: Bool, edge: FluentTransitionEdge) -> CGFloat {
    let page = FluentObservable(0)
    let host = FluentViewHost(LogicalEdgeTransitionProbe(page: page, flipped: flipped, edge: edge))
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    host.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 180, height: 80)
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    let transitionContainer = host.subviews.first
    page.value = 1
    _ = waitUntil(timeout: 0.15, pollInterval: 0.001) {
        transitionContainer?.subviews.last?.layer?
            .animation(forKey: "fluent.transition.incoming.transform") != nil
    }
    let transformAnimation = transitionContainer?.subviews.last?.layer?
        .animation(forKey: "fluent.transition.incoming.transform") as? CABasicAnimation
    let offset = (transformAnimation?.fromValue as? NSValue)?.caTransform3DValue.m42 ?? .nan
    window.orderOut(nil)
    return offset
}

let nonFlippedTopOffset = logicalEdgeEntranceOffset(flipped: false, edge: .top)
let flippedTopOffset = logicalEdgeEntranceOffset(flipped: true, edge: .top)
let nonFlippedBottomOffset = logicalEdgeEntranceOffset(flipped: false, edge: .bottom)
let flippedBottomOffset = logicalEdgeEntranceOffset(flipped: true, edge: .bottom)
require(
    abs(nonFlippedTopOffset - 24) < 0.0001
        && abs(flippedTopOffset + 24) < 0.0001
        && abs(nonFlippedBottomOffset + 24) < 0.0001
        && abs(flippedBottomOffset - 24) < 0.0001,
    "logical top/bottom move edges map into flipped and non-flipped host coordinates"
)

let transitionFlag = FluentObservable(true)
struct TransitionProbe: FluentView {
    let flag: FluentObservable<Bool>

    var body: FluentTransitionView<FluentAnyView> {
        let branch = flag.value
            ? FluentAnyView(FluentText("Visible").offset(x: 7))
            : FluentAnyView(FluentButton(title: "Replacement").offset(x: 7))
        return branch
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .crossFade),
                    removal: .scale.combined(with: .crossFade)
                ),
                animation: FluentAnimationTransaction(duration: 0.50, curve: .easeOut)
            )
    }
}
let transitionHost = FluentViewHost(TransitionProbe(flag: transitionFlag))
let transitionWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
transitionWindow.contentView = transitionHost
transitionHost.frame = transitionWindow.contentView?.bounds
    ?? NSRect(x: 0, y: 0, width: 320, height: 120)
transitionWindow.orderFront(nil)
transitionHost.layoutSubtreeIfNeeded()
let nativeTransitionContainer = transitionHost.subviews.first
transitionFlag.value = false
require(
    waitUntil(timeout: 0.20, pollInterval: 0.001) {
        guard let outgoingEntry = nativeTransitionContainer?.subviews.first,
              let incomingEntry = nativeTransitionContainer?.subviews.last,
              outgoingEntry !== incomingEntry else { return false }
        return outgoingEntry.layer?.animation(forKey: "fluent.transition.outgoing.opacity") != nil
            && outgoingEntry.layer?.animation(forKey: "fluent.transition.outgoing.transform") != nil
            && incomingEntry.layer?.animation(forKey: "fluent.transition.incoming.opacity") != nil
            && incomingEntry.layer?.animation(forKey: "fluent.transition.incoming.transform") != nil
    },
    "transition host creates explicit incoming and outgoing opacity/transform animations (host: \(nativeTransitionContainer?.layer != nil), entries: \(nativeTransitionContainer?.subviews.map { ($0.layer != nil, $0.layer?.animationKeys() ?? []) } ?? []))"
)
require(transitionHost.subviews.count == 1, "transition wrapper keeps a stable host during branch replacement")
require(transitionHost.subviews.first === nativeTransitionContainer, "composed transitions preserve their native host identity")
if let outgoingEntry = nativeTransitionContainer?.subviews.first,
   let incomingEntry = nativeTransitionContainer?.subviews.last,
   outgoingEntry !== incomingEntry {
    require(
        outgoingEntry.layer?.animation(forKey: "fluent.transition.outgoing.opacity") != nil
            && outgoingEntry.layer?.animation(forKey: "fluent.transition.outgoing.transform") != nil
            && incomingEntry.layer?.animation(forKey: "fluent.transition.incoming.opacity") != nil
            && incomingEntry.layer?.animation(forKey: "fluent.transition.incoming.transform") != nil,
        "transition host runs incoming and outgoing opacity/transform through explicit Core Animation (outgoing: \(outgoingEntry.layer?.animationKeys() ?? []), incoming: \(incomingEntry.layer?.animationKeys() ?? []))"
    )
} else {
    fatalError("transition host did not retain both entries during explicit motion")
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.60))
require(nativeTransitionContainer?.subviews.count == 1, "transition completion removes the outgoing native entry")
let contentTransformPreserved = abs(
    (nativeTransitionContainer?.subviews.first?.subviews.first?.layer?.affineTransform().tx ?? 0) - 7
) < 0.0001
require(
    contentTransformPreserved,
    "transition entry animation does not overwrite a content transform (actual: \(nativeTransitionContainer?.subviews.first?.subviews.first?.layer?.affineTransform().tx ?? 0), hierarchy: \(nativeTransitionContainer?.subviews.map { $0.subviews.count } ?? []))"
)
transitionWindow.orderOut(nil)

let rapidTransitionPage = FluentObservable(0)
struct RapidTransitionProbe: FluentView {
    let page: FluentObservable<Int>

    var body: FluentTransitionView<FluentIDView<FluentTextView>> {
        FluentText("Page \(page.value)")
            .fluentID(page.value)
            .transition(
                .move(edge: .trailing).combined(with: .crossFade),
                animation: FluentAnimationTransaction(duration: 0.04, curve: .cubicBezier(.direct))
            )
    }
}
let rapidTransitionHost = FluentViewHost(RapidTransitionProbe(page: rapidTransitionPage))
let nativeRapidTransitionContainer = rapidTransitionHost.subviews.first
rapidTransitionPage.value = 1
drainMainQueue()
rapidTransitionPage.value = 2
drainMainQueue()
rapidTransitionPage.value = 3
drainMainQueue()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
require(
    rapidTransitionHost.subviews.first === nativeRapidTransitionContainer,
    "rapid transition updates preserve their stable native host"
)
require(
    nativeRapidTransitionContainer?.subviews.count == 1,
    "rapid transition updates remove all superseded outgoing entries"
)
require(
    firstLabel(in: rapidTransitionHost)?.stringValue == "Page 3",
    "rapid transition updates resolve to the latest requested page"
)

let compatibleTransitionText = FluentObservable("First")
struct CompatibleTransitionProbe: FluentView {
    let text: FluentObservable<String>

    var body: FluentTransitionView<FluentTextView> {
        FluentText(text.value)
            .transition(.scale.combined(with: .crossFade))
    }
}
let compatibleTransitionHost = FluentViewHost(CompatibleTransitionProbe(text: compatibleTransitionText))
let compatibleTransitionContainer = compatibleTransitionHost.subviews.first
let compatibleTransitionEntry = compatibleTransitionContainer?.subviews.first
let compatibleTransitionLabel = firstLabel(in: compatibleTransitionHost)
compatibleTransitionText.value = "Second"
drainMainQueue()
require(compatibleTransitionHost.subviews.first === compatibleTransitionContainer, "compatible transition updates preserve the host")
require(compatibleTransitionContainer?.subviews.first === compatibleTransitionEntry, "compatible transition updates preserve the entry")
require(firstLabel(in: compatibleTransitionHost) === compatibleTransitionLabel, "compatible transition updates preserve native content identity")
require(compatibleTransitionLabel?.stringValue == "Second", "compatible transition updates content in place")

let reducedTransitionFlag = FluentObservable(true)
struct ReducedTransitionProbe: FluentView {
    let flag: FluentObservable<Bool>

    var body: some FluentView {
        let branch = flag.value
            ? FluentAnyView(FluentText("Reduced visible"))
            : FluentAnyView(FluentButton(title: "Reduced replacement"))
        return branch
            .transition(
                .move(edge: .bottom).combined(with: .crossFade),
                animation: FluentAnimationTransaction(duration: 1, curve: .easeInOut)
            )
            .fluentReduceMotion(true)
    }
}
let reducedTransitionHost = FluentViewHost(ReducedTransitionProbe(flag: reducedTransitionFlag))
let reducedTransitionContainer = reducedTransitionHost.subviews.first
reducedTransitionFlag.value = false
drainMainQueue()
require(reducedTransitionHost.subviews.first === reducedTransitionContainer, "reduced motion preserves the transition host")
require(reducedTransitionContainer?.subviews.count == 1, "reduced motion replaces a branch without retaining an outgoing entry")
require(firstButton(in: reducedTransitionHost)?.title == "Reduced replacement", "reduced motion resolves immediately to replacement content")

let matchedGeometryFlag = FluentObservable(true)
let matchedGeometryNamespace = FluentMatchedGeometryNamespace()
struct MatchedGeometryProbe: FluentView {
    let flag: FluentObservable<Bool>
    let namespace: FluentMatchedGeometryNamespace

    var body: FluentTransitionView<FluentAnyView> {
        let branch = flag.value
            ? FluentAnyView(
                FluentZStack {
                    FluentAnyView(FluentText("Origin"))
                }
                .frame(width: 96, height: 42)
                .matchedGeometryEffect(id: "card", in: namespace, configuration: .direct)
            )
            : FluentAnyView(
                FluentVStack(spacing: 4) {
                    FluentText("Destination", weight: .semibold)
                    FluentText("Details", size: 11, color: FluentTheme.current.textSecondary)
                }
                .padding(8)
                .frame(width: 196, height: 64)
                .matchedGeometryEffect(id: "card", in: namespace, configuration: .direct)
            )
        return branch.transition(.crossFade, animation: FluentAnimationTransaction(duration: 0.08, curve: .easeInOut))
    }
}
let matchedGeometryHost = FluentViewHost(
    MatchedGeometryProbe(flag: matchedGeometryFlag, namespace: matchedGeometryNamespace)
)
matchedGeometryHost.frame = NSRect(x: 0, y: 0, width: 260, height: 90)
matchedGeometryHost.layoutSubtreeIfNeeded()
let nativeMatchedTransitionHost = matchedGeometryHost.subviews.first
matchedGeometryFlag.value = false
drainMainQueue()
require(matchedGeometryHost.subviews.first === nativeMatchedTransitionHost, "matched geometry preserves the transition host")
require(nativeMatchedTransitionHost?.subviews.count == 2, "matched geometry retains both entries during interpolation")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.26))
require(nativeMatchedTransitionHost?.subviews.count == 1, "matched geometry removes the outgoing entry after interpolation")
let matchedGeometryMarker = nativeMatchedTransitionHost?.subviews.first?.subviews.first
require(matchedGeometryMarker != nil, "matched geometry keeps its native marker host mounted")

var capturedAnimationDuration: TimeInterval = 0
var capturedAnimationTimingFunction: CAMediaTimingFunction?
struct AnimationContextProbe: FluentPrimitiveView {
    let capture: (FluentRenderContext) -> Void

    var body: NeverFluentView { NeverFluentView() }

    func _makeView(in context: FluentRenderContext) -> NSView {
        capture(context)
        return NSView()
    }
}
let linearTiming = CAMediaTimingFunction(name: .linear)
let animationContextView = AnimationContextProbe { context in
    capturedAnimationDuration = context.animationDuration
    capturedAnimationTimingFunction = context.animationTimingFunction
}.fluentAnimationDuration(0.42).fluentAnimationTimingFunction(linearTiming)
_ = animationContextView._mount(in: FluentRenderContext())
require(abs(capturedAnimationDuration - 0.42) < 0.0001, "animation duration environment reaches nested content")
require(capturedAnimationTimingFunction != nil, "animation timing function environment reaches nested content")

let undoValue = FluentState(wrappedValue: 1)
let undoCoordinator = FluentUndoCoordinator()
let undoBinding = undoValue.projectedValue.undoable(using: undoCoordinator, actionName: "Change value")
undoBinding.wrappedValue = 2
require(undoValue.wrappedValue == 2, "undoable binding applies a mutation")
require(undoCoordinator.canUndo, "undoable binding registers a native undo operation")
require(undoCoordinator.state.value.undoActionName == "Change value", "undo coordinator publishes its action name")
undoCoordinator.undo()
require(undoValue.wrappedValue == 1, "undo coordinator restores the previous binding value")
require(undoCoordinator.canRedo, "undo registers the inverse redo operation")
undoCoordinator.redo()
require(undoValue.wrappedValue == 2, "redo reapplies the binding mutation")
undoCoordinator.withGroup(actionName: "Double change") {
    undoBinding.wrappedValue = 3
    undoBinding.wrappedValue = 4
}
undoCoordinator.undo()
require(undoValue.wrappedValue == 2, "explicit undo groups restore multiple mutations atomically")

var capturedUndoCoordinator: FluentUndoCoordinator?
struct UndoContextProbe: FluentPrimitiveView {
    let capture: (FluentUndoCoordinator?) -> Void
    var body: NeverFluentView { NeverFluentView() }
    func _makeView(in context: FluentRenderContext) -> NSView {
        capture(context.undoCoordinator)
        return NSView()
    }
}
_ = UndoContextProbe { capturedUndoCoordinator = $0 }
    .fluentUndoScope(undoCoordinator)
    ._mount(in: FluentRenderContext())
require(capturedUndoCoordinator === undoCoordinator, "undo scope propagates its coordinator through the render environment")

struct ValidationDocument: Codable, Equatable {
    var title: String
    var body: String
}
let validationDocumentDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("FluentKitValidation-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: validationDocumentDirectory, withIntermediateDirectories: true)
let validationDocumentURL = validationDocumentDirectory.appendingPathComponent("document.json")
let validationExportURL = validationDocumentDirectory.appendingPathComponent("export.json")
let validationImportURL = validationDocumentDirectory.appendingPathComponent("import.json")
let validationDocumentDefaults = UserDefaults(suiteName: "FluentKitDocumentValidation.\(UUID().uuidString)")!
let documentSession = FluentDocumentSession(
    id: "validation-document",
    document: ValidationDocument(title: "Draft", body: "Initial"),
    fileURL: validationDocumentURL,
    autosave: .disabled,
    defaults: validationDocumentDefaults
)
documentSession.mutate(actionName: "Edit body") { $0.body = "Changed" }
require(documentSession.document.value.body == "Changed", "document session applies undoable mutations")
require(documentSession.isDirty.value, "document session becomes dirty after editing")
documentSession.undoCoordinator.undo()
require(documentSession.document.value.body == "Initial", "document session undo restores content")
require(!documentSession.isDirty.value, "undoing to the saved revision clears document dirty state")
documentSession.undoCoordinator.redo()
try documentSession.save()
require(!documentSession.isDirty.value, "saving establishes a clean document revision")
let savedDocumentData = try Data(contentsOf: validationDocumentURL)
let savedDocument = try JSONDecoder().decode(ValidationDocument.self, from: savedDocumentData)
require(savedDocument.body == "Changed", "document session writes its encoded revision atomically")
documentSession.mutate(actionName: "Edit title") { $0.title = "Unsaved" }
try documentSession.revert()
require(documentSession.document.value.title == "Draft", "document session revert reloads the saved file")
require(!documentSession.isDirty.value, "document session revert clears dirty state")
let documentZoom = FluentRestoredState<Double>(
    wrappedValue: 1,
    "zoom",
    store: documentSession.restorationStore
)
documentZoom.wrappedValue = 1.25
require(documentSession.restorationStore.value(forKey: "zoom", as: Double.self) == 1.25, "document session exposes a scoped restoration store")
documentSession.autosavePolicy = .delayed(0)
documentSession.mutate(actionName: "Autosave") { $0.body = "Autosaved" }
drainMainQueue()
require(!documentSession.isDirty.value, "document session delayed autosave saves the dirty revision")
let autosavedData = try Data(contentsOf: validationDocumentURL)
let autosavedDocument = try JSONDecoder().decode(ValidationDocument.self, from: autosavedData)
require(autosavedDocument.body == "Autosaved", "document autosave updates the file")
documentSession.mutate(actionName: "Export copy") { $0.body = "Exported copy" }
try documentSession.exportDocument(to: validationExportURL)
let exportedDocument = try JSONDecoder().decode(
    ValidationDocument.self,
    from: Data(contentsOf: validationExportURL)
)
require(exportedDocument.body == "Exported copy", "document export writes the current revision")
require(documentSession.fileURL.value == validationDocumentURL, "document export preserves the active file URL")
require(documentSession.isDirty.value, "document export does not mark unsaved edits as saved")
let importedDocument = ValidationDocument(title: "Imported", body: "External")
try JSONEncoder().encode(importedDocument).write(to: validationImportURL, options: .atomic)
try documentSession.importDocument(from: validationImportURL)
require(documentSession.document.value == importedDocument, "document import decodes a new session revision")
require(documentSession.fileURL.value == nil, "document import requires Save As instead of overwriting its source")
require(!documentSession.isDirty.value, "document import starts from a clean imported revision")

let coordinatedSession = FluentDocumentSession(
    id: "coordinated-document",
    document: ValidationDocument(title: "Coordinated", body: "Initial"),
    fileURL: validationDocumentURL,
    defaults: UserDefaults(suiteName: "FluentKitCoordinatedDocumentValidation.\(UUID().uuidString)")!
)
let documentCoordinator = FluentDocumentCoordinator(sessions: [documentSession, coordinatedSession])
require(documentCoordinator.documentIDs == ["validation-document", "coordinated-document"], "document coordinator preserves registration order")
require(documentCoordinator.activeDocumentID.value == "validation-document", "document coordinator selects its first document by default")
require(documentCoordinator.activate(id: "coordinated-document"), "document coordinator activates a registered document")
try documentCoordinator.open(id: "coordinated-document", from: validationImportURL)
require(documentCoordinator.activeSession === coordinatedSession, "document coordinator routes open into the active session")
require(documentCoordinator.session(forFileURL: validationImportURL) === coordinatedSession, "document coordinator resolves sessions by file URL")
documentCoordinator.activate(id: "validation-document")
coordinatedSession.mutate { $0.body = "Unsaved" }
require(!documentCoordinator.close(id: "coordinated-document"), "document coordinator protects dirty documents from implicit close")
require(documentCoordinator.close(id: "coordinated-document", discardChanges: true), "document coordinator allows explicit dirty close")
require(documentCoordinator.activeDocumentID.value == "validation-document", "document coordinator selects a remaining document after close")
let saveCoordinatorSession = FluentDocumentSession(
    id: "save-all-document",
    document: ValidationDocument(title: "Batch", body: "Initial"),
    fileURL: validationDocumentURL,
    defaults: UserDefaults(suiteName: "FluentKitSaveAllValidation.\(UUID().uuidString)")!
)
let saveCoordinator = FluentDocumentCoordinator(sessions: [saveCoordinatorSession])
saveCoordinatorSession.mutate { $0.body = "Batch saved" }
try saveCoordinator.saveAll()
require(!saveCoordinatorSession.isDirty.value, "document coordinator saves every registered document")
require(saveCoordinator.closeAll(), "document coordinator closes a clean document set")

let importConfiguration = FluentFileImportConfiguration(
    allowedContentTypes: [.json],
    allowsMultipleSelection: true,
    canChooseDirectories: true,
    prompt: "Import",
    message: "Choose workspace files"
)
let exportConfiguration = FluentFileExportConfiguration(
    contentType: .json,
    defaultFilename: "workspace.json",
    canCreateDirectories: false,
    prompt: "Export",
    message: "Save a portable copy"
)

final class ValidationFileDialogSession: FluentFileDialogSession {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        let action = cancellation
        cancellation = nil
        action?()
    }
}

final class ValidationFileDialogPresenter: FluentFileDialogPresenting {
    var importConfiguration: FluentFileImportConfiguration?
    var exportConfiguration: FluentFileExportConfiguration?
    var importPresentations = 0
    var exportPresentations = 0
    var importCancellations = 0
    var exportCancellations = 0
    private var importCompletion: ((Result<[URL], Error>) -> Void)?
    private var exportCompletion: ((Result<URL, Error>) -> Void)?

    func presentImport(
        configuration: FluentFileImportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) -> any FluentFileDialogSession {
        importConfiguration = configuration
        importPresentations += 1
        importCompletion = completion
        return ValidationFileDialogSession { [weak self] in
            guard let self else { return }
            self.importCancellations += 1
            self.completeImport(.failure(FluentFileDialogError.cancelled))
        }
    }

    func presentExport(
        configuration: FluentFileExportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> any FluentFileDialogSession {
        exportConfiguration = configuration
        exportPresentations += 1
        exportCompletion = completion
        return ValidationFileDialogSession { [weak self] in
            guard let self else { return }
            self.exportCancellations += 1
            self.completeExport(.failure(FluentFileDialogError.cancelled))
        }
    }

    func completeImport(_ result: Result<[URL], Error>) {
        let completion = importCompletion
        importCompletion = nil
        completion?(result)
    }

    func completeExport(_ result: Result<URL, Error>) {
        let completion = exportCompletion
        exportCompletion = nil
        completion?(result)
    }
}

let fileDialogPresenter = ValidationFileDialogPresenter()

let importerPresented = FluentState(wrappedValue: false)
var importerCompletions = 0
var importedURLs: [URL] = []
let importerHost = FluentButtonView("Import document")
    .fileImporter(
        isPresented: importerPresented.projectedValue,
        configuration: importConfiguration,
        presenter: fileDialogPresenter
    ) { result in
        importerCompletions += 1
        if case let .success(urls) = result { importedURLs = urls }
    }
    ._mount(in: FluentRenderContext())
let importerWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
importerWindow.contentView = importerHost
importerWindow.orderFront(nil)
importerPresented.wrappedValue = true
drainMainQueue()
require(fileDialogPresenter.importPresentations == 1, "file importer presents through its configured presenter")
require(fileDialogPresenter.importConfiguration?.allowedContentTypes == [.json], "file importer forwards allowed content types")
require(fileDialogPresenter.importConfiguration?.allowsMultipleSelection == true, "file importer forwards multi-selection")
require(fileDialogPresenter.importConfiguration?.canChooseDirectories == true, "file importer forwards directory selection")
require(fileDialogPresenter.importConfiguration?.prompt == "Import", "file importer forwards its native prompt")
fileDialogPresenter.completeImport(.success([validationImportURL]))
drainMainQueue()
require(!importerPresented.wrappedValue, "file importer clears presentation after user selection")
require(importedURLs == [validationImportURL] && importerCompletions == 1, "file importer reports selected URLs")
importerPresented.wrappedValue = true
drainMainQueue()
importerPresented.wrappedValue = false
drainMainQueue()
require(fileDialogPresenter.importCancellations == 1, "file importer cancels its active presentation from the binding")
require(importerCompletions == 1, "programmatic importer dismissal does not report user cancellation")
importerWindow.orderOut(nil)

let exporterPresented = FluentState(wrappedValue: false)
var exporterCompletions = 0
var exportedURL: URL?
let exporterHost = FluentButtonView("Export document")
    .fileExporter(
        isPresented: exporterPresented.projectedValue,
        configuration: exportConfiguration,
        presenter: fileDialogPresenter
    ) { result in
        exporterCompletions += 1
        if case let .success(url) = result { exportedURL = url }
    }
    ._mount(in: FluentRenderContext())
let exporterWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
exporterWindow.contentView = exporterHost
exporterWindow.orderFront(nil)
exporterPresented.wrappedValue = true
drainMainQueue()
require(fileDialogPresenter.exportPresentations == 1, "file exporter presents through its configured presenter")
require(fileDialogPresenter.exportConfiguration?.contentType == .json, "file exporter forwards its content type")
require(fileDialogPresenter.exportConfiguration?.defaultFilename == "workspace.json", "file exporter forwards its default filename")
require(fileDialogPresenter.exportConfiguration?.canCreateDirectories == false, "file exporter forwards directory creation policy")
require(fileDialogPresenter.exportConfiguration?.prompt == "Export", "file exporter forwards its native prompt")
fileDialogPresenter.completeExport(.success(validationExportURL))
drainMainQueue()
require(!exporterPresented.wrappedValue, "file exporter clears presentation after user selection")
require(exportedURL == validationExportURL && exporterCompletions == 1, "file exporter reports its selected destination")
exporterPresented.wrappedValue = true
drainMainQueue()
exporterPresented.wrappedValue = false
drainMainQueue()
require(fileDialogPresenter.exportCancellations == 1, "file exporter cancels its active presentation from the binding")
require(exporterCompletions == 1, "programmatic exporter dismissal does not report user cancellation")
exporterWindow.orderOut(nil)

let serialPresenter = ValidationFileDialogPresenter()
let serialImporterPresented = FluentState(wrappedValue: false)
let serialExporterPresented = FluentState(wrappedValue: false)
let serialDialogHost = FluentButtonView("Serial file dialogs")
    .fileImporter(
        isPresented: serialImporterPresented.projectedValue,
        configuration: importConfiguration,
        presenter: serialPresenter
    ) { _ in }
    .fileExporter(
        isPresented: serialExporterPresented.projectedValue,
        configuration: exportConfiguration,
        presenter: serialPresenter
    ) { _ in }
    ._mount(in: FluentRenderContext())
let serialDialogWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
serialDialogWindow.contentView = serialDialogHost
serialDialogWindow.orderFront(nil)
serialImporterPresented.wrappedValue = true
serialExporterPresented.wrappedValue = true
drainMainQueue()
require(
    serialPresenter.importPresentations == 1 && serialPresenter.exportPresentations == 0,
    "window presentation coordinator starts only the first document-modal request"
)
serialPresenter.completeImport(.success([validationImportURL]))
drainMainQueue()
require(
    serialPresenter.exportPresentations == 1,
    "window presentation coordinator advances to the next queued request after completion"
)
serialPresenter.completeExport(.success(validationExportURL))
drainMainQueue()
require(!serialImporterPresented.wrappedValue && !serialExporterPresented.wrappedValue, "serialized file dialogs clear their own bindings")
serialDialogWindow.orderOut(nil)

final class DeferredValidationFileDialogPresenter: FluentFileDialogPresenting {
    var importPresentations = 0
    var importCancellations = 0
    private var importCompletions: [(Result<[URL], Error>) -> Void] = []

    func presentImport(
        configuration: FluentFileImportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) -> any FluentFileDialogSession {
        importPresentations += 1
        importCompletions.append(completion)
        return ValidationFileDialogSession { [weak self] in self?.importCancellations += 1 }
    }

    func presentExport(
        configuration: FluentFileExportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> any FluentFileDialogSession {
        ValidationFileDialogSession {}
    }

    func completeOldestImport(_ result: Result<[URL], Error>) {
        guard !importCompletions.isEmpty else { return }
        importCompletions.removeFirst()(result)
    }
}

let deferredPresenter = DeferredValidationFileDialogPresenter()
let rapidImporterPresented = FluentState(wrappedValue: false)
var rapidImporterCompletions = 0
let rapidImporterHost = FluentButtonView("Rapid importer")
    .fileImporter(
        isPresented: rapidImporterPresented.projectedValue,
        configuration: importConfiguration,
        presenter: deferredPresenter
    ) { _ in rapidImporterCompletions += 1 }
    ._mount(in: FluentRenderContext())
let rapidImporterWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
rapidImporterWindow.contentView = rapidImporterHost
rapidImporterWindow.orderFront(nil)
rapidImporterPresented.wrappedValue = true
drainMainQueue()
require(deferredPresenter.importPresentations == 1, "rapid importer begins its initial request")
rapidImporterPresented.wrappedValue = false
drainMainQueue()
rapidImporterPresented.wrappedValue = true
drainMainQueue()
require(
    deferredPresenter.importCancellations == 1 && deferredPresenter.importPresentations == 1,
    "rapid importer waits for native cancellation completion before reopening"
)
deferredPresenter.completeOldestImport(.failure(FluentFileDialogError.cancelled))
drainMainQueue()
require(rapidImporterPresented.wrappedValue, "an old file-dialog completion cannot clear a reopened binding")
require(deferredPresenter.importPresentations == 2, "rapid importer reopens after the old request releases the window")
require(rapidImporterCompletions == 0, "programmatic dismissal does not leak a stale file-dialog completion")
deferredPresenter.completeOldestImport(.success([validationImportURL]))
drainMainQueue()
require(!rapidImporterPresented.wrappedValue, "the current file-dialog completion clears its binding")
require(rapidImporterCompletions == 1, "the current file-dialog completion is delivered exactly once")
rapidImporterWindow.orderOut(nil)

final class ValidationPrintSession: FluentPrintSession {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) { self.cancellation = cancellation }

    func cancel() {
        let action = cancellation
        cancellation = nil
        action?()
    }
}

final class ValidationPrintPresenter: FluentPrintPresenting {
    var view: NSView?
    var window: NSWindow?
    var configuration: FluentPrintConfiguration?
    var presentations = 0
    var cancellations = 0
    private var completion: ((Result<Void, Error>) -> Void)?

    func presentPrint(
        view: NSView,
        in window: NSWindow?,
        configuration: FluentPrintConfiguration,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> any FluentPrintSession {
        self.view = view
        self.window = window
        self.configuration = configuration
        presentations += 1
        self.completion = completion
        return ValidationPrintSession { [weak self] in
            guard let self else { return }
            cancellations += 1
            let callback = self.completion
            self.completion = nil
            callback?(.failure(FluentPrintError.cancelled))
        }
    }

    func complete(_ result: Result<Void, Error>) {
        let callback = completion
        completion = nil
        callback?(result)
    }
}

final class ValidationSharingSession: FluentSharingSession {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) { self.cancellation = cancellation }

    func dismiss() {
        let action = cancellation
        cancellation = nil
        action?()
    }
}

final class ValidationSharingPresenter: FluentSharingPresenting {
    var items: [Any] = []
    var view: NSView?
    var configuration: FluentSharingConfiguration?
    var presentations = 0
    var dismissals = 0

    func presentSharing(
        items: [Any],
        from view: NSView,
        configuration: FluentSharingConfiguration
    ) -> any FluentSharingSession {
        self.items = items
        self.view = view
        self.configuration = configuration
        presentations += 1
        return ValidationSharingSession { [weak self] in self?.dismissals += 1 }
    }
}

let printPresenter = ValidationPrintPresenter()
let printView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
let printWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
let printConfiguration = FluentPrintConfiguration(
    jobTitle: "Validation print",
    showsPrintPanel: false,
    showsProgressPanel: false
)
let printSession = printPresenter.presentPrint(
    view: printView,
    in: printWindow,
    configuration: printConfiguration
) { result in
    if case .success = result {
        return
    }
    require(false, "print presenter reports a successful native print")
}
require(printPresenter.presentations == 1, "printing routes through the injected presenter")
require(printPresenter.view === printView && printPresenter.window === printWindow, "printing forwards its source view and window")
require(printPresenter.configuration?.jobTitle == "Validation print", "printing forwards job metadata")
printPresenter.complete(.success(()))
printSession.cancel()
require(printPresenter.cancellations == 1, "print sessions expose cancellation")

let sharingPresenter = ValidationSharingPresenter()
let shareView = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 80))
let sharingSession = sharingPresenter.presentSharing(
    items: ["Share this text", validationExportURL],
    from: shareView,
    configuration: FluentSharingConfiguration(
        relativeRect: NSRect(x: 4, y: 5, width: 40, height: 20),
        preferredEdge: .maxX
    )
)
require(sharingPresenter.presentations == 1, "sharing routes through the injected presenter")
require(sharingPresenter.items.count == 2 && sharingPresenter.view === shareView, "sharing forwards its items and anchor view")
require(sharingPresenter.configuration?.relativeRect == NSRect(x: 4, y: 5, width: 40, height: 20), "sharing forwards its anchor geometry")
sharingSession.dismiss()
require(sharingPresenter.dismissals == 1, "sharing sessions expose dismissal")

struct ValidationApp: FluentApp {
    var body: FluentWindowScene<FluentTextView> {
        FluentWindowScene(title: "Validation", size: NSSize(width: 420, height: 280), material: nil) {
            FluentText("Application scene")
        }
    }
}
let appDescription = ValidationApp().body._makeWindowDescription()
require(appDescription.id == "main", "fluent app scene supplies a stable default window ID")
require(appDescription.placement == .automatic, "fluent app scene supplies automatic placement by default")
require(appDescription.restoration == .automatic, "fluent app scene enables frame restoration by default")
require(appDescription.title == "Validation", "fluent app scene preserves window title")
require(appDescription.size == NSSize(width: 420, height: 280), "fluent app scene preserves window size")
require(appDescription.material == nil, "fluent app scene supports plain AppKit windows")
require(appDescription.content._mount(in: appDescription.context) is NSTextField, "fluent app scene mounts declarative content")

struct MultiSceneApp: FluentApp {
    var body: FluentSceneGroup {
        FluentSceneGroup {
            FluentWindowScene(id: "main-window", title: "Main", material: nil, placement: .centered) {
                FluentText("Main")
            }
            FluentWindowScene(id: "inspector-window", title: "Inspector", size: NSSize(width: 260, height: 220), material: nil, initiallyVisible: false) {
                FluentText("Inspector")
            }
        }
    }
}
let multiDescriptions = MultiSceneApp().body._makeWindowDescriptions()
require(multiDescriptions.count == 2, "scene group composes multiple native windows")
require(multiDescriptions.map(\.title) == ["Main", "Inspector"], "scene group preserves window ordering")
require(multiDescriptions.map(\.id) == ["main-window", "inspector-window"], "scene group preserves stable window IDs")
require(multiDescriptions.first?.placement == .centered, "scene group preserves window placement policy")
require(multiDescriptions.last?.initiallyVisible == false, "scene group preserves deferred window visibility")
let transientScene = FluentWindowScene(id: "transient", title: "Transient", material: nil, restoration: .disabled) { FluentText("Transient") }
require(transientScene._makeWindowDescription().restoration == .disabled, "scene can disable frame restoration")
require(FluentWindowCommand.toggle("inspector-window") == FluentWindowCommand.toggle("inspector-window"), "window commands are value comparable")

let settingsScene = FluentSettingsScene(material: nil) {
    FluentText("Application settings")
}
let settingsDescription = settingsScene._makeWindowDescription()
require(settingsDescription.id == "settings", "settings scene supplies a stable default ID")
require(settingsDescription.role == .settings, "settings scene carries its semantic window role")
require(settingsDescription.restoration == .disabled, "settings scene avoids restoring stale frames")
require(settingsDescription.tabbing == .disallowed, "settings scene opts out of document tabs")
require(!settingsDescription.initiallyVisible, "settings scene opens on demand")

let windowRestorationDefaults = UserDefaults(suiteName: "FluentKitWindowRestorationValidation.\(UUID().uuidString)")!
let restoredMainDescription = FluentWindowDescription(
    id: "restored-main",
    title: "Restored Main",
    size: NSSize(width: 420, height: 280),
    minimumSize: NSSize(width: 240, height: 160),
    styleMask: [.titled, .closable],
    material: nil,
    restoration: .automatic,
    initiallyVisible: true,
    content: FluentAnyView(FluentText("Restored main"))
)
let restoredUtilityDescription = FluentWindowDescription(
    id: "restored-utility",
    title: "Restored Utility",
    size: NSSize(width: 260, height: 200),
    minimumSize: NSSize(width: 180, height: 140),
    styleMask: [.titled, .closable],
    material: nil,
    restoration: .automatic,
    initiallyVisible: false,
    content: FluentAnyView(FluentText("Restored utility"))
)
let nonRestoredDescription = FluentWindowDescription(
    id: "non-restored",
    title: "Non Restored",
    size: NSSize(width: 220, height: 160),
    minimumSize: NSSize(width: 160, height: 120),
    styleMask: [.titled, .closable],
    material: nil,
    restoration: .disabled,
    initiallyVisible: false,
    content: FluentAnyView(FluentText("Non restored"))
)
let restorationDescriptions = [restoredMainDescription, restoredUtilityDescription, nonRestoredDescription]
let makeRestorationWindow: (FluentWindowDescription) -> NSWindow = { description in
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: description.size),
        styleMask: description.styleMask,
        backing: .buffered,
        defer: false
    )
    window.title = description.title
    window.contentView = description.content._mount(in: description.context)
    window.isReleasedWhenClosed = false
    return window
}
let firstRestorationCoordinator = FluentWindowCoordinator(
    descriptions: restorationDescriptions,
    makeWindow: makeRestorationWindow,
    positionWindow: { _, _, _ in },
    defaults: windowRestorationDefaults
)
let firstRestoredMain = firstRestorationCoordinator.open(id: "restored-main")
let firstRestoredUtility = firstRestorationCoordinator.open(id: "restored-utility")
firstRestoredMain?.setFrame(NSRect(x: 120, y: 120, width: 420, height: 280), display: false)
firstRestoredUtility?.setFrame(NSRect(x: 180, y: 180, width: 260, height: 200), display: false)
firstRestorationCoordinator.open(id: "non-restored")
firstRestorationCoordinator.focus(id: "restored-utility")
firstRestorationCoordinator.saveRestorationState()
require(
    windowRestorationDefaults.array(forKey: "FluentKit.windows.openIDs") as? [String] == ["restored-main", "restored-utility", "non-restored"],
    "window coordinator persists the declaration-ordered open window set"
)
require(
    windowRestorationDefaults.string(forKey: "FluentKit.windows.activeID") == "restored-utility",
    "window coordinator persists the active window ID"
)
let secondRestorationCoordinator = FluentWindowCoordinator(
    descriptions: restorationDescriptions,
    makeWindow: makeRestorationWindow,
    positionWindow: { _, _, _ in },
    defaults: windowRestorationDefaults
)
secondRestorationCoordinator.openInitiallyVisibleWindows()
let secondRestoredMainFrame = secondRestorationCoordinator.window(for: "restored-main")?.frame ?? .zero
let secondRestoredUtilityFrame = secondRestorationCoordinator.window(for: "restored-utility")?.frame ?? .zero
let firstRestoredMainFrame = firstRestoredMain?.frame ?? .zero
let firstRestoredUtilityFrame = firstRestoredUtility?.frame ?? .zero
require(
    secondRestorationCoordinator.openWindowIDs == ["restored-main", "restored-utility"],
    "window restoration reopens automatic utility windows but excludes disabled restoration scenes"
)
require(
    secondRestoredMainFrame == firstRestoredMainFrame
        && secondRestoredUtilityFrame == firstRestoredUtilityFrame,
    "window restoration keeps independent frames for multiple stable IDs (main: \(secondRestoredMainFrame) vs \(firstRestoredMainFrame), utility: \(secondRestoredUtilityFrame) vs \(firstRestoredUtilityFrame))"
)
let restoredUtilityWindow = secondRestorationCoordinator.window(for: "restored-utility")
let restoredMainWindow = secondRestorationCoordinator.window(for: "restored-main")
require(
    secondRestorationCoordinator.activeWindowID == "restored-utility"
        && restoredUtilityWindow?.isVisible == true
        && restoredMainWindow?.isVisible == true,
    "window restoration restores the active stable ID and reopens both windows"
)
let edgeRestorationDefaults = UserDefaults(suiteName: "FluentKitWindowRestorationEdgeValidation.\(UUID().uuidString)")!
edgeRestorationDefaults.set(["restored-main", "restored-utility"], forKey: "FluentKit.windows.openIDs")
edgeRestorationDefaults.set("restored-main", forKey: "FluentKit.windows.activeID")
if let visibleFrame = NSScreen.main?.visibleFrame {
    edgeRestorationDefaults.set(
        [visibleFrame.maxX - 12, visibleFrame.minY + 40, 420, 280],
        forKey: "FluentKit.window.restored-main.frame"
    )
}
let edgeRestorationCoordinator = FluentWindowCoordinator(
    descriptions: restorationDescriptions,
    makeWindow: makeRestorationWindow,
    positionWindow: { _, _, _ in },
    defaults: edgeRestorationDefaults
)
edgeRestorationCoordinator.openInitiallyVisibleWindows()
let edgeRestoredMainWindow = edgeRestorationCoordinator.window(for: "restored-main")
require(
    edgeRestorationCoordinator.activeWindowID == "restored-main",
    "window restoration preserves an active ID that is not the last declared window"
)
if let visibleFrame = NSScreen.main?.visibleFrame, let edgeRestoredMainWindow {
    require(
        edgeRestoredMainWindow.frame.minX >= visibleFrame.minX - 1
            && edgeRestoredMainWindow.frame.maxX <= visibleFrame.maxX + 1
            && edgeRestoredMainWindow.frame.minY >= visibleFrame.minY - 1
            && edgeRestoredMainWindow.frame.maxY <= visibleFrame.maxY + 1,
        "window restoration constrains a partially off-screen frame to the visible screen"
    )
}
let invalidFrameDefaults = UserDefaults(suiteName: "FluentKitWindowRestorationInvalidValidation.\(UUID().uuidString)")!
invalidFrameDefaults.set(["restored-main"], forKey: "FluentKit.windows.openIDs")
invalidFrameDefaults.set("restored-main", forKey: "FluentKit.windows.activeID")
invalidFrameDefaults.set(
    [Double.nan, Double.infinity, 420, 280],
    forKey: "FluentKit.window.restored-main.frame"
)
let invalidFrameCoordinator = FluentWindowCoordinator(
    descriptions: restorationDescriptions,
    makeWindow: makeRestorationWindow,
    positionWindow: { _, _, _ in },
    defaults: invalidFrameDefaults
)
invalidFrameCoordinator.openInitiallyVisibleWindows()
let invalidRestoredFrame = invalidFrameCoordinator.window(for: "restored-main")?.frame ?? .zero
require(
    invalidRestoredFrame.origin.x.isFinite
        && invalidRestoredFrame.origin.y.isFinite
        && invalidRestoredFrame.width >= restoredMainDescription.minimumSize.width
        && invalidRestoredFrame.height >= restoredMainDescription.minimumSize.height,
    "window restoration ignores non-finite saved frame coordinates"
)
secondRestorationCoordinator.close(id: "restored-utility")
drainMainQueue()
secondRestorationCoordinator.saveRestorationState()
let thirdRestorationCoordinator = FluentWindowCoordinator(
    descriptions: restorationDescriptions,
    makeWindow: makeRestorationWindow,
    positionWindow: { _, _, _ in },
    defaults: windowRestorationDefaults
)
thirdRestorationCoordinator.openInitiallyVisibleWindows()
require(
    thirdRestorationCoordinator.openWindowIDs == ["restored-main"],
    "closing a restored utility window updates the next launch open set"
)
[firstRestoredMain, firstRestoredUtility, secondRestorationCoordinator.window(for: "restored-main"), secondRestorationCoordinator.window(for: "restored-utility"), thirdRestorationCoordinator.window(for: "restored-main"), edgeRestorationCoordinator.window(for: "restored-main"), edgeRestorationCoordinator.window(for: "restored-utility"), invalidFrameCoordinator.window(for: "restored-main")].compactMap { $0 }.forEach { $0.orderOut(nil) }

let preferredTabScene = FluentWindowScene(
    id: "tabbed-document",
    title: "Tabbed",
    material: nil,
    tabbing: .preferred(identifier: "validation.workspace")
) {
    FluentText("Tabbed document")
}
require(
    preferredTabScene._makeWindowDescription().tabbing == .preferred(identifier: "validation.workspace"),
    "window scenes preserve preferred native tab groups"
)

var settingsActionInvocations = 0
let settingsMenuCoordinator = FluentMainMenuCoordinator(
    applicationName: "Validation",
    settingsAction: { settingsActionInvocations += 1 }
)
let settingsMenuItem = settingsMenuCoordinator.menu.items.first?.submenu?.items.first {
    $0.title == "Settings..."
}
require(settingsMenuItem?.keyEquivalent == ",", "settings scene menu uses the standard Command-comma shortcut")
if let settingsMenuItem, let action = settingsMenuItem.action {
    _ = NSApp.sendAction(action, to: settingsMenuItem.target, from: settingsMenuItem)
}
require(settingsActionInvocations == 1, "settings menu routes to its declarative scene action")

final class ValidationApplicationServices: FluentApplicationServices {
    var openedFiles: [URL] = []
    var openedURLs: [URL] = []
    var reopenRequests: [Bool] = []
    var handlesReopen = false
    var dockInvocations = 0
    var serviceInvocations = 0

    func applicationOpenFiles(_ urls: [URL], with coordinator: FluentWindowCoordinator) {
        openedFiles = urls
    }

    func applicationOpenURLs(_ urls: [URL], with coordinator: FluentWindowCoordinator) {
        openedURLs = urls
    }

    func applicationShouldHandleReopen(
        hasVisibleWindows: Bool,
        with coordinator: FluentWindowCoordinator
    ) -> Bool {
        reopenRequests.append(hasVisibleWindows)
        return handlesReopen
    }

    var applicationDockMenuItems: [FluentMenuItem] {
        [FluentMenuItem("New workspace") { self.dockInvocations += 1 }]
    }

    var applicationServicesMenuTypes: FluentServicesMenuTypes {
        FluentServicesMenuTypes(
            sendTypes: [.string],
            returnTypes: [.string]
        )
    }

    var applicationProvidedServices: [FluentProvidedService] {
        [FluentProvidedService(
            identifier: "validation.uppercase",
            acceptedTypes: [.string],
            returnedTypes: [.string]
        ) { pasteboard, _ in
            self.serviceInvocations += 1
            guard let value = pasteboard.string(forType: .string) else { return }
            pasteboard.clearContents()
            pasteboard.setString(value.uppercased(), forType: .string)
        }]
    }
}

let serviceDescription = FluentWindowDescription(
    id: "z-service-main",
    title: "Service Main",
    material: nil,
    initiallyVisible: false,
    content: FluentAnyView(FluentText("Service window"))
)
let serviceUtilityDescription = FluentWindowDescription(
    id: "a-service-utility",
    title: "Service Utility",
    material: nil,
    initiallyVisible: false,
    content: FluentAnyView(FluentText("Service utility"))
)
let serviceWindows = FluentWindowCoordinator(
    descriptions: [serviceDescription, serviceUtilityDescription],
    makeWindow: { description in
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: description.size),
            styleMask: description.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = description.title
        window.isReleasedWhenClosed = false
        return window
    },
    positionWindow: { _, _, _ in },
    defaults: UserDefaults(suiteName: "FluentKitServicesValidation.\(UUID().uuidString)")!
)
let serviceProvider = ValidationApplicationServices()
let applicationServices = FluentApplicationServicesCoordinator(
    provider: serviceProvider,
    windows: serviceWindows
)
let openedFileURLs = [URL(fileURLWithPath: "/tmp/one.fluent"), URL(fileURLWithPath: "/tmp/two.fluent")]
let openedWebURLs = [URL(string: "fluentkit://workspace/42")!]
applicationServices.openFiles(openedFileURLs)
applicationServices.openURLs(openedWebURLs)
require(serviceProvider.openedFiles == openedFileURLs, "application services route native file-open events")
require(serviceProvider.openedURLs == openedWebURLs, "application services route native URL-open events")
require(applicationServices.handleReopen(hasVisibleWindows: false), "application services accept reopen requests")
require(serviceProvider.reopenRequests == [false], "application service provider receives window visibility on reopen")
require(serviceWindows.openWindowIDs == ["z-service-main"], "default reopen behavior restores the first declared scene")
let dockMenu = applicationServices.makeDockMenu()
require(dockMenu?.items.map(\.title) == ["New workspace"], "application services build a native Dock menu from declarative items")
dockMenu?.performActionForItem(at: 0)
require(serviceProvider.dockInvocations == 1, "Dock menu items retain their Swift actions")
let servicePasteboard = NSPasteboard(name: NSPasteboard.Name("FluentKitServicesValidation.\(UUID().uuidString)"))
servicePasteboard.clearContents()
servicePasteboard.setString("Fluent service", forType: NSPasteboard.PasteboardType.string)
try? applicationServices.performProvidedService(
    identifier: "validation.uppercase",
    pasteboard: servicePasteboard
)
require(serviceProvider.serviceInvocations == 1, "provided services route through their declarative action")
require(servicePasteboard.string(forType: NSPasteboard.PasteboardType.string) == "FLUENT SERVICE", "provided services can transform the native pasteboard")
servicePasteboard.clearContents()
servicePasteboard.setString("Fluent service", forType: NSPasteboard.PasteboardType.string)
let invalidServicePasteboard = NSPasteboard(name: NSPasteboard.Name("FluentKitServicesValidation.invalid.\(UUID().uuidString)"))
invalidServicePasteboard.clearContents()
do {
    try applicationServices.performProvidedService(
        identifier: "validation.uppercase",
        pasteboard: invalidServicePasteboard
    )
    require(false, "provided services reject unsupported pasteboard contents")
} catch let error as FluentProvidedServiceError {
    require(error == .unsupportedPasteboardContents("validation.uppercase"), "provided service reports unsupported pasteboard contents")
}
applicationServices.installServices(on: NSApp)
require(NSApp.servicesProvider as AnyObject? === applicationServices, "application services install the native Services provider")
require(
    settingsMenuCoordinator.servicesMenu.title == "Services",
    "main menu coordinator owns a native Services submenu"
)
serviceWindows.window(for: "z-service-main")?.orderOut(nil)

let routeHistory = FluentNavigationCoordinator(initial: "home")
require(routeHistory.push("controls"), "NavigationCoordinator pushes a distinct route")
require(routeHistory.push("button"), "NavigationCoordinator appends a second forward route")
require(
    routeHistory.goBack() == "controls"
        && routeHistory.direction == .backward
        && routeHistory.canGoForward,
    "NavigationCoordinator exposes browser-style Back state independently from UndoManager"
)
require(
    routeHistory.goForward() == "button" && routeHistory.direction == .forward,
    "NavigationCoordinator restores the forward route"
)
_ = routeHistory.goBack()
require(
    routeHistory.push("textbox")
        && !routeHistory.canGoForward
        && routeHistory.entries == ["home", "controls", "textbox"],
    "a new navigation push truncates the forward stack"
)
require(!routeHistory.push("textbox"), "NavigationCoordinator ignores a duplicate current route")

let hierarchySelection = FluentState<String?>(wrappedValue: "standalone")
let hierarchyPaneOpen = FluentState(wrappedValue: true)
let hierarchyHost = FluentViewHost(
    FluentNavigationView(
        [
            FluentNavigationItem(
                id: "parent",
                title: "Parent",
                systemImageName: "folder",
                children: [
                    FluentNavigationItem(id: "child", title: "Child", systemImageName: "doc")
                ],
                selectsOnInvoked: false
            ),
            FluentNavigationItem(id: "standalone", title: "Standalone", systemImageName: "star")
        ],
        selection: hierarchySelection.projectedValue,
        isPaneOpen: hierarchyPaneOpen.projectedValue,
        paneDisplayMode: .left,
        contentTransition: .none
    ) {
        FluentText("Hierarchy content")
    }
)
hierarchyHost.frame = NSRect(x: 0, y: 0, width: 720, height: 420)
hierarchyHost.layoutSubtreeIfNeeded()
let initialHierarchyButtons = views(identifier: "FluentKit.NavigationView.Item", in: hierarchyHost)
let hierarchyParent = initialHierarchyButtons.first { $0.accessibilityTitle() == "Parent" } as? NSButton
let hierarchyStandalone = initialHierarchyButtons.first { $0.accessibilityTitle() == "Standalone" }
require(initialHierarchyButtons.count == 2, "collapsed hierarchical NavigationView hides descendant rows")
require(
    firstLayer(named: "FluentKit.NavigationView.ItemChevron", in: hierarchyParent ?? NSView())?.isHidden == false
        && firstLayer(named: "FluentKit.NavigationView.ItemChevron", in: hierarchyStandalone ?? NSView())?.isHidden != false,
    "NavigationView shows a Chevron only for items with children"
)
hierarchyParent?.performClick(nil)
hierarchyHost.layoutSubtreeIfNeeded()
require(
    views(identifier: "FluentKit.NavigationView.Item", in: hierarchyHost).contains {
        $0.accessibilityTitle() == "Child"
    },
    "hierarchical NavigationView expands child rows from the public item model"
)
hierarchyParent?.performClick(nil)
require(
    waitUntil(timeout: 0.35) {
        views(identifier: "FluentKit.NavigationView.Item", in: hierarchyHost).count == 2
    },
    "hierarchical NavigationView collapses descendants through the shared animation coordinator"
)

let navigationQuery = FluentState(wrappedValue: "but")
let navigationPaneOpen = FluentState(wrappedValue: false)
var submittedNavigationSuggestion: FluentNavigationSearchSuggestion?
let navigationSearchHost = FluentViewHost(
    FluentNavigationSearch(
        navigationQuery.projectedValue,
        isPaneOpen: navigationPaneOpen.projectedValue,
        suggestions: { query in
            query.isEmpty ? [] : [FluentNavigationSearchSuggestion(id: "button", title: "Button")]
        },
        onSubmit: { _, suggestion in submittedNavigationSuggestion = suggestion }
    )
)
navigationSearchHost.frame = NSRect(x: 0, y: 0, width: 240, height: 96)
navigationSearchHost.layoutSubtreeIfNeeded()
let navigationSearchField = firstView(
    identifier: "FluentKit.NavigationView.Search.Field",
    in: navigationSearchHost
)
let navigationSuggestion = firstView(
    identifier: "FluentKit.NavigationView.Search.Suggestion",
    in: navigationSearchHost
) as? NSButton
require(
    navigationSearchField?.isHidden == false && navigationSuggestion != nil,
    "NavigationSearch displays its field and suggestions in the expanded pane"
)
navigationSuggestion?.performClick(nil)
require(
    submittedNavigationSuggestion?.id == AnyHashable("button"),
    "NavigationSearch submits a selected suggestion through its public callback"
)
navigationSearchHost.frame = NSRect(x: 0, y: 0, width: 48, height: 40)
navigationSearchHost.layoutSubtreeIfNeeded()
let compactSearchButton = firstView(
    identifier: "FluentKit.NavigationView.Search.CompactButton",
    in: navigationSearchHost
) as? NSButton
require(
    navigationSearchField?.isHidden == true && compactSearchButton?.isHidden == false,
    "NavigationSearch replaces the field with a compact search button"
)
compactSearchButton?.performClick(nil)
require(navigationPaneOpen.wrappedValue, "compact NavigationSearch requests the pane to expand")

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let snapshotBaselines: [(filename: String, width: Int, height: Int)] = [
    ("accessibility-light.png", 980, 680),
    ("accessibility-dark.png", 980, 680),
    ("accessibility-rtl.png", 980, 680),
    ("application-light.png", 980, 680),
    ("application-dark.png", 980, 680),
    ("controls-light.png", 980, 680),
    ("controls-dark.png", 980, 680),
    ("collections-light.png", 980, 680),
    ("collections-dark.png", 980, 680),
    ("inputs-light.png", 980, 680),
    ("inputs-dark.png", 980, 680),
    ("window-shell-extended-light.png", 980, 680),
    ("window-shell-native-light.png", 980, 680),
    ("command-bar-flyout-light.png", 141, 133),
    ("command-bar-flyout-dark.png", 141, 133),
    ("menu-flyout-light.png", 194, 121),
    ("menu-flyout-dark.png", 194, 121),
    ("menu-flyout-high-contrast.png", 194, 121),
    ("navigation-minimal-light.png", 560, 680),
    ("navigation-minimal-dark.png", 560, 680),
    ("navigation-top-light.png", 980, 680),
    ("navigation-top-dark.png", 980, 680),
    ("navigation-top-rtl.png", 980, 680)
]
for baseline in snapshotBaselines {
    let filename = baseline.filename
    let url = packageRoot.appendingPathComponent(".snapshots").appendingPathComponent(filename)
    guard let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data) else {
        require(false, "snapshot baseline \(filename) exists and is a readable bitmap")
        continue
    }
    require(
        bitmap.pixelsWide == baseline.width && bitmap.pixelsHigh == baseline.height,
        "snapshot baseline \(filename) preserves the \(baseline.width) x \(baseline.height) viewport"
    )
    require(
        bitmapHasVisibleVariation(bitmap),
        "snapshot baseline \(filename) contains rendered pixel variation"
    )
}

print("FluentKitValidation: PASS")
