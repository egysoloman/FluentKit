import AppKit

/// A button that presents FluentKit content in an NSPopover.
/// The popover is configured with macOS presentation semantics while its content is rendered by
/// FluentViewHost, so applications can use the same declarative view values in overlays.
public final class FluentPopoverButton<Content: FluentView>: NSButton {
    public var theme: FluentTheme = .current { didSet { needsDisplay = true } }
    public var content: Content {
        didSet { popover?.contentViewController = makeViewController() }
    }

    private var popover: NSPopover?
    private let contentSize: NSSize

    public init(title: String = "More", contentSize: NSSize = NSSize(width: 280, height: 180), @FluentViewBuilder content: () -> Content) {
        self.content = content()
        self.contentSize = contentSize
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(ofSize: 13)
        focusRingType = .none
        target = self
        action = #selector(togglePopover)
        setAccessibilityRole(.button)
        setAccessibilityTitle(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: font as Any])
        let padding = theme.controlPadding
        return NSSize(width: text.width + padding.left + padding.right, height: theme.controlHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: theme.buttonCornerRadius, yRadius: theme.buttonCornerRadius)
        theme.controlFill.setFill(); path.fill()
        theme.controlStroke.setStroke(); path.lineWidth = 1; path.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: font as Any, .foregroundColor: theme.textPrimary]
        let text = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(in: NSRect(x: bounds.midX - text.width / 2, y: bounds.midY - text.height / 2 + 1, width: text.width, height: text.height), withAttributes: attrs)
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = contentSize
        popover.contentViewController = makeViewController()
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = popover
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            popover?.performClose(nil)
        } else if event.keyCode == 36 || event.keyCode == 49 {
            togglePopover()
        } else {
            super.keyDown(with: event)
        }
    }

    func applyDeclarativeConfiguration(from source: FluentPopoverButton<Content>) {
        title = source.title
        font = source.font
        content = source.content
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    private func makeViewController() -> NSViewController {
        let host = FluentViewHost(content, context: FluentRenderContext(theme: theme))
        let material = FluentMaterialView(material: .acrylic)
        material.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 16),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -16),
            host.topAnchor.constraint(equalTo: material.topAnchor, constant: 16),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -16)
        ])
        let controller = NSViewController()
        controller.view = material
        return controller
    }
}

/// A declarative sheet presenter. The wrapped content remains mounted while the sheet is shown,
/// and changing the binding presents or dismisses the native sheet window.
public struct FluentSheet<Content: FluentView, SheetContent: FluentView>: FluentUpdatablePrimitiveView {
    private let content: Content
    private let sheetContent: SheetContent
    private let isPresented: FluentBinding<Bool>
    private let title: String
    private let size: NSSize
    private let onDismiss: () -> Void

    public init(
        isPresented: FluentBinding<Bool>,
        title: String = "",
        size: NSSize = NSSize(width: 520, height: 360),
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder content: () -> Content,
        @FluentViewBuilder sheet: () -> SheetContent
    ) {
        self.content = content()
        self.sheetContent = sheet()
        self.isPresented = isPresented
        self.title = title
        self.size = NSSize(width: max(size.width, 240), height: max(size.height, 180))
        self.onDismiss = onDismiss
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentSheetHost(
            content: content._mount(in: context),
            sheetContent: sheetContent,
            binding: isPresented,
            title: title,
            size: size,
            onDismiss: onDismiss,
            context: context
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentSheetHost<SheetContent> else { return false }
        host.update(binding: isPresented, sheetContent: sheetContent, title: title, size: size, onDismiss: onDismiss, context: context)
        host.updateContent(
            using: { nativeView, updateContext in content._update(nativeView, in: updateContext) },
            make: { content._mount(in: context) }
        )
        return true
    }
}

private final class FluentSheetHost<SheetContent: FluentView>: NSView {
    private var sheetContent: SheetContent
    private var updateContent: (NSView, FluentRenderContext) -> Bool
    private var binding: FluentBinding<Bool>
    private var title: String
    private var size: NSSize
    private var onDismiss: () -> Void
    private var context: FluentRenderContext
    private weak var sheetWindow: NSWindow?
    private var sheetController: NSWindowController?
    private var observerID: UUID?
    private var updatePresentedContent: ((SheetContent, FluentRenderContext) -> Void)?

