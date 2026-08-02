import AppKit

/// A two-column navigation container driven by stable item identities.
///
/// The sidebar uses a native, keyboard-navigable list while the detail column remains mounted
/// inside the same split view. Selection and sidebar visibility can be shared with application
/// state or `FluentRestoredState`, and removing the selected item clears stale selection.
public struct FluentNavigationSplitView<Item, ID: Hashable>: FluentUpdatablePrimitiveView {
    private let items: [Item]
    private let id: (Item) -> ID
    private let selection: FluentBinding<ID?>
    private let isSidebarVisible: FluentBinding<Bool>?
    private let minimumSidebarWidth: CGFloat
    private let idealSidebarWidth: CGFloat
    private let maximumSidebarWidth: CGFloat
    private let rowHeight: CGFloat
    private let sidebarRow: (Item) -> FluentAnyView
    private let detail: (Item) -> FluentAnyView
    private let placeholder: () -> FluentAnyView

    public init<SidebarRow: FluentView, Detail: FluentView, Placeholder: FluentView>(
        _ items: [Item],
        id: @escaping (Item) -> ID,
        selection: FluentBinding<ID?>,
        isSidebarVisible: FluentBinding<Bool>? = nil,
        sidebarWidth: ClosedRange<CGFloat> = 180...360,
        idealSidebarWidth: CGFloat = 240,
        rowHeight: CGFloat = 38,
        @FluentViewBuilder sidebarRow: @escaping (Item) -> SidebarRow,
        @FluentViewBuilder detail: @escaping (Item) -> Detail,
        @FluentViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        let minimumWidth = max(sidebarWidth.lowerBound, 0)
        let maximumWidth = max(sidebarWidth.upperBound, minimumWidth)
        self.items = items
        self.id = id
        self.selection = selection
        self.isSidebarVisible = isSidebarVisible
        minimumSidebarWidth = minimumWidth
        self.idealSidebarWidth = min(max(idealSidebarWidth, minimumWidth), maximumWidth)
        maximumSidebarWidth = maximumWidth
        self.rowHeight = max(rowHeight, 1)
        self.sidebarRow = { FluentAnyView(sidebarRow($0)) }
        self.detail = { FluentAnyView(detail($0)) }
        self.placeholder = { FluentAnyView(placeholder()) }
    }

    public init<SidebarRow: FluentView, Detail: FluentView, Placeholder: FluentView>(
        _ items: [Item],
        id: KeyPath<Item, ID>,
        selection: FluentBinding<ID?>,
        isSidebarVisible: FluentBinding<Bool>? = nil,
        sidebarWidth: ClosedRange<CGFloat> = 180...360,
        idealSidebarWidth: CGFloat = 240,
        rowHeight: CGFloat = 38,
        @FluentViewBuilder sidebarRow: @escaping (Item) -> SidebarRow,
        @FluentViewBuilder detail: @escaping (Item) -> Detail,
        @FluentViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            items,
            id: { $0[keyPath: id] },
            selection: selection,
            isSidebarVisible: isSidebarVisible,
            sidebarWidth: sidebarWidth,
            idealSidebarWidth: idealSidebarWidth,
            rowHeight: rowHeight,
            sidebarRow: sidebarRow,
            detail: detail,
            placeholder: placeholder
        )
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentNavigationSplitHost(
            items: items,
            id: id,
            selection: selection,
            isSidebarVisible: isSidebarVisible,
            minimumSidebarWidth: minimumSidebarWidth,
            idealSidebarWidth: idealSidebarWidth,
            maximumSidebarWidth: maximumSidebarWidth,
            rowHeight: rowHeight,
            sidebarRow: sidebarRow,
            detail: detail,
            placeholder: placeholder,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentNavigationSplitHost<Item, ID> else { return false }
        host.update(
            items: items,
            id: id,
            selection: selection,
            isSidebarVisible: isSidebarVisible,
            minimumSidebarWidth: minimumSidebarWidth,
            idealSidebarWidth: idealSidebarWidth,
            maximumSidebarWidth: maximumSidebarWidth,
            rowHeight: rowHeight,
            sidebarRow: sidebarRow,
            detail: detail,
            placeholder: placeholder,
            context: context
        )
        return true
    }
}

