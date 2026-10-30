import AppKit

/// Controls whether marked (IME composition) text is published to the model.
public enum FluentTextCommitPolicy: Sendable {
    case continuous
    case committedText
}

public struct FluentTextEditingChange: Equatable {
    public let text: String
    public let isComposing: Bool
}

public struct FluentTextInputConfiguration {
    public var commitPolicy: FluentTextCommitPolicy
    public var onEditingChange: ((FluentTextEditingChange) -> Void)?

    public init(commitPolicy: FluentTextCommitPolicy = .continuous,
                onEditingChange: ((FluentTextEditingChange) -> Void)? = nil) {
        self.commitPolicy = commitPolicy
        self.onEditingChange = onEditingChange
    }
}

public extension FluentBinding where Value == String {
    /// Applies to TextBox, PasswordBox, SearchField and AutoSuggestBox bindings.
    func textInput(_ configuration: FluentTextInputConfiguration) -> FluentBinding<String> {
        var copy = self
        copy.textInputConfiguration = configuration
        return copy
    }
}

final class FluentStringBindingCoordinator {
    private weak var field: NSTextField?
    private var binding: FluentBinding<String>
    private var observerID: UUID?
    private var subscriptionGeneration: UInt = 0
    private var deliveryGeneration: UInt = 0
    private var publicationGeneration: UInt = 0
    private var publicationScheduled = false
    private var lastModelValue: String?
    private var pendingExternalValue: String?
    private var isPublishing = false
    private var lastEditingChange: FluentTextEditingChange?
    private weak var observedEditor: NSTextView?
    private var editingObservers: [NSObjectProtocol] = []
    private var editorObservers: [NSObjectProtocol] = []
    var currentBinding: FluentBinding<String> { binding }

    init(field: NSTextField, binding: FluentBinding<String>) {
        self.field = field
        self.binding = binding
        installObserver()
        synchronizeExternalValue(self.modelValue())
        for name in [NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification] {
            editingObservers.append(NotificationCenter.default.addObserver(forName: name, object: field, queue: .main) { [weak self] notification in
                if notification.name == NSControl.textDidBeginEditingNotification { self?.observeEditorChanges() }
                else { self?.removeEditorObservers() }
            })
        }
    }

    func update(binding newBinding: FluentBinding<String>) {
        let reusesObservation = binding.observationIdentity != nil
            && binding.observationIdentity == newBinding.observationIdentity
        if !reusesObservation {
            cancelScheduledPublication()
            removeObserver()
        }
        binding = newBinding
        if !reusesObservation {
            installObserver()
        }
        synchronizeExternalValue(FluentDependencyTracking.withoutTracking { newBinding.get() })
    }

    func publishCurrentValue() {
        cancelScheduledPublication()
        publishFieldValue()
    }

