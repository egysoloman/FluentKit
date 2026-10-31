import AppKit

/// The kind of device that produced the most recent input in a window, mirroring WinUI's
/// `DirectUI::InputDeviceType`. Controls read it when they open or lay out to pick touch or
/// pointer variants (for example wider menu padding, or no hover navigation buttons for touch).
public enum FluentInputDeviceType: Hashable, Sendable {
    case none
    case mouse
    case touch
    case pen
    case keyboard

    /// WinUI treats touch and pen as devices that prefer primary commands and larger targets.
    public var prefersTouchLayout: Bool { self == .touch }
    public var prefersPrimaryCommands: Bool { self == .touch || self == .pen }
}

/// Records the last input device per window. A trackpad is a mouse here, as in WinUI where
/// touchpad pointers map to `InputDeviceType::Mouse`; direct screen touches (macOS 27) are touch.
public final class FluentInputDeviceTracker {
    public static let shared = FluentInputDeviceTracker()
    /// Posted with the window as object when its last input device type changes.
    public static let didChangeNotification = Notification.Name("FluentKit.InputDeviceTypeDidChange")

    private var monitors: [Any] = []
    private let typesByWindow = NSMapTable<NSWindow, Box>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    public private(set) var lastDeviceType: FluentInputDeviceType = .none

    private final class Box {
        var value: FluentInputDeviceType
        init(_ value: FluentInputDeviceType) { self.value = value }
    }

    private init() {}

    public func lastDeviceType(in window: NSWindow?) -> FluentInputDeviceType {
        installIfNeeded()
        guard let window else { return lastDeviceType }
        return typesByWindow.object(forKey: window)?.value ?? lastDeviceType
    }

    /// Lets controls report input that AppKit does not deliver as an event, such as a direct
    /// touch recognized by a gesture recognizer.
    public func record(_ type: FluentInputDeviceType, in window: NSWindow?) {
        guard type != .none else { return }
        lastDeviceType = type
        guard let window else { return }
        let previous = typesByWindow.object(forKey: window)?.value
        typesByWindow.setObject(Box(type), forKey: window)
        if previous != type {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: window)
        }
    }

    /// Classifies an AppKit event, or returns nil for events that do not change the device.
    public static func deviceType(for event: NSEvent) -> FluentInputDeviceType? {
        switch event.type {
        case .keyDown:
            return .keyboard
        case .directTouch:
            return .touch
        case .tabletPoint, .tabletProximity:
            return .pen
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            switch event.subtype {
            case .touch: return .touch
            case .tabletPoint, .tabletProximity: return .pen
            default: return .mouse
            }
        case .scrollWheel, .mouseMoved, .swipe, .magnify, .rotate, .smartMagnify:
            return .mouse
        default:
            return nil
        }
    }

    func installIfNeeded() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .scrollWheel, .tabletPoint, .tabletProximity, .directTouch, .swipe, .magnify, .rotate, .smartMagnify]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if let type = Self.deviceType(for: event) { self?.record(type, in: event.window) }
            return event
        }) {
            monitors.append(monitor)
        }
    }
}

/// One interactive pan along an axis, fed by direct touch (macOS 27), phased trackpad scrolling
/// and, optionally, discrete wheel steps. Translations are content displacements in logical
/// coordinates: horizontally positive points toward the trailing edge (mirrored in RTL),
/// vertically positive points down. Clients own what the translation means.
final class FluentPanGestureDriver: NSObject, NSGestureRecognizerDelegate {
    enum Axis { case horizontal, vertical }

    /// Distance a trackpad gesture travels before its axis is decided.
    static let axisThreshold: CGFloat = 4
    /// Window over which recent trackpad deltas form the release velocity.
    static let velocityWindow: TimeInterval = 0.1

    let axis: Axis
    private weak var view: NSView?

    /// Returns the translation the new gesture continues from, or nil to decline it.
    var onBegin: () -> CGFloat? = { 0 }
    var onChange: (CGFloat) -> Void = { _ in }
    /// Receives the logical release velocity in points per second.
    var onEnd: (CGFloat) -> Void = { _ in }
    var onCancel: () -> Void = {}
    /// Discrete (phase-less) wheel input along the axis: -1 toward leading/up, +1 toward trailing/down
    /// in content-displacement terms. Return true when handled.
    var onDiscreteStep: ((Int, NSEvent) -> Bool)?

