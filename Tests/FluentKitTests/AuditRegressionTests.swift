import XCTest
@testable import FluentKit

private final class AuditCounters {
    var updates = 0
    var attachments = 0
    var makes = 0
}
private final class AuditNativeView: NSView {
    let counters: AuditCounters
    init(_ counters: AuditCounters) { self.counters = counters; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 20) }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); counters.attachments += 1 }
}
private struct AuditRow: FluentUpdatablePrimitiveView {
    let counters: AuditCounters
    var value = "Stable"
    var body: NeverFluentView { NeverFluentView() }
    func _makeView(in context: FluentRenderContext) -> NSView {
        counters.makes += 1
        return NSTextField(labelWithString: value)
    }
    func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let label = view as? NSTextField else { return false }
        counters.updates += 1
        label.stringValue = value
        return true
    }
}
private struct AuditShell: FluentView {
    let state: FluentState<String>
    let counters: AuditCounters
    let native: AuditNativeView
    var body: FluentAnyView {
        let text = state.wrappedValue
        return FluentAnyView(FluentWindowShell(
            configuration: .init(layout: .document, titleBarStyle: .extended, navigationPlacement: .left,
                                 backdrop: .solid, contentTransition: .none),
            title: "Audit", items: [FluentNavigationItem(id: "home", title: "Home", systemImageName: "house")],
            selection: FluentBinding<String?>(get: { "home" }, set: { _ in }),
            header: { FluentEmptyView() }, content: {
                FluentVStack {
                    FluentTextFieldView(text: state.projectedValue)
                    FluentText(text)
                    FluentForEach(Array(0..<8), id: \.self) { _ in AuditRow(counters: counters) }
                    FluentNativeView(native)
                }
            }))
    }
}
private final class MeasuredTextField: FluentTextField {
    var invalidations = 0
    override func invalidateIntrinsicContentSize() { invalidations += 1; super.invalidateIntrinsicContentSize() }
}

