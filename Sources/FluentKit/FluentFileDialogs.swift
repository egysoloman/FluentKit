import AppKit
import UniformTypeIdentifiers

public enum FluentFileDialogError: Error, Equatable {
    case cancelled
    case missingSelection
}

/// Configuration for a native `NSOpenPanel` presented by `fileImporter`.
public struct FluentFileImportConfiguration: Sendable {
    public var allowedContentTypes: [UTType]
    public var allowsMultipleSelection: Bool
    public var canChooseDirectories: Bool
    public var prompt: String?
    public var message: String?

    public init(
        allowedContentTypes: [UTType] = [],
        allowsMultipleSelection: Bool = false,
        canChooseDirectories: Bool = false,
        prompt: String? = nil,
        message: String? = nil
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.canChooseDirectories = canChooseDirectories
        self.prompt = prompt
        self.message = message
    }
}

/// Configuration for a native `NSSavePanel` presented by `fileExporter`.
public struct FluentFileExportConfiguration: Sendable {
    public var contentType: UTType?
    public var defaultFilename: String
    public var canCreateDirectories: Bool
    public var prompt: String?
    public var message: String?

    public init(
        contentType: UTType? = nil,
        defaultFilename: String = "",
        canCreateDirectories: Bool = true,
        prompt: String? = nil,
        message: String? = nil
    ) {
        self.contentType = contentType
        self.defaultFilename = defaultFilename
        self.canCreateDirectories = canCreateDirectories
        self.prompt = prompt
        self.message = message
    }
}

/// Native panel construction shared by declarative modifiers and AppKit integrations.
public enum FluentFileDialogFactory {
    public static func makeImportPanel(
        configuration: FluentFileImportConfiguration
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = configuration.allowedContentTypes
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.prompt = configuration.prompt
        panel.message = configuration.message
        return panel
    }

    public static func makeExportPanel(
        configuration: FluentFileExportConfiguration
    ) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = configuration.contentType.map { [$0] } ?? []
        panel.nameFieldStringValue = configuration.defaultFilename
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.prompt = configuration.prompt
        panel.message = configuration.message
        return panel
    }
}

/// A cancellable file-panel presentation. Cancellation must finish the pending presentation once.
public protocol FluentFileDialogSession: AnyObject {
    func cancel()
}

/// Presentation boundary used by declarative file-dialog modifiers.
public protocol FluentFileDialogPresenting: AnyObject {
    @discardableResult
    func presentImport(
        configuration: FluentFileImportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) -> any FluentFileDialogSession

    @discardableResult
    func presentExport(
        configuration: FluentFileExportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> any FluentFileDialogSession
}

/// The production presenter backed by `NSOpenPanel` and `NSSavePanel` sheets.
public final class FluentNativeFileDialogPresenter: FluentFileDialogPresenting {
    public static let shared = FluentNativeFileDialogPresenter()

    public init() {}

    @discardableResult
    public func presentImport(
        configuration: FluentFileImportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) -> any FluentFileDialogSession {
        let session = FluentNativeImportSession(
            configuration: configuration,
            window: window,
            completion: completion
        )
        session.present()
        return session
    }

    @discardableResult
    public func presentExport(
        configuration: FluentFileExportConfiguration,
        for window: NSWindow,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> any FluentFileDialogSession {
        let session = FluentNativeExportSession(
            configuration: configuration,
            window: window,
            completion: completion
        )
        session.present()
        return session
    }
}

private final class FluentNativeImportSession: FluentFileDialogSession {
    private let configuration: FluentFileImportConfiguration
    private weak var window: NSWindow?
    private var completion: ((Result<[URL], Error>) -> Void)?
    private var panel: NSOpenPanel?

    init(
        configuration: FluentFileImportConfiguration,
        window: NSWindow,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        self.configuration = configuration
        self.window = window
        self.completion = completion
    }

