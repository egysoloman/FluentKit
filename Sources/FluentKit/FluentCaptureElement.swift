import AppKit
import AVFoundation

/// How a CaptureElement fills its bounds (`Stretch`).
public enum FluentCaptureStretch: Hashable, Sendable {
    case uniform
    case uniformToFill
    case fill

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .uniform: return .resizeAspect
        case .uniformToFill: return .resizeAspectFill
        case .fill: return .resize
        }
    }
}

/// A camera feed for a CaptureElement (WinUI's `MediaCapture` + `MediaPlayerElement` preview).
/// Apps must provide `NSCameraUsageDescription` and, when sandboxed, the camera entitlement.
public final class FluentCameraCapture {
    public struct Device: Hashable, Sendable {
        public let id: String
        public let name: String
    }

    public let session = AVCaptureSession()
    public private(set) var activeDevice: Device?

    public init() {}

    public static var authorizationStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    /// Asks for camera access; the completion runs on the main queue.
    public static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in DispatchQueue.main.async { completion(granted) } }
    }

    public static var devices: [Device] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14, *) { types.append(.external) } else { types.append(.externalUnknown) }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
            .devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    public enum CaptureError: Error {
        case notAuthorized
        case noCamera
        case cannotAddInput
    }

    /// Configures the session with the given (or default) camera and starts it off the main thread.
    public func start(deviceID: String? = nil) throws {
        guard Self.authorizationStatus == .authorized else { throw CaptureError.notAuthorized }
        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw CaptureError.noCamera }
        let input = try AVCaptureDeviceInput(device: device)
        let session = self.session
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CaptureError.cannotAddInput
        }
        session.addInput(input)
        session.commitConfiguration()
        activeDevice = Device(id: device.uniqueID, name: device.localizedName)
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    public func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}

/// A camera preview surface (the Gallery's "Capture Element / Camera Preview"). Shows the session's
/// video through `AVCaptureVideoPreviewLayer`; without a session the placeholder is shown.
public struct FluentCaptureElement: FluentUpdatablePrimitiveView {
    private let session: AVCaptureSession?
    private let stretch: FluentCaptureStretch
    private let isMirrored: Bool
    private let placeholder: FluentAnyView?

    public init(session: AVCaptureSession?, stretch: FluentCaptureStretch = .uniform, isMirrored: Bool = true,
                placeholder: FluentAnyView? = nil) {
        self.session = session
        self.stretch = stretch
        self.isMirrored = isMirrored
        self.placeholder = placeholder
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentCaptureElementView()
        view.update(session: session, stretch: stretch, isMirrored: isMirrored, placeholder: placeholder, context: context)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let view = view as? FluentCaptureElementView else { return false }
        view.update(session: session, stretch: stretch, isMirrored: isMirrored, placeholder: placeholder, context: context)
        return true
    }
}

final class FluentCaptureElementView: NSView {
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private(set) var placeholderHost: FluentViewHost<FluentAnyView>?
    private var isMirrored = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.CaptureElement")
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        fluentSetDefaultAccessibilityLabel("Camera preview")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 240) }

    func update(session: AVCaptureSession?, stretch: FluentCaptureStretch, isMirrored: Bool, placeholder: FluentAnyView?,
                context: FluentRenderContext) {
        self.isMirrored = isMirrored
        if previewLayer?.session !== session {
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
            if let session {
                let preview = AVCaptureVideoPreviewLayer(session: session)
                layer?.addSublayer(preview)
                previewLayer = preview
            }
        }
        previewLayer?.videoGravity = stretch.videoGravity
        applyMirroring()
        if previewLayer == nil, let placeholder {
            if let placeholderHost { placeholderHost.update(placeholder, context: context) } else {
                let host = FluentViewHost(placeholder, context: context)
                host.translatesAutoresizingMaskIntoConstraints = true
                addSubview(host)
                placeholderHost = host
            }
        } else {
            placeholderHost?.removeFromSuperview()
            placeholderHost = nil
        }
        needsLayout = true
    }

    private func applyMirroring() {
        guard let connection = previewLayer?.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isMirrored
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
        placeholderHost?.frame = bounds
        applyMirroring()
    }
}