final class AuditRegressionTests: XCTestCase {
    @MainActor private func drain() async {
        for _ in 0..<6 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
    @MainActor private func window(_ view: NSView, width: CGFloat = 900) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor func testWindowShellHasOneUpdateTraversalAndKeepsNativeAttachment() async throws {
        _ = NSApplication.shared
        let state = FluentState(wrappedValue: "")
        let counters = AuditCounters()
        let native = AuditNativeView(counters)
        let host = FluentViewHost(AuditShell(state: state, counters: counters, native: native),
                                  context: .init(theme: .custom(colorScheme: .light, materialEffectsEnabled: false), reduceMotion: true))
        let window = window(host)
        defer { window.close() }
        await drain()
        let field = try XCTUnwrap(descendants(host).compactMap { $0 as? FluentTextField }.first)
        let parent = native.superview
        counters.updates = 0
        counters.attachments = 0
        for index in 0..<3 {
            field.stringValue = "input-\(index)"
            field.delegate?.controlTextDidChange?(.init(name: NSControl.textDidChangeNotification, object: field))
            await drain()
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(counters.updates, 24)
        XCTAssertEqual(counters.attachments, 0)
        XCTAssertTrue(native.superview === parent)
        XCTAssertEqual(state.wrappedValue, "input-2")
    }

    @MainActor func testNativeFactoryIsCreatedOnceAndReceivesUpdatedConfiguration() {
        _ = NSApplication.shared
        var makes = 0
        func content(_ text: String) -> FluentNativeView {
            FluentNativeView(make: { makes += 1; return NSTextField(labelWithString: "") }, update: { (field: NSTextField, _) in field.stringValue = text })
        }
        let host = FluentViewHost(content("a"))
        let view = host.subviews.first
        host.update(content("b"), context: .init(theme: .custom(colorScheme: .dark)))
        XCTAssertEqual(makes, 1)
        XCTAssertTrue(host.subviews.first === view)
        XCTAssertEqual((view as? NSTextField)?.stringValue, "b")
    }

    @MainActor func testFocusedExternalResetCancelsQueuedLocalWriteAndSurvivesBlur() async throws {
        let state = FluentState(wrappedValue: "initial")
        let bound = FluentBoundTextField(state.projectedValue)
        let window = window(bound, width: 360)
        defer { window.close() }
        window.orderFrontRegardless()
        bound.field.selectText(nil)
        let editor = try XCTUnwrap(bound.field.currentEditor() as? NSTextView)
        editor.string = "typed"
        editor.didChangeText()
        state.wrappedValue = "external reset" // Beats the scheduled local publication.
        await drain()
        XCTAssertEqual(editor.string, "external reset")
        XCTAssertEqual(bound.field.stringValue, "external reset")
        editor.string = "unsent local text"
        editor.didChangeText()
        state.observableValue.send() // Explicitly resetting to the same model value also wins.
        await drain()
        XCTAssertEqual(editor.string, "external reset")
        window.makeFirstResponder(nil)
        await drain()
        XCTAssertEqual(state.wrappedValue, "external reset")
    }

    @MainActor func testCommittedTextPolicyDefersIMEAndExternalResetWinsAfterComposition() async throws {
        let state = FluentState(wrappedValue: "initial")
        var changes: [FluentTextEditingChange] = []
        let bound = FluentBoundTextField(state.projectedValue.textInput(.init(commitPolicy: .committedText, onEditingChange: { changes.append($0) })))
        let window = window(bound, width: 360)
        defer { window.close() }
        window.orderFrontRegardless()
        bound.field.selectText(nil)
        let editor = try XCTUnwrap(bound.field.currentEditor() as? NSTextView)
        editor.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.didChangeText()
        editor.setMarkedText("ping", selectedRange: NSRange(location: 4, length: 0), replacementRange: editor.markedRange())
        editor.didChangeText()
        XCTAssertEqual(changes.last?.text, "ping")
        await drain()
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(state.wrappedValue, "initial")
        XCTAssertEqual(changes.last?.isComposing, true)
        state.wrappedValue = "reset"
        XCTAssertTrue(editor.hasMarkedText())
        editor.unmarkText()
        editor.didChangeText()
        await drain()
        XCTAssertEqual(editor.string, "reset")
        XCTAssertEqual(changes.last?.isComposing, false)
        window.makeFirstResponder(nil)
        await drain()
        XCTAssertEqual(state.wrappedValue, "reset")
    }

    @MainActor func testClosureBindingResetAndBindingReplacementDoNotPublishOldText() {
        _ = NSApplication.shared
        var first = "a"
        var second = "b"
        let field = FluentTextField()
        let coordinator = FluentStringBindingCoordinator(field: field, binding: .init(get: { first }, set: { first = $0 }))
        field.stringValue = "local"
        first = "reset"
        coordinator.publishCurrentValue()
        XCTAssertEqual(field.stringValue, "reset")
        coordinator.update(binding: .init(get: { second }, set: { second = $0 }))
        coordinator.publishCurrentValue()
        XCTAssertEqual(first, "reset")
        XCTAssertEqual(second, "b")
    }

    @MainActor func testCollectionSkipsUnchangedSnapshotAndSupportsContentVersionsAndTheme() async throws {
        _ = NSApplication.shared
        let counters = AuditCounters()
        var versions: [Int: Int] = [:]
        func content(_ count: Int = 5000) -> FluentCollection<Int, Int> {
            FluentCollection(snapshot: .init(section: 0, items: Array(0..<count)), layout: .list(rowHeight: 24)) { id in
                AuditRow(counters: counters, value: "\(id):\(versions[id, default: 0])")
            }.contentVersion { versions[$0, default: 0] }
        }
        let host = FluentViewHost(content(), context: .init(theme: .custom(colorScheme: .light), reduceMotion: true))
        let window = window(host)
        defer { window.close() }
        await drain()
        host.layoutSubtreeIfNeeded()
        let collection = try XCTUnwrap(host.subviews.first as? FluentSectionedCollectionView<Int, Int>)
        XCTAssertLessThan(counters.makes, 50, "Initial layout must remain virtualized")
        let snapshots = collection.snapshotApplicationCount
        counters.updates = 0
        host.update(content())
        XCTAssertEqual(collection.snapshotApplicationCount, snapshots)
        XCTAssertEqual(counters.updates, 0)
        versions[0] = 1
        host.update(content())
        XCTAssertEqual(collection.snapshotApplicationCount, snapshots)
        XCTAssertEqual(counters.updates, 1)
        host.update(content(), context: .init(theme: .custom(colorScheme: .dark), reduceMotion: true))
        XCTAssertGreaterThan(counters.updates, 1)
        XCTAssertEqual(collection.snapshotApplicationCount, snapshots)
        host.update(content(5001))
        XCTAssertEqual(collection.snapshotApplicationCount, snapshots + 1)
    }

    @MainActor func testForEachStableOrderDoesNotDetachViewsAndMovesKeepIdentity() throws {
        _ = NSApplication.shared
        let counters = AuditCounters()
        let views = (0..<4).map { _ in AuditNativeView(counters) }
        func content(_ ids: [Int]) -> some FluentView { FluentForEach(ids, id: \.self) { FluentNativeView(views[$0]) } }
        let host = FluentViewHost(content([0, 1, 2, 3]))
        counters.attachments = 0
        host.update(content([0, 1, 2, 3]))
        XCTAssertEqual(counters.attachments, 0)
        host.update(content([3, 0, 2]))
        let stack = try XCTUnwrap(descendants(host).compactMap { $0 as? NSStackView }.first)
        XCTAssertEqual(stack.arrangedSubviews.map(ObjectIdentifier.init), [views[3], views[0], views[2]].map(ObjectIdentifier.init))
        XCTAssertNil(views[1].superview)
    }

    @MainActor func testEqualStateDeduplicatesButExplicitSendPublishes() {
        let state = FluentState(wrappedValue: "same")
        var notifications = 0
        let token = state.observableValue.observe({ _ in notifications += 1 }, notifyImmediately: false)
        defer { state.observableValue.removeObserver(token) }
        state.wrappedValue = "same"
        XCTAssertEqual(notifications, 0)
        state.observableValue.send()
        XCTAssertEqual(notifications, 1)
        state.wrappedValue = "new"
        XCTAssertEqual(notifications, 2)
        let observable = FluentObservable(1, areEquivalent: { _, _ in false })
        var forced = 0
        _ = observable.observe({ _ in forced += 1 }, notifyImmediately: false)
        observable.value = 1
        XCTAssertEqual(forced, 1)
    }

    @MainActor func testRepeatedTextStyleDoesNotInvalidateSizeAndFontIsReadyBeforeDrawing() {
        _ = NSApplication.shared
        let field = MeasuredTextField(placeholder: "Search")
        field.fluentStyle = FluentAutomaticTextFieldStyle()
        field.invalidations = 0
        for _ in 0..<20 { field.fluentStyle = FluentAutomaticTextFieldStyle() }
        XCTAssertEqual(field.invalidations, 0)
        field.theme = .custom(typography: .init(scale: 1.5))
        XCTAssertEqual(field.font?.pointSize, 21)
        XCTAssertTrue(field._updateView(field, in: .init(theme: field.theme)))
        XCTAssertEqual(field.placeholderAttributedString?.string ?? field.placeholderString, "Search")
    }

    @MainActor func testInactiveTextFieldsInstallNoApplicationMonitors() {
        _ = NSApplication.shared
        let before = FluentTextEditingSession.activeRightClickMonitorCount
        let fields = (0..<50).map { _ in FluentTextField() }
        XCTAssertEqual(fields.count, 50)
        XCTAssertEqual(FluentTextEditingSession.activeRightClickMonitorCount, before)
        let window = window(fields[0], width: 300)
        fields[0].selectText(nil)
        XCTAssertEqual(FluentTextEditingSession.activeRightClickMonitorCount, before + 1)
        window.makeFirstResponder(nil)
        XCTAssertEqual(FluentTextEditingSession.activeRightClickMonitorCount, before)
        window.close()
    }

    @MainActor func testTypographyMatchesUpstreamAndProviderCanOverrideFamilyAndLineHeight() {
        _ = NSApplication.shared
        let type = FluentTypography()
        for (style, size) in [(FluentTextStyle.caption, 12), (.body, 14), (.bodyLarge, 18), (.subtitle, 20), (.title, 28), (.titleLarge, 40), (.display, 68)] {
            XCTAssertEqual(type.font(for: style).pointSize, CGFloat(size))
        }
        let custom = FluentTypography(overrides: [.body: .init(size: 16, lineHeight: 25)], fontProvider: .init { _, size, _ in NSFont(name: "Menlo", size: size) })
        XCTAssertTrue(custom.font(for: .body).fontName.contains("Menlo"))
        XCTAssertEqual(custom.lineHeight(for: .body), 25)
    }

    @MainActor func testMaterialSemanticsAreSeparateFromNativeGlass() {
        _ = NSApplication.shared
        let mica = FluentMaterialView(material: .mica)
        let acrylic = FluentMaterialView(material: .acrylic)
        let expected: FluentMaterialBackend = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .opaque : .fluentRecipe
        XCTAssertEqual(mica.resolvedBackend, expected)
        XCTAssertEqual(acrylic.resolvedBackend, expected)
        mica.materialStyle = .nativeMica
        XCTAssertNotEqual(mica.resolvedBackend, .nativeGlass)
        mica.isMaterialEnabled = false
        XCTAssertEqual(mica.resolvedBackend, .opaque)
    }

    @MainActor func testIconSourcesPreserveAspectAndCommandChevronHasOwnSpaceInLTRAndRTL() throws {
        _ = NSApplication.shared
        let source = FluentIconSource.systemSymbol("ellipsis")
        let image = try XCTUnwrap(source.image(pointSize: 20))
        let rect = source.fittedRect(imageSize: image.size, in: NSRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertEqual(rect.width / rect.height, image.size.width / image.size.height, accuracy: 0.001)
        XCTAssertLessThan(rect.height, rect.width)
        let button = FluentAppBarButton("查看", systemImageName: "list.bullet")
        button.defaultLabelPosition = .right
        let withoutArrow = button.intrinsicContentSize.width
        button.flyoutItems = [FluentMenuItem("Details", action: {})]
        XCTAssertGreaterThan(button.intrinsicContentSize.width, withoutArrow)
        button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
        var geometry = button.horizontalContentGeometry
        XCTAssertGreaterThanOrEqual(geometry.chevron.minX - geometry.label.maxX, 8)
        button.userInterfaceLayoutDirection = .rightToLeft
        geometry = button.horizontalContentGeometry
        XCTAssertGreaterThanOrEqual(geometry.label.minX - geometry.chevron.maxX, 8)
        button.commandHeight = 32
        XCTAssertEqual(button.intrinsicContentSize.height, 32)
        let customImage = NSImage(size: NSSize(width: 30, height: 10))
        let menu = FluentMenuItem("Image", icon: .image(customImage), action: {})
        XCTAssertNotNil(menu.icon?.image(pointSize: 16))
        XCTAssertNil(menu.systemImageName)
    }

    @MainActor func testLongTextSelectionReplacementAndUndoKeepBindingSynchronized() async throws {
        let original = String(repeating: "abc文", count: 2000)
        let state = FluentState(wrappedValue: original)
        let bound = FluentBoundTextField(state.projectedValue)
        let window = window(bound, width: 400)
        defer { window.close() }
        window.orderFrontRegardless()
        bound.field.selectText(nil)
        let editor = try XCTUnwrap(bound.field.currentEditor() as? NSTextView)
        editor.allowsUndo = true
        editor.setSelectedRange(NSRange(location: 3, length: 5))
        editor.insertText("中文", replacementRange: editor.selectedRange())
        await drain()
        let expected = (original as NSString).replacingCharacters(in: NSRange(location: 3, length: 5), with: "中文")
        XCTAssertTrue(state.wrappedValue == expected, "selection replacement: expected \(expected.utf16.count) units, got \(state.wrappedValue.utf16.count); prefix \(state.wrappedValue.prefix(16))")
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        await drain()
        XCTAssertTrue(state.wrappedValue == original, "undo: expected \(original.utf16.count) units, got \(state.wrappedValue.utf16.count); editor \(editor.string.utf16.count), field \(bound.field.stringValue.utf16.count), redo \(undo.canRedo), groups \(undo.groupingLevel)")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        await drain()
        XCTAssertTrue(state.wrappedValue == expected)
        state.wrappedValue = ""
        await drain()
        XCTAssertEqual(editor.string, "")
    }

    @MainActor func testCollectionWaitsForViewportAndFitsNarrowScrolledWidth() async throws {
        _ = NSApplication.shared
        let counters = AuditCounters()
        let host = FluentViewHost(FluentListView(Array(0..<500)) { _ in AuditRow(counters: counters) })
        let collection = try XCTUnwrap(descendants(host).compactMap { $0 as? FluentSectionedCollectionView<Int, Int> }.first)
        XCTAssertEqual(collection.snapshotApplicationCount, 0)
        XCTAssertEqual(counters.makes, 0)
        let window = window(host, width: 300)
        defer { window.close() }
        await drain()
        host.layoutSubtreeIfNeeded()
        for width: CGFloat in [40, 160, 80] {
            window.setContentSize(NSSize(width: width, height: 600))
            host.layoutSubtreeIfNeeded()
            await drain()
            let native = try XCTUnwrap(descendants(host).compactMap { $0 as? NSCollectionView }.first)
            let flow = try XCTUnwrap(native.collectionViewLayout as? NSCollectionViewFlowLayout)
            XCTAssertLessThanOrEqual(flow.itemSize.width + flow.sectionInset.left + flow.sectionInset.right, native.bounds.width + 0.01)
        }
        XCTAssertEqual(collection.snapshotApplicationCount, 1)
    }

    @MainActor func testCollectionResizePreservesSingleColumnScrollPositionAndVirtualization() async throws {
        let counters = AuditCounters()
        let host = FluentViewHost(FluentListView(Array(0..<5000), rowHeight: 32) { _ in AuditRow(counters: counters) },
                                  context: .init(reduceMotion: true))
        let window = window(host, width: 300)
        defer { window.close() }
        let native = try XCTUnwrap(descendants(host).compactMap { $0 as? NSCollectionView }.first)
        let scroll = try XCTUnwrap(native.enclosingScrollView)
        let layout = try XCTUnwrap(native.collectionViewLayout as? NSCollectionViewFlowLayout)
        await drain()
        native.scrollToItems(at: [IndexPath(item: 4000, section: 0)], scrollPosition: .top)
        await drain()
        let initialOffset = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(initialOffset, 100_000)
        for style in [NSScroller.Style.legacy, .overlay] {
            scroll.scrollerStyle = style
            for width: CGFloat in [40, 1200, 80, 640, 300] {
                window.setContentSize(NSSize(width: width, height: 600))
                host.layoutSubtreeIfNeeded()
                await drain()
                XCTAssertEqual(native.bounds.width, scroll.contentView.bounds.width, accuracy: 0.01)
                XCTAssertEqual(scroll.contentView.bounds.minY, initialOffset, accuracy: 1)
                let first = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 4000, section: 0)))
                let next = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 4001, section: 0)))
                XCTAssertEqual(first.frame.minX, next.frame.minX, accuracy: 0.01)
                XCTAssertEqual(next.frame.minY - first.frame.minY, 32, accuracy: 0.01)
                XCTAssertEqual(layout.collectionViewContentSize.height, 5000 * 32 + 10, accuracy: 1)
                XCTAssertFalse(native.visibleItems().isEmpty)
                XCTAssertLessThan(native.visibleItems().count, 32)
                XCTAssertLessThan(counters.makes, 80, "A width change must not briefly realize a multi-column list")
                for item in native.visibleItems() {
                    for view in descendants(item.view) {
                        XCTAssertTrue(view.frame.width.isFinite && view.frame.height.isFinite)
                        XCTAssertGreaterThanOrEqual(view.frame.width, 0)
                        XCTAssertGreaterThanOrEqual(view.frame.height, 0)
                    }
                }
            }
        }
    }

    @MainActor func testGridResizeFitsRowsAndSectionHeadersInBothDirections() async throws {
        for direction in [FluentLayoutDirection.leftToRight, .rightToLeft] {
            let snapshot = FluentCollectionSnapshot(section: 0, items: Array(0..<500))
            let host = FluentViewHost(FluentCollection(snapshot: snapshot,
                layout: .adaptiveGrid(minimumItemWidth: 120, itemHeight: 60, spacing: 8),
                content: { FluentText("Item \($0)") },
                header: { _ in FluentText("A long section heading that must fit the current viewport") }),
                context: .init(reduceMotion: true, layoutDirection: direction))
            let window = window(host, width: 600)
            defer { window.close() }
            let native = try XCTUnwrap(descendants(host).compactMap { $0 as? NSCollectionView }.first)
            let scroll = try XCTUnwrap(native.enclosingScrollView)
            scroll.scrollerStyle = .legacy
            for width: CGFloat in [40, 1200, 180, 320] {
                window.setContentSize(NSSize(width: width, height: 600))
                host.layoutSubtreeIfNeeded()
                await drain()
                let headers = native.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader)
                XCTAssertFalse(headers.isEmpty)
                for header in headers {
                    for label in descendants(header).compactMap({ $0 as? NSTextField }) {
                        XCTAssertLessThanOrEqual(label.alignmentRect(forFrame: label.frame).width, max(0, header.bounds.width - 12) + 0.01)
                        XCTAssertGreaterThanOrEqual(label.frame.width, 0)
                    }
                }
                for item in native.visibleItems() {
                    XCTAssertGreaterThanOrEqual(item.view.frame.minX, -0.01)
                    XCTAssertLessThanOrEqual(item.view.frame.maxX, native.bounds.width + 0.01)
                }
                XCTAssertFalse(native.visibleItems().isEmpty)
                XCTAssertLessThan(native.visibleItems().count, 150)
            }
        }
    }

    @MainActor func testCollectionSurvivesCollapsingAndRestoringAWindowlessViewport() async throws {
        let host = FluentViewHost(FluentListView(Array(0..<1000)) { FluentText("Item \($0)") })
        let native = try XCTUnwrap(descendants(host).compactMap { $0 as? NSCollectionView }.first)
        for width: CGFloat in [300, 0, 0.5, 2, 160, 0, 600] {
            host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
            host.layoutSubtreeIfNeeded()
            await drain()
            if width > 4 {
                XCTAssertFalse(native.visibleItems().isEmpty)
                XCTAssertEqual(native.bounds.width, native.enclosingScrollView!.contentView.bounds.width, accuracy: 0.01)
            }
        }
        let layout = try XCTUnwrap(native.collectionViewLayout as? NSCollectionViewFlowLayout)
        XCTAssertEqual(layout.collectionViewContentSize.height, 40_010, accuracy: 1)
    }

    @MainActor func testFrameworkLocalizationFollowsHostAndAllowsBundleOverride() throws {
        _ = NSApplication.shared
        let child = FluentTextField()
        let host = FluentViewHost(FluentNativeView(child), context: .init(locale: Locale(identifier: "zh_CN")))
        XCTAssertEqual(child.fluentControlString("Copy"), "复制")
        host.context = .init(locale: Locale(identifier: "zh_TW"))
        XCTAssertEqual(child.fluentControlString("Copy"), "複製")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "\"FluentKit.Copy\" = \"Custom Copy\";".write(to: directory.appendingPathComponent("FluentKit.strings"), atomically: true, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle(path: directory.path))
        host.context = .init(locale: Locale(identifier: "en"), localizationBundle: bundle)
        XCTAssertEqual(child.fluentControlString("Copy"), "Custom Copy")
    }
}
