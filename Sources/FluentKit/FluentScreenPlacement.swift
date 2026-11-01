import AppKit

/// Popup coordinates are AppKit screen points, not backing pixels. A window may span
/// monitors; its `screen` is not necessarily the monitor containing the popup target.
enum FluentScreenPlacement {
    static func nearestScreenIndex(to point: NSPoint, frames: [NSRect]) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        if let contained = frames.firstIndex(where: { $0.contains(point) }) { return contained }
        var result: Int?
        var nearestDistance = CGFloat.infinity
        for (index, frame) in frames.enumerated() where !frame.isEmpty && !frame.isInfinite && !frame.isNull {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if distance < nearestDistance {
                nearestDistance = distance
                result = index
            }
        }
        return result
    }

    static func screen(nearest point: NSPoint) -> NSScreen? {
        // Read each time: screen arrangement and work areas can change while a popup is open.
        let screens = NSScreen.screens
        guard let index = nearestScreenIndex(to: point, frames: screens.map(\.frame)) else { return nil }
        return screens[index]
    }

    static func visibleFrame(at point: NSPoint, fallback window: NSWindow?) -> NSRect {
        screen(nearest: point)?.visibleFrame ?? window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }

    /// WinUI's transformed (0, 0) is the top-leading origin, including RTL mirroring.
    static func topLeading(of rect: NSRect, rightToLeft: Bool) -> NSPoint {
        NSPoint(x: rightToLeft ? rect.maxX : rect.minX, y: rect.maxY)
    }
}

/// Owned only for the lifetime of an open popup; releases all registrations on dismissal.
final class FluentPopupScreenObserver {
    private var tokens: [NSObjectProtocol] = []

    init(window: NSWindow, onChange: @escaping () -> Void) {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            tokens.append(center.addObserver(forName: name, object: window, queue: .main) { _ in onChange() })
        }
        tokens.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in onChange() })
    }

    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}