    private(set) var isActive = false
    private(set) var touchRecognizer: NSPanGestureRecognizer?
    private var scrollState: ScrollState = .idle
    private var startTranslation: CGFloat = 0
    private var accumulated: CGFloat = 0
    private var samples: [(time: TimeInterval, delta: CGFloat)] = []
    private var lastStep: (time: TimeInterval, direction: Int)?

    private enum ScrollState: Equatable {
        case idle
        case undecided(along: CGFloat, across: CGFloat)
        case owned
        case rejected
    }

    init(view: NSView, axis: Axis) {
        self.view = view
        self.axis = axis
        super.init()
        installTouchRecognizer()
    }

    private var sign: CGFloat {
        guard axis == .horizontal, view?.userInterfaceLayoutDirection == .rightToLeft else { return 1 }
        return -1
    }

    // MARK: Trackpad and wheel

    /// Returns true when the event was consumed; otherwise the view should forward it to super.
    func handleScrollWheel(_ event: NSEvent) -> Bool {
        let along = (axis == .horizontal ? event.scrollingDeltaX : event.scrollingDeltaY) * sign
        let across = axis == .horizontal ? event.scrollingDeltaY : event.scrollingDeltaX
        if !event.momentumPhase.isEmpty {
            // Momentum after a pan this driver owned is replaced by the client's settle animation.
            let owned = scrollState == .owned
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { scrollState = .idle }
            return owned
        }
        if event.phase.isEmpty {
            return handleDiscreteWheel(event, along: along, across: across)
        }
        if event.phase.contains(.began) {
            scrollState = .undecided(along: 0, across: 0)
        }
        if event.phase.contains(.began) || event.phase.contains(.changed) {
            switch scrollState {
            case let .undecided(previousAlong, previousAcross):
                let nextAlong = previousAlong + along
                let nextAcross = previousAcross + across
                guard hypot(nextAlong, nextAcross) >= Self.axisThreshold else {
                    scrollState = .undecided(along: nextAlong, across: nextAcross)
                    return true
                }
                if abs(nextAlong) > abs(nextAcross), let start = beginPan(device: .mouse) {
                    scrollState = .owned
                    startTranslation = start
                    accumulated = nextAlong
                    samples = [(event.timestamp, nextAlong)]
                    onChange(startTranslation + accumulated)
                    return true
                }
                scrollState = .rejected
                return false
            case .owned:
                accumulated += along
                samples.append((event.timestamp, along))
                samples.removeAll { event.timestamp - $0.time > Self.velocityWindow }
                onChange(startTranslation + accumulated)
                return true
            case .rejected, .idle:
                return false
            }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            switch scrollState {
            case .owned:
                // Keep ownership until momentum ends so trailing momentum events are consumed.
                isActive = false
                if event.phase.contains(.cancelled) { onCancel() } else { onEnd(sampledVelocity) }
                return true
            case .rejected:
                scrollState = .idle
                return false
            case .undecided, .idle:
                scrollState = .idle
                return true
            }
        }
        return false
    }

    private var sampledVelocity: CGFloat {
        guard let first = samples.first, let last = samples.last else { return 0 }
        let span = max(last.time - first.time, 1.0 / 120.0)
        return samples.reduce(0) { $0 + $1.delta } / CGFloat(span)
    }

    /// A discrete wheel along the axis steps once per burst (200ms or a direction reversal).
    private func handleDiscreteWheel(_ event: NSEvent, along: CGFloat, across: CGFloat) -> Bool {
        guard let onDiscreteStep, abs(along) > abs(across), along != 0 else { return false }
        let direction = along < 0 ? -1 : 1
        let isBurst = lastStep.map { $0.direction == direction && event.timestamp - $0.time <= 0.2 } ?? false
        lastStep = (event.timestamp, direction)
        if isBurst { return true }
        return onDiscreteStep(direction, event)
    }

    private func beginPan(device: FluentInputDeviceType) -> CGFloat? {
        guard let start = onBegin() else { return nil }
        isActive = true
        FluentInputDeviceTracker.shared.record(device, in: view?.window)
        FluentFocusVisibility.markPointerInteraction(in: view?.window)
        return start
    }

    // MARK: Direct touch (macOS 27)

