import AppKit
import ScreenCaptureKit
import FluentKit

@MainActor
final class Recorder: NSObject, NSApplicationDelegate, SCRecordingOutputDelegate {
    var window: NSWindow!
    var stream: SCStream?
    var finished = false
    var recordingError: Error?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await record() }
            catch { print("RECORDING FAILED: \(error)") }
            window?.orderOut(nil)
            NSApp.terminate(nil)
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.finished = true }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.recordingError = error; self.finished = true }
    }

    func record() async throws {
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 600, height: 200),
            styleMask: [.closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "FluentKit Tooltip Recording"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        window.contentView = root
        let header = NSView(frame: NSRect(x: 0, y: 168, width: 600, height: 32))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        root.addSubview(header)
        let appearance = FluentAppearanceCoordinator(theme: .custom(colorScheme: .dark))
        appearance.attach(to: window)
        window.applyFluentWindowControlsStyle(.windows, titleBarHeight: 32, hostedIn: header)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.layoutSubtreeIfNeeded()
        let controls = header.subviews.first { $0.identifier?.rawValue == "FluentKit.WindowControls.Windows" }!
        let hosts = controls.subviews.filter { $0.identifier?.rawValue == "FluentKit.ToolTip.Anchor" }
        precondition(hosts.count == 3)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Current-process sharing exposes only capture content available to this diagnostic app
        // without requesting access to other applications or to the user's desktop.
        let available = try await SCShareableContent.currentProcess
        let ownWindow = available.windows.first { $0.windowID == CGWindowID(window.windowNumber) }!
        let ownApplication = ownWindow.owningApplication!
        let display = available.displays.first { $0.frame.intersects(ownWindow.frame) }!
        let filter = SCContentFilter(display: display, including: [ownApplication], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: ownWindow.frame.maxX - display.frame.minX - 270,
            y: ownWindow.frame.minY - display.frame.minY, width: 290, height: 120)
        configuration.width = Int(290 * filter.pointPixelScale)
        configuration.height = Int(120 * filter.pointPixelScale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.includeChildWindows = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        // ScreenCaptureKit's backgroundColor property is assign rather than retain.
        let captureBackground = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        configuration.backgroundColor = captureBackground
        defer { withExtendedLifetime(captureBackground) {} }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        self.stream = stream
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        recording.videoCodecType = .h264
        recording.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        var active: Int?
        func event(_ host: NSView, x: CGFloat = 20, y: CGFloat = 16) -> NSEvent {
            NSEvent.mouseEvent(with: .mouseMoved, location: host.convert(NSPoint(x: x, y: y), to: nil),
                modifierFlags: [], timestamp: Date.timeIntervalSinceReferenceDate, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        }
        func enter(_ index: Int) {
            if let active {
                hosts[active].subviews.first?.mouseExited(with: event(hosts[active], x: -50, y: 60))
                hosts[active].mouseExited(with: event(hosts[active], x: -50, y: 60))
            }
            hosts[index].subviews.first?.mouseEntered(with: event(hosts[index]))
            hosts[index].mouseEntered(with: event(hosts[index]))
            active = index
        }
        try await Task.sleep(nanoseconds: 350_000_000)
        for (index, seconds) in [(0,1.7), (1,0.8), (2,0.8), (1,0.6), (0,0.7), (2,0.08), (0,0.9), (1,0.6), (2,0.8), (0,0.7)] {
            enter(index)
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        if let active {
            let outside = event(hosts[active], x: -400, y: 150)
            hosts[active].subviews.first?.mouseExited(with: outside)
            hosts[active].mouseExited(with: outside)
        }
        try await Task.sleep(nanoseconds: 900_000_000)
        try await stream.stopCapture()
        for _ in 0..<100 where !finished { try await Task.sleep(nanoseconds: 50_000_000) }
        if let recordingError { throw recordingError }
        guard finished else { throw NSError(domain: "TooltipRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording did not finish"]) }
        print("Recorded \(output.recordedDuration.seconds) seconds: \(recording.outputURL.path)")
    }
}

@main struct TooltipRecording {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let recorder = Recorder()
        app.delegate = recorder
        app.run()
        withExtendedLifetime(recorder) {}
    }
}