    func scheduleCurrentValuePublication() {
        guard let field else { return }
        observeEditorChanges()
        let change = FluentTextEditingChange(text: field.stringValue,
            isComposing: (field.currentEditor() as? NSTextView)?.hasMarkedText() == true)
        if change != lastEditingChange {
            lastEditingChange = change
            binding.textInputConfiguration.onEditingChange?(change)
        }
        // Coalesce model writes, but never lose the latest composition event in the same turn.
        guard !publicationScheduled else { return }
        publicationScheduled = true
        let publication = publicationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.publicationScheduled,
                  publication == self.publicationGeneration else { return }
            self.publicationScheduled = false
            self.publishFieldValue()
        }
    }

    private func publishFieldValue() {
        guard let field else { return }
        let editor = field.currentEditor() as? NSTextView
        if let pendingExternalValue {
            guard editor?.hasMarkedText() != true else { return }
            self.pendingExternalValue = nil
            applyExternalValue(pendingExternalValue, to: field)
            return
        }
        // A closure binding may have changed without an observation callback.
        let modelValue = modelValue()
        if let lastModelValue, modelValue != lastModelValue {
            synchronizeExternalValue(modelValue)
            return
        }
        if binding.textInputConfiguration.commitPolicy == .committedText,
           editor?.hasMarkedText() == true { return }
        let value = field.stringValue
        lastModelValue = value
        guard modelValue != value else { return }
        isPublishing = true
        binding.set(value)
        isPublishing = false
        // A validating setter can transform the value synchronously.
        synchronizeExternalValue(self.modelValue())
    }

    private func cancelScheduledPublication() {
        publicationGeneration &+= 1
        publicationScheduled = false
    }

    private func installObserver() {
        subscriptionGeneration &+= 1
        let subscription = subscriptionGeneration
        observerID = binding.observe { [weak self] value in
            self?.receiveExternalValue(value, subscription: subscription)
        }
    }

    private func receiveExternalValue(_ value: String, subscription: UInt) {
        deliveryGeneration &+= 1
        let delivery = deliveryGeneration
        let apply = { [weak self] in
            guard let self,
                  subscription == self.subscriptionGeneration,
                  delivery == self.deliveryGeneration,
                  self.modelValue() == value else { return }
            self.synchronizeExternalValue(value, force: true)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func synchronizeExternalValue(_ value: String, force: Bool = false) {
        guard !isPublishing, let field else { return }
        guard force || lastModelValue != value else { return }
        lastModelValue = value
        cancelScheduledPublication()
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() == true {
            // External updates win after the composition ends; do not interrupt the IME.
            pendingExternalValue = value
            return
        }
        pendingExternalValue = nil
        applyExternalValue(value, to: field)
    }

    private func applyExternalValue(_ value: String, to field: NSTextField) {
        let editor = field.currentEditor() as? NSTextView
        let selection = editor?.selectedRange()
        if field.stringValue != value { field.stringValue = value }
        if let editor, editor.string != value { editor.string = value }
        if let editor, let selection {
            let length = value.utf16.count
            let location = min(selection.location, length)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        }
    }

    private func observeEditorChanges() {
        guard let editor = field?.currentEditor() as? NSTextView, editor !== observedEditor else { return }
        removeEditorObservers()
        observedEditor = editor
        editorObservers.append(NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: editor, queue: .main) { [weak self] _ in
            self?.scheduleCurrentValuePublication()
        })
        // AppKit can update the field editor during undo/redo without forwarding a control
        // delegate change. Listen to this editor's undo manager, never all application edits.
        if let undoManager = editor.undoManager {
            for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                editorObservers.append(NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                    self?.scheduleCurrentValuePublication()
                })
            }
        }
    }

    private func removeEditorObservers() {
        editorObservers.forEach(NotificationCenter.default.removeObserver)
        editorObservers.removeAll()
        observedEditor = nil
    }

    private func modelValue() -> String { FluentDependencyTracking.withoutTracking { binding.get() } }

    private func removeObserver() {
        subscriptionGeneration &+= 1
        deliveryGeneration &+= 1
        if let observerID { binding.removeObserver(observerID) }
        observerID = nil
    }

    deinit {
        editingObservers.forEach(NotificationCenter.default.removeObserver)
        removeEditorObservers()
        cancelScheduledPublication()
        removeObserver()
    }
}

public final class FluentBoundTextField: NSView {
    public var theme: FluentTheme = .current { didSet { field.theme = theme } }
    public let field: FluentTextField
    private var bindingCoordinator: FluentStringBindingCoordinator!
    var binding: FluentBinding<String> { bindingCoordinator.currentBinding }

    public init(_ binding: FluentBinding<String>, placeholder: String = "", observable: FluentObservable<String>? = nil) {
        field = FluentTextField(placeholder: placeholder)
        super.init(frame: .zero)
        addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        field.target = self
        field.action = #selector(commitValue)
        field.delegate = self
        bindingCoordinator = FluentStringBindingCoordinator(field: field, binding: binding)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func commitValue() { bindingCoordinator.publishCurrentValue() }

    func update(binding: FluentBinding<String>, theme: FluentTheme) {
        bindingCoordinator.update(binding: binding)
        if self.theme != theme { self.theme = theme }
    }
}

extension FluentBoundTextField: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        bindingCoordinator.scheduleCurrentValuePublication()
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        bindingCoordinator.publishCurrentValue()
    }
}

public final class FluentBoundToggle: NSView {
    public let toggle: FluentToggle
    var binding: FluentBinding<Bool>
    private var observer: UUID?
    private var isApplyingBinding = false
    private var subscriptionGeneration: UInt = 0

