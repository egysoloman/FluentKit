import XCTest
@testable import FluentKit

final class FluentKitTests: XCTestCase {
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
}
