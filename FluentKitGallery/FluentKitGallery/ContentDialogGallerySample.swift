import AppKit
import FluentKit

struct ContentDialogGallerySample: FluentView {
    let theme: FluentTheme
    @FluentState private var isPresented = false
    @FluentState private var isSaveEnabled = true
    @FluentState private var keepsRecoveryCopy = true
    @FluentState private var resultText = "No result yet"

    var body: FluentAnyView {
        FluentAnyView(
            FluentVStack(spacing: 14) {
                FluentToggleView("Enable Save", isOn: $isSaveEnabled)
                FluentButtonView("Open ContentDialog") {
                    isPresented = true
                }
                .contentDialog(
                    "Save changes?",
                    isPresented: $isPresented,
                    primaryButtonText: "Save",
                    secondaryButtonText: "Don't save",
                    closeButtonText: "Cancel",
                    defaultButton: .primary,
                    isPrimaryButtonEnabled: isSaveEnabled,
                    onClosed: { result in
                        resultText = switch result {
                        case .none: "Cancel"
                        case .primary: "Save"
                        case .secondary: "Don't save"
                        }
                    }
                ) {
                    FluentVStack(spacing: 12) {
                        FluentText("The document has unsaved changes.", style: .body)
                        FluentCheckBoxView(
                            "Keep a recovery copy",
                            isChecked: $keepsRecoveryCopy
                        )
                    }
                }
                FluentText(
                    "Result: \(resultText)",
                    style: .caption,
                    color: theme.textSecondary
                )
            }
        )
    }
}
