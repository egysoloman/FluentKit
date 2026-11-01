import XCTest
@testable import FluentKit

final class FluentKitTests: XCTestCase {
    @MainActor
    func testToolTipSourceGeometryAccessibilityAndDeclarativeIdentity() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(
            theme: FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false),
            reduceMotion: true
        )
        let host = FluentViewHost(
            FluentButtonView("ToolTip anchor").toolTip("Short help"),
            context: context
        )
        let toolTipHost = try XCTUnwrap(host.subviews.first as? FluentToolTipHost)
        let anchor = toolTipHost.contentView
        XCTAssertEqual(anchor.accessibilityHelp(), "Short help")

        let nativeIdentity = ObjectIdentifier(toolTipHost)
        host.update(FluentButtonView("ToolTip anchor").toolTip("Updated help", placement: .left))
        XCTAssertEqual(ObjectIdentifier(try XCTUnwrap(host.subviews.first as? FluentToolTipHost)), nativeIdentity)
        XCTAssertEqual(anchor.accessibilityHelp(), "Updated help")

        let surface = FluentToolTipSurface(content: toolTipHost.toolTipView, context: context)
        let size = surface.measure(maximumHeight: 600)
        surface.frame = NSRect(origin: .zero, size: size)
        surface.layoutSubtreeIfNeeded()
        XCTAssertEqual(surface.layer?.cornerRadius ?? -1, 4, accuracy: 0.001)
        let material = try XCTUnwrap(surface.subviews.first as? FluentMaterialView)
        XCTAssertEqual(material.materialStyle, .acrylic)
        XCTAssertEqual(material.layer?.borderWidth ?? -1, 1, accuracy: 0.001)
        XCTAssertLessThanOrEqual(size.width, 320)
        XCTAssertEqual(toolTipHost.toolTipView.frame.minX, 9, accuracy: 0.001)
        XCTAssertEqual(toolTipHost.toolTipView.frame.minY, 8, accuracy: 0.001)
        XCTAssertEqual(surface.accessibilityRole(), .helpTag)

        let longLabel = FluentToolTipText(
            "WinUI-aligned pointer delay, safe-zone dismissal, and screen-edge fallback."
        )._mount(in: context)
        let wrappedSurface = FluentToolTipSurface(content: longLabel, context: context)
        let wrappedSize = wrappedSurface.measure(maximumHeight: 600)
        XCTAssertEqual(wrappedSize.width, 320, accuracy: 0.001)
        XCTAssertGreaterThan(wrappedSize.height, 29, "constraining width must remeasure wrapped text height")

        let panel = FluentToolTipPanel(contentRect: NSRect(origin: .zero, size: size))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)

        anchor.setAccessibilityHelp("Anchor help")
        host.update(FluentButtonView("ToolTip anchor").toolTip("Disabled", isEnabled: false))
        XCTAssertEqual(anchor.accessibilityHelp(), "Anchor help")
    }

    @MainActor
    func testToolTipSafeZoneUsesOwnerTooltipConvexHull() {
        let owner = NSRect(x: 0, y: 0, width: 40, height: 30)
        let tip = NSRect(x: 100, y: 50, width: 80, height: 30)
        XCTAssertTrue(FluentToolTipHost.point(NSPoint(x: 20, y: 15), isInsideConvexHullOf: owner, and: tip))
        XCTAssertTrue(FluentToolTipHost.point(NSPoint(x: 130, y: 65), isInsideConvexHullOf: owner, and: tip))
        XCTAssertTrue(
            FluentToolTipHost.point(NSPoint(x: 70, y: 40), isInsideConvexHullOf: owner, and: tip),
            "the corridor between owner and ToolTip remains safe"
        )
        XCTAssertFalse(FluentToolTipHost.point(NSPoint(x: 10, y: 90), isInsideConvexHullOf: owner, and: tip))
    }

    @MainActor
    func testToolTipExclusivePendingOwnerCancelsEarlierDelay() throws {
        _ = NSApplication.shared
        let firstHost = FluentViewHost(
            FluentButtonView("First").toolTip("First help"),
            context: FluentRenderContext(reduceMotion: true)
        )
        let secondHost = FluentViewHost(
            FluentButtonView("Second").toolTip("Second help"),
            context: FluentRenderContext(reduceMotion: true)
        )
        firstHost.frame = NSRect(x: 50, y: 100, width: 100, height: 32)
        secondHost.frame = NSRect(x: 220, y: 100, width: 100, height: 32)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        root.addSubview(firstHost)
        root.addSubview(secondHost)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 420, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        root.layoutSubtreeIfNeeded()
        let first = try XCTUnwrap(firstHost.subviews.first as? FluentToolTipHost)
        let second = try XCTUnwrap(secondHost.subviews.first as? FluentToolTipHost)

        func entered(_ host: FluentToolTipHost, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved,
                location: host.convert(NSPoint(x: 20, y: 16), to: nil),
                modifierFlags: [],
                timestamp: TimeInterval(number),
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 0,
                pressure: 0
            ))
        }
        first.mouseEntered(with: try entered(first, number: 10))
        second.mouseEntered(with: try entered(second, number: 11))
        second.dismiss(animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(window.childWindows?.isEmpty != false, "the superseded owner cannot open")
        second.mouseEntered(with: try entered(second, number: 12))
        waitForUI(window.childWindows?.first?.isVisible == true)
        let panel = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(
            ((panel.contentView as? FluentToolTipSurface)?.content as? NSTextField)?.stringValue,
            "Second help"
        )
        second.dismiss(animated: false)
    }

    @MainActor
    func testToolTipPointerDelayCancelAndAutomaticPresentation() throws {
        _ = NSApplication.shared
        let host = FluentViewHost(
            FluentButtonView("Hover target").toolTip("Delayed help"),
            context: FluentRenderContext(reduceMotion: true)
        )
        host.frame = NSRect(x: 120, y: 100, width: 120, height: 32)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        root.addSubview(host)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 420, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        root.layoutSubtreeIfNeeded()
        let toolTipHost = try XCTUnwrap(host.subviews.first as? FluentToolTipHost)
        defer { toolTipHost.dismiss(animated: false) }

        func event(_ type: NSEvent.EventType, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: toolTipHost.convert(NSPoint(x: 30, y: 16), to: nil),
                modifierFlags: [],
                timestamp: TimeInterval(number),
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 0,
                pressure: 0
            ))
        }

        toolTipHost.mouseEntered(with: try event(.mouseMoved, number: 1))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        toolTipHost.mouseExited(with: try event(.mouseMoved, number: 2))
        RunLoop.main.run(until: Date().addingTimeInterval(0.85))
        XCTAssertTrue(window.childWindows?.isEmpty != false, "leaving before the delay cancels opening")

        toolTipHost.mouseEntered(with: try event(.mouseMoved, number: 3))
        waitForUI(window.childWindows?.first?.isVisible == true)
        let panel = try XCTUnwrap(window.childWindows?.first as? FluentToolTipPanel)
        XCTAssertEqual(panel.contentView?.identifier?.rawValue, "FluentKit.ToolTip.Surface")
        XCTAssertTrue(panel.ignoresMouseEvents)

        toolTipHost.mouseExited(with: try event(.mouseMoved, number: 4))
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertTrue(window.childWindows?.first === panel, "an opened ToolTip is governed by its safe zone")

        let farPoint = NSPoint(x: panel.frame.maxX + 200, y: panel.frame.maxY + 200)
        XCTAssertFalse(FluentToolTipHost.point(farPoint, isInsideConvexHullOf: window.convertToScreen(host.frame), and: panel.frame))
        toolTipHost.dismiss(animated: false)
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }
    @MainActor
    func testInfoBadgeDisplayPriorityAndSourceGeometry() throws {
        _ = NSApplication.shared
        let host = FluentViewHost(FluentInfoBadge(accessibilityLabel: "Activity"))

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let badge = try XCTUnwrap(descendant(identifier: "FluentKit.InfoBadge", in: host))
        let valueLabel = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBadge.Value", in: badge) as? NSTextField
        )
        let icon = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBadge.Icon", in: badge)
        )
        XCTAssertEqual(badge.intrinsicContentSize, NSSize(width: 4, height: 4))
        XCTAssertTrue(valueLabel.isHidden)
        XCTAssertTrue(icon.isHidden)

        host.update(FluentInfoBadge(systemImageName: "bell.fill", accessibilityLabel: "Alerts"))
        XCTAssertTrue(badge === descendant(identifier: "FluentKit.InfoBadge", in: host))
        XCTAssertEqual(badge.intrinsicContentSize, NSSize(width: 20, height: 16))
        XCTAssertTrue(valueLabel.isHidden)
        XCTAssertFalse(icon.isHidden)

        host.update(FluentInfoBadge(
            value: 10,
            systemImageName: "bell.fill",
            accessibilityLabel: "10 alerts"
        ))
        XCTAssertFalse(valueLabel.isHidden)
        XCTAssertTrue(icon.isHidden)
        XCTAssertEqual(valueLabel.stringValue, "10")
        XCTAssertEqual(badge.intrinsicContentSize.height, 16, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(badge.intrinsicContentSize.width, 16)
        XCTAssertEqual(badge.accessibilityValue() as? String, "10")

        badge.frame = NSRect(origin: .zero, size: badge.intrinsicContentSize)
        badge.layoutSubtreeIfNeeded()
        XCTAssertEqual(badge.layer?.cornerRadius ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(valueLabel.frame.midY, badge.bounds.midY, accuracy: 0.001)
    }

    @MainActor
    func testInfoBadgeKeepsAsymmetricImagesUprightInFlippedLayout() throws {
        _ = NSApplication.shared
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { _ in
            blue.setFill()
            NSRect(x: 0, y: 0, width: 4, height: 2).fill()
            red.setFill()
            NSRect(x: 0, y: 2, width: 4, height: 2).fill()
            return true
        }

        let host = FluentViewHost(FluentInfoBadge(
            image: image,
            background: .clear,
            cornerRadius: 0,
            accessibilityLabel: "Orientation"
        ))
        let badge = try XCTUnwrap(host.subviews.first)
        badge.frame = NSRect(origin: .zero, size: badge.intrinsicContentSize)
        badge.layoutSubtreeIfNeeded()
        let rendered = try XCTUnwrap(badge.bitmapImageRepForCachingDisplay(in: badge.bounds))
        badge.cacheDisplay(in: badge.bounds, to: rendered)

        var redMoment: CGFloat = 0
        var redWeight: CGFloat = 0
        var blueMoment: CGFloat = 0
        var blueWeight: CGFloat = 0
        for y in 0..<rendered.pixelsHigh {
            for x in 0..<rendered.pixelsWide {
                guard let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let redOnly = max(color.redComponent - color.blueComponent, 0) * color.alphaComponent
                let blueOnly = max(color.blueComponent - color.redComponent, 0) * color.alphaComponent
                redMoment += CGFloat(y) * redOnly
                redWeight += redOnly
                blueMoment += CGFloat(y) * blueOnly
                blueWeight += blueOnly
            }
        }
        XCTAssertGreaterThan(redWeight, 0)
        XCTAssertGreaterThan(blueWeight, 0)
        XCTAssertGreaterThan(blueMoment / blueWeight, redMoment / redWeight)
    }

    @MainActor
    func testProgressRingMatchesWinUIDefaultStateAndGeometry() throws {
        _ = NSApplication.shared
        let ring = FluentProgressRing()
        ring.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        ring.layoutSubtreeIfNeeded()

        let track = try XCTUnwrap(
            ring.layer?.sublayers?.first { $0.name == "FluentKit.ProgressRing.Track" } as? CAShapeLayer
        )
        let indicator = try XCTUnwrap(
            ring.layer?.sublayers?.first { $0.name == "FluentKit.ProgressRing.Indicator" } as? CAShapeLayer
        )
        XCTAssertTrue(ring.isActive)
        XCTAssertTrue(ring.isIndeterminate)
        XCTAssertEqual(ring.intrinsicContentSize, NSSize(width: 32, height: 32))
        XCTAssertEqual(track.lineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(indicator.lineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(NSColor(cgColor: try XCTUnwrap(track.strokeColor))?.alphaComponent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(indicator.strokeStart, 0, accuracy: 0.001)
        XCTAssertEqual(indicator.strokeEnd, 0.5, accuracy: 0.001)
        XCTAssertEqual(ring.layer?.opacity ?? -1, 1, accuracy: 0.001)
        XCTAssertTrue(ring.isAccessibilityElement())
        XCTAssertEqual(ring.accessibilityValue() as? String, FluentLocalization.controlString("Indeterminate"))

        ring.theme = FluentTheme(contrast: .high, colorScheme: .dark)
        XCTAssertEqual(NSColor(cgColor: try XCTUnwrap(track.strokeColor))?.alphaComponent ?? -1, 1, accuracy: 0.001)

        ring.isActive = false
        XCTAssertEqual(ring.layer?.opacity ?? -1, 0, accuracy: 0.001)
        XCTAssertFalse(ring.isAccessibilityElement())
        XCTAssertEqual(ring.intrinsicContentSize, NSSize(width: 32, height: 32))
    }

    @MainActor
    func testProgressRingDeterminateRangeCoercionAndDeclarativeUpdate() throws {
        _ = NSApplication.shared
        let ring = FluentProgressRing(isIndeterminate: false, value: 50)
        ring.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        ring.layoutSubtreeIfNeeded()
        let indicator = try XCTUnwrap(
            ring.layer?.sublayers?.first { $0.name == "FluentKit.ProgressRing.Indicator" } as? CAShapeLayer
        )
        XCTAssertEqual(indicator.lineWidth, 2.655, accuracy: 0.001)
        XCTAssertEqual(indicator.strokeEnd, 0.5, accuracy: 0.001)
        XCTAssertEqual(ring.accessibilityMinValue() as? Double, 0)
        XCTAssertEqual(ring.accessibilityMaxValue() as? Double, 100)
        XCTAssertEqual(ring.accessibilityValue() as? Double, 50)

        ring.value = 0
        XCTAssertEqual(indicator.strokeEnd, 0, accuracy: 0.001)

        ring.value = 500
        XCTAssertEqual(ring.value, 100)
        ring.maximum = -10
        XCTAssertEqual(ring.minimum, -10)
        XCTAssertEqual(ring.maximum, -10)
        XCTAssertEqual(ring.value, -10)
        ring.minimum = 15
        XCTAssertEqual(ring.minimum, 15)
        XCTAssertEqual(ring.maximum, 15)
        XCTAssertEqual(ring.value, 15)
        ring.value = .nan
        XCTAssertTrue(ring.value.isNaN)

        let host = FluentViewHost(FluentProgressRing(
            isActive: true,
            isIndeterminate: false,
            value: 25,
            minimum: 0,
            maximum: 100
        ))
        let mounted = try XCTUnwrap(host.subviews.first as? FluentProgressRing)
        host.update(FluentProgressRing(
            isActive: false,
            isIndeterminate: false,
            value: 7,
            minimum: 5,
            maximum: 10
        ))
        XCTAssertTrue(mounted === host.subviews.first)
        XCTAssertFalse(mounted.isActive)
        XCTAssertFalse(mounted.isIndeterminate)
        XCTAssertEqual(mounted.value, 7)
        XCTAssertEqual(mounted.minimum, 5)
        XCTAssertEqual(mounted.maximum, 10)
    }

    @MainActor
    func testProgressRingIndeterminateAnimationRespectsReducedMotion() throws {
        _ = NSApplication.shared
        let ring = FluentProgressRing()
        ring.reduceMotion = false
        ring.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(ring)
        ring.layoutSubtreeIfNeeded()
        let indicator = try XCTUnwrap(
            ring.layer?.sublayers?.first { $0.name == "FluentKit.ProgressRing.Indicator" } as? CAShapeLayer
        )
        let animation = try XCTUnwrap(
            indicator.animation(forKey: "fluent.progressRing.indeterminate") as? CAAnimationGroup
        )
        XCTAssertEqual(animation.duration, 2, accuracy: 0.001)
        XCTAssertTrue(animation.repeatCount.isInfinite)
        let rotation = try XCTUnwrap(
            animation.animations?
                .compactMap { $0 as? CAKeyframeAnimation }
                .first { $0.keyPath == "transform.rotation.z" }
        )
        let rotationValues = try XCTUnwrap(rotation.values as? [NSNumber])
        XCTAssertGreaterThan(try XCTUnwrap(rotationValues.last).doubleValue, 0)

        ring.reduceMotion = true
        XCTAssertNil(indicator.animation(forKey: "fluent.progressRing.indeterminate"))
        XCTAssertEqual(indicator.strokeStart, 0, accuracy: 0.001)
        XCTAssertEqual(indicator.strokeEnd, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testProgressRingDeterminateQuarterStartsAtTwelveOClockClockwise() throws {
        _ = NSApplication.shared
        let ring = FluentProgressRing(isIndeterminate: false, value: 25)
        ring.foregroundColor = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        ring.backgroundColor = .clear
        ring.reduceMotion = true
        ring.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        ring.layoutSubtreeIfNeeded()
        let rendered = try XCTUnwrap(ring.bitmapImageRepForCachingDisplay(in: ring.bounds))
        ring.cacheDisplay(in: ring.bounds, to: rendered)

        var quadrants = [Int](repeating: 0, count: 4)
        let midX = rendered.pixelsWide / 2
        let midY = rendered.pixelsHigh / 2
        for y in 0..<rendered.pixelsHigh {
            for x in 0..<rendered.pixelsWide {
                guard let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1,
                      color.blueComponent > color.redComponent + 0.2 else { continue }
                let index = (y >= midY ? 2 : 0) + (x >= midX ? 1 : 0)
                quadrants[index] += 1
            }
        }
        XCTAssertGreaterThan(quadrants[3], quadrants[0] + quadrants[1] + quadrants[2])

        ring.value = 2
        let startFrame = try XCTUnwrap(ring.bitmapImageRepForCachingDisplay(in: ring.bounds))
        ring.cacheDisplay(in: ring.bounds, to: startFrame)
        var xMoment: CGFloat = 0
        var yMoment: CGFloat = 0
        var weight: CGFloat = 0
        for y in 0..<startFrame.pixelsHigh {
            for x in 0..<startFrame.pixelsWide {
                guard let color = startFrame.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1,
                      color.blueComponent > color.redComponent + 0.2 else { continue }
                let sampleWeight = color.alphaComponent
                xMoment += CGFloat(x) * sampleWeight
                yMoment += CGFloat(y) * sampleWeight
                weight += sampleWeight
            }
        }
        XCTAssertGreaterThan(weight, 0)
        XCTAssertEqual(xMoment / weight, CGFloat(startFrame.pixelsWide) / 2, accuracy: 4)
        XCTAssertGreaterThan(yMoment / weight, CGFloat(startFrame.pixelsHigh) * 0.75)
    }

    @MainActor
    func testProgressBarMatchesWinUIDefaultRangeAndGeometry() throws {
        _ = NSApplication.shared
        let progress = FluentProgressBar(value: 25)
        progress.reduceMotion = true
        progress.frame = NSRect(x: 0, y: 0, width: 240, height: 3)
        progress.layoutSubtreeIfNeeded()

        func layer(_ name: String) throws -> CALayer {
            try XCTUnwrap(progress.layer?.sublayers?.first { $0.name == name })
        }

        let track = try layer("FluentKit.ProgressBar.Track")
        let indicator = try layer("FluentKit.ProgressBar.Determinate")
        XCTAssertFalse(progress.isIndeterminate)
        XCTAssertFalse(progress.showPaused)
        XCTAssertFalse(progress.showError)
        XCTAssertEqual(progress.minimum, 0)
        XCTAssertEqual(progress.maximum, 100)
        XCTAssertEqual(progress.value, 25)
        XCTAssertEqual(progress.intrinsicContentSize.height, 3, accuracy: 0.001)
        XCTAssertEqual(track.frame, CGRect(x: 0, y: 1, width: 240, height: 1))
        XCTAssertEqual(indicator.bounds.width, 60, accuracy: 0.001)
        XCTAssertEqual(indicator.frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(indicator.frame.height, 3, accuracy: 0.001)
        XCTAssertEqual(progress.accessibilityMinValue() as? Double, 0)
        XCTAssertEqual(progress.accessibilityMaxValue() as? Double, 100)
        XCTAssertEqual(progress.accessibilityValue() as? Double, 25)

        progress.fluentLayoutDirection = .rightToLeft
        progress.layoutSubtreeIfNeeded()
        XCTAssertEqual(indicator.frame.maxX, progress.bounds.maxX, accuracy: 0.001)
    }

    @MainActor
    func testProgressBarUsesRangePaddingBorderAndWinUIStatePrecedence() throws {
        _ = NSApplication.shared
        let progress = FluentProgressBar(value: 50, minimum: 0, maximum: 200)
        progress.reduceMotion = true
        progress.theme = FluentTheme(contrast: .high, colorScheme: .light)
        progress.contentInsets = NSEdgeInsets(top: 2, left: 10, bottom: 3, right: 20)
        progress.frame = NSRect(x: 0, y: 0, width: 240, height: 16)
        progress.layoutSubtreeIfNeeded()

        func layer(_ name: String) throws -> CALayer {
            try XCTUnwrap(progress.layer?.sublayers?.first { $0.name == name })
        }

        let track = try layer("FluentKit.ProgressBar.Track")
        let indicator = try layer("FluentKit.ProgressBar.Determinate")
        XCTAssertEqual(progress.layer?.borderWidth, 1)
        XCTAssertEqual(track.frame.minX, 11, accuracy: 0.001)
        XCTAssertEqual(track.frame.width, 208, accuracy: 0.001)
        XCTAssertEqual(track.frame.height, 1, accuracy: 0.001)
        XCTAssertEqual(indicator.bounds.width, 52, accuracy: 0.001)
        XCTAssertEqual(indicator.frame.height, 3, accuracy: 0.001)
        XCTAssertEqual(progress.intrinsicContentSize.height, 10, accuracy: 0.001)

        progress.showPaused = true
        XCTAssertEqual(progress.progressState, .paused)
        XCTAssertEqual(progress.accessibilityHelp(), "Paused")
        progress.showError = true
        XCTAssertTrue(progress.showPaused)
        XCTAssertTrue(progress.showError)
        XCTAssertEqual(progress.progressState, .error)
        XCTAssertEqual(progress.accessibilityHelp(), "Error")
        progress.showError = false
        XCTAssertEqual(progress.progressState, .paused)

        progress.maximum = -10
        XCTAssertEqual(progress.minimum, -10)
        XCTAssertEqual(progress.maximum, -10)
        XCTAssertEqual(progress.value, -10)
        progress.minimum = 15
        XCTAssertEqual(progress.minimum, 15)
        XCTAssertEqual(progress.maximum, 15)
        XCTAssertEqual(progress.value, 15)
        progress.value = .nan
        XCTAssertTrue(progress.value.isNaN)

        progress.isIndeterminate = true
        XCTAssertNil(progress.accessibilityMinValue())
        XCTAssertNil(progress.accessibilityMaxValue())
        XCTAssertEqual(progress.accessibilityValue() as? String, FluentLocalization.controlString("Indeterminate"))
    }

    @MainActor
    func testProgressBarUsesSourceIndeterminateAndSequentialStateMotion() throws {
        _ = NSApplication.shared
        let progress = FluentProgressBar(isIndeterminate: false)
        progress.reduceMotion = false
        progress.frame = NSRect(x: 0, y: 0, width: 240, height: 16)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 16),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(progress)
        window.orderFront(nil)
        progress.layoutSubtreeIfNeeded()

        func layer(_ name: String) throws -> CALayer {
            try XCTUnwrap(progress.layer?.sublayers?.first { $0.name == name })
        }

        let primary = try layer("FluentKit.ProgressBar.Indeterminate.Primary")
        let secondary = try layer("FluentKit.ProgressBar.Indeterminate.Secondary")
        progress.isIndeterminate = true
        let primaryLoop = try XCTUnwrap(
            primary.animation(forKey: "fluent.progress.indeterminate.primary") as? CAKeyframeAnimation
        )
        let secondaryLoop = try XCTUnwrap(
            secondary.animation(forKey: "fluent.progress.indeterminate.secondary") as? CAKeyframeAnimation
        )
        XCTAssertEqual(primaryLoop.duration, 2, accuracy: 0.001)
        XCTAssertEqual(primaryLoop.keyTimes ?? [], [0, 0.75, 1])
        XCTAssertEqual(secondaryLoop.duration, 2, accuracy: 0.001)
        XCTAssertEqual(secondaryLoop.keyTimes ?? [], [0, 0.375, 1])
        XCTAssertEqual(primary.bounds.width, 96, accuracy: 0.001)
        XCTAssertEqual(secondary.bounds.width, 144, accuracy: 0.001)

        progress.showPaused = true
        let settle = try XCTUnwrap(
            secondary.animation(forKey: "fluent.progress.indeterminate.settle") as? CAKeyframeAnimation
        )
        XCTAssertEqual(settle.duration, 0.75, accuracy: 0.001)
        XCTAssertEqual(settle.values?.count, 4)
        XCTAssertEqual(primary.opacity, 0)
        XCTAssertEqual(secondary.bounds.width, 240, accuracy: 0.001)

        progress.showError = true
        XCTAssertEqual(progress.progressState, .error)
        XCTAssertEqual(progress.accessibilityHelp(), "Error")
        progress.showError = false
        XCTAssertEqual(progress.progressState, .paused)
        progress.showPaused = false
        let resume = try XCTUnwrap(
            secondary.animation(forKey: "fluent.progress.indeterminate.resume") as? CABasicAnimation
        )
        let resumeTrack = try XCTUnwrap(
            try layer("FluentKit.ProgressBar.Track")
                .animation(forKey: "fluent.progress.indeterminate.resume.track") as? CABasicAnimation
        )
        XCTAssertEqual(resume.duration, 0.333, accuracy: 0.001)
        XCTAssertEqual(resumeTrack.duration, 0.5, accuracy: 0.001)
        XCTAssertEqual(primary.opacity, 0)
        XCTAssertNil(primary.animation(forKey: "fluent.progress.indeterminate.primary"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.56))
        XCTAssertNotNil(primary.animation(forKey: "fluent.progress.indeterminate.primary"))

        progress.isIndeterminate = false
        window.orderOut(nil)
    }

    @MainActor
    func testProgressBarDeclarativeUpdatePreservesIdentityAndSourceProperties() throws {
        _ = NSApplication.shared
        let initial = FluentProgressBar(value: 25, showPaused: true)
        initial.contentInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 8)
        let host = FluentViewHost(initial)
        let mounted = try XCTUnwrap(host.subviews.first as? FluentProgressBar)

        let update = FluentProgressBar(
            value: 7,
            minimum: 5,
            maximum: 10,
            isIndeterminate: true,
            showPaused: true,
            showError: true
        )
        update.contentInsets = NSEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        host.update(update)

        XCTAssertTrue(mounted === host.subviews.first)
        XCTAssertEqual(mounted.value, 7)
        XCTAssertEqual(mounted.minimum, 5)
        XCTAssertEqual(mounted.maximum, 10)
        XCTAssertTrue(mounted.isIndeterminate)
        XCTAssertTrue(mounted.showPaused)
        XCTAssertTrue(mounted.showError)
        XCTAssertEqual(mounted.progressState, .error)
        XCTAssertEqual(mounted.contentInsets.top, 1)
        XCTAssertEqual(mounted.contentInsets.left, 2)
        XCTAssertEqual(mounted.contentInsets.bottom, 3)
        XCTAssertEqual(mounted.contentInsets.right, 4)
    }

    func testInfoBadgeAndInfoBarSystemFillResourcesMatchWinUI() {
        let light = FluentTheme(colorScheme: .light)
        let dark = FluentTheme(colorScheme: .dark)

        func whiteComponents(_ color: NSColor) -> (CGFloat, CGFloat) {
            var white: CGFloat = 0
            var alpha: CGFloat = 0
            color.getWhite(&white, alpha: &alpha)
            return (white, alpha)
        }

        let lightNeutral = whiteComponents(light.infoBadgeBackground(for: .informational))
        XCTAssertEqual(lightNeutral.0, 138.0 / 255.0, accuracy: 0.001)
        let darkNeutral = whiteComponents(dark.infoBadgeBackground(for: .informational))
        XCTAssertEqual(darkNeutral.0, 157.0 / 255.0, accuracy: 0.001)
        let lightAttentionBackground = whiteComponents(light.infoBarBackground(for: .informational))
        XCTAssertEqual(lightAttentionBackground.0, 246.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(lightAttentionBackground.1, 128.0 / 255.0, accuracy: 0.001)
        let darkAttentionBackground = whiteComponents(dark.infoBarBackground(for: .informational))
        XCTAssertEqual(darkAttentionBackground.1, 8.0 / 255.0, accuracy: 0.001)
    }

    @MainActor
    func testInfoBarCloseEventOrderAndCancellation() throws {
        _ = NSApplication.shared
        let isOpen = FluentState(wrappedValue: true)
        var events: [String] = []
        var cancelsClose = false
        let host = FluentViewHost(
            FluentInfoBar(
                isOpen: isOpen.projectedValue,
                title: "Update available",
                message: "Restart to finish installing.",
                onCloseButtonClick: { events.append("click") },
                onClosing: {
                    events.append("closing:\($0.reason)")
                    $0.cancel = cancelsClose
                },
                onClosed: { events.append("closed:\($0)") }
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 80)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        let closeButton = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBar.CloseButton", in: host) as? NSButton
        )
        closeButton.performClick(nil)
        XCTAssertFalse(isOpen.wrappedValue)
        XCTAssertEqual(events, ["click", "closing:closeButton", "closed:closeButton"])
        XCTAssertTrue(try XCTUnwrap(descendant(identifier: "FluentKit.InfoBar", in: host)).isHidden)

        isOpen.wrappedValue = true
        cancelsClose = true
        events.removeAll()
        closeButton.performClick(nil)
        XCTAssertTrue(isOpen.wrappedValue)
        XCTAssertEqual(events, ["click", "closing:closeButton"])
        XCTAssertFalse(try XCTUnwrap(descendant(identifier: "FluentKit.InfoBar", in: host)).isHidden)
    }

    @MainActor
    func testInfoBarAdaptsFromHorizontalToVerticalAndMirrorsRTL() throws {
        _ = NSApplication.shared
        let isOpen = FluentState(wrappedValue: true)
        let infoBar = FluentInfoBar(
            isOpen: isOpen.projectedValue,
            title: "Update",
            message: "A new version is ready.",
            severity: .warning
        ) {
            FluentButtonView("Restart") {}
        }
        let host = FluentViewHost(infoBar)

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        func descendants<T>(of type: T.Type, in root: NSView) -> [T] {
            let own = (root as? T).map { [$0] } ?? []
            return own + root.subviews.flatMap { descendants(of: type, in: $0) }
        }

        host.frame = NSRect(x: 0, y: 0, width: 720, height: 120)
        host.layoutSubtreeIfNeeded()
        let title = try XCTUnwrap(descendant(identifier: "FluentKit.InfoBar.Title", in: host))
        let message = try XCTUnwrap(descendant(identifier: "FluentKit.InfoBar.Message", in: host))
        let button = try XCTUnwrap(descendants(of: FluentButton.self, in: host).first)
        let actionPresenter = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBar.ActionPresenter", in: host)
        )
        XCTAssertGreaterThan(message.frame.minX, title.frame.maxX)
        XCTAssertGreaterThan(actionPresenter.frame.minX, message.frame.maxX)
        XCTAssertLessThan(button.frame.width, actionPresenter.frame.width)

        host.frame.size.width = 300
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(message.frame.minY, title.frame.maxY)
        XCTAssertGreaterThan(actionPresenter.frame.minY, message.frame.maxY)

        let rtlHost = FluentViewHost(
            infoBar,
            context: FluentRenderContext(layoutDirection: .rightToLeft)
        )
        rtlHost.frame = NSRect(x: 0, y: 0, width: 720, height: 120)
        rtlHost.layoutSubtreeIfNeeded()
        let icon = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBar.StandardIcon", in: rtlHost)
        )
        let close = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBar.CloseButton", in: rtlHost)
        )
        XCTAssertLessThan(close.frame.midX, icon.frame.midX)
    }

    @MainActor
    func testInfoBarKeepsWarningExclamationUprightInFlippedLayout() throws {
        _ = NSApplication.shared
        let isOpen = FluentState(wrappedValue: true)
        let host = FluentViewHost(
            FluentInfoBar(
                isOpen: isOpen.projectedValue,
                title: "Warning",
                severity: .warning
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 64)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let icon = try XCTUnwrap(
            descendant(identifier: "FluentKit.InfoBar.StandardIcon", in: host)
        )
        let rendered = try XCTUnwrap(icon.bitmapImageRepForCachingDisplay(in: icon.bounds))
        icon.cacheDisplay(in: icon.bounds, to: rendered)

        var brightWeightByRow = Array(repeating: CGFloat.zero, count: rendered.pixelsHigh)
        for y in 0..<rendered.pixelsHigh {
            for x in 0..<rendered.pixelsWide {
                guard let color = rendered.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let whiteness = min(color.redComponent, color.greenComponent, color.blueComponent)
                if whiteness > 0.7 {
                    brightWeightByRow[y] += whiteness * color.alphaComponent
                }
            }
        }

        let occupiedRows = brightWeightByRow.indices.filter { brightWeightByRow[$0] > 0.15 }
        XCTAssertFalse(occupiedRows.isEmpty)
        let midpoint = rendered.pixelsHigh / 2
        let topRows = occupiedRows.filter { $0 < midpoint }
        let bottomRows = occupiedRows.filter { $0 >= midpoint }
        // An upright exclamation mark has its small dot below the centre and its longer stem
        // above it. Bitmap rows follow the flipped view's top-down coordinate space.
        XCTAssertGreaterThan(topRows.count, bottomRows.count)
    }

    @MainActor
    func testEmptyTextFieldPresentsDisabledContextCommands() throws {
        _ = NSApplication.shared
        let field = FluentSearchTextField(placeholder: "Search")
        field.frame = NSRect(x: 20, y: 20, width: 260, height: 32)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = field
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(nil)
        XCTAssertNil(field.currentEditor())
        XCTAssertTrue(field.stringValue.isEmpty)

        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: field.convert(NSPoint(x: 40, y: field.bounds.midY), to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ))
        field.rightMouseDown(with: click)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

        XCTAssertNotNil(field.currentEditor())
        let panel = try XCTUnwrap(window.childWindows?.first)
        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        let presenter = try XCTUnwrap(
            panel.contentView.flatMap { descendant(identifier: "FluentKit.TextCommandBarFlyout", in: $0) }
        )
        let selectAll = try XCTUnwrap(
            (presenter.accessibilityChildren() ?? [])
                .compactMap { $0 as? NSView }
                .first { $0.accessibilityTitle() == field.fluentControlString("Select All") }
        )
        XCTAssertFalse(try XCTUnwrap(selectAll as? NSControl).isEnabled)
        window.orderOut(nil)
    }

    @MainActor
    func testTeachingTipDefaultButtonMatrixAndCloseEventOrderMatchWinUI() throws {
        _ = NSApplication.shared
        let presented = FluentState(wrappedValue: false)
        var events: [String] = []
        let anchor = FluentButtonView("Teaching tip anchor")
            .teachingTip(
                isPresented: presented.projectedValue,
                title: "Keyboard navigation",
                placement: .top,
                shouldConstrainToRootBounds: false,
                size: NSSize(width: 280, height: 140),
                actionButtonTitle: "Show shortcuts",
                onActionButtonClick: { events.append("action") },
                onCloseButtonClick: { events.append("close-click") },
                onClosing: { events.append("closing:\($0.reason)") },
                onClosed: { events.append("closed:\($0)") },
                onOpened: { events.append("opened") }
            ) {
                FluentText("Use the arrow keys.")
            }
        let host = FluentViewHost(anchor, context: FluentRenderContext(reduceMotion: true))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        presented.wrappedValue = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let panel = try XCTUnwrap(window.childWindows?.first as? NSPanel)
        let chrome = try XCTUnwrap(panel.contentView)
        let action = try XCTUnwrap(
            descendant(identifier: "FluentKit.TeachingTip.ActionButton", in: chrome) as? NSButton
        )
        let headerClose = try XCTUnwrap(
            descendant(identifier: "FluentKit.TeachingTip.HeaderCloseButton", in: chrome) as? NSButton
        )
        let footerClose = try XCTUnwrap(
            descendant(identifier: "FluentKit.TeachingTip.CloseButton", in: chrome) as? NSButton
        )
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(action.isHidden)
        XCTAssertFalse(headerClose.isHidden)
        XCTAssertTrue(footerClose.isHidden)
        XCTAssertEqual(events, ["opened"])

        action.performClick(nil)
        XCTAssertTrue(presented.wrappedValue)
        XCTAssertEqual(events, ["opened", "action"])

        headerClose.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(presented.wrappedValue)
        XCTAssertEqual(
            events,
            ["opened", "action", "close-click", "closing:closeButton", "closed:closeButton"]
        )
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }

    @MainActor
    func testTeachingTipClosingCanCancelAndLightDismissUsesModalPresenter() throws {
        _ = NSApplication.shared
        let presented = FluentState(wrappedValue: false)
        var cancels = true
        var reasons: [FluentTeachingTipCloseReason] = []
        let anchor = FluentButtonView("Teaching tip anchor")
            .teachingTip(
                isPresented: presented.projectedValue,
                title: "Light dismiss",
                placement: .bottom,
                shouldConstrainToRootBounds: false,
                isLightDismissEnabled: true,
                actionButtonTitle: "Action",
                onClosing: {
                    reasons.append($0.reason)
                    $0.cancel = cancels
                },
                onClosed: { reasons.append($0) }
            ) {
                FluentText("Transient guidance")
            }
        let host = FluentViewHost(anchor, context: FluentRenderContext(reduceMotion: true))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        presented.wrappedValue = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let panel = try XCTUnwrap(window.childWindows?.first as? NSPanel)
        let chrome = try XCTUnwrap(panel.contentView)
        let headerClose = try XCTUnwrap(
            descendant(identifier: "FluentKit.TeachingTip.HeaderCloseButton", in: chrome)
        )
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertEqual(chrome.accessibilityRole(), .window)
        XCTAssertTrue(headerClose.isHidden)

        presented.wrappedValue = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(presented.wrappedValue)
        XCTAssertEqual(reasons, [.programmatic])
        XCTAssertTrue(window.childWindows?.first === panel)

        cancels = false
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))
        chrome.keyDown(with: escape)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(presented.wrappedValue)
        XCTAssertEqual(reasons, [.programmatic, .lightDismiss, .lightDismiss])
        XCTAssertTrue(window.childWindows?.isEmpty != false)
    }

    @MainActor
    func testTeachingTipSourceSizeTailAndCornerPlacementGeometry() throws {
        _ = NSApplication.shared
        let presented = FluentState(wrappedValue: true)
        let initial = FluentButtonView("Teaching tip anchor")
            .teachingTip(
                isPresented: presented.projectedValue,
                tailVisibility: .visible,
                placement: .topRight,
                shouldConstrainToRootBounds: false,
                size: NSSize(width: 200, height: 100)
            ) {
                FluentText("Geometry")
            }
        let host = FluentViewHost(initial, context: FluentRenderContext(reduceMotion: true))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 700, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let panel = try XCTUnwrap(window.childWindows?.first)
        let topRightFrame = panel.frame
        XCTAssertEqual(topRightFrame.width, 320 + 32, accuracy: 0.001)
        XCTAssertEqual(topRightFrame.height, 100 + 32 + 8, accuracy: 0.001)

        let topLeft = FluentButtonView("Teaching tip anchor")
            .teachingTip(
                isPresented: presented.projectedValue,
                tailVisibility: .collapsed,
                placement: .topLeft,
                shouldConstrainToRootBounds: false,
                size: NSSize(width: 500, height: 600)
            ) {
                FluentText("Updated geometry")
            }
        XCTAssertTrue(topLeft._update(host.subviews[0], in: FluentRenderContext(reduceMotion: true)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertLessThan(panel.frame.minX, topRightFrame.minX)
        XCTAssertEqual(panel.frame.width, 336 + 32, accuracy: 0.001)
        XCTAssertEqual(panel.frame.height, 520 + 32, accuracy: 0.001)
    }

    @MainActor
    func testTeachingTipSourceFallbackPrioritizesOppositeRequestedEdge() throws {
        _ = NSApplication.shared
        let presented = FluentState(wrappedValue: true)
        func makeTip(_ placement: FluentTeachingTipPlacement) -> some FluentView {
            FluentButtonView("Anchor")
                .teachingTip(
                    isPresented: presented.projectedValue,
                    placement: placement,
                    shouldConstrainToRootBounds: true,
                    size: NSSize(width: 320, height: 100)
                ) {
                    FluentText("Fallback")
                }
        }

        let host = FluentViewHost(makeTip(.top), context: FluentRenderContext(reduceMotion: true))
        host.frame = NSRect(x: 260, y: 360, width: 80, height: 40)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 420))
        root.addSubview(host)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let panel = try XCTUnwrap(window.childWindows?.first)
        var anchorOnScreen = window.convertToScreen(root.convert(host.frame, to: nil))
        XCTAssertLessThan(panel.frame.midY, anchorOnScreen.midY)

        host.frame = NSRect(x: 510, y: 190, width: 80, height: 40)
        host.update(makeTip(.right))
        root.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        anchorOnScreen = window.convertToScreen(root.convert(host.frame, to: nil))
        XCTAssertTrue(window.childWindows?.first === panel)
        XCTAssertLessThan(panel.frame.midX, anchorOnScreen.midX)
    }

    func testTeachingTipSourceSurfaceResources() {
        let light = FluentTheme(colorScheme: .light)
        let dark = FluentTheme(colorScheme: .dark)
        let highContrast = FluentTheme(contrast: .high, colorScheme: .dark)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        light.teachingTipBackground.getWhite(&white, alpha: &alpha)
        XCTAssertEqual(white, 249.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
        XCTAssertEqual(light.teachingTipTopHighlight.alphaComponent, 153.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(dark.teachingTipTopHighlight.alphaComponent, 13.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(highContrast.teachingTipTopHighlight.alphaComponent, 0, accuracy: 0.001)
    }

    @MainActor
    func testSettingsExpanderReplacesTypeErasedContentWhenComponentChanges() {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: true)
        let buttonPage = FluentAnyView(
            FluentSettingsExpander("Example", isExpanded: expanded.projectedValue) {
                FluentAnyView(FluentButtonView("Button sample"))
            }
        )
        let host = FluentViewHost(buttonPage)

        func descendants<T>(of type: T.Type, in root: NSView) -> [T] {
            let own = (root as? T).map { [$0] } ?? []
            return own + root.subviews.flatMap { descendants(of: type, in: $0) }
        }

        XCTAssertEqual(descendants(of: FluentButton.self, in: host).count, 1)
        XCTAssertTrue(descendants(of: FluentCheckBox.self, in: host).isEmpty)

        let checkBoxPage = FluentAnyView(
            FluentSettingsExpander("Example", isExpanded: expanded.projectedValue) {
                FluentAnyView(
                    FluentCheckBoxView(
                        "CheckBox sample",
                        isChecked: FluentBinding(get: { true }, set: { _ in })
                    )
                )
            }
        )
        host.update(checkBoxPage)

        XCTAssertTrue(descendants(of: FluentButton.self, in: host).isEmpty)
        XCTAssertEqual(descendants(of: FluentCheckBox.self, in: host).count, 1)
    }

    @MainActor
    func testExpanderMatchesWinUISourceGeometryEventsAndAccessibility() throws {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: false)
        var events: [String] = []
        let root = FluentExpander(
            "Details",
            isExpanded: expanded.projectedValue,
            onExpanding: { events.append("expanding") },
            onCollapsed: { events.append("collapsed") }
        ) {
            FluentText("Expanded content")
        }
        ._mount(in: FluentRenderContext(reduceMotion: false))

        func descendant(identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let header = try XCTUnwrap(descendant(identifier: "FluentKit.Expander.Header", in: root))
        let clip = try XCTUnwrap(descendant(identifier: "FluentKit.Expander.ContentClip", in: root))
        let content = try XCTUnwrap(descendant(identifier: "FluentKit.Expander.Content", in: root))
        root.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: root.intrinsicContentSize.height))
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(root.intrinsicContentSize.height, 48, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(root.intrinsicContentSize.width, 96)
        XCTAssertEqual(header.frame.height, 48, accuracy: 0.001)
        XCTAssertGreaterThan(
            header.subviews.first?.frame.width ?? 0,
            header.subviews.first?.intrinsicContentSize.width ?? .greatestFiniteMagnitude
        )
        XCTAssertTrue(clip.isHidden)
        XCTAssertTrue(content.isHidden)
        XCTAssertEqual(root.accessibilityRole(), .disclosureTriangle)
        XCTAssertEqual(root.accessibilityValue() as? String, "Collapsed")
        XCTAssertEqual(root.accessibilityChildren()?.count, 0)

        XCTAssertTrue(root.accessibilityPerformPress())
        XCTAssertTrue(expanded.wrappedValue)
        XCTAssertEqual(events, ["expanding"])
        root.frame.size.height = root.intrinsicContentSize.height
        root.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(root.intrinsicContentSize.height, 48)
        XCTAssertFalse(clip.isHidden)
        XCTAssertFalse(content.isHidden)
        XCTAssertEqual(header.frame.minY, 0, accuracy: 0.001)
        XCTAssertEqual(clip.frame.minY, 48, accuracy: 0.001)
        XCTAssertEqual(root.accessibilityValue() as? String, "Expanded")
        XCTAssertEqual(root.accessibilityChildren()?.count, 1)

        XCTAssertTrue(root.accessibilityPerformPress())
        XCTAssertFalse(expanded.wrappedValue)
        XCTAssertEqual(events, ["expanding", "collapsed"])
        XCTAssertEqual(root.intrinsicContentSize.height, 48, accuracy: 0.001)
        XCTAssertTrue(clip.isHidden)
        XCTAssertTrue(content.isHidden)
    }

    @MainActor
    func testExpanderUpDirectionAndRTLMirrorWinUITemplate() throws {
        _ = NSApplication.shared
        let expanded = FluentState(wrappedValue: true)
        let root = FluentExpander(
            "Details",
            isExpanded: expanded.projectedValue,
            expandDirection: .up
        ) {
            FluentText("Expanded content")
        }
        ._mount(in: FluentRenderContext(
            reduceMotion: true,
            layoutDirection: .rightToLeft
        ))

        func descendant(identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            return view.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let header = try XCTUnwrap(descendant(identifier: "FluentKit.Expander.Header", in: root))
        let clip = try XCTUnwrap(descendant(identifier: "FluentKit.Expander.ContentClip", in: root))
        root.frame = NSRect(origin: .zero, size: NSSize(width: 320, height: root.intrinsicContentSize.height))
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(root.userInterfaceLayoutDirection, .rightToLeft)
        XCTAssertEqual(clip.frame.minY, 0, accuracy: 0.001)
        XCTAssertEqual(header.frame.minY, clip.frame.maxY, accuracy: 0.001)
        let chevron = try XCTUnwrap(header.layer?.sublayers?.first as? FluentChevronPrimitiveLayer)
        XCTAssertLessThan(chevron.position.x, header.bounds.midX)
        XCTAssertEqual(chevron.transform.m11, 1, accuracy: 0.001)
        XCTAssertEqual(chevron.transform.m22, 1, accuracy: 0.001)
    }

    func testExpanderUsesWinUISourceMotionTokens() {
        XCTAssertEqual(FluentMotion.expanderExpand.duration, 0.333, accuracy: 0.0001)
        XCTAssertEqual(FluentMotion.expanderExpand.curve, FluentCubicBezier(0, 0, 0, 1))
        XCTAssertEqual(FluentMotion.expanderCollapse.duration, 0.167, accuracy: 0.0001)
        XCTAssertEqual(FluentMotion.expanderCollapse.curve, FluentCubicBezier(1, 1, 0, 1))
    }

    @MainActor
    func testComboBoxPopupOpensFromRealHostAndNativeBridgeReleasePaths() throws {
        _ = NSApplication.shared
        enum Option: String, Hashable { case first, second, third }
        let selection = FluentState<Option?>(wrappedValue: .second)
        let host = FluentComboBox(
            options: [.first, .second, .third],
            selection: selection.projectedValue,
            title: { $0.rawValue.capitalized }
        )
        ._mount(in: FluentRenderContext(reduceMotion: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        host.frame = NSRect(x: 20, y: 40, width: 220, height: 34)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        func descendant<T: NSView>(of type: T.Type, in root: NSView) -> T? {
            if let match = root as? T { return match }
            return root.subviews.lazy.compactMap { descendant(of: type, in: $0) }.first
        }
        func event(_ type: NSEvent.EventType, in view: NSView, number: Int) throws -> NSEvent {
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            return try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
        func drain() {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        let native = try XCTUnwrap(descendant(of: NSComboBox.self, in: host))
        native.mouseDown(with: try event(.leftMouseDown, in: native, number: 811))
        native.mouseUp(with: try event(.leftMouseUp, in: native, number: 812))
        drain()
        XCTAssertEqual(window.childWindows?.count, 1)
        native.mouseDown(with: try event(.leftMouseDown, in: native, number: 813))
        native.mouseUp(with: try event(.leftMouseUp, in: native, number: 814))
        drain()
        XCTAssertEqual(window.childWindows?.count, 0)

        host.mouseDown(with: try event(.leftMouseDown, in: host, number: 815))
        host.mouseUp(with: try event(.leftMouseUp, in: host, number: 816))
        drain()
        XCTAssertEqual(window.childWindows?.count, 1)
    }

    func testJumpAndAdaptiveIndicatorsGrowInPlaceAcrossVisualDepths() throws {
        for mode in [FluentNavigationSelectionIndicatorMode.jump, .adaptive] {
            let root = CALayer()
            let animator = FluentSelectionIndicatorAnimator(
                currentLayerName: "current",
                previousLayerName: "previous",
                axis: .vertical
            )
            animator.attach(to: root)
            animator.setMode(mode)
            animator.update(
                target: NSRect(x: 4, y: 20, width: 3, height: 16),
                color: .controlAccentColor,
                animated: false,
                reduceMotion: false
            )
            animator.update(
                target: NSRect(x: 28, y: 180, width: 3, height: 16),
                color: .controlAccentColor,
                animated: true,
                reduceMotion: false
            )

            let current = try XCTUnwrap(root.sublayers?.first { $0.name == "current" })
            let previous = try XCTUnwrap(root.sublayers?.first { $0.name == "previous" })
            let incoming = try XCTUnwrap(
                current.animation(forKey: "fluent.navigation.selection") as? CAAnimationGroup
            )
            let outgoing = try XCTUnwrap(
                previous.animation(forKey: "fluent.navigation.selection.outgoing") as? CAAnimationGroup
            )
            let incomingBounds = try XCTUnwrap(
                incoming.animations?.first { ($0 as? CAPropertyAnimation)?.keyPath == "bounds.size" }
                    as? CABasicAnimation
            )
            let outgoingBounds = try XCTUnwrap(
                outgoing.animations?.first { ($0 as? CAPropertyAnimation)?.keyPath == "bounds.size" }
                    as? CABasicAnimation
            )
            XCTAssertEqual((incomingBounds.fromValue as? NSValue)?.sizeValue.height ?? -1, 0, accuracy: 0.001)
            XCTAssertEqual((incomingBounds.toValue as? NSValue)?.sizeValue.height ?? -1, 16, accuracy: 0.001)
            XCTAssertEqual((outgoingBounds.fromValue as? NSValue)?.sizeValue.height ?? -1, 16, accuracy: 0.001)
            XCTAssertEqual((outgoingBounds.toValue as? NSValue)?.sizeValue.height ?? -1, 0, accuracy: 0.001)
            XCTAssertEqual(incoming.duration, 0.6, accuracy: 0.000_001)
            XCTAssertEqual(outgoing.duration, 0.6, accuracy: 0.000_001)
        }
    }

    func testTabDragPreviewCentersThePointerAndClampsTheInlineTab() {
        let preview = FluentTabViewDragGeometry.centeredFrame(
            at: NSPoint(x: 320, y: 240),
            size: NSSize(width: 180, height: 120)
        )
        XCTAssertEqual(preview.midX, 320, accuracy: 0.001)
        XCTAssertEqual(preview.midY, 240, accuracy: 0.001)

        let visible = NSRect(x: 100, y: 8, width: 360, height: 32)
        let centeredTab = FluentTabViewDragGeometry.inlineCenteredFrame(
            at: NSPoint(x: 280, y: 24),
            size: NSSize(width: 160, height: 32),
            visibleFrame: visible,
            rowY: 8
        )
        XCTAssertEqual(centeredTab.midX, 280, accuracy: 0.001)
        XCTAssertEqual(centeredTab.minY, 8, accuracy: 0.001)

        let leftClamped = FluentTabViewDragGeometry.inlineCenteredFrame(
            at: NSPoint(x: 40, y: 24),
            size: NSSize(width: 160, height: 32),
            visibleFrame: visible,
            rowY: 8
        )
        let rightClamped = FluentTabViewDragGeometry.inlineCenteredFrame(
            at: NSPoint(x: 520, y: 24),
            size: NSSize(width: 160, height: 32),
            visibleFrame: visible,
            rowY: 8
        )
        XCTAssertEqual(leftClamped.minX, visible.minX, accuracy: 0.001)
        XCTAssertEqual(rightClamped.maxX, visible.maxX, accuracy: 0.001)
    }

    func testPublishedMotionDurations() {
        XCTAssertEqual(FluentMotion.controlFaster.duration, 0.083, accuracy: 0.000_001)
        XCTAssertEqual(FluentMotion.controlFast.duration, 0.167, accuracy: 0.000_001)
        XCTAssertEqual(FluentMotion.controlNormal.duration, 0.250, accuracy: 0.000_001)
    }

    @MainActor
    func testWindowControlsSwitchBetweenWindowsAndMacOSStyles() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.applyFluentWindowControlsStyle(.windows)
        XCTAssertEqual(window.fluentWindowControlsStyle, .windows)
        XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(.closeButton)).isHidden)
        XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(.miniaturizeButton)).isHidden)
        XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(.zoomButton)).isHidden)
        XCTAssertEqual(window.titlebarAccessoryViewControllers.count, 1)
        XCTAssertEqual(
            window.titlebarAccessoryViewControllers.first?.view.identifier?.rawValue,
            "FluentKit.WindowControls.Windows"
        )

        window.applyFluentWindowControlsStyle(.macOS)
        XCTAssertEqual(window.fluentWindowControlsStyle, .macOS)
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.closeButton)).isHidden)
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.miniaturizeButton)).isHidden)
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)).isHidden)
        XCTAssertTrue(window.titlebarAccessoryViewControllers.isEmpty)
    }

    @MainActor
    func testWindowsControlsFollowExpandedTitleBarHostHeight() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let titleBarHost = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 48))

        window.applyFluentWindowControlsStyle(
            .windows,
            titleBarHeight: 48,
            hostedIn: titleBarHost
        )
        titleBarHost.layoutSubtreeIfNeeded()

        let controls = try XCTUnwrap(titleBarHost.subviews.first {
            $0.identifier?.rawValue == "FluentKit.WindowControls.Windows"
        })
        XCTAssertTrue(window.titlebarAccessoryViewControllers.isEmpty)
        XCTAssertEqual(controls.frame.height, 48, accuracy: 0.001)
        XCTAssertEqual(controls.frame.maxX, titleBarHost.bounds.maxX, accuracy: 0.001)

        window.applyFluentWindowControlsStyle(.macOS)
        XCTAssertNil(controls.superview)
    }

    @MainActor
    func testTitleBarPrimaryStaysWindowCenteredAndHeightCanBeFixed() throws {
        _ = NSApplication.shared
        let titleBar = FluentTitleBar(
            title: "FluentKit Gallery",
            subtitle: "WinUI Gallery source comparison",
            heightMode: .automatic,
            leftHeader: {
                FluentText("Leading").titleBarPrimary()
            },
            content: {
                FluentSearchField(FluentState(wrappedValue: "").projectedValue, placeholder: "Search")
                    .frame(width: 340, height: 32)
                    .titleBarPrimary()
            },
            rightHeader: {
                FluentText("Trailing").titleBarPrimary()
            }
        )
        let host = FluentViewHost(titleBar)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 48)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let nativeTitleBar = try XCTUnwrap(
            descendant(identifier: "FluentKit.TitleBar", in: host)
        )
        let content = try XCTUnwrap(
            descendant(identifier: "FluentKit.TitleBar.Content", in: nativeTitleBar)
        )
        XCTAssertEqual(nativeTitleBar.intrinsicContentSize.height, 48, accuracy: 0.001)
        XCTAssertEqual(content.frame.midX, nativeTitleBar.bounds.midX, accuracy: 0.5)
        let subtitle = try XCTUnwrap(
            descendant(identifier: "FluentKit.TitleBar.Subtitle", in: nativeTitleBar)
        )
        XCTAssertLessThanOrEqual(subtitle.frame.maxX, content.frame.minX - 7)

        let fixed = FluentTitleBar(title: "Fixed", heightMode: .fixed(56))
        let fixedHost = FluentViewHost(fixed)
        fixedHost.frame = NSRect(x: 0, y: 0, width: 500, height: 56)
        fixedHost.layoutSubtreeIfNeeded()
        let fixedNative = try XCTUnwrap(
            descendant(identifier: "FluentKit.TitleBar", in: fixedHost)
        )
        XCTAssertEqual(fixedNative.intrinsicContentSize.height, 56, accuracy: 0.001)
    }

    func testCubicBezierClampsHorizontalControlPoints() {
        let curve = FluentCubicBezier(-0.5, -0.25, 1.5, 1.25)

        XCTAssertEqual(curve.x1, 0)
        XCTAssertEqual(curve.y1, -0.25)
        XCTAssertEqual(curve.x2, 1)
        XCTAssertEqual(curve.y2, 1.25)
    }

    func testMappedBindingReadsWritesAndObserves() {
        let state = FluentState(wrappedValue: 2)
        let mapped = state.projectedValue.map(String.init) { Int($0) ?? 0 }
        var observedValues: [String] = []
        let observerID = mapped.observe { observedValues.append($0) }

        XCTAssertEqual(mapped.wrappedValue, "2")
        mapped.wrappedValue = "7"
        XCTAssertEqual(state.wrappedValue, 7)
        XCTAssertEqual(observedValues, ["7"])

        if let observerID {
            mapped.removeObserver(observerID)
        }
        state.wrappedValue = 9
        XCTAssertEqual(observedValues, ["7"])
    }

    func testControlSizeMetricsRemainOrdered() {
        XCTAssertLessThan(FluentControlSize.small.height, FluentControlSize.regular.height)
        XCTAssertLessThan(FluentControlSize.regular.height, FluentControlSize.large.height)
        XCTAssertLessThan(FluentControlSize.small.metricScale, FluentControlSize.regular.metricScale)
        XCTAssertLessThan(FluentControlSize.regular.metricScale, FluentControlSize.large.metricScale)
    }

    @MainActor
    func testButtonKeepsCenteredTitleWidthBeforeAdjacentDescription() {
        _ = NSApplication.shared
        let button = FluentButton(title: "Open detachable window tabs", role: .primary)
        let description = NSTextField(
            labelWithString: "Windows-style Fluent tabs with native macOS window tear-out and merge behavior."
        )
        description.lineBreakMode = .byTruncatingTail

        XCTAssertGreaterThan(
            button.contentCompressionResistancePriority(for: .horizontal).rawValue,
            description.contentCompressionResistancePriority(for: .horizontal).rawValue
        )
        let textWidth = (button.title as NSString).size(withAttributes: [.font: button.font as Any]).width
        XCTAssertGreaterThanOrEqual(
            button.intrinsicContentSize.width,
            ceil(textWidth + button.theme.controlPadding.left + button.theme.controlPadding.right)
        )
    }

    @MainActor
    func testLayoutBoundariesYieldWhileParentHasNoArrangeSlot() throws {
        _ = NSApplication.shared
        let host = FluentViewHost(
            FluentVStack(spacing: 12, alignment: .width) {
                FluentText("Boundary-safe content")
                FluentDivider()
            }
            .padding(32)
        )
        host.frame = .zero
        host.layoutSubtreeIfNeeded()

        func firstView(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { firstView(identifier: identifier, in: $0) }.first
        }
        let container = try XCTUnwrap(firstView(identifier: "FluentKit.LayoutContainer", in: host))
        let trailing = try XCTUnwrap(
            container.constraints.first { $0.identifier == "FluentKit.LayoutBoundary.Trailing" }
        )
        let bottom = try XCTUnwrap(
            container.constraints.first { $0.identifier == "FluentKit.LayoutBoundary.Bottom" }
        )
        XCTAssertLessThan(trailing.priority.rawValue, NSLayoutConstraint.Priority.required.rawValue)
        XCTAssertLessThan(bottom.priority.rawValue, NSLayoutConstraint.Priority.required.rawValue)

        host.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        host.layoutSubtreeIfNeeded()
        let child = try XCTUnwrap(container.subviews.first)
        XCTAssertEqual(child.frame.minX, 32, accuracy: 0.001)
        XCTAssertEqual(child.frame.maxX, container.bounds.maxX - 32, accuracy: 0.001)
    }

    @MainActor
    func testNavigationContentDefersAutoresizingMaskUntilFirstArrangeSlot() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "home")
        let host = FluentViewHost(
            FluentNavigationView(
                [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
                selection: selection.projectedValue,
                paneDisplayMode: .left
            ) {
                FluentText("Arranged content")
                    .padding(32)
            }
        )
        host.frame = NSRect.zero
        host.layoutSubtreeIfNeeded()

        func firstView(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { firstView(identifier: identifier, in: $0) }.first
        }
        let presenter = try XCTUnwrap(
            firstView(identifier: "FluentKit.NavigationView.Content", in: host)
        )
        XCTAssertFalse(presenter.translatesAutoresizingMaskIntoConstraints)

        host.frame = NSRect(x: 0, y: 0, width: 900, height: 520)
        host.layoutSubtreeIfNeeded()
        let page = try XCTUnwrap(presenter.subviews.first)
        XCTAssertTrue(presenter.translatesAutoresizingMaskIntoConstraints)
        XCTAssertGreaterThan(presenter.frame.width, 0)
        XCTAssertEqual(page.frame.width, presenter.bounds.width, accuracy: 0.001)
        XCTAssertEqual(page.frame.height, presenter.bounds.height, accuracy: 0.001)
    }

    func testNavigationItemSlotsMirrorAsOneUnitForRightToLeftLayout() {
        let bounds = NSRect(x: 0, y: 0, width: 232, height: 40)
        let leftToRight = FluentNavigationItemHorizontalGeometry.resolve(
            in: bounds,
            top: false,
            expanded: true,
            depth: 1,
            hasChildren: true,
            rightToLeft: false
        )
        let rightToLeft = FluentNavigationItemHorizontalGeometry.resolve(
            in: bounds,
            top: false,
            expanded: true,
            depth: 1,
            hasChildren: true,
            rightToLeft: true
        )

        func mirrored(_ rect: NSRect) -> NSRect {
            NSRect(
                x: bounds.minX + bounds.maxX - rect.maxX,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
        }

        XCTAssertEqual(rightToLeft.iconFrame, mirrored(leftToRight.iconFrame))
        XCTAssertEqual(rightToLeft.textFrame, mirrored(leftToRight.textFrame))
        XCTAssertEqual(rightToLeft.chevronFrame, leftToRight.chevronFrame.map(mirrored))
        XCTAssertGreaterThanOrEqual(leftToRight.textFrame.minX - leftToRight.iconFrame.maxX, 8)
        XCTAssertGreaterThanOrEqual(
            (leftToRight.chevronFrame?.minX ?? 0) - leftToRight.textFrame.maxX,
            8
        )
        XCTAssertGreaterThanOrEqual(rightToLeft.textFrame.minX - (rightToLeft.chevronFrame?.maxX ?? 0), 8)
        XCTAssertGreaterThanOrEqual(rightToLeft.iconFrame.minX - rightToLeft.textFrame.maxX, 8)

        let badgedLeftToRight = FluentNavigationItemHorizontalGeometry.resolve(
            in: bounds,
            top: false,
            expanded: true,
            depth: 0,
            hasChildren: true,
            rightToLeft: false,
            infoBadgeSize: NSSize(width: 16, height: 16)
        )
        let badgedRightToLeft = FluentNavigationItemHorizontalGeometry.resolve(
            in: bounds,
            top: false,
            expanded: true,
            depth: 0,
            hasChildren: true,
            rightToLeft: true,
            infoBadgeSize: NSSize(width: 16, height: 16)
        )
        let leftBadge = badgedLeftToRight.infoBadgeFrame
        let rightBadge = badgedRightToLeft.infoBadgeFrame
        XCTAssertEqual(rightBadge, leftBadge.map(mirrored))
        XCTAssertGreaterThanOrEqual((leftBadge?.minX ?? 0) - badgedLeftToRight.textFrame.maxX, 8)
        XCTAssertGreaterThanOrEqual(
            (badgedLeftToRight.chevronFrame?.minX ?? 0) - (leftBadge?.maxX ?? 0),
            8
        )
        XCTAssertGreaterThanOrEqual(
            badgedRightToLeft.textFrame.minX - (rightBadge?.maxX ?? 0),
            8
        )

        let compactLeftToRight = FluentNavigationItemHorizontalGeometry.resolve(
            in: NSRect(x: 0, y: 0, width: 40, height: 40),
            top: false,
            expanded: false,
            depth: 0,
            hasChildren: false,
            rightToLeft: false,
            infoBadgeSize: NSSize(width: 4, height: 4)
        )
        let compactRightToLeft = FluentNavigationItemHorizontalGeometry.resolve(
            in: NSRect(x: 0, y: 0, width: 40, height: 40),
            top: false,
            expanded: false,
            depth: 0,
            hasChildren: false,
            rightToLeft: true,
            infoBadgeSize: NSSize(width: 4, height: 4)
        )
        XCTAssertEqual(compactLeftToRight.infoBadgeFrame, NSRect(x: 34, y: 2, width: 4, height: 4))
        XCTAssertEqual(compactRightToLeft.infoBadgeFrame, NSRect(x: 2, y: 2, width: 4, height: 4))

        let topBadge = FluentNavigationItemHorizontalGeometry.resolve(
            in: NSRect(x: 0, y: 0, width: 128, height: 40),
            top: true,
            expanded: true,
            depth: 0,
            hasChildren: false,
            rightToLeft: false,
            infoBadgeSize: NSSize(width: 16, height: 16)
        )
        XCTAssertEqual(topBadge.infoBadgeFrame?.minY ?? -1, 5.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            (topBadge.infoBadgeFrame?.minX ?? 0) - topBadge.textFrame.maxX,
            8
        )
    }

    @MainActor
    func testNavigationItemHostsInfoBadgeInDedicatedPresenter() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "inbox")
        let item = FluentNavigationItem(
            id: "inbox",
            title: "Inbox",
            systemImageName: "tray"
        ) {
            FluentInfoBadge(value: 7, accessibilityLabel: "7 unread items")
        }
        let host = FluentViewHost(
            FluentNavigationView([item], selection: selection.projectedValue, paneDisplayMode: .left) {
                FluentText("Inbox")
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        host.layoutSubtreeIfNeeded()

        func descendants(in root: NSView) -> [NSView] {
            root.subviews + root.subviews.flatMap(descendants(in:))
        }
        let itemButton = try XCTUnwrap(
            descendants(in: host).first {
                $0.identifier?.rawValue == "FluentKit.NavigationView.Item"
                    && $0.accessibilityTitle() == "Inbox"
            }
        )
        let presenter = try XCTUnwrap(
            itemButton.subviews.first {
                $0.identifier?.rawValue == "FluentKit.NavigationView.Item.InfoBadge"
            }
        )
        let badge = try XCTUnwrap(
            descendants(in: presenter).first {
                $0.identifier?.rawValue == "FluentKit.InfoBadge"
            }
        )
        let valueLabel = try XCTUnwrap(
            descendants(in: badge).first {
                $0.identifier?.rawValue == "FluentKit.InfoBadge.Value"
            } as? NSTextField
        )
        XCTAssertFalse(presenter.isHidden)
        XCTAssertEqual(badge.accessibilityValue() as? String, "7")
        XCTAssertEqual(presenter.frame.height, 16, accuracy: 0.001)
        XCTAssertLessThan(presenter.frame.maxX, itemButton.bounds.maxX)
        XCTAssertGreaterThan(valueLabel.frame.width, 0)
        XCTAssertGreaterThan(valueLabel.frame.height, 0)

        host.update(
            FluentNavigationView(
                [FluentNavigationItem(id: "inbox", title: "Inbox", systemImageName: "tray")],
                selection: selection.projectedValue,
                paneDisplayMode: .left
            ) {
                FluentText("Inbox")
            }
        )
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(presenter.isHidden)
        XCTAssertFalse(
            descendants(in: presenter).contains {
                $0.identifier?.rawValue == "FluentKit.InfoBadge"
            }
        )
    }

    @MainActor
    func testNavigationRightToLeftSectionHeaderAndItemsExposeMirroredDirection() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "home")
        let host = FluentViewHost(
            FluentNavigationView(
                [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
                selection: selection.projectedValue,
                paneDisplayMode: .left,
                paneSectionTitle: "Explore"
            ) {
                FluentText("Content")
            },
            context: FluentRenderContext(layoutDirection: .rightToLeft)
        )
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        host.layoutSubtreeIfNeeded()

        func descendants(in root: NSView) -> [NSView] {
            root.subviews + root.subviews.flatMap(descendants(in:))
        }
        let sectionHost = try XCTUnwrap(
            descendants(in: host).first {
                $0.identifier?.rawValue == "FluentKit.NavigationView.SectionHeader"
            }
        )
        let sectionLabel = try XCTUnwrap(sectionHost.subviews.first as? NSTextField)
        let item = try XCTUnwrap(
            descendants(in: host).first {
                $0.identifier?.rawValue == "FluentKit.NavigationView.Item"
            }
        )
        XCTAssertEqual(sectionLabel.alignment, .right)
        XCTAssertEqual(sectionLabel.userInterfaceLayoutDirection, .rightToLeft)
        XCTAssertEqual(item.userInterfaceLayoutDirection, .rightToLeft)
    }

    @MainActor
    func testNavigationGroupExpansionAnimatesReflowAndChildVisibility() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: nil)
        let group = FluentNavigationItem(
            id: "group",
            title: "Group",
            systemImageName: "folder",
            children: [
                FluentNavigationItem(id: "child", title: "Child", systemImageName: "doc")
            ]
        )
        let host = FluentViewHost(
            FluentNavigationView(
                [
                    group,
                    FluentNavigationItem(id: "tail", title: "Tail", systemImageName: "star")
                ],
                selection: selection.projectedValue,
                paneDisplayMode: .left,
                content: { FluentText("Content") }
            ),
            context: FluentRenderContext(reduceMotion: false)
        )
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        host.layoutSubtreeIfNeeded()

        func buttons(in root: NSView) -> [NSButton] {
            root.subviews.flatMap { subview in
                let own = subview as? NSButton
                return (own.map { [$0] } ?? []) + buttons(in: subview)
            }
        }
        let groupButton = try XCTUnwrap(buttons(in: host).first { $0.accessibilityTitle() == "Group" })
        let tailButton = try XCTUnwrap(buttons(in: host).first { $0.accessibilityTitle() == "Tail" })
        groupButton.performClick(nil)

        let expansionReflow = try XCTUnwrap(
            tailButton.layer?.animation(forKey: "fluent.navigation.item.reflow.position")
                as? CABasicAnimation
        )
        XCTAssertEqual(expansionReflow.keyPath, "transform.translation.y")
        let childButton = try XCTUnwrap(buttons(in: host).first { $0.accessibilityTitle() == "Child" })
        let childTranslation = try XCTUnwrap(
            childButton.layer?.animation(forKey: "fluent.navigation.item.expansion.position")
                as? CABasicAnimation
        )
        XCTAssertEqual(childTranslation.keyPath, "transform.translation.y")

        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        groupButton.performClick(nil)
        let collapseReflow = try XCTUnwrap(
            tailButton.layer?.animation(forKey: "fluent.navigation.item.reflow.position")
                as? CABasicAnimation
        )
        XCTAssertEqual(collapseReflow.keyPath, "transform.translation.y")
        XCTAssertNotNil(childButton.layer?.animation(forKey: "fluent.navigation.item.expansion"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    @MainActor
    func testNavigationGroupExpansionPreservesScrollAnchor() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: nil)
        let children = (0..<6).map {
            FluentNavigationItem(id: "child-\($0)", title: "Child \($0)", systemImageName: "doc")
        }
        let rows = (0..<18).map {
            FluentNavigationItem(id: "row-\($0)", title: "Row \($0)", systemImageName: "circle")
        }
        let group = FluentNavigationItem(
            id: "group",
            title: "Group",
            systemImageName: "folder",
            children: children
        )
        let host = FluentViewHost(
            FluentNavigationView(
                rows + [group],
                selection: selection.projectedValue,
                paneDisplayMode: .left,
                content: { FluentText("Content") }
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 420)
        host.layoutSubtreeIfNeeded()

        func firstView(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { firstView(identifier: identifier, in: $0) }.first
        }
        func buttons(in root: NSView) -> [NSButton] {
            root.subviews.flatMap { subview in
                let own = subview as? NSButton
                return (own.map { [$0] } ?? []) + buttons(in: subview)
            }
        }

        let scrollView = try XCTUnwrap(
            firstView(identifier: "FluentKit.NavigationView.PrimaryScroll", in: host) as? NSScrollView
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 160))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let originBefore = scrollView.contentView.bounds.origin.y
        let groupButton = try XCTUnwrap(buttons(in: host).first { $0.accessibilityTitle() == "Group" })

        groupButton.performClick(nil)

        XCTAssertEqual(scrollView.contentView.bounds.origin.y, originBefore, accuracy: 0.001)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    @MainActor
    func testWindowTabsMoveDetachMergeAndPreserveStableContentState() {
        _ = NSApplication.shared
        let firstState = FluentState(wrappedValue: "preserved")
        let coordinator = FluentWindowTabCoordinator(
            configuration: FluentWindowTabConfiguration(
                size: NSSize(width: 620, height: 420),
                minimumSize: NSSize(width: 420, height: 280),
                material: .mica,
                showsAddTabButton: false,
                context: FluentRenderContext(reduceMotion: true)
            )
        )
        let first = FluentWindowTab(id: "first", title: "First") {
            FluentTextFieldView(text: firstState.projectedValue)
        }
        let second = FluentWindowTab(id: "second", title: "Second") {
            FluentText("Second")
        }

        let originalGroup = coordinator.open(first)
        _ = coordinator.open(second, in: originalGroup)
        XCTAssertEqual(coordinator.tabs(in: originalGroup).map(\.id), [AnyHashable("first"), AnyHashable("second")])
        coordinator.window(for: originalGroup)?.contentView?.layoutSubtreeIfNeeded()
        func firstView(identifier: String, in root: NSView?) -> NSView? {
            guard let root else { return nil }
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { firstView(identifier: identifier, in: $0) }.first
        }
        let mountedTabView = firstView(identifier: "FluentKit.TabView", in: coordinator.window(for: originalGroup)?.contentView)
        XCTAssertNotNil(mountedTabView)
        if let mountedTabView, let contentView = coordinator.window(for: originalGroup)?.contentView {
            XCTAssertEqual(mountedTabView.frame.minY, 0, accuracy: 0.001)
            XCTAssertEqual(mountedTabView.frame.height, contentView.bounds.height, accuracy: 0.001)
            XCTAssertEqual(mountedTabView.bounds.height, contentView.bounds.height, accuracy: 0.001)
            let contentContainer = firstView(identifier: "FluentKit.TabView.Content", in: mountedTabView)
            let selectedContent = firstView(identifier: "FluentKit.TabView.Content.0", in: mountedTabView)
            XCTAssertEqual(contentContainer?.frame.minY ?? -1, 40, accuracy: 0.001)
            XCTAssertEqual(contentContainer?.frame.maxY ?? -1, mountedTabView.bounds.maxY, accuracy: 0.001)
            XCTAssertEqual(selectedContent?.frame, contentContainer?.bounds)
            XCTAssertTrue(selectedContent?.translatesAutoresizingMaskIntoConstraints == true)
        }

        let detachedGroup = coordinator.detach(
            tabID: AnyHashable("second"),
            at: NSPoint(x: 320, y: 480),
            pointerOffset: NSPoint(x: 20, y: 12)
        )
        XCTAssertNotNil(detachedGroup)
        XCTAssertNotEqual(detachedGroup, originalGroup)
        XCTAssertEqual(coordinator.tabs(in: originalGroup).map(\.id), [AnyHashable("first")])
        XCTAssertEqual(detachedGroup.map { coordinator.tabs(in: $0).map(\.id) }, [AnyHashable("second")])

        if detachedGroup != nil {
            XCTAssertTrue(coordinator.move(tabID: AnyHashable("second"), to: originalGroup, at: 0))
            XCTAssertEqual(coordinator.tabs(in: originalGroup).map(\.id), [AnyHashable("second"), AnyHashable("first")])
        }
        firstState.wrappedValue = "still preserved"
        XCTAssertEqual(firstState.wrappedValue, "still preserved")

        XCTAssertEqual(coordinator.groupIDs, [originalGroup])
        coordinator.close(groupID: originalGroup)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    func testWindowTabCloseCanBeVetoed() {
        _ = NSApplication.shared
        let coordinator = FluentWindowTabCoordinator(
            configuration: FluentWindowTabConfiguration(material: nil, showsAddTabButton: false)
        )
        let group = coordinator.open(
            FluentWindowTab(id: 1, title: "Unsaved", shouldClose: { false }) {
                FluentText("Unsaved")
            }
        )

        coordinator.close(tabID: AnyHashable(1))
        XCTAssertEqual(coordinator.tabs(in: group).count, 1)
        coordinator.window(for: group)?.close()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    @MainActor
    func testWindowTabDefaultsAndLiveThemeUpdatePreserveGroupState() throws {
        _ = NSApplication.shared
        XCTAssertEqual(
            FluentWindowTabConfiguration().windowsLeadingTitleBarInset,
            12,
            accuracy: 0.001
        )

        let coordinator = FluentWindowTabCoordinator(
            configuration: FluentWindowTabConfiguration(
                material: nil,
                windowControlsStyle: .windows,
                showsAddTabButton: false,
                context: FluentRenderContext(
                    theme: FluentTheme(colorScheme: .light),
                    reduceMotion: true
                )
            )
        )
        let group = coordinator.open(
            FluentWindowTab(id: "theme", title: "Theme") {
                FluentText("Theme content")
            }
        )
        let window = try XCTUnwrap(coordinator.window(for: group))
        let windowsControls = try XCTUnwrap(window.titlebarAccessoryViewControllers.first)
        XCTAssertEqual(
            windowsControls.preferredContentSize.height,
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(window.fluentAppearanceCoordinator?.theme.colorScheme, .light)

        coordinator.updateTheme(FluentTheme(colorScheme: .dark))

        XCTAssertEqual(window.fluentAppearanceCoordinator?.theme.colorScheme, .dark)
        XCTAssertEqual(coordinator.groupIDs, [group])
        XCTAssertEqual(coordinator.tabs(in: group).map(\.id), [AnyHashable("theme")])
        coordinator.close(groupID: group)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    @MainActor
    func testTabDragMovesInsideStripBeforeCommittingReorder() throws {
        _ = NSApplication.shared
        var moveRequests: [(Int, Int)] = []
        let tabView = FluentTabView(
            items: [
                FluentTabItem(id: "first", title: "First") { FluentText("First") },
                FluentTabItem(id: "second", title: "Second") { FluentText("Second") },
                FluentTabItem(id: "third", title: "Third") { FluentText("Third") }
            ],
            isAddTabButtonVisible: false,
            canDragTabs: true,
            canReorderTabs: true,
            tearOutDistance: 24,
            onTabMoveRequested: { moveRequests.append(($0, $1)) }
        )
        let host = FluentViewHost(tabView, context: FluentRenderContext(reduceMotion: false))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = window.contentView?.bounds ?? .zero
        host.layoutSubtreeIfNeeded()

        func descendants(identifier: String, in root: NSView) -> [NSView] {
            let own = root.identifier?.rawValue == identifier ? [root] : []
            return own + root.subviews.flatMap { descendants(identifier: identifier, in: $0) }
        }
        let tabs = descendants(identifier: "FluentKit.TabView.Tab", in: host)
            .sorted { $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX }
        XCTAssertEqual(tabs.count, 3)
        let first = try XCTUnwrap(tabs.first)
        let third = try XCTUnwrap(tabs.last)
        let start = first.convert(NSPoint(x: first.bounds.midX, y: first.bounds.midY), to: nil)
        let destination = third.convert(NSPoint(x: third.bounds.midX, y: third.bounds.midY), to: nil)
        func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }

        first.mouseDown(with: try mouseEvent(.leftMouseDown, at: start, number: 1))
        first.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: destination, number: 2))
        XCTAssertGreaterThan(first.layer?.transform.m41 ?? 0, 1)
        XCTAssertEqual(first.layer?.transform.m11 ?? 0, 1, accuracy: 0.001)
        XCTAssertLessThan(tabs[1].layer?.transform.m41 ?? 0, -1)
        XCTAssertNotNil(tabs[1].layer?.animation(forKey: "fluent.tabview.drag.reorder"))
        XCTAssertTrue(moveRequests.isEmpty)

        first.mouseUp(with: try mouseEvent(.leftMouseUp, at: destination, number: 3))
        XCTAssertEqual(moveRequests.map { [$0.0, $0.1] }, [[0, 2]])
        XCTAssertTrue(tabs.allSatisfy {
            abs($0.layer?.transform.m41 ?? 0) < 0.001
                && abs(($0.layer?.transform.m11 ?? 0) - 1) < 0.001
        })
        window.orderOut(nil)
    }

    @MainActor
    func testRadioButtonUsesWinUIControlAltResources() throws {
        _ = NSApplication.shared
        let light = FluentTheme(colorScheme: .light)
        let dark = FluentTheme(colorScheme: .dark)

        func alpha(_ color: NSColor) throws -> CGFloat {
            try XCTUnwrap(color.usingColorSpace(.deviceRGB)).alphaComponent
        }

        XCTAssertEqual(try alpha(light.controlAltFillSecondary), 6.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(try alpha(light.controlAltFillTertiary), 15.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(try alpha(light.controlAltFillQuaternary), 24.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(try alpha(dark.controlAltFillSecondary), 25.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(try alpha(dark.controlAltFillTertiary), 11.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(try alpha(dark.controlAltFillQuaternary), 18.0 / 255.0, accuracy: 0.0001)

        let style = FluentAutomaticRadioButtonStyle()
        let normal = style.appearance(for: FluentRadioButtonStyleConfiguration(
            isSelected: false,
            isEnabled: true,
            controlSize: .regular,
            theme: light
        ))
        let disabled = style.appearance(for: FluentRadioButtonStyleConfiguration(
            isSelected: false,
            isEnabled: false,
            controlSize: .regular,
            theme: light
        ))
        XCTAssertEqual(normal.diameter, 20, accuracy: 0.001)
        XCTAssertEqual(normal.dotDiameter, 12, accuracy: 0.001)
        XCTAssertEqual(disabled.dotDiameter, 14, accuracy: 0.001)
        XCTAssertEqual(try alpha(disabled.fillColor), 0, accuracy: 0.0001)

        let radio = FluentRadioButton(title: "Choice")
        radio.theme = light
        radio.reduceMotion = true
        radio.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 32),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = radio
        radio.layoutSubtreeIfNeeded()
        let outer = try XCTUnwrap(radio.layer?.sublayers?.first {
            $0.name == "FluentKit.RadioButton.Outer"
        })
        let pressedDot = try XCTUnwrap(radio.layer?.sublayers?.first {
            $0.name == "FluentKit.RadioButton.PressedDot"
        })

        func components(_ color: NSColor) throws -> [CGFloat] {
            let converted = try XCTUnwrap(color.usingColorSpace(.deviceRGB))
            return [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent]
        }
        func assertColor(_ actual: CGColor?, equals expected: NSColor, line: UInt = #line) throws {
            let actual = try XCTUnwrap(actual.flatMap(NSColor.init(cgColor:)), line: line)
            let lhs = try components(actual)
            let rhs = try components(expected)
            for index in lhs.indices { XCTAssertEqual(lhs[index], rhs[index], accuracy: 0.001, line: line) }
        }
        func mouseEvent(_ type: NSEvent.EventType, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: 10, y: 16),
                modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }

        radio.mouseEntered(with: try mouseEvent(.mouseMoved, number: 1))
        try assertColor(outer.backgroundColor, equals: light.controlAltFillTertiary)
        radio.mouseDown(with: try mouseEvent(.leftMouseDown, number: 2))
        try assertColor(outer.backgroundColor, equals: light.controlAltFillQuaternary)
        XCTAssertEqual(pressedDot.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(pressedDot.bounds.width, 10, accuracy: 0.001)
        XCTAssertEqual(pressedDot.bounds.height, 10, accuracy: 0.001)
        radio.cancelOperation(nil)
        XCTAssertEqual(pressedDot.opacity, 0, accuracy: 0.001)
        window.orderOut(nil)
    }

    @MainActor
    func testRadioButtonMatchesWinUIPressLifecycleAndIndependentGroupWrapping() throws {
        _ = NSApplication.shared
        let radio = FluentRadioButton(title: "Choice")
        radio.reduceMotion = true
        radio.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        root.addSubview(radio)
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        radio.layoutSubtreeIfNeeded()
        let pressedDot = try XCTUnwrap(radio.layer?.sublayers?.first {
            $0.name == "FluentKit.RadioButton.PressedDot"
        })

        func key(_ type: NSEvent.EventType, code: UInt16, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber, context: nil,
                characters: code == 49 ? " " : "\r", charactersIgnoringModifiers: code == 49 ? " " : "\r",
                isARepeat: false, keyCode: code
            ))
        }
        func pointer(_ type: NSEvent.EventType, at point: NSPoint, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber, context: nil, eventNumber: number,
                clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
            ))
        }

        radio.keyDown(with: try key(.keyDown, code: 49, number: 1))
        XCTAssertFalse(radio.isSelected, "Space keyDown only enters WinUI's Pressed state")
        XCTAssertEqual(pressedDot.opacity, 1, accuracy: 0.001)
        radio.keyUp(with: try key(.keyUp, code: 49, number: 2))
        XCTAssertTrue(radio.isSelected, "Space commits on keyUp")
        XCTAssertEqual(pressedDot.opacity, 0, accuracy: 0.001)

        radio.isSelected = false
        radio.keyDown(with: try key(.keyDown, code: 36, number: 3))
        radio.keyUp(with: try key(.keyUp, code: 36, number: 4))
        XCTAssertFalse(radio.isSelected, "WinUI RadioButton does not accept Return")

        let inside = NSPoint(x: 10, y: 16)
        let outside = NSPoint(x: 220, y: 80)
        radio.mouseDown(with: try pointer(.leftMouseDown, at: inside, number: 5))
        XCTAssertEqual(pressedDot.opacity, 1, accuracy: 0.001)
        radio.mouseDragged(with: try pointer(.leftMouseDragged, at: outside, number: 6))
        XCTAssertEqual(pressedDot.opacity, 0, accuracy: 0.001, "dragging out cancels Pressed")
        radio.mouseDragged(with: try pointer(.leftMouseDragged, at: inside, number: 7))
        XCTAssertEqual(pressedDot.opacity, 1, accuracy: 0.001, "dragging back restores Pressed")
        radio.mouseUp(with: try pointer(.leftMouseUp, at: inside, number: 8))
        XCTAssertTrue(radio.isSelected)

        let highContrast = FluentTheme(contrast: .high, colorScheme: .dark)
        let automatic = FluentAutomaticRadioButtonStyle()
        let hcPressed = automatic.appearance(for: .init(
            isSelected: false, isEnabled: true, isPointerOver: true, isPressed: true,
            controlSize: .regular, theme: highContrast
        ))
        XCTAssertEqual(hcPressed.borderWidth, 1, accuracy: 0.001)
        XCTAssertEqual(hcPressed.dotDiameter, 10, accuracy: 0.001)
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            XCTAssertEqual(hcPressed.pressedFeedbackColor.usingColorSpace(.deviceRGB),
                           NSColor.selectedContentBackgroundColor.usingColorSpace(.deviceRGB))
        }

        let first = FluentRadioButton(title: "First", isSelected: true)
        let second = FluentRadioButton(title: "Second")
        let third = FluentRadioButton(title: "Third")
        let stack = NSStackView(views: [first, second, third])
        stack.orientation = .vertical
        stack.frame = NSRect(x: 0, y: 0, width: 180, height: 96)
        root.subviews.forEach { $0.removeFromSuperview() }
        root.addSubview(stack)
        stack.layoutSubtreeIfNeeded()
        first.keyDown(with: try key(.keyDown, code: 123, number: 9))
        XCTAssertTrue(third.isSelected, "Left from the first independent RadioButton wraps to the last")
        third.keyDown(with: try key(.keyDown, code: 125, number: 10))
        XCTAssertTrue(first.isSelected, "Down from the last independent RadioButton wraps to the first")
        window.orderOut(nil)
    }

    @MainActor
    func testImplicitRadioButtonGroupIsMutuallyExclusiveAndCannotUserClearSelection() {
        _ = NSApplication.shared
        var firstValue = false
        var secondValue = true
        let first = FluentBoundRadioButton(
            FluentBinding(get: { firstValue }, set: { firstValue = $0 }),
            title: "First"
        )
        let second = FluentBoundRadioButton(
            FluentBinding(get: { secondValue }, set: { secondValue = $0 }),
            title: "Second"
        )
        let stack = NSStackView(views: [first, second])
        stack.orientation = .vertical

        XCTAssertFalse(first.radioButton.isSelected)
        XCTAssertTrue(second.radioButton.isSelected)
        XCTAssertTrue(first.radioButton.accessibilityPerformPress())
        XCTAssertTrue(firstValue)
        XCTAssertFalse(secondValue)
        XCTAssertTrue(first.radioButton.isSelected)
        XCTAssertFalse(second.radioButton.isSelected)

        XCTAssertTrue(first.radioButton.accessibilityPerformPress())
        XCTAssertTrue(firstValue, "A user cannot clear the selected radio button by pressing it again")
        XCTAssertTrue(first.radioButton.isSelected)
    }

    @MainActor
    func testRadioButtonsOwnsSelectionLayoutAccessibilityAndArrowNavigation() throws {
        _ = NSApplication.shared
        let selected = FluentState<String?>(wrappedValue: "Second")
        var changes: [(String?, String?)] = []
        let group = FluentRadioButtons(
            ["First", "Second", "Disabled", "Fourth"],
            selection: selected.projectedValue,
            header: "Options",
            maxColumns: 2,
            isEnabled: { $0 != "Disabled" },
            onSelectionChanged: { changes.append(($0, $1)) }
        )
        let native = group._makeView(in: FluentRenderContext(reduceMotion: true))
        native.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = native
        native.layoutSubtreeIfNeeded()
        let radios = native.subviews.compactMap { $0 as? FluentRadioButton }
        XCTAssertEqual(radios.count, 4)
        XCTAssertEqual(native.accessibilityRole(), .radioGroup)
        XCTAssertEqual(native.accessibilityLabel(), "Options")
        XCTAssertFalse(radios[0].isSelected)
        XCTAssertTrue(radios[1].isSelected)
        XCTAssertFalse(radios[2].isEnabled)
        XCTAssertEqual(radios[3].accessibilityHelp(), "Option 4 of 4")

        // WinUI's layout is column-major: First/Second occupy column one, Disabled/Fourth column two.
        XCTAssertEqual(radios[0].frame.minX, radios[1].frame.minX, accuracy: 0.001)
        XCTAssertGreaterThan(radios[2].frame.minX, radios[0].frame.minX)
        XCTAssertLessThan(radios[0].frame.minY, radios[1].frame.minY)

        XCTAssertTrue(radios[0].accessibilityPerformPress())
        XCTAssertEqual(selected.wrappedValue, "First")
        XCTAssertTrue(radios[0].isSelected)
        XCTAssertTrue(radios.dropFirst().allSatisfy { !$0.isSelected })
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].0, "Second")
        XCTAssertEqual(changes[0].1, "First")

        func keyEvent(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            ))
        }

        radios[0].keyDown(with: try keyEvent(125))
        XCTAssertEqual(selected.wrappedValue, "Second")
        XCTAssertTrue(radios[1].isSelected)
        radios[1].keyDown(with: try keyEvent(126, modifiers: .control))
        XCTAssertEqual(selected.wrappedValue, "Second", "Control+arrow moves focus without selection")
        XCTAssertTrue(window.firstResponder === radios[0])

        selected.wrappedValue = nil
        XCTAssertTrue(radios.allSatisfy { !$0.isSelected }, "Programmatic nil selection remains supported")
        window.orderOut(nil)
    }

    @MainActor
    func testRadioButtonsUsesGlobalUniformColumnsAndGroupDisabledState() throws {
        _ = NSApplication.shared
        let options = (1...10).map { "Option \($0)" }
        let selected = FluentState<String?>(wrappedValue: options[0])
        let context = FluentRenderContext(reduceMotion: true)
        let group = FluentRadioButtons(
            options,
            selection: selected.projectedValue,
            header: "Ten choices",
            maxColumns: 3,
            isGroupEnabled: false,
            isEnabled: { $0 != "Option 5" }
        )
        let native = group._makeView(in: context)
        native.frame = NSRect(x: 0, y: 0, width: 500, height: 220)
        native.layoutSubtreeIfNeeded()
        let radios = native.subviews.compactMap { $0 as? FluentRadioButton }
        let header = try XCTUnwrap(native.subviews.compactMap { $0 as? NSTextField }.first)

        XCTAssertEqual(radios.count, 10)
        XCTAssertTrue(radios.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(header.textColor, context.theme.textDisabled)
        XCTAssertFalse(try XCTUnwrap(native as? NSControl).isEnabled)

        // WinUI distributes the remainder into the leading columns: ten items / three columns = 4,3,3.
        XCTAssertEqual(radios[0].frame.minX, radios[3].frame.minX, accuracy: 0.001)
        XCTAssertGreaterThan(radios[4].frame.minX, radios[3].frame.minX)
        XCTAssertEqual(radios[4].frame.minX, radios[6].frame.minX, accuracy: 0.001)
        XCTAssertGreaterThan(radios[7].frame.minX, radios[6].frame.minX)
        let pitch1 = radios[4].frame.minX - radios[0].frame.minX
        let pitch2 = radios[7].frame.minX - radios[4].frame.minX
        XCTAssertEqual(pitch1, pitch2, accuracy: 0.001, "all columns use the global largest-child pitch")
        XCTAssertEqual(radios[0].frame.width, radios[9].frame.width, accuracy: 0.001)

        let enabled = FluentRadioButtons(
            options,
            selection: selected.projectedValue,
            header: "Ten choices",
            maxColumns: 3,
            isGroupEnabled: true,
            isEnabled: { $0 != "Option 5" }
        )
        XCTAssertTrue(enabled._update(native, in: context))
        XCTAssertEqual(header.textColor, context.theme.textPrimary)
        XCTAssertTrue(radios[0].isEnabled)
        XCTAssertFalse(radios[4].isEnabled, "per-option disabled state survives group re-enabling")
        XCTAssertTrue(try XCTUnwrap(native as? NSControl).isEnabled)
    }

    @MainActor
    func testRatingControlDefaultsCoercionPlaceholderAndSourceGeometry() throws {
        _ = NSApplication.shared
        let control = FluentRatingControl(placeholderValue: 3.5, caption: "312 ratings")
        XCTAssertEqual(control.value, FluentRatingControl.unsetValue)
        XCTAssertEqual(control.placeholderValue, 3.5)
        XCTAssertEqual(control.maxRating, 5)
        XCTAssertEqual(control.initialSetValue, 1)
        XCTAssertTrue(control.isClearEnabled)
        XCTAssertFalse(control.isReadOnly)
        XCTAssertEqual(control.intrinsicContentSize.height, 32, accuracy: 0.001)

        control.frame = NSRect(origin: .zero, size: control.intrinsicContentSize)
        control.layoutSubtreeIfNeeded()
        let foregrounds = (control.layer?.sublayers ?? [])
            .flatMap { $0.sublayers ?? [] }
            .filter { $0.name?.hasPrefix("FluentKit.RatingControl.Foreground.") == true }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
        XCTAssertEqual(foregrounds.count, 5)
        XCTAssertEqual(foregrounds[0].mask?.frame.width ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(foregrounds[1].mask?.frame.width ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(foregrounds[2].mask?.frame.width ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(foregrounds[3].mask?.frame.width ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(foregrounds[4].mask?.frame.width ?? -1, 0, accuracy: 0.001)
        let firstBackground = try XCTUnwrap((control.layer?.sublayers ?? [])
            .flatMap { $0.sublayers ?? [] }
            .first { $0.name == "FluentKit.RatingControl.Background.0" } as? CAShapeLayer)
        var starVertices: [CGPoint] = []
        firstBackground.path?.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                starVertices.append(element.pointee.points[0])
            }
        }
        XCTAssertGreaterThan(try XCTUnwrap(starVertices.first).y, 8,
                             "The first outer vertex must point toward twelve o'clock")

        control.value = 0
        XCTAssertEqual(control.value, 1, "WinUI coerces a programmatic 0...1 value to one")
        control.value = -20
        XCTAssertEqual(control.value, FluentRatingControl.unsetValue)
        control.value = 20
        XCTAssertEqual(control.value, 5)
        control.maxRating = 3
        XCTAssertEqual(control.value, 3)
        XCTAssertEqual(control.placeholderValue, 3)
    }

    @MainActor
    func testRatingControlPointerPreviewScaleClickClearAndDragClear() throws {
        _ = NSApplication.shared
        let control = FluentRatingControl()
        control.reduceMotion = true
        control.frame = NSRect(x: 0, y: 0, width: 112, height: 32)
        let window = NSWindow(
            contentRect: control.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = control
        control.layoutSubtreeIfNeeded()

        func mouseEvent(_ type: NSEvent.EventType, x: CGFloat, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: x, y: 16),
                modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
        func item(_ index: Int) throws -> CALayer {
            try XCTUnwrap(control.layer?.sublayers?.first {
                $0.name == "FluentKit.RatingControl.Item.\(index)"
            })
        }
        func foreground(_ index: Int) throws -> CALayer {
            try XCTUnwrap(try item(index).sublayers?.first {
                $0.name == "FluentKit.RatingControl.Foreground.\(index)"
            })
        }

        // The third star center is x=56 for source 16pt items with 8pt spacing.
        control.mouseMoved(with: try mouseEvent(.mouseMoved, x: 56, number: 1))
        XCTAssertEqual(try foreground(0).mask?.frame.width ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(try foreground(1).mask?.frame.width ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(try foreground(2).mask?.frame.width ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(try item(2).transform.m11, 1.6, accuracy: 0.001)
        XCTAssertEqual(try item(2).transform.m22, 1.6, accuracy: 0.001)

        control.mouseDown(with: try mouseEvent(.leftMouseDown, x: 56, number: 2))
        control.mouseUp(with: try mouseEvent(.leftMouseUp, x: 56, number: 3))
        XCTAssertEqual(control.value, 3)
        control.mouseDown(with: try mouseEvent(.leftMouseDown, x: 56, number: 4))
        control.mouseUp(with: try mouseEvent(.leftMouseUp, x: 56, number: 5))
        XCTAssertEqual(control.value, FluentRatingControl.unsetValue,
                       "Clicking the current rating clears it when IsClearEnabled is true")

        control.value = 4
        control.mouseDown(with: try mouseEvent(.leftMouseDown, x: 80, number: 6))
        control.mouseDragged(with: try mouseEvent(.leftMouseDragged, x: -10, number: 7))
        control.mouseUp(with: try mouseEvent(.leftMouseUp, x: -10, number: 8))
        XCTAssertEqual(control.value, FluentRatingControl.unsetValue)

        control.isClearEnabled = false
        control.value = 2
        control.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 115
        )))
        XCTAssertEqual(control.value, 1)
        window.orderOut(nil)
    }

    @MainActor
    func testRatingControlKeyboardFractionRtlReadOnlyAndBinding() throws {
        _ = NSApplication.shared
        let state = FluentState<Double>(wrappedValue: 2.5)
        let view = FluentRatingControlView(
            value: state.projectedValue,
            initialSetValue: 2,
            caption: "Quality"
        )
        let host = FluentViewHost(view, context: FluentRenderContext(reduceMotion: true))
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        func descendants<T>(of type: T.Type, in root: NSView) -> [T] {
            let own = (root as? T).map { [$0] } ?? []
            return own + root.subviews.flatMap { descendants(of: type, in: $0) }
        }
        let control = try XCTUnwrap(descendants(of: FluentRatingControl.self, in: host).first)
        func key(_ code: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
            ))
        }

        control.keyDown(with: try key(123))
        XCTAssertEqual(state.wrappedValue, 2, "Decrementing a fractional value drops its fraction")
        control.value = 2.5
        control.keyDown(with: try key(124))
        XCTAssertEqual(state.wrappedValue, 3, "Incrementing a fractional value rounds to the next integer")

        control.fluentLayoutDirection = .rightToLeft
        control.value = 2
        control.keyDown(with: try key(123))
        XCTAssertEqual(state.wrappedValue, 3, "Left increases in RTL")
        control.keyDown(with: try key(124))
        XCTAssertEqual(state.wrappedValue, 2, "Right decreases in RTL")
        control.keyDown(with: try key(126))
        XCTAssertEqual(state.wrappedValue, 3, "Up always increases")
        control.keyDown(with: try key(125))
        XCTAssertEqual(state.wrappedValue, 2, "Down always decreases")
        control.keyDown(with: try key(119))
        XCTAssertEqual(state.wrappedValue, 5)
        control.keyDown(with: try key(119))
        XCTAssertEqual(state.wrappedValue, 5, "Keyboard End does not clear a maximum rating")

        state.wrappedValue = 4.5
        XCTAssertEqual(control.value, 4.5)
        XCTAssertEqual(control.accessibilityRole(), .slider)
        XCTAssertEqual(control.accessibilityLabel(), "Quality")
        XCTAssertEqual(control.accessibilityMaxValue() as? Double, 5)
        XCTAssertTrue(control.accessibilityPerformDecrement())
        XCTAssertEqual(state.wrappedValue, 4)
        control.maxRating = 3
        XCTAssertEqual(control.value, 3)
        XCTAssertEqual(state.wrappedValue, 3, "MaxRating coercion publishes the normalized value")
        state.wrappedValue = 99
        XCTAssertEqual(control.value, 3)
        XCTAssertEqual(state.wrappedValue, 3, "External out-of-range values are normalized back into the binding")
        control.isReadOnly = true
        control.keyDown(with: try key(123))
        XCTAssertEqual(state.wrappedValue, 3)
        XCTAssertFalse(control.accessibilityPerformIncrement())
        window.orderOut(nil)
    }

    @MainActor
    func testPipsPagerDefaultsSourceGeometryVirtualizationAndCoercion() throws {
        _ = NSApplication.shared
        let pager = FluentPipsPager()
        XCTAssertEqual(pager.numberOfPages, -1)
        XCTAssertEqual(pager.selectedPageIndex, 0)
        XCTAssertEqual(pager.maxVisiblePips, 5)
        XCTAssertEqual(pager.orientation, .horizontal)
        XCTAssertEqual(pager.previousButtonVisibility, .collapsed)
        XCTAssertEqual(pager.nextButtonVisibility, .collapsed)
        XCTAssertEqual(pager.wrapMode, .none)
        XCTAssertEqual(pager.intrinsicContentSize, NSSize(width: 60, height: 24))

        pager.frame = NSRect(origin: .zero, size: pager.intrinsicContentSize)
        pager.layoutSubtreeIfNeeded()
        XCTAssertEqual(pager.realizedPipButtons.count, 5)
        let selected = try XCTUnwrap(pager.realizedPipButtons[0])
        let normal = try XCTUnwrap(pager.realizedPipButtons[1])
        let selectedGlyph = try XCTUnwrap(selected.layer?.sublayers?[1] as? CAShapeLayer)
        let normalGlyph = try XCTUnwrap(normal.layer?.sublayers?[1] as? CAShapeLayer)
        XCTAssertEqual(try XCTUnwrap(selectedGlyph.path).boundingBox.width, 6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(normalGlyph.path).boundingBox.width, 4, accuracy: 0.001)
        XCTAssertEqual(selected.frame.size, NSSize(width: 12, height: 24))

        pager.numberOfPages = 20
        pager.selectedPageIndex = 10
        pager.frame = NSRect(origin: .zero, size: pager.intrinsicContentSize)
        pager.layoutSubtreeIfNeeded()
        XCTAssertEqual(pager.viewport.frame.width, 60, accuracy: 0.001)
        XCTAssertEqual(pager.viewport.bounds.origin.x, 96, accuracy: 0.001)
        XCTAssertLessThanOrEqual(pager.realizedPipButtons.count, 9, "ItemsRepeater-style virtualization must not realize all pages")
        XCTAssertTrue(pager.realizedPipButtons[10]?.isSelectedPip == true)

        var changes: [(Int, Int)] = []
        pager.onSelectedIndexChanged = { changes.append(($0, $1)) }
        pager.numberOfPages = 3
        XCTAssertEqual(pager.selectedPageIndex, 2)
        XCTAssertEqual(changes.last?.0, 10)
        XCTAssertEqual(changes.last?.1, 2)
        pager.selectedPageIndex = -50
        XCTAssertEqual(pager.selectedPageIndex, 0)
        pager.selectedPageIndex = 50
        XCTAssertEqual(pager.selectedPageIndex, 2)

        pager.numberOfPages = 0
        XCTAssertEqual(pager.selectedPageIndex, 0, "An empty WinUI PipsPager retains its required zero selection")
        XCTAssertEqual(pager.intrinsicContentSize.width, 0)

        pager.maxVisiblePips = 0
        XCTAssertEqual(pager.intrinsicContentSize.width, 0)
        XCTAssertTrue(pager.realizedPipButtons.isEmpty)
    }

    @MainActor
    func testPipsPagerNavigationVisibilityWrapInfiniteVerticalAndRTL() throws {
        _ = NSApplication.shared
        let pager = FluentPipsPager(
            numberOfPages: 3,
            selectedPageIndex: 0,
            previousButtonVisibility: .visible,
            nextButtonVisibility: .visible
        )
        pager.frame = NSRect(origin: .zero, size: pager.intrinsicContentSize)
        pager.layoutSubtreeIfNeeded()
        XCTAssertEqual(pager.intrinsicContentSize, NSSize(width: 84, height: 24))
        XCTAssertEqual(pager.previousButton.alphaValue, 0)
        XCTAssertFalse(pager.previousButton.isEnabled)
        XCTAssertEqual(pager.nextButton.alphaValue, 1)
        XCTAssertTrue(pager.nextButton.isEnabled)

        XCTAssertTrue(pager.selectNextPage())
        XCTAssertTrue(pager.selectNextPage())
        XCTAssertEqual(pager.selectedPageIndex, 2)
        XCTAssertEqual(pager.nextButton.alphaValue, 0)
        XCTAssertFalse(pager.nextButton.isEnabled)
        XCTAssertEqual(pager.previousButton.alphaValue, 1)

        pager.wrapMode = .wrap
        XCTAssertEqual(pager.nextButton.alphaValue, 1)
        XCTAssertTrue(pager.nextButton.isEnabled)
        XCTAssertTrue(pager.selectNextPage())
        XCTAssertEqual(pager.selectedPageIndex, 0)
        XCTAssertTrue(pager.selectPreviousPage())
        XCTAssertEqual(pager.selectedPageIndex, 2)

        pager.wrapMode = .none
        pager.selectedPageIndex = 1
        pager.previousButtonVisibility = .visibleOnPointerOver
        pager.nextButtonVisibility = .visibleOnPointerOver
        XCTAssertEqual(pager.previousButton.alphaValue, 0)
        XCTAssertTrue(pager.previousButton.isEnabled, "WinUI hides pointer-only buttons with opacity while retaining their enabled state")
        let entered = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: NSPoint(x: 1, y: 1), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ))
        pager.mouseEntered(with: entered)
        XCTAssertEqual(pager.previousButton.alphaValue, 1)
        XCTAssertEqual(pager.nextButton.alphaValue, 1)

        pager.orientation = .vertical
        pager.previousButtonVisibility = .collapsed
        pager.nextButtonVisibility = .collapsed
        pager.numberOfPages = 8
        pager.selectedPageIndex = 0
        pager.frame = NSRect(origin: .zero, size: pager.intrinsicContentSize)
        pager.layoutSubtreeIfNeeded()
        XCTAssertEqual(pager.intrinsicContentSize, NSSize(width: 24, height: 60))
        XCTAssertEqual(pager.realizedPipButtons[0]?.frame, NSRect(x: 0, y: 84, width: 24, height: 12))
        XCTAssertEqual(pager.viewport.bounds.origin.y, 36, accuracy: 0.001)
        XCTAssertEqual(pager.previousButton.direction, .up)
        XCTAssertEqual(pager.nextButton.direction, .down)

        pager.orientation = .horizontal
        pager.fluentLayoutDirection = .rightToLeft
        pager.previousButtonVisibility = .visible
        pager.nextButtonVisibility = .visible
        pager.frame = NSRect(origin: .zero, size: pager.intrinsicContentSize)
        pager.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(pager.realizedPipButtons[0]).frame.minX, 84, accuracy: 0.001)
        XCTAssertEqual(pager.previousButton.direction, .right)
        XCTAssertEqual(pager.nextButton.direction, .left)

        let infinite = FluentPipsPager(
            numberOfPages: -1,
            selectedPageIndex: 0,
            maxVisiblePips: 3,
            nextButtonVisibility: .visible
        )
        XCTAssertEqual(infinite.realizedPipButtons.count, 3)
        XCTAssertTrue(infinite.selectNextPage())
        XCTAssertTrue(infinite.selectNextPage())
        XCTAssertTrue(infinite.selectNextPage())
        XCTAssertEqual(infinite.selectedPageIndex, 3)
        XCTAssertNotNil(infinite.realizedPipButtons[4], "Infinite mode appends a following page when advancing")
    }

    @MainActor
    func testPipsPagerKeyboardSelectionAccessibilityAndBindingNormalization() throws {
        _ = NSApplication.shared
        let state = FluentState<Int>(wrappedValue: 99)
        var callback: (Int, Int)?
        let view = FluentPipsPagerView(
            selectedPageIndex: state.projectedValue,
            numberOfPages: 5,
            previousButtonVisibility: .visible,
            nextButtonVisibility: .visible,
            onSelectedIndexChanged: { callback = ($0, $1) }
        )
        let host = view._makeView(in: FluentRenderContext(reduceMotion: true))
        host.frame = NSRect(x: 0, y: 0, width: 108, height: 24)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 108, height: 24),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        func descendants<T>(of type: T.Type, in root: NSView) -> [T] {
            let own = (root as? T).map { [$0] } ?? []
            return own + root.subviews.flatMap { descendants(of: type, in: $0) }
        }
        let pager = try XCTUnwrap(descendants(of: FluentPipsPager.self, in: host).first)
        XCTAssertEqual(pager.selectedPageIndex, 4)
        XCTAssertEqual(state.wrappedValue, 4, "The declarative binding receives the source-coerced index")
        XCTAssertEqual(pager.accessibilityRole(), .menu)
        XCTAssertEqual(pager.accessibilitySelectedChildren()?.count, 1)
        let pageThree = try XCTUnwrap(pager.realizedPipButtons[2])
        XCTAssertEqual(pageThree.accessibilityLabel(), "Page 3")
        XCTAssertEqual(pageThree.accessibilityHelp(), "Page 3 of 5")
        XCTAssertTrue(pageThree.accessibilityPerformPress())
        XCTAssertEqual(state.wrappedValue, 2)
        XCTAssertEqual(callback?.0, 4)
        XCTAssertEqual(callback?.1, 2)

        state.wrappedValue = -10
        XCTAssertEqual(pager.selectedPageIndex, 0)
        XCTAssertEqual(state.wrappedValue, 0)

        let first = try XCTUnwrap(pager.realizedPipButtons[0])
        _ = window.makeFirstResponder(first)
        let right = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124
        ))
        first.keyDown(with: right)
        XCTAssertEqual(pager.selectedPageIndex, 0, "Arrow keys move focus without selecting")
        let focused = try XCTUnwrap(window.firstResponder as? FluentPipsPagerPipButton)
        XCTAssertEqual(focused.index, 1)
        XCTAssertTrue(focused.accessibilityPerformPress())
        XCTAssertEqual(state.wrappedValue, 1)
        window.orderOut(nil)
    }

    @MainActor
    func testBreadcrumbBarUsesWinUISuffixOverflowAndCurrentItemGeometry() throws {
        _ = NSApplication.shared
        let items = [
            FluentBreadcrumbBarItem("Root", id: 0),
            FluentBreadcrumbBarItem("Node A", id: 1),
            FluentBreadcrumbBarItem("Node A_2", id: 2),
            FluentBreadcrumbBarItem("Node A_2_3", id: 3),
            FluentBreadcrumbBarItem("Node A_2_3_1", id: 4)
        ]
        let bar = FluentBreadcrumbBar(items: items)
        XCTAssertEqual(bar.intrinsicContentSize.height, 26)
        XCTAssertEqual(
            bar.intrinsicContentSize.width,
            bar.itemControls.reduce(0) { $0 + $1.preferredWidth },
            accuracy: 0.001,
            "The ellipsis placeholder is excluded from BreadcrumbBar's desired width"
        )
        XCTAssertLessThan(
            try XCTUnwrap(bar.itemControls.last).preferredWidth,
            bar.itemControls[3].preferredWidth,
            "The current item has no trailing chevron"
        )

        let suffixWidth = bar.ellipsisControl.preferredWidth
            + bar.itemControls[3].preferredWidth
            + bar.itemControls[4].preferredWidth
        bar.frame = NSRect(x: 0, y: 0, width: suffixWidth + 0.5, height: 32)
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.firstVisibleItemIndex, 3)
        XCTAssertEqual(bar.hiddenItemIndices, [0, 1, 2])
        XCTAssertFalse(bar.ellipsisControl.isHidden)
        XCTAssertTrue(bar.itemControls[2].isHidden)
        XCTAssertFalse(bar.itemControls[3].isHidden)
        XCTAssertFalse(bar.itemControls[4].isHidden)
        XCTAssertEqual(bar.accessibilityChildren()?.count, 3)

        bar.frame.size.width = bar.intrinsicContentSize.width
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.ellipsisControl.isHidden)
        XCTAssertTrue(bar.hiddenItemIndices.isEmpty)
        XCTAssertEqual(bar.accessibilityChildren()?.count, 5)
    }

    @MainActor
    func testBreadcrumbBarInvocationKeyboardFocusAndRTLMapping() throws {
        _ = NSApplication.shared
        let items: [FluentBreadcrumbBarItem] = (0..<5).map { (index: Int) -> FluentBreadcrumbBarItem in
            FluentBreadcrumbBarItem("Level " + String(index), id: AnyHashable(index))
        }
        let bar = FluentBreadcrumbBar(items: items)
        var clicked: (Int, Int)?
        bar.onItemClicked = { item, index in clicked = (item.id as? Int ?? -1, index) }
        let width = bar.ellipsisControl.preferredWidth
            + bar.itemControls[3].preferredWidth
            + bar.itemControls[4].preferredWidth
        bar.frame = NSRect(x: 0, y: 0, width: width, height: 32)
        let window = NSWindow(
            contentRect: bar.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = bar
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.hiddenItemIndices, [0, 1, 2])
        bar.isEnabled = false
        XCTAssertFalse(bar.ellipsisControl.isEnabled)
        XCTAssertTrue(bar.itemControls.allSatisfy { !$0.isEnabled })
        bar.isEnabled = true
        XCTAssertTrue(bar.itemControls[3].accessibilityPerformPress())
        XCTAssertEqual(clicked?.0, 3)
        XCTAssertEqual(clicked?.1, 3)

        clicked = nil
        let current = bar.itemControls[4]
        let currentPoint = current.convert(NSPoint(x: current.bounds.midX, y: current.bounds.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: currentPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: currentPoint, modifierFlags: [], timestamp: 0.01,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0
        ))
        current.mouseDown(with: down)
        current.mouseUp(with: up)
        XCTAssertNil(clicked, "The source current presenter is not pointer-clickable")
        XCTAssertTrue(current.accessibilityPerformPress())
        XCTAssertEqual(clicked?.1, 4, "The current item remains invokable through keyboard and automation")

        _ = window.makeFirstResponder(bar.ellipsisControl)
        XCTAssertTrue(bar.moveFocus(from: bar.ellipsisControl, keyCode: 124))
        XCTAssertTrue(window.firstResponder === bar.itemControls[3])
        bar.fluentLayoutDirection = .rightToLeft
        bar.layoutSubtreeIfNeeded()
        _ = window.makeFirstResponder(bar.ellipsisControl)
        XCTAssertTrue(bar.moveFocus(from: bar.ellipsisControl, keyCode: 123))
        XCTAssertTrue(window.firstResponder === bar.itemControls[3])
        XCTAssertGreaterThan(bar.ellipsisControl.frame.minX, bar.itemControls[3].frame.minX)
        window.orderOut(nil)
    }

    @MainActor
    func testBreadcrumbBarDeclarativeUpdatePreservesNativeIdentity() throws {
        _ = NSApplication.shared
        let first = [
            FluentBreadcrumbBarItem("Root", id: "root"),
            FluentBreadcrumbBarItem("Folder", id: "folder")
        ]
        let host = FluentViewHost(FluentBreadcrumbBarView(items: first))
        let bar = try XCTUnwrap(host.subviews.first as? FluentBreadcrumbBar)
        host.update(FluentBreadcrumbBarView(items: first + [
            FluentBreadcrumbBarItem("File", id: "file")
        ]))
        XCTAssertTrue(host.subviews.first === bar)
        XCTAssertEqual(bar.items.map(\.title), ["Root", "Folder", "File"])
        XCTAssertTrue(try XCTUnwrap(bar.itemControls.last).isCurrent)
    }

    @MainActor
    func testHyperlinkButtonUsesWinUIStatePaletteAndReleaseActivation() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        var invocations = 0
        let button = FluentHyperlinkButton("Learn more") { invocations += 1 }
        button.theme = theme
        button.reduceMotion = true
        button.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
        let window = NSWindow(
            contentRect: button.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = button
        button.layoutSubtreeIfNeeded()

        func event(_ type: NSEvent.EventType, x: CGFloat, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: x, y: 16),
                modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
        func assertBackground(_ expected: NSColor, line: UInt = #line) throws {
            let actual = try XCTUnwrap(button.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)), line: line)
            let lhs = try XCTUnwrap(actual.usingColorSpace(.deviceRGB), line: line)
            let rhs = try XCTUnwrap(expected.usingColorSpace(.deviceRGB), line: line)
            XCTAssertEqual(lhs.redComponent, rhs.redComponent, accuracy: 0.001, line: line)
            XCTAssertEqual(lhs.alphaComponent, rhs.alphaComponent, accuracy: 0.001, line: line)
        }

        button.mouseEntered(with: try event(.mouseMoved, x: 20, number: 1))
        try assertBackground(theme.subtleFillSecondary)
        button.mouseDown(with: try event(.leftMouseDown, x: 20, number: 2))
        try assertBackground(theme.subtleFillTertiary)
        button.mouseDragged(with: try event(.leftMouseDragged, x: 160, number: 3))
        try assertBackground(.clear)
        button.mouseUp(with: try event(.leftMouseUp, x: 160, number: 4))
        XCTAssertEqual(invocations, 0)

        let keyDown = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        let keyUp = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0.1,
            windowNumber: window.windowNumber, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        button.keyDown(with: keyDown)
        XCTAssertEqual(invocations, 0, "WinUI invokes HyperlinkButton on key release")
        button.keyUp(with: keyUp)
        XCTAssertEqual(invocations, 1)
        XCTAssertEqual(button.accessibilityRole(), .link)
        window.orderOut(nil)
    }

    @MainActor
    func testSplitButtonSeparatesPrimaryAndFlyoutRegionsAndKeyboardTiming() throws {
        _ = NSApplication.shared
        var invocations = 0
        let button = FluentSplitButton("Save", items: [FluentMenuItem("Save as…") {}]) {
            invocations += 1
        }
        button.reduceMotion = true
        button.frame = NSRect(x: 0, y: 0, width: 140, height: 32)
        let window = NSWindow(
            contentRect: button.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = button
        button.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)

        XCTAssertEqual(FluentSplitButton.primaryMinimumWidth, 35)
        XCTAssertEqual(FluentSplitButton.secondaryWidth, 35)
        XCTAssertEqual(FluentSplitButton.separatorWidth, 1)

        func mouse(_ type: NSEvent.EventType, x: CGFloat, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: x, y: 16), modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: number, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }

        button.mouseDown(with: try mouse(.leftMouseDown, x: 30, number: 1))
        button.mouseUp(with: try mouse(.leftMouseUp, x: 30, number: 2))
        XCTAssertEqual(invocations, 1)
        XCTAssertFalse(button.isFlyoutPresented)

        button.mouseDown(with: try mouse(.leftMouseDown, x: 125, number: 3))
        button.mouseUp(with: try mouse(.leftMouseUp, x: 125, number: 4))
        XCTAssertEqual(invocations, 1, "secondary activation must not invoke the primary action")
        XCTAssertTrue(button.isFlyoutPresented)
        XCTAssertEqual(button.accessibilityValue() as? String, "Expanded")
        button.hideFlyout(animated: false)

        let down = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        let up = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0.1,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        button.keyDown(with: down)
        XCTAssertEqual(invocations, 1)
        button.keyUp(with: up)
        XCTAssertEqual(invocations, 2)

        button.userInterfaceLayoutDirection = .rightToLeft
        button.layoutSubtreeIfNeeded()
        button.mouseDown(with: try mouse(.leftMouseDown, x: 15, number: 5))
        button.mouseUp(with: try mouse(.leftMouseUp, x: 15, number: 6))
        XCTAssertTrue(button.isFlyoutPresented, "RTL mirrors the secondary region to the leading edge")
        button.hideFlyout(animated: false)
        window.orderOut(nil)
    }

    @MainActor
    func testToggleSplitButtonBindingAndDeclarativeIdentity() throws {
        _ = NSApplication.shared
        let state = FluentState<Bool>(wrappedValue: false)
        let makeView = {
            FluentToggleSplitButtonView("Favorite", isChecked: state.projectedValue) {
                FluentMenuItem("Manage favorites") {}
            }
        }
        let host = FluentViewHost(makeView(), context: FluentRenderContext(reduceMotion: true))

        func descendant<T>(_ type: T.Type, in root: NSView) -> T? {
            if let value = root as? T { return value }
            return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        let button = try XCTUnwrap(descendant(FluentToggleSplitButton.self, in: host))
        XCTAssertFalse(button.isChecked)
        button.invokePrimaryAction()
        XCTAssertTrue(button.isChecked)
        XCTAssertTrue(state.wrappedValue)
        XCTAssertEqual(button.accessibilityValue() as? String, "On, Collapsed")

        state.wrappedValue = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertFalse(button.isChecked)
        host.update(makeView())
        XCTAssertTrue(descendant(FluentToggleSplitButton.self, in: host) === button)
    }

    @MainActor
    func testSplitButtonFaceplateAndChevronMatchWinUIWithoutDoubleFill() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        let button = FluentSplitButton("Save", items: [FluentMenuItem("Save as…") {}]) {}
        button.theme = theme
        button.reduceMotion = true
        button.frame = NSRect(x: 0, y: 0, width: 140, height: 32)
        button.layoutSubtreeIfNeeded()

        let titleLabel = try XCTUnwrap(button.subviews.first {
            $0.identifier?.rawValue == "FluentKit.SplitButton.Title"
        } as? NSTextField)
        XCTAssertEqual(titleLabel.stringValue, "Save")
        XCTAssertTrue(titleLabel.textColor?.isEqual(theme.textPrimary) == true)
        XCTAssertEqual(titleLabel.frame.midY, button.bounds.midY, accuracy: 0.5)

        func sublayer(named name: String, in layer: CALayer) -> CALayer? {
            if layer.name == name { return layer }
            return layer.sublayers?.lazy.compactMap { sublayer(named: name, in: $0) }.first
        }

        let rootLayer = try XCTUnwrap(button.layer)
        let rootColor = rootLayer.backgroundColor.flatMap { NSColor(cgColor: $0) }
        XCTAssertEqual(rootColor?.alphaComponent ?? 0, 0, accuracy: 0.001)

        let primary = try XCTUnwrap(sublayer(named: "FluentKit.SplitButton.Primary", in: rootLayer))
        let primaryColor = try XCTUnwrap(primary.backgroundColor.flatMap { NSColor(cgColor: $0) })
        XCTAssertTrue(primaryColor.isEqual(theme.controlFill), "primary region owns the single faceplate fill")

        let elevation = try XCTUnwrap(
            sublayer(named: "FluentKit.SplitButton.ElevationBorder", in: rootLayer) as? CAGradientLayer
        )
        XCTAssertEqual(elevation.colors?.count, 2)
        let elevationColors = (elevation.colors ?? []).compactMap { NSColor(cgColor: $0 as! CGColor) }
        let expectedColors = theme.controlElevationBorderColors
        XCTAssertEqual(elevationColors.count, expectedColors.count)
        for (actual, expected) in zip(elevationColors, expectedColors) {
            XCTAssertTrue(actual.isEqual(expected))
        }

        let chevron = try XCTUnwrap(
            rootLayer.sublayers?.compactMap { $0 as? FluentChevronPrimitiveLayer }.first
        )
        let path = try XCTUnwrap(chevron.path)
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(element.pointee.points[0])
            default:
                break
            }
        }
        XCTAssertEqual(points.count, 3)
        XCTAssertGreaterThan(points[0].y, points[1].y, "down chevron starts above its point")
        XCTAssertGreaterThan(points[2].y, points[1].y, "down chevron ends above its point")
    }

    @MainActor
    func testNonSplitChevronsKeepTheSharedDownPath() throws {
        _ = NSApplication.shared
        let button = FluentDropDownButton(title: "Actions", items: [FluentMenuItem("Save as…") {}])
        button.reduceMotion = true
        button.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
        button.layoutSubtreeIfNeeded()
        let chevron = try XCTUnwrap(
            button.layer?.sublayers?.compactMap { $0 as? FluentChevronPrimitiveLayer }.first
        )
        let path = try XCTUnwrap(chevron.path)
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(element.pointee.points[0])
            default:
                break
            }
        }
        XCTAssertEqual(points.count, 3)
        XCTAssertLessThan(points[0].y, points[1].y, "non-split chevrons keep the shared down-facing path")
        XCTAssertLessThan(points[2].y, points[1].y)
    }

    @MainActor
    func testFlipViewButtonsKeyboardAndBindingNavigation() throws {
        _ = NSApplication.shared
        let selection = FluentState(wrappedValue: 0)
        let flip = FluentFlipView(["First", "Second", "Third"], selection: selection.projectedValue) { item in
            FluentText(item)
        }
        let host = FluentViewHost(flip, context: FluentRenderContext(reduceMotion: true))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        host.layoutSubtreeIfNeeded()
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let flipHost = try XCTUnwrap(descendant(identifier: "FluentKit.FlipView", in: host))
        let previous = try XCTUnwrap(
            descendant(identifier: "FluentKit.FlipView.Previous", in: host) as? NSButton
        )
        let next = try XCTUnwrap(
            descendant(identifier: "FluentKit.FlipView.Next", in: host) as? NSButton
        )
        XCTAssertEqual(flipHost.accessibilityValue() as? String, "1 of 3")
        XCTAssertFalse(previous.isEnabled)
        XCTAssertTrue(next.isEnabled)
        // FlipView_themeresources[_perf2026].xaml: 16x38 with a one-point outer margin.
        XCTAssertEqual(previous.frame.size, NSSize(width: 16, height: 38))
        XCTAssertEqual(next.frame.size, NSSize(width: 16, height: 38))

        next.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(selection.wrappedValue, 1)
        XCTAssertEqual(flipHost.accessibilityValue() as? String, "2 of 3")
        XCTAssertTrue(previous.isEnabled)

        selection.wrappedValue = 2
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(flipHost.accessibilityValue() as? String, "3 of 3")
        XCTAssertFalse(next.isEnabled)

        let left = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 123
        ))
        flipHost.keyDown(with: left)
        XCTAssertEqual(selection.wrappedValue, 1)
        XCTAssertEqual(flipHost.accessibilityValue() as? String, "2 of 3")

        window.orderOut(nil)
    }

    @MainActor
    func testListViewAndGridViewPublicWrappersPreserveLayoutAndSelection() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: nil)
        let list = FluentListView(
            ["Alpha", "Beta", "Gamma"],
            selectionID: selection.projectedValue,
            rowHeight: 42,
            spacing: 2
        ) { FluentText($0) }
        let listHost = FluentViewHost(list, context: FluentRenderContext(reduceMotion: true))
        listHost.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        listHost.layoutSubtreeIfNeeded()

        func descendant<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
            if let value = root as? T { return value }
            return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        func descendants(in root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap { descendants(in: $0) }
        }

        let listCollection = try XCTUnwrap(descendant(NSCollectionView.self, in: listHost))
        let listLayout = try XCTUnwrap(listCollection.collectionViewLayout as? NSCollectionViewFlowLayout)
        XCTAssertEqual(listLayout.itemSize.height, 42, accuracy: 0.001)
        XCTAssertEqual(listLayout.minimumInteritemSpacing, 2, accuracy: 0.001)

        selection.wrappedValue = "Beta"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        let listCells = descendants(in: listHost).filter { $0.accessibilityRole() == .row }
        XCTAssertEqual(listCells.count, 3)
        XCTAssertEqual(listCells.filter { $0.isAccessibilitySelected() }.count, 1)
        XCTAssertEqual(
            listCells.first { $0.isAccessibilitySelected() }?.accessibilityLabel(),
            "Item 2"
        )

        let originalCollection = listCollection
        let reordered = FluentListView(
            ["Beta", "Alpha", "Gamma"],
            selectionID: selection.projectedValue,
            rowHeight: 42,
            spacing: 2
        ) { FluentText($0) }
        listHost.update(reordered)
        XCTAssertTrue(descendant(NSCollectionView.self, in: listHost) === originalCollection)

        let multiSelection = FluentState<Set<Int>>(wrappedValue: [])
        let grid = FluentGridView(
            [1, 2, 3, 4],
            selectionIDs: multiSelection.projectedValue,
            minimumItemWidth: 96,
            itemHeight: 88,
            spacing: 10
        ) { FluentText("\($0)") }
        let gridHost = FluentViewHost(grid, context: FluentRenderContext(reduceMotion: true))
        gridHost.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        gridHost.layoutSubtreeIfNeeded()
        let gridCollection = try XCTUnwrap(descendant(NSCollectionView.self, in: gridHost))
        let gridLayout = try XCTUnwrap(gridCollection.collectionViewLayout as? NSCollectionViewFlowLayout)
        XCTAssertEqual(gridLayout.itemSize.height, 88, accuracy: 0.001)
        multiSelection.wrappedValue = [2, 4]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        let gridCells = descendants(in: gridHost).filter { $0.accessibilityRole() == .cell }
        XCTAssertEqual(gridCells.filter { $0.isAccessibilitySelected() }.count, 2)
    }

    @MainActor
    func testLoopingSelectorPublicKeyboardAndBoundarySemantics() throws {
        _ = NSApplication.shared
        let selection = FluentState<Int>(wrappedValue: 1)
        let host = FluentViewHost(
            FluentLoopingSelector(
                ["Zero", "One", "Two", "Three"],
                selection: selection.projectedValue,
                shouldLoop: false,
                visibleItemCount: 5,
                accessibilityLabel: "Number"
            ),
            context: FluentRenderContext(reduceMotion: true)
        )
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 200)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(host.subviews.first as? FluentLoopingSelectorControl)
        XCTAssertEqual(control.intrinsicContentSize, NSSize(width: 120, height: 200))
        XCTAssertEqual(control.accessibilityLabel(), "Number")
        XCTAssertEqual(control.accessibilityValue() as? String, "One")
        XCTAssertEqual(
            control.theme.loopingSelectorItemSelectedBackground.alphaComponent,
            control.theme.subtleFillSecondary.alphaComponent,
            accuracy: 0.0001,
            "the selected-row token must retain WinUI's translucent SubtleFill alpha"
        )

        func key(_ keyCode: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            ))
        }
        control.keyDown(with: try key(125))
        XCTAssertEqual(selection.wrappedValue, 2)
        control.keyDown(with: try key(119))
        XCTAssertEqual(selection.wrappedValue, 3)
        control.keyDown(with: try key(125))
        XCTAssertEqual(selection.wrappedValue, 3, "a non-looping selector stops at its last item")
        control.keyDown(with: try key(115))
        XCTAssertEqual(selection.wrappedValue, 0)
        XCTAssertFalse(control.accessibilityPerformDecrement())
    }

    @MainActor
    func testListViewSelectionModesAndItemInvocationAreExplicit() throws {
        _ = NSApplication.shared
        let selection = FluentState<String?>(wrappedValue: "Beta")
        var invoked: [String] = []
        let list = FluentListView(
            ["Alpha", "Beta", "Gamma"],
            selectionID: selection.projectedValue,
            selectionMode: .single,
            onItemInvoked: { invoked.append($0) }
        ) { FluentText($0) }
        let host = FluentViewHost(list, context: FluentRenderContext(reduceMotion: true))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 150)
        host.layoutSubtreeIfNeeded()

        func descendant<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
            if let value = root as? T { return value }
            return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: host))
        XCTAssertTrue(collection.isSelectable)
        XCTAssertFalse(collection.allowsMultipleSelection)
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        collection.keyDown(with: enter)
        XCTAssertEqual(invoked, ["Beta"])

        host.update(FluentListView(
            ["Alpha", "Beta", "Gamma"],
            selectionID: selection.projectedValue,
            selectionMode: .none
        ) { FluentText($0) })
        XCTAssertFalse(collection.isSelectable)
        XCTAssertNil(selection.wrappedValue)
    }

    func testCollectionSnapshotMovesStableItemGroupsAcrossInsertionOffsets() {
        var snapshot = FluentCollectionSnapshot(section: "main", items: ["A", "B", "C", "D", "E"])
        snapshot.moveItems(["B", "C"], toSection: "main", at: 5)
        XCTAssertEqual(snapshot.itemIdentifiers, ["A", "D", "E", "B", "C"])
        snapshot.moveItems(["E"], toSection: "main", at: 1)
        XCTAssertEqual(snapshot.itemIdentifiers, ["A", "E", "D", "B", "C"])
    }

    @MainActor
    func testListViewMultipleCheckmarksAndExtendedRangeSelection() throws {
        _ = NSApplication.shared
        let selected = FluentState<Set<Int>>(wrappedValue: [2])
        let host = FluentViewHost(
            FluentListView(
                [1, 2, 3, 4],
                selectionIDs: selected.projectedValue,
                selectionMode: .multiple
            ) { FluentText("Item \($0)") },
            context: FluentRenderContext(reduceMotion: true)
        )
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 180)
        host.layoutSubtreeIfNeeded()

        func descendant<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
            if let value = root as? T { return value }
            return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        func descendants(in root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap { descendants(in: $0) }
        }
        func layers(named name: String, in layer: CALayer?) -> [CALayer] {
            guard let layer else { return [] }
            return (layer.name == name ? [layer] : []) + (layer.sublayers ?? []).flatMap {
                layers(named: name, in: $0)
            }
        }
        func viewLayers(named name: String, in view: NSView) -> [CALayer] {
            layers(named: name, in: view.layer) + view.subviews.flatMap {
                viewLayers(named: name, in: $0)
            }
        }

        let collection = try XCTUnwrap(descendant(NSCollectionView.self, in: host))
        let markerLayers = viewLayers(named: "FluentKit.CollectionItem.MultiSelectSquare", in: host)
        XCTAssertEqual(markerLayers.count, 4)
        XCTAssertTrue(markerLayers.allSatisfy { $0.bounds.size == NSSize(width: 20, height: 20) })
        XCTAssertTrue(markerLayers.allSatisfy { $0.cornerRadius == 4 })
        XCTAssertTrue(markerLayers.allSatisfy {
            guard let superlayer = $0.superlayer else { return false }
            return abs($0.frame.maxY - (superlayer.bounds.maxY + 2)) < 0.001
                && abs($0.frame.maxX - (superlayer.bounds.maxX - 4)) < 0.001
        })
        XCTAssertEqual(
            viewLayers(named: "FluentKit.CollectionItem.MultiSelectCheck", in: host)
                .filter { $0.opacity > 0.5 }.count,
            1
        )
        let rows = descendants(in: host).filter { $0.accessibilityRole() == .row }
        XCTAssertEqual(rows.count, 4)
        let firstRow = try XCTUnwrap(rows.first { $0.accessibilityLabel() == "Item 1" })
        XCTAssertTrue(firstRow.accessibilityPerformPress())
        XCTAssertEqual(selected.wrappedValue, Set([1, 2]))

        let disabledHost = FluentViewHost(
            FluentListView(
                [1, 2],
                selectionIDs: FluentState<Set<Int>>(wrappedValue: []).projectedValue,
                selectionMode: .multiple,
                isEnabled: { $0 != 2 }
            ) { FluentText("Disabled item \($0)") },
            context: FluentRenderContext(reduceMotion: true)
        )
        disabledHost.frame = NSRect(x: 0, y: 0, width: 300, height: 90)
        disabledHost.layoutSubtreeIfNeeded()
        let disabledRows = descendants(in: disabledHost).filter { $0.accessibilityRole() == .row }
        XCTAssertEqual(disabledRows.count, 2)
        XCTAssertTrue(disabledRows.contains { abs($0.alphaValue - 1) < 0.001 })
        XCTAssertTrue(disabledRows.contains { abs($0.alphaValue - 0.3) < 0.001 })

        host.update(FluentListView(
            [1, 2, 3, 4],
            selectionIDs: selected.projectedValue,
            selectionMode: .extended
        ) { FluentText("Item \($0)") })
        host.layoutSubtreeIfNeeded()
        let paths = (0..<4).map { IndexPath(item: $0, section: 0) }
        let first = fluentCollectionSelectionAfterClick(
            current: [],
            clicked: paths[0],
            anchor: nil,
            previousFocus: nil,
            mode: .extended,
            modifiers: [],
            orderedEnabledItems: paths
        )
        let range = fluentCollectionSelectionAfterClick(
            current: first.selection,
            clicked: paths[3],
            anchor: first.anchor,
            previousFocus: paths[0],
            mode: .extended,
            modifiers: .shift,
            orderedEnabledItems: paths
        )
        XCTAssertEqual(range.selection, Set(paths))
        let preservedRange = fluentCollectionSelectionAfterClick(
            current: range.selection,
            clicked: paths[1],
            anchor: range.anchor,
            previousFocus: paths[3],
            mode: .extended,
            modifiers: [],
            orderedEnabledItems: paths
        )
        XCTAssertEqual(preservedRange.selection, Set(paths), "clicking inside an Extended range preserves it")
        let multipleRange = fluentCollectionSelectionAfterClick(
            current: [paths[0]],
            clicked: paths[3],
            anchor: paths[0],
            previousFocus: paths[0],
            mode: .multiple,
            modifiers: .shift,
            orderedEnabledItems: paths
        )
        XCTAssertEqual(multipleRange.selection, Set(paths))
        let keyboardUnion = fluentCollectionSelectionAfterKeyboardNavigation(
            current: [paths[0], paths[3]],
            target: paths[2],
            anchor: paths[0],
            mode: .extended,
            modifiers: [.shift, .command],
            orderedEnabledItems: paths
        )
        XCTAssertEqual(keyboardUnion.selection, Set(paths))
        XCTAssertTrue(
            viewLayers(named: "FluentKit.CollectionItem.MultiSelectSquare", in: host)
                .allSatisfy { $0.opacity == 0 },
            "automatic checkmarks stay specific to WinUI Multiple mode"
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        let selectAll = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        collection.keyDown(with: selectAll)
        XCTAssertEqual(selected.wrappedValue, Set([1, 2, 3, 4]))
        func click(_ index: Int, modifiers: NSEvent.ModifierFlags) throws {
            let attributes = try XCTUnwrap(collection.layoutAttributesForItem(at: paths[index]))
            let point = collection.convert(
                NSPoint(x: attributes.frame.midX, y: attributes.frame.midY),
                to: nil
            )
            collection.mouseDown(with: try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: point,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: index + 1,
                clickCount: 1,
                pressure: 1
            )))
        }
        selected.wrappedValue = []
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        try click(0, modifiers: [])
        try click(3, modifiers: .shift)
        XCTAssertEqual(selected.wrappedValue, Set([1, 2, 3, 4]))
        selected.wrappedValue = []
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        try click(0, modifiers: [])
        let shiftDown = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        ))
        collection.keyDown(with: shiftDown)
        XCTAssertEqual(selected.wrappedValue, Set([1, 2]))
        window.orderOut(nil)
    }

    @MainActor
    func testListViewIncrementalLoadingRequestsOncePerCompletedBatch() {
        _ = NSApplication.shared
        var requests = 0
        let configuration = FluentIncrementalLoadingConfiguration(threshold: 2) { requests += 1 }
        let host = FluentViewHost(
            FluentListView(
                [1, 2, 3],
                incrementalLoading: configuration
            ) { FluentText("Item \($0)") },
            context: FluentRenderContext(reduceMotion: true)
        )
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 180)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(requests, 1)

        host.update(FluentListView(
            [1, 2, 3],
            incrementalLoading: configuration
        ) { FluentText("Item \($0)") })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(requests, 1)

        host.update(FluentListView(
            [1, 2, 3],
            incrementalLoading: FluentIncrementalLoadingConfiguration(
                threshold: 2,
                isLoading: true,
                loadMore: { requests += 1 }
            )
        ) { FluentText("Item \($0)") })
        host.update(FluentListView(
            [1, 2, 3],
            incrementalLoading: configuration
        ) { FluentText("Item \($0)") })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(requests, 1, "a failed/empty batch does not enter an automatic retry loop")

        host.update(FluentListView(
            [1, 2, 3],
            incrementalLoading: FluentIncrementalLoadingConfiguration(
                threshold: 2,
                retryToken: 1,
                loadMore: { requests += 1 }
            )
        ) { FluentText("Item \($0)") })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(requests, 2, "changing retryToken explicitly retries the same batch")

        host.update(FluentListView(
            [1, 2, 3, 4],
            incrementalLoading: configuration
        ) { FluentText("Item \($0)") })
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(requests, 3)

        var initialRequests = 0
        let emptyHost = FluentViewHost(
            FluentListView(
                [Int](),
                incrementalLoading: FluentIncrementalLoadingConfiguration {
                    initialRequests += 1
                }
            ) { FluentText("Item \($0)") },
            context: FluentRenderContext(reduceMotion: true)
        )
        emptyHost.frame = NSRect(x: 0, y: 0, width: 300, height: 180)
        emptyHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(initialRequests, 1, "an empty incremental source requests its initial batch")
    }

    @MainActor
    func testRichTextBlockWrappingLinkActivationAndDeclarativeIdentity() throws {
        _ = NSApplication.shared
        let text = NSMutableAttributedString(
            string: "Bold lead and an Apple link.",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        text.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .bold), range: NSRange(location: 0, length: 9))
        text.addAttribute(
            .link,
            value: URL(string: "https://apple.com") as Any,
            range: (text.string as NSString).range(of: "Apple")
        )
        var activatedURLs: [URL] = []
        let block = FluentRichTextBlock(
            text,
            maximumLines: 2,
            isTextSelectionEnabled: true,
            onLinkActivated: { activatedURLs.append($0) }
        )
        let host = FluentViewHost(block, context: FluentRenderContext(reduceMotion: true))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        host.layoutSubtreeIfNeeded()

        func descendant<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
            if let value = root as? T { return value }
            return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }

        let richText = try XCTUnwrap(descendant(FluentRichTextBlockView.self, in: host))
        XCTAssertFalse(richText.isEditable)
        XCTAssertTrue(richText.isSelectable)
        XCTAssertEqual(richText.string, "Bold lead and an Apple link.")
        XCTAssertEqual(richText.textContainer?.maximumNumberOfLines, 2)
        XCTAssertEqual(richText.textContainer?.widthTracksTextView, true)
        XCTAssertEqual(richText.textContainer?.lineFragmentPadding ?? -1, 0, accuracy: 0.001)

        let delegate = try XCTUnwrap(richText.delegate)
        let url = try XCTUnwrap(URL(string: "https://apple.com"))
        let handled = delegate.textView?(richText, clickedOnLink: url, at: 24) ?? false
        XCTAssertTrue(handled)
        XCTAssertEqual(activatedURLs, [url])

        let original = richText
        let updatedText = NSMutableAttributedString(
            string: "Updated rich text.",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        host.update(FluentRichTextBlock(updatedText, maximumLines: 2))
        XCTAssertTrue(descendant(FluentRichTextBlockView.self, in: host) === original)
        XCTAssertEqual(original.string, "Updated rich text.")
    }

    @MainActor
    func testBorderAndImagePrimitivesPreserveGeometryAndDeclarativeIdentity() throws {
        _ = NSApplication.shared
        let border = FluentBorder(
            background: NSColor.systemBlue.withAlphaComponent(0.1),
            borderColor: NSColor.systemBlue,
            borderWidth: 2,
            cornerRadius: 8,
            padding: NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        ) {
            FluentText("Bordered content")
        }
        let borderHost = FluentViewHost(border, context: FluentRenderContext(reduceMotion: true))
        borderHost.frame = NSRect(x: 0, y: 0, width: 120, height: 48)
        borderHost.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        let nativeBorder = try XCTUnwrap(descendant(identifier: "FluentKit.Border", in: borderHost))
        XCTAssertEqual(nativeBorder.layer?.cornerRadius ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(nativeBorder.subviews.first?.frame.minX ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(nativeBorder.subviews.first?.frame.width ?? -1, 100, accuracy: 0.001)

        let originalBorder = nativeBorder
        borderHost.update(FluentBorder(cornerRadius: 4, padding: NSEdgeInsetsZero) {
            FluentText("Updated")
        })
        XCTAssertTrue(descendant(identifier: "FluentKit.Border", in: borderHost) === originalBorder)
        XCTAssertEqual(originalBorder.layer?.cornerRadius ?? -1, 4, accuracy: 0.001)

        let image = FluentImageView(systemImageName: "star.fill", scaling: .fill, accessibilityLabel: "Star")
        let imageHost = FluentViewHost(image, context: FluentRenderContext(reduceMotion: true))
        imageHost.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
        imageHost.layoutSubtreeIfNeeded()
        let nativeImage = try XCTUnwrap(
            descendant(identifier: "FluentKit.Image", in: imageHost) as? NSImageView
        )
        XCTAssertEqual(nativeImage.imageScaling, .scaleAxesIndependently)
        XCTAssertEqual(nativeImage.accessibilityLabel(), "Star")

        let originalImage = nativeImage
        imageHost.update(FluentImageView(systemImageName: "star", scaling: .aspectFit, accessibilityLabel: "Outline"))
        XCTAssertTrue(descendant(identifier: "FluentKit.Image", in: imageHost) === originalImage)
        XCTAssertEqual(originalImage.imageScaling, .scaleProportionallyUpOrDown)
        XCTAssertEqual(originalImage.accessibilityLabel(), "Outline")
    }

    @MainActor
    func testCanvasUsesWinUIAbsolutePositioningZeroDesiredAndNoClipping() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(
            theme: FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false),
            reduceMotion: true
        )
        let host = FluentViewHost(
            FluentCanvas {
                FluentText("Origin", size: 14).canvasPosition(x: 12, y: 24)
                FluentText("Overflow", size: 14).canvasPosition(x: 180, y: 8)
            },
            context: context
        )
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 80)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let canvas = try XCTUnwrap(descendant(identifier: "FluentKit.Canvas", in: host))
        XCTAssertTrue(canvas.isFlipped, "Canvas.Left/Top are measured from the visual top edge")
        XCTAssertEqual(canvas.intrinsicContentSize, .zero, "WinUI Canvas reports a zero desired size")
        XCTAssertEqual(canvas.subviews.count, 2)

        let first = try XCTUnwrap(canvas.subviews.first as? NSTextField)
        let second = try XCTUnwrap(canvas.subviews.last as? NSTextField)
        XCTAssertEqual(first.frame.origin, NSPoint(x: 12, y: 24))
        XCTAssertEqual(second.frame.origin, NSPoint(x: 180, y: 8))
        XCTAssertGreaterThan(second.frame.maxX, canvas.bounds.maxX)
        XCTAssertFalse(canvas.layer?.masksToBounds ?? false, "Canvas does not clip children to its bounds")

        let originalFirst = first
        host.update(FluentCanvas {
            FluentText("Moved", size: 14).canvasPosition(x: 40, y: 4)
            FluentText("Overflow", size: 14).canvasPosition(x: 180, y: 8)
        })
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(canvas.subviews.first === originalFirst, "updating Canvas.Left/Top preserves child identity")
        XCTAssertEqual(originalFirst.stringValue, "Moved")
        XCTAssertEqual(originalFirst.frame.origin, NSPoint(x: 40, y: 4))
    }

    @MainActor
    func testCanvasDefaultsUnpositionedChildToTopLeftAndRebuildsIncompatibleChild() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let host = FluentViewHost(
            FluentCanvas {
                FluentText("Default")
            },
            context: context
        )
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        host.layoutSubtreeIfNeeded()

        func canvasDescendant(in root: NSView) -> NSView? {
            if root.identifier?.rawValue == "FluentKit.Canvas" { return root }
            return root.subviews.lazy.compactMap(canvasDescendant).first
        }
        let canvas = try XCTUnwrap(canvasDescendant(in: host))
        let label = try XCTUnwrap(canvas.subviews.first as? NSTextField)
        XCTAssertEqual(label.frame.origin, NSPoint.zero)

        let originalCanvas = canvas
        host.update(FluentCanvas {
            FluentButtonView("Button").canvasPosition(x: 32, y: 16)
        })
        host.layoutSubtreeIfNeeded()
        let updatedCanvas = try XCTUnwrap(canvasDescendant(in: host))
        XCTAssertTrue(updatedCanvas === originalCanvas, "replacing one child keeps the Canvas host")
        let button = try XCTUnwrap(updatedCanvas.subviews.first as? FluentButton)
        XCTAssertEqual(button.frame.origin, NSPoint(x: 32, y: 16))
    }

    @MainActor
    func testViewboxMatchesWinUIStretchDirectionAndTopLeftScaleOrigin() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let host = FluentViewHost(
            FluentViewbox(stretch: .uniform, stretchDirection: .both) {
                FluentText("Content", size: 14).frame(width: 80, height: 40)
            },
            context: context
        )
        // WinUI's Viewbox scales to the layout slot assigned by its parent. Model that slot as
        // real Auto Layout constraints so the free-standing test host does not grow to the
        // child's natural size and hide the requested downscale.
        let widthConstraint = host.widthAnchor.constraint(equalToConstant: 40)
        let heightConstraint = host.heightAnchor.constraint(equalToConstant: 40)
        widthConstraint.isActive = true
        heightConstraint.isActive = true
        host.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        let box = try XCTUnwrap(descendant(identifier: "FluentKit.Viewbox", in: host))
        XCTAssertTrue(box.isFlipped)
        XCTAssertEqual(box.intrinsicContentSize, NSSize(width: 80, height: 40))

        let child = try XCTUnwrap(box.subviews.first)
        XCTAssertEqual(child.frame.origin, NSPoint.zero)
        XCTAssertEqual(child.frame.size, NSSize(width: 80, height: 40))
        let uniform = try XCTUnwrap(child.layer?.affineTransform())
        XCTAssertEqual(uniform.a, 0.5, accuracy: 0.001)
        XCTAssertEqual(uniform.d, 0.5, accuracy: 0.001)

        let originalChild = child
        host.update(FluentViewbox(stretch: .uniformToFill, stretchDirection: .both) {
            FluentText("Content", size: 14).frame(width: 80, height: 40)
        })
        widthConstraint.constant = 160
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(box.subviews.first === originalChild, "stretch changes preserve child identity")
        let uniformToFill = try XCTUnwrap(originalChild.layer?.affineTransform())
        XCTAssertEqual(uniformToFill.a, 2, accuracy: 0.001)
        XCTAssertEqual(uniformToFill.d, 2, accuracy: 0.001)

        host.update(FluentViewbox(stretch: .fill, stretchDirection: .downOnly) {
            FluentText("Content", size: 14).frame(width: 80, height: 40)
        })
        host.frame = NSRect(x: 0, y: 0, width: 160, height: 40)
        host.layoutSubtreeIfNeeded()
        let downOnly = try XCTUnwrap(originalChild.layer?.affineTransform())
        XCTAssertEqual(downOnly.a, 1, accuracy: 0.001)
        XCTAssertEqual(downOnly.d, 1, accuracy: 0.001)

        host.update(FluentViewbox(stretch: .none, stretchDirection: .both) {
            FluentText("Content", size: 14).frame(width: 80, height: 40)
        })
        widthConstraint.constant = 20
        heightConstraint.constant = 10
        host.frame = NSRect(x: 0, y: 0, width: 20, height: 10)
        host.layoutSubtreeIfNeeded()
        let none = try XCTUnwrap(originalChild.layer?.affineTransform())
        XCTAssertEqual(none.a, 1, accuracy: 0.001)
        XCTAssertEqual(none.d, 1, accuracy: 0.001)
    }

    @MainActor
    func testVariableSizedWrapGridPacksSpansAndTruncatesAtMaximumRowsOrColumns() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)

        let packed = FluentVariableSizedWrapGrid(
            itemWidth: 40,
            itemHeight: 30,
            orientation: .vertical
        ) {
            FluentText("A", size: 14)
            FluentText("B", size: 14).variableSizedWrapGridPosition(rowSpan: 2, columnSpan: 1)
            FluentText("C", size: 14)
            FluentText("D", size: 14).variableSizedWrapGridPosition(rowSpan: 1, columnSpan: 2)
            FluentText("E", size: 14)
        }._mount(in: context)
        packed.frame = NSRect(x: 0, y: 0, width: 180, height: 140)
        packed.layoutSubtreeIfNeeded()

        XCTAssertTrue(packed.isFlipped)
        XCTAssertEqual(packed.subviews.count, 5)
        let packedFrames = packed.subviews.map(\.frame)
        XCTAssertEqual(packedFrames[0], NSRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(packedFrames[1], NSRect(x: 0, y: 30, width: 40, height: 60))
        XCTAssertEqual(packedFrames[2], NSRect(x: 0, y: 90, width: 40, height: 30))
        XCTAssertEqual(packedFrames[3], NSRect(x: 40, y: 0, width: 80, height: 30))
        XCTAssertEqual(packedFrames[4], NSRect(x: 40, y: 30, width: 40, height: 30))

        let truncated = FluentVariableSizedWrapGrid(
            itemWidth: 40,
            itemHeight: 30,
            orientation: .vertical,
            maximumRowsOrColumns: 1
        ) {
            FluentText("A", size: 14)
            FluentText("B", size: 14)
            FluentText("C", size: 14)
            FluentText("D", size: 14)
            FluentText("E", size: 14)
        }._mount(in: context)
        truncated.frame = NSRect(x: 0, y: 0, width: 130, height: 60)
        truncated.layoutSubtreeIfNeeded()

        let truncatedFrames = truncated.subviews.map(\.frame)
        XCTAssertEqual(truncatedFrames[0], NSRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(truncatedFrames[1], NSRect(x: 40, y: 0, width: 40, height: 30))
        XCTAssertEqual(truncatedFrames[2], NSRect(x: 80, y: 0, width: 40, height: 30))
        XCTAssertEqual(truncatedFrames[3], .zero, "elements that cannot fit are not arranged")
        XCTAssertEqual(truncatedFrames[4], .zero)
        XCTAssertEqual(
            truncated.intrinsicContentSize,
            NSSize(width: 200, height: 30),
            "an unconstrained slot lays all five items along one row"
        )
    }

    @MainActor
    func testVariableSizedWrapGridHorizontalOrientationAndAlignmentOffsets() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)

        let horizontal = FluentVariableSizedWrapGrid(
            itemWidth: 40,
            itemHeight: 30,
            orientation: .horizontal
        ) {
            FluentText("A", size: 14)
            FluentText("B", size: 14).variableSizedWrapGridPosition(rowSpan: 1, columnSpan: 2)
            FluentText("C", size: 14)
            FluentText("D", size: 14).variableSizedWrapGridPosition(rowSpan: 2, columnSpan: 1)
            FluentText("E", size: 14)
        }._mount(in: context)
        horizontal.frame = NSRect(x: 0, y: 0, width: 130, height: 100)
        horizontal.layoutSubtreeIfNeeded()

        let frames = horizontal.subviews.map(\.frame)
        XCTAssertEqual(frames[0], NSRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(frames[1], NSRect(x: 40, y: 0, width: 80, height: 30))
        XCTAssertEqual(frames[2], NSRect(x: 0, y: 30, width: 40, height: 30))
        XCTAssertEqual(frames[3], NSRect(x: 40, y: 30, width: 40, height: 60))
        XCTAssertEqual(frames[4], NSRect(x: 80, y: 30, width: 40, height: 30))

        let centered = FluentVariableSizedWrapGrid(
            itemWidth: 40,
            itemHeight: 30,
            horizontalChildrenAlignment: .center,
            verticalChildrenAlignment: .center
        ) {
            FluentText("Center", size: 14)
        }._mount(in: context)
        centered.frame = NSRect(x: 0, y: 0, width: 120, height: 90)
        centered.layoutSubtreeIfNeeded()
        XCTAssertEqual(centered.subviews.first?.frame, NSRect(x: 40, y: 30, width: 40, height: 30))

        let stretched = FluentVariableSizedWrapGrid(
            itemWidth: 40,
            itemHeight: 30,
            horizontalChildrenAlignment: .stretch,
            verticalChildrenAlignment: .stretch
        ) {
            FluentText("Stretch", size: 14)
        }._mount(in: context)
        stretched.frame = NSRect(x: 0, y: 0, width: 140, height: 100)
        stretched.layoutSubtreeIfNeeded()
        XCTAssertEqual(stretched.subviews.first?.frame, NSRect(x: 50, y: 35, width: 40, height: 30))
    }

    @MainActor
    func testVariableSizedWrapGridInfersItemSizeAndPreservesHostIdentity() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let host = FluentViewHost(
            FluentVariableSizedWrapGrid {
                FluentText("First tile", size: 14)
                FluentText("Second tile", size: 14)
            },
            context: context
        )
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
        host.layoutSubtreeIfNeeded()

        func gridDescendant(in root: NSView) -> NSView? {
            if root.identifier?.rawValue == "FluentKit.VariableSizedWrapGrid" { return root }
            return root.subviews.lazy.compactMap(gridDescendant).first
        }

        let grid = try XCTUnwrap(gridDescendant(in: host))
        let firstChild = try XCTUnwrap(grid.subviews.first)
        let inferred = fluentNaturalSize(of: firstChild, forceLayout: false)
        XCTAssertGreaterThan(inferred.width, 0)
        XCTAssertGreaterThan(inferred.height, 0)
        XCTAssertEqual(firstChild.frame.size, inferred)

        let originalGrid = grid
        let originalFirstChild = firstChild
        host.update(
            FluentVariableSizedWrapGrid {
                FluentText("Renamed tile", size: 14)
                FluentText("Second tile", size: 14)
            }
        )
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(gridDescendant(in: host) === originalGrid)
        XCTAssertTrue(originalGrid.subviews.first === originalFirstChild)
        XCTAssertEqual((originalFirstChild as? NSTextField)?.stringValue, "Renamed tile")

        host.update(
            FluentVariableSizedWrapGrid(orientation: .horizontal) {
                FluentText("Renamed tile", size: 14).variableSizedWrapGridPosition(rowSpan: 1, columnSpan: 2)
                FluentText("Second tile", size: 14)
            }
        )
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(gridDescendant(in: host) === originalGrid)
        XCTAssertTrue(originalGrid.subviews.first === originalFirstChild)
    }

    @MainActor
    func testRelativePanelPositionsChildrenRelativeToSiblingsAndPanelEdges() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)

        let host = FluentViewHost(
            FluentRelativePanel {
                FluentText("Anchor", size: 14)
                    .frame(width: 60, height: 40)
                    .relativePanelName("anchor")
                    .relativePanelPosition(alignLeftWithPanel: true, alignTopWithPanel: true)
                FluentText("Right", size: 14)
                    .frame(width: 80, height: 50)
                    .relativePanelPosition(rightOf: "anchor", alignTopWith: "anchor")
                FluentText("Below", size: 14)
                    .frame(width: 70, height: 30)
                    .relativePanelPosition(below: "anchor", alignLeftWith: "anchor")
            },
            context: context
        )
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        let panel = try XCTUnwrap(descendant(identifier: "FluentKit.RelativePanel", in: host))
        XCTAssertTrue(panel.isFlipped, "RelativePanel Top/Left measure from the visual top edge")
        XCTAssertEqual(panel.subviews.count, 3)
        XCTAssertEqual(panel.subviews[0].frame, NSRect(x: 0, y: 0, width: 60, height: 40))
        XCTAssertEqual(panel.subviews[1].frame, NSRect(x: 60, y: 0, width: 80, height: 50))
        XCTAssertEqual(panel.subviews[2].frame, NSRect(x: 0, y: 40, width: 70, height: 30))

        let oppositeHost = FluentViewHost(
            FluentRelativePanel {
                FluentText("Anchor", size: 14)
                    .frame(width: 60, height: 40)
                    .relativePanelName("anchor")
                    .relativePanelPosition(alignRightWithPanel: true, alignBottomWithPanel: true)
                FluentText("Left", size: 14)
                    .frame(width: 80, height: 50)
                    .relativePanelPosition(leftOf: "anchor", alignBottomWith: "anchor")
                FluentText("Above", size: 14)
                    .frame(width: 70, height: 30)
                    .relativePanelPosition(above: "anchor", alignRightWith: "anchor")
            },
            context: context
        )
        oppositeHost.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        oppositeHost.layoutSubtreeIfNeeded()

        let oppositePanel = try XCTUnwrap(
            descendant(identifier: "FluentKit.RelativePanel", in: oppositeHost)
        )
        XCTAssertEqual(
            oppositePanel.subviews[0].frame,
            NSRect(x: 240, y: 160, width: 60, height: 40)
        )
        XCTAssertEqual(
            oppositePanel.subviews[1].frame,
            NSRect(x: 160, y: 150, width: 80, height: 50),
            "LeftOf keeps the child right edge flush with the sibling's left edge"
        )
        XCTAssertEqual(
            oppositePanel.subviews[2].frame,
            NSRect(x: 230, y: 130, width: 70, height: 30),
            "Above keeps the child bottom edge flush with the sibling's top edge"
        )
    }

    @MainActor
    func testRelativePanelCentersAndDesiredSizeChains() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)

        let host = FluentViewHost(
            FluentRelativePanel {
                FluentText("A", size: 14)
                    .frame(width: 80, height: 50)
                    .relativePanelName("a")
                    .relativePanelPosition(alignLeftWithPanel: true, alignTopWithPanel: true)
                FluentText("B", size: 14)
                    .frame(width: 90, height: 40)
                    .relativePanelPosition(alignRightWithPanel: true, alignBottomWithPanel: true)
                FluentText("C", size: 14)
                    .frame(width: 40, height: 20)
                    .relativePanelPosition(
                        alignHorizontalCenterWithPanel: true,
                        alignVerticalCenterWithPanel: true
                    )
                FluentText("D", size: 14)
                    .frame(width: 40, height: 20)
                    .relativePanelPosition(
                        alignHorizontalCenterWith: "a",
                        alignVerticalCenterWith: "a"
                    )
            },
            context: context
        )
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        host.layoutSubtreeIfNeeded()

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        let panel = try XCTUnwrap(descendant(identifier: "FluentKit.RelativePanel", in: host))
        XCTAssertEqual(panel.subviews[0].frame, NSRect(x: 0, y: 0, width: 80, height: 50))
        XCTAssertEqual(panel.subviews[1].frame, NSRect(x: 210, y: 160, width: 90, height: 40))
        XCTAssertEqual(panel.subviews[2].frame, NSRect(x: 130, y: 90, width: 40, height: 20))
        XCTAssertEqual(
            panel.subviews[3].frame,
            NSRect(x: 20, y: 15, width: 40, height: 20),
            "align horizontal/vertical center with a sibling tracks that sibling's midpoints"
        )

        let chainHost = FluentViewHost(
            FluentRelativePanel {
                FluentText("Anchor", size: 14)
                    .frame(width: 60, height: 40)
                    .relativePanelName("anchor")
                    .relativePanelPosition(alignLeftWithPanel: true, alignTopWithPanel: true)
                FluentText("First", size: 14)
                    .frame(width: 80, height: 50)
                    .relativePanelName("first")
                    .relativePanelPosition(rightOf: "anchor", below: "anchor")
                FluentText("Second", size: 14)
                    .frame(width: 40, height: 20)
                    .relativePanelPosition(rightOf: "first", below: "first")
            },
            context: context
        )
        chainHost.layoutSubtreeIfNeeded()
        let chainPanel = try XCTUnwrap(
            descendant(identifier: "FluentKit.RelativePanel", in: chainHost)
        )
        XCTAssertEqual(
            chainPanel.intrinsicContentSize,
            NSSize(width: 180, height: 110),
            "desired size accumulates each horizontal and vertical dependency chain"
        )
    }

    @MainActor
    func testRelativePanelUpdatesPreserveHostAndChildIdentity() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let host = FluentViewHost(
            FluentRelativePanel {
                FluentText("A", size: 14)
                    .frame(width: 60, height: 40)
                    .relativePanelName("a")
                    .relativePanelPosition(alignLeftWithPanel: true, alignTopWithPanel: true)
                FluentText("B", size: 14)
                    .frame(width: 80, height: 50)
                    .relativePanelPosition(rightOf: "a", alignTopWith: "a")
            },
            context: context
        )
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        host.layoutSubtreeIfNeeded()

        func panelDescendant(in root: NSView) -> NSView? {
            if root.identifier?.rawValue == "FluentKit.RelativePanel" { return root }
            return root.subviews.lazy.compactMap(panelDescendant).first
        }
        let panel = try XCTUnwrap(panelDescendant(in: host))
        let originalFirst = try XCTUnwrap(panel.subviews.first)
        let originalSecond = try XCTUnwrap(panel.subviews.last)

        host.update(
            FluentRelativePanel {
                FluentText("Updated A", size: 14)
                    .frame(width: 70, height: 30)
                    .relativePanelName("a")
                    .relativePanelPosition(alignLeftWithPanel: true, alignTopWithPanel: true)
                FluentText("Updated B", size: 14)
                    .frame(width: 60, height: 40)
                    .relativePanelPosition(rightOf: "a", alignTopWith: "a")
            }
        )
        host.layoutSubtreeIfNeeded()

        XCTAssertTrue(panelDescendant(in: host) === panel, "stable children keep the RelativePanel host")
        XCTAssertTrue(panel.subviews.first === originalFirst, "updating attached properties preserves child identity")
        XCTAssertTrue(panel.subviews.last === originalSecond, "updating sibling references preserves child identity")
        XCTAssertEqual((originalFirst.subviews.first as? NSTextField)?.stringValue, "Updated A")
        XCTAssertEqual(originalFirst.frame, NSRect(x: 0, y: 0, width: 70, height: 30))
        XCTAssertEqual(originalSecond.frame, NSRect(x: 70, y: 0, width: 60, height: 40))
    }

    @MainActor
    func testDatePickerFlyoutEditorUsesFluentMonthWithoutSystemDatePicker() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        var selectedDates: [Date] = []
        let selectedDate = DateComponents(calendar: .current, year: 2026, month: 8, day: 13).date!
        let editor = FluentCalendarPickerEditorView(
            selectedDate: selectedDate,
            calendar: .current,
            locale: .current,
            timeZone: .current,
            theme: theme,
            onSelect: { selectedDates.append($0) }
        )
        editor.frame = NSRect(origin: .zero, size: editor.intrinsicContentSize)
        editor.layoutSubtreeIfNeeded()

        func descendants(in root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap { descendants(in: $0) }
        }
        XCTAssertTrue(descendants(in: editor).filter { $0 is NSDatePicker }.isEmpty)
        let dayButtons = descendants(in: editor).compactMap { $0 as? NSButton }
        let grid = try XCTUnwrap(descendants(in: editor).first { $0 is FluentCalendarGridView } as? FluentCalendarGridView)
        let calendarCells = grid.visibleCells
        XCTAssertEqual(calendarCells.count, 42)
        XCTAssertLessThanOrEqual(dayButtons.count, 73, "Only the viewport and a bounded cache should exist")
        let firstCalendarRow = Array(calendarCells.prefix(7))
        let secondCalendarRow = Array(calendarCells.dropFirst(7).prefix(7))
        XCTAssertGreaterThan(
            firstCalendarRow.map { $0.convert($0.bounds, to: editor).minY }.min() ?? 0,
            secondCalendarRow.map { $0.convert($0.bounds, to: editor).minY }.max() ?? 0,
            "Calendar rows must read top-to-bottom after converting the flipped document coordinates"
        )
        XCTAssertFalse(calendarCells.contains { $0.title == "..." })
        let day = try XCTUnwrap(grid.cell(for: DateComponents(calendar: .current, year: 2026, month: 8, day: 5).date!))
        day.performClick(nil)
        XCTAssertEqual(selectedDates.count, 1)
        let selectedComponents = Calendar.current.dateComponents([.year, .month], from: selectedDates[0])
        XCTAssertEqual(selectedComponents.year, 2026)
        XCTAssertEqual(selectedComponents.month, 8)

        let header = try XCTUnwrap(
            dayButtons.first { $0.identifier?.rawValue == "FluentKit.CalendarDatePicker.Header" }
        )
        let originalHeader = header.title
        let initialOffset = grid.contentView.bounds.minY
        grid.contentView.scroll(to: NSPoint(x: 0, y: initialOffset + 11))
        grid.reflectScrolledClipView(grid.contentView)
        XCTAssertEqual(header.title, originalHeader, "A partial row scroll must not jump to an adjacent month")
        grid.scroll(to: DateComponents(calendar: .current, year: 2026, month: 9, day: 1).date!, leading: true)
        XCTAssertNotEqual(header.title, originalHeader, "The header follows the visible month")

        header.performClick(nil)
        editor.layoutSubtreeIfNeeded()
        let visibleMonthCells = grid.visibleCells
        XCTAssertEqual(visibleMonthCells.count, 16)
        XCTAssertEqual(Set(visibleMonthCells.map(\.frame.minX)).count, 4)
        XCTAssertEqual(Set(visibleMonthCells.map(\.frame.minY)).count, 4)
        XCTAssertFalse(visibleMonthCells.contains { $0.title == "..." })
    }

    @MainActor
    func testTimeAndColorPickerEditorsUseFluentComponentsInsteadOfSystemControls() throws {
        _ = NSApplication.shared
        let theme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        var times: [FluentTime] = []
        let timeEditor = FluentTimePickerEditorView(
            time: FluentTime(hour: 9, minute: 30),
            minuteIncrement: 5,
            clockIdentifier: .twentyFourHour,
            locale: .current,
            theme: theme,
            onChange: { times.append($0) }
        )
        timeEditor.frame = NSRect(origin: .zero, size: timeEditor.intrinsicContentSize)
        timeEditor.layoutSubtreeIfNeeded()

        func descendants(in root: NSView) -> [NSView] {
            [root] + root.subviews.flatMap { descendants(in: $0) }
        }
        XCTAssertTrue(descendants(in: timeEditor).filter { $0 is NSDatePicker }.isEmpty)
        XCTAssertEqual(descendants(in: timeEditor).filter { $0 is NSScrollView }.count, 0)
        let timeSelectors = descendants(in: timeEditor).compactMap { $0 as? FluentWinUILoopingSelector }
        let visibleTimeSelectors = timeSelectors.filter { !$0.isHidden }
        XCTAssertEqual(timeSelectors.count, 3)
        XCTAssertEqual(visibleTimeSelectors.count, 2)
        XCTAssertEqual(timeEditor.intrinsicContentSize.height, 357, accuracy: 0.001)
        XCTAssertTrue(visibleTimeSelectors.allSatisfy { $0.frame.height == 357 })
        XCTAssertLessThanOrEqual(visibleTimeSelectors[0].frame.maxX, visibleTimeSelectors[1].frame.minX)

        let twelveHourEditor = FluentTimePickerEditorView(
            time: FluentTime(hour: 9, minute: 30),
            minuteIncrement: 5,
            clockIdentifier: .twelveHour,
            locale: Locale(identifier: "en_US"),
            theme: theme,
            onChange: { _ in }
        )
        twelveHourEditor.frame = NSRect(origin: .zero, size: twelveHourEditor.intrinsicContentSize)
        twelveHourEditor.layoutSubtreeIfNeeded()
        let twelveHourSelectors = descendants(in: twelveHourEditor)
            .compactMap { $0 as? FluentWinUILoopingSelector }
            .filter { !$0.isHidden }
        XCTAssertEqual(twelveHourSelectors.count, 3)
        XCTAssertTrue(twelveHourSelectors.allSatisfy { $0.frame.height == 357 })
        XCTAssertLessThanOrEqual(twelveHourSelectors[0].frame.maxX, twelveHourSelectors[1].frame.minX)
        XCTAssertLessThanOrEqual(twelveHourSelectors[1].frame.maxX, twelveHourSelectors[2].frame.minX)
        XCTAssertFalse(twelveHourSelectors[2].shouldLoop, "AM/PM is a bounded two-item selector")

        var colors: [NSColor] = []
        let colorEditor = FluentWinUIColorPickerEditorView(
            color: .systemBlue,
            theme: theme,
            onChange: { colors.append($0) }
        )
        colorEditor.frame = NSRect(origin: .zero, size: colorEditor.intrinsicContentSize)
        colorEditor.layoutSubtreeIfNeeded()
        let colorSliders = descendants(in: colorEditor).compactMap { $0 as? FluentSlider }
        let colorSpectrum = try XCTUnwrap(
            descendants(in: colorEditor).first { $0 is FluentColorSpectrumView }
        )
        let colorPreview = try XCTUnwrap(
            descendants(in: colorEditor).first {
                $0.identifier?.rawValue == "FluentKit.ColorPicker.Preview"
            }
        )
        XCTAssertEqual(colorSliders.count, 3)
        XCTAssertEqual(
            descendants(in: colorEditor).filter { $0 is FluentColorSpectrumView }.count,
            1
        )
        XCTAssertGreaterThanOrEqual(
            colorSpectrum.frame.minY,
            colorSliders.map(\.frame.maxY).max()! + 11
        )
        XCTAssertGreaterThanOrEqual(colorPreview.frame.minY, colorSpectrum.frame.maxY + 9)
        colorSliders[2].value = 50
        XCTAssertEqual(colors.count, 1)
        XCTAssertEqual(colorSliders[2].value, 50, accuracy: 0.001)
        let emittedColorCount = colors.count
        colorEditor.updateColor(.systemRed)
        XCTAssertEqual(
            colors.count,
            emittedColorCount,
            "Synchronizing an external color must not feed back through the three slider callbacks"
        )

        let colorState = FluentState(wrappedValue: NSColor.systemBlue)
        let mountedColorPicker = FluentColorPicker(
            selection: colorState.projectedValue,
            label: "Accent color"
        )._mount(in: FluentRenderContext(theme: theme))
        let mountedEditor = try XCTUnwrap(mountedColorPicker as? FluentWinUIColorPickerEditorView)
        mountedEditor.frame = NSRect(origin: .zero, size: mountedEditor.intrinsicContentSize)
        mountedEditor.layoutSubtreeIfNeeded()
        XCTAssertEqual(mountedEditor.intrinsicContentSize, NSSize(width: 320, height: 350))
        XCTAssertEqual(descendants(in: mountedEditor).filter { $0 is FluentColorSpectrumView }.count, 1)
        XCTAssertEqual(descendants(in: mountedEditor).filter { $0 is FluentSlider }.count, 3)
        XCTAssertTrue(descendants(in: mountedEditor).filter { $0 is NSColorWell }.isEmpty)

        let flyoutPicker = FluentColorPicker(
            selection: colorState.projectedValue,
            label: "Accent color",
            presentation: .flyout
        )._mount(in: FluentRenderContext(theme: theme))
        XCTAssertEqual(
            flyoutPicker.identifier?.rawValue,
            "FluentKit.ColorPicker.FlyoutButton"
        )
        XCTAssertEqual(flyoutPicker.intrinsicContentSize, NSSize(width: 180, height: 32))

        let dateFlyout = FluentWinUIDatePickerFlyout(
            date: DateComponents(calendar: .current, year: 2026, month: 8, day: 13).date!,
            minYear: nil,
            maxYear: nil,
            dayFormat: nil,
            monthFormat: nil,
            yearFormat: nil,
            calendarIdentifier: nil,
            yearVisible: true,
            theme: theme,
            reduceMotion: true
        )
        dateFlyout.frame = NSRect(origin: .zero, size: dateFlyout.intrinsicContentSize)
        dateFlyout.layoutSubtreeIfNeeded()
        let dateSelectors = descendants(in: dateFlyout)
            .compactMap { $0 as? FluentWinUILoopingSelector }
            .filter { !$0.isHidden }
            .sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(dateFlyout.intrinsicContentSize, NSSize(width: 296, height: 398))
        XCTAssertEqual(dateSelectors.count, 3)
        XCTAssertTrue(dateSelectors.allSatisfy { $0.frame.height == 357 })
        XCTAssertLessThanOrEqual(dateSelectors[0].frame.maxX, dateSelectors[1].frame.minX)
        XCTAssertLessThanOrEqual(dateSelectors[1].frame.maxX, dateSelectors[2].frame.minX)

        let flyoutButtons = descendants(in: dateFlyout)
            .compactMap { $0 as? FluentWinUIDatePickerFlyoutButton }
            .sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(flyoutButtons.count, 2)
        XCTAssertEqual(flyoutButtons[0].frame, NSRect(x: 0, y: 0, width: 148, height: 41))
        XCTAssertEqual(flyoutButtons[1].frame, NSRect(x: 148, y: 0, width: 148, height: 41))
        XCTAssertTrue(flyoutButtons.allSatisfy { $0.layer?.borderWidth == 0 })

        let scrollingSelector = FluentWinUILoopingSelector()
        scrollingSelector.values = ["0", "1", "2", "3"]
        scrollingSelector.selectedIndex = 1
        func preciseScrollEvent(deltaY: Int32) throws -> NSEvent {
            let event = try XCTUnwrap(CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: deltaY,
                wheel2: 0,
                wheel3: 0
            ))
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            return try XCTUnwrap(NSEvent(cgEvent: event))
        }
        scrollingSelector.scrollWheel(with: try preciseScrollEvent(deltaY: -11))
        XCTAssertEqual(scrollingSelector.selectedIndex, 1, "a partial trackpad delta remains as scroll residual")
        scrollingSelector.scrollWheel(with: try preciseScrollEvent(deltaY: -11))
        XCTAssertEqual(scrollingSelector.selectedIndex, 2, "successive trackpad deltas accumulate to the next snap point")
    }

    @MainActor
    func testTimePickerMatchesWinUINullClockAndMinuteIncrementSemantics() throws {
        _ = NSApplication.shared
        XCTAssertEqual(FluentTime(hour: 23, minute: 58).adjusted(toMinuteIncrement: 15), FluentTime(hour: 23, minute: 45))
        XCTAssertEqual(FluentTime(hour: 9, minute: 58).adjusted(toMinuteIncrement: 0), FluentTime(hour: 9, minute: 0))

        let picker = FluentTimePicker(
            selectedTime: nil,
            minuteIncrement: 15,
            clockIdentifier: .twelveHour,
            header: "Departure time"
        )
        picker.reduceMotion = true
        picker.frame = NSRect(origin: .zero, size: picker.intrinsicContentSize)
        picker.layoutSubtreeIfNeeded()
        XCTAssertEqual(picker.intrinsicContentSize.width, 242, accuracy: 0.001)
        XCTAssertEqual(picker.intrinsicContentSize.height, 52, accuracy: 1,
                       "a header adds its source four-point gap above the 32-point picker")
        XCTAssertEqual(picker.accessibilityValue() as? String, "No time selected")
        let lightTheme = FluentTheme.custom(colorScheme: .light, materialEffectsEnabled: false)
        picker.theme = lightTheme
        XCTAssertEqual(
            try XCTUnwrap(picker.displayForegroundColor.usingColorSpace(.deviceRGB)).alphaComponent,
            try XCTUnwrap(lightTheme.textSecondary.usingColorSpace(.deviceRGB)).alphaComponent,
            accuracy: 0.001
        )

        let firstDivider = try XCTUnwrap(picker.layer?.sublayers?.first { $0.name == "FluentKit.TimePicker.FirstDivider" })
        let secondDivider = try XCTUnwrap(picker.layer?.sublayers?.first { $0.name == "FluentKit.TimePicker.SecondDivider" })
        XCTAssertFalse(firstDivider.isHidden)
        XCTAssertFalse(secondDivider.isHidden)
        XCTAssertEqual(firstDivider.frame.width * (NSScreen.main?.backingScaleFactor ?? 1), 1, accuracy: 0.001,
                       "Divider occupies one physical pixel on both 1x and Retina displays")

        picker.selectedTime = FluentTime(hour: 13, minute: 58)
        XCTAssertEqual(picker.selectedTime, FluentTime(hour: 13, minute: 45))
        XCTAssertEqual(
            try XCTUnwrap(picker.displayForegroundColor.usingColorSpace(.deviceRGB)).alphaComponent,
            try XCTUnwrap(lightTheme.textPrimary.usingColorSpace(.deviceRGB)).alphaComponent,
            accuracy: 0.001,
            "a selected time uses the normal enabled foreground rather than placeholder/disabled text"
        )
        picker.isEnabled = false
        XCTAssertEqual(
            try XCTUnwrap(picker.displayForegroundColor.usingColorSpace(.deviceRGB)).alphaComponent,
            try XCTUnwrap(lightTheme.textDisabled.usingColorSpace(.deviceRGB)).alphaComponent,
            accuracy: 0.001
        )
        picker.isEnabled = true
        picker.minuteIncrement = 0
        XCTAssertEqual(picker.selectedTime, FluentTime(hour: 13, minute: 0))
        picker.minuteIncrement = 60
        XCTAssertEqual(picker.minuteIncrement, 0, "WinUI rejects increments outside 0...59")

        picker.clockIdentifier = .twentyFourHour
        picker.layoutSubtreeIfNeeded()
        XCTAssertTrue(secondDivider.isHidden, "24-hour mode removes the period column and its divider")
        XCTAssertEqual(picker.accessibilityValue() as? String, "13:00")
    }

    @MainActor
    func testTimePickerBindingAndDeclarativeUpdatesPreserveIdentity() throws {
        _ = NSApplication.shared
        let state = FluentState<FluentTime?>(wrappedValue: nil)
        let host = FluentViewHost(
            FluentTimePickerView(
                selection: state.projectedValue,
                minuteIncrement: 5,
                clockIdentifier: .twentyFourHour
            ),
            context: FluentRenderContext(reduceMotion: true)
        )
        let picker = try XCTUnwrap(host.subviews.first as? FluentTimePicker)
        picker.selectedTime = FluentTime(hour: 8, minute: 14)
        XCTAssertEqual(state.wrappedValue, FluentTime(hour: 8, minute: 10))

        state.wrappedValue = FluentTime(hour: 18, minute: 49)
        waitForUI(picker.selectedTime == FluentTime(hour: 18, minute: 45))
        XCTAssertEqual(picker.selectedTime, FluentTime(hour: 18, minute: 45))
        XCTAssertEqual(state.wrappedValue, FluentTime(hour: 18, minute: 45), "The adjusted time is written back to the binding")
        host.update(FluentTimePickerView(
            selection: state.projectedValue,
            minuteIncrement: 15,
            clockIdentifier: .twelveHour,
            header: "Time"
        ))
        XCTAssertTrue(host.subviews.first === picker)
        XCTAssertEqual(picker.selectedTime, FluentTime(hour: 18, minute: 45))
        XCTAssertEqual(picker.clockIdentifier, .twelveHour)
    }

    @MainActor
    func testWinUIDatePickerClosedFieldsAndYearRangeSemantics() throws {
        _ = NSApplication.shared
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US")
        gregorian.timeZone = TimeZone(identifier: "UTC")!

        let selected = try XCTUnwrap(
            gregorian.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12))
        )
        let picker = FluentWinUIDatePickerControl(
            selectedDate: selected,
            calendarIdentifier: "gregorian",
            yearVisible: true
        )
        picker.reduceMotion = true

        let fields = picker.closedFieldTexts
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[0], "13")
        XCTAssertEqual(fields[2], "2026")
        XCTAssertFalse(fields[1].isEmpty)

        picker.yearVisible = false
        XCTAssertEqual(picker.closedFieldTexts, ["13", fields[1]])

        picker.yearVisible = true
        picker.selectedDate = nil
        XCTAssertEqual(picker.closedFieldTexts, ["day", "month", "year"])

        let minYear = try XCTUnwrap(
            gregorian.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 12))
        )
        let maxYear = try XCTUnwrap(
            gregorian.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 12))
        )
        let clampedLow = FluentWinUIDatePickerControl(
            selectedDate: try XCTUnwrap(gregorian.date(from: DateComponents(year: 2010, month: 6, day: 1, hour: 12))),
            minYear: minYear,
            maxYear: maxYear,
            dayFormat: "{day.integer}",
            monthFormat: "{month.full}",
            yearFormat: "{year.full}",
            calendarIdentifier: "gregorian"
        )
        let clampedLowDate = try XCTUnwrap(clampedLow.selectedDate)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: clampedLowDate), 2020)
        XCTAssertEqual(clampedLow.closedFieldTexts[0], "1")
        XCTAssertEqual(clampedLow.closedFieldTexts[2], "2020")

        let clampedHigh = FluentWinUIDatePickerControl(
            selectedDate: try XCTUnwrap(gregorian.date(from: DateComponents(year: 2030, month: 6, day: 1, hour: 12))),
            minYear: minYear,
            maxYear: maxYear,
            dayFormat: "{day.integer}",
            monthFormat: "{month.full}",
            yearFormat: "{year.full}",
            calendarIdentifier: "gregorian"
        )
        let clampedHighDate = try XCTUnwrap(clampedHigh.selectedDate)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: clampedHighDate), 2025)
        XCTAssertEqual(clampedHigh.closedFieldTexts[0], "31")
        XCTAssertEqual(clampedHigh.closedFieldTexts[2], "2025")

        let invalidRange = FluentWinUIDatePickerControl(minYear: maxYear, maxYear: minYear)
        XCTAssertFalse(invalidRange.hasValidYearRange)
        XCTAssertEqual(invalidRange.closedFieldTexts, ["", "", ""])
    }

    @MainActor
    func testWinUIDatePickerFormatsSupportedDateTokens() throws {
        _ = NSApplication.shared
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US")
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let date = try XCTUnwrap(
            gregorian.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12))
        )

        XCTAssertEqual(FluentWinUIDatePickerControl.format("{day.integer}", field: .day, date: date, calendar: gregorian), "13")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("{month.full}", field: .month, date: date, calendar: gregorian), "August")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("{month.abbreviated}", field: .month, date: date, calendar: gregorian), "Aug")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("{year.full}", field: .year, date: date, calendar: gregorian), "2026")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("{dayofweek.full}", field: .day, date: date, calendar: gregorian), "Thursday")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("{dayofweek.abbreviated}", field: .day, date: date, calendar: gregorian), "Thu")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("day", field: .day, date: date, calendar: gregorian), "13")
        XCTAssertEqual(FluentWinUIDatePickerControl.format("month", field: .month, date: date, calendar: gregorian), "August")
    }

    @MainActor
    func testWinUIDatePickerBindingDeclarativeUpdatesAndAccessibility() throws {
        _ = NSApplication.shared
        let state = FluentState<Date?>(wrappedValue: nil)
        let host = FluentViewHost(
            FluentWinUIDatePickerView(
                selection: state.projectedValue,
                calendarIdentifier: "gregorian",
                yearVisible: true,
                header: "Pick a date"
            ),
            context: FluentRenderContext(reduceMotion: true)
        )
        let picker = try XCTUnwrap(host.subviews.first as? FluentWinUIDatePickerControl)
        XCTAssertEqual(picker.accessibilityLabel(), "Pick a date")
        XCTAssertEqual(picker.accessibilityValue() as? String, FluentLocalization.controlString("No date selected"))
        XCTAssertEqual(picker.accessibilityRole(), .popUpButton)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12))
        )
        picker.selectedDate = date
        XCTAssertEqual(state.wrappedValue, date)

        let updatedDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 3, day: 2, hour: 12))
        )
        state.wrappedValue = updatedDate
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(picker.selectedDate, updatedDate)

        host.update(
            FluentWinUIDatePickerView(
                selection: state.projectedValue,
                calendarIdentifier: "gregorian",
                yearVisible: false,
                header: "Day and month"
            )
        )
        XCTAssertTrue(host.subviews.first === picker)
        XCTAssertFalse(picker.yearVisible)
        XCTAssertEqual(picker.header, "Day and month")
        XCTAssertEqual(picker.closedFieldTexts.count, 2)
    }

    @MainActor
    func testWinUIDatePickerFlyoutCommitAndDismissAreTransactional() throws {
        _ = NSApplication.shared
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let initialDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12))
        )

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }

        func makeFlyout() throws -> FluentWinUIDatePickerFlyout {
            FluentWinUIDatePickerFlyout(
                date: initialDate,
                minYear: nil,
                maxYear: nil,
                dayFormat: nil,
                monthFormat: nil,
                yearFormat: nil,
                calendarIdentifier: "gregorian",
                yearVisible: true,
                theme: .custom(colorScheme: .light, materialEffectsEnabled: false),
                reduceMotion: true
            )
        }

        let committed = try makeFlyout()
        committed.frame = NSRect(origin: .zero, size: committed.intrinsicContentSize)
        committed.layoutSubtreeIfNeeded()
        let daySelector = try XCTUnwrap(
            descendant(identifier: "FluentKit.WinUIDatePicker.DaySelector", in: committed)
                as? FluentWinUILoopingSelector
        )
        XCTAssertGreaterThan(daySelector.values.count, 1)
        let committedDay = (daySelector.selectedIndex + 1) % daySelector.values.count
        daySelector.selectedIndex = committedDay
        var accepted: Date?
        committed.onAccept = { accepted = $0 }
        let acceptButton = try XCTUnwrap(
            committed.subviews.compactMap { $0 as? NSControl }
                .first { $0.accessibilityLabel() == "Accept" }
        )
        acceptButton.performClick(nil)
        let acceptedDate = try XCTUnwrap(accepted)
        XCTAssertEqual(
            calendar.component(.day, from: acceptedDate),
            Int(daySelector.values[committedDay])
        )

        let dismissed = try makeFlyout()
        dismissed.frame = NSRect(origin: .zero, size: dismissed.intrinsicContentSize)
        dismissed.layoutSubtreeIfNeeded()
        let dismissDaySelector = try XCTUnwrap(
            descendant(identifier: "FluentKit.WinUIDatePicker.DaySelector", in: dismissed)
                as? FluentWinUILoopingSelector
        )
        dismissDaySelector.selectedIndex = (dismissDaySelector.selectedIndex + 1) % dismissDaySelector.values.count
        var dismissedAccept: Date?
        var didDismiss = false
        dismissed.onAccept = { dismissedAccept = $0 }
        dismissed.onDismiss = { didDismiss = true }
        let dismissButton = try XCTUnwrap(
            dismissed.subviews.compactMap { $0 as? NSControl }
                .first { $0.accessibilityLabel() == "Dismiss" }
        )
        dismissButton.performClick(nil)
        XCTAssertTrue(didDismiss)
        XCTAssertNil(dismissedAccept)
    }

    @MainActor
    func testAppBarButtonMatchesWinUIPresentationGeometryAndReleaseActivation() throws {
        _ = NSApplication.shared
        var invocations = 0
        let button = FluentAppBarButton("Save", systemImageName: "square.and.arrow.down") {
            invocations += 1
        }
        button.reduceMotion = true
        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        root.addSubview(button)
        let editor = NSTextField(frame: NSRect(x: 100, y: 10, width: 120, height: 24))
        root.addSubview(editor)
        let window = NSWindow(
            contentRect: root.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(editor), "test precondition: the editor must own focus")
        let commandTarget = window.firstResponder
        button.layoutSubtreeIfNeeded()

        XCTAssertEqual(button.presentation, .fullSize)
        XCTAssertEqual(button.intrinsicContentSize, NSSize(width: 68, height: 64))
        let surface = try XCTUnwrap(button.layer?.sublayers?.first { $0.name == "FluentKit.AppBarButton.InnerBorder" })
        XCTAssertEqual(surface.frame, CGRect(x: 1, y: 0, width: 66, height: 64))

        button.isCompact = true
        button.frame.size = button.intrinsicContentSize
        button.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.presentation, .compact)
        XCTAssertEqual(button.intrinsicContentSize, NSSize(width: 68, height: 48))
        XCTAssertEqual(surface.frame, CGRect(x: 1, y: 0, width: 66, height: 48))

        button.defaultLabelPosition = .right
        XCTAssertEqual(button.presentation, .labelOnRight)
        XCTAssertEqual(button.intrinsicContentSize.height, 48)
        button.labelPosition = .collapsed
        XCTAssertEqual(button.presentation, .labelCollapsed)
        XCTAssertEqual(button.intrinsicContentSize, NSSize(width: 68, height: 48))
        button.useOverflowStyle = true
        XCTAssertEqual(button.presentation, .overflow)
        XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.width, 160)
        XCTAssertEqual(button.intrinsicContentSize.height, 40)

        button.useOverflowStyle = false
        button.labelPosition = .default
        button.defaultLabelPosition = .bottom
        button.isCompact = false
        button.frame.size = button.intrinsicContentSize

        func mouse(_ type: NSEvent.EventType, point: NSPoint, number: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: TimeInterval(number) / 100,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
        button.mouseDown(with: try mouse(.leftMouseDown, point: NSPoint(x: 20, y: 20), number: 1))
        XCTAssertTrue(window.firstResponder === commandTarget, "AllowFocusOnInteraction=False must preserve the command target")
        XCTAssertEqual(invocations, 0)
        button.mouseDragged(with: try mouse(.leftMouseDragged, point: NSPoint(x: 200, y: 90), number: 2))
        button.mouseUp(with: try mouse(.leftMouseUp, point: NSPoint(x: 200, y: 90), number: 3))
        XCTAssertEqual(invocations, 0, "dragging outside cancels the press")

        let keyDown = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        let keyUp = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0.1,
            windowNumber: window.windowNumber, context: nil, characters: " ",
            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
        ))
        button.keyDown(with: keyDown)
        XCTAssertEqual(invocations, 0)
        button.keyUp(with: keyUp)
        XCTAssertEqual(invocations, 1, "ButtonBase activates on key release")
        window.orderOut(nil)
    }

    @MainActor
    func testAppBarToggleOverflowBindingAndSeparatorBranches() throws {
        _ = NSApplication.shared
        let state = FluentState<Bool>(wrappedValue: false)
        let makeView = {
            FluentAppBarToggleButtonView(
                "Pin",
                systemImageName: "pin",
                isChecked: state.projectedValue,
                useOverflowStyle: true
            )
        }
        let host = FluentViewHost(makeView(), context: FluentRenderContext(reduceMotion: true))
        func descendant<T>(_ type: T.Type, in root: NSView) -> T? {
            if let value = root as? T { return value }
            return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
        }
        let toggle = try XCTUnwrap(descendant(FluentAppBarToggleButton.self, in: host))
        XCTAssertEqual(toggle.presentation, .overflow)
        XCTAssertEqual(toggle.accessibilityRole(), .checkBox)
        toggle.invokeAction()
        XCTAssertTrue(toggle.isChecked)
        XCTAssertTrue(state.wrappedValue)
        XCTAssertEqual(toggle.accessibilityValue() as? String, "On")

        state.wrappedValue = false
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertFalse(toggle.isChecked)
        host.update(makeView())
        XCTAssertTrue(descendant(FluentAppBarToggleButton.self, in: host) === toggle)

        let separator = FluentAppBarSeparator()
        separator.frame = NSRect(origin: .zero, size: separator.intrinsicContentSize)
        separator.layoutSubtreeIfNeeded()
        XCTAssertEqual(separator.intrinsicContentSize, NSSize(width: 5, height: 64))
        let divider = try XCTUnwrap(separator.layer?.sublayers?.first { $0.name == "FluentKit.AppBarSeparator.Divider" })
        XCTAssertEqual(divider.frame.height, 48, accuracy: 0.001)
        XCTAssertLessThanOrEqual(divider.frame.width, 1)

        separator.useOverflowStyle = true
        separator.frame.size = separator.intrinsicContentSize
        separator.layoutSubtreeIfNeeded()
        XCTAssertEqual(separator.intrinsicContentSize, NSSize(width: 160, height: 9))
        XCTAssertEqual(divider.frame.minY, 4, accuracy: 0.001)
        XCTAssertLessThanOrEqual(divider.frame.height, 1)
        XCTAssertFalse(separator.isAccessibilityElement())
    }

    @MainActor
    func testCommandBarPropagatesCompactLabelAndOverflowVisibilityPolicies() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: [
            FluentCommandBarItem("Save", systemImageName: "square.and.arrow.down") {},
            FluentCommandBarItem("Share", systemImageName: "square.and.arrow.up") {}
        ])
        bar.reduceMotion = true
        bar.frame = NSRect(x: 0, y: 0, width: 240, height: 48)
        bar.layoutSubtreeIfNeeded()

        XCTAssertEqual(bar.intrinsicContentSize.height, 48)
        XCTAssertTrue(bar.isOverflowButtonVisible, "Auto shows More when a primary command has a bottom label")
        let buttons = bar.primaryCommandViews.compactMap { $0 as? FluentAppBarButton }
        XCTAssertEqual(buttons.map(\.presentation), [.compact, .compact])

        bar.defaultLabelPosition = .right
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(buttons.map(\.presentation), [.labelOnRight, .labelOnRight])
        XCTAssertFalse(bar.isOverflowButtonVisible, "Auto hides More when no secondary, overflow, or bottom-label condition remains")

        bar.overflowButtonVisibility = .visible
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.isOverflowButtonVisible)
        bar.overflowButtonVisibility = .collapsed
        bar.layoutSubtreeIfNeeded()
        XCTAssertFalse(bar.isOverflowButtonVisible)

        bar.closedDisplayMode = .minimal
        XCTAssertEqual(bar.intrinsicContentSize.height, 24)
        bar.closedDisplayMode = .hidden
        XCTAssertEqual(bar.intrinsicContentSize.height, 0)
        XCTAssertEqual(bar.accessibilityRole(), .toolbar)
    }

    @MainActor
    func testCommandBarDynamicOverflowMovesOrderedGroupsThenRestoresStableViews() throws {
        _ = NSApplication.shared
        var actions: [FluentCommandBarDynamicOverflowAction] = []
        let commands = [
            FluentCommandBarItem("Keep", systemImageName: "lock", labelPosition: .collapsed) {},
            FluentCommandBarItem("First A", systemImageName: "1.circle", dynamicOverflowOrder: 1, labelPosition: .collapsed) {},
            FluentCommandBarItem("First B", systemImageName: "1.circle.fill", dynamicOverflowOrder: 1, labelPosition: .collapsed) {},
            FluentCommandBarItem("Second", systemImageName: "2.circle", dynamicOverflowOrder: 2, labelPosition: .collapsed) {},
            FluentCommandBarItem("Fallback", systemImageName: "3.circle", labelPosition: .collapsed) {}
        ]
        let bar = FluentCommandBar(
            primaryCommands: commands,
            secondaryCommands: [FluentCommandBarItem("Settings", systemImageName: "gear") {}]
        )
        bar.reduceMotion = true
        bar.onDynamicOverflowItemsChanging = { actions.append($0) }
        let originalViews = bar.primaryCommandViews
        bar.frame = NSRect(x: 0, y: 0, width: 240, height: 48)
        bar.layoutSubtreeIfNeeded()

        XCTAssertTrue(bar.overflowedPrimaryIndexes.contains(1))
        XCTAssertTrue(bar.overflowedPrimaryIndexes.contains(2), "equal DynamicOverflowOrder values move as one group")
        XCTAssertFalse(bar.overflowedPrimaryIndexes.contains(0))
        XCTAssertEqual(actions.last, .addingToOverflow)

        bar.frame.size.width = 520
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.overflowedPrimaryIndexes.isEmpty)
        XCTAssertEqual(actions.last, .removingFromOverflow)
        XCTAssertEqual(bar.primaryCommandViews.count, originalViews.count)
        for index in originalViews.indices {
            XCTAssertTrue(bar.primaryCommandViews[index] === originalViews[index], "restoration must preserve command identity")
        }
    }

    @MainActor
    func testCommandBarDefaultOverflowCanMoveTheFirstAndOnlyPrimaryCommand() {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: [
            FluentCommandBarItem("Only", systemImageName: "doc", labelPosition: .collapsed) {}
        ])
        bar.reduceMotion = true
        bar.frame = NSRect(x: 0, y: 0, width: 40, height: 48)
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(bar.overflowedPrimaryIndexes, [0])
        XCTAssertTrue(bar.isOverflowButtonVisible)
    }

    @MainActor
    func testCommandBarMirrorsPrimaryStripAndRemovesConsecutiveOuterSeparators() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(primaryCommands: [
            FluentCommandBarItem("One", systemImageName: "1.circle", labelPosition: .collapsed) {},
            FluentCommandBarItem("Two", systemImageName: "2.circle", labelPosition: .collapsed) {}
        ])
        bar.reduceMotion = true
        bar.overflowButtonVisibility = .visible
        bar.userInterfaceLayoutDirection = .rightToLeft
        bar.frame = NSRect(x: 0, y: 0, width: 180, height: 48)
        bar.layoutSubtreeIfNeeded()

        let more = try XCTUnwrap(bar.subviews.first {
            $0.identifier?.rawValue == "FluentKit.CommandBar.MoreButton"
        })
        XCTAssertEqual(more.frame.minX, 0, accuracy: 0.001)
        let buttons = bar.primaryCommandViews.compactMap { $0 as? FluentAppBarButton }
        XCTAssertGreaterThan(buttons[0].frame.minX, buttons[1].frame.minX)

        let separators = FluentCommandBar(primaryCommands: [
            .separator(dynamicOverflowOrder: 1),
            .separator(dynamicOverflowOrder: 1),
            FluentCommandBarItem("One", systemImageName: "1.circle", labelPosition: .collapsed) {},
            FluentCommandBarItem("Two", systemImageName: "2.circle", labelPosition: .collapsed) {},
            .separator,
            .separator
        ])
        separators.reduceMotion = true
        separators.overflowButtonVisibility = .visible
        separators.frame = NSRect(x: 0, y: 0, width: 100, height: 48)
        separators.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            separators.visiblePrimaryIndexes.allSatisfy { !separators.primaryCommands[$0].isSeparator },
            "dynamic overflow must not strand consecutive separators at either visible edge"
        )
    }

    @MainActor
    func testCommandBarOpenReparentsRealControlsAndRestoresFocus() throws {
        _ = NSApplication.shared
        var invoked = 0
        let editor = NSTextField(frame: NSRect(x: 4, y: 80, width: 160, height: 24))
        let bar = FluentCommandBar(
            primaryCommands: [
                FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") { invoked += 1 }
            ],
            secondaryCommands: [
                FluentCommandBarItem("Select all", systemImageName: "selection.pin.in.out") { invoked += 10 }
            ]
        )
        bar.reduceMotion = true
        bar.frame = NSRect(x: 0, y: 0, width: 260, height: 48)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        root.addSubview(bar)
        root.addSubview(editor)
        let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(editor))
        let originalFirstResponder = window.firstResponder
        bar.layoutSubtreeIfNeeded()

        let primaryButton = try XCTUnwrap(bar.primaryCommandViews.first as? FluentAppBarButton)
        XCTAssertEqual(primaryButton.presentation, .compact)
        bar.setOpen(true, animated: false)
        XCTAssertTrue(bar.isOpen)
        XCTAssertEqual(bar.intrinsicContentSize.height, 64)
        XCTAssertEqual(primaryButton.presentation, .fullSize)
        XCTAssertTrue(bar.isOpen)

        let overflowPanel = try XCTUnwrap(window.childWindows?.first { child in
            child.contentView?.identifier?.rawValue == "FluentKit.CommandBar.Overflow"
        })
        func descendants<T>(_ type: T.Type, in root: NSView) -> [T] {
            (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants(type, in: $0) }
        }
        let overflowButtons = overflowPanel.contentView.map {
            descendants(FluentAppBarButton.self, in: $0)
        } ?? []
        let secondaryButton = try XCTUnwrap(overflowButtons.first { $0.label == "Select all" && $0.isInOverflow })
        XCTAssertTrue(secondaryButton.accessibilityPerformPress())
        XCTAssertEqual(invoked, 10)
        XCTAssertFalse(bar.isOpen, "invoking an overflow command closes CommandBar")

        bar.setOpen(true, animated: false)
        XCTAssertTrue(bar.isOpen)

        bar.setOpen(false, animated: false)
        XCTAssertFalse(bar.isOpen)
        XCTAssertFalse(bar.isOpen)
        XCTAssertTrue(primaryButton.superview === bar)
        XCTAssertTrue(window.firstResponder === originalFirstResponder)
        XCTAssertTrue(primaryButton.accessibilityPerformPress())
        XCTAssertEqual(invoked, 11)
        window.orderOut(nil)
    }

    @MainActor
    func testCommandBarProgrammaticOpenIgnoresCollapsedMoreButtonAndOverflowKeyboardNavigation() throws {
        _ = NSApplication.shared
        let bar = FluentCommandBar(
            primaryCommands: [FluentCommandBarItem("Copy", systemImageName: "doc.on.doc", labelPosition: .collapsed) {}],
            secondaryCommands: [
                FluentCommandBarItem("One") {},
                FluentCommandBarItem("Two") {},
                FluentCommandBarItem("Three") {}
            ]
        )
        bar.reduceMotion = true
        bar.overflowButtonVisibility = .collapsed
        bar.frame = NSRect(x: 0, y: 0, width: 240, height: 48)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = bar
        window.makeKeyAndOrderFront(nil)
        bar.layoutSubtreeIfNeeded()
        XCTAssertFalse(bar.isOverflowButtonVisible)

        bar.setOpen(true, animated: false)
        XCTAssertTrue(bar.isOpen, "OverflowButtonVisibility.Collapsed hides only the invocation target")
        let panel = try XCTUnwrap(window.childWindows?.first)
        func buttons(in root: NSView) -> [FluentAppBarButton] {
            (root as? FluentAppBarButton).map { [$0] } ?? root.subviews.flatMap(buttons)
        }
        let rows = buttons(in: try XCTUnwrap(panel.contentView))
        XCTAssertEqual(rows.map(\.label), ["One", "Two", "Three"])
        XCTAssertTrue(panel.makeFirstResponder(rows[0]))
        let down = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125
        ))
        panel.sendEvent(down)
        XCTAssertTrue(panel.firstResponder === rows[1])
        bar.setOpen(false, animated: false)
        window.orderOut(nil)
    }

    @MainActor
    func testMenuBarUsesWinUISourceGeometryAccessKeysAndEmptyItemBehavior() throws {
        _ = NSApplication.shared
        let bar = FluentMenuBar(items: [
            FluentMenuBarItem("File", accessKey: "F") {
                FluentMenuItem("New") {}
            },
            FluentMenuBarItem("Empty", accessKey: "E", items: [])
        ])
        bar.reduceMotion = true
        bar.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        root.addSubview(bar)
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        bar.layoutSubtreeIfNeeded()

        XCTAssertEqual(bar.intrinsicContentSize.height, 40)
        XCTAssertEqual(bar.accessibilityRole(), .menuBar)
        XCTAssertEqual(bar.itemControlViews.count, 2)
        XCTAssertEqual(bar.itemControlViews[0].frame.height, 32)
        bar.frame.size.height = 24
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            bar.itemControlViews[0].frame.height,
            16,
            "a 24-point MenuBar preserves the source four-point outer margins"
        )
        bar.frame.size.height = 40
        bar.layoutSubtreeIfNeeded()

        XCTAssertTrue(bar.itemControlViews[1].accessibilityPerformPress())
        XCTAssertFalse(bar.isFlyoutOpen, "a MenuBarItem with no children must not create a popup")
        XCTAssertTrue(bar.performAccessKey("f"))
        XCTAssertEqual(bar.openItemIndex, 0)
        XCTAssertTrue(bar.isFlyoutOpen)
        bar.closeMenu()

        let optionF = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "ƒ",
            charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3
        ))
        NSApp.sendEvent(optionF)
        XCTAssertEqual(bar.openItemIndex, 0, "Option plus AccessKey enters MenuBar access-key mode")
        bar.closeMenu()
        window.orderOut(nil)
    }

    @MainActor
    func testMenuBarHoverAndExpandedArrowNavigationSwitchTopLevelFlyouts() throws {
        _ = NSApplication.shared
        let bar = FluentMenuBar(items: [
            FluentMenuBarItem("File") { FluentMenuItem("New") {} },
            FluentMenuBarItem("Disabled", isEnabled: false) { FluentMenuItem("Never") {} },
            FluentMenuBarItem("View") { FluentMenuItem("Zoom") {} }
        ])
        bar.reduceMotion = true
        bar.frame = NSRect(x: 0, y: 0, width: 320, height: 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = bar
        window.makeKeyAndOrderFront(nil)
        bar.layoutSubtreeIfNeeded()
        bar.openItem(at: 0)
        XCTAssertEqual(bar.openItemIndex, 0)

        let entered = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 0, pressure: 0
        ))
        bar.itemControlViews[2].mouseEntered(with: entered)
        XCTAssertEqual(bar.openItemIndex, 2, "hover switches top-level flyouts while the MenuBar is open")

        let panel = try XCTUnwrap(window.childWindows?.first)
        let right = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124
        ))
        panel.sendEvent(right)
        XCTAssertEqual(bar.openItemIndex, 0, "expanded Right wraps and skips disabled top-level items")

        bar.userInterfaceLayoutDirection = .rightToLeft
        bar.layoutSubtreeIfNeeded()
        bar.closeMenu()
        XCTAssertTrue(window.makeFirstResponder(bar.itemControlViews[0]))
        bar.itemControlViews[0].keyDown(with: right)
        XCTAssertTrue(window.firstResponder === bar.itemControlViews[2], "RTL reverses physical top-level arrow navigation")
        window.orderOut(nil)
    }

    @MainActor
    func testMenuBarSingleExpandedItemClosesOnHorizontalArrowAndDeclarativeUpdatePreservesIdentity() throws {
        _ = NSApplication.shared
        let bar = FluentMenuBar(items: [
            FluentMenuBarItem(id: "only", "Only") { FluentMenuItem("Action") {} }
        ])
        bar.reduceMotion = true
        bar.frame = NSRect(x: 0, y: 0, width: 160, height: 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = bar
        window.makeKeyAndOrderFront(nil)
        bar.openItem(at: 0)
        let panel = try XCTUnwrap(window.childWindows?.first)
        let right = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124
        ))
        panel.sendEvent(right)
        XCTAssertFalse(bar.isFlyoutOpen)

        let original = try XCTUnwrap(bar.itemControlViews.first)
        bar.items = [FluentMenuBarItem(id: "only", "Renamed") { FluentMenuItem("Other") {} }]
        XCTAssertTrue(bar.itemControlViews.first === original)
        XCTAssertEqual(original.accessibilityTitle(), "Renamed")
        window.orderOut(nil)
    }

    @MainActor
    func testAutoSuggestBoxDebouncesTextChangedAndSubmitsSelectedSuggestion() throws {
        _ = NSApplication.shared
        let text = FluentState(wrappedValue: "")
        var changed: [String] = []
        var chosen: [String] = []
        var submitted: [(String, String?)] = []
        let auto = FluentAutoSuggestBox(
            text.projectedValue,
            placeholder: "Search controls",
            querySystemImageName: "magnifyingglass",
            suggestions: { query in
                guard !query.isEmpty else { return [] }
                return ["Apple", "Apricot", "Banana"]
                    .filter { $0.localizedCaseInsensitiveContains(query) }
                    .map { FluentAutoSuggestBoxSuggestion(title: $0) }
            },
            onTextChanged: { changed.append($0) },
            onSuggestionChosen: { chosen.append($0.title) },
            onSubmit: { query, suggestion in
                submitted.append((query, suggestion?.title))
            }
        )
        let host = FluentViewHost(auto)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        host.layoutSubtreeIfNeeded()
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        func descendants(identifier: String, in root: NSView) -> [NSView] {
            let own = root.identifier?.rawValue == identifier ? [root] : []
            return own + root.subviews.flatMap { descendants(identifier: identifier, in: $0) }
        }

        let field = try XCTUnwrap(
            descendant(identifier: "FluentKit.AutoSuggestBox.Field", in: host) as? NSTextField
        )
        XCTAssertTrue(window.makeFirstResponder(field))
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
        waitForUI(window.childWindows?.first?.isVisible == true)

        XCTAssertEqual(changed, ["Ap"])
        XCTAssertEqual(text.wrappedValue, "Ap")
        let popup = try XCTUnwrap(window.childWindows?.first)
        let popupRoot = try XCTUnwrap(popup.contentView)
        let rows = descendants(identifier: "FluentKit.AutoSuggestBox.Suggestion", in: popupRoot)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].accessibilityLabel(), "Apple")
        XCTAssertEqual(rows[1].accessibilityLabel(), "Apricot")

        editor.doCommand(by: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(field.stringValue, "Apple")
        XCTAssertEqual(text.wrappedValue, "Apple")
        XCTAssertEqual(chosen, ["Apple"])

        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(submitted[0].0, "Apple")
        XCTAssertEqual(submitted[0].1, "Apple")
        XCTAssertFalse(popup.isVisible)
        window.orderOut(nil)
    }

    @MainActor
    func testAutoSuggestBoxClearAndQueryButtonsFollowWinUISemantics() throws {
        _ = NSApplication.shared
        let text = FluentState(wrappedValue: "")
        var submitted: [(String, String?)] = []
        let auto = FluentAutoSuggestBox(
            text.projectedValue,
            placeholder: "Search",
            querySystemImageName: "magnifyingglass",
            suggestions: { query in
                guard !query.isEmpty else { return [] }
                return ["Apple", "Apricot", "Banana"]
                    .filter { $0.localizedCaseInsensitiveContains(query) }
                    .map { FluentAutoSuggestBoxSuggestion(title: $0) }
            },
            onSubmit: { query, suggestion in
                submitted.append((query, suggestion?.title))
            }
        )
        let host = FluentViewHost(auto)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        host.layoutSubtreeIfNeeded()
        let window = NSWindow(
            contentRect: host.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)

        func descendant(identifier: String, in root: NSView) -> NSView? {
            if root.identifier?.rawValue == identifier { return root }
            return root.subviews.lazy.compactMap { descendant(identifier: identifier, in: $0) }.first
        }
        func descendants(identifier: String, in root: NSView) -> [NSView] {
            let own = root.identifier?.rawValue == identifier ? [root] : []
            return own + root.subviews.flatMap { descendants(identifier: identifier, in: $0) }
        }

        let field = try XCTUnwrap(
            descendant(identifier: "FluentKit.AutoSuggestBox.Field", in: host) as? NSTextField
        )
        let clear = try XCTUnwrap(
            descendant(identifier: "FluentKit.AutoSuggestBox.ClearButton", in: host) as? NSButton
        )
        let query = try XCTUnwrap(
            descendant(identifier: "FluentKit.AutoSuggestBox.QueryButton", in: host) as? NSButton
        )
        XCTAssertTrue(window.makeFirstResponder(field))
        field.selectText(nil)
        let initialEditor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        initialEditor.insertText("Ap", replacementRange: NSRange(location: 0, length: 0))
        waitForUI(window.childWindows?.first?.isVisible == true)
        let firstPopup = try XCTUnwrap(window.childWindows?.first)
        XCTAssertTrue(firstPopup.isVisible)
        XCTAssertFalse(clear.isHidden)

        clear.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(field.stringValue, "")
        XCTAssertEqual(text.wrappedValue, "")
        XCTAssertTrue(clear.isHidden)
        XCTAssertFalse(firstPopup.isVisible)

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText("Ba", replacementRange: NSRange(location: 0, length: 0))
        waitForUI(window.childWindows?.first?.isVisible == true)
        let secondPopup = try XCTUnwrap(window.childWindows?.first)
        XCTAssertTrue(secondPopup.isVisible)
        host.layoutSubtreeIfNeeded()
        let adornmentHost = try XCTUnwrap(query.superview)
        XCTAssertEqual(query.frame.maxX, adornmentHost.bounds.width - 4, accuracy: 0.001)
        XCTAssertEqual(clear.frame.maxX, query.frame.minX - 2, accuracy: 0.001)
        XCTAssertEqual(
            descendants(identifier: "FluentKit.AutoSuggestBox.Suggestion", in: try XCTUnwrap(secondPopup.contentView)).count,
            1
        )

        query.performClick(nil)
        XCTAssertEqual(submitted.last?.0, "Ba")
        XCTAssertNil(submitted.last?.1)
        XCTAssertFalse(secondPopup.isVisible)
        window.orderOut(nil)
    }
}
