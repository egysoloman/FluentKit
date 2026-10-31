import XCTest
@testable import FluentKit

final class MaterialResizeTests: XCTestCase {
    @MainActor func testMaterialSurfacesDoNotStartTheirOwnGeometryAnimationsDuringWindowLayout() throws {
        _ = NSApplication.shared
        for material in [FluentMaterial.mica, .nativeMica, .acrylic] {
            for enabled in [false,true] {
                let window = NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:200),styleMask:[.titled],backing:.buffered,defer:false)
                window.isReleasedWhenClosed = false
                let view = FluentMaterialView(material:material); view.isMaterialEnabled = enabled
                window.contentView = view; window.makeKeyAndOrderFront(nil); view.layoutSubtreeIfNeeded(); CATransaction.flush()
                let layers = try XCTUnwrap(view.layer?.sublayers).filter { $0.name?.hasPrefix("FluentKit.Material.") == true }
                XCTAssertEqual(layers.count,2)
                // performZoom lays out children inside an animation transaction. View geometry
                // already follows the window; custom sublayers must not animate a second time.
                CATransaction.begin(); CATransaction.setDisableActions(false); CATransaction.setAnimationDuration(1)
                view.frame.size = NSSize(width:900,height:600); view.layout()
                CATransaction.commit(); CATransaction.flush()
                for layer in layers {
                    XCTAssertEqual(layer.frame,view.bounds)
                    XCTAssertNil(layer.animation(forKey:"bounds"),"\(material): background trails the window")
                    XCTAssertNil(layer.animation(forKey:"position"),"\(material): background trails the window")
                }
                window.close()
            }
        }
    }
}
