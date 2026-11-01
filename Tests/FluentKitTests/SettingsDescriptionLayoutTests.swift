import XCTest
@testable import FluentKit

@MainActor
final class SettingsDescriptionLayoutTests: XCTestCase {
    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    private func settle(_ host: NSView) async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            host.layoutSubtreeIfNeeded()
        }
    }

    func testScrollingSettingsHeadersReflowAfterWindowResize() async throws {
        _ = NSApplication.shared
        let description = "Light, Dark and RTL mounting checked; interactive states need the acceptance matrix"
        let expanded = FluentState(wrappedValue: true)
        let host = FluentViewHost(FluentScrollView(.vertical) {
            FluentVStack(spacing: 12, alignment: .width) {
                FluentSettingsCard("Plain", description: description, systemImageName: "play.circle")
                FluentSettingsExpander("Expanded", description: description, systemImageName: "play.circle",
                    isExpanded: expanded.projectedValue) { FluentText("Body") }
                FluentText("Following row")
            }.padding(20)
        }, context: .init(reduceMotion: true))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 820, height: 500),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        window.orderFront(nil)
        let fixedWidth = host.widthAnchor.constraint(equalToConstant: 820)
        fixedWidth.isActive = true
        var wideHeights: [CGFloat] = []
        for width: CGFloat in [820, 500, 820] {
            fixedWidth.constant = width
            window.setContentSize(NSSize(width: width, height: 500))
            await settle(host)
            XCTAssertEqual(host.bounds.width, width, accuracy: 0.5)
            let cards = all(host).filter { ["FluentKit.Settings.Card", "FluentKit.Settings.Expander.Header"].contains($0.identifier?.rawValue ?? "") }
            XCTAssertEqual(cards.count, 2)
            for (index, card) in cards.enumerated() {
                let label = try XCTUnwrap(all(card).compactMap { $0 as? NSTextField }.first { $0.stringValue == description })
                let needed = try XCTUnwrap(label.cell).cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: 1000)).height
                XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, needed, "All description lines must fit at window width \(width)")
                if wideHeights.count < cards.count { wideHeights.append(card.bounds.height) }
                else if width == 500 { XCTAssertGreaterThan(card.bounds.height, wideHeights[index]) }
                else { XCTAssertEqual(card.bounds.height, wideHeights[index], accuracy: 0.5) }
            }
        }
    }

    func testDescriptionAndActionUpdatesRemeasureAndMoveFollowingRow() async throws {
        _ = NSApplication.shared
        for rtl in [false, true] {
            func definition(_ description: String?, actionWidth: CGFloat) -> some FluentView {
                FluentVStack(spacing: 12, alignment: .width) {
                    FluentSettingsCard("Setting", description: description, systemImageName: "play.circle") {
                        FluentText("Action").frame(width: actionWidth)
                    }
                    FluentText("Following row")
                }.padding(20)
            }
            let host = FluentViewHost(definition(nil, actionWidth: 40), context: .init(reduceMotion: true,
                layoutDirection: rtl ? .rightToLeft : .leftToRight))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host
            host.widthAnchor.constraint(equalToConstant: 500).isActive = true
            window.orderFront(nil)
            await settle(host)
            let card = try XCTUnwrap(all(host).first { $0.identifier?.rawValue == "FluentKit.Settings.Card" })
            let originalHeight = card.bounds.height
            let text = "Description that wraps when the action takes more space."
            let cases: [(String?, CGFloat)] = [(text, 40), (text, 160), ("Short", 160), (nil, 40), (text, 160), (text, 40)]
            for (description, actionWidth) in cases {
                host.update(definition(description, actionWidth: actionWidth))
                await settle(host)
                XCTAssertTrue(card === all(host).first { $0.identifier?.rawValue == "FluentKit.Settings.Card" })
                if let description {
                    let label = try XCTUnwrap(all(card).compactMap { $0 as? NSTextField }.first { $0.stringValue == description })
                    let needed = try XCTUnwrap(label.cell).cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: 1000)).height
                    XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, needed)
                    if description == text && actionWidth == 160 { XCTAssertGreaterThan(card.bounds.height, originalHeight) }
                    else { XCTAssertEqual(card.bounds.height, originalHeight, accuracy: 0.5) }
                } else { XCTAssertEqual(card.bounds.height, originalHeight, accuracy: 0.5) }
                let marker = try XCTUnwrap(all(host).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Following row" })
                let cardRect = card.convert(card.bounds, to: host)
                let markerRect = marker.convert(marker.alignmentRect(forFrame: marker.bounds), to: host)
                XCTAssertEqual(abs(markerRect.midY - cardRect.midY), (markerRect.height + cardRect.height) / 2 + 12, accuracy: 0.5)
            }
        }
    }
}
