import AppKit
@testable import FluentKit

@main struct MaterialBaseline {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        func find(_ view: NSView) -> FluentMaterialView? {
            if let material = view as? FluentMaterialView { return material }
            return view.subviews.lazy.compactMap(find).first
        }
        let context = FluentRenderContext(theme: .custom(colorScheme: .dark))
        let host = FluentViewHost(FluentMaterialSurface(material: .mica, cornerRadius: 4) { FluentText("Material") }, context: context)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        host.layoutSubtreeIfNeeded()
        let surface = find(host)!
        host.update(FluentMaterialSurface(material: .nativeAcrylic, cornerRadius: 20, showsBorder: false) { FluentText("Material") })
        host.layoutSubtreeIfNeeded()
        var rows: [String: Any] = ["surface_updated": ["material": String(describing: surface.materialStyle), "radius": surface.layer!.cornerRadius, "border": surface.layer!.borderWidth]]
        let high = FluentMaterialView(material: .nativeAcrylic)
        high.fluentTheme = .custom(contrast: .high, colorScheme: .dark)
        high.fallbackColor = high.fluentTheme!.flyoutSurfaceFill
        rows["high_contrast_backend"] = high.resolvedBackend.rawValue
        let tip = FluentToolTipSurface(content: FluentToolTipText("Help")._mount(in: context),
            context: FluentRenderContext(theme: .custom(material: .liquidGlass, colorScheme: .dark)))
        rows["tooltip_material"] = String(describing: find(tip)!.materialStyle)
        let glass = FluentMaterialView(material: .liquidGlass)
        glass.frame = NSRect(x: 0, y: 0, width: 100, height: 50)
        glass.layer?.cornerRadius = 12
        glass.layoutSubtreeIfNeeded()
        rows["glass_radius"] = glass.subviews.first { $0.identifier?.rawValue == "FluentKit.Material.NativeGlass" }?.value(forKey: "cornerRadius") ?? "unavailable"
        let tint = FluentMaterialView(material: .nativeMica)
        tint.frame = NSRect(x: 0, y: 0, width: 80, height: 40)
        tint.tintColor = NSColor.blue.withAlphaComponent(0.5)
        let content = NSView(frame: NSRect(x: 10, y: 10, width: 20, height: 20))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.red.cgColor
        tint.addSubview(content)
        let window = NSWindow(contentRect: tint.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = tint
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        tint.layoutSubtreeIfNeeded()
        tint.displayIfNeeded()
        CATransaction.flush()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        tint.layer?.render(in: NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext)
        let pixel = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        rows["foreground_pixel"] = [pixel.redComponent, pixel.greenComponent, pixel.blueComponent, pixel.alphaComponent]
        rows["content_layer_attached"] = content.layer?.superlayer != nil
        tint.tintColor = .clear
        CATransaction.flush()
        tint.layer?.render(in: NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext)
        let control = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        rows["untinted_foreground_pixel"] = [control.redComponent, control.greenComponent, control.blueComponent, control.alphaComponent]
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
