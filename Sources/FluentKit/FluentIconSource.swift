import AppKit

public enum FluentIconTint: Sendable { case template, original }
public enum FluentIconAlignment: Sendable { case leading, center, trailing }

/// A shared icon source for controls and custom content. Paths use their own bounding box;
/// images keep their aspect ratio. Mirroring and tinting are explicit rather than font-specific.
public struct FluentIconSource {
    private enum Storage {
        case symbol(String)
        case image(NSImage)
        case glyph(String, NSFont)
        case path(CGPath)
    }
    private let storage: Storage
    public var tint: FluentIconTint
    public var alignment: FluentIconAlignment = .center
    public var mirrorsInRightToLeft = false

    public static func systemSymbol(_ name: String) -> Self { Self(storage: .symbol(name), tint: .template) }
    public static func image(_ image: NSImage, tint: FluentIconTint = .original) -> Self {
        Self(storage: .image(image), tint: tint)
    }
    public static func glyph(_ text: String, font: NSFont) -> Self { Self(storage: .glyph(text, font), tint: .template) }
    public static func path(_ path: CGPath) -> Self { Self(storage: .path(path.copy()!), tint: .template) }

    public func image(pointSize: CGFloat, color: NSColor = .labelColor,
                      layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight) -> NSImage? {
        let source: NSImage
        switch storage {
        case let .symbol(name):
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            source = symbol.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)) ?? symbol
        case let .image(image): source = image
        case let .glyph(text, font):
            let attributes: [NSAttributedString.Key: Any] = [.font: font.withSize(pointSize), .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attributes)
            guard size.width > 0, size.height > 0 else { return nil }
            source = NSImage(size: size, flipped: false) { rect in
                (text as NSString).draw(in: rect, withAttributes: attributes)
                return true
            }
        case let .path(path):
            let box = path.boundingBoxOfPath
            guard box.width > 0, box.height > 0 else { return nil }
            source = NSImage(size: box.size, flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.translateBy(x: -box.minX, y: -box.minY)
                context.addPath(path)
                context.setFillColor(NSColor.white.cgColor)
                context.fillPath()
                return true
            }
        }
        guard source.size.width > 0, source.size.height > 0 else { return nil }
        let mirror = mirrorsInRightToLeft && layoutDirection == .rightToLeft
        let template = tint == .template
        return NSImage(size: source.size, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            if mirror {
                let transform = AffineTransform(translationByX: rect.width, byY: 0)
                var reflected = transform
                reflected.scale(x: -1, y: 1)
                (reflected as NSAffineTransform).concat()
            }
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            if template {
                color.setFill()
                rect.fill(using: .sourceIn)
            }
            return true
        }
    }

    public func draw(in rect: NSRect, color: NSColor,
                     layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight) {
        guard let image = image(pointSize: min(rect.width, rect.height), color: color, layoutDirection: layoutDirection) else { return }
        let target = fittedRect(imageSize: image.size, in: rect, layoutDirection: layoutDirection)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    public func fittedRect(imageSize: NSSize, in rect: NSRect,
                           layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, rect.width > 0, rect.height > 0 else { return .zero }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let isLeading = alignment == .leading && layoutDirection != .rightToLeft
            || alignment == .trailing && layoutDirection == .rightToLeft
        let x = alignment == .center ? rect.midX - size.width / 2 : (isLeading ? rect.minX : rect.maxX - size.width)
        return NSRect(x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
