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

func firstLabel(in view: NSView) -> NSTextField? {
    if let label = view as? NSTextField, !label.isEditable { return label }
    return view.subviews.lazy.compactMap(firstLabel).first
}

func firstButton(in view: NSView) -> FluentButton? {
    if let button = view as? FluentButton { return button }
    return view.subviews.lazy.compactMap(firstButton).first
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
        return layer.sublayers?.lazy.compactMap(search).first
    }
    if let layer = view.layer, let match = search(layer) { return match }
    return view.subviews.lazy.compactMap { firstLayer(named: name, in: $0) }.first
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
let highContrastFieldAppearance = FluentAutomaticTextFieldStyle().appearance(
    for: FluentTextFieldStyleConfiguration(isEnabled: true, isFocused: false, controlSize: .regular, theme: highContrastSelectionTheme)
)
require(highContrastFieldAppearance.borderWidth > standardFieldAppearance.borderWidth, "high contrast increases text field border emphasis")
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
drainMainQueue()
let checkBoxOffAnimation = checkBoxGlyph.animation(forKey: "fluent.checkbox.glyph.strokeEnd") as? CABasicAnimation
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
    contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
segmentedMotionWindow.contentView = styledSegmentHost
segmentedMotionWindow.orderFront(nil)
let nativeStyledSegmented = firstSegmentedControl(in: styledSegmentHost)
require(nativeStyledSegmented?.font?.pointSize == 15, "segmented style applies semantic font metrics")
nativeStyledSegmented?.frame = NSRect(x: 0, y: 0, width: 240, height: 32)
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
    contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
