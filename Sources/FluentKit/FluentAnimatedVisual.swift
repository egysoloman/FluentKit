import AppKit

/// A timeline-driven animation (WinUI `IAnimatedVisualSource2`): a duration, a natural size,
/// named progress markers and a factory for the visual that renders any progress in 0…1.
public protocol FluentAnimatedVisualSource {
    var duration: TimeInterval { get }
    var naturalSize: NSSize { get }
    var markers: [String: Double] { get }
    func makeVisual() -> FluentAnimatedVisual
}

/// The rendered instance of a source. `rootLayer` is laid out at the source's natural size.
public protocol FluentAnimatedVisual: AnyObject {
    var rootLayer: CALayer { get }
    func setProgress(_ progress: Double)
    func setForeground(_ color: NSColor)
}

/// Drives a progress value over time with a 60Hz timer (linear, as WinUI's segment animations).
final class FluentAnimatedProgressDriver {
    private(set) var progress: Double = 0
    private(set) var isPlaying = false
    private var timer: Timer?
    private var segment: (from: Double, to: Double, duration: TimeInterval, looped: Bool)?
    private var elapsed: TimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var completion: ((Bool) -> Void)?
    var rate: Double = 1
    var onProgress: ((Double) -> Void)?

    deinit { timer?.invalidate() }

    /// Plays from → to over `duration`. A superseded play completes with `false`.
    func play(from: Double, to: Double, duration: TimeInterval, looped: Bool, completion: ((Bool) -> Void)? = nil) {
        finish(completed: false)
        setProgress(from)
        guard duration > 0, from != to || looped else {
            setProgress(to)
            completion?(true)
            return
        }
        segment = (from, to, duration, looped)
        elapsed = 0
        self.completion = completion
        resume()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }

    func resume() {
        guard segment != nil, timer == nil else { return }
        isPlaying = true
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the current play (completing it as cancelled) and keeps the given progress.
    func stop(at value: Double) {
        finish(completed: false)
        setProgress(value)
    }

    func setProgress(_ value: Double) {
        progress = min(max(value, 0), 1)
        onProgress?(progress)
    }

    private func tick() {
        guard let segment else { return }
        let now = CACurrentMediaTime()
        elapsed += (now - lastTick) * max(rate, 0)
        lastTick = now
        var fraction = elapsed / segment.duration
        if fraction >= 1 {
            if segment.looped {
                fraction = fraction.truncatingRemainder(dividingBy: 1)
                elapsed = fraction * segment.duration
            } else {
                setProgress(segment.to)
                finish(completed: true)
                return
            }
        }
        setProgress(segment.from + (segment.to - segment.from) * fraction)
    }

    private func finish(completed: Bool) {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        segment = nil
        let completion = self.completion
        self.completion = nil
        completion?(completed)
    }
}

// MARK: - AnimatedVisualPlayer

/// `Stretch` for an AnimatedVisualPlayer.
public enum FluentAnimatedVisualStretch: Hashable, Sendable {
    case none
    case fill
    case uniform
    case uniformToFill
}

/// Imperative control of an AnimatedVisualPlayer (`PlayAsync`, `Pause`, `Resume`, `Stop`, `SetProgress`).
public final class FluentAnimatedVisualPlayerController {
    fileprivate weak var player: FluentAnimatedVisualPlayerView?

    public init() {}

    public var isPlaying: Bool { player?.driver.isPlaying ?? false }
    public var progress: Double { player?.driver.progress ?? 0 }

    /// Plays from → to; the completion receives `true` when the segment finished, `false` when it
    /// was stopped or superseded. Looped plays only complete when stopped.
    public func play(from: Double = 0, to: Double = 1, looped: Bool = false, completion: ((Bool) -> Void)? = nil) {
        player?.play(from: from, to: to, looped: looped, completion: completion)
    }

