import FluentKit
import AppKit

func wrapperCases() -> [(String, (FluentAnyView) -> FluentAnyView)] { [
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

private func fixedWrapperBinding<Value>(_ value: Value) -> FluentBinding<Value> {
    FluentBinding(get: { value }, set: { _ in })
}
