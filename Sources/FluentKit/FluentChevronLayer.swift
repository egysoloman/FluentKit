import AppKit

enum FluentChevronDirection: Hashable, Sendable {
    case left
    case right
    case up
    case down
}

/// Semantic WinUI chevron families. Callers choose the visual role instead of treating every
/// glyph as an interchangeable rotated symbol.
enum FluentChevronVisual: Hashable, Sendable {
    /// Expand/collapse glyph used by Settings and hierarchical navigation rows.
    case upDownSmall
    /// Fixed downward glyph used by closed ComboBox and DropDownButton triggers.
    case downSmall
    /// Directional glyph used by Back and NumberBox controls.
    case directional
}

/// Shared WinUI chevron geometry used by button-like controls. The layer keeps one canonical
/// down-facing path and uses the common animation coordinator for direction, press, and color
/// changes, so interrupted rotations and presses continue from their presentation value.
final class FluentChevronPrimitiveLayer: CAShapeLayer {
    private let animationCoordinator = FluentAnimationCoordinator()
    private var state: FluentControlState = .normal
    private var direction: FluentChevronDirection = .down
    private var visual: FluentChevronVisual = .directional

    override init() {
        super.init()
        fillColor = nil
        lineWidth = 1.35
        lineCap = .round
        lineJoin = .round
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        masksToBounds = false
        isGeometryFlipped = false
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        frame: CGRect,
        color: NSColor,
        state: FluentControlState,
        visual: FluentChevronVisual = .directional,
        direction: FluentChevronDirection = .down,
        backingScale: CGFloat? = nil,
        animated: Bool
    ) {
        let scale = max(backingScale ?? contentsScale, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(origin: .zero, size: frame.size)
        position = CGPoint(x: frame.midX, y: frame.midY)
        contentsScale = scale
        lineWidth = max(1 / scale, FluentPixelGeometry(backingScale: scale).align(1.35))
        path = chevronPath(in: bounds, scale: scale, visual: visual)
        CATransaction.commit()

        self.state = state
        self.visual = visual
        let resolvedDirection = visual == .downSmall ? FluentChevronDirection.down : direction
        self.direction = resolvedDirection
        let targetTransform = transform(for: resolvedDirection, pressed: state == .pressed)
        let motion = state == .pressed ? FluentMotion.controlFaster : FluentMotion.controlNormal
        let changes = [
            FluentLayerAnimationChange(
                layer: self,
                key: "fluent.chevron.press",
                keyPath: "transform",
                toValue: NSValue(caTransform3D: targetTransform)
            ) { [weak self] in self?.transform = targetTransform },
            FluentLayerAnimationChange(
                layer: self,
                key: "fluent.chevron.color",
                keyPath: "strokeColor",
                toValue: color.cgColor
            ) { [weak self] in self?.strokeColor = color.cgColor }
        ]
        animationCoordinator.animateState(changes, motion: motion, animated: animated)
    }

    private func transform(for direction: FluentChevronDirection, pressed: Bool) -> CATransform3D {
        let angle: CGFloat = switch direction {
        case .down: 0
        case .up: .pi
        case .right: -.pi / 2
        case .left: .pi / 2
        }
        let rotation = CATransform3DMakeRotation(angle, 0, 0, 1)
        guard pressed else { return rotation }
        return CATransform3DTranslate(rotation, 0, 1.875, 0)
    }

    private func chevronPath(
        in bounds: CGRect,
        scale: CGFloat,
        visual: FluentChevronVisual
    ) -> CGPath {
        let geometry = FluentPixelGeometry(backingScale: scale)
        let centerY = geometry.align(bounds.midY)
        let horizontalInset: CGFloat = visual == .downSmall ? 2.5 : 2.75
        let upperOffset: CGFloat = visual == .downSmall ? 1.5 : 1.75
        let lowerOffset: CGFloat = visual == .downSmall ? 2.2 : 2.0
        let path = CGMutablePath()
        path.move(to: CGPoint(
            x: geometry.align(bounds.minX + horizontalInset),
            y: geometry.align(centerY - upperOffset)
        ))
        path.addLine(to: CGPoint(
            x: geometry.align(bounds.midX),
            y: geometry.align(centerY + lowerOffset)
        ))
        path.addLine(to: CGPoint(
            x: geometry.align(bounds.maxX - horizontalInset),
            y: geometry.align(centerY - upperOffset)
        ))
        return path
    }
}

typealias FluentAnimatedChevronLayer = FluentChevronPrimitiveLayer
