import XCTest
@testable import FluentKit

final class DirectTouchPointerFixture: NSEvent {
    var eventType: NSEvent.EventType = .leftMouseDown
    var point: NSPoint = .zero
    override var type: NSEvent.EventType { eventType }
    override var subtype: NSEvent.EventSubtype { .touch }
    override var associatedEventsMask: NSEvent.EventTypeMask { [.directTouch] }
    override var locationInWindow: NSPoint { point }
}

final class PointerDeviceRegressionTests: XCTestCase {
    private func trackpad(_ type: NSEvent.EventType) throws -> NSEvent {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with:type,location:.zero,modifierFlags:[],timestamp:0,
            windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)?.cgEvent)
        event.setIntegerValueField(.mouseEventSubtype,value:Int64(NSEvent.EventSubtype.touch.rawValue))
        return try XCTUnwrap(NSEvent(cgEvent:event))
    }
    func testTrackpadMouseSubtypeDoesNotMeanDirectScreenTouch() throws {
        _ = NSApplication.shared
        for type: NSEvent.EventType in [.leftMouseDown,.leftMouseUp,.leftMouseDragged,.rightMouseDown,.rightMouseUp,.otherMouseDown,.mouseMoved] {
            let event = try trackpad(type)
            XCTAssertEqual(event.subtype,.touch)
            XCTAssertFalse(FluentInputDeviceTracker.isTouch(event), "Trackpad \(type)")
            XCTAssertEqual(FluentInputDeviceTracker.deviceType(for:event),.mouse)
        }
    }
    @MainActor func testTrackpadOpensDesktopComboBoxAndMenuRows() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:100,y:200,width:400,height:300),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame:NSRect(x:20,y:200,width:180,height:32));window.contentView?.addSubview(anchor)
        window.orderFront(nil);defer { window.close() }
        let tracker = FluentInputDeviceTracker.shared
        tracker.record(try XCTUnwrap(FluentInputDeviceTracker.deviceType(for:trackpad(.leftMouseDown))),in:window)
        let popup = FluentComboBoxPopup(titles:["中文","英文"],selectedIndex:0,theme:.current,
            layoutDirection:.leftToRight,reduceMotion:true,onMove:{ _ in },onCommit:{ _ in },onDismiss:{})
        popup.present(relativeTo:anchor)
        XCTAssertEqual(popup.rowHeight,36)
        XCTAssertEqual(popup.presentedPanelSize?.width,180)
        popup.dismiss(animated:false)
        let menu = FluentMenuFlyout(items:[FluentMenuItem("中文") {},FluentMenuItem("英文") {}],reduceMotion:true)
        menu.present(relativeTo:anchor)
        XCTAssertEqual(menu.itemHeight,36)
        menu.dismiss(animated:false)
    }
    func testDirectEvidenceAndNonMouseEventsStayDistinct() {
        _ = NSApplication.shared
        let direct = DirectTouchPointerFixture()
        for type: NSEvent.EventType in [.leftMouseDown,.leftMouseUp,.leftMouseDragged,.directTouch] {
            direct.eventType = type
            XCTAssertTrue(FluentInputDeviceTracker.isTouch(direct))
            XCTAssertEqual(FluentInputDeviceTracker.deviceType(for:direct),.touch)
        }
        let entered = NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,
            windowNumber:0,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
        XCTAssertFalse(FluentInputDeviceTracker.isTouch(entered), "Never access mouse-only properties on tracking events")
        XCTAssertNil(FluentInputDeviceTracker.deviceType(for:entered))
    }
    @MainActor func testWindowRecordsDoNotLeakTouchDensityAcrossWindows() {
        _ = NSApplication.shared
        let first = NSWindow(contentRect:.zero,styleMask:[],backing:.buffered,defer:true)
        let second = NSWindow(contentRect:.zero,styleMask:[],backing:.buffered,defer:true)
        first.isReleasedWhenClosed = false; second.isReleasedWhenClosed = false
        defer { first.close(); second.close() }
        let tracker = FluentInputDeviceTracker.shared
        tracker.record(.touch,in:first)
        XCTAssertEqual(tracker.lastDeviceType(in:first),.touch)
        XCTAssertEqual(tracker.lastDeviceType(in:second),.none)
        XCTAssertEqual(tracker.deviceTypeForCurrentInteraction(in:second),.none)
        tracker.record(.pen,in:second)
        XCTAssertEqual(tracker.deviceTypeForCurrentInteraction(in:second),.pen)
        XCTAssertEqual(tracker.deviceTypeForCurrentInteraction(in:first),.touch)
    }

}
