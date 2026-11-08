import AppKit

/// Draws control content above layer-backed chrome without adding an input or accessibility target.
/// NSView's own backing contents sit below its sublayers, including opaque state backgrounds.
final class FluentControlForegroundView: NSView {
    var drawContent: ((NSRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { drawContent?(dirtyRect) }
}
