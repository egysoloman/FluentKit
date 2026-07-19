import AppKit

/// A value that can be sampled between two states for declarative motion.
public protocol FluentInterpolatable {
    static func interpolate(from: Self, to: Self, fraction: CGFloat) -> Self
}

public extension FluentInterpolatable where Self: BinaryFloatingPoint {
    static func interpolate(from: Self, to: Self, fraction: CGFloat) -> Self {
        let amount = Self(fraction)
        return from + (to - from) * amount
    }
}

extension Double: FluentInterpolatable {}
extension Float: FluentInterpolatable {}
extension CGFloat: FluentInterpolatable {}

extension Int: FluentInterpolatable {
    public static func interpolate(from: Int, to: Int, fraction: CGFloat) -> Int {
        let lower = CGFloat(from)
        let delta = CGFloat(to) - lower
        return Int((lower + delta * fraction).rounded())
    }
}

extension CGPoint: FluentInterpolatable {
    public static func interpolate(from: CGPoint, to: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }
}

extension CGSize: FluentInterpolatable {
    public static func interpolate(from: CGSize, to: CGSize, fraction: CGFloat) -> CGSize {
        CGSize(width: from.width + (to.width - from.width) * fraction, height: from.height + (to.height - from.height) * fraction)
    }
}

extension CGRect: FluentInterpolatable {
    public static func interpolate(from: CGRect, to: CGRect, fraction: CGFloat) -> CGRect {
        CGRect(origin: CGPoint.interpolate(from: from.origin, to: to.origin, fraction: fraction), size: CGSize.interpolate(from: from.size, to: to.size, fraction: fraction))
    }
}

extension CGAffineTransform: FluentInterpolatable {
    public static func interpolate(from: CGAffineTransform, to: CGAffineTransform, fraction: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(
            a: from.a + (to.a - from.a) * fraction,
            b: from.b + (to.b - from.b) * fraction,
            c: from.c + (to.c - from.c) * fraction,
            d: from.d + (to.d - from.d) * fraction,
            tx: from.tx + (to.tx - from.tx) * fraction,
            ty: from.ty + (to.ty - from.ty) * fraction
        )
    }
}

extension NSEdgeInsets: FluentInterpolatable {
    public static func interpolate(from: NSEdgeInsets, to: NSEdgeInsets, fraction: CGFloat) -> NSEdgeInsets {
        return NSEdgeInsets(
            top: from.top + (to.top - from.top) * fraction,
            left: from.left + (to.left - from.left) * fraction,
            bottom: from.bottom + (to.bottom - from.bottom) * fraction,
            right: from.right + (to.right - from.right) * fraction
        )
    }
}

extension NSColor: FluentInterpolatable {
    public static func interpolate(from: NSColor, to: NSColor, fraction: CGFloat) -> Self {
        let amount = min(max(fraction, 0), 1)
        guard let source = from.usingColorSpace(.extendedSRGB),
              let destination = to.usingColorSpace(.extendedSRGB) else {
            return self.init(cgColor: (amount < 0.5 ? from : to).cgColor)!
        }
        return self.init(
            colorSpace: .extendedSRGB,
            components: [
                source.redComponent + (destination.redComponent - source.redComponent) * amount,
                source.greenComponent + (destination.greenComponent - source.greenComponent) * amount,
                source.blueComponent + (destination.blueComponent - source.blueComponent) * amount,
                source.alphaComponent + (destination.alphaComponent - source.alphaComponent) * amount
            ],
            count: 4
        )
    }
}

/// A spring response used by FluentAnimatedValue.
public struct FluentSpringAnimation: Sendable {
    public let mass: CGFloat
    public let stiffness: CGFloat
    public let damping: CGFloat
    public let initialVelocity: CGFloat

    public init(mass: CGFloat = 1, stiffness: CGFloat = 180, damping: CGFloat = 20, initialVelocity: CGFloat = 0) {
        self.mass = max(mass, 0.01)
        self.stiffness = max(stiffness, 0.01)
        self.damping = max(damping, 0)
        self.initialVelocity = initialVelocity
    }

    public var settlingDuration: TimeInterval {
        let angularFrequency = sqrt(stiffness / mass)
        let dampingRatio = damping / (2 * sqrt(stiffness * mass))
        guard angularFrequency.isFinite, angularFrequency > 0 else { return 0 }
        let decay = max(dampingRatio * angularFrequency, angularFrequency * 0.08)
        return min(max(4 / decay, 0.12), 3)
    }

