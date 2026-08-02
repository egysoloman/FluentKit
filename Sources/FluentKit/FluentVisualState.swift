import AppKit

/// Composable named states shared by FluentKit controls and composite presenters.
///
/// WinUI commonly represents combinations such as `SelectedPointerOver` as a visual-state
/// group rather than as a single Boolean. An option set keeps those combinations explicit while
/// remaining independent from the control's semantic value.
public struct FluentVisualState: OptionSet, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let normal = FluentVisualState(rawValue: 1 << 0)
    public static let pointerOver = FluentVisualState(rawValue: 1 << 1)
    public static let pressed = FluentVisualState(rawValue: 1 << 2)
    public static let selected = FluentVisualState(rawValue: 1 << 3)
    public static let disabled = FluentVisualState(rawValue: 1 << 4)
    public static let focused = FluentVisualState(rawValue: 1 << 5)
    public static let determinate = FluentVisualState(rawValue: 1 << 6)
    public static let indeterminate = FluentVisualState(rawValue: 1 << 7)
    public static let paused = FluentVisualState(rawValue: 1 << 8)
    public static let error = FluentVisualState(rawValue: 1 << 9)

    /// Maps the single-axis control state used by existing Fluent styles into the
    /// named-state vocabulary shared by templates and composite presenters.
    public static func forControlState(_ state: FluentControlState) -> FluentVisualState {
        switch state {
        case .normal: return .normal
        case .pointerOver: return [.normal, .pointerOver]
        case .pressed: return [.normal, .pressed]
        case .disabled: return .disabled
        case .focused: return [.normal, .focused]
        case .selected: return [.normal, .selected]
        case .checked: return [.normal, .selected]
        }
    }

    /// Resolves a combination to the style state precedence used by WinUI common states.
    /// Disabled and pressed suppress hover/focus; selected remains available to controls that
    /// have a separate selection resource group.
    public var primaryControlState: FluentControlState {
        if contains(.disabled) { return .disabled }
        if contains(.pressed) { return .pressed }
        if contains(.pointerOver) { return .pointerOver }
        if contains(.focused) { return .focused }
        if contains(.selected) { return .selected }
        return .normal
    }
}

public struct FluentVisualStateTransition {
    public let from: FluentVisualState
    public let to: FluentVisualState
    public let motion: FluentMotionToken
    public let isAnimated: Bool
    public let changed: Bool

    public init(
        from: FluentVisualState,
        to: FluentVisualState,
        motion: FluentMotionToken,
        isAnimated: Bool,
        changed: Bool
    ) {
        self.from = from
        self.to = to
        self.motion = motion
        self.isAnimated = isAnimated
        self.changed = changed
    }
}

/// Coordinates named visual-state changes and their animation policy.
///
/// The coordinator owns state transition bookkeeping and Reduce Motion policy. A control still
/// owns its native layers; it only needs to map the transition to those layers in one place.
public final class FluentVisualStateCoordinator {
    public private(set) var state: FluentVisualState
    public var reduceMotion: Bool

    public init(
        state: FluentVisualState = .normal,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        self.state = state
        self.reduceMotion = reduceMotion
    }

    @discardableResult
    public func transition(
        to next: FluentVisualState,
        animated: Bool = true,
        motion: FluentMotionToken = FluentMotion.controlFast,
        apply: (FluentVisualStateTransition) -> Void
    ) -> Bool {
        let previous = state
        let changed = previous != next
        state = next
        apply(
            FluentVisualStateTransition(
                from: previous,
                to: next,
                motion: motion,
                isAnimated: changed && animated && !reduceMotion && motion.duration > 0,
                changed: changed
            )
        )
        return changed
    }

    public func reset(to next: FluentVisualState = .normal) {
        state = next
    }
}
