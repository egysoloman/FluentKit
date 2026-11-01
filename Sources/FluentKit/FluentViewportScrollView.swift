import AppKit

// AppKit retiles scroll views when the preferred scroller style changes, even when
// their outer frame stays unchanged. Frame-laid-out documents must follow the new
// clip size; ordinary scrolling must not trigger another parent layout.
class FluentViewportScrollView: NSScrollView {
    var onViewportSizeChange: (() -> Void)?
    private var lastViewportSize = NSSize(width: -1, height: -1)

    override func tile() {
        super.tile()
        let size = contentView.bounds.size
        guard size != lastViewportSize else { return }
        lastViewportSize = size
        onViewportSizeChange?()
    }
}
