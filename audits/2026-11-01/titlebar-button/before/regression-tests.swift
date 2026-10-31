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
}