public extension FluentNavigationSplitView where Item: Identifiable, ID == Item.ID {
    init<SidebarRow: FluentView, Detail: FluentView, Placeholder: FluentView>(
        _ items: [Item],
        selection: FluentBinding<ID?>,
        isSidebarVisible: FluentBinding<Bool>? = nil,
        sidebarWidth: ClosedRange<CGFloat> = 180...360,
        idealSidebarWidth: CGFloat = 240,
        rowHeight: CGFloat = 38,
        @FluentViewBuilder sidebarRow: @escaping (Item) -> SidebarRow,
        @FluentViewBuilder detail: @escaping (Item) -> Detail,
        @FluentViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            items,
            id: { $0.id },
            selection: selection,
            isSidebarVisible: isSidebarVisible,
            sidebarWidth: sidebarWidth,
            idealSidebarWidth: idealSidebarWidth,
            rowHeight: rowHeight,
            sidebarRow: sidebarRow,
            detail: detail,
            placeholder: placeholder
        )
    }
}

private struct FluentNavigationSidebarRow<ID: Hashable>: FluentView {
    let id: ID
    let content: FluentAnyView

    var body: FluentAnyView { content }
}

private final class FluentNavigationSplitHost<Item, ID: Hashable>: NSView, NSSplitViewDelegate {
    private var items: [Item]
    private var id: (Item) -> ID
    private var selection: FluentBinding<ID?>
    private var isSidebarVisible: FluentBinding<Bool>?
    private var minimumSidebarWidth: CGFloat
    private var idealSidebarWidth: CGFloat
    private var maximumSidebarWidth: CGFloat
    private var rowHeight: CGFloat
    private var sidebarRow: (Item) -> FluentAnyView
    private var detail: (Item) -> FluentAnyView
    private var placeholder: () -> FluentAnyView
    private var context: FluentRenderContext

    private let splitView = NSSplitView()
    private let sidebarMaterial = FluentMaterialView(material: .liquidGlass)
    private let sidebarHost: FluentViewHost<FluentAnyView>
    private let detailHost: FluentViewHost<FluentAnyView>
    private var observedSelection: FluentBinding<ID?>?
    private var selectionObserverID: UUID?
    private var observedSidebarVisibility: FluentBinding<Bool>?
    private var visibilityObserverID: UUID?
    private var didApplyInitialSidebarWidth = false
    private var lastVisibleSidebarWidth: CGFloat
    private var isSanitizingSelection = false

    init(
        items: [Item],
        id: @escaping (Item) -> ID,
        selection: FluentBinding<ID?>,
        isSidebarVisible: FluentBinding<Bool>?,
        minimumSidebarWidth: CGFloat,
        idealSidebarWidth: CGFloat,
        maximumSidebarWidth: CGFloat,
        rowHeight: CGFloat,
        sidebarRow: @escaping (Item) -> FluentAnyView,
        detail: @escaping (Item) -> FluentAnyView,
        placeholder: @escaping () -> FluentAnyView,
        context: FluentRenderContext
    ) {
        self.items = items
        self.id = id
        self.selection = selection
        self.isSidebarVisible = isSidebarVisible
        self.minimumSidebarWidth = minimumSidebarWidth
        self.idealSidebarWidth = idealSidebarWidth
        self.maximumSidebarWidth = maximumSidebarWidth
        self.rowHeight = rowHeight
        self.sidebarRow = sidebarRow
        self.detail = detail
        self.placeholder = placeholder
        self.context = context
        lastVisibleSidebarWidth = idealSidebarWidth

        let rows = items.map { FluentNavigationSidebarRow(id: id($0), content: sidebarRow($0)) }
        let sidebar = FluentList(
            rows: rows,
            id: { $0.id },
            spacing: 2,
            rowHeight: rowHeight,
            selectionID: selection
        ).padding(NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6))
        sidebarHost = FluentViewHost(FluentAnyView(sidebar), context: context)