    init(content: NSView, sheetContent: SheetContent, binding: FluentBinding<Bool>, title: String, size: NSSize, onDismiss: @escaping () -> Void, context: FluentRenderContext) {
        self.sheetContent = sheetContent
        self.updateContent = { _, _ in false }
        self.binding = binding
        self.title = title
        self.size = size
        self.onDismiss = onDismiss
        self.context = context
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        installBindingObserver()
        DispatchQueue.main.async { [weak self] in self?.syncPresentation() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.syncPresentation() }
    }

    func update(binding: FluentBinding<Bool>, sheetContent: SheetContent, title: String, size: NSSize, onDismiss: @escaping () -> Void, context: FluentRenderContext) {
        if let observerID { self.binding.removeObserver?(observerID) }
        self.binding = binding
        self.sheetContent = sheetContent
        self.title = title
        self.size = size
        self.onDismiss = onDismiss
        self.context = context
        installBindingObserver()
        updatePresentedContent?(sheetContent, context)
        syncPresentation()
    }

    func updateContent(using update: @escaping (NSView, FluentRenderContext) -> Bool, make: @escaping () -> NSView) {
        self.updateContent = update
        guard let current = subviews.first else { return }
        if !update(current, context) {
            current.removeFromSuperview()
            let replacement = make()
            addSubview(replacement)
            replacement.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                replacement.leadingAnchor.constraint(equalTo: leadingAnchor),
                replacement.trailingAnchor.constraint(equalTo: trailingAnchor),
                replacement.topAnchor.constraint(equalTo: topAnchor),
                replacement.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    private func installBindingObserver() {
        observerID = binding.observe? { [weak self] _ in
            DispatchQueue.main.async { self?.syncPresentation() }
        }
    }

    private func syncPresentation() {
        guard let parentWindow = window else { return }
        if binding.get() {
            guard sheetWindow == nil else { return }
            let controller = FluentSheetWindowController(content: sheetContent, title: title, size: size, context: context)
            sheetController = controller
            sheetWindow = controller.window
            updatePresentedContent = { [weak controller] content, context in
                controller?.update(content: content, context: context)
            }
            parentWindow.beginSheet(controller.window!) { [weak self] _ in
                self?.sheetWindow = nil
                self?.sheetController = nil
                self?.updatePresentedContent = nil
                if self?.binding.get() == true { self?.binding.set(false) }
                self?.onDismiss()
            }
        } else if let sheetWindow {
            parentWindow.endSheet(sheetWindow, returnCode: .cancel)
            self.sheetWindow = nil
            sheetController = nil
            updatePresentedContent = nil
        }
    }

    deinit {
        if let observerID { binding.removeObserver?(observerID) }
    }
}

private final class FluentSheetWindowController<Content: FluentView>: NSWindowController {
    private let host: FluentViewHost<Content>

    init(content: Content, title: String, size: NSSize, context: FluentRenderContext) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        let material = FluentMaterialView(material: .mica)
        host = FluentViewHost(content, context: context)
        material.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 28),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -28),
            host.topAnchor.constraint(equalTo: material.topAnchor, constant: 24),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -24)
        ])
        window.contentView = material
        super.init(window: window)
    }

    func update(content: Content, context: FluentRenderContext) {
        host.context = context
        host.update(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

public extension FluentView {
    /// Presents custom Fluent content as a native document-modal sheet.
    func sheet<SheetContent: FluentView>(
        isPresented: FluentBinding<Bool>,
        title: String = "",
        size: NSSize = NSSize(width: 520, height: 360),
        onDismiss: @escaping () -> Void = {},
        @FluentViewBuilder sheet: @escaping () -> SheetContent
    ) -> FluentSheet<Self, SheetContent> {
        FluentSheet(
            isPresented: isPresented,
            title: title,
            size: size,
            onDismiss: onDismiss,
            content: { self },
            sheet: sheet
        )
    }
}

/// Presents a Fluent-styled alert window and writes the selected response into the binding.
public struct FluentAlert: FluentPrimitiveView {
    private let title: String
    private let message: String
    private let buttons: [String]
    private let selection: FluentBinding<Int>?

    public init(title: String, message: String, buttons: [String] = ["OK"], selection: FluentBinding<Int>? = nil) {
        self.title = title
        self.message = message
        self.buttons = buttons.isEmpty ? ["OK"] : buttons
        self.selection = selection
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let placeholder = NSView()
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            buttons.forEach { alert.addButton(withTitle: $0) }
            alert.beginSheetModal(for: window) { response in
                let index = max(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue, 0)
                selection?.set(index)
            }
        }
        return placeholder
    }
}
