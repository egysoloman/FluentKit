import XCTest
@testable import FluentKit

private final class ScopeRefreshProbe: NSView {
    var text = ""
    var invoke: (() -> Void)?
    weak var observedUndo: FluentUndoCoordinator?
}

final class ScopeRefreshTests: XCTestCase {
    @MainActor private func descendants(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants)
    }

    @MainActor private func verifyRefresh(undoScope: Bool, historyScope: Bool) throws {
        _ = NSApplication.shared
        let inheritedUndo = FluentUndoCoordinator()
        let scopedUndo = FluentUndoCoordinator()
        let history = FluentNavigationCoordinator(initial: "home")
        var invoked: [String] = []
        func page(_ value: String) -> FluentAnyView {
            var view = FluentAnyView(FluentNativeView(make: { ScopeRefreshProbe() }) { native, context in
                native.text = value
                native.invoke = { invoked.append(value) }
                native.observedUndo = context.undoCoordinator
            })
            if historyScope { view = FluentAnyView(view.fluentNavigationHistory(history, onNavigate: { _ in })) }
            if undoScope { view = FluentAnyView(view.fluentUndoScope(scopedUndo)) }
            return view
        }
        let root = FluentViewHost(page("before"), context: .init(undoCoordinator: inheritedUndo))
        let native = try XCTUnwrap(descendants(root).compactMap { $0 as? ScopeRefreshProbe }.first)
        let parent = native.superview
        root.update(page("after"))
        XCTAssertTrue(native === descendants(root).compactMap { $0 as? ScopeRefreshProbe }.first)
        XCTAssertTrue(native.superview === parent)
        XCTAssertEqual(native.text, "after", "Scope must forward the current declarative value")
        native.invoke?()
        XCTAssertEqual(invoked, ["after"], "Scope must forward the current action capture")
        XCTAssertTrue(native.observedUndo === (undoScope ? scopedUndo : inheritedUndo))
    }

    @MainActor func testUndoScopeUpdatesContentAndActionsWithoutReplacingNativeView() throws {
        try verifyRefresh(undoScope: true, historyScope: false)
    }

    @MainActor func testHistoryScopeUpdatesContentAndActionsWithoutReplacingNativeView() throws {
        try verifyRefresh(undoScope: false, historyScope: true)
    }

    @MainActor func testNestedHistoryAndUndoScopesForwardLatestContentAndEnvironment() throws {
        try verifyRefresh(undoScope: true, historyScope: true)
    }

    @MainActor func testScopedTypeErasedContentCanChangeItsNativeKind() {
        _ = NSApplication.shared
        let undo = FluentUndoCoordinator()
        let history = FluentNavigationCoordinator(initial: "home")
        func page(_ showLabel: Bool) -> some FluentView {
            let content = showLabel ? FluentAnyView(FluentText("Label"))
                : FluentAnyView(FluentNativeView(make: { ScopeRefreshProbe() }, update: { native, _ in native.text = "Replacement" }))
            return content.fluentNavigationHistory(history, onNavigate: { _ in }).fluentUndoScope(undo)
        }
        let root = FluentViewHost(page(true))
        XCTAssertTrue(descendants(root).contains { $0 is NSTextField })
        root.update(page(false))
        XCTAssertFalse(descendants(root).contains { $0 is NSTextField })
        XCTAssertEqual(descendants(root).compactMap { $0 as? ScopeRefreshProbe }.first?.text, "Replacement")
    }
}
