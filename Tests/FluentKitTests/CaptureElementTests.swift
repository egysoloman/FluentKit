import XCTest
import AVFoundation
@testable import FluentKit

final class CaptureElementTests: XCTestCase {
    @MainActor
    func testPreviewLayerFollowsSessionStretchAndPlaceholder() throws {
        _ = NSApplication.shared
        let context = FluentRenderContext(reduceMotion: true)
        let empty = try XCTUnwrap(FluentCaptureElement(session: nil, placeholder: FluentAnyView(FluentText("Camera off")))
            ._makeView(in: context) as? FluentCaptureElementView)
        empty.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        empty.layoutSubtreeIfNeeded()
        XCTAssertNil(empty.previewLayer)
        XCTAssertEqual(empty.placeholderHost?.frame.size, NSSize(width: 320, height: 240))

        let session = AVCaptureSession()
        XCTAssertTrue(FluentCaptureElement(session: session, stretch: .uniformToFill)._updateView(empty, in: context))
        empty.layoutSubtreeIfNeeded()
        XCTAssertTrue(empty.previewLayer?.session === session)
        XCTAssertNil(empty.placeholderHost, "The placeholder goes away once a session is shown")
        XCTAssertEqual(empty.previewLayer?.videoGravity, .resizeAspectFill)
        XCTAssertEqual(empty.previewLayer?.frame, empty.bounds)
        let layer = empty.previewLayer
        XCTAssertTrue(FluentCaptureElement(session: session, stretch: .fill)._updateView(empty, in: context))
        XCTAssertTrue(empty.previewLayer === layer, "The same session keeps its preview layer")
        XCTAssertEqual(empty.previewLayer?.videoGravity, .resize)
        XCTAssertEqual(FluentCaptureStretch.uniform.videoGravity, .resizeAspect)
    }

    func testCaptureRefusesToStartWithoutAuthorization() {
        let capture = FluentCameraCapture()
        guard FluentCameraCapture.authorizationStatus != .authorized else { return }
        XCTAssertThrowsError(try capture.start()) { error in
            XCTAssertEqual(error as? FluentCameraCapture.CaptureError, .notAuthorized)
        }
        XCTAssertNil(capture.activeDevice)
    }
}
