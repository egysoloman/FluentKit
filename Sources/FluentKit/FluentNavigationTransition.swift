import AppKit

/// Selects the page choreography owned by `FluentNavigationView`.
public enum FluentNavigationTransitionMode: String, CaseIterable, Hashable, Sendable {
    /// Uses WinUI's NavigationView recommendation: Slide for ordered Top items and Entrance elsewhere.
    case automatic
    /// Replaces content without motion.
    case none
    /// Cross-fades the outgoing and incoming pages.
    case crossFade
    /// Uses the directional SlideNavigationTransitionInfo choreography.
    case slide
    /// Uses the scale and opacity choreography from DrillInNavigationTransitionInfo.
    case drillIn
    /// Uses the vertical EntranceNavigationTransitionInfo choreography.
    case entrance
    /// Always brings the incoming page from the lower edge into place. This is useful for
    /// gallery-style content browsing where the visual direction is fixed rather than tied to
    /// the relative order of destination IDs.
    case bottomUp
    /// Explicitly suppresses navigation motion while preserving the navigation operation.
    case suppress
}

enum FluentNavigationTransitionDirection: Equatable {
    case backward
    case forward
    case neutral
}

private enum FluentNavigationVerticalEdge {
    case top
    case bottom
}

final class FluentNavigationContentPresenter<ID: Hashable>: NSView {
    private var current: FluentNavigationContentEntry
    private var currentIdentity: ID?
    private let animationCoordinator: FluentAnimationCoordinator
    private var transitionGeneration: UInt64 = 0
    private var appliedTheme: FluentTheme

    init(content: FluentAnyView, identity: ID?, context: FluentRenderContext) {
        currentIdentity = identity
        current = FluentNavigationContentEntry(content: content, context: context)
        animationCoordinator = FluentAnimationCoordinator(reduceMotion: context.reduceMotion)
        appliedTheme = context.theme
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.Content")
        wantsLayer = true
        layer?.name = "FluentKit.NavigationView.ContentPresenter"
        layer?.masksToBounds = true
        addPage(current)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        content: FluentAnyView,
        identity: ID?,
        orderedIDs: [ID],
        primaryIDs: Set<ID>,
        mode requestedMode: FluentNavigationTransitionMode,
        isTopNavigation: Bool,
        context: FluentRenderContext
    ) {
        let previousIdentity = currentIdentity
        let direction = transitionDirection(
            from: previousIdentity,
            to: identity,
            orderedIDs: orderedIDs
        )
        let mode = resolvedMode(
            requestedMode,
            from: previousIdentity,
            to: identity,
            primaryIDs: primaryIDs,
            isTopNavigation: isTopNavigation
        )
        replace(
            content: content,
            identity: identity,
            direction: direction,
            mode: mode,
            context: context
        )
    }

    func update(
        content: FluentAnyView,
        identity: ID?,
        direction: FluentNavigationTransitionDirection,
        mode: FluentNavigationTransitionMode,
        context: FluentRenderContext
    ) {
        replace(
            content: content,
            identity: identity,
            direction: direction,
            mode: mode,
            context: context
        )
    }

    private func replace(
        content: FluentAnyView,
        identity: ID?,
        direction: FluentNavigationTransitionDirection,
        mode: FluentNavigationTransitionMode,
        context: FluentRenderContext
    ) {
        let appearanceDidChange = appliedTheme != context.theme
        let reduceMotionWasEnabled = context.reduceMotion && !animationCoordinator.reduceMotion
        appliedTheme = context.theme
        animationCoordinator.reduceMotion = context.reduceMotion
        if appearanceDidChange || reduceMotionWasEnabled {
            transitionGeneration &+= 1
            settle(on: current)
        }
        guard currentIdentity != identity else {
            current.update(content: content, context: context)
            return
        }

        let replacement = FluentNavigationContentEntry(content: content, context: context)
        addPage(replacement)
        layoutSubtreeIfNeeded()

        let outgoing = current
        current = replacement
        currentIdentity = identity
        transitionGeneration &+= 1
        let generation = transitionGeneration

        removeSupersededEntries(keeping: outgoing, replacement)
        guard !appearanceDidChange,
              !context.reduceMotion,
              mode != .none,
              mode != .suppress else {
            settle(on: replacement)
            return
        }

        animate(
            mode: mode,
            direction: direction,
            outgoing: outgoing,
            incoming: replacement,
            isRightToLeft: context.layoutDirection.appKitValue == .rightToLeft
        )
        scheduleOutgoingRemoval(
            generation: generation,
            outgoing: outgoing,
            duration: outgoingDuration(for: mode)
        )
        scheduleCleanup(generation: generation, incoming: replacement, duration: duration(for: mode, direction: direction))
    }

