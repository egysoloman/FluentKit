import AppKit

enum FluentPopupRevealEdge {
    case top
    case bottom
}

/// Hosts the popup animation root, its border surface, its content presenter, and a shared clip.
/// MenuPopupThemeTransition moves the root while SplitOpenThemeAnimation changes only the clip;
/// no individual row owns an entrance transform.
final class FluentPopupTransitionHost: NSView {
    let animationRoot: NSView
    let surface: FluentMaterialView
    let content: NSView
    let revealMaskLayer = CALayer()
    let animationCoordinator = FluentAnimationCoordinator()

    init(content: NSView, theme: FluentTheme, cornerRadius: CGFloat, name: String) {
        animationRoot = NSView()
        surface = FluentMaterialView(material: theme.material(for: .transient) ?? .liquidGlass)
        self.content = content
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(name)
        wantsLayer = true
        layer?.name = "\(name).ClipHost"
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
        revealMaskLayer.name = "\(name).RevealClip"
        revealMaskLayer.backgroundColor = NSColor.black.cgColor

        animationRoot.wantsLayer = true
        animationRoot.layer?.name = "\(name).AnimationRoot"
        animationRoot.layer?.masksToBounds = false
        animationRoot.layer?.mask = revealMaskLayer
        addSubview(animationRoot)

        surface.wantsLayer = true
        surface.fluentTheme = theme
        surface.layer?.name = "\(name).PopupBorder"
        surface.layer?.cornerRadius = cornerRadius
        surface.layer?.masksToBounds = true
        surface.isMaterialEnabled = theme.materialEffectsEnabled
        surface.fallbackColor = theme.flyoutSurfaceFill
        surface.tintColor = nil
        surface.layer?.borderWidth = theme.isHighContrast ? 2 : 1
        surface.layer?.borderColor = theme.surfaceStrokeFlyout.cgColor
        animationRoot.addSubview(surface)

        content.wantsLayer = true
        content.layer?.name = "\(name).Presenter"
        animationRoot.addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        animationRoot.frame = bounds
        surface.frame = animationRoot.bounds
        content.frame = animationRoot.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // During an entrance the mask model is already the fully open geometry while its
        // presentation is still clipped. Reassigning frame here would erase that animation.
        if revealMaskLayer.animation(forKey: "fluent.popup.clip.open") == nil,
           revealMaskLayer.bounds.size == .zero {
            revealMaskLayer.frame = bounds
        }
        CATransaction.commit()
    }

    func update(theme: FluentTheme) {
        surface.materialStyle = theme.material(for: .transient) ?? .liquidGlass
        surface.fluentTheme = theme
        surface.isMaterialEnabled = theme.materialEffectsEnabled
        surface.fallbackColor = theme.flyoutSurfaceFill
        surface.layer?.borderWidth = theme.isHighContrast ? 2 : 1
        surface.layer?.borderColor = theme.surfaceStrokeFlyout.cgColor
    }

    /// Theme changes must not leave a popup half-way through its entrance storyboard. The
    /// coordinator cancels the shared timeline first, then commits one fully-open model state so
    /// the newly resolved material and presenter colors are composited without an old clip frame.
    func settleForAppearanceChange() {
        let layers = [
            animationRoot.layer,
            surface.layer,
            content.layer,
            revealMaskLayer,
            layer
        ].compactMap { $0 }
        animationCoordinator.cancelAll(on: layers)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        animationRoot.layer?.transform = CATransform3DIdentity
        surface.layer?.transform = CATransform3DIdentity
        content.layer?.transform = CATransform3DIdentity
        revealMaskLayer.transform = CATransform3DIdentity
        revealMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        revealMaskLayer.frame = animationRoot.bounds
        CATransaction.commit()
    }
}

