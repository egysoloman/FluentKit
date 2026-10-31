import XCTest
@testable import FluentKit

final class TitleBarButtonTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor private func make(_ action: @escaping () -> Void) throws -> (NSView, NSButton) {
        _ = NSApplication.shared
        let native = FluentTitleBar(title:"Settings", heightMode:.expanded, isBackButtonVisible:true, onBack:action)._makeView(in:.init(reduceMotion:true))
        native.frame = NSRect(x:0,y:0,width:600,height:48); native.layoutSubtreeIfNeeded()
        return (native, try XCTUnwrap(descendants(native).first { $0.identifier?.rawValue == "FluentKit.TitleBar.Back" } as? NSButton))
    }
    private func key(_ code: UInt16, up: Bool = false, repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with:up ? .keyUp:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:code == 49 ? " ":"\r",charactersIgnoringModifiers:code == 49 ? " ":"\r",isARepeat:repeatKey,keyCode:code)!
    }
    @MainActor func testSpaceInvokesOnceOnReleaseAndIgnoresRepeat() throws {
        var count = 0; let (host, back) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        back.keyDown(with:key(49)); back.keyDown(with:key(49,repeatKey:true))
        XCTAssertEqual(count,0)
        back.keyUp(with:key(49,up:true)); XCTAssertEqual(count,1)
        back.keyUp(with:key(49,up:true)); XCTAssertEqual(count,1)
    }
    @MainActor func testReturnDoesNotRepeatNavigation() throws {
        var count = 0; let (host, back) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        back.keyDown(with:key(36)); back.keyDown(with:key(36,repeatKey:true)); XCTAssertEqual(count,1)
    }
    @MainActor func testHiddenAncestorCannotBeInvokedByAccessibility() throws {
        var count = 0; let (host, back) = try make { count += 1 }
        host.isHidden = true
        XCTAssertFalse(back.accessibilityPerformPress()); XCTAssertEqual(count,0)
    }
    private func mouse(_ type: NSEvent.EventType, in button: NSView, inside: Bool = true) -> NSEvent {
        let point = button.convert(NSPoint(x: inside ? button.bounds.midX : -12, y: button.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:0,windowNumber:button.window?.windowNumber ?? 0,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    }
    @MainActor func testDragOutsideCancelsAndReenterRearmsBeforeRelease() throws {
        var count = 0; let (host, native) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        let back = try XCTUnwrap(native as? FluentTitleBarButton)
        let frame = back.frame
        back.mouseDown(with:mouse(.leftMouseDown,in:back)); XCTAssertTrue(back.pressed)
        XCTAssertEqual(back.glyphHeadOffset,3); XCTAssertEqual(back.glyphTailOffset,0.938/3,accuracy:0.0001)
        XCTAssertEqual(back.frame,frame,"Only the arrow changes, not the hit target")
        back.mouseDragged(with:mouse(.leftMouseDragged,in:back,inside:false)); XCTAssertFalse(back.pressed)
        back.mouseUp(with:mouse(.leftMouseUp,in:back,inside:false)); XCTAssertEqual(count,0); XCTAssertFalse(back.pointerOver)
        back.mouseDown(with:mouse(.leftMouseDown,in:back))
        back.mouseDragged(with:mouse(.leftMouseDragged,in:back,inside:false))
        back.mouseDragged(with:mouse(.leftMouseDragged,in:back)); XCTAssertTrue(back.pressed)
        back.mouseUp(with:mouse(.leftMouseUp,in:back)); XCTAssertEqual(count,1); XCTAssertFalse(back.pressed)
        back.mouseUp(with:mouse(.leftMouseUp,in:back)); XCTAssertEqual(count,1)
    }
    @MainActor func testHidingAndRedisplayingClearsHoverAndCapturedPress() throws {
        var count = 0; let (host, native) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        let back = try XCTUnwrap(native as? FluentTitleBarButton)
        back.mouseDown(with:mouse(.leftMouseDown,in:back))
        back.isHidden = true; back.isHidden = false
        XCTAssertFalse(back.pointerOver); XCTAssertFalse(back.pressed); XCTAssertEqual(back.glyphHeadOffset,0)
        back.mouseUp(with:mouse(.leftMouseUp,in:back)); XCTAssertEqual(count,0)
    }
    @MainActor func testDisableDuringSpacePressCancelsPendingAction() throws {
        var count = 0; let (host, native) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        let back = try XCTUnwrap(native as? FluentTitleBarButton)
        back.keyDown(with:key(49)); back.isEnabled = false; back.isEnabled = true
        back.keyUp(with:key(49,up:true)); XCTAssertEqual(count,0); XCTAssertFalse(back.pressed)
    }
    @MainActor func testEscapeAndFocusLossCancelPendingSpace() throws {
        var count = 0; let (host, back) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        back.keyDown(with:key(49)); back.keyDown(with:key(53)); back.keyUp(with:key(49,up:true))
        back.keyDown(with:key(49)); _ = back.resignFirstResponder(); back.keyUp(with:key(49,up:true))
        XCTAssertEqual(count,0)
    }
    @MainActor func testDisabledAndHiddenProgrammaticInvocationDoesNothing() throws {
        var count = 0; let (host, back) = try make { count += 1 }
        back.isEnabled = false; back.performClick(nil); XCTAssertFalse(back.accessibilityPerformPress())
        back.isEnabled = true; host.isHidden = true; back.performClick(nil)
        XCTAssertEqual(count,0)
        host.isHidden = false; XCTAssertTrue(back.accessibilityPerformPress()); XCTAssertEqual(count,1)
    }
    @MainActor func testCompactExpandedAndRTLKeepWinUICaptionButtonGeometry() throws {
        _ = NSApplication.shared
        for rtl in [false,true] { for height: CGFloat in [32,48] {
            let view = FluentTitleBar(title:"Settings",heightMode:.fixed(height),isBackButtonVisible:true)
                ._makeView(in:.init(reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight))
            view.frame = NSRect(x:0,y:0,width:600,height:height); view.layoutSubtreeIfNeeded()
            let back = try XCTUnwrap(descendants(view).first { $0.identifier?.rawValue == "FluentKit.TitleBar.Back" })
            XCTAssertEqual(back.frame.width,40); XCTAssertEqual(back.frame.height,height-4)
            XCTAssertEqual(back.frame.minY,2); XCTAssertEqual(back.frame.minX,rtl ? 558:2)
        }}
    }
    @MainActor func testWindowDeactivationCancelsCapturedPress() throws {
        var count = 0; let (host, native) = try make { count += 1 }; defer { withExtendedLifetime(host) {} }
        let back = try XCTUnwrap(native as? FluentTitleBarButton)
        back.mouseDown(with:mouse(.leftMouseDown,in:back))
        back.update(theme:.current,layoutDirection:.leftToRight,isActive:false,reduceMotion:true,isEnabled:true,accessibilityValue:nil)
        back.mouseUp(with:mouse(.leftMouseUp,in:back))
        XCTAssertEqual(count,0); XCTAssertFalse(back.pressed); XCTAssertFalse(back.pointerOver)
    }
    @MainActor func testAnimatedPressSettlesAndHiddenButtonCancelsTimer() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:80),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let host = FluentTitleBar(title:"Settings",isBackButtonVisible:true,extendsIntoWindowChrome:false)
            ._makeView(in:.init(reduceMotion:false))
        window.contentView = host; window.makeKeyAndOrderFront(nil); host.layoutSubtreeIfNeeded()
        let back = try XCTUnwrap(descendants(host).first { $0.identifier?.rawValue == "FluentKit.TitleBar.Back" } as? FluentTitleBarButton)
        back.keyDown(with:key(49))
        RunLoop.current.run(until:Date().addingTimeInterval(0.25))
        XCTAssertEqual(back.glyphHeadOffset,3,accuracy:0.001)
        back.keyUp(with:key(49,up:true))
        RunLoop.current.run(until:Date().addingTimeInterval(0.4))
        XCTAssertEqual(back.glyphHeadOffset,0,accuracy:0.001)
        back.keyDown(with:key(49)); back.isHidden = true
        RunLoop.current.run(until:Date().addingTimeInterval(0.25))
        XCTAssertEqual(back.glyphHeadOffset,0); XCTAssertFalse(back.pressed)
    }
}
