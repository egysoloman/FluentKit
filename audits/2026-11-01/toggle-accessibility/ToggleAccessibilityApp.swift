import AppKit
import FluentKit

private final class AuditModel {
    @FluentState var value = false
    @FluentState var disabledValue = true
    @FluentState var hide = true
    @FluentState var writes = 0
    @FluentState var directWrites = 0
    let direct = FluentToggle(title: "Direct switch")
}

private struct AuditPage: FluentView {
    let model: AuditModel
    var body: some FluentView {
        FluentVStack(spacing: 16, alignment: .leading) {
            FluentToggleView("Bound switch", isOn: FluentBinding(get: { model.value }, set: {
                model.writes += 1; model.value = $0
            }))
            FluentToggleView("Disabled switch", isOn: model.$disabledValue).disabled()
            FluentNativeView(model.direct)
            FluentToggleView("Hidden switch", isOn: model.$disabledValue).padding(4).accessibilityHidden(model.hide)
            FluentToggleView("Visible title", isOn: model.$disabledValue).accessibilityLabel("Custom switch name")
            FluentToggleView("Group child", isOn: model.$disabledValue).accessibilityGroup(label: "Named group")
            FluentText("Model: \(model.value ? "on" : "off"); binding writes: \(model.writes); direct writes: \(model.directWrites)")
            FluentHStack {
                FluentButtonView("Set model on") { model.value = true }
                FluentButtonView("Set model off") { model.value = false }
                FluentButtonView("Change AX visibility") { model.hide.toggle() }
            }
        }.padding(24)
    }
}

@main struct ToggleAccessibilityApp: FluentApp {
    private let model = AuditModel()
    var body: some FluentScene {
        FluentWindowScene(title: "Toggle accessibility audit", size: NSSize(width: 560, height: 480),
                          material: nil, restoration: .disabled) { AuditPage(model: model) }
    }
    func applicationDidLaunch() {
        model.direct.onValueChanged = { _ in model.directWrites += 1 }
    }
}