        let selected = Self.resolveSelection(items: items, id: id, selectedID: selection.get())
        detailHost = FluentViewHost(selected.map(detail) ?? placeholder(), context: context)
        super.init(frame: .zero)

        setAccessibilityRole(.group)
        setAccessibilityLabel("Navigation split view")
        sidebarMaterial.setAccessibilityRole(.group)
        sidebarMaterial.setAccessibilityLabel("Navigation sidebar")
        sidebarMaterial.materialStyle = context.theme.material(for: .navigation) ?? .liquidGlass
        sidebarMaterial.fluentTheme = context.theme
        sidebarMaterial.isMaterialEnabled = context.theme.materialEffectsEnabled
        sidebarMaterial.fallbackColor = context.theme.layerFill
        detailHost.setAccessibilityRole(.group)
        detailHost.setAccessibilityLabel("Navigation detail")

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        sidebarMaterial.blendingMode = .withinWindow
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false
        sidebarMaterial.addSubview(sidebarHost)
        NSLayoutConstraint.activate([
            sidebarHost.leadingAnchor.constraint(equalTo: sidebarMaterial.leadingAnchor),
            sidebarHost.trailingAnchor.constraint(equalTo: sidebarMaterial.trailingAnchor),
            sidebarHost.topAnchor.constraint(equalTo: sidebarMaterial.topAnchor),
            sidebarHost.bottomAnchor.constraint(equalTo: sidebarMaterial.bottomAnchor)
        ])
        splitView.addArrangedSubview(sidebarMaterial)
        splitView.addArrangedSubview(detailHost)
        detailHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        installObservers()
        sanitizeSelectionIfNeeded()
        applySidebarVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        splitView.layoutSubtreeIfNeeded()
        splitView.adjustSubviews()
        guard isSidebarVisible?.get() ?? true else {
            splitView.setPosition(0, ofDividerAt: 0)
            return
        }
        if !didApplyInitialSidebarWidth {
            didApplyInitialSidebarWidth = true
            splitView.setPosition(clampedSidebarWidth(lastVisibleSidebarWidth), ofDividerAt: 0)
        }
    }

    func update(
        items: [Item],
        id: @escaping (Item) -> ID,
        selection: FluentBinding<ID?>,
        isSidebarVisible: FluentBinding<Bool>?,
        minimumSidebarWidth: CGFloat,
        idealSidebarWidth: CGFloat,
        maximumSidebarWidth: CGFloat,
        rowHeight: CGFloat,
        sidebarRow: @escaping (Item) -> FluentAnyView,
        detail: @escaping (Item) -> FluentAnyView,
        placeholder: @escaping () -> FluentAnyView,
        context: FluentRenderContext
    ) {
        removeObservers()
        self.items = items
        self.id = id
        self.selection = selection
        self.isSidebarVisible = isSidebarVisible
        self.minimumSidebarWidth = minimumSidebarWidth
        self.idealSidebarWidth = idealSidebarWidth
        self.maximumSidebarWidth = maximumSidebarWidth
        self.rowHeight = rowHeight
        self.sidebarRow = sidebarRow
        self.detail = detail
        self.placeholder = placeholder
        self.context = context
        lastVisibleSidebarWidth = clampedSidebarWidth(lastVisibleSidebarWidth)
        sidebarMaterial.materialStyle = context.theme.material(for: .navigation) ?? .liquidGlass
        sidebarMaterial.fluentTheme = context.theme
        sidebarMaterial.isMaterialEnabled = context.theme.materialEffectsEnabled
        sidebarMaterial.fallbackColor = context.theme.layerFill

        sanitizeSelectionIfNeeded()
        sidebarHost.context = context
        sidebarHost.update(makeSidebar())
        detailHost.context = context
        updateDetail()
        installObservers()
        applySidebarVisibility()
        if isSidebarVisible?.get() ?? true, didApplyInitialSidebarWidth {
            splitView.setPosition(clampedSidebarWidth(sidebarMaterial.frame.width), ofDividerAt: 0)
        }
    }

    private func makeSidebar() -> FluentAnyView {
        let rows = items.map { FluentNavigationSidebarRow(id: id($0), content: sidebarRow($0)) }
        return FluentAnyView(
            FluentList(
                rows: rows,
                id: { $0.id },
                spacing: 2,
                rowHeight: rowHeight,
                selectionID: selection
            ).padding(NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6))
        )
    }

    private func updateDetail() {
        let selected = Self.resolveSelection(items: items, id: id, selectedID: selection.get())
        detailHost.update(selected.map(detail) ?? placeholder())
    }

    private func sanitizeSelectionIfNeeded() {
        guard !isSanitizingSelection, selection.get() != nil else { return }
        guard Self.resolveSelection(items: items, id: id, selectedID: selection.get()) == nil else { return }
        isSanitizingSelection = true
        selection.set(nil)
        isSanitizingSelection = false
    }

    private static func resolveSelection(
        items: [Item],
        id: (Item) -> ID,
        selectedID: ID?
    ) -> Item? {
        guard let selectedID else { return nil }
        let matches = items.filter { id($0) == selectedID }
        return matches.count == 1 ? matches[0] : nil
    }

    private func installObservers() {
        observedSelection = selection
        selectionObserverID = selection.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sanitizeSelectionIfNeeded()
                self.updateDetail()
            }
        }
        observedSidebarVisibility = isSidebarVisible
        visibilityObserverID = isSidebarVisible?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applySidebarVisibility() }
        }
    }

    private func removeObservers() {
        if let selectionObserverID { observedSelection?.removeObserver(selectionObserverID) }
        if let visibilityObserverID { observedSidebarVisibility?.removeObserver(visibilityObserverID) }
        self.selectionObserverID = nil
        visibilityObserverID = nil
    }

    private func applySidebarVisibility() {
        let visible = isSidebarVisible?.get() ?? true
        if !visible, sidebarMaterial.frame.width > 0 {
            lastVisibleSidebarWidth = clampedSidebarWidth(sidebarMaterial.frame.width)
        }
        if !visible { setSidebarRenderingSuspended(true) }
        sidebarHost.isHidden = !visible
        if visible {
            needsLayout = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isSidebarVisible?.get() ?? true else { return }
                self.splitView.setPosition(self.clampedSidebarWidth(self.lastVisibleSidebarWidth), ofDividerAt: 0)
                self.splitView.layoutSubtreeIfNeeded()
                self.setSidebarRenderingSuspended(false)
                self.sidebarHost.layoutSubtreeIfNeeded()
            }
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
        }
    }

    private func setSidebarRenderingSuspended(_ suspended: Bool) {
        func visit(_ view: NSView) {
            (view as? FluentListRenderingSuspending)?.setListRenderingSuspended(suspended)
            view.subviews.forEach(visit)
        }
        visit(sidebarHost)
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumSidebarWidth), maximumSidebarWidth)
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex == 0 else { return proposedPosition }
        guard isSidebarVisible?.get() ?? true else { return 0 }
        return proposedPosition < minimumSidebarWidth / 2 ? 0 : clampedSidebarWidth(proposedPosition)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === sidebarMaterial
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        let width = sidebarMaterial.frame.width
        if width > 0 {
            lastVisibleSidebarWidth = clampedSidebarWidth(width)
        } else if splitView.bounds.width > minimumSidebarWidth, isSidebarVisible?.get() == true {
            isSidebarVisible?.set(false)
        }
    }

    deinit { removeObservers() }
}