    deinit {
        let layers = subviews.compactMap(\.layer) + [layer].compactMap { $0 }
        animationCoordinator.cancelAll(on: layers)
    }

    private func addPage(_ entry: FluentNavigationContentEntry) {
        entry.frame = bounds
        entry.autoresizingMask = [.width, .height]
        addSubview(entry)
    }

    private func transitionDirection(from old: ID?, to new: ID?, orderedIDs: [ID]) -> FluentNavigationTransitionDirection {
        guard let old,
              let new,
              let oldIndex = orderedIDs.firstIndex(of: old),
              let newIndex = orderedIDs.firstIndex(of: new),
              oldIndex != newIndex else { return .neutral }
        return oldIndex < newIndex ? .forward : .backward
    }

    private func resolvedMode(
        _ requestedMode: FluentNavigationTransitionMode,
        from old: ID?,
        to new: ID?,
        primaryIDs: Set<ID>,
        isTopNavigation: Bool
    ) -> FluentNavigationTransitionMode {
        guard requestedMode == .automatic else { return requestedMode }
        guard isTopNavigation,
              let old,
              let new,
              primaryIDs.contains(old),
              primaryIDs.contains(new) else { return .entrance }
        return .slide
    }

    private func removeSupersededEntries(
        keeping outgoing: FluentNavigationContentEntry,
        _ incoming: FluentNavigationContentEntry
    ) {
        for entry in subviews.compactMap({ $0 as? FluentNavigationContentEntry })
            where entry !== outgoing && entry !== incoming {
            if let layer = entry.layer { animationCoordinator.cancelAll(on: [layer]) }
            entry.removeFromSuperview()
        }
    }

    private func animate(
        mode: FluentNavigationTransitionMode,
        direction: FluentNavigationTransitionDirection,
        outgoing: FluentNavigationContentEntry,
        incoming: FluentNavigationContentEntry,
        isRightToLeft: Bool
    ) {
        switch mode {
        case .automatic, .none, .suppress:
            break
        case .crossFade:
            animateOpacity(outgoing, from: nil, to: 0, motion: FluentMotion.controlNormal)
            animateOpacity(incoming, from: 0, to: 1, motion: FluentMotion.controlNormal)
        case .slide:
            animateSlide(
                direction: direction,
                outgoing: outgoing,
                incoming: incoming,
                isRightToLeft: isRightToLeft
            )
        case .drillIn:
            animateDrill(direction: direction, outgoing: outgoing, incoming: incoming)
        case .entrance:
            animateEntrance(direction: direction, outgoing: outgoing, incoming: incoming)
        case .bottomUp:
            animateBottomUp(outgoing: outgoing, incoming: incoming)
        }
    }

    private func animateSlide(
        direction: FluentNavigationTransitionDirection,
        outgoing: FluentNavigationContentEntry,
        incoming: FluentNavigationContentEntry,
        isRightToLeft: Bool
    ) {
        let logicalSign: CGFloat = direction == .backward ? -1 : 1
        let visualSign = logicalSign * (isRightToLeft ? -1 : 1)
        animateTransform(
            outgoing,
            from: nil,
            to: CGAffineTransform(translationX: -visualSign * FluentMotion.navigationPageSlideExit.distance, y: 0),
            motion: FluentMotion.navigationPageSlideExit
        )
        animateOpacity(outgoing, from: nil, to: 0, motion: discreteMotion(at: 0.149))
        animateTransform(
            incoming,
            from: CGAffineTransform(translationX: visualSign * FluentMotion.navigationPageSlideEntrance.distance, y: 0),
            to: .identity,
            motion: FluentMotion.navigationPageSlideEntrance
        )
        animateOpacity(incoming, from: 0, to: 1, motion: discreteMotion(at: 0.150))
    }

