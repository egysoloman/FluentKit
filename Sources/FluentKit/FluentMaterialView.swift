import AppKit

public final class FluentMaterialView: NSVisualEffectView {
    public var materialStyle: FluentMaterial {
        didSet { applyMaterial() }
    }

    public var tintColor: NSColor? {
        didSet { tintLayer.backgroundColor = tintColor?.cgColor }
    }

    private let tintLayer = CALayer()

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public init(material: FluentMaterial = .mica) {
        self.materialStyle = material
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        layer?.addSublayer(tintLayer)
        applyMaterial()
    }

    public override init(frame frameRect: NSRect) {
        self.materialStyle = .mica
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        layer?.addSublayer(tintLayer)
        applyMaterial()
    }

    required init?(coder: NSCoder) {
        self.materialStyle = .mica
        super.init(coder: coder)
        wantsLayer = true
        layer?.addSublayer(tintLayer)
        applyMaterial()
    }

    public override func layout() {
        super.layout()
        tintLayer.frame = bounds
    }

    private func applyMaterial() {
        blendingMode = switch materialStyle {
        case .mica, .sidebar: .withinWindow
        case .acrylic: .behindWindow
        }
        material = switch materialStyle {
        case .mica: .underWindowBackground
        case .acrylic: .hudWindow
        case .sidebar: .sidebar
        }
        state = .active
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyMaterial()
        needsDisplay = true
    }
}
