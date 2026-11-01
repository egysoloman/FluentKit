import AppKit

// AppKit retiles scroll views when the preferred scroller style changes, even when
// their outer frame stays unchanged. Frame-laid-out documents must follow the new
// clip size; ordinary scrolling must not trigger another parent layout.
class FluentViewportScrollView: NSScrollView {
    var onViewportSizeChange: (() -> Void)?
    private var lastViewportSize = NSSize(width: -1, height: -1)
    private var viewportChangePending = false

    override func tile() {
        super.tile()
        let size = contentView.bounds.size
        guard size != lastViewportSize else { return }
        lastViewportSize = size
        guard !viewportChangePending else { return }
        viewportChangePending = true
        // Retiling can occur while the parent lays out its document (including autohiding
        // a legacy scroller). Invalidating that parent synchronously is lost at layout exit.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewportChangePending = false
            self.onViewportSizeChange?()
        }
    }
}
