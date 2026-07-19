import AppKit

/// Coordinates multiple document sessions while keeping activation and dirty-close policy in one
/// application-owned object. Individual sessions remain responsible for encoding, undo, and save
/// semantics; this type only coordinates their lifetime and routing.
public final class FluentDocumentCoordinator<Document: Equatable> {
    public let activeDocumentID: FluentObservable<String?>

    private var orderedIDs: [String] = []
    private var sessionsByID: [String: FluentDocumentSession<Document>] = [:]

    public init(sessions: [FluentDocumentSession<Document>] = []) {
        activeDocumentID = FluentObservable(nil)
        sessions.forEach { register($0, activate: false) }
        if let firstID = orderedIDs.first { activeDocumentID.value = firstID }
    }

    public var documentIDs: [String] { orderedIDs }

    public var sessions: [FluentDocumentSession<Document>] {
        orderedIDs.compactMap { sessionsByID[$0] }
    }

    public var activeSession: FluentDocumentSession<Document>? {
        guard let activeID = activeDocumentID.value else { return nil }
        return sessionsByID[activeID]
    }

    public func session(for id: String) -> FluentDocumentSession<Document>? {
        sessionsByID[id]
    }

    /// Registers a session once. Registration can activate the new document immediately.
    public func register(
        _ session: FluentDocumentSession<Document>,
        activate: Bool = true
    ) {
        precondition(sessionsByID[session.id] == nil, "Duplicate Fluent document ID: \(session.id)")
        sessionsByID[session.id] = session
        orderedIDs.append(session.id)
        if activate || activeDocumentID.value == nil {
            activeDocumentID.value = session.id
        }
    }

    @discardableResult
    public func activate(id: String) -> Bool {
        guard sessionsByID[id] != nil else { return false }
        activeDocumentID.value = id
        return true
    }

    /// Opens a URL into an already registered session and makes that session active.
    @discardableResult
    public func open(id: String, from url: URL) throws -> Bool {
        guard let session = sessionsByID[id] else { return false }
        try session.open(from: url)
        activeDocumentID.value = id
        return true
    }

    /// Finds the registered session associated with a URL, if any.
    public func session(forFileURL url: URL) -> FluentDocumentSession<Document>? {
        sessions.first { $0.fileURL.value?.standardizedFileURL == url.standardizedFileURL }
    }

    /// Closes a document unless it is dirty. Pass `discardChanges` for an explicit destructive close.
    @discardableResult
    public func close(id: String, discardChanges: Bool = false) -> Bool {
        guard let session = sessionsByID[id] else { return false }
        guard discardChanges || !session.isDirty.value else { return false }
        sessionsByID.removeValue(forKey: id)
        orderedIDs.removeAll { $0 == id }
        if activeDocumentID.value == id {
            activeDocumentID.value = orderedIDs.first
        }
        return true
    }

    /// Saves every registered document in declaration order. The first failure stops the batch.
    public func saveAll() throws {
        for session in sessions {
            try session.save()
        }
    }

    /// Attempts to close every document, preserving all sessions when a dirty document blocks close.
    @discardableResult
    public func closeAll(discardChanges: Bool = false) -> Bool {
        guard discardChanges || sessions.allSatisfy({ !$0.isDirty.value }) else { return false }
        sessionsByID.removeAll()
        orderedIDs.removeAll()
        activeDocumentID.value = nil
        return true
    }
}