    fileprivate func progress(at time: TimeInterval) -> CGFloat {
        let t = max(time, 0)
        let angularFrequency = sqrt(stiffness / mass)
        let dampingRatio = damping / (2 * sqrt(stiffness * mass))
        guard angularFrequency.isFinite, angularFrequency > 0 else { return 1 }
        let value: CGFloat
        if dampingRatio < 1 {
            let dampedFrequency = angularFrequency * sqrt(max(1 - dampingRatio * dampingRatio, 0))
            let initialDisplacement: CGFloat = -1
            let coefficient = (initialVelocity + dampingRatio * angularFrequency * initialDisplacement) / max(dampedFrequency, 0.0001)
            let envelope = exp(-dampingRatio * angularFrequency * t)
            let displacement = envelope * (initialDisplacement * cos(dampedFrequency * t) + coefficient * sin(dampedFrequency * t))
            value = 1 + displacement
        } else {
            let envelope = exp(-angularFrequency * t)
            value = 1 - envelope * (1 + angularFrequency * t)
        }
        return min(max(value, -0.2), 1.2)
    }
}

/// A normalized keyframe for a declarative value animation.
public struct FluentKeyframe<Value: FluentInterpolatable> {
    public let offset: CGFloat
    public let value: Value

    public init(offset: CGFloat, value: Value) {
        self.offset = min(max(offset, 0), 1)
        self.value = value
    }
}

/// A sequence of absolute values sampled over a normalized timeline.
public struct FluentKeyframeAnimation<Value: FluentInterpolatable> {
    public let keyframes: [FluentKeyframe<Value>]
    public let duration: TimeInterval
    public let curve: FluentAnimationCurve

    public init(keyframes: [FluentKeyframe<Value>], duration: TimeInterval = FluentAnimation.content, curve: FluentAnimationCurve = .easeInOut) {
        let sorted = keyframes.enumerated().sorted { lhs, rhs in
            lhs.element.offset == rhs.element.offset
                ? lhs.offset < rhs.offset
                : lhs.element.offset < rhs.element.offset
        }.map(\.element)
        var normalized: [FluentKeyframe<Value>] = []
        for frame in sorted {
            if normalized.last?.offset == frame.offset {
                normalized[normalized.count - 1] = frame
            } else {
                normalized.append(frame)
            }
        }
        self.keyframes = normalized
        self.duration = max(duration, 0)
        self.curve = curve
    }

    /// Samples the timeline without starting an animation. This is useful for previews, tests,
    /// and custom renderers that drive their own display clock.
    public func value(at progress: CGFloat, from initialValue: Value) -> Value {
        var frames = keyframes
        guard !frames.isEmpty else { return initialValue }
        if frames[0].offset > 0 {
            frames.insert(FluentKeyframe(offset: 0, value: initialValue), at: 0)
        }
        if frames.last?.offset ?? 0 < 1, let last = frames.last {
            frames.append(FluentKeyframe(offset: 1, value: last.value))
        }

        let timeline = curve.progress(at: progress)
        guard let upperIndex = frames.firstIndex(where: { $0.offset >= timeline }) else {
            return frames[frames.count - 1].value
        }
        guard upperIndex > 0 else { return frames[0].value }
        let lower = frames[upperIndex - 1]
        let upper = frames[upperIndex]
        let span = upper.offset - lower.offset
        guard span > 0 else { return upper.value }
        return Value.interpolate(
            from: lower.value,
            to: upper.value,
            fraction: (timeline - lower.offset) / span
        )
    }
}

/// A value source that animates on the main run loop while remaining observable by Fluent views.
public final class FluentAnimatedValue<Value: FluentInterpolatable> {
    public let observable: FluentObservable<Value>
    public private(set) var targetValue: Value
    private var timer: Timer?
    private var generation = 0
    private var completion: (() -> Void)?

    public init(_ value: Value) {
        observable = FluentObservable(value)
        targetValue = value
    }

    public var value: Value { observable.value }
    public var isAnimating: Bool { timer?.isValid == true }

    public var binding: FluentBinding<Value> {
        FluentBinding(get: { self.value }, set: { self.set($0) }, observe: { self.observable.observe($0, notifyImmediately: false) }, removeObserver: { self.observable.removeObserver($0) })
    }

