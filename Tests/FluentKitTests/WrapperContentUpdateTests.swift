import XCTest
@testable import FluentKit

final class WrapperContentUpdateTests: XCTestCase {
    private typealias Wrap = (FluentAnyView) -> FluentAnyView

    private var wrappers: [(String, Wrap)] { [
        ("unwrapped control", { $0 }),
        ("accessibility actions control", { FluentAnyView($0.accessibilityActions([])) }),
        ("accessibility group", { FluentAnyView($0.accessibilityGroup(label: "Group")) }),
        ("accessibility element", { FluentAnyView($0.accessibilityElement(children: .contain)) }),
        ("dynamic accessibility", { FluentAnyView($0.accessibilityLabel(fixedWrapperBinding("Label"))) }),
        ("focus announcement", { FluentAnyView($0.accessibilityAnnounceOnFocus("Focused")) }),
        ("lifecycle", { FluentAnyView($0.onAppear {}) }),
        ("hover", { FluentAnyView($0.onHover { _ in }) }),
        ("focused", { FluentAnyView($0.focused(fixedWrapperBinding(false))) }),
        ("initial focus", { FluentAnyView($0.fluentInitialFocus()) }),
        ("focus scope", { FluentAnyView($0.fluentFocusScope()) }),
        ("commands", { FluentAnyView($0.fluentCommands {}) }),
        ("confirmation", { FluentAnyView($0.confirmationDialog("Confirm", isPresented: fixedWrapperBinding(false)) { FluentDialogAction("OK") }) }),
        ("file importer", { FluentAnyView($0.fileImporter(isPresented: fixedWrapperBinding(false)) { _ in }) }),
        ("file exporter", { FluentAnyView($0.fileExporter(isPresented: fixedWrapperBinding(false)) { _ in }) }),
        ("context menu", { FluentAnyView($0.contextMenu { FluentMenuItem("Item") {} }) }),
        ("default action", { FluentAnyView($0.fluentDefaultAction {}) }),
        ("drag source", { content in FluentAnyView(FluentDragSource("payload" as NSString) { content }) }),
        ("drop target", { content in FluentAnyView(FluentDropTarget(types: [.string], content: { content }, onDrop: { _ in })) }),
        ("form field", { content in FluentAnyView(FluentFormField("Field") { content }) }),
        ("form section", { content in FluentAnyView(FluentFormSection("Section") { content }) }),
        ("labeled content", { content in FluentAnyView(FluentLabeledContent("Label") { content }) }),
        ("toolbar", { FluentAnyView($0.toolbar {}) }),
        ("control size", { FluentAnyView($0.controlSize(.small)) }),
        ("teaching tip", { FluentAnyView($0.teachingTip(isPresented: fixedWrapperBinding(false)) { FluentText("Tip") }) }),
        ("content dialog", { FluentAnyView($0.contentDialog("Dialog", isPresented: fixedWrapperBinding(false)) { FluentText("Dialog body") }) }),
        ("settings card action", { content in FluentAnyView(FluentSettingsCard("Card") { content }) }),
        ("expander control", { content in FluentAnyView(FluentExpander("Expander", isExpanded: fixedWrapperBinding(true)) { content }) }),
        ("settings expander control", { content in FluentAnyView(FluentSettingsExpander("Settings", isExpanded: fixedWrapperBinding(true)) { content }) })
    ] }