    private func animateEntrance(
        direction: FluentNavigationTransitionDirection,
        outgoing: FluentNavigationContentEntry,
        incoming: FluentNavigationContentEntry
    ) {
        // WinUI's EntranceNavigationTransitionInfo is deliberately asymmetric. Forward
        // navigation fades the old page while the new page waits 150ms and enters from below;
        // back navigation moves the old page down, while the destination only fades in after
        // that outgoing phase. Keep those triggers separate instead of mirroring the motion.
        if direction == .backward {
            let outgoingOffset = verticalOffset(for: .bottom, in: outgoing)
            animateTransform(
                outgoing,
                from: nil,
                to: CGAffineTransform(translationX: 0, y: outgoingOffset),
                motion: FluentMotion.navigationPageExit
            )
            animateOpacity(outgoing, from: nil, to: 0, motion: discreteMotion(at: 0.149))
            animateOpacity(incoming, from: 0, to: 1, motion: FluentMotion.navigationPageEntrance)
            return
        }

        let incomingOffset = verticalOffset(for: .bottom, in: incoming)
        animateOpacity(outgoing, from: nil, to: 0, motion: FluentMotion.navigationPageExit)
        animateTransform(
            incoming,
            from: CGAffineTransform(translationX: 0, y: incomingOffset),
            to: .identity,
            motion: FluentMotion.navigationPageEntrance
        )
        animateOpacity(incoming, from: 0, to: 1, motion: discreteMotion(at: 0.150))
    }

    private func animateBottomUp(
        outgoing: FluentNavigationContentEntry,
        incoming: FluentNavigationContentEntry
    ) {
        // Gallery's bottomUp mode is intentionally independent of navigation order: every
        // destination enters from the logical lower edge, including backward selection.
        let incomingOffset = verticalOffset(for: .bottom, in: incoming)
        let outgoingOffset = verticalOffset(for: .top, in: outgoing)
        animateTransform(
            outgoing,
            from: nil,
            to: CGAffineTransform(translationX: 0, y: outgoingOffset),
            motion: FluentMotion.navigationPageExit
        )
        animateOpacity(outgoing, from: nil, to: 0, motion: discreteMotion(at: 0.149))
        animateTransform(
            incoming,
            from: CGAffineTransform(translationX: 0, y: incomingOffset),
            to: .identity,
            motion: FluentMotion.navigationPageEntrance
        )
        animateOpacity(incoming, from: 0, to: 1, motion: discreteMotion(at: 0.150))
    }

    private func verticalOffset(
        for edge: FluentNavigationVerticalEdge,
        in entry: FluentNavigationContentEntry
    ) -> CGFloat {
        let distance = FluentMotion.navigationPageEntrance.distance
        switch edge {
        case .top:
            return entry.isFlipped ? -distance : distance
        case .bottom:
            return entry.isFlipped ? distance : -distance
        }
    }

    private func animateDrill(
        direction: FluentNavigationTransitionDirection,
        outgoing: FluentNavigationContentEntry,
        incoming: FluentNavigationContentEntry
    ) {
        let isBack = direction == .backward
        let outgoingScale: CGFloat = isBack ? 0.96 : FluentMotion.navigationDrillExit.scale
        let incomingScale: CGFloat = isBack
            ? FluentMotion.navigationDrillBackEntrance.scale
            : FluentMotion.navigationDrillInScale.scale
        let incomingScaleMotion = isBack
            ? FluentMotion.navigationDrillBackEntrance
            : FluentMotion.navigationDrillInScale

        animateTransform(
            outgoing,
            from: nil,
            to: CGAffineTransform(scaleX: outgoingScale, y: outgoingScale),
            motion: FluentMotion.navigationDrillExit
        )
        animateOpacity(outgoing, from: nil, to: 0, motion: drillExitOpacityMotion)
        animateTransform(
            incoming,
            from: CGAffineTransform(scaleX: incomingScale, y: incomingScale),
            to: .identity,
            motion: incomingScaleMotion
        )
        animateOpacity(incoming, from: 0, to: 1, motion: FluentMotion.navigationDrillInOpacity)
    }

    private var drillExitOpacityMotion: FluentMotionToken {
        FluentMotionToken(
            duration: FluentMotion.navigationDrillExit.duration,
            curve: FluentMotion.navigationDrillInOpacity.curve
        )
    }

    private func discreteMotion(at delay: TimeInterval) -> FluentMotionToken {
        FluentMotionToken(duration: 0.001, curve: .linear, delay: delay)
    }