rtlSegmentWindow.contentView = rtlSegmentHost
rtlSegmentWindow.orderFront(nil)
guard let rtlSegmented = firstSegmentedControl(in: rtlSegmentHost) else {
    fatalError("RTL segmented validation hierarchy did not mount")
}
rtlSegmented.frame = NSRect(x: 0, y: 0, width: 270, height: 32)
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
require(secureField?.stringValue == "initial-secret", "secure field reads its initial binding value")
require((secureField as? FluentSecureTextField)?.fluentStyle is ValidationTextFieldStyle, "secure field receives the shared text field style")
secureText.wrappedValue = "external-secret"
drainMainQueue()
require(secureField?.stringValue == "external-secret", "secure field reflects external binding updates")
secureField?.stringValue = "edited-secret"
if let secureField, let delegate = secureField.delegate {
    delegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: secureField))
}
require(secureText.wrappedValue == "edited-secret", "secure field writes native edits through its binding")

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
searchField?.stringValue = "fluent"
if let searchField, let delegate = searchField.delegate {
    delegate.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: searchField))
}
require(searchText.wrappedValue == "fluent", "search field writes native edits through its binding")
searchText.wrappedValue = "external-filter"
drainMainQueue()
require(searchField?.stringValue == "external-filter", "search field reflects external binding updates")
if let searchField, let action = searchField.action {
    require(NSApp.sendAction(action, to: searchField.target, from: searchField), "search field sends its submit action")
}
require(searchSubmits == 1, "search field invokes submit callback")

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
comboFlyoutWindow.center()
comboFlyoutWindow.makeKeyAndOrderFront(nil)
comboView.layoutSubtreeIfNeeded()
guard let comboFocusPill = firstLayer(named: "FluentKit.ComboBox.FocusPill", in: comboView) else {
    fatalError("ComboBox focus Pill did not mount")
}
guard let comboFocusHighlight = firstLayer(named: "FluentKit.ComboBox.FocusHighlight", in: comboView) else {
    fatalError("ComboBox focus Highlight did not mount")
}
guard let nativeComboBox else { fatalError("ComboBox native control did not mount") }
nativeComboBox.performClick(nil)
require(
    comboFocusPill.opacity == 1
        && comboFocusPill.frame.size == CGSize(width: 3, height: 16),
    "focused ComboBox exposes the source-derived 3 x 16 leading Pill"
)
require(
    comboFocusHighlight.opacity == 1
        && comboFocusHighlight.frame == comboView.bounds.insetBy(dx: -4, dy: -4)
        && comboFocusHighlight.borderWidth == 2
        && comboFocusHighlight.cornerRadius == 7,
    "focused ComboBox exposes the source-derived -4 margin, 2pt, 7pt focus highlight"
)
drainMainQueue()
require(comboFlyoutWindow.childWindows?.count == 1, "combo box opens an application-owned flyout panel")
if let comboPanelContent = comboFlyoutWindow.childWindows?.first?.contentView {
    require(firstView(withAccessibilityRole: .menu, in: comboPanelContent) != nil, "combo box popup uses the Fluent menu presenter")
    guard let selectedRow = firstView(withAccessibilityTitle: "Third", in: comboPanelContent),
          let selectionPill = firstLayer(named: "FluentKit.ComboBoxItem.SelectionPill", in: comboPanelContent) else {
        fatalError("ComboBox selected-item Pill did not mount")
    }
    require(
        selectionPill.frame.size == CGSize(width: 3, height: 16),
        "selected ComboBoxItem exposes the source-derived 3 x 16 leading Pill"
    )
    selectedRow.mouseDown(
        with: toggleMouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 16), in: selectedRow, eventNumber: 70)
    )
    let pillPressAnimation = selectionPill.animation(forKey: "fluent.combobox.pill.frame") as? CABasicAnimation
    require(
        selectionPill.frame.height == 10
            && abs((pillPressAnimation?.duration ?? 0) - 0.167) < 0.0001,
        "pressed ComboBoxItem compresses its Pill to 62.5% over 167ms"
    )
}
if let escapeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
    if let panel = comboFlyoutWindow.childWindows?.first,
       let presenter = panel.contentView.flatMap({ firstView(withAccessibilityRole: .menu, in: $0) }) {
        presenter.keyDown(with: escapeEvent)
    }
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.24))
require(comboFlyoutWindow.childWindows?.isEmpty != false, "combo box flyout dismisses through the shared Escape path")
comboFlyoutWindow.orderOut(nil)
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
let downwardOutgoingGroup = previousListSelectionIndicator?.animation(
    forKey: "fluent.navigation.selection.outgoing"
) as? CAAnimationGroup
require(
    downwardIncomingGroup != nil && downwardOutgoingGroup != nil,
    "stable-ID list selection animates incoming and outgoing navigation indicators (incoming: \(downwardIncomingGroup != nil), outgoing: \(downwardOutgoingGroup != nil))"
)
require(
    downwardIncomingGroup?.duration == FluentMotion.navigationIndicator.duration,
    "navigation indicator uses the 600ms motion token"
)
let downwardPosition = keyframeAnimation(for: "position", in: downwardIncomingGroup)
let downwardScale = keyframeAnimation(for: "transform.scale.y", in: downwardIncomingGroup)
let downwardOpacity = keyframeAnimation(for: "opacity", in: downwardOutgoingGroup)
let downwardStart = (downwardPosition?.values?.first as? NSValue)?.pointValue.y
let downwardEnd = (downwardPosition?.values?.last as? NSValue)?.pointValue.y
require(
    downwardStart.map { start in downwardEnd.map { start < $0 } == true } == true,
    "navigation indicator keyframes preserve downward selection direction (start: \(String(describing: downwardStart)), end: \(String(describing: downwardEnd)))"
)
require(
    ((downwardScale?.values?[1] as? NSNumber)?.doubleValue ?? 0) > 1,
    "navigation indicator stretches across rows at the one-third keyframe"
)
require(
    downwardOpacity?.values?.count == 3,
    "outgoing navigation indicator remains visible through one third before fading"
)
selectedID.wrappedValue = "General"
drainMainQueue()
let upwardIncomingGroup = listSelectionIndicator?.animation(
    forKey: "fluent.navigation.selection"
) as? CAAnimationGroup
let upwardPosition = keyframeAnimation(for: "position", in: upwardIncomingGroup)
let upwardStart = (upwardPosition?.values?.first as? NSValue)?.pointValue.y
let upwardEnd = (upwardPosition?.values?.last as? NSValue)?.pointValue.y
require(
    upwardStart.map { start in upwardEnd.map { start > $0 } == true } == true,
    "navigation indicator keyframes preserve upward selection direction"
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
    rapidEnd.map { end in aboutRow.map { abs(end - $0.frame.midY) < 0.5 } == true } == true,
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

var sectionedSnapshot = FluentCollectionSnapshot<String, Int>()
sectionedSnapshot.appendSections(["active", "recent"])
sectionedSnapshot.appendItems([1, 2, 3], toSection: "active")
sectionedSnapshot.appendItems([4, 5], toSection: "recent")
let collectionSelections = FluentState(wrappedValue: Set([2, 5]))
let sectionedCollection = FluentCollection(
    snapshot: sectionedSnapshot,
    layout: .adaptiveGrid(minimumItemWidth: 120, itemHeight: 72, spacing: 8),
    selectionIDs: collectionSelections.projectedValue
) { item in
    FluentText("Item \(item)")
} header: { section in
    FluentText(section.capitalized, weight: .semibold)
}
let sectionedCollectionView = sectionedCollection._mount(in: FluentRenderContext())
sectionedCollectionView.frame = NSRect(x: 0, y: 0, width: 420, height: 260)
sectionedCollectionView.layoutSubtreeIfNeeded()
drainMainQueue()
let nativeSectionedCollection = firstCollectionView(in: sectionedCollectionView)
require(nativeSectionedCollection?.numberOfSections == 2, "sectioned collection mounts every snapshot section")
require(nativeSectionedCollection?.numberOfItems(inSection: 0) == 3, "sectioned collection mounts items in their declared section")
require(nativeSectionedCollection?.selectionIndexPaths.count == 2, "sectioned collection applies stable multi-selection")
let sectionedFlowLayout = nativeSectionedCollection?.collectionViewLayout as? NSCollectionViewFlowLayout
require(sectionedFlowLayout?.headerReferenceSize.height == 34, "sectioned collection reserves native supplementary header space")
require((sectionedFlowLayout?.itemSize.width ?? 0) >= 120, "adaptive grid resolves a usable native item width")

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
let nestedMenuItem = FluentMenuItem.submenu("More") {
    FluentMenuItem("Rename") { nestedMenuInvocations += 1 }
    FluentMenuItem("Manage access") {}
}
require(nestedMenuItem.hasSubmenu && nestedMenuItem.submenu.count == 2, "menu model preserves nested declarative items")
let menuFlyout = FluentMenuFlyout(items: [
    FluentMenuItem("Open") {},
    nestedMenuItem,
    .separator,
    FluentMenuItem("Checked", state: .on) {},
    FluentMenuItem("Zebra") {},
    FluentMenuItem("Disabled", isEnabled: false) {}
], reduceMotion: false)
menuFlyout.present(relativeTo: menuFlyoutAnchor)
require(menuFlyout.isPresented, "application menu flyout presents its custom panel")
require(menuFlyoutWindow.childWindows?.count == 1, "application menu flyout attaches its panel to the owning window")
let rootMenuPanel = menuFlyoutWindow.childWindows?.first
let rootMenuReveal = rootMenuPanel?.contentView?.layer?.mask?
    .animation(forKey: "fluent.menu.reveal") as? CABasicAnimation
let rootRevealStart = (rootMenuReveal?.fromValue as? NSValue)?.rectValue.height
let rootRevealEnd = (rootMenuReveal?.toValue as? NSValue)?.rectValue.height
require(
    rootMenuReveal?.keyPath == "bounds"
        && abs((rootMenuReveal?.duration ?? 0) - FluentMotion.menuOpen.duration) < 0.0001
        && rootRevealStart.map { abs($0 - (rootRevealEnd ?? 0) * 0.5) < 0.001 } == true,
    "root MenuFlyout reveals from 50% height over the source-derived 250ms motion"
)
let rootMenuPresenter = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityRole: .menu, in: $0) }
require(rootMenuPresenter?.accessibilityChildren()?.count == 5, "menu accessibility tree excludes separators and includes every actionable row")
let moreMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "More", in: $0) }
let checkedMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Checked", in: $0) }
let disabledMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Disabled", in: $0) }
require(moreMenuRow?.accessibilityRole() == .menuItem, "submenu row exposes the native menu-item role")
require(moreMenuRow?.accessibilityValue() as? String == "Submenu", "submenu row announces its expandable state")
require(moreMenuRow?.accessibilityHelp() == "Opens a submenu", "submenu row exposes an accessibility hint")
require(checkedMenuRow?.accessibilityValue() as? String == "Selected", "checked menu row exposes its selected state")
require(disabledMenuRow?.isAccessibilityEnabled() == false, "disabled menu row exposes disabled semantics")
if let typeaheadEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6) {
    rootMenuPresenter?.keyDown(with: typeaheadEvent)
}
let zebraMenuRow = rootMenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Zebra", in: $0) }
require(zebraMenuRow?.isAccessibilitySelected() == true, "menu type-ahead selects the first enabled title prefix")
if let hoverEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0), let moreMenuRow {
    moreMenuRow.mouseEntered(with: hoverEvent)
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.10))
require(rootMenuPanel?.childWindows?.isEmpty != false, "submenu hover waits for the presentation delay")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
require(rootMenuPanel?.childWindows?.count == 1, "submenu opens after the Fluent hover delay")
let submenuPanel = rootMenuPanel?.childWindows?.first
let submenuReveal = submenuPanel?.contentView?.layer?.mask?
    .animation(forKey: "fluent.menu.reveal") as? CABasicAnimation
