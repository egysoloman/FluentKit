import AppKit

public final class FluentObservable<Value> {
    public typealias Observer = (Value) -> Void

    private var storedValue: Value
    private let lock = NSLock()

    public var value: Value {
        get {
            FluentDependencyTracking.register(self)
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
            notifyObservers()
        }
    }

    private var observers: [UUID: Observer] = [:]

    public init(_ value: Value) { storedValue = value }

    @discardableResult
    public func observe(_ observer: @escaping Observer, notifyImmediately: Bool = true) -> UUID {
        let id = UUID()
        lock.lock()
        observers[id] = observer
        let current = storedValue
        lock.unlock()
        if notifyImmediately {
            deliver(observer, value: current)
        }
        return id
    }

    public func removeObserver(_ id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
    }

    private func notifyObservers() {
        lock.lock()
        let snapshot = Array(observers.values)
        let current = storedValue
        lock.unlock()
        snapshot.forEach { deliver($0, value: current) }
    }

    private func deliver(_ observer: @escaping Observer, value: Value) {
        if Thread.isMainThread {
            observer(value)
        } else {
            DispatchQueue.main.async { observer(value) }
        }
    }
}

struct FluentTrackedDependency {
    let id: ObjectIdentifier
    let subscribe: (@escaping () -> Void) -> (() -> Void)
}

private final class FluentDependencyCollector {
    var dependencies: [ObjectIdentifier: FluentTrackedDependency] = [:]
}

enum FluentDependencyTracking {
    private static let collectorKey = "FluentKit.DependencyCollector"

    private static var currentCollector: FluentDependencyCollector? {
        get { Thread.current.threadDictionary[collectorKey] as? FluentDependencyCollector }
        set { Thread.current.threadDictionary[collectorKey] = newValue }
    }

    static func collect<Result>(_ operation: () -> Result) -> (Result, [ObjectIdentifier: FluentTrackedDependency]) {
        let parent = currentCollector
        let collector = FluentDependencyCollector()
        currentCollector = collector
        defer { currentCollector = parent }
        return (operation(), collector.dependencies)
    }

    static func register<Value>(_ observable: FluentObservable<Value>) {
        guard let collector = currentCollector else { return }
        let id = ObjectIdentifier(observable)
        guard collector.dependencies[id] == nil else { return }
        collector.dependencies[id] = FluentTrackedDependency(id: id) { invalidate in
            let observerID = observable.observe({ _ in invalidate() }, notifyImmediately: false)
            return { observable.removeObserver(observerID) }
        }
    }
}

public struct FluentBinding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void
    let observe: ((@escaping (Value) -> Void) -> UUID)?
    let removeObserver: ((UUID) -> Void)?

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
        observe = nil
        removeObserver = nil
    }

    init(get: @escaping () -> Value, set: @escaping (Value) -> Void, observe: ((@escaping (Value) -> Void) -> UUID)?, removeObserver: ((UUID) -> Void)?) {
        self.get = get
        self.set = set
        self.observe = observe
        self.removeObserver = removeObserver
    }

    public var wrappedValue: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    /// Observes binding changes when the underlying source supports observation (for example
    /// `FluentState` or `FluentRestoredState`). Plain closure bindings may return `nil`.
    @discardableResult
    public func observe(_ observer: @escaping (Value) -> Void) -> UUID? {
        observe.map { $0(observer) }
    }

    public func removeObserver(_ id: UUID) {
        removeObserver?(id)
    }

    public func map<Output>(_ transform: @escaping (Value) -> Output, _ inverse: @escaping (Output) -> Value) -> FluentBinding<Output> {
        FluentBinding<Output>(
            get: { transform(self.get()) },
            set: { self.set(inverse($0)) },
            observe: self.observe.map { observe in { observer in observe { observer(transform($0)) } } },
            removeObserver: self.removeObserver
        )
    }
}

@propertyWrapper
public final class FluentState<Value> {
    private let observable: FluentObservable<Value>

    public init(wrappedValue: Value) { observable = FluentObservable(wrappedValue) }

    public var wrappedValue: Value {
        get { observable.value }
        set { observable.value = newValue }
    }

    public var projectedValue: FluentBinding<Value> {
        FluentBinding(
            get: { self.observable.value },
            set: { self.observable.value = $0 },
            observe: { self.observable.observe($0, notifyImmediately: false) },
            removeObserver: { self.observable.removeObserver($0) }
        )
    }

    public var observableValue: FluentObservable<Value> { observable }

    public func observe(_ observer: @escaping FluentObservable<Value>.Observer) -> UUID {
        observable.observe(observer)
    }
}

public extension FluentView {
    func onChange<Value>(of observable: FluentObservable<Value>, perform action: @escaping (Value) -> Void) -> FluentObservedView<Self, Value> {
        FluentObservedView(content: self, observable: observable, action: action)
    }
}

public struct FluentObservedView<Content: FluentView, Value>: FluentUpdatablePrimitiveView {
    fileprivate let content: Content
    fileprivate let observable: FluentObservable<Value>
    fileprivate let action: (Value) -> Void

    public var body: NeverFluentView { NeverFluentView() }

    public init(content: Content, observable: FluentObservable<Value>, action: @escaping (Value) -> Void) {
        self.content = content
        self.observable = observable
        self.action = action
    }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        FluentObservationHost(
            content: content._mount(in: context),
            observable: observable,
            action: action,
            invalidate: context.invalidate
        )
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let host = view as? FluentObservationHost<Value> else { return false }
        host.update(
            observable: observable,
            action: action,
            context: context,
            updateContent: { view, updateContext in content._update(view, in: updateContext) },
            makeContent: { content._mount(in: context) }
        )
        return true
    }
}

private final class FluentObservationHost<Value>: NSView {
    private var observable: FluentObservable<Value>
    private var action: (Value) -> Void
    private var invalidate: (() -> Void)?
    private var observerID: UUID?

    init(content: NSView, observable: FluentObservable<Value>, action: @escaping (Value) -> Void, invalidate: (() -> Void)?) {
        self.observable = observable
        self.action = action
        self.invalidate = invalidate
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        observerID = observable.observe({ [weak self] value in
            self?.action(value)
            self?.invalidate?()
        }, notifyImmediately: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(observable: FluentObservable<Value>, action: @escaping (Value) -> Void, context: FluentRenderContext, updateContent: (NSView, FluentRenderContext) -> Bool, makeContent: () -> NSView) {
        self.action = action
        self.invalidate = context.invalidate
        if self.observable !== observable {
            if let observerID { self.observable.removeObserver(observerID) }
            self.observable = observable
            observerID = observable.observe({ [weak self] value in
                self?.action(value)
                self?.invalidate?()
            }, notifyImmediately: false)
        }
        guard let current = subviews.first else { return }
        if !updateContent(current, context) {
            current.removeFromSuperview()
            let content = makeContent()
            addSubview(content)
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    deinit {
        if let observerID { observable.removeObserver(observerID) }
    }
}
