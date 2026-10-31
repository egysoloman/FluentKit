import AppKit
import FluentKit

final class MotionViewport: NSView { override var isFlipped: Bool { true } }
final class MotionContent: NSView {
    var color = NSColor.systemRed { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill(); bounds.fill()
        NSColor.white.setFill(); NSRect(x: 24, y: 12, width: 45, height: 25).fill()
    }
}

@main struct IMEPageMotionAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 500, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = MotionViewport(frame: NSRect(x: 20, y: 20, width: 300, height: 160))
        viewport.wantsLayer = true; viewport.layer?.masksToBounds = true; viewport.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView!.addSubview(viewport)
        let content = MotionContent(frame: viewport.bounds); content.wantsLayer = true; viewport.addSubview(content)
        window.makeKeyAndOrderFront(nil)
        func settle(_ seconds: TimeInterval) {
            viewport.layoutSubtreeIfNeeded(); content.displayIfNeeded(); CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        }
        func image(_ layer: CALayer, _ size: CGSize) -> CGImage {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
            cg.scaleBy(x: 2, y: 2)
            cg.translateBy(x: 0, y: size.height); cg.scaleBy(x: 1, y: -1)
            layer.render(in: cg)
            return bitmap.cgImage!
        }
        func save(_ image: CGImage, _ name: String) throws {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent(name + ".png"))
        }
        func layers() -> [CALayer] { viewport.layer!.sublayers?.filter { $0.zPosition == 10 } ?? [] }
        let motion = IMEPageMotion()
        settle(0.06)
        let initial = motion.capture(viewport)!
        try save(initial.image, "initial-snapshot")
        try save(image(viewport.layer!.presentation() ?? viewport.layer!, viewport.bounds.size), "initial-presentation")
        content.color = .systemGreen; content.displayIfNeeded()
        motion.play(initial, in: viewport, content: content, backward: false, navigation: true)
        settle(0.025)
        try save(image(viewport.layer!.presentation() ?? viewport.layer!, viewport.bounds.size), "interrupt-presentation")
        let interrupted = motion.capture(viewport)!
        try save(interrupted.image, "interrupt-snapshot")
        content.color = .systemBlue; content.displayIfNeeded()
        motion.play(interrupted, in: viewport, content: content, backward: true, navigation: true)
        settle(0.01)
        let oldFrames = layers().map { NSStringFromRect($0.frame) }
        viewport.frame.size.width = 420; content.frame = viewport.bounds
        settle(0.01)
        let resizedFrames = layers().map { NSStringFromRect($0.frame) }
        let resizedAnimationCount = content.layer?.animationKeys()?.count ?? 0
        try save(image(viewport.layer!.presentation() ?? viewport.layer!, viewport.bounds.size), "resized")
        settle(0.7)
        var results: [String: Any] = ["reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "initialOverlayFrames": oldFrames, "resizedOverlayFrames": resizedFrames,
            "resizedViewport": NSStringFromRect(viewport.bounds), "resizedIncomingAnimations": resizedAnimationCount,
            "settledOverlays": layers().count, "settledIncomingAnimations": content.layer?.animationKeys()?.count ?? 0]
        let bar = MotionViewport(frame: NSRect(x: 20, y: 185, width: 460, height: 32))
        bar.wantsLayer = true; window.contentView!.addSubview(bar)
        let back = MotionContent(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        back.identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.Back"); back.wantsLayer = true
        let title = MotionContent(frame: NSRect(x: 38, y: 0, width: 80, height: 32))
        title.identifier = NSUserInterfaceItemIdentifier("FluentKit.TitleBar.Title"); title.wantsLayer = true
        bar.addSubview(back); bar.addSubview(title); bar.displayIfNeeded(); settle(0.03)
        let titleMotion = IMETitleBarMotion()
        let showing = titleMotion.capture(bar)!
        back.isHidden = true; title.frame.origin.x = 0
        titleMotion.play(showing, in: bar, showingBack: false); settle(0.015)
        let leaving = bar.layer!.sublayers!.first { $0.zPosition == 10 }!
        results["visibleLeavingBackOpacity"] = leaving.presentation()?.opacity ?? -1
        let reversing = titleMotion.capture(bar)!
        results["reversingBackImage"] = reversing.backImage != nil
        results["reversingBackOpacity"] = reversing.backOpacity
        back.isHidden = false; title.frame.origin.x = 38
        titleMotion.play(reversing, in: bar, showingBack: true)
        let group = back.layer!.animation(forKey: "FluentIME.TitleBar.Visibility") as! CAAnimationGroup
        let fade = group.animations!.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "opacity" }!
        results["reversingEntranceOpacity"] = fade.fromValue as! NSNumber
        bar.frame.size.width = 420; settle(0.01)
        results["resizedTitleAnimations"] = title.layer?.animationKeys()?.count ?? 0
        results["resizedBackAnimations"] = back.layer?.animationKeys()?.count ?? 0
        settle(0.25)
        let closingPage = motion.capture(viewport)!
        motion.play(closingPage, in: viewport, content: content, backward: false, navigation: true)
        let closingTitle = titleMotion.capture(bar)!
        back.isHidden = true
        titleMotion.play(closingTitle, in: bar, showingBack: false)
        window.close()
        results["closedOverlays"] = layers().count
        results["closedIncomingAnimations"] = content.layer?.animationKeys()?.count ?? 0
        results["closedTitleAnimations"] = title.layer?.animationKeys()?.count ?? 0
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.deletingLastPathComponent().appendingPathComponent("results.json"))
    }
}