    public init(_ binding: FluentBinding<Bool>, title: String = "Toggle") {
        self.binding = binding
        toggle = FluentToggle(title: title, isOn: binding.get())
        super.init(frame: .zero)
        addSubview(toggle)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: leadingAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggle.topAnchor.constraint(equalTo: topAnchor),
            toggle.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        toggle.onValueChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.binding.set(value)
        }
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        binding: FluentBinding<Bool>,
        theme: FluentTheme,
        reduceMotion: Bool,
        layoutDirection: FluentLayoutDirection
    ) {
        let reusesObservation = self.binding.observationIdentity != nil
            && self.binding.observationIdentity == binding.observationIdentity
        if !reusesObservation { removeObserver() }
        self.binding = binding
        if toggle.theme != theme { toggle.theme = theme }
        if toggle.reduceMotion != reduceMotion { toggle.reduceMotion = reduceMotion }
        if toggle.fluentLayoutDirection != layoutDirection {
            toggle.fluentLayoutDirection = layoutDirection
        }
        let value = binding.get()
        if toggle.isOn != value { toggle.setStateFromBinding(value) }
        if !reusesObservation { installObserver() }
    }

    private func installObserver() {
        subscriptionGeneration &+= 1
        let subscription = subscriptionGeneration
        observer = binding.observe { [weak self] value in
            let apply = { [weak self] in
                guard let self,
                      subscription == self.subscriptionGeneration,
                      self.toggle.isOn != value else { return }
                self.isApplyingBinding = true
                self.toggle.setStateFromBinding(value)
                self.isApplyingBinding = false
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    private func removeObserver() {
        subscriptionGeneration &+= 1
        if let observer { binding.removeObserver(observer) }
        observer = nil
    }

    deinit { removeObserver() }
}

public final class FluentBoundSlider: NSView {
    public let slider: FluentSlider
    var binding: FluentBinding<Double>
    private var observer: UUID?
    private var isApplyingBinding = false
    private var observedBinding: FluentBinding<Double>?
    private var observedBindingIdentity: ObjectIdentifier?
    private var subscriptionGeneration: UInt64 = 0
    private var latestValueGeneration: UInt64 = 0
    private var lastLocallyWrittenValue: Double?

    public init(_ binding: FluentBinding<Double>, range: ClosedRange<Double> = 0...1) {
        self.binding = binding
        slider = FluentSlider(value: binding.get(), range: range)
        super.init(frame: .zero)
        addSubview(slider)
        slider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.topAnchor.constraint(equalTo: topAnchor),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        slider.onValueChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.lastLocallyWrittenValue = value
            self.binding.set(value)
        }
        installObserver()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        binding: FluentBinding<Double>,
        theme: FluentTheme,
        reduceMotion: Bool,
        layoutDirection: FluentLayoutDirection
    ) {
        let reusesObservation = observer != nil
            && binding.observationIdentity != nil
            && binding.observationIdentity == observedBindingIdentity
        self.binding = binding
        if slider.theme != theme { slider.theme = theme }
        if slider.reduceMotion != reduceMotion { slider.reduceMotion = reduceMotion }
        if slider.fluentLayoutDirection != layoutDirection {
            slider.fluentLayoutDirection = layoutDirection
        }
        let value = binding.get()
        if slider.value != value { applyExternalValue(value) }
        if !reusesObservation { installObserver() }
    }

    private func installObserver() {
        removeObserver()
        observedBinding = binding
        observedBindingIdentity = binding.observationIdentity
        subscriptionGeneration &+= 1
        let subscription = subscriptionGeneration
        observer = binding.observe? { [weak self] value in
            self?.enqueueObservedValue(value, subscription: subscription)
        }
    }

    private func enqueueObservedValue(_ value: Double, subscription: UInt64) {
        latestValueGeneration &+= 1
        let valueGeneration = latestValueGeneration
        let apply = { [weak self] in
            guard let self,
                  self.subscriptionGeneration == subscription,
                  self.latestValueGeneration == valueGeneration else { return }
            if self.slider.value == value {
                if self.lastLocallyWrittenValue == value { self.lastLocallyWrittenValue = nil }
                return
            }
            self.applyExternalValue(value)
        }
        if Thread.isMainThread {
            // Defer out of the binding notification while generation checks discard older drag
            // samples that were superseded in the same run-loop turn.
            DispatchQueue.main.async(execute: apply)
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func applyExternalValue(_ value: Double) {
        isApplyingBinding = true
        slider.setValueFromBinding(value, cancelInteraction: true)
        isApplyingBinding = false
        lastLocallyWrittenValue = nil
    }

    private func removeObserver() {
        subscriptionGeneration &+= 1
        if let observer { observedBinding?.removeObserver?(observer) }
        observer = nil
        observedBinding = nil
        observedBindingIdentity = nil
    }

    deinit {
        removeObserver()
    }
}

public final class FluentBoundCheckBox: NSView {
    public let checkBox: FluentCheckBox
    private var binding: FluentBinding<Bool>
    private var observer: UUID?
    private var isApplyingBinding = false

    public init(_ binding: FluentBinding<Bool>, title: String = "Check box") {
        self.binding = binding
        checkBox = FluentCheckBox(title: title, isChecked: binding.get())
        super.init(frame: .zero)
        addSubview(checkBox)
        checkBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            checkBox.topAnchor.constraint(equalTo: topAnchor),
            checkBox.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        checkBox.onValueChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.binding.set(value)
        }
        installObserver()
    }

    public override var intrinsicContentSize: NSSize { checkBox.intrinsicContentSize }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        binding: FluentBinding<Bool>,
        theme: FluentTheme,
        reduceMotion: Bool,
        layoutDirection: FluentLayoutDirection
    ) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        checkBox.theme = theme
        checkBox.reduceMotion = reduceMotion
        checkBox.fluentLayoutDirection = layoutDirection
        let value = binding.get()
        if checkBox.isChecked != value {
            isApplyingBinding = true
            checkBox.setStateFromBinding(value)
            isApplyingBinding = false
        }
        installObserver()
    }

    private func installObserver() {
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.checkBox.isChecked != value else { return }
                self.isApplyingBinding = true
                self.checkBox.setStateFromBinding(value)
                self.isApplyingBinding = false
            }
        }
    }

    deinit {
        if let observer { binding.removeObserver?(observer) }
    }
}

