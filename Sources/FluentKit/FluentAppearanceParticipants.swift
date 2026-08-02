import AppKit

// Public controls can be embedded directly in AppKit without a FluentViewHost. These lightweight
// conformances keep that supported path in the same window transaction as declarative controls.

extension FluentMaterialView: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) {
        fluentTheme = theme
        isMaterialEnabled = theme.materialEffectsEnabled
        fallbackColor = materialStyle == .mica ? theme.windowBackground : theme.flyoutSurfaceFill
    }
}

extension FluentCard: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentButton: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentTextField: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentSecureTextField: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentSearchTextField: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentToggle: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentToggleButton: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentRepeatButton: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentDropDownButton: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentCheckBox: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentRadioButton: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentProgressBar: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentProgressRing: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentSlider: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentNumberBoxControl: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentTextEditor: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentRichTextEditor: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}

extension FluentPopoverButton: FluentAppearanceParticipant {
    func applyFluentAppearance(_ theme: FluentTheme) { self.theme = theme }
}
