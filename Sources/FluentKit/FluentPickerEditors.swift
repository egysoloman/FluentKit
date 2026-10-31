import AppKit

/// A WinUI ColorSpectrum-style hue/saturation surface. Brightness is controlled by the adjacent
/// third-dimension slider, matching the source ColorPicker template structure.
final class FluentColorSpectrumView: NSView {
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.55
            needsDisplay = true
        }
    }
    var color: NSColor = .white {
        didSet {
            guard color != oldValue else { return }
            needsDisplay = true
        }
    }
    var onSelect: ((NSColor) -> Void)?

    private var spectrumImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if spectrumImage == nil || spectrumImage?.size != bounds.size {
            spectrumImage = makeSpectrumImage(size: bounds.size)
        }
        spectrumImage?.draw(in: bounds)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if color.usingColorSpace(.sRGB)?.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) == nil {
            (hue, saturation, brightness, alpha) = (0, 0, 0, 1)
        }
        let point = CGPoint(x: hue * bounds.width, y: saturation * bounds.height)
        let indicator = NSBezierPath(
            ovalIn: NSRect(
                x: point.x - 7,
                y: point.y - 7,
                width: 14,
                height: 14
            )
        )
        NSColor.white.setStroke()
        indicator.lineWidth = 3
        indicator.stroke()
        NSColor.black.withAlphaComponent(0.4).setStroke()
        indicator.lineWidth = 1
        indicator.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        select(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        select(at: convert(event.locationInWindow, from: nil))
    }

    private func select(at point: NSPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let hue = min(max(point.x / bounds.width, 0), 1)
        let saturation = min(max(point.y / bounds.height, 0), 1)
        // The two-dimensional surface edits hue and saturation only. Preserve the third
        // dimension instead of silently forcing brightness to 100% on every pointer sample.
        let brightness = color.hsbComponents.brightness
        color = NSColor(
            calibratedHue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: 1
        )
        onSelect?(color)
        needsDisplay = true
    }

    private func makeSpectrumImage(size: NSSize) -> NSImage? {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else { return nil }
        guard let pixels = representation.bitmapData else { return nil }
        for y in 0..<height {
            let saturation = height == 1 ? 1 : CGFloat(y) / CGFloat(height - 1)
            for x in 0..<width {
                let hue = width == 1 ? 1 : CGFloat(x) / CGFloat(width - 1)
                let color = NSColor(calibratedHue: hue, saturation: saturation, brightness: 1, alpha: 1)
                    .usingColorSpace(.deviceRGB) ?? NSColor.white
                let offset = y * width * 4 + x * 4
                pixels[offset] = UInt8(color.redComponent * 255)
                pixels[offset + 1] = UInt8(color.greenComponent * 255)
                pixels[offset + 2] = UInt8(color.blueComponent * 255)
                pixels[offset + 3] = 255
            }
        }
        return NSImage(size: size, flipped: false) { rect in
            representation.draw(in: rect)
            return true
        }
    }
}

/// The WinUI ColorPicker layout: spectrum, third-dimension (brightness) slider, hue and
/// saturation sliders, and a preview rectangle. All interactive parts are Fluent controls.
final class FluentWinUIColorPickerEditorView: NSControl {
    var theme: FluentTheme {
        didSet {
            guard oldValue != theme else { return }
            spectrum.layer?.borderColor = theme.controlStroke.cgColor
            preview.layer?.borderColor = theme.controlStroke.cgColor
            for slider in sliders { slider.theme = theme }
            for label in labels { label.textColor = theme.textSecondary }
        }
    }

    var onChange: (NSColor) -> Void
    private var pendingColor: NSColor
    private let spectrum: FluentColorSpectrumView
    private let preview = NSView()
    private let hueSlider: FluentSlider
    private let saturationSlider: FluentSlider
    private let brightnessSlider: FluentSlider
    private var sliders: [FluentSlider] { [hueSlider, saturationSlider, brightnessSlider] }
    private var labels: [NSTextField] = []
    private var isSyncing = false