public final class FluentBoundRadioButton: NSView {
    public let radioButton: FluentRadioButton
    private var binding: FluentBinding<Bool>
    private var observer: UUID?
    private var isApplyingBinding = false

    public init(
        _ binding: FluentBinding<Bool>,
        title: String = "Radio button",
        groupName: String? = nil
    ) {
        self.binding = binding
        radioButton = FluentRadioButton(
            title: title,
            isSelected: binding.get(),
            groupName: groupName
        )
        super.init(frame: .zero)
        addSubview(radioButton)
        radioButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            radioButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            radioButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            radioButton.topAnchor.constraint(equalTo: topAnchor),
            radioButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        radioButton.onValueChanged = { [weak self] value in
            guard let self, !self.isApplyingBinding else { return }
            self.binding.set(value)
        }
        installObserver()
    }

    public override var intrinsicContentSize: NSSize { radioButton.intrinsicContentSize }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        binding: FluentBinding<Bool>,
        theme: FluentTheme,
        reduceMotion: Bool,
        layoutDirection: FluentLayoutDirection,
        groupName: String? = nil
    ) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        radioButton.theme = theme
        radioButton.reduceMotion = reduceMotion
        radioButton.fluentLayoutDirection = layoutDirection
        radioButton.groupName = groupName
        let value = binding.get()
        if radioButton.isSelected != value {
            isApplyingBinding = true
            radioButton.setStateFromBinding(value)
            isApplyingBinding = false
        }
        installObserver()
    }

    private func installObserver() {
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.radioButton.isSelected != value else { return }
                self.isApplyingBinding = true
                self.radioButton.setStateFromBinding(value)
                self.isApplyingBinding = false
            }
        }
    }

    deinit {
        if let observer { binding.removeObserver?(observer) }
    }
}

public extension FluentBoundTextField {
    @discardableResult
    func textFieldStyle(_ style: any FluentTextFieldStyle) -> FluentBoundTextField {
        field.fluentStyle = style
        return self
    }
}

public extension FluentBoundToggle {
    @discardableResult
    func toggleStyle(_ style: any FluentToggleStyle) -> FluentBoundToggle {
        toggle.fluentStyle = style
        return self
    }
}

public extension FluentBoundSlider {
    @discardableResult
    func sliderStyle(_ style: any FluentSliderStyle) -> FluentBoundSlider {
        slider.fluentStyle = style
        return self
    }
}

public extension FluentBoundCheckBox {
    @discardableResult
    func checkBoxStyle(_ style: any FluentCheckBoxStyle) -> FluentBoundCheckBox {
        checkBox.fluentStyle = style
        invalidateIntrinsicContentSize()
        return self
    }
}

public extension FluentBoundRadioButton {
    @discardableResult
    func radioButtonStyle(_ style: any FluentRadioButtonStyle) -> FluentBoundRadioButton {
        radioButton.fluentStyle = style
        invalidateIntrinsicContentSize()
        return self
    }
}