    func present() {
        guard let window else {
            finish(.failure(FluentFileDialogError.cancelled))
            return
        }
        let panel = FluentFileDialogFactory.makeImportPanel(configuration: configuration)
        self.panel = panel
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self else { return }
            if response == .OK, let panel {
                self.finish(.success(panel.urls))
            } else {
                self.finish(.failure(FluentFileDialogError.cancelled))
            }
        }
    }

    func cancel() {
        guard let panel, let window else {
            finish(.failure(FluentFileDialogError.cancelled))
            return
        }
        window.endSheet(panel, returnCode: .cancel)
    }

    private func finish(_ result: Result<[URL], Error>) {
        guard let completion else { return }
        self.completion = nil
        panel = nil
        completion(result)
    }
}

private final class FluentNativeExportSession: FluentFileDialogSession {
    private let configuration: FluentFileExportConfiguration
    private weak var window: NSWindow?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var panel: NSSavePanel?

    init(
        configuration: FluentFileExportConfiguration,
        window: NSWindow,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.configuration = configuration
        self.window = window
        self.completion = completion
    }

    func present() {
        guard let window else {
            finish(.failure(FluentFileDialogError.cancelled))
            return
        }
        let panel = FluentFileDialogFactory.makeExportPanel(configuration: configuration)
        self.panel = panel
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard let self else { return }
            if response == .OK, let url = panel?.url {
                self.finish(.success(url))
            } else if response == .OK {
                self.finish(.failure(FluentFileDialogError.missingSelection))
            } else {
                self.finish(.failure(FluentFileDialogError.cancelled))
            }
        }
    }

    func cancel() {
        guard let panel, let window else {
            finish(.failure(FluentFileDialogError.cancelled))
            return
        }
        window.endSheet(panel, returnCode: .cancel)
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let completion else { return }
        self.completion = nil
        panel = nil
        completion(result)
    }
}

public struct FluentFileImporterView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let isPresented: FluentBinding<Bool>
    fileprivate let configuration: FluentFileImportConfiguration
    fileprivate let presenter: any FluentFileDialogPresenting
    fileprivate let completion: (Result<[URL], Error>) -> Void

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFileImporterHost(
            content: content._mount(in: context),
            isPresented: isPresented,
            configuration: configuration,
            presenter: presenter,
            completion: completion
        )
        host.updateContent = { [content] native, updateContext in
            content._update(native, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFileImporterHost else { return false }
        host.update(
            isPresented: isPresented,
            configuration: configuration,
            presenter: presenter,
            completion: completion
        )
        return host.updateContent?(host.contentView, context) ?? false
    }
}

public struct FluentFileExporterView<Content: FluentView>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let isPresented: FluentBinding<Bool>
    fileprivate let configuration: FluentFileExportConfiguration
    fileprivate let presenter: any FluentFileDialogPresenting
    fileprivate let completion: (Result<URL, Error>) -> Void

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let host = FluentFileExporterHost(
            content: content._mount(in: context),
            isPresented: isPresented,
            configuration: configuration,
            presenter: presenter,
            completion: completion
        )
        host.updateContent = { [content] native, updateContext in
            content._update(native, in: updateContext)
        }
        return host
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentFileExporterHost else { return false }
        host.update(
            isPresented: isPresented,
            configuration: configuration,
            presenter: presenter,
            completion: completion
        )
        return host.updateContent?(host.contentView, context) ?? false
    }
}

