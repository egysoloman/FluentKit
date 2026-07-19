import AppKit

/// Options applied to a native `NSPrintOperation`.
public struct FluentPrintConfiguration {
    public var printInfo: NSPrintInfo?
    public var jobTitle: String?
    public var showsPrintPanel: Bool
    public var showsProgressPanel: Bool

    public init(
        printInfo: NSPrintInfo? = nil,
        jobTitle: String? = nil,
        showsPrintPanel: Bool = true,
        showsProgressPanel: Bool = true
    ) {
        self.printInfo = printInfo
        self.jobTitle = jobTitle
        self.showsPrintPanel = showsPrintPanel
        self.showsProgressPanel = showsProgressPanel
    }
}

public enum FluentPrintError: Error, Equatable, LocalizedError {
    case missingWindow
    case cancelled
    case failed

    public var errorDescription: String? {
        switch self {
        case .missingWindow: return "Printing requires a visible document window."
        case .cancelled: return "Printing was cancelled."
        case .failed: return "The print operation could not be completed."
        }
    }
}

/// A cancellable native print presentation. Cancellation suppresses the callback when a host
/// dismisses its operation before AppKit returns from the nested print run loop.
public protocol FluentPrintSession: AnyObject {
    func cancel()
}

public protocol FluentPrintPresenting: AnyObject {
    @discardableResult
    func presentPrint(
        view: NSView,
        in window: NSWindow?,
        configuration: FluentPrintConfiguration,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> any FluentPrintSession
}

public enum FluentPrintFactory {
    public static func makeOperation(
        view: NSView,
        configuration: FluentPrintConfiguration = .init()
    ) -> NSPrintOperation {
        let printInfo = configuration.printInfo ?? NSPrintInfo.shared.copy() as! NSPrintInfo
        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        if let jobTitle = configuration.jobTitle, !jobTitle.isEmpty {
            operation.jobTitle = jobTitle
        }
        operation.showsPrintPanel = configuration.showsPrintPanel
        operation.showsProgressPanel = configuration.showsProgressPanel
        return operation
    }
}

/// The production presenter backed by `NSPrintOperation` and an AppKit print sheet.
public final class FluentNativePrintPresenter: FluentPrintPresenting {
    public static let shared = FluentNativePrintPresenter()

    private var activeSessions: [UUID: FluentNativePrintSession] = [:]

    public init() {}

    @discardableResult
    public func presentPrint(
        view: NSView,
        in window: NSWindow?,
        configuration: FluentPrintConfiguration = .init(),
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> any FluentPrintSession {
        let session = FluentNativePrintSession(
            view: view,
            window: window,
            configuration: configuration,
            completion: completion,
            onFinish: { [weak self] id in self?.activeSessions.removeValue(forKey: id) }
        )
        activeSessions[session.id] = session
        session.present()
        return session
    }
}

private final class FluentNativePrintSession: NSObject, FluentPrintSession {
    let id = UUID()
    private let view: NSView
    private weak var window: NSWindow?
    private let configuration: FluentPrintConfiguration
    private var completion: ((Result<Void, Error>) -> Void)?
    private let onFinish: (UUID) -> Void
    private var operation: NSPrintOperation?
    private var isCancelled = false

    init(
        view: NSView,
        window: NSWindow?,
        configuration: FluentPrintConfiguration,
        completion: @escaping (Result<Void, Error>) -> Void,
        onFinish: @escaping (UUID) -> Void
    ) {
        self.view = view
        self.window = window
        self.configuration = configuration
        self.completion = completion
        self.onFinish = onFinish
    }

    func present() {
        guard let window else {
            finish(.failure(FluentPrintError.missingWindow))
            return
        }
        let operation = FluentPrintFactory.makeOperation(view: view, configuration: configuration)
        self.operation = operation
        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    func cancel() {
        isCancelled = true
        completion = nil
        operation = nil
        onFinish(id)
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        _ = contextInfo
        guard !isCancelled else { return }
        finish(success ? .success(()) : .failure(FluentPrintError.cancelled))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let completion else { return }
        self.completion = nil
        operation = nil
        onFinish(id)
        completion(result)
    }
}

/// Presents native sharing services from an arbitrary AppKit view. The picker remains alive in
/// the returned session until it is dismissed by the system or the host calls `dismiss()`.
public struct FluentSharingConfiguration {
    public var relativeRect: NSRect?
    public var preferredEdge: NSRectEdge

    public init(relativeRect: NSRect? = nil, preferredEdge: NSRectEdge = .maxY) {
        self.relativeRect = relativeRect
        self.preferredEdge = preferredEdge
    }
}

public protocol FluentSharingSession: AnyObject {
    func dismiss()
}

public protocol FluentSharingPresenting: AnyObject {
    @discardableResult
    func presentSharing(
        items: [Any],
        from view: NSView,
        configuration: FluentSharingConfiguration
    ) -> any FluentSharingSession
}

public final class FluentNativeSharingPresenter: FluentSharingPresenting {
    public static let shared = FluentNativeSharingPresenter()

    public init() {}

    @discardableResult
    public func presentSharing(
        items: [Any],
        from view: NSView,
        configuration: FluentSharingConfiguration = .init()
    ) -> any FluentSharingSession {
        let picker = NSSharingServicePicker(items: items)
        let session = FluentNativeSharingSession(picker: picker)
        let rect = configuration.relativeRect ?? view.bounds
        picker.show(relativeTo: rect, of: view, preferredEdge: configuration.preferredEdge)
        return session
    }
}

private final class FluentNativeSharingSession: FluentSharingSession {
    private var picker: NSSharingServicePicker?

    init(picker: NSSharingServicePicker) { self.picker = picker }

    func dismiss() {
        picker = nil
    }
}
