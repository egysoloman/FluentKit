import AppKit

/// A trailing inspector pane backed by a native NSSplitView.
///
/// The inspector keeps its native host mounted while content, width constraints, and visibility
/// change. Pass a binding when the pane should be controlled by application state; without one,
/// the pane remains visible.
public struct FluentInspector<Content: FluentView, InspectorContent: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let inspector: InspectorContent
    private let isPresented: FluentBinding<Bool>?
    private let minimumWidth: CGFloat
    private let idealWidth: CGFloat
    private let maximumWidth: CGFloat

    public init(
        isPresented: FluentBinding<Bool>? = nil,
        width: ClosedRange<CGFloat> = 240...420,
        idealWidth: CGFloat = 300,
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder inspector: () -> InspectorContent
    ) {
        let minimum = max(width.lowerBound, 0)
        let maximum = max(width.upperBound, minimum)
        self.content = content()
        self.inspector = inspector()
        self.isPresented = isPresented
        minimumWidth = minimum
        self.idealWidth = min(max(idealWidth, minimum), maximum)
        self.maximumWidth = maximum
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentInspectorHost(
            content: FluentAnyView(content),
            inspector: FluentAnyView(inspector),
            isPresented: isPresented,
            minimumWidth: minimumWidth,
            idealWidth: idealWidth,
            maximumWidth: maximumWidth,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentInspectorHost else { return false }
        host.update(
            content: FluentAnyView(content),
            inspector: FluentAnyView(inspector),
            isPresented: isPresented,
            minimumWidth: minimumWidth,
            idealWidth: idealWidth,
            maximumWidth: maximumWidth,
            context: context
        )
        return true
    }
}

private final class FluentInspectorHost: NSView, NSSplitViewDelegate {
    private var content: FluentAnyView
    private var inspector: FluentAnyView
    private var isPresented: FluentBinding<Bool>?
    private var minimumWidth: CGFloat
    private var idealWidth: CGFloat
    private var maximumWidth: CGFloat
    private var context: FluentRenderContext

    private let splitView = NSSplitView()
    private let contentHost: FluentViewHost<FluentAnyView>
    private let inspectorMaterial = FluentMaterialView(material: .sidebar)
    private let inspectorHost: FluentViewHost<FluentAnyView>
    private var observedPresentation: FluentBinding<Bool>?
    private var presentationObserverID: UUID?
    private var didApplyInitialWidth = false
    private var lastVisibleWidth: CGFloat

    init(
        content: FluentAnyView,
        inspector: FluentAnyView,
        isPresented: FluentBinding<Bool>?,
        minimumWidth: CGFloat,
        idealWidth: CGFloat,
        maximumWidth: CGFloat,
        context: FluentRenderContext
    ) {
        self.content = content
        self.inspector = inspector
        self.isPresented = isPresented
        self.minimumWidth = minimumWidth
        self.idealWidth = idealWidth
        self.maximumWidth = maximumWidth
        self.context = context
        lastVisibleWidth = idealWidth
        contentHost = FluentViewHost(content, context: context)
        inspectorHost = FluentViewHost(inspector, context: context)
        super.init(frame: .zero)

        setAccessibilityRole(.group)
        setAccessibilityLabel("Content with inspector")
        inspectorMaterial.blendingMode = .withinWindow
        inspectorMaterial.setAccessibilityRole(.group)
        inspectorMaterial.setAccessibilityLabel("Inspector")
        inspectorHost.translatesAutoresizingMaskIntoConstraints = false
        inspectorMaterial.addSubview(inspectorHost)
        NSLayoutConstraint.activate([
            inspectorHost.leadingAnchor.constraint(equalTo: inspectorMaterial.leadingAnchor, constant: 16),
            inspectorHost.trailingAnchor.constraint(equalTo: inspectorMaterial.trailingAnchor, constant: -16),
            inspectorHost.topAnchor.constraint(equalTo: inspectorMaterial.topAnchor, constant: 16),
            inspectorHost.bottomAnchor.constraint(equalTo: inspectorMaterial.bottomAnchor, constant: -16)
        ])

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
        contentHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inspectorMaterial.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        inspectorMaterial.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        splitView.addArrangedSubview(contentHost)
        splitView.addArrangedSubview(inspectorMaterial)

        installObserver()
        applyVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard splitView.bounds.width > 0 else { return }
        splitView.layoutSubtreeIfNeeded()
        splitView.adjustSubviews()
        guard didApplyInitialWidth else {
            didApplyInitialWidth = true
            applyVisibility()
            return
        }
        if isPresented?.get() ?? true {
            splitView.setPosition(splitPosition(for: lastVisibleWidth), ofDividerAt: 0)
        } else {
            splitView.setPosition(splitView.bounds.width, ofDividerAt: 0)
        }
    }

    func update(
        content: FluentAnyView,
        inspector: FluentAnyView,
        isPresented: FluentBinding<Bool>?,
        minimumWidth: CGFloat,
        idealWidth: CGFloat,
        maximumWidth: CGFloat,
        context: FluentRenderContext
    ) {
        removeObserver()
        self.content = content
        self.inspector = inspector
        self.isPresented = isPresented
        self.minimumWidth = minimumWidth
        self.idealWidth = idealWidth
        self.maximumWidth = maximumWidth
        self.context = context
        lastVisibleWidth = clampedWidth(lastVisibleWidth)
        contentHost.context = context
        contentHost.update(content)
        inspectorHost.context = context
        inspectorHost.update(inspector)
        inspectorMaterial.materialStyle = .sidebar
        installObserver()
        applyVisibility()
    }

    private func installObserver() {
        observedPresentation = isPresented
        presentationObserverID = isPresented?.observe { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.applyVisibility() }
        }
    }

    private func removeObserver() {
        if let presentationObserverID { observedPresentation?.removeObserver(presentationObserverID) }
        presentationObserverID = nil
        observedPresentation = nil
    }

    private func applyVisibility() {
        let visible = isPresented?.get() ?? true
        if visible {
            inspectorHost.isHidden = false
            inspectorMaterial.isHidden = false
            needsLayout = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPresented?.get() ?? true else { return }
                self.splitView.layoutSubtreeIfNeeded()
                self.splitView.setPosition(self.splitPosition(for: self.lastVisibleWidth), ofDividerAt: 0)
            }
        } else {
            if inspectorMaterial.frame.width > 0 { lastVisibleWidth = clampedWidth(inspectorMaterial.frame.width) }
            inspectorHost.isHidden = true
            splitView.setPosition(splitView.bounds.width, ofDividerAt: 0)
        }
    }

    private func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }

    private func splitPosition(for width: CGFloat) -> CGFloat {
        max(0, splitView.bounds.width - clampedWidth(width))
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex == 0 else { return proposedPosition }
        guard isPresented?.get() ?? true else { return splitView.bounds.width }
        let maximumPosition = max(0, splitView.bounds.width - minimumWidth)
        let minimumPosition = max(0, splitView.bounds.width - maximumWidth)
        return min(max(proposedPosition, minimumPosition), maximumPosition)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        subview === inspectorMaterial
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard isPresented?.get() ?? true else { return }
        let width = inspectorMaterial.frame.width
        if width > 0 { lastVisibleWidth = clampedWidth(width) }
    }

    deinit { removeObserver() }
}
