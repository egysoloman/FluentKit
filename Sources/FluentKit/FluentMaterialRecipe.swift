import AppKit
import CoreImage

struct FluentMaterialRecipe: Equatable {
    let color: NSColor
    let tintOpacity: CGFloat
    let luminosityOpacity: CGFloat
    let noiseOpacity: Float

    init(material: FluentMaterial, dark: Bool, tint: NSColor?,
         tintOpacity: CGFloat?, luminosityOpacity: CGFloat?) {
        let mica = material == .mica
        // WinUI MicaController and AcrylicInAppFillColorDefaultBrush. macOS supplies
        // the blur source; the two blend stages retain their WinUI meanings.
        // Also cross-checked against WinUIEssentials InAppAcrylicVisual and TenMicaConstants
        // (MIT; see LICENSES/WinUIEssentials.txt).
        let value: CGFloat = mica ? (dark ? 32 : 243) : (dark ? 44 : 252)
        color = tint ?? NSColor(srgbRed: value / 255, green: value / 255, blue: value / 255, alpha: 1)
        self.tintOpacity = Self.opacity(tintOpacity, fallback: mica ? (dark ? 0.8 : 0.5) : (dark ? 0.15 : 0))
        self.luminosityOpacity = Self.opacity(luminosityOpacity, fallback: mica ? 1 : (dark ? 0.96 : 0.85))
        noiseOpacity = mica ? 0 : 0.02
    }

    private static func opacity(_ value: CGFloat?, fallback: CGFloat) -> CGFloat {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, 0), 1)
    }
}

/// Stable one-device-pixel grain, tiled rather than stretched as the surface resizes.
final class FluentMaterialNoiseLayer: CALayer {
    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    private static let tile: CGImage? = {
        var state: UInt32 = 0x9e3779b9
        let bytes: [UInt8] = (0..<4096).map { _ in
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return UInt8(truncatingIfNeeded: state)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()

    override func draw(in context: CGContext) {
        guard let image = Self.tile, let colorSpace = CGColorSpace(patternBaseSpace: nil) else { return }
        let info = Unmanaged.passRetained(image).toOpaque()
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { info, context in
            guard let info else { return }
            context.draw(Unmanaged<CGImage>.fromOpaque(info).takeUnretainedValue(),
                         in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }, releaseInfo: { info in
            if let info { Unmanaged<CGImage>.fromOpaque(info).release() }
        })
        let scale = 1 / max(contentsScale, 1)
        guard let pattern = CGPattern(info: info, bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            matrix: CGAffineTransform(scaleX: scale, y: scale), xStep: 64, yStep: 64,
            tiling: .noDistortion, isColored: true, callbacks: &callbacks) else {
            Unmanaged<CGImage>.fromOpaque(info).release()
            return
        }
        context.setFillColorSpace(colorSpace)
        var alpha: CGFloat = 1
        context.setFillPattern(pattern, colorComponents: &alpha)
        context.fill(bounds)
    }
}