    private func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }

    @MainActor func testWrappersForwardLatestContentStyleAndActionWithoutRemounting() throws {
        _ = NSApplication.shared
        let light = FluentRenderContext(theme: .custom(colorScheme: .light), reduceMotion: true)
        let dark = FluentRenderContext(theme: .custom(colorScheme: .dark), reduceMotion: true)
        for (name, wrap) in wrappers {
            var invoked = ""
            let initial = wrap(FluentAnyView(FluentButtonView("Before", role: .standard, action: { invoked = "before" })))
            let host = FluentViewHost(initial, context: light)
            let button = try XCTUnwrap(all(host).compactMap { $0 as? FluentButton }.first, name)
            let mountedWrapper = try XCTUnwrap(host.subviews.first, name)
            for context in [dark, light] {
                let next = wrap(FluentAnyView(FluentButtonView("After", role: .primary, action: { invoked = "after" })))
                host.update(next, context: context)
                XCTAssertTrue(host.subviews.first === mountedWrapper, name)
                XCTAssertTrue(all(host).contains { $0 === button }, name)
                XCTAssertEqual(button.title, "After", name)
                XCTAssertEqual(button.role, .primary, name)
                XCTAssertEqual(button.theme, context.theme, name)
                button.performClick(nil)
                XCTAssertEqual(invoked, "after", name)
            }
        }
    }

    @MainActor func testFormFieldReplacesIncompatibleContentUsingTheLatestValue() throws {
        _ = NSApplication.shared
        let first = FluentFormField<FluentAnyView>("Before") { FluentAnyView(FluentText("Old content")) }
        let host = FluentViewHost(first)
        let form = try XCTUnwrap(host.subviews.first)
        let oldLabel = try XCTUnwrap(all(host).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Old content" })
        var invoked = false
        host.update(FluentFormField<FluentAnyView>("After") { FluentAnyView(FluentButtonView("New content", action: { invoked = true })) })
        XCTAssertTrue(host.subviews.first === form)
        XCTAssertFalse(all(host).contains { $0 === oldLabel })
        let button = try XCTUnwrap(all(host).compactMap { $0 as? FluentButton }.first)
        XCTAssertEqual(button.title, "New content")
        button.performClick(nil); XCTAssertTrue(invoked)
    }

    @MainActor func testFocusScopeDoesNotRetainItsOwnHost() {
        _ = NSApplication.shared
        weak var released: NSView?
        autoreleasepool {
            let native = FluentButtonView("Focus").fluentFocusScope()._makeView(in: .init())
            released = native
            XCTAssertNotNil(released)
        }
        XCTAssertNil(released)
    }

    @MainActor func testCombinedAccessibilityLabelUsesUpdatedChildren() throws {
        _ = NSApplication.shared
        func content(_ value: String) -> some FluentView {
            FluentButtonView(value).accessibilityLabel(value).accessibilityHidden(false)
                .accessibilityElement(children: .combine)
        }
        let host = FluentViewHost(content("Before"))
        let semantic = try XCTUnwrap(host.subviews.first)
        XCTAssertEqual(semantic.accessibilityLabel(), "Before")
        host.update(content("After"))
        XCTAssertEqual(semantic.accessibilityLabel(), "After")
    }

    @MainActor func testLifecycleAndFocusLoopSurviveCompatibleContentUpdates() throws {
        _ = NSApplication.shared
        var appearances = 0, disappearances = 0
        func content(_ value: String) -> some FluentView {
            FluentButtonView(value)
                .onAppear { appearances += 1 }
                .onDisappear { disappearances += 1 }
                .fluentFocusScope()
        }
        let host = FluentViewHost(content("Before"))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 200, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = host
        let button = try XCTUnwrap(all(host).compactMap { $0 as? FluentButton }.first)
        host.update(content("After"))
        XCTAssertEqual(button.title, "After")
        XCTAssertEqual(appearances, 1); XCTAssertEqual(disappearances, 0)
        XCTAssertTrue(button.nextKeyView === button)
        host.removeFromSuperview()
        XCTAssertEqual(disappearances, 1)
    }

    @MainActor func testFocusLoopIncludesNewChildrenAndSkipsRemovedChildren() throws {
        _ = NSApplication.shared
        func content(_ values: [String]) -> some FluentView {
            FluentHStack {
                FluentForEach(values, id: \.self) { value in
                    FluentNativeView(make: { NSTextField(string: value) }, update: { field, _ in field.stringValue = value })
                }
            }.fluentFocusScope()
        }
        let host = FluentViewHost(content(["A", "B"]))
        let initial = all(host).compactMap { $0 as? NSTextField }
        for values in [["A", "B", "C"], ["B", "C"]] {
            host.update(content(values))
            let fields = all(host).compactMap { $0 as? NSTextField }
            XCTAssertEqual(fields.map(\.stringValue), values)
            for i in fields.indices { XCTAssertTrue(fields[i].nextKeyView === fields[(i + 1) % fields.count]) }
            XCTAssertTrue(fields.contains { $0 === initial[1] })
        }
    }

    @MainActor func testSettingsCardAppearanceCallbackKeepsTheLatestActionContent() throws {
        _ = NSApplication.shared
        var invoked = ""
        func content(_ value: String) -> some FluentView {
            FluentSettingsCard("Card") { FluentButtonView(value, action: { invoked = value }) }
        }
        let host = FluentViewHost(content("Before"), context: .init(theme: .custom(colorScheme: .light)))
        let button = try XCTUnwrap(all(host).compactMap { $0 as? FluentButton }.first)
        host.update(content("After"))
        let participant = try XCTUnwrap(host.subviews.first as? FluentAppearanceParticipant)
        participant.applyFluentAppearance(.custom(colorScheme: .dark))
        XCTAssertEqual(button.title, "After")
        XCTAssertTrue(button.theme.isDark)
        button.performClick(nil); XCTAssertEqual(invoked, "After")
    }
}

private func fixedWrapperBinding<Value>(_ value: Value) -> FluentBinding<Value> {
    FluentBinding(get: { value }, set: { _ in })
}