    init(
        color: NSColor,
        theme: FluentTheme,
        onChange: @escaping (NSColor) -> Void
    ) {
        pendingColor = color
        self.theme = theme
        self.onChange = onChange
        spectrum = FluentColorSpectrumView(frame: .zero)
        let components = color.hsbComponents
        hueSlider = FluentSlider(value: Double(components.hue * 360), range: 0...360)
        saturationSlider = FluentSlider(value: Double(components.saturation * 100), range: 0...100)
        brightnessSlider = FluentSlider(value: Double(components.brightness * 100), range: 0...100)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Editor")
        spectrum.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Spectrum")
        preview.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Preview")

        spectrum.color = color
        spectrum.layer?.borderColor = theme.controlStroke.cgColor
        spectrum.onSelect = { [weak self] newColor in
            guard let self else { return }
            self.isSyncing = true
            self.pendingColor = newColor
            self.hueSlider.value = Double(newColor.hsbComponents.hue * 360)
            self.saturationSlider.value = Double(newColor.hsbComponents.saturation * 100)
            self.isSyncing = false
            self.preview.layer?.backgroundColor = newColor.cgColor
            self.onChange(newColor)
        }
        addSubview(spectrum)

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 5
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = theme.controlStroke.cgColor
        preview.layer?.backgroundColor = pendingColor.cgColor
        addSubview(preview)

        let titles = ["Hue", "Saturation", "Brightness"]
        for (index, slider) in sliders.enumerated() {
            slider.theme = theme
            slider.onValueChanged = { [weak self] _ in self?.emitColor() }
            slider.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Slider.\(index)")
            addSubview(slider)
            let label = NSTextField(labelWithString: titles[index])
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = theme.textSecondary
            addSubview(label)
            labels.append(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet {
            spectrum.isEnabled = isEnabled
            for slider in sliders { slider.isEnabled = isEnabled }
            preview.alphaValue = isEnabled ? 1 : 0.55
            for label in labels {
                label.textColor = isEnabled ? theme.textSecondary : theme.textDisabled
            }
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 350) }

    override func layout() {
        super.layout()
        let topMargin: CGFloat = 6
        let previewHeight: CGFloat = 26
        let previewGap: CGFloat = 10
        let labelWidth: CGFloat = 74
        let sliderHeight: CGFloat = 30
        let sliderSpacing: CGFloat = 4
        let spectrumGap: CGFloat = 12

        preview.frame = NSRect(
            x: 0,
            y: bounds.maxY - topMargin - previewHeight,
            width: bounds.width,
            height: previewHeight
        )

        // AppKit's native coordinate system grows upward. Arrange the rows bottom-up so Hue is
        // visually closest to the spectrum while Brightness stays at the bottom; this also keeps
        // every label outside the spectrum for arbitrarily constrained heights.
        for (index, slider) in sliders.enumerated() {
            let y = CGFloat(sliders.count - index - 1) * (sliderHeight + sliderSpacing)
            labels[index].frame = NSRect(x: 0, y: y + 4, width: labelWidth, height: 20)
            slider.frame = NSRect(
                x: labelWidth,
                y: y,
                width: max(0, bounds.width - labelWidth),
                height: sliderHeight
            )
        }
        let sliderStackHeight = CGFloat(sliders.count) * sliderHeight
            + CGFloat(max(sliders.count - 1, 0)) * sliderSpacing
        let spectrumY = sliderStackHeight + spectrumGap
        let spectrumTop = preview.frame.minY - previewGap
        spectrum.frame = NSRect(
            x: 0,
            y: spectrumY,
            width: bounds.width,
            height: max(0, spectrumTop - spectrumY)
        )
    }

    func updateColor(_ color: NSColor) {
        // Declarative binding updates are model synchronization, not user input. Writing through
        // `value` here used to invoke each slider's callback, write the color binding again, and
        // schedule another render indefinitely while dragging. Suppress callbacks and preserve an
        // active drag while bringing all three controls up to date.
        isSyncing = true
        defer { isSyncing = false }
        pendingColor = color
        spectrum.color = color
        preview.layer?.backgroundColor = color.cgColor
        let components = color.hsbComponents
        hueSlider.setValueFromBinding(Double(components.hue * 360), cancelInteraction: false)
        saturationSlider.setValueFromBinding(Double(components.saturation * 100), cancelInteraction: false)
        brightnessSlider.setValueFromBinding(Double(components.brightness * 100), cancelInteraction: false)
    }

    func update(color: NSColor, theme: FluentTheme, onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
        self.theme = theme
        updateColor(color)
    }

    private func emitColor() {
        guard !isSyncing else { return }
        let hue = CGFloat(hueSlider.value / 360)
        let saturation = CGFloat(saturationSlider.value / 100)
        let brightness = CGFloat(brightnessSlider.value / 100)
        let color = NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        pendingColor = color
        spectrum.color = color
        preview.layer?.backgroundColor = color.cgColor
        onChange(color)
    }
}

/// A custom Fluent color editor using three FluentSliders and a small palette. It replaces the
/// system NSColorPanel that NSColorWell would otherwise activate.
final class FluentColorPickerEditorView: NSView {
    var theme: FluentTheme {
        didSet {
            guard oldValue != theme else { return }
            for slider in sliders { slider.theme = theme }
            for label in labels { label.textColor = theme.textSecondary }
            preview.layer?.borderColor = theme.controlStroke.cgColor
            needsDisplay = true
        }
    }

    let onChange: (NSColor) -> Void
    private var pendingColor: NSColor
    private let preview = NSView()
    private let redSlider: FluentSlider
    private let greenSlider: FluentSlider
    private let blueSlider: FluentSlider
    private var sliders: [FluentSlider] { [redSlider, greenSlider, blueSlider] }
    private var labels: [NSTextField] = []
    private var swatches: [FluentColorSwatchButton] = []

    init(
        color: NSColor,
        theme: FluentTheme,
        onChange: @escaping (NSColor) -> Void
    ) {
        pendingColor = color
        self.theme = theme
        self.onChange = onChange
        let rgb = color.rgbComponents
        redSlider = FluentSlider(value: Double(rgb.red * 255), range: 0...255)
        greenSlider = FluentSlider(value: Double(rgb.green * 255), range: 0...255)
        blueSlider = FluentSlider(value: Double(rgb.blue * 255), range: 0...255)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Editor")

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 5
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = theme.controlStroke.cgColor
        preview.layer?.backgroundColor = pendingColor.cgColor
        addSubview(preview)

        let titles = ["R", "G", "B"]
        for (index, slider) in sliders.enumerated() {
            slider.theme = theme
            slider.minimumValue = 0
            slider.maximumValue = 255
            slider.onValueChanged = { [weak self] _ in self?.emitColor() }
            slider.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Slider.\(index)")
            addSubview(slider)
            let label = NSTextField(labelWithString: titles[index])
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = theme.textSecondary
            addSubview(label)
            labels.append(label)
        }

        let palette: [NSColor] = [
            .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal,
            .systemBlue, .systemPurple, .systemPink, .systemGray, .white
        ]
        for (index, paletteColor) in palette.enumerated() {
            let swatch = FluentColorSwatchButton(color: paletteColor)
            swatch.identifier = NSUserInterfaceItemIdentifier("FluentKit.ColorPicker.Swatch.\(index)")
            swatch.onClick = { [weak self] in
                self?.updateColor(paletteColor)
            }
            addSubview(swatch)
            swatches.append(swatch)
        }
        updateSliders()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 280, height: 176) }

    override func layout() {
        super.layout()
        preview.frame = NSRect(x: 0, y: bounds.maxY - 36, width: bounds.width, height: 30)
        let sliderHeight: CGFloat = 28
        let labelWidth: CGFloat = 18
        for (index, slider) in sliders.enumerated() {
            let y = bounds.maxY - 44 - CGFloat(index) * (sliderHeight + 4)
            labels[index].frame = NSRect(x: 0, y: y + 5, width: labelWidth, height: 18)
            slider.frame = NSRect(
                x: labelWidth,
                y: y,
                width: max(0, bounds.width - labelWidth),
                height: sliderHeight
            )
        }
        let swatchTop = bounds.maxY - 44 - 3 * 32 - 10
        let swatchSize: CGFloat = 24
        let swatchSpacing: CGFloat = 6
        for (index, swatch) in swatches.enumerated() {
            let column = index % 5
            let row = index / 5
            swatch.frame = NSRect(
                x: CGFloat(column) * (swatchSize + swatchSpacing),
                y: swatchTop - CGFloat(row) * (swatchSize + swatchSpacing),
                width: swatchSize,
                height: swatchSize
            )
        }
    }

    func updateColor(_ color: NSColor) {
        pendingColor = color
        preview.layer?.backgroundColor = color.cgColor
        updateSliders()
        onChange(color)
    }

    private func emitColor() {
        let red = CGFloat(redSlider.value / 255)
        let green = CGFloat(greenSlider.value / 255)
        let blue = CGFloat(blueSlider.value / 255)
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        pendingColor = color
        preview.layer?.backgroundColor = color.cgColor
        onChange(color)
    }

    private func updateSliders() {
        let rgb = pendingColor.rgbComponents
        redSlider.value = Double(rgb.red * 255)
        greenSlider.value = Double(rgb.green * 255)
        blueSlider.value = Double(rgb.blue * 255)
    }
}

private final class FluentColorSwatchButton: NSButton {
    var onClick: (() -> Void)?

    init(color: NSColor) {
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = color.luminance > 0.5
            ? NSColor.black.withAlphaComponent(0.18).cgColor
            : NSColor.white.withAlphaComponent(0.24).cgColor
        layer?.backgroundColor = color.cgColor
        target = self
        action = #selector(invoke)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invoke() { onClick?() }
}

private extension NSColor {
    var rgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let resolved = usingColorSpace(.sRGB) ?? self
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
    }

    var hsbComponents: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let resolved = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        return (hue, saturation, brightness)
    }

    var luminance: CGFloat {
        let rgb = rgbComponents
        return 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
    }
}