let submenuRevealStart = (submenuReveal?.fromValue as? NSValue)?.rectValue.height
let submenuRevealEnd = (submenuReveal?.toValue as? NSValue)?.rectValue.height
require(
    submenuReveal?.keyPath == "bounds"
        && abs((submenuReveal?.duration ?? 0) - FluentMotion.submenuOpen.duration) < 0.0001
        && submenuRevealStart.map { abs($0 - (submenuRevealEnd ?? 0) * 0.33) < 0.001 } == true,
    "submenu reveals from 33% height over the source-derived 250ms motion"
)
let submenuPresenter = submenuPanel?.contentView.flatMap { firstView(withAccessibilityRole: .menu, in: $0) }
require(submenuPresenter?.accessibilityChildren()?.count == 2, "submenu exposes its own menu accessibility tree")
let renameMenuRow = submenuPanel?.contentView.flatMap { firstView(withAccessibilityTitle: "Rename", in: $0) }
require(renameMenuRow?.accessibilityPerformPress() == true, "submenu item supports the accessibility press action")
require(nestedMenuInvocations == 1, "submenu action invokes its declarative closure exactly once")
let menuCloseAnimation = rootMenuPanel?.contentView?.layer?
    .animation(forKey: "fluent.menu.close") as? CABasicAnimation