    public func set(
        _ value: Value,
        animation: FluentAnimationTransaction? = nil,
        reduceMotion: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        performOnMain { [weak self] in
            guard let self else { return }
            self.cancelTimer()
            self.targetValue = value
            self.completion = completion
            guard let animation, animation.duration > 0, !Self.shouldReduceMotion(reduceMotion) else {
                self.observable.value = value
                self.completeAnimation()
                return
            }
            self.animate(from: self.observable.value, to: value, duration: animation.duration) { progress in
                animation.progress(at: progress)
            }
        }
    }

    public func set(
        _ value: Value,
        spring: FluentSpringAnimation,
        reduceMotion: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        performOnMain { [weak self] in
            guard let self else { return }
            self.cancelTimer()
            self.targetValue = value
            self.completion = completion
            let duration = spring.settlingDuration
            guard duration > 0, !Self.shouldReduceMotion(reduceMotion) else {
                self.observable.value = value
                self.completeAnimation()
                return
            }
            self.animate(from: self.observable.value, to: value, duration: duration) { progress in
                spring.progress(at: duration * TimeInterval(progress))
            }
        }
    }

    public func animate(
        using animation: FluentKeyframeAnimation<Value>,
        reduceMotion: Bool? = nil,
        completion: (() -> Void)? = nil
    ) {
        performOnMain { [weak self] in
            guard let self else { return }
            self.cancelTimer()
            guard !animation.keyframes.isEmpty else { return }
            let current = self.observable.value
            self.targetValue = animation.value(at: 1, from: current)
            self.completion = completion
            guard animation.duration > 0, !Self.shouldReduceMotion(reduceMotion) else {
                self.observable.value = self.targetValue
                self.completeAnimation()
                return
            }
            self.animate(duration: animation.duration) { progress in
                animation.value(at: progress, from: current)
            }
        }
    }

    /// Stops an active animation and preserves its currently sampled value.
    public func stop() { performOnMain { [weak self] in self?.cancelTimer() } }

    /// Stops an active animation and writes its exact target value.
    public func finish() {
        performOnMain { [weak self] in
            guard let self else { return }
            self.cancelTimer(preserveCompletion: true)
            self.observable.value = self.targetValue
            self.completeAnimation()
        }
    }

    private func animate(from: Value, to: Value, duration: TimeInterval, sample: @escaping (CGFloat) -> CGFloat) {
        animate(duration: duration) { progress in
            Value.interpolate(from: from, to: to, fraction: sample(progress))
        }
    }

    private func animate(duration: TimeInterval, sample: @escaping (CGFloat) -> Value) {
        generation += 1
        let currentGeneration = generation
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, self.generation == currentGeneration else { timer.invalidate(); return }
            let fraction = min(max(Date().timeIntervalSince(start) / duration, 0), 1)
            self.observable.value = sample(CGFloat(fraction))
            if fraction >= 1 {
                timer.invalidate()
                self.timer = nil
                self.observable.value = self.targetValue
                self.completeAnimation()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func cancelTimer(preserveCompletion: Bool = false) {
        generation += 1
        timer?.invalidate()
        timer = nil
        if !preserveCompletion { completion = nil }
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func completeAnimation() {
        let completion = completion
        self.completion = nil
        completion?()
    }

    private static func shouldReduceMotion(_ override: Bool?) -> Bool {
        override ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    deinit { timer?.invalidate() }
}

/// A property wrapper whose assignments animate with a configurable default transaction.
@propertyWrapper
public final class FluentAnimatedState<Value: FluentInterpolatable> {
    private let storage: FluentAnimatedValue<Value>
    private let defaultAnimation: FluentAnimationTransaction?

    public init(wrappedValue: Value) {
        storage = FluentAnimatedValue(wrappedValue)
        defaultAnimation = FluentAnimationTransaction()
    }

    public init(wrappedValue: Value, animation: FluentAnimationTransaction?) {
        storage = FluentAnimatedValue(wrappedValue)
        defaultAnimation = animation
    }

    public var wrappedValue: Value {
        get { storage.value }
        set { storage.set(newValue, animation: defaultAnimation) }
    }

    public var projectedValue: FluentBinding<Value> { storage.binding }
    public var animatedValue: FluentAnimatedValue<Value> { storage }

    public func animate(to value: Value, spring: FluentSpringAnimation) { storage.set(value, spring: spring) }
    public func animate(using animation: FluentKeyframeAnimation<Value>) { storage.animate(using: animation) }
    public func stopAnimation() { storage.stop() }
}
