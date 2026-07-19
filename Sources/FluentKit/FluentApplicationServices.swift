import AppKit

/// Pasteboard capabilities exposed to the native macOS Services menu for the current selection.
public struct FluentServicesMenuTypes: Sendable {
    public var sendTypes: [NSPasteboard.PasteboardType]
    public var returnTypes: [NSPasteboard.PasteboardType]

    public init(
        sendTypes: [NSPasteboard.PasteboardType] = [],
        returnTypes: [NSPasteboard.PasteboardType] = []
    ) {
        self.sendTypes = sendTypes
        self.returnTypes = returnTypes
    }
}

/// A service implemented by the application and routed through the native macOS Services system.
///
/// The app bundle declares a matching `NSServices` entry whose `NSMessage` is
/// `performFluentService` and whose `NSUserData` equals `identifier`. FluentKit owns the Objective-C
/// entry point and forwards the request to this Swift closure.
public struct FluentProvidedService {
    public static let message = "performFluentService"

    public let identifier: String
    public let acceptedTypes: [NSPasteboard.PasteboardType]
    public let returnedTypes: [NSPasteboard.PasteboardType]
    public let action: (NSPasteboard, FluentWindowCoordinator) throws -> Void

    public init(
        identifier: String,
        acceptedTypes: [NSPasteboard.PasteboardType],
        returnedTypes: [NSPasteboard.PasteboardType] = [],
        action: @escaping (NSPasteboard, FluentWindowCoordinator) throws -> Void
    ) {
        precondition(!identifier.isEmpty, "Fluent service identifiers must not be empty")
        self.identifier = identifier
        self.acceptedTypes = acceptedTypes
        self.returnedTypes = returnedTypes
        self.action = action
    }
}

public enum FluentProvidedServiceError: Error, Equatable, LocalizedError {
    case unknownIdentifier(String)
    case unsupportedPasteboardContents(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownIdentifier(identifier):
            return "No Fluent service is registered with identifier \(identifier)."
        case let .unsupportedPasteboardContents(identifier):
            return "The pasteboard does not contain data accepted by service \(identifier)."
        }
    }
}

/// Optional application-level integration points for files, URLs, reopen requests, and the Dock
/// menu. The callbacks receive the live window coordinator so an app can open or focus a scene
/// without reaching through AppKit globals.
public protocol FluentApplicationServices {
    func applicationOpenFiles(_ urls: [URL], with coordinator: FluentWindowCoordinator)
    func applicationOpenURLs(_ urls: [URL], with coordinator: FluentWindowCoordinator)
    func applicationShouldHandleReopen(
        hasVisibleWindows: Bool,
        with coordinator: FluentWindowCoordinator
    ) -> Bool

    var applicationDockMenuItems: [FluentMenuItem] { get }
    var applicationServicesMenuTypes: FluentServicesMenuTypes { get }
    var applicationProvidedServices: [FluentProvidedService] { get }
}

public extension FluentApplicationServices {
    func applicationOpenFiles(_ urls: [URL], with coordinator: FluentWindowCoordinator) {}
    func applicationOpenURLs(_ urls: [URL], with coordinator: FluentWindowCoordinator) {}

    func applicationShouldHandleReopen(
        hasVisibleWindows: Bool,
        with coordinator: FluentWindowCoordinator
    ) -> Bool {
        false
    }

    var applicationDockMenuItems: [FluentMenuItem] { [] }
    var applicationServicesMenuTypes: FluentServicesMenuTypes { .init() }
    var applicationProvidedServices: [FluentProvidedService] { [] }
}

/// Routes native application events to a `FluentApplicationServices` provider and coordinates the
/// default reopen behavior. `FluentApplicationRunner` uses this same public object, so embedded
/// hosts and executable tests can exercise identical behavior without launching a second app.
public final class FluentApplicationServicesCoordinator: NSObject {
    public let windows: FluentWindowCoordinator

    private let provider: (any FluentApplicationServices)?

    public init(
        provider: (any FluentApplicationServices)?,
        windows: FluentWindowCoordinator
    ) {
        self.provider = provider
        self.windows = windows
        super.init()
    }

    public func openFiles(_ urls: [URL]) {
        provider?.applicationOpenFiles(urls, with: windows)
    }

    public func openURLs(_ urls: [URL]) {
        provider?.applicationOpenURLs(urls, with: windows)
    }

    /// Returns true when the provider handles reopening or the default behavior restores the first
    /// declared scene. A visible app is already considered handled.
    @discardableResult
    public func handleReopen(hasVisibleWindows: Bool) -> Bool {
        if provider?.applicationShouldHandleReopen(
            hasVisibleWindows: hasVisibleWindows,
            with: windows
        ) == true {
            return true
        }
        if !hasVisibleWindows, let firstID = windows.primaryWindowID {
            _ = windows.open(id: firstID)
        }
        return true
    }

    /// Builds the native Dock menu from the provider's latest declarative items.
    public func makeDockMenu() -> NSMenu? {
        let items = provider?.applicationDockMenuItems ?? []
        return items.isEmpty ? nil : makeFluentMenu(items: items)
    }

    /// Registers selection pasteboard capabilities and installs this coordinator as the service
    /// provider when the app declares at least one `FluentProvidedService`.
    public func installServices(on application: NSApplication = .shared) {
        let menuTypes = provider?.applicationServicesMenuTypes ?? .init()
        application.registerServicesMenuSendTypes(
            deduplicated(menuTypes.sendTypes),
            returnTypes: deduplicated(menuTypes.returnTypes)
        )
        if !providedServices.isEmpty {
            application.servicesProvider = self
        }
    }

    /// Performs a provided service without crossing the Objective-C Services entry point.
    /// Embedded hosts and validation can use this deterministic route directly.
    public func performProvidedService(
        identifier: String,
        pasteboard: NSPasteboard
    ) throws {
        guard let service = providedServices.first(where: { $0.identifier == identifier }) else {
            throw FluentProvidedServiceError.unknownIdentifier(identifier)
        }
        if !service.acceptedTypes.isEmpty,
           pasteboard.availableType(from: service.acceptedTypes) == nil {
            throw FluentProvidedServiceError.unsupportedPasteboardContents(identifier)
        }
        try service.action(pasteboard, windows)
    }

    /// Stable Objective-C entry point referenced by each app bundle `NSServices` declaration.
    @objc(performFluentService:userData:error:)
    public func performFluentService(
        _ pasteboard: NSPasteboard,
        userData identifier: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        do {
            try performProvidedService(identifier: identifier, pasteboard: pasteboard)
            errorPointer.pointee = nil
        } catch {
            errorPointer.pointee = error.localizedDescription as NSString
        }
    }

    private var providedServices: [FluentProvidedService] {
        let services = provider?.applicationProvidedServices ?? []
        precondition(
            Set(services.map(\.identifier)).count == services.count,
            "Fluent provided service identifiers must be unique"
        )
        return services
    }

    private func deduplicated(
        _ types: [NSPasteboard.PasteboardType]
    ) -> [NSPasteboard.PasteboardType] {
        var rawValues = Set<String>()
        return types.filter { rawValues.insert($0.rawValue).inserted }
    }
}
