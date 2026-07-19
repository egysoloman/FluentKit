import AppKit

/// A small Codable-backed store for document, workspace, and scene state.
///
/// Values are encoded as JSON data inside UserDefaults and namespaced so multiple
/// applications or test instances can share the standard defaults without colliding.
public final class FluentRestorationStore: NSObject {
    public static let standard = FluentRestorationStore()
    fileprivate static let didChange = Notification.Name("FluentKit.RestorationStore.didChange")
    fileprivate static let changedKey = "key"

    private let defaults: UserDefaults
    private let namespace: String

    public init(defaults: UserDefaults = .standard, namespace: String = "FluentKit.restoration") {
        precondition(!namespace.isEmpty, "Fluent restoration namespaces must not be empty")
        self.defaults = defaults
        self.namespace = namespace
        super.init()
    }

    /// Reads and decodes a value. Invalid or missing data is treated as absent so a
    /// corrupted preference never prevents an application from launching.
    public func value<Value: Decodable>(forKey key: String, as type: Value.Type = Value.self) -> Value? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// Encodes and stores a value. Returns false when encoding fails.
    @discardableResult
    public func set<Value: Encodable>(_ value: Value, forKey key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: storageKey(for: key))
        notifyChange(forKey: key)
        return true
    }

    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: storageKey(for: key))
        notifyChange(forKey: key)
    }

    /// Removes every value owned by this store while leaving unrelated defaults intact.
    public func removeAll() {
        let prefix = namespace + "."
        let keys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
        keys.forEach(defaults.removeObject(forKey:))
        keys.forEach { notifyChange(forKey: String($0.dropFirst(prefix.count))) }
    }

    private func storageKey(for key: String) -> String {
        precondition(!key.isEmpty, "Fluent restoration keys must not be empty")
        return namespace + "." + key
    }

    fileprivate func encodedValues() -> [String: Data] {
        let prefix = namespace + "."
        var values: [String: Data] = [:]
        for storageKey in defaults.dictionaryRepresentation().keys where storageKey.hasPrefix(prefix) {
            guard let data = defaults.data(forKey: storageKey) else { continue }
            values[String(storageKey.dropFirst(prefix.count))] = data
        }
        return values
    }

    fileprivate func replaceEncodedValues(_ values: [String: Data]) {
        let previous = encodedValues()
        let changedKeys = Set(previous.keys).union(values.keys).filter { previous[$0] != values[$0] }
        for key in changedKeys {
            if let data = values[key] {
                defaults.set(data, forKey: storageKey(for: key))
            } else {
                defaults.removeObject(forKey: storageKey(for: key))
            }
            notifyChange(forKey: key)
        }
    }

    private func notifyChange(forKey key: String) {
        NotificationCenter.default.post(
            name: Self.didChange,
            object: self,
            userInfo: [Self.changedKey: key]
        )
    }
}

/// An isolated, in-memory view of one restoration namespace during migration.
public final class FluentStateMigrationContext {
    fileprivate var values: [String: Data]

    fileprivate init(values: [String: Data]) {
        self.values = values
    }

    public var keys: [String] { values.keys.sorted() }

    public func value<Value: Decodable>(
        forKey key: String,
        as type: Value.Type = Value.self
    ) -> Value? {
        guard let data = values[key] else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func set<Value: Encodable>(_ value: Value, forKey key: String) throws {
        precondition(!key.isEmpty, "Fluent migration keys must not be empty")
        values[key] = try JSONEncoder().encode(value)
    }

    public func removeValue(forKey key: String) {
        values.removeValue(forKey: key)
    }

    /// Moves the encoded value without requiring the old schema's Swift type to remain available.
    @discardableResult
    public func renameValue(
        fromKey source: String,
        toKey destination: String,
        overwrite: Bool = false
    ) -> Bool {
        precondition(!source.isEmpty && !destination.isEmpty, "Fluent migration keys must not be empty")
        guard let data = values[source], overwrite || values[destination] == nil else { return false }
        values[destination] = data
        values.removeValue(forKey: source)
        return true
    }
}

/// One strictly forward schema migration.
public struct FluentStateMigrationStep {
    public let fromVersion: Int
    public let toVersion: Int
    public let migrate: (FluentStateMigrationContext) throws -> Void

    public init(
        from fromVersion: Int,
        to toVersion: Int,
        migrate: @escaping (FluentStateMigrationContext) throws -> Void
    ) {
        precondition(fromVersion >= 0, "Fluent migration versions must not be negative")
        precondition(toVersion > fromVersion, "Fluent migrations must move to a newer version")
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.migrate = migrate
    }
}

public struct FluentStateMigrationResult: Equatable, Sendable {
    public let fromVersion: Int
    public let toVersion: Int
    public let didMigrate: Bool