    private func installTouchRecognizer() {
        guard #available(macOS 27, *), let view else { return }
        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handleTouchPan(_:)))
        recognizer.allowedTouchTypes = [.direct]
        // Only fingers on a touch screen pan; mouse drags keep their ordinary meaning.
        recognizer.buttonMask = 0
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        // A pan inside a scroll view yields once that scroll view's own gesture begins.
        recognizer.isCancellableByScrollGesture = true
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        touchRecognizer = recognizer
    }

    private func touchTranslation(_ recognizer: NSPanGestureRecognizer) -> CGFloat {
        guard let view else { return 0 }
        let translation = recognizer.translation(in: view)
        return axis == .horizontal ? translation.x * sign : (view.isFlipped ? translation.y : -translation.y)
    }

    private func touchVelocity(_ recognizer: NSPanGestureRecognizer) -> CGFloat {
        guard let view else { return 0 }
        let velocity = recognizer.velocity(in: view)
        return axis == .horizontal ? velocity.x * sign : (view.isFlipped ? velocity.y : -velocity.y)
    }

    @objc func handleTouchPan(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let start = beginPan(device: .touch) else {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
                return
            }
            startTranslation = start
            onChange(start + touchTranslation(recognizer))
        case .changed:
            guard isActive else { return }
            onChange(startTranslation + touchTranslation(recognizer))
        case .ended:
            guard isActive else { return }
            isActive = false
            onEnd(touchVelocity(recognizer))
        case .cancelled, .failed:
            guard isActive else { return }
            isActive = false
            onCancel()
        default:
            break
        }
    }

    /// Only gestures dominant along the driver's axis begin; the rest go to enclosing scrollers.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard gestureRecognizer === touchRecognizer, let pan = gestureRecognizer as? NSPanGestureRecognizer,
              let view else { return true }
        let velocity = pan.velocity(in: view)
        let dominant = axis == .horizontal ? abs(velocity.x) > abs(velocity.y) : abs(velocity.y) > abs(velocity.x)
        return dominant && onBeginAllowed()
    }

    /// Asked before a touch gesture begins; defaults to allowing it.
    var onBeginAllowed: () -> Bool = { true }
}

/// One pinch gesture, fed by trackpad `magnify` events and macOS 27 direct-touch pinches.
/// Reports the cumulative scale (1 at the start of the gesture).
final class FluentMagnifyGestureDriver: NSObject, NSGestureRecognizerDelegate {
    private weak var view: NSView?
    var onBeginAllowed: () -> Bool = { true }
    var onBegin: () -> Bool = { true }
    var onChange: (CGFloat) -> Void = { _ in }
    var onEnd: (CGFloat) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private(set) var isActive = false
    private(set) var touchRecognizer: NSMagnificationGestureRecognizer?
    private var trackpadScale: CGFloat = 1

    init(view: NSView) {
        self.view = view
        super.init()
        installTouchRecognizer()
    }

    /// Returns true when the event was consumed; otherwise forward it to super.
    func handleMagnify(_ event: NSEvent) -> Bool {
        if event.phase.contains(.began) {
            guard onBeginAllowed(), onBegin() else { return false }
            isActive = true
            trackpadScale = 1
            FluentInputDeviceTracker.shared.record(.mouse, in: view?.window)
        }
        guard isActive else { return false }
        if event.phase.contains(.began) || event.phase.contains(.changed) {
            trackpadScale = max(0.05, trackpadScale * (1 + event.magnification))
            onChange(trackpadScale)
        }
        if event.phase.contains(.ended) {
            isActive = false
            onEnd(trackpadScale)
        } else if event.phase.contains(.cancelled) {
            isActive = false
            onCancel()
        }
        return true
    }

    private func installTouchRecognizer() {
        guard #available(macOS 27, *), let view else { return }
        let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(handleTouchMagnify(_:)))
        recognizer.allowedTouchTypes = [.direct]
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        touchRecognizer = recognizer
    }

    @objc func handleTouchMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
        let scale = max(0.05, 1 + recognizer.magnification)
        switch recognizer.state {
        case .began:
            guard onBegin() else {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
                return
            }
            isActive = true
            FluentInputDeviceTracker.shared.record(.touch, in: view?.window)
            onChange(scale)
        case .changed:
            if isActive { onChange(scale) }
        case .ended:
            guard isActive else { return }
            isActive = false
            onEnd(scale)
        case .cancelled, .failed:
            guard isActive else { return }
            isActive = false
            onCancel()
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer !== touchRecognizer || onBeginAllowed()
    }
}
