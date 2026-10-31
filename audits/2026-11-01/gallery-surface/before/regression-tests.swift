import XCTest
@testable import FluentKit

final class WindowSurfaceResizeTests: XCTestCase {
    @MainActor func testSharedChromeTintAndMaskFollowResizeWithoutExtraAnimation() throws {
        _ = NSApplication.shared
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        for dark in [false, true] {
            for rtl in [false, true] {
                let theme = FluentTheme.custom(colorScheme: dark ? .dark : .light)
                let root = FluentViewHost(
                    FluentWindowShell(
                        configuration: .init(layout: .settings, backdrop: .mica, contentTransition: .none),
                        title: "Resize audit",
                        items: [FluentNavigationItem(id: "home", title: "Home")],
                        selection: FluentBinding<String?>(get: { "home" }, set: { _ in }),
                        header: { FluentText("Page heading") },
                        content: { FluentText("Page content") }
                    ),
                    context: .init(theme: theme, reduceMotion: true,
                                   layoutDirection: rtl ? .rightToLeft : .leftToRight)
                )
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.contentView = root
                window.makeKeyAndOrderFront(nil)
                root.layoutSubtreeIfNeeded()
                CATransaction.flush()
                let chrome = try XCTUnwrap(descendants(root).first {
                    $0.identifier?.rawValue == "FluentKit.WindowShell.SharedChromeHost"
                })
                let tint = try XCTUnwrap(chrome.layer?.sublayers?.first {
                    $0.name == "FluentKit.WindowShell.SharedChromeTint"
                })
                let mask = try XCTUnwrap(tint.mask as? CAShapeLayer)
                for size in [NSSize(width: 1400, height: 850), NSSize(width: 820, height: 560)] {
                    CATransaction.begin()
                    CATransaction.setDisableActions(false)
                    CATransaction.setAnimationDuration(1)
                    root.setFrameSize(size)
                    root.layoutSubtreeIfNeeded()
                    CATransaction.commit()
                    CATransaction.flush()
                    XCTAssertEqual(tint.frame, chrome.bounds)
                    XCTAssertEqual(mask.frame, chrome.bounds)
                    for layer in [tint, mask] {
                        XCTAssertNil(layer.animation(forKey: "bounds"))
                        XCTAssertNil(layer.animation(forKey: "position"))
                        XCTAssertNil(layer.animation(forKey: "path"))
                    }
                    let surface = try XCTUnwrap(descendants(root).first {
                        $0.identifier?.rawValue == "FluentKit.WindowShell.ContentSurface"
                    })
                    let center = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: chrome)
                    XCTAssertFalse(try XCTUnwrap(mask.path).contains(center, using: .evenOdd),
                                   "Chrome tint must not cover the content surface after resize")
                }
            }
        }
    }
}
