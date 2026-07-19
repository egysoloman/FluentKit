import AppKit

public final class FluentBoundTextField: NSView {
    public var theme: FluentTheme = .current { didSet { field.theme = theme } }
    public let field: FluentTextField
    var binding: FluentBinding<String>
    private var observer: UUID?

    public init(_ binding: FluentBinding<String>, placeholder: String = "", observable: FluentObservable<String>? = nil) {
        self.binding = binding
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
        if let observe = binding.observe {
            observer = observe { [weak self] value in
                guard let self, self.field.stringValue != value else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.field.window?.firstResponder !== self.field else { return }
                    self.field.stringValue = value
                }
            }
        }
        field.stringValue = binding.get()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func commitValue() { binding.set(field.stringValue) }

    func update(binding: FluentBinding<String>, theme: FluentTheme) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        self.theme = theme
        if field.window?.firstResponder !== field {
            let value = binding.get()
            if field.stringValue != value { field.stringValue = value }
        }
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.field.window?.firstResponder !== self.field else { return }
                self.field.stringValue = value
            }
        }
    }

    deinit {
        if let observer { binding.removeObserver?(observer) }
    }
}

extension FluentBoundTextField: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) { binding.set(field.stringValue) }
}

public final class FluentBoundToggle: NSView {
    public let toggle: FluentToggle
    var binding: FluentBinding<Bool>
    private var observer: UUID?
    private var isApplyingBinding = false

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
        if let observe = binding.observe {
            observer = observe { [weak self] value in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.toggle.isOn != value else { return }
                    self.isApplyingBinding = true
                    self.toggle.setStateFromBinding(value)
                    self.isApplyingBinding = false
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        binding: FluentBinding<Bool>,
        theme: FluentTheme,
        reduceMotion: Bool,
        layoutDirection: FluentLayoutDirection
    ) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        toggle.theme = theme
        toggle.reduceMotion = reduceMotion
        toggle.fluentLayoutDirection = layoutDirection
        let value = binding.get()
        if toggle.isOn != value { toggle.setStateFromBinding(value) }
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.toggle.isOn != value else { return }
                self.isApplyingBinding = true
                self.toggle.setStateFromBinding(value)
                self.isApplyingBinding = false
            }
        }
    }

    deinit {
        if let observer { binding.removeObserver?(observer) }
    }
}

public final class FluentBoundSlider: NSView {
    public let slider: FluentSlider
    var binding: FluentBinding<Double>
    private var observer: UUID?
    private var isApplyingBinding = false

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
            self.binding.set(value)
        }
        if let observe = binding.observe {
            observer = observe { [weak self] value in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.slider.value != value else { return }
                    self.isApplyingBinding = true
                    self.slider.value = value
                    self.isApplyingBinding = false
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(binding: FluentBinding<Double>, theme: FluentTheme) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        slider.theme = theme
        let value = binding.get()
        if slider.value != value { slider.value = value }
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.slider.value != value else { return }
                self.isApplyingBinding = true
                self.slider.value = value
                self.isApplyingBinding = false
            }
        }
    }

    deinit {
        if let observer { binding.removeObserver?(observer) }
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

    func update(binding: FluentBinding<Bool>, theme: FluentTheme) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        checkBox.theme = theme
        let value = binding.get()
        if checkBox.isChecked != value {
            isApplyingBinding = true
            checkBox.isChecked = value
            isApplyingBinding = false
        }
        installObserver()
    }

    private func installObserver() {
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.checkBox.isChecked != value else { return }
                self.isApplyingBinding = true
                self.checkBox.isChecked = value
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

    public init(_ binding: FluentBinding<Bool>, title: String = "Radio button") {
        self.binding = binding
        radioButton = FluentRadioButton(title: title, isSelected: binding.get())
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

    func update(binding: FluentBinding<Bool>, theme: FluentTheme) {
        if let observer { self.binding.removeObserver?(observer) }
        self.binding = binding
        radioButton.theme = theme
        let value = binding.get()
        if radioButton.isSelected != value {
            isApplyingBinding = true
            radioButton.isSelected = value
            isApplyingBinding = false
        }
        installObserver()
    }

    private func installObserver() {
        observer = binding.observe? { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.radioButton.isSelected != value else { return }
                self.isApplyingBinding = true
                self.radioButton.isSelected = value
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
