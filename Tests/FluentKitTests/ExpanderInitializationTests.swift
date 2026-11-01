import XCTest
@testable import FluentKit

@MainActor
final class ExpanderInitializationTests: XCTestCase {
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    func testCustomHeaderUsesItsNaturalHeightAndMovesBodyOnLiveUpdate() throws {
        _ = NSApplication.shared
        for direction in [FluentExpandDirection.down, .up] {
            let state = FluentState(wrappedValue: true)
            func definition(_ height: CGFloat) -> some FluentView {
                FluentExpanderView(isExpanded: state.projectedValue, expandDirection: direction,
                    header: { FluentText("Custom header").frame(height: height) },
                    content: { FluentText("Body").frame(height: 60) })
            }
            let native = definition(72)._mount(in: .init(reduceMotion: true))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = native
            window.orderFront(nil)
            let header = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == "FluentKit.Expander.Header" })
            let clip = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == "FluentKit.Expander.ContentClip" })
            for height: CGFloat in [72, 104, 24] {
                XCTAssertTrue(definition(height)._update(native, in: .init(reduceMotion: true)))
                native.layoutSubtreeIfNeeded()
                let expected = max(48, height)
                XCTAssertEqual(header.bounds.height, expected, accuracy: 0.01)
                XCTAssertEqual(native.intrinsicContentSize.height, expected + 92, accuracy: 0.01)
                XCTAssertEqual(direction == .down ? clip.frame.minY : header.frame.minY,
                               direction == .down ? expected : 92, accuracy: 0.01)
                XCTAssertTrue(header === all(native).first { $0.identifier?.rawValue == "FluentKit.Expander.Header" })
                state.wrappedValue = false
                native.layoutSubtreeIfNeeded()
                XCTAssertEqual(native.intrinsicContentSize.height, expected, accuracy: 0.01)
                XCTAssertTrue(clip.isHidden)
                state.wrappedValue = true
                native.layoutSubtreeIfNeeded()
            }
        }
    }
    func testNestedHeaderHeightUpdateMovesSettingsViewportAndFollowingRow() async throws {
        _ = NSApplication.shared
        let outerExpanded = FluentState(wrappedValue: true)
        let innerExpanded = FluentState(wrappedValue: true)
        let marker = NSTextField(labelWithString: "Following row")
        func definition(_ height: CGFloat) -> some FluentView {
            FluentVStack(spacing: 12, alignment: .width) {
                FluentSettingsExpander("Settings card", isExpanded: outerExpanded.projectedValue) {
                    FluentExpanderView(isExpanded: innerExpanded.projectedValue,
                        header: { FluentText("Custom header").frame(height: height) },
                        content: { FluentText("Body").frame(height: 60) })
                }
                FluentNativeView(marker)
            }.frame(width: 380)
        }
        let host = FluentViewHost(definition(72), context: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        window.orderFront(nil)
        func settle() async {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            host.layoutSubtreeIfNeeded()
        }
        await settle()
        let viewport = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.Settings.Expander.Viewport" })
        let expander = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.Expander" })
        let originalViewportHeight = viewport.bounds.height
        let originalMarker = marker.convert(marker.bounds, to: host)
        host.update(definition(104))
        await settle()
        XCTAssertTrue(expander === all(host).first { $0.identifier?.rawValue == "FluentKit.Expander" })
        XCTAssertEqual(viewport.bounds.height - originalViewportHeight, 32, accuracy: 0.5)
        XCTAssertEqual(abs(marker.convert(marker.bounds, to: host).minY - originalMarker.minY), 32, accuracy: 0.5)
        innerExpanded.wrappedValue = false
        await settle()
        XCTAssertEqual(viewport.bounds.height, 104 + 20, accuracy: 0.5)
        outerExpanded.wrappedValue = false
        await settle()
        XCTAssertTrue(viewport.isHidden)
        host.update(definition(72))
        await settle()
        outerExpanded.wrappedValue = true
        await settle()
        XCTAssertEqual(viewport.bounds.height, 72 + 20, accuracy: 0.5)
        XCTAssertFalse(viewport.isHidden)
    }

    func testGrowingTemplateStacksKeepNaturalHeightAndMirroredHeaderInsets() throws {
        _ = NSApplication.shared
        for bodyTemplate in [false, true] {
            for rtl in [false, true] {
                let context = FluentRenderContext(reduceMotion: true,
                    layoutDirection: rtl ? .rightToLeft : .leftToRight)
                func definition(_ gap: CGFloat) -> some FluentView {
                    let template = FluentVStack(spacing: gap) { FluentText("First"); FluentText("Second") }
                    return FluentExpanderView(isExpanded: FluentBinding(get: { true }, set: { _ in }),
                        header: { if bodyTemplate { FluentText("Header") } else { template } },
                        content: { if bodyTemplate { template } else { FluentText("Body") } })
                }
                let native = definition(4)._mount(in: context)
                let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.contentView = native
                window.orderFront(nil)
                native.layoutSubtreeIfNeeded()
                let header = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == "FluentKit.Expander.Header" })
                let surface = try XCTUnwrap(all(native).first { $0.identifier?.rawValue == "FluentKit.Expander.Content" })
                for gap: CGFloat in [80, 4, 120] {
                    XCTAssertTrue(definition(gap)._update(native, in: context))
                    native.layoutSubtreeIfNeeded()
                    let content = try XCTUnwrap((bodyTemplate ? surface : header).subviews.first)
                    XCTAssertEqual(content.frame.height, content.fittingSize.height, accuracy: 0.01)
                    XCTAssertGreaterThanOrEqual(content.bounds.height, gap)
                    XCTAssertTrue((bodyTemplate ? surface : header).bounds.contains(content.frame))
                    let headerContent = try XCTUnwrap(header.subviews.first)
                    let headerRect = headerContent.alignmentRect(forFrame: headerContent.frame)
                    XCTAssertEqual(header.bounds.height, max(48, headerContent.fittingSize.height), accuracy: 0.01)
                    XCTAssertEqual(headerRect.minX, rtl ? 60 : 16, accuracy: 0.01)
                    XCTAssertEqual(headerRect.maxX, header.bounds.maxX - (rtl ? 16 : 60), accuracy: 0.01)
                }
            }
        }
    }
}