require(
    menuCloseAnimation?.keyPath == "opacity"
        && abs((menuCloseAnimation?.duration ?? 0) - FluentMotion.menuClose.duration) < 0.0001,
    "MenuFlyout closes with the source-derived 83ms linear opacity motion"
)
menuFlyout.dismiss(animated: false)
require(menuFlyoutWindow.childWindows?.isEmpty != false, "dismissing a menu removes its complete submenu hierarchy")

menuFlyoutAnchor.userInterfaceLayoutDirection = .rightToLeft
let rtlMenuFlyout = FluentMenuFlyout(items: [nestedMenuItem])
rtlMenuFlyout.present(relativeTo: menuFlyoutAnchor)
let rtlAnchorRect = menuFlyoutWindow.convertToScreen(menuFlyoutAnchor.convert(menuFlyoutAnchor.bounds, to: nil))
if let rtlPanel = menuFlyoutWindow.childWindows?.first {
    require(abs(rtlPanel.frame.maxX - rtlAnchorRect.maxX) < 2, "RTL root menu aligns its trailing edge to the anchor")
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
    reducedMenuPanel?.contentView?.layer?.mask == nil,
    "MenuFlyout Reduce Motion reaches final reveal geometry without a mask animation"
)
reducedMenuFlyout.dismiss(animated: true)
require(
    menuFlyoutWindow.childWindows?.isEmpty != false,
    "MenuFlyout Reduce Motion dismisses without allocating close motion"
)
menuFlyoutWindow.orderOut(nil)

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
require(teachingTipWindow.childWindows?.count == 1, "teaching tip presents an application-owned child panel")
require(
    teachingTipWindow.childWindows?.first?.contentView?.accessibilityLabel() == "Teaching tip",
    "teaching tip exposes a semantic presentation group"
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

let expanded = FluentState(wrappedValue: true)
let disclosure = FluentDisclosureGroup("Advanced", isExpanded: expanded.projectedValue) {
    FluentText("Advanced content")
}
let disclosureView = disclosure._mount(in: FluentRenderContext())
require(disclosureView.subviews.count == 1, "disclosure group mounts a native host")
require(expanded.wrappedValue, "disclosure binding starts expanded")

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
require(mainMenuCoordinator.menu.items.count == 3, "main menu contains app item and declarative command groups")
let fileMenu = mainMenuCoordinator.menu.items[1].submenu
require(fileMenu?.title == "File", "main menu preserves command group title")
require(fileMenu?.items.count == 1, "main menu renders one item per command")
let exportItem = fileMenu?.items.first
require(exportItem?.keyEquivalent == "e", "main menu preserves command key equivalent")
require(exportItem?.keyEquivalentModifierMask == [.command, .shift], "main menu preserves command modifiers")
require(exportItem.map(mainMenuCoordinator.perform) == true, "main menu performs an enabled command")
require(appCommandInvocations == 1, "main menu invokes the declarative action")
appCommandEnabled = false
mainMenuCoordinator.menuNeedsUpdate(mainMenuCoordinator.menu)
require(exportItem?.isEnabled == false, "main menu refreshes dynamic enabled state")
require(exportItem.map(mainMenuCoordinator.perform) == false, "main menu refuses to perform a disabled command")
mainMenuCoordinator.update(groups: [])
require(mainMenuCoordinator.menu.items.count == 1, "main menu update removes stale declarative groups")

let pickedDate = FluentState(wrappedValue: Date(timeIntervalSince1970: 1_700_000_000))
let datePicker = FluentDatePicker(selection: pickedDate.projectedValue)
let styledDatePicker = datePicker.textFieldStyle(ValidationTextFieldStyle())
let dateView = styledDatePicker._mount(in: FluentRenderContext())
require(dateView is NSDatePicker, "date picker mounts native AppKit control")
require((dateView as? NSDatePicker)?.dateValue == pickedDate.wrappedValue, "date picker reads selection binding")
require((dateView as? NSDatePicker)?.font?.pointSize == 17, "date picker receives the shared semantic field font")

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
let navigationViewSelection = FluentState<String?>(wrappedValue: "home")
let navigationViewPaneOpen = FluentState(wrappedValue: true)
let reusableNavigation = FluentNavigationView(
    navigationViewItems,
    footerItems: navigationViewFooterItems,
    selection: navigationViewSelection.projectedValue,
    isPaneOpen: navigationViewPaneOpen.projectedValue,
    paneDisplayMode: .left,
    openPaneLength: 280,
    paneSectionTitle: "Explore"
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
let reusableToggle = firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: reusableNavigationHost) as? NSButton
let reusableIndicator = firstLayer(named: "FluentKit.NavigationView.SelectionIndicator", in: reusableNavigationHost)
let reusablePreviousIndicator = firstLayer(named: "FluentKit.NavigationView.PreviousSelectionIndicator", in: reusableNavigationHost)
require(
    abs((reusablePane?.frame.width ?? 0) - 280) < 0.5
        && abs((reusableContent?.frame.minX ?? 0) - 280) < 0.5,
    "NavigationView left mode reserves the configured open pane length"
)
require(
    reusableIndicator?.frame.size == NSSize(width: 3, height: 16)
        && reusablePreviousIndicator?.opacity == 0,
    "NavigationView exposes the shared vertical two-indicator geometry"
)
require(
    views(identifier: "FluentKit.NavigationView.Item", in: reusableNavigationHost).count == 4,
    "NavigationView mounts primary and footer items through one presenter"
)
navigationViewSelection.wrappedValue = "settings"
drainMainQueue()
let footerIncoming = reusableIndicator?.animation(forKey: "fluent.navigation.selection") as? CAAnimationGroup
let footerOutgoing = reusablePreviousIndicator?.animation(forKey: "fluent.navigation.selection.outgoing") as? CAAnimationGroup
require(
    footerIncoming != nil && footerOutgoing != nil,
    "NavigationView animates one shared indicator between primary and footer destinations"
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
reusableToggle?.performClick(nil)
drainMainQueue()
require(
    navigationViewPaneOpen.wrappedValue == false
        && abs((reusablePane?.frame.width ?? 0) - 48) < 0.5
        && abs((reusableContent?.frame.minX ?? 0) - 48) < 0.5,
    "NavigationView left mode closes to the 48pt compact rail"
)
require(
    reusablePane?.layer?.animation(forKey: "fluent.navigation.pane.frame") != nil,
    "NavigationView pane close uses explicit completion-trackable frame motion"
)
require(
    reusablePane.flatMap { pane in labels(in: pane).first { $0.stringValue == "Explore" } }?.isHidden == true,
    "NavigationView hides section text before compact-pane motion can clip or jump it"
)
reusableToggle?.performClick(nil)
drainMainQueue()
require(
    navigationViewPaneOpen.wrappedValue == true && abs((reusablePane?.frame.width ?? 0) - 280) < 0.5,
    "rapid NavigationView pane reversal settles on the latest requested state"
)

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
require(
    automaticDisplayModes.last == .compact
        && automaticPaneOpen.wrappedValue == false
        && abs((automaticPane?.frame.width ?? 0) - 48) < 0.5,
    "NavigationView Auto resolves 800pt to closed Compact mode"
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
require(
    keyframeAnimation(for: "transform.scale.x", in: topIndicatorGroup) != nil,
    "Top NavigationView uses horizontal two-indicator scaling"
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
    paneDisplayMode: .leftCompact
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
(firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: reducedNavigationViewHost) as? NSButton)?.performClick(nil)
drainMainQueue()
require(
    reducedPaneOpen.wrappedValue == true
        && reducedPane?.layer?.animation(forKey: "fluent.navigation.pane.frame") == nil,
    "NavigationView Reduce Motion snaps pane geometry without allocating frame animation"
)

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
var titleBarPaneInvocations = 0
let compactTitleBar = FluentTitleBar(
    title: "Workspace",
    subtitle: "Compact",
    heightMode: .compact,
    isBackButtonVisible: true,
    isBackButtonEnabled: true,
    isPaneToggleButtonVisible: true,
    isPaneOpen: titleBarPaneOpen.projectedValue,
    onBack: { titleBarBackInvocations += 1 },
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
titleBarPaneButton?.performClick(nil)
drainMainQueue()
require(titleBarBackInvocations == 1, "TitleBar back button routes its declarative action")
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

let navigation = FluentNavigationStack(
    path: navigationPath.projectedValue,
    root: { FluentText("Root screen") },
    title: { String(describing: $0) },
    destination: { route in FluentAnyView(FluentText("Route: \(route)")) }
)
let navigationView = navigation._mount(in: FluentRenderContext())
require(navigationView.subviews.count == 1, "navigation stack mounts a native host")
navigationPath.wrappedValue = [AnyHashable("detail")]
drainMainQueue()
require(navigationPath.wrappedValue == [AnyHashable("detail")], "navigation path binding accepts pushed routes")

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
require(abs(FluentMotion.controlFaster.duration - 0.083) < 0.0001, "control-faster motion preserves its exact duration")
require(abs(FluentMotion.controlFast.duration - 0.167) < 0.0001, "control-fast motion preserves its exact duration")
require(abs(FluentMotion.controlNormal.duration - 0.250) < 0.0001, "control-normal motion preserves its exact duration")
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
require(
    abs(FluentMotion.menuClose.duration - 0.083) < 0.0001
        && FluentMotion.menuClose.curve == .linear,
    "menu-close motion preserves its 83ms linear fade"
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
animatedScalar.set(1, animation: FluentAnimationTransaction(duration: 0.06, curve: .linear), reduceMotion: false) {
    scalarAnimationCompleted = true
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035))
require(animatedScalar.isAnimating, "animated value reports an active display-driven animation")
require(animatedScalar.value > 0 && animatedScalar.value < 1, "animated value publishes intermediate samples")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
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
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.07))
require(firstLabel(in: trackedAnimatedHost)?.stringValue == "Animated: 100", "animated values participate in declarative dependency tracking")

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
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035))
require(springValue.isAnimating && springValue.value != 0, "spring animation publishes a moving value")
springValue.finish()
require(abs(springValue.value - 1) < 0.0001 && springCompleted, "finishing a spring writes its exact target and completion")
let overshootingSpringValue = FluentAnimatedValue<CGFloat>(0)
var overshootingSpringSamples: [CGFloat] = []
let overshootingSpringObserver = overshootingSpringValue.observable.observe(
    { overshootingSpringSamples.append($0) },
    notifyImmediately: false
)
overshootingSpringValue.set(1, spring: FluentSpringAnimation(stiffness: 240, damping: 4), reduceMotion: false)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
overshootingSpringValue.stop()
overshootingSpringValue.observable.removeObserver(overshootingSpringObserver)
require(overshootingSpringSamples.contains { $0 > 1.01 }, "underdamped springs publish overshooting value samples")