public extension FluentView {
    func fileImporter(
        isPresented: FluentBinding<Bool>,
        configuration: FluentFileImportConfiguration = .init(),
        presenter: any FluentFileDialogPresenting = FluentNativeFileDialogPresenter.shared,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> FluentFileImporterView<Self> {
        FluentFileImporterView(
            content: self,
            isPresented: isPresented,
            configuration: configuration,
            presenter: presenter,
            completion: onCompletion
        )
    }

    func fileExporter(
        isPresented: FluentBinding<Bool>,
        configuration: FluentFileExportConfiguration = .init(),
        presenter: any FluentFileDialogPresenting = FluentNativeFileDialogPresenter.shared,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> FluentFileExporterView<Self> {
        FluentFileExporterView(
            content: self,
            isPresented: isPresented,
            configuration: configuration,
            presenter: presenter,
            completion: onCompletion
        )
    }
}

private final class FluentFileImporterHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    private var isPresented: FluentBinding<Bool>
    private var configuration: FluentFileImportConfiguration
    private var presenter: any FluentFileDialogPresenting
    private var completion: (Result<[URL], Error>) -> Void
    private var observerID: UUID?
    private var session: (any FluentFileDialogSession)?
    private var isProgrammaticDismissal = false

    init(
        content: NSView,
        isPresented: FluentBinding<Bool>,
        configuration: FluentFileImportConfiguration,
        presenter: any FluentFileDialogPresenting,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.configuration = configuration
        self.presenter = presenter
        self.completion = completion
        super.init(frame: .zero)
        install(content: content)
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    func update(
        isPresented: FluentBinding<Bool>,
        configuration: FluentFileImportConfiguration,
        presenter: any FluentFileDialogPresenting,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        removeObserver()
        self.isPresented = isPresented
        self.configuration = configuration
        self.presenter = presenter
        self.completion = completion
        installObserver()
        synchronizePresentation()
    }

    private func install(content: NSView) {
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func installObserver() {
        observerID = isPresented.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func removeObserver() {
        if let observerID { isPresented.removeObserver?(observerID) }
        observerID = nil
    }

    private func synchronizePresentation() {
        guard let window else { return }
        if isPresented.get() {
            guard session == nil else { return }
            session = presenter.presentImport(configuration: configuration, for: window) { [weak self] result in
                guard let self else { return }
                let wasProgrammatic = self.isProgrammaticDismissal
                self.isProgrammaticDismissal = false
                self.session = nil
                if self.isPresented.get() { self.isPresented.set(false) }
                guard !wasProgrammatic else { return }
                self.completion(result)
            }
        } else if let session {
            isProgrammaticDismissal = true
            session.cancel()
        }
    }

    deinit { removeObserver() }
}

private final class FluentFileExporterHost: NSView {
    var updateContent: ((NSView, FluentRenderContext) -> Bool)?
    var contentView: NSView { subviews[0] }

    private var isPresented: FluentBinding<Bool>
    private var configuration: FluentFileExportConfiguration
    private var presenter: any FluentFileDialogPresenting
    private var completion: (Result<URL, Error>) -> Void
    private var observerID: UUID?
    private var session: (any FluentFileDialogSession)?
    private var isProgrammaticDismissal = false

    init(
        content: NSView,
        isPresented: FluentBinding<Bool>,
        configuration: FluentFileExportConfiguration,
        presenter: any FluentFileDialogPresenting,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.configuration = configuration
        self.presenter = presenter
        self.completion = completion
        super.init(frame: .zero)
        install(content: content)
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
    }

    func update(
        isPresented: FluentBinding<Bool>,
        configuration: FluentFileExportConfiguration,
        presenter: any FluentFileDialogPresenting,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        removeObserver()
        self.isPresented = isPresented
        self.configuration = configuration
        self.presenter = presenter
        self.completion = completion
        installObserver()
        synchronizePresentation()
    }

    private func install(content: NSView) {
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func installObserver() {
        observerID = isPresented.observe? { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.synchronizePresentation() }
        }
    }

    private func removeObserver() {
        if let observerID { isPresented.removeObserver?(observerID) }
        observerID = nil
    }

    private func synchronizePresentation() {
        guard let window else { return }
        if isPresented.get() {
            guard session == nil else { return }
            session = presenter.presentExport(configuration: configuration, for: window) { [weak self] result in
                guard let self else { return }
                let wasProgrammatic = self.isProgrammaticDismissal
                self.isProgrammaticDismissal = false
                self.session = nil
                if self.isPresented.get() { self.isPresented.set(false) }
                guard !wasProgrammatic else { return }
                self.completion(result)
            }
        } else if let session {
            isProgrammaticDismissal = true
            session.cancel()
        }
    }

    deinit { removeObserver() }
}