    private func animateOpacity(
        _ entry: FluentNavigationContentEntry,
        from: Float?,
        to: Float,
        motion: FluentMotionToken
    ) {
        guard let layer = entry.layer else { return }
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: layer,
                    key: "fluent.navigation.page.opacity",
                    keyPath: "opacity",
                    fromValue: from,
                    toValue: to
                ) { [layer] in layer.opacity = to }
            ],
            motion: motion,
            animated: true
        )
    }

    private func animateTransform(
        _ entry: FluentNavigationContentEntry,
        from: CGAffineTransform?,
        to: CGAffineTransform,
        motion: FluentMotionToken
    ) {
        guard let layer = entry.layer else { return }
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: layer,
                    key: "fluent.navigation.page.transform",
                    keyPath: "transform",
                    fromValue: from.map { NSValue(caTransform3D: CATransform3DMakeAffineTransform($0)) },
                    toValue: NSValue(caTransform3D: CATransform3DMakeAffineTransform(to))
                ) { [layer] in layer.setAffineTransform(to) }
            ],
            motion: motion,
            animated: true
        )
    }

    private func duration(
        for mode: FluentNavigationTransitionMode,
        direction: FluentNavigationTransitionDirection
    ) -> TimeInterval {
        switch mode {
        case .automatic, .none, .suppress: return 0
        case .crossFade: return FluentMotion.controlNormal.duration
        case .slide, .entrance, .bottomUp:
            return FluentMotion.navigationPageEntrance.delay + FluentMotion.navigationPageEntrance.duration
        case .drillIn:
            return direction == .backward
                ? FluentMotion.navigationDrillBackEntrance.duration
                : FluentMotion.navigationDrillInScale.duration
        }
    }

    private func outgoingDuration(for mode: FluentNavigationTransitionMode) -> TimeInterval {
        switch mode {
        case .automatic, .none, .suppress: return 0
        case .crossFade: return FluentMotion.controlNormal.duration
        case .slide, .entrance, .bottomUp: return FluentMotion.navigationPageExit.duration
        case .drillIn: return FluentMotion.navigationDrillExit.duration
        }
    }

    private func scheduleOutgoingRemoval(
        generation: UInt64,
        outgoing: FluentNavigationContentEntry,
        duration: TimeInterval
    ) {
        guard let layer = outgoing.layer else {
            outgoing.removeFromSuperview()
            return
        }
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: layer,
                    key: "fluent.navigation.page.outgoing.cleanup",
                    keyPath: "zPosition",
                    toValue: layer.zPosition
                ) {}
            ],
            motion: FluentMotionToken(duration: duration, curve: .linear),
            animated: true
        ) { [weak self, weak outgoing] in
            guard let self,
                  let outgoing,
                  self.transitionGeneration == generation,
                  self.current !== outgoing else { return }
            outgoing.removeFromSuperview()
        }
    }

    private func scheduleCleanup(
        generation: UInt64,
        incoming: FluentNavigationContentEntry,
        duration: TimeInterval
    ) {
        guard let layer else {
            settle(on: incoming)
            return
        }
        animationCoordinator.animateTransition(
            [
                FluentLayerAnimationChange(
                    layer: layer,
                    key: "fluent.navigation.page.cleanup",
                    keyPath: "opacity",
                    toValue: layer.opacity
                ) {}
            ],
            motion: FluentMotionToken(duration: duration, curve: .linear),
            animated: true
        ) { [weak self, weak incoming] in
            guard let self,
                  let incoming,
                  self.transitionGeneration == generation,
                  self.current === incoming else { return }
            self.settle(on: incoming)
        }
    }

    private func settle(on entry: FluentNavigationContentEntry) {
        let entries = subviews.compactMap { $0 as? FluentNavigationContentEntry }
        animationCoordinator.cancelAll(on: entries.compactMap(\.layer) + [layer].compactMap { $0 })
        for candidate in entries where candidate !== entry {
            candidate.removeFromSuperview()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        entry.layer?.opacity = 1
        entry.layer?.setAffineTransform(.identity)
        CATransaction.commit()
    }
}

private final class FluentNavigationContentEntry: NSView {
    let host: FluentViewHost<FluentAnyView>

    init(content: FluentAnyView, context: FluentRenderContext) {
        host = FluentViewHost(content, context: context)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.ContentEntry")
        wantsLayer = true
        layer?.name = "FluentKit.NavigationView.ContentEntry"
        host.identifier = NSUserInterfaceItemIdentifier("FluentKit.NavigationView.ContentPage")
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(content: FluentAnyView, context: FluentRenderContext) {
        host.context = context
        host.update(content)
    }
}

extension FluentNavigationContentPresenter: FluentAppearanceParticipant {
    func prepareForFluentAppearanceChange() {
        transitionGeneration &+= 1
        settle(on: current)
    }

    func applyFluentAppearance(_ theme: FluentTheme) {
        // The owning FluentViewHost applies the new render context to this presenter. Keeping the
        // participant here is intentional: it lets the coordinator settle the page timeline first.
    }
}
