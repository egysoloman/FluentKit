import AppKit
import ObjectiveC

/// Chooses the placement and visual language of a window's system controls.
///
/// `.macOS` keeps AppKit's native traffic lights on the leading edge. `.windows`
/// hides those buttons and installs Minimize, Maximize/Restore, and Close on the
/// trailing edge while still routing every command through `NSWindow`.
public enum FluentWindowControlsStyle: String, CaseIterable, Hashable, Sendable {
    case macOS
    case windows

    static let windowsControlWidth: CGFloat = 46
    static let windowsControlCount: CGFloat = 3

    var trailingTitleBarInset: CGFloat {
        self == .windows ? Self.windowsControlWidth * Self.windowsControlCount : 0
    }
}

private var fluentWindowControlsCoordinatorKey: UInt8 = 0

public extension NSWindow {
    /// Applies a FluentKit system-control style to this window. Reapplying another
    /// style is supported and restores the native buttons when returning to macOS.
    func applyFluentWindowControlsStyle(
        _ style: FluentWindowControlsStyle,
        titleBarHeight: CGFloat? = nil,
        hostedIn controlsHost: NSView? = nil
    ) {
        let coordinator: FluentWindowControlsCoordinator
        if let existing = objc_getAssociatedObject(
            self,
            &fluentWindowControlsCoordinatorKey
        ) as? FluentWindowControlsCoordinator {
            coordinator = existing
        } else {
            coordinator = FluentWindowControlsCoordinator(window: self)
            objc_setAssociatedObject(
                self,
                &fluentWindowControlsCoordinatorKey,
                coordinator,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        coordinator.apply(
            style,
            titleBarHeight: titleBarHeight,
            controlsHost: controlsHost
        )
    }

    var fluentWindowControlsStyle: FluentWindowControlsStyle {
        (objc_getAssociatedObject(
            self,
            &fluentWindowControlsCoordinatorKey
        ) as? FluentWindowControlsCoordinator)?.style ?? .macOS
    }
}

private final class FluentWindowControlsCoordinator: NSObject {
    private weak var window: NSWindow?
    private var accessoryController: NSTitlebarAccessoryViewController?
    private var controlsView: FluentWindowsWindowControlsView?
    private var originalButtonVisibility: [NSWindow.ButtonType: Bool] = [:]
    private var observers: [NSObjectProtocol] = []
    private(set) var style: FluentWindowControlsStyle = .macOS

    init(window: NSWindow) {
        self.window = window
        super.init()
        for type in Self.nativeButtonTypes {
            if let button = window.standardWindowButton(type) {
                originalButtonVisibility[type] = button.isHidden
            }
        }
    }

    func apply(
        _ style: FluentWindowControlsStyle,
        titleBarHeight: CGFloat?,
        controlsHost: NSView?
    ) {
        self.style = style
        switch style {
        case .macOS:
            removeWindowsControls()
            restoreNativeControls()
        case .windows:
            hideNativeControls()
            installWindowsControlsIfNeeded(
                titleBarHeight: titleBarHeight,
                controlsHost: controlsHost
            )
        }
    }

    private func hideNativeControls() {
        guard let window else { return }
        for type in Self.nativeButtonTypes {
            window.standardWindowButton(type)?.isHidden = true
        }
    }

    private func restoreNativeControls() {
        guard let window else { return }
        for type in Self.nativeButtonTypes {
            window.standardWindowButton(type)?.isHidden = originalButtonVisibility[type] ?? false
        }
    }

    private func installWindowsControlsIfNeeded(
        titleBarHeight: CGFloat?,
        controlsHost requestedHost: NSView?
    ) {
        guard let window else { return }
        let controls: FluentWindowsWindowControlsView
        if let controlsView {
            controls = controlsView
            controls.updateTitleBarHeight(titleBarHeight)
        } else {
            controls = FluentWindowsWindowControlsView(
                window: window,
                titleBarHeight: titleBarHeight
            )
            controlsView = controls
            installObservers(for: controls, window: window)
        }

        if let requestedHost {
            removeAccessoryController()
            if controls.superview !== requestedHost {
                controls.removeFromSuperview()
                controls.translatesAutoresizingMaskIntoConstraints = false
                requestedHost.addSubview(controls)
                NSLayoutConstraint.activate([
                    controls.topAnchor.constraint(equalTo: requestedHost.topAnchor),
                    controls.trailingAnchor.constraint(equalTo: requestedHost.trailingAnchor),
                    controls.bottomAnchor.constraint(equalTo: requestedHost.bottomAnchor),
                    controls.widthAnchor.constraint(
                        equalToConstant: FluentWindowControlsStyle.windows.trailingTitleBarInset
                    )
                ])
            }
            controls.refresh()
            return
        }

        if accessoryController == nil {
            controls.removeFromSuperview()
            let controller = NSTitlebarAccessoryViewController()
            controller.layoutAttribute = .right
            controller.view = controls
            controller.view.identifier = NSUserInterfaceItemIdentifier("FluentKit.WindowControls.Windows")
            controller.preferredContentSize = controls.intrinsicContentSize
            window.addTitlebarAccessoryViewController(controller)
            accessoryController = controller
        } else {
            accessoryController?.preferredContentSize = controls.intrinsicContentSize
        }
        controls.refresh()
    }

    private func installObservers(for controls: FluentWindowsWindowControlsView, window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) {
                [weak controls] _ in controls?.refresh()
            },
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) {
                [weak controls] _ in controls?.refresh()
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) {
                [weak controls] _ in controls?.refresh()
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) {
                [weak controls] _ in controls?.refresh()
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) {
                [weak controls] _ in controls?.refresh()
            }
        ]
    }

    private func removeWindowsControls() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        removeAccessoryController()
        controlsView?.removeFromSuperview()
        controlsView = nil
    }

    private func removeAccessoryController() {
        guard let window, let accessoryController,
              let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessoryController }) else {
            self.accessoryController = nil
            return
        }
        window.removeTitlebarAccessoryViewController(at: index)
        self.accessoryController = nil
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private static let nativeButtonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]
}

