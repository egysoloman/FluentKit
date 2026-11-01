import AppKit
import CoreImage
import ImageIO

/// Maps a desktop image into display points before downsampling. Display origins are deliberately
/// absent: a monitor move changes sampling coordinates, not the cached wallpaper pixels.
struct FluentWallpaperGeometry {
    static func imageRect(imagePixels: CGSize, displaySize: CGSize, backingScale: CGFloat,
                          scaling: NSImageScaling, allowClipping: Bool) -> CGRect {
        guard imagePixels.width > 0, imagePixels.height > 0 else { return .zero }
        let imageSize = CGSize(width: imagePixels.width / max(backingScale, 1),
                               height: imagePixels.height / max(backingScale, 1))
        let factor: CGFloat
        switch scaling {
        case .scaleAxesIndependently: return CGRect(origin: .zero, size: displaySize)
        case .scaleNone: factor = 1
        default:
            let ratios = (displaySize.width / imageSize.width, displaySize.height / imageSize.height)
            let proposed = allowClipping ? max(ratios.0, ratios.1) : min(ratios.0, ratios.1)
            factor = scaling == .scaleProportionallyDown ? min(proposed, 1) : proposed
        }
        let size = CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
        return CGRect(x: (displaySize.width - size.width) / 2, y: (displaySize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// One wallpaper source per display, shared by every Mica surface. AppKit source discovery stays
/// on the main thread; image decoding and blur never run in layout or input callbacks.
final class FluentWallpaperBackdrop {
    static let shared = FluentWallpaperBackdrop()

    private struct Source: Equatable {
        var url: URL
        var modified: Date?
        var bytes: Int?
        var size: CGSize
        var scale: CGFloat
        var scaling: UInt
        var clipping: Bool
        var fill: [CGFloat]
    }
    private struct Entry {
        var source: Source
        var image: CGImage?
    }
    private var entries: [CGDirectDisplayID: Entry] = [:]
    private let clients = NSHashTable<FluentMaterialView>.weakObjects()
    private let queue = DispatchQueue(label: "FluentKit.Wallpaper", qos: .utility)
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?

    func subscribe(_ view: FluentMaterialView) {
        guard !clients.contains(view) else { return }
        clients.add(view)
        if timer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() })
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    func unsubscribe(_ view: FluentMaterialView) {
        clients.remove(view)
        stopIfUnused()
    }

    func image(for screen: NSScreen) -> CGImage? {
        displayID(screen).flatMap { entries[$0]?.image }
    }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func stopIfUnused() {
        guard clients.allObjects.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func refresh() {
        stopIfUnused()
        guard !clients.allObjects.isEmpty else { return }
        var retained: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = displayID(screen) else { continue }
            retained.insert(id)
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen), url.isFileURL else {
                if entries.removeValue(forKey: id) != nil { notifyClients() }
                continue
            }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            let fill = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
                ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let source = Source(url: url, modified: attributes?.contentModificationDate, bytes: attributes?.fileSize,
                size: screen.frame.size, scale: screen.backingScaleFactor,
                scaling: (options[.imageScaling] as? NSNumber)?.uintValue ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                clipping: (options[.allowClipping] as? NSNumber)?.boolValue ?? true,
                fill: [fill.redComponent, fill.greenComponent, fill.blueComponent])
            guard entries[id]?.source != source else { continue }
            // Do not display an old Space's wallpaper while its replacement is loading.
            entries[id] = Entry(source: source, image: nil)
            notifyClients()
            queue.async { [weak self] in
                guard let self else { return }
                let image = Self.render(source, context: self.context)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.entries[id]?.source == source else { return }
                    self.entries[id]?.image = image
                    self.notifyClients()
                }
            }
        }
        let removed = entries.keys.filter { !retained.contains($0) }
        removed.forEach { entries.removeValue(forKey: $0) }
        if !removed.isEmpty { notifyClients() }
    }

    private func notifyClients() {
        clients.allObjects.forEach { $0.wallpaperBackdropDidChange() }
    }

    private static func render(_ source: Source, context: CIContext) -> CGImage? {
        guard source.size.width > 0, source.size.height > 0,
              let input = CGImageSourceCreateWithURL(source.url as CFURL, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              let image = CGImageSourceCreateThumbnailAtIndex(input, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        // A heavily blurred backdrop needs neither full-resolution decoding nor a per-window
        // copy. This caps each display's cached image at roughly four MiB.
        let ratio = min(1024 / max(source.size.width, source.size.height), 1)
        let canvasWidth = max(Int(ceil(source.size.width * ratio)), 1)
        let canvasHeight = max(Int(ceil(source.size.height * ratio)), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: canvasWidth, height: canvasHeight, bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        canvas.setFillColor(red: source.fill[0], green: source.fill[1], blue: source.fill[2], alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        canvas.scaleBy(x: ratio, y: ratio)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapped = (5...8).contains(orientation)
        let rect = FluentWallpaperGeometry.imageRect(
            imagePixels: CGSize(width: swapped ? height.doubleValue : width.doubleValue,
                                height: swapped ? width.doubleValue : height.doubleValue),
            displaySize: source.size, backingScale: source.scale,
            scaling: NSImageScaling(rawValue: source.scaling) ?? .scaleProportionallyUpOrDown,
            allowClipping: source.clipping)
        canvas.interpolationQuality = .high
        canvas.draw(image, in: rect)
        guard let mapped = canvas.makeImage() else { return nil }
        let base = CIImage(cgImage: mapped)
        // TenMica (WinUIEssentials) uses a heavy 120-unit wallpaper blur before its blend
        // stages. Adapt that reference to display points and the downsampled Core Image
        // canvas; neither the kernel nor its pixels are claimed identical to Direct2D.
        // See LICENSES/WinUIEssentials.txt and README acknowledgements.
        let blurred = base.clampedToExtent().applyingFilter("CIGaussianBlur",
            parameters: [kCIInputRadiusKey: 120 * ratio]).cropped(to: base.extent)
        return context.createCGImage(blurred, from: base.extent)
    }
}