let reducedKeyframeValue = FluentAnimatedValue<CGFloat>(0)
var reducedKeyframesCompleted = false
reducedKeyframeValue.animate(using: keyframeTimeline, reduceMotion: true) { reducedKeyframesCompleted = true }
require(abs(reducedKeyframeValue.value - 0.25) < 0.0001, "reduced motion resolves keyframes to their final value immediately")
require(!reducedKeyframeValue.isAnimating && reducedKeyframesCompleted, "reduced keyframes complete without allocating a timer")

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
                animation: FluentAnimationTransaction(duration: 0.06, curve: .easeOut)
            )
    }
}
let transitionHost = FluentViewHost(TransitionProbe(flag: transitionFlag))
let nativeTransitionContainer = transitionHost.subviews.first
transitionFlag.value = false
drainMainQueue()
require(transitionHost.subviews.count == 1, "transition wrapper keeps a stable host during branch replacement")
require(transitionHost.subviews.first === nativeTransitionContainer, "composed transitions preserve their native host identity")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
require(nativeTransitionContainer?.subviews.count == 1, "transition completion removes the outgoing native entry")
let contentTransformPreserved = abs(
    (nativeTransitionContainer?.subviews.first?.subviews.first?.layer?.affineTransform().tx ?? 0) - 7
) < 0.0001
require(contentTransformPreserved, "transition entry animation does not overwrite a content transform")

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
    ("inputs-light.png", 980, 680),
    ("inputs-dark.png", 980, 680),
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