func fluentPreparePopupEntrance(
    host: FluentPopupTransitionHost,
    edge: FluentPopupRevealEdge,
    motion: FluentMotionToken,
    closedRatio: CGFloat,
    baselineFromTop: CGFloat? = nil,
    reduceMotion: Bool
) {
    guard motion.duration >= 0,
          host.bounds.height > 0,
          host.layer != nil,
          let surfaceLayer = host.surface.layer,
          host.content.layer != nil else { return }

    let ratio = min(max(closedRatio, 0.05), 0.95)
    let fullBounds = host.bounds
    let baselineLayerY: CGFloat
    if let baselineFromTop {
        baselineLayerY = fullBounds.height - baselineFromTop
    } else {
        let initialHeight = max(1, fullBounds.height * ratio)
        baselineLayerY = edge == .top
            ? fullBounds.height - initialHeight / 2
            : initialHeight / 2
    }
    var initialHeight = max(1, fullBounds.height * ratio)
    if baselineFromTop != nil {
        // SplitOpen keeps DropDownOffset as the clip origin. When that origin is too close to an
        // edge for the default half-height clip, WinUI grows the clip instead of shifting its
        // center away from the selected item (ThemeAnimations.cpp, SplitOpenThemeAnimation).
        let offsetFromCenter = abs(baselineLayerY - fullBounds.midY)
        let maximumOffset = fullBounds.height * (1 - ratio) / 2
        if offsetFromCenter > maximumOffset {
            let pixelsOff = initialHeight / 2 - (fullBounds.height / 2 - offsetFromCenter)
            initialHeight += max(0, pixelsOff) * 2
        }
    }
    let initialBounds = NSRect(x: 0, y: 0, width: fullBounds.width, height: initialHeight)
    let offsetFromCenter = abs(baselineLayerY - fullBounds.midY)
    let finalHeight = baselineFromTop == nil
        ? fullBounds.height
        : fullBounds.height + offsetFromCenter * 2
    let finalBounds = NSRect(x: 0, y: 0, width: fullBounds.width, height: finalHeight)
    let initialPosition = NSPoint(x: fullBounds.midX, y: baselineLayerY)
    let finalPosition = baselineFromTop == nil
        ? NSPoint(x: fullBounds.midX, y: fullBounds.midY)
        : initialPosition
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surfaceLayer.transform = CATransform3DIdentity
    host.content.layer?.transform = CATransform3DIdentity
    host.revealMaskLayer.transform = CATransform3DIdentity
    host.revealMaskLayer.bounds = finalBounds
    host.revealMaskLayer.position = finalPosition
    host.revealMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    CATransaction.commit()

    // SplitOpen animates the popup clip around the selected-item offset. Popup rows do not own a
    // translation; the closed faceplate is the separate target in the source template. Submit both
    // properties together so interruption samples one coherent clip state.
    let finalBoundsValue = NSValue(rect: finalBounds)
    let finalPositionValue = NSValue(point: finalPosition)
    host.animationCoordinator.animateTransition(
        [
            FluentLayerAnimationChange(
                layer: host.revealMaskLayer,
                key: "fluent.popup.reveal.bounds",
                keyPath: "bounds",
                fromValue: NSValue(rect: initialBounds),
                toValue: finalBoundsValue
            ) {
                host.revealMaskLayer.bounds = finalBounds
            },
            FluentLayerAnimationChange(
                layer: host.revealMaskLayer,
                key: "fluent.popup.reveal.position",
                keyPath: "position",
                fromValue: NSValue(point: initialPosition),
                toValue: finalPositionValue
            ) {
                host.revealMaskLayer.position = finalPosition
            }
        ],
        motion: motion,
        animated: !reduceMotion
    )
}

/// MenuPopupThemeTransition moves the complete animation root by `openedLength * closedRatio`,
/// applies the inverse translation to its clip, and expands the child border from `1 - closedRatio`.
func fluentPrepareMenuPopupEntrance(
    host: FluentPopupTransitionHost,
    edge: FluentPopupRevealEdge,
    motion: FluentMotionToken,
    closedRatio: CGFloat,
    reduceMotion: Bool
) {
    guard motion.duration >= 0,
          host.bounds.height > 0,
          let animationRootLayer = host.animationRoot.layer,
          let surfaceLayer = host.surface.layer,
          host.content.layer != nil else { return }

    let ratio = min(max(closedRatio, 0.05), 0.95)
    let distance = host.bounds.height * ratio
    // XAML's negative Top translation is a positive Core Animation Y translation. It initially
    // exposes the lower menu rows, then returns the complete presenter downward into place.
    let direction: CGFloat = edge == .top ? 1 : -1
    var closedSurface = CATransform3DMakeScale(1, 1 - ratio, 1)
    closedSurface.m42 = edge == .top ? 0 : distance
    let closedAnimationRoot = CATransform3DMakeTranslation(0, direction * distance, 0)
    let closedClip = CATransform3DMakeTranslation(0, -direction * distance, 0)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    host.revealMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    host.revealMaskLayer.frame = host.bounds
    host.revealMaskLayer.transform = CATransform3DIdentity
    host.layer?.transform = CATransform3DIdentity
    animationRootLayer.transform = CATransform3DIdentity
    surfaceLayer.transform = CATransform3DIdentity
    host.content.layer?.transform = CATransform3DIdentity
    CATransaction.commit()

    let identityValue = NSValue(caTransform3D: CATransform3DIdentity)
    host.animationCoordinator.animateTransition(
        [
            FluentLayerAnimationChange(
                layer: surfaceLayer,
                key: "fluent.popup.border.open",
                keyPath: "transform",
                fromValue: NSValue(caTransform3D: closedSurface),
                toValue: identityValue
            ) {
                surfaceLayer.transform = CATransform3DIdentity
            },
            FluentLayerAnimationChange(
                layer: animationRootLayer,
                key: "fluent.popup.animationRoot.open",
                keyPath: "transform",
                fromValue: NSValue(caTransform3D: closedAnimationRoot),
                toValue: identityValue
            ) {
                animationRootLayer.transform = CATransform3DIdentity
            },
            FluentLayerAnimationChange(
                layer: host.revealMaskLayer,
                key: "fluent.popup.clip.open",
                keyPath: "transform",
                fromValue: NSValue(caTransform3D: closedClip),
                toValue: identityValue
            ) {
                host.revealMaskLayer.transform = CATransform3DIdentity
            }
        ],
        motion: motion,
        animated: !reduceMotion
    )
}
