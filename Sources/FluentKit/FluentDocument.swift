import AppKit

/// Controls automatic saving after an edited document becomes dirty.
public enum FluentAutosavePolicy: Equatable, Sendable {
    case disabled
    case delayed(TimeInterval)

    fileprivate var delay: TimeInterval? {
        switch self {
        case .disabled: return nil
        case let .delayed(delay): return max(delay, 0)
        }
    }
}

/// Describes how a document value is encoded to and decoded from disk.
public struct FluentDocumentFormat<Document> {
    public let decode: (Data) throws -> Document
    public let encode: (Document) throws -> Data

    public init(
        decode: @escaping (Data) throws -> Document,
        encode: @escaping (Document) throws -> Data
    ) {
        self.decode = decode
        self.encode = encode
    }
}

public extension FluentDocumentFormat where Document: Codable {
    static var json: FluentDocumentFormat<Document> {
        FluentDocumentFormat(
            decode: { try JSONDecoder().decode(Document.self, from: $0) },
            encode: { try JSONEncoder().encode($0) }
        )
    }
}

/// A native document-session model with observable content, dirty-state calculation,
/// undo/redo transactions, save/revert lifecycle, delayed autosave, and a document-scoped
/// restoration store for UI state such as selection and zoom.
public final class FluentDocumentSession<Document: Equatable> {
    public let id: String
    public let document: FluentObservable<Document>
    public let fileURL: FluentObservable<URL?>
    public let isDirty: FluentObservable<Bool>
    public let undoCoordinator: FluentUndoCoordinator
    public let restorationStore: FluentRestorationStore

    public var autosavePolicy: FluentAutosavePolicy {
        didSet { scheduleAutosaveIfNeeded() }
    }

    private let format: FluentDocumentFormat<Document>
    private var savedDocument: Document
    private var autosaveWorkItem: DispatchWorkItem?

    public init(
        id: String,
        document: Document,
        fileURL: URL? = nil,
        format: FluentDocumentFormat<Document>,
        autosave: FluentAutosavePolicy = .disabled,
        undoCoordinator: FluentUndoCoordinator = FluentUndoCoordinator(),
        defaults: UserDefaults = .standard
    ) {
        precondition(!id.isEmpty, "Fluent document IDs must not be empty")
        self.id = id
        self.document = FluentObservable(document)
        self.fileURL = FluentObservable(fileURL)
        isDirty = FluentObservable(false)
        self.format = format
        savedDocument = document
        autosavePolicy = autosave
        self.undoCoordinator = undoCoordinator
        restorationStore = FluentRestorationStore(
            defaults: defaults,
            namespace: "FluentKit.document." + id
        )
    }

    public convenience init(
        id: String,
        document: Document,
        fileURL: URL? = nil,
        autosave: FluentAutosavePolicy = .disabled,
        undoCoordinator: FluentUndoCoordinator = FluentUndoCoordinator(),
        defaults: UserDefaults = .standard
    ) where Document: Codable {
        self.init(
            id: id,
            document: document,
            fileURL: fileURL,
            format: .json,
            autosave: autosave,
            undoCoordinator: undoCoordinator,
            defaults: defaults
        )
    }

    /// A two-way binding that registers distinct document changes with the session undo manager.
    public func binding(actionName: String = "Edit Document") -> FluentBinding<Document> {
        baseBinding.undoable(using: undoCoordinator, actionName: actionName)
    }

    /// Applies an in-place mutation as one undoable document transaction.
    public func mutate(actionName: String = "Edit Document", _ mutation: (inout Document) -> Void) {
        var next = document.value
        mutation(&next)
        binding(actionName: actionName).set(next)
    }

    /// Replaces the document and starts a clean session, as when opening a file.
    public func replace(with document: Document, fileURL: URL? = nil) {
        autosaveWorkItem?.cancel()
        savedDocument = document
        self.document.value = document
        self.fileURL.value = fileURL
        isDirty.value = false
        undoCoordinator.removeAllActions()
    }

    /// Decodes a document from disk and makes it the clean saved revision.
    public func open(from url: URL) throws {
        let data = try Data(contentsOf: url)
        replace(with: try format.decode(data), fileURL: url)
    }

    /// Imports a file as a new clean document without associating the source URL with Save.
    public func importDocument(from url: URL) throws {
        let data = try Data(contentsOf: url)
        replace(with: try format.decode(data), fileURL: nil)
    }

    /// Saves the current revision atomically. Supplying a URL performs Save As.
    public func save(to destination: URL? = nil) throws {
        guard let destination = destination ?? fileURL.value else {
            throw FluentDocumentSessionError.missingFileURL
        }
        let revision = document.value
        let data = try format.encode(revision)
        try data.write(to: destination, options: .atomic)
        fileURL.value = destination
        savedDocument = revision
        isDirty.value = false
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
    }

    /// Writes an encoded copy without changing the session URL, saved revision, or dirty state.
    public func exportDocument(to destination: URL) throws {
        let data = try format.encode(document.value)
        try data.write(to: destination, options: .atomic)
    }

    /// Reloads the current file URL, discarding unsaved edits and undo history.
    public func revert() throws {
        guard let fileURL = fileURL.value else {
            throw FluentDocumentSessionError.missingFileURL
        }
        try open(from: fileURL)
    }

    private var baseBinding: FluentBinding<Document> {
        FluentBinding(
            get: { self.document.value },
            set: { [weak self] value in self?.apply(value) },
            observe: { self.document.observe($0, notifyImmediately: false) },
            removeObserver: { self.document.removeObserver($0) }
        )
    }

    private func apply(_ value: Document) {
        guard document.value != value else { return }
        document.value = value
        isDirty.value = value != savedDocument
        scheduleAutosaveIfNeeded()
    }

    private func scheduleAutosaveIfNeeded() {
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        guard isDirty.value, fileURL.value != nil, let delay = autosavePolicy.delay else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isDirty.value else { return }
            try? self.save()
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    deinit { autosaveWorkItem?.cancel() }
}

public enum FluentDocumentSessionError: Error, Equatable {
    case missingFileURL
}