    public func pause() { player?.driver.pause() }
    public func resume() { player?.driver.resume() }
    /// `Stop`: ends the current play and returns to the start.
    public func stop() { player?.driver.stop(at: 0) }
    public func setProgress(_ progress: Double) { player?.driver.stop(at: progress) }
}

/// A WinUI-style AnimatedVisualPlayer. With `autoPlay` it loops 0…1 as soon as the source loads;
/// otherwise drive it through a controller. Without a source the fallback content is shown.
public struct FluentAnimatedVisualPlayer: FluentUpdatablePrimitiveView {
    private let source: FluentAnimatedVisualSource?
    private let controller: FluentAnimatedVisualPlayerController?
    private let autoPlay: Bool
    private let playbackRate: Double
    private let stretch: FluentAnimatedVisualStretch
    private let fallback: FluentAnyView?

    public init(
        source: FluentAnimatedVisualSource?,
        controller: FluentAnimatedVisualPlayerController? = nil,
        autoPlay: Bool = true,
        playbackRate: Double = 1,
        stretch: FluentAnimatedVisualStretch = .uniform,
        fallback: FluentAnyView? = nil
    ) {
        self.source = source
        self.controller = controller
        self.autoPlay = autoPlay
        self.playbackRate = playbackRate
        self.stretch = stretch
        self.fallback = fallback
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let player = FluentAnimatedVisualPlayerView(context: context)
        apply(to: player, context: context)
        return player
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let player = view as? FluentAnimatedVisualPlayerView else { return false }
        apply(to: player, context: context)
        return true
    }

    private func apply(to player: FluentAnimatedVisualPlayerView, context: FluentRenderContext) {
        controller?.player = player
        player.update(source: source, autoPlay: autoPlay, playbackRate: playbackRate, stretch: stretch,
                      fallback: fallback, context: context)
    }
}

final class FluentAnimatedVisualPlayerView: NSView {
    override var isFlipped: Bool { true }
    let driver = FluentAnimatedProgressDriver()
    private var sourceIdentity: ObjectIdentifier?
    private var sourceKey: String?
    private(set) var visual: FluentAnimatedVisual?
    private(set) var naturalSize: NSSize = .zero
    private(set) var stretch: FluentAnimatedVisualStretch = .uniform
    private var duration: TimeInterval = 0
    private var autoPlay = true
    private(set) var fallbackHost: FluentViewHost<FluentAnyView>?
    private var context: FluentRenderContext

