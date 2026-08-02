import AppKit

/// Coordinates document-modal presentations attached to one parent window.
///
/// AppKit permits only one attached sheet at a time.  Keeping that policy in one place avoids
/// Sheet, ConfirmationDialog, and file panels racing each other when a declarative update happens
/// while an older sheet is still dismissing.  A request is identified by a token so a completion
/// from an older presentation can never mutate a newer one.
final class FluentPresentationCoordinator {
    final class Token: NSObject {}

    private final class Request {
        let token: Token
        weak var owner: AnyObject?
        let present: () -> Void
        let cancel: () -> Void
        weak var focusedView: NSView?
        var isCancelled = false

        init(
            token: Token,
            owner: AnyObject,
            present: @escaping () -> Void,
            cancel: @escaping () -> Void
        ) {
            self.token = token
            self.owner = owner
            self.present = present
            self.cancel = cancel
        }
    }

    private static var coordinators: [ObjectIdentifier: FluentPresentationCoordinator] = [:]

    static func coordinator(for window: NSWindow) -> FluentPresentationCoordinator {
        let key = ObjectIdentifier(window)
        if let coordinator = coordinators[key], coordinator.window === window {
            return coordinator
        }
        coordinators = coordinators.filter { $0.value.window != nil }
        let coordinator = FluentPresentationCoordinator(window: window)
        coordinators[key] = coordinator
        return coordinator
    }

    private weak var window: NSWindow?
    private var active: Request?
    private var queued: [Request] = []
    private var drainScheduled = false

    private init(window: NSWindow) {
        self.window = window
    }

    @discardableResult
    func enqueue(
        owner: AnyObject,
        present: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> Token {
        if let active, active.owner === owner, !active.isCancelled {
            return active.token
        }
        if let queued = queued.first(where: { $0.owner === owner }) {
            return queued.token
        }

        let token = Token()
        queued.append(Request(token: token, owner: owner, present: present, cancel: cancel))
        scheduleDrain()
        return token
    }

    func cancel(_ token: Token) {
        if let index = queued.firstIndex(where: { $0.token === token }) {
            queued.remove(at: index)
            scheduleDrain()
            return
        }

        guard let active, active.token === token, !active.isCancelled else { return }
        active.isCancelled = true
        active.cancel()
    }

    /// Completes a native presentation. Stale completions are ignored and cannot release the
    /// request currently occupying the window.
    func finish(_ token: Token) {
        guard let active, active.token === token else { return }
        self.active = nil
        restoreFocus(for: active)
        scheduleDrain()
    }

    private func scheduleDrain() {
        guard !drainScheduled else { return }
        drainScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drainScheduled = false
            self.drain()
        }
    }

    private func drain() {
        while let first = queued.first, first.owner == nil {
            queued.removeFirst()
        }
        guard active == nil, let request = queued.first else { return }
        guard window != nil else {
            queued.removeFirst()
            return
        }
        queued.removeFirst()
        active = request
        if let window, let view = window.firstResponder as? NSView {
            request.focusedView = view
        }
        request.present()
    }

    private func restoreFocus(for request: Request) {
        guard let window, let view = request.focusedView, view.window === window else { return }
        window.makeFirstResponder(view)
    }
}