private final class FluentWindowsWindowControlsView: NSView {
    private static let defaultTitleBarHeight: CGFloat = 32
    private weak var targetWindow: NSWindow?
    private let minimizeButton: FluentWindowsCaptionButton
    private let maximizeButton: FluentWindowsCaptionButton
    private let closeButton: FluentWindowsCaptionButton

    private var titleBarHeight: CGFloat

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: FluentWindowControlsStyle.windows.trailingTitleBarInset,
            height: titleBarHeight
        )
    }

    init(window: NSWindow, titleBarHeight: CGFloat?) {
        targetWindow = window
        self.titleBarHeight = max(
            titleBarHeight ?? Self.defaultTitleBarHeight,
            Self.defaultTitleBarHeight
        )
        minimizeButton = FluentWindowsCaptionButton(kind: .minimize, window: window)
        maximizeButton = FluentWindowsCaptionButton(kind: .maximize, window: window)
        closeButton = FluentWindowsCaptionButton(kind: .close, window: window)
        super.init(frame: NSRect(origin: .zero, size: NSSize(
            width: FluentWindowControlsStyle.windows.trailingTitleBarInset,
            height: self.titleBarHeight
        )))
        identifier = NSUserInterfaceItemIdentifier("FluentKit.WindowControls.Windows")
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window controls")
        [minimizeButton, maximizeButton, closeButton].forEach(addSubview)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let width = FluentWindowControlsStyle.windowsControlWidth
        minimizeButton.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        maximizeButton.frame = NSRect(x: width, y: 0, width: width, height: bounds.height)
        closeButton.frame = NSRect(x: width * 2, y: 0, width: width, height: bounds.height)
    }

    func refresh() {
        guard let targetWindow else { return }
        minimizeButton.isEnabled = targetWindow.styleMask.contains(.miniaturizable)
        maximizeButton.isEnabled = targetWindow.styleMask.contains(.resizable)
        closeButton.isEnabled = targetWindow.styleMask.contains(.closable)
        maximizeButton.refreshWindowState()
        [minimizeButton, maximizeButton, closeButton].forEach { $0.needsDisplay = true }
    }

    func updateTitleBarHeight(_ requestedHeight: CGFloat?) {
        let next = max(requestedHeight ?? Self.defaultTitleBarHeight, Self.defaultTitleBarHeight)
        guard abs(next - titleBarHeight) > 0.5 else { return }
        titleBarHeight = next
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
}

private final class FluentWindowsCaptionButton: NSButton {
    enum Kind: Equatable {
        case minimize
        case maximize
        case close
    }

    private let kind: Kind
    private weak var targetWindow: NSWindow?
    private var pointerOver = false
    private var tracking: NSTrackingArea?

    init(kind: Kind, window: NSWindow) {
        self.kind = kind
        targetWindow = window
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        target = self
        action = #selector(invoke)
        let label: String
        switch kind {
        case .minimize:
            label = "Minimize"
        case .maximize:
            label = "Maximize"
        case .close:
            label = "Close"
        }
        identifier = NSUserInterfaceItemIdentifier("FluentKit.WindowControls.\(label)")
        setAccessibilityRole(.button)
        refreshWindowState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        pointerOver = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointerOver = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if pointerOver || isHighlighted {
            if kind == .close {
                NSColor(calibratedRed: 0.91, green: 0.15, blue: 0.14, alpha: 1).setFill()
            } else {
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
            }
            bounds.fill()
        }

        contentTintColor = kind == .close && pointerOver
            ? NSColor.white
            : (isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor)
        super.draw(dirtyRect)
    }

    func refreshWindowState() {
        let label: String
        let symbolName: String
        switch kind {
        case .minimize:
            label = "Minimize"
            symbolName = "minus"
        case .maximize where targetWindow?.isZoomed == true:
            label = "Restore"
            symbolName = "square.on.square"
        case .maximize:
            label = "Maximize"
            symbolName = "square"
        case .close:
            label = "Close"
            symbolName = "xmark"
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: label
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        setAccessibilityLabel(label)
        toolTip = label
        needsDisplay = true
    }

    @objc private func invoke() {
        guard let targetWindow else { return }
        pointerOver = false
        needsDisplay = true
        switch kind {
        case .minimize:
            targetWindow.performMiniaturize(self)
        case .maximize:
            targetWindow.performZoom(self)
            refreshWindowState()
        case .close:
            targetWindow.performClose(self)
        }
        DispatchQueue.main.async { [weak self] in
            self?.synchronizePointerOverWithCurrentMouseLocation()
        }
    }

    private func synchronizePointerOverWithCurrentMouseLocation() {
        guard let targetWindow, targetWindow.isVisible, window != nil else {
            pointerOver = false
            needsDisplay = true
            return
        }
        let pointInWindow = targetWindow.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(pointInWindow, from: nil)
        let next = bounds.contains(point)
        guard next != pointerOver else { return }
        pointerOver = next
        needsDisplay = true
    }
}