    init(context: FluentRenderContext) {
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AnimatedVisualPlayer")
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        driver.onProgress = { [weak self] progress in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.visual?.setProgress(progress)
            CATransaction.commit()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isAnimatedVisualLoaded: Bool { visual != nil }

    func update(source: FluentAnimatedVisualSource?, autoPlay: Bool, playbackRate: Double, stretch: FluentAnimatedVisualStretch,
                fallback: FluentAnyView?, context: FluentRenderContext) {
        self.context = context
        self.stretch = stretch
        driver.rate = playbackRate
        let key = source.map { String(reflecting: type(of: $0)) }
        let sourceChanged = key != sourceKey
        sourceKey = key
        if sourceChanged {
            driver.stop(at: 0)
            visual?.rootLayer.removeFromSuperlayer()
            visual = nil
            if let source {
                let made = source.makeVisual()
                visual = made
                naturalSize = source.naturalSize
                duration = source.duration
                layer?.addSublayer(made.rootLayer)
            }
        }
        visual?.setForeground(context.theme.textPrimary)
        // FallbackContent shows only when no animated visual is loaded.
        if visual == nil, let fallback {
            if let fallbackHost { fallbackHost.update(fallback, context: context) } else {
                let host = FluentViewHost(fallback, context: context)
                host.translatesAutoresizingMaskIntoConstraints = true
                addSubview(host)
                fallbackHost = host
            }
        } else {
            fallbackHost?.removeFromSuperview()
            fallbackHost = nil
        }
        // `OnAutoPlayPropertyChanged`: AutoPlay loops 0…1; turning it off stops playback.
        if autoPlay != self.autoPlay || sourceChanged {
            if autoPlay, visual != nil { play(from: 0, to: 1, looped: true, completion: nil) } else if !autoPlay, self.autoPlay { driver.stop(at: 0) }
        }
        self.autoPlay = autoPlay
        needsLayout = true
    }

    func play(from: Double, to: Double, looped: Bool, completion: ((Bool) -> Void)?) {
        guard visual != nil else { completion?(false); return }
        let span = looped ? abs(to - from) : abs(to - from)
        driver.play(from: from, to: to, duration: duration * max(span, looped ? 1 : 0), looped: looped, completion: completion)
    }

    override var intrinsicContentSize: NSSize { visual == nil ? (fallbackHost?.fittingSize ?? .zero) : naturalSize }

    override func layout() {
        super.layout()
        fallbackHost?.frame = bounds
        guard let visual, naturalSize.width > 0, naturalSize.height > 0 else { return }
        let sx = bounds.width / naturalSize.width
        let sy = bounds.height / naturalSize.height
        let scale: (CGFloat, CGFloat)
        switch stretch {
        case .none: scale = (1, 1)
        case .fill: scale = (sx, sy)
        case .uniform: scale = (min(sx, sy), min(sx, sy))
        case .uniformToFill: scale = (max(sx, sy), max(sx, sy))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        visual.rootLayer.bounds = CGRect(origin: .zero, size: naturalSize)
        visual.rootLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        visual.rootLayer.setAffineTransform(CGAffineTransform(scaleX: scale.0, y: scale.1))
        CATransaction.commit()
        layer?.masksToBounds = stretch == .uniformToFill || stretch == .none
    }
}

// MARK: - AnimatedIcon

/// `AnimatedIconAnimationQueueBehavior`.
public enum FluentAnimatedIconQueueBehavior: Hashable, Sendable {
    case cut
    case queueOne
    case speedUpQueueOne
}

/// A WinUI-style AnimatedIcon: plays the source's `FromToTo_Start/_End` marker segment whenever its
/// state changes (Normal, PointerOver, Pressed, or any custom state, or a numeric progress string).
/// When `state` is nil the icon follows its own pointer and pressed state. Without a source the
/// fallback SF Symbol is shown.
public struct FluentAnimatedIcon: FluentUpdatablePrimitiveView {
    private let source: FluentAnimatedVisualSource?
    private let fallbackSymbol: String?
    private let state: String?
    private let queueBehavior: FluentAnimatedIconQueueBehavior
    private let size: CGFloat

    public init(
        source: FluentAnimatedVisualSource?,
        fallbackSymbol: String? = nil,
        state: String? = nil,
        queueBehavior: FluentAnimatedIconQueueBehavior = .queueOne,
        size: CGFloat = 16
    ) {
        self.source = source
        self.fallbackSymbol = fallbackSymbol
        self.state = state
        self.queueBehavior = queueBehavior
        self.size = size
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let icon = FluentAnimatedIconView(context: context)
        icon.update(source: source, fallbackSymbol: fallbackSymbol, state: state, queueBehavior: queueBehavior, size: size, context: context)
        return icon
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let icon = view as? FluentAnimatedIconView else { return false }
        icon.update(source: source, fallbackSymbol: fallbackSymbol, state: state, queueBehavior: queueBehavior, size: size, context: context)
        return true
    }
}

enum FluentAnimatedIconMetrics {
    static let queueLength = 4
    static let speedUpMultiplier: Double = 7
    /// Segments shorter than this cut straight to their end (`PlaySegment`).
    static let minimumAnimatedDuration: TimeInterval = 0.02
}

final class FluentAnimatedIconView: NSView {
    override var isFlipped: Bool { true }
    let driver = FluentAnimatedProgressDriver()
    private(set) var visual: FluentAnimatedVisual?
    private var source: FluentAnimatedVisualSource?
    private var sourceKey: String?
    private var context: FluentRenderContext
    private let fallbackLayer = CALayer()
    private var fallbackSymbol: String?
    private var size: CGFloat = 16
    private(set) var queueBehavior: FluentAnimatedIconQueueBehavior = .queueOne
    private var explicitState: String?
    private(set) var currentState = "Normal"
    private(set) var previousState = ""
    private var pendingState: String?
    private(set) var queuedStates: [String] = []
    private(set) var lastAnimationSegment = ""
    private(set) var lastAnimationSegmentEnd = ""
    private var previousSegmentLength: Double = 1
    private var isSpeedUp = false
    private var isPointerOver = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?
    private var stateGeneration: UInt64 = 0

    init(context: FluentRenderContext) {
        self.context = context
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.AnimatedIcon")
        wantsLayer = true
        layer?.addSublayer(fallbackLayer)
        fallbackLayer.contentsGravity = .resizeAspect
        setAccessibilityElement(false)
        driver.onProgress = { [weak self] progress in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.visual?.setProgress(progress)
            CATransaction.commit()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var progress: Double { driver.progress }
    var isShowingFallback: Bool { visual == nil && fallbackLayer.contents != nil }

    func update(source: FluentAnimatedVisualSource?, fallbackSymbol: String?, state: String?,
                queueBehavior: FluentAnimatedIconQueueBehavior, size: CGFloat, context: FluentRenderContext) {
        self.context = context
        self.queueBehavior = queueBehavior
        self.size = size
        self.fallbackSymbol = fallbackSymbol
        let key = source.map { String(reflecting: type(of: $0)) }
        if key != sourceKey {
            sourceKey = key
            self.source = source
            driver.stop(at: 0)
            visual?.rootLayer.removeFromSuperlayer()
            visual = source?.makeVisual()
            if let visual { layer?.addSublayer(visual.rootLayer) }
            // A new source starts at its current state's resting frame.
            if source != nil { transitionStates(from: currentState, to: currentState, multiplier: 1, animated: false) }
        }
        visual?.setForeground(context.theme.textPrimary)
        updateFallback()
        explicitState = state
        if let state, state != currentState, state != pendingState { setState(state) }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.frame = bounds
        if let visual, let source, source.naturalSize.width > 0 {
            let scale = min(bounds.width / source.naturalSize.width, bounds.height / source.naturalSize.height)
            visual.rootLayer.bounds = CGRect(origin: .zero, size: source.naturalSize)
            visual.rootLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            visual.rootLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        CATransaction.commit()
        updateTracking()
    }

    private func updateFallback() {
        guard visual == nil, let name = fallbackSymbol,
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .regular)) else {
            fallbackLayer.contents = nil
            return
        }
        let color = context.theme.textPrimary
        fallbackLayer.contents = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: State

    /// `OnStatePropertyChanged`: rapid changes within one turn (a parent's GoToState("Foo") followed
    /// by GoToState("Bar")) collapse into the last one, applied on the next layout pass.
    func setState(_ state: String) {
        pendingState = state
        stateGeneration &+= 1
        let generation = stateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stateGeneration == generation else { return }
            self.applyPendingState()
        }
    }

    /// Applies a pending state immediately (used by tests and by `setState`).
    func applyPendingState() {
        guard let pending = pendingState else { return }
        pendingState = nil
        switch queueBehavior {
        case .cut:
            transitionAndUpdate(from: currentState, to: pending, multiplier: 1)
        case .queueOne:
            if driver.isPlaying {
                if queuedStates.count >= FluentAnimatedIconMetrics.queueLength, let first = queuedStates.first {
                    transitionAndUpdate(from: currentState, to: first, multiplier: 1)
                }
                queuedStates.append(pending)
            } else {
                transitionAndUpdate(from: currentState, to: pending, multiplier: 1)
            }
        case .speedUpQueueOne:
            if driver.isPlaying {
                if queuedStates.count >= FluentAnimatedIconMetrics.queueLength, let first = queuedStates.first {
                    transitionAndUpdate(from: currentState, to: first, multiplier: FluentAnimatedIconMetrics.speedUpMultiplier)
                    queuedStates.append(pending)
                } else {
                    queuedStates.append(pending)
                    if !isSpeedUp {
                        isSpeedUp = true
                        let end = "\(previousState)To\(currentState)_End"
                        if let to = source?.markers[end] { playSegment(from: nil, to: to, multiplier: FluentAnimatedIconMetrics.speedUpMultiplier, completion: nil) }
                    }
                }
            } else {
                transitionAndUpdate(from: currentState, to: pending, multiplier: 1)
            }
        }
    }

    /// `TransitionAndUpdateStates`: the state bookkeeping (WinUI's cleanup action) runs before the
    /// segment can complete, so a synchronously finished segment already sees the new state.
    private func transitionAndUpdate(from: String, to: String, multiplier: Double) {
        previousState = from
        currentState = to
        if !queuedStates.isEmpty { queuedStates.removeFirst() }
        transitionStates(from: from, to: to, multiplier: multiplier, animated: true, onComplete: { [weak self] in
            self?.animationCompleted()
        })
    }

    /// `AnimatedIcon::TransitionStates`: prefer a FromToTo_Start/_End segment, then single markers,
    /// then any segment ending in the target state, then a numeric progress, else frame 0.
    func transitionStates(from: String, to: String, multiplier: Double, animated: Bool, onComplete: (() -> Void)? = nil) {
        let markers = source?.markers ?? [:]
        let name = "\(from)To\(to)"
        let start = markers["\(name)_Start"]
        let end = markers["\(name)_End"]
        lastAnimationSegment = name
        if let start, let end {
            lastAnimationSegmentEnd = "\(name)_End"
            if animated { playSegment(from: start, to: end, multiplier: multiplier, completion: onComplete) } else { driver.stop(at: end) }
        } else if let end {
            lastAnimationSegmentEnd = "\(name)_End"
            driver.stop(at: end)
        } else if let start {
            lastAnimationSegmentEnd = ""
            driver.stop(at: start)
        } else if let value = markers[name] {
            lastAnimationSegmentEnd = name
            driver.stop(at: value)
        } else if let value = markers[to] {
            lastAnimationSegmentEnd = to
            driver.stop(at: value)
        } else if let match = markers.first(where: { $0.key.contains("To\(to)_End") }) {
            lastAnimationSegmentEnd = match.key
            driver.stop(at: match.value)
        } else if let value = Double(to) {
            lastAnimationSegmentEnd = to
            if animated { playSegment(from: nil, to: value, multiplier: multiplier, completion: onComplete) } else { driver.stop(at: value) }
        } else {
            lastAnimationSegmentEnd = "0.0"
            driver.stop(at: 0)
        }
    }

    /// `PlaySegment`: linear over duration × segment length / multiplier; a NaN start continues from
    /// the current progress with the previous segment's length; short segments or Reduce Motion cut.
    private func playSegment(from: Double?, to: Double, multiplier: Double, completion: (() -> Void)?) {
        let length = from.map { abs(to - $0) } ?? previousSegmentLength
        previousSegmentLength = length
        let duration = (source?.duration ?? 0) * length / multiplier
        if duration < FluentAnimatedIconMetrics.minimumAnimatedDuration || context.reduceMotion {
            driver.stop(at: to)
            completion?()
            return
        }
        driver.play(from: from ?? driver.progress, to: to, duration: duration, looped: false) { finished in
            if finished { completion?() }
        }
    }

    /// `OnAnimationCompleted`: plays the next queued state.
    private func animationCompleted() {
        isSpeedUp = false
        guard let next = queuedStates.first else { return }
        transitionAndUpdate(from: currentState, to: next, multiplier: queueBehavior == .speedUpQueueOne ? FluentAnimatedIconMetrics.speedUpMultiplier : 1)
    }

    // MARK: Self-driven pointer state

    private func updateTracking() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func pointerStateChanged() {
        guard explicitState == nil else { return }
        setState(isPressed ? "Pressed" : isPointerOver ? "PointerOver" : "Normal")
    }

    override func mouseEntered(with event: NSEvent) { isPointerOver = true; pointerStateChanged() }
    override func mouseExited(with event: NSEvent) { isPointerOver = false; isPressed = false; pointerStateChanged() }
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        pointerStateChanged()
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        pointerStateChanged()
        super.mouseUp(with: event)
    }
}

// MARK: - Built-in icon sources

/// A pose-based source: each state has a pose; between a segment's markers the visual eases from
/// the segment's start pose to its end pose. The marker timelines and durations are WinUI's; the
/// glyphs and poses are FluentKit's own Core Animation approximations of the Lottie originals.
struct FluentAnimatedIconPose {
    var translation = CGPoint.zero
    var rotation: CGFloat = 0
    var scale = CGSize(width: 1, height: 1)
    /// Extra per-glyph parameter (for example line spread for the navigation button).
    var detail: CGFloat = 0

    static func lerp(_ a: FluentAnimatedIconPose, _ b: FluentAnimatedIconPose, _ t: CGFloat) -> FluentAnimatedIconPose {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return FluentAnimatedIconPose(
            translation: CGPoint(x: mix(a.translation.x, b.translation.x), y: mix(a.translation.y, b.translation.y)),
            rotation: mix(a.rotation, b.rotation),
            scale: CGSize(width: mix(a.scale.width, b.scale.width), height: mix(a.scale.height, b.scale.height)),
            detail: mix(a.detail, b.detail))
    }
}

/// Shared implementation for the built-in Normal/PointerOver/Pressed icons.
public struct FluentBuiltInAnimatedIconSource: FluentAnimatedVisualSource {
    public enum Glyph: String, Sendable, CaseIterable {
        case back
        case chevronDownSmall
        case settings
        case globalNavigationButton
        case find
    }

    public let glyph: Glyph
    public init(_ glyph: Glyph) { self.glyph = glyph }

    public var naturalSize: NSSize { NSSize(width: 48, height: 48) }

    /// `c_durationTicks` of the corresponding WinUI source.
    public var duration: TimeInterval {
        switch glyph {
        case .chevronDownSmall: return 0.4833333
        case .settings: return 2.0
        case .back, .globalNavigationButton, .find: return 1.3333333
        }
    }

    public var markers: [String: Double] {
        switch glyph {
        case .chevronDownSmall:
            return ["NormalToPointerOver_Start": 0, "NormalToPointerOver_End": 0, "NormalToPressed_Start": 0,
                    "NormalToPressed_End": 0.312068965517241, "PointerOverToNormal_Start": 0, "PointerOverToNormal_End": 0,
                    "PointerOverToPressed_Start": 0, "PointerOverToPressed_End": 0.312068965517241,
                    "PressedToNormal_Start": 0.346551724137931, "PressedToNormal_End": 0.967241379310345,
                    "PressedToPointerOver_Start": 0.346551724137931, "PressedToPointerOver_End": 0.967241379310345]
        case .settings:
            return ["NormalToPointerOver_Start": 0, "NormalToPointerOver_End": 0.0754166666666667,
                    "NormalToPressed_Start": 0.08375, "NormalToPressed_End": 0.15875,
                    "PointerOverToNormal_Start": 0.167083333333333, "PointerOverToNormal_End": 0.242083333333333,
                    "PointerOverToPressed_Start": 0.250416666666667, "PointerOverToPressed_End": 0.325416666666667,
                    "PressedToNormal_Start": 0.33375, "PressedToNormal_End": 0.65875,
                    "PressedToPointerOver_Start": 0.667083333333333, "PressedToPointerOver_End": 0.992083333333333]
        case .back, .globalNavigationButton, .find:
            return ["NormalToPointerOver_Start": 0, "NormalToPointerOver_End": 0.113125,
                    "NormalToPressed_Start": 0.125625, "NormalToPressed_End": 0.238125,
                    "PointerOverToNormal_Start": 0.250625, "PointerOverToNormal_End": 0.363125,
                    "PointerOverToPressed_Start": 0.375625, "PointerOverToPressed_End": 0.488125,
                    "PressedToNormal_Start": 0.500625, "PressedToNormal_End": 0.738125,
                    "PressedToPointerOver_Start": 0.750625, "PressedToPointerOver_End": 0.988125]
        }
    }

    func pose(for state: String) -> FluentAnimatedIconPose {
        switch (glyph, state) {
        case (.back, "PointerOver"): return FluentAnimatedIconPose(translation: CGPoint(x: -2, y: 0))
        case (.back, "Pressed"): return FluentAnimatedIconPose(translation: CGPoint(x: -1, y: 0), scale: CGSize(width: 0.85, height: 1))
        case (.chevronDownSmall, "Pressed"): return FluentAnimatedIconPose(translation: CGPoint(x: 0, y: 2))
        case (.settings, "PointerOver"): return FluentAnimatedIconPose(rotation: .pi / 4)
        case (.settings, "Pressed"): return FluentAnimatedIconPose(rotation: .pi / 2, scale: CGSize(width: 0.9, height: 0.9))
        case (.globalNavigationButton, "PointerOver"): return FluentAnimatedIconPose(detail: 1)
        case (.globalNavigationButton, "Pressed"): return FluentAnimatedIconPose(scale: CGSize(width: 0.9, height: 0.9), detail: -1)
        case (.find, "PointerOver"): return FluentAnimatedIconPose(rotation: -.pi / 18)
        case (.find, "Pressed"): return FluentAnimatedIconPose(scale: CGSize(width: 0.88, height: 0.88))
        default: return FluentAnimatedIconPose()
        }
    }

    /// The pose at a timeline progress: inside a segment it eases between the segment's states;
    /// between segments it rests on the preceding segment's end state.
    func pose(at progress: Double) -> FluentAnimatedIconPose {
        let segments = markers.keys.filter { $0.hasSuffix("_Start") }.compactMap { key -> (String, String, Double, Double)? in
            let name = String(key.dropLast("_Start".count))
            guard let start = markers[key], let end = markers["\(name)_End"], let range = name.range(of: "To") else { return nil }
            return (String(name[..<range.lowerBound]), String(name[range.upperBound...]), start, end)
        }
        let epsilon = 0.000001
        // Prefer the longest segment containing the progress; otherwise rest on the segment that
        // ended most recently (ties broken by name so the choice is deterministic).
        let containing = segments.filter { $0.2 <= progress + epsilon && progress <= $0.3 + epsilon && $0.3 > $0.2 }
            .max { ($0.3 - $0.2, $1.0 + $1.1) < ($1.3 - $1.2, $0.0 + $0.1) }
        let ended = segments.filter { $0.3 <= progress + epsilon }
            .max { ($0.3, $1.0 + $1.1) < ($1.3, $0.0 + $0.1) }
        guard let current = containing ?? ended else { return pose(for: "Normal") }
        let span = current.3 - current.2
        let t = span <= 0 ? 1 : min(max((progress - current.2) / span, 0), 1)
        let eased = CGFloat(t * t * (3 - 2 * t))
        return FluentAnimatedIconPose.lerp(pose(for: current.0), pose(for: current.1), eased)
    }

    public func makeVisual() -> FluentAnimatedVisual { FluentBuiltInAnimatedVisual(source: self) }
}

final class FluentBuiltInAnimatedVisual: FluentAnimatedVisual {
    let source: FluentBuiltInAnimatedIconSource
    let rootLayer = CALayer()
    private let glyphLayer = CALayer()
    private var lineLayers: [CAShapeLayer] = []
    private var foreground: NSColor = .labelColor
    private(set) var currentPose = FluentAnimatedIconPose()

    init(source: FluentBuiltInAnimatedIconSource) {
        self.source = source
        rootLayer.bounds = CGRect(origin: .zero, size: source.naturalSize)
        glyphLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(glyphLayer)
        if source.glyph == .globalNavigationButton {
            for _ in 0..<3 {
                let line = CAShapeLayer()
                line.lineWidth = 2.5
                line.lineCap = .round
                glyphLayer.addSublayer(line)
                lineLayers.append(line)
            }
        } else {
            glyphLayer.contentsGravity = .center
        }
        setForeground(foreground)
        setProgress(0)
    }

    private var symbolName: String {
        switch source.glyph {
        case .back: return "arrow.left"
        case .chevronDownSmall: return "chevron.down"
        case .settings: return "gearshape"
        case .globalNavigationButton: return "line.3.horizontal"
        case .find: return "magnifyingglass"
        }
    }

    func setForeground(_ color: NSColor) {
        foreground = color
        if source.glyph == .globalNavigationButton {
            lineLayers.forEach { $0.strokeColor = color.cgColor }
            return
        }
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .regular)) else { return }
        glyphLayer.contents = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        glyphLayer.contentsScale = 2
    }

    func setProgress(_ progress: Double) {
        let pose = source.pose(at: progress)
        currentPose = pose
        // Hosting views are flipped, so positive y in a pose moves the glyph down.
        var transform = CATransform3DMakeTranslation(pose.translation.x, pose.translation.y, 0)
        transform = CATransform3DRotate(transform, -pose.rotation, 0, 0, 1)
        transform = CATransform3DScale(transform, pose.scale.width, pose.scale.height, 1)
        glyphLayer.transform = transform
        guard source.glyph == .globalNavigationButton else { return }
        // Three lines spread apart on hover and draw together when pressed.
        let spacing: CGFloat = 8 + 1.5 * pose.detail
        for (index, line) in lineLayers.enumerated() {
            let y = 24 + CGFloat(index - 1) * spacing
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 11, y: y))
            path.addLine(to: CGPoint(x: 37, y: y))
            line.path = path
        }
    }
}