    public init(fromVersion: Int, toVersion: Int, didMigrate: Bool) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.didMigrate = didMigrate
    }
}

public enum FluentStateMigrationError: Error, Equatable {
    case storedVersionIsNewer(stored: Int, supported: Int)
    case missingStep(from: Int, target: Int)
}

/// Applies ordered schema changes atomically to one `FluentRestorationStore` namespace.
public struct FluentStateMigrator {
    public let targetVersion: Int
    public let schemaVersionKey: String
    public let steps: [FluentStateMigrationStep]

    public init(
        targetVersion: Int,
        schemaVersionKey: String = "__schemaVersion",
        steps: [FluentStateMigrationStep]
    ) {
        precondition(targetVersion >= 0, "Fluent migration target versions must not be negative")
        precondition(!schemaVersionKey.isEmpty, "Fluent migration schema keys must not be empty")
        precondition(
            Set(steps.map(\.fromVersion)).count == steps.count,
            "Fluent migrations must have one step per source version"
        )
        self.targetVersion = targetVersion
        self.schemaVersionKey = schemaVersionKey
        self.steps = steps
    }

    @discardableResult
    public func migrate(_ store: FluentRestorationStore) throws -> FluentStateMigrationResult {
        let initialVersion = store.value(forKey: schemaVersionKey, as: Int.self) ?? 0
        guard initialVersion <= targetVersion else {
            throw FluentStateMigrationError.storedVersionIsNewer(
                stored: initialVersion,
                supported: targetVersion
            )
        }
        guard initialVersion < targetVersion else {
            return FluentStateMigrationResult(
                fromVersion: initialVersion,
                toVersion: targetVersion,
                didMigrate: false
            )
        }

        let stepsByVersion = Dictionary(uniqueKeysWithValues: steps.map { ($0.fromVersion, $0) })
        let context = FluentStateMigrationContext(values: store.encodedValues())
        var currentVersion = initialVersion
        while currentVersion < targetVersion {
            guard let step = stepsByVersion[currentVersion], step.toVersion <= targetVersion else {
                throw FluentStateMigrationError.missingStep(
                    from: currentVersion,
                    target: targetVersion
                )
            }
            try step.migrate(context)
            currentVersion = step.toVersion
            try context.set(currentVersion, forKey: schemaVersionKey)
        }

        store.replaceEncodedValues(context.values)
        return FluentStateMigrationResult(
            fromVersion: initialVersion,
            toVersion: currentVersion,
            didMigrate: true
        )
    }
}

/// A Codable state wrapper that restores its initial value from a
/// FluentRestorationStore and persists every subsequent mutation.
///
/// It mirrors FluentState projected binding API, so restored state can be passed directly to
/// controls and navigation/list selection.
@propertyWrapper
public final class FluentRestoredState<Value: Codable> {
    private let observable: FluentObservable<Value>
    private let key: String
    private let store: FluentRestorationStore
    private let defaultValue: Value
    private var storeObserver: NSObjectProtocol?

    public init(
        wrappedValue: Value,
        _ key: String,
        store: FluentRestorationStore = .standard
    ) {
        self.key = key
        self.store = store
        defaultValue = wrappedValue
        let initialValue = store.value(forKey: key, as: Value.self) ?? wrappedValue
        observable = FluentObservable(initialValue)
        storeObserver = NotificationCenter.default.addObserver(
            forName: FluentRestorationStore.didChange,
            object: store,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  notification.userInfo?[FluentRestorationStore.changedKey] as? String == self.key else { return }
            self.observable.value = self.store.value(forKey: self.key, as: Value.self) ?? self.defaultValue
        }
    }

    public var wrappedValue: Value {
        get { observable.value }
        set {
            if !store.set(newValue, forKey: key) {
                observable.value = newValue
            }
        }
    }

    public var projectedValue: FluentBinding<Value> {
        FluentBinding(
            get: { self.observable.value },
            set: { self.wrappedValue = $0 },
            observe: { self.observable.observe($0, notifyImmediately: false) },
            removeObserver: { self.observable.removeObserver($0) }
        )
    }

    public var observableValue: FluentObservable<Value> { observable }

    public func observe(_ observer: @escaping FluentObservable<Value>.Observer) -> UUID {
        observable.observe(observer)
    }

    /// Removes the persisted value and restores the value declared at initialization.
    public func reset() {
        store.removeValue(forKey: key)
    }

    deinit {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
    }
}
