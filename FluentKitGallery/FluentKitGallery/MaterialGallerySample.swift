import AppKit
import FluentKit

struct MaterialGallerySample: FluentView {
    let theme: FluentTheme
    @FluentState private var selection: String? = "Preset"
    @FluentState private var enabled = true
    @FluentState private var tinted = false
    @FluentState private var rounded = false
    @FluentState private var text = "Keep editing while changing material"

    private var selectedMaterial: FluentMaterial? {
        switch selection {
        case "Native Acrylic": .nativeAcrylic
        case "Native Mica": .nativeMica
        case "Liquid Glass": .liquidGlass
        default: nil
        }
    }

    var body: some FluentView {
        let configuration = FluentMaterialConfiguration(material: selectedMaterial,
            tintColor: tinted ? NSColor.systemTeal.withAlphaComponent(0.18) : nil)
        let customized = selectedMaterial != nil || tinted
        let previewTheme = theme.with(materialEffectsEnabled: enabled)
            .with(materialConfiguration: customized ? configuration : nil, for: .container)
            .with(materialConfiguration: customized ? configuration : nil, for: .transient)
        return FluentVStack(spacing: 12, alignment: .leading) {
            FluentComboBox(options: ["Preset", "Native Acrylic", "Native Mica", "Liquid Glass"],
                selection: $selection).frame(width: 220)
            FluentToggleView("Material effects", isOn: $enabled)
            FluentToggleView("Teal tint", isOn: $tinted)
            FluentToggleView("Larger surface corners", isOn: $rounded)
            FluentVStack(spacing: 12, alignment: .leading) {
                FluentCardView {
                    FluentVStack(spacing: 8, alignment: .leading) {
                        FluentText("Card uses the theme or its preset", style: .bodyStrong)
                        FluentTextFieldView(text: $text, placeholder: "Edit here").frame(width: 280)
                    }
                }
                FluentText("Local choice: Native Acrylic, clear tint")
                    .cardStyle(.automatic, material: .nativeAcrylic, configuration: .init(tintColor: .clear))
                FluentText("Generic container").padding(20)
                    .materialBackground(cornerRadius: rounded ? 20 : 8)
                FluentButtonView("Open a themed menu") {}
                    .flyout { FluentMenuItem("A menu item", action: {}) }
                    .toolTip("The Tooltip inherits transient material settings", motion: .continuous)
            }.fluentTheme(previewTheme)
            FluentText("Presets keep Fluent base colors. Native effects use AppKit; Glass requires a supported macOS version. Accessibility settings can force an opaque surface.", style: .caption)
        }
    }
}
