import AppKit
import FluentKit
import UniformTypeIdentifiers

struct GalleryTableRow: Equatable {
    let id: Int
    let name: String
    let state: String
}

private struct GalleryNavigationSnapshot: FluentView {
    @FluentState private var selection: String? = "Library"
    @FluentState private var isSidebarVisible = true

    var body: FluentAnyView {
        FluentAnyView(
            FluentVStack(spacing: 14) {
                FluentText("Navigation workspace", size: 24, weight: .semibold)
                FluentText(
                    "A persistent native split view with stable destination identity.",
                    size: 13,
                    color: FluentTheme.current.textSecondary
                )
                FluentBoundToggle($isSidebarVisible, title: "Show sidebar")
                FluentNavigationSplitView(
                    ["Home", "Library", "Settings"],
                    id: { $0 },
                    selection: $selection,
                    isSidebarVisible: $isSidebarVisible,
                    sidebarWidth: 180...300,
                    idealSidebarWidth: 220
                ) { item in
                    FluentText(item, size: 13)
                } detail: { item in
                    FluentVStack(spacing: 10) {
                        FluentText(item, size: 22, weight: .semibold)
                        FluentText(
                            "Stable selection drives this native detail column.",
                            size: 13,
                            color: FluentTheme.current.textSecondary
                        )
                        FluentDivider()
                        FluentText(
                            "The sidebar uses macOS material while the content remains fully declarative.",
                            size: 13
                        )
                    }
                    .padding(28)
                } placeholder: {
                    FluentText("Choose a destination", size: 14, color: FluentTheme.current.textSecondary)
                        .padding(28)
                }
                .frame(height: 330)
            }
            .padding(NSEdgeInsets(top: 34, left: 36, bottom: 36, right: 36))
        )
    }
}

private struct GalleryStyleSnapshot: FluentView {
    @FluentState private var notificationsEnabled = true
    @FluentState private var sliderValue = 0.58
    @FluentState private var searchText = ""
    @FluentState private var showCompleted = true
    @FluentState private var primaryChoice = false
    @FluentState private var selectedSegment = 0
    @FluentState private var secureText = ""
    @FluentState private var quantity = 2

    var body: FluentAnyView {
        FluentAnyView(
            FluentVStack(spacing: 18) {
                FluentText("Styles and theming", style: .title)
                FluentText("Reusable native appearances with inherited semantic metrics.", style: .callout)
                FluentHStack(spacing: 10) {
                    FluentButtonView("Automatic")
                    FluentButtonView("Accent").buttonStyle(FluentAccentButtonStyle())
                    FluentButtonView("Outline").buttonStyle(FluentOutlineButtonStyle())
                    FluentButtonView("Borderless").buttonStyle(FluentBorderlessButtonStyle())
                }
                FluentHStack(spacing: 14) {
                    FluentToggleView("Updates", isOn: $notificationsEnabled)
                        .toggleStyle(FluentMonochromeToggleStyle())
                    FluentSliderView(value: $sliderValue)
                        .sliderStyle(FluentNeutralSliderStyle())
                        .frame(width: 150)
                    FluentTextFieldView(text: $searchText, placeholder: "Underline style")
                        .textFieldStyle(FluentUnderlineTextFieldStyle())
                        .frame(width: 170)
                    FluentProgressBar(value: sliderValue)
                        .progressStyle(FluentNeutralProgressStyle())
                        .frame(width: 210)
                }
                FluentHStack(spacing: 14) {
                    FluentCheckBoxView("Completed", isChecked: $showCompleted)
                        .checkBoxStyle(FluentMonochromeCheckBoxStyle())
                    FluentRadioButtonView("Primary", isSelected: $primaryChoice)
                        .radioButtonStyle(FluentAutomaticRadioButtonStyle())
                    FluentSegmentedControl(["One", "Two"], selection: $selectedSegment)
                        .segmentedStyle(FluentNeutralSegmentedStyle())
                }
                FluentHStack(spacing: 14) {
                    FluentSecureField($secureText, placeholder: "Secure underline")
                        .textFieldStyle(FluentUnderlineTextFieldStyle())
                        .frame(width: 190)
                    FluentStepper("Items", value: $quantity, in: 1...9)
                        .stepperStyle(FluentInlineStepperStyle())
                }
                FluentVStack(spacing: 6) {
                    FluentText("Elevated card", style: .headline)
                    FluentText("The card surface and content inset come from a reusable style.", style: .caption)
                }
                .cardStyle(FluentElevatedCardStyle())
                FluentVStack(spacing: 8) {
                    FluentText("Compact high contrast", style: .headline)
                    FluentHStack(spacing: 8) {
                        FluentButtonView("Primary").buttonStyle(FluentAccentButtonStyle())
                        FluentButtonView("Secondary").buttonStyle(FluentOutlineButtonStyle())
                    }
                }
                .fluentDensity(.compact)
                .fluentContrast(.high)
            }
            .padding(NSEdgeInsets(top: 36, left: 42, bottom: 36, right: 42))
        )
    }
}

private enum GalleryPage: String, CaseIterable, Hashable {
    case overview
    case controls
    case inputs
    case collections
    case navigation
    case motion
    case application
    case accessibility
    case settings

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .controls: return "Controls"
        case .inputs: return "Inputs & forms"
        case .collections: return "Collections"
        case .navigation: return "Navigation"
        case .motion: return "Motion & theme"
        case .application: return "Application"
        case .accessibility: return "Accessibility"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .controls: return "slider.horizontal.3"
        case .inputs: return "keyboard"
        case .collections: return "square.grid.3x3"
        case .navigation: return "sidebar.left"
        case .motion: return "sparkles"
        case .application: return "macwindow.on.rectangle"
        case .accessibility: return "accessibility"
        case .settings: return "gearshape"
        }
    }
}

private struct GalleryNavigationShell: FluentView {
    let page: GalleryPage
    let selection: FluentBinding<GalleryPage>
    let isPaneOpen: FluentBinding<Bool>
    let search: FluentBinding<String>
    let content: FluentAnyView
    let theme: FluentTheme
    let reduceMotion: Bool

    var body: FluentAnyView {
        let navigationSelection = selection.map(
            { Optional($0) },
            { $0 ?? selection.wrappedValue }
        )
        let navigationItems = GalleryPage.allCases.filter { $0 != .settings }.map { item in
            FluentNavigationItem(
                id: item,
                title: item.title,
                systemImageName: item.symbolName
            )
        }
        let footerItems = [
            FluentNavigationItem(
                id: GalleryPage.settings,
                title: GalleryPage.settings.title,
                systemImageName: GalleryPage.settings.symbolName
            )
        ]
        let environment = ProcessInfo.processInfo.environment
        let showsBackButton = environment["FLUENTKIT_GALLERY_SHOW_BACK"] == "1"
        let navigationPlacement: FluentWindowNavigationPlacement = switch environment["FLUENTKIT_GALLERY_NAV_MODE"] {
        case "none": .none
        case "auto": .automatic
        case "compact": .leftCompact
        case "minimal": .leftMinimal
        case "top": .top
        default: .left
        }
        let titleBarStyle: FluentWindowTitleBarStyle = environment["FLUENTKIT_GALLERY_TITLEBAR_STYLE"] == "native"
            ? .native
            : .extended
        let paneTogglePlacement: FluentWindowPaneTogglePlacement = environment["FLUENTKIT_GALLERY_TOGGLE_PLACEMENT"] == "pane"
            ? .navigationPane
            : .titleBar
        let searchPlacement: FluentWindowSearchPlacement = environment["FLUENTKIT_GALLERY_SEARCH_PLACEMENT"] == "none"
            ? .none
            : .titleBar
        let shellConfiguration = FluentWindowConfiguration(
            layout: navigationPlacement == .none
                ? .standard
                : (navigationPlacement == .top ? .topNavigation : .settings),
            titleBarStyle: titleBarStyle,
            navigationPlacement: navigationPlacement,
            paneTogglePlacement: paneTogglePlacement,
            searchPlacement: searchPlacement,
            backdrop: .liquidGlass,
            contentCornerStyle: navigationPlacement == .top ? FluentContentCornerStyle.none : .topLeading,
            titleBarHeight: .expanded,
            contentTransition: .bottomUp
        )
        return FluentAnyView(
            FluentWindowShell(
                configuration: shellConfiguration,
                title: "FluentKit Gallery",
                systemImageName: "square.grid.2x2.fill",
                isBackButtonVisible: showsBackButton,
                isBackButtonEnabled: page != .overview,
                onBack: { selection.wrappedValue = .overview },
                items: navigationItems,
                footerItems: footerItems,
                selection: navigationSelection,
                isPaneOpen: isPaneOpen,
                openPaneLength: theme.designTokens.navigationPaneWidth,
                compactPaneLength: 48,
                rowHeight: 40,
                paneSectionTitle: "Explore",
                titleBarContent: {
                    FluentSearchField(search, placeholder: "Search controls and samples...")
                        .frame(width: 360, height: 32)
                },
                header: {
                    FluentVStack(spacing: 0) {
                        FluentHStack(spacing: 12) {
                            FluentText(page.title, style: .title)
                            FluentSpacer()
                        }
                        .padding(NSEdgeInsets(top: 24, left: 32, bottom: 22, right: 32))
                        FluentDivider()
                    }
                },
                content: {
                    FluentScrollView(.vertical) {
                        content.padding(NSEdgeInsets(top: 28, left: 32, bottom: 36, right: 32))
                    }
                }
            )
            .fluentReduceMotion(reduceMotion)
        )
    }
}

private struct WinUIStyleGalleryScreen: FluentView {
    private let applicationTheme: FluentThemeStore
    @FluentState private var page: GalleryPage = .overview
    @FluentState private var isNavigationPaneOpen = true
    @FluentState private var notifications = true
    @FluentState private var syncEnabled = false
    @FluentState private var toggleButtonEnabled = true
    @FluentState private var toggleButtonState: FluentToggleButtonState = .mixed
    @FluentState private var repeatButtonCount = 0
    @FluentState private var slider = 0.62
    @FluentState private var search = ""
    @FluentState private var password = ""
    @FluentState private var selectedAccount: String? = "Work"
    @FluentState private var selectedTheme: String? = "System"
    @FluentState private var editableTheme: String = "Type a theme"
    @FluentState private var editableThemeSelection: String?
    @FluentState private var selectedLongOption: Int? = 21
    @FluentState private var date = Date()
    @FluentState private var quantity = 3
    @FluentState private var checked = true
    @FluentState private var radio = false
    @FluentState private var selectedRadio = true
    @FluentState private var selectedSegment = 0
    @FluentState private var progressMode = 0
    @FluentState private var collectionLayout = 0
    @FluentState private var selectedCollectionItems = Set([2])
    @FluentState private var navigationSelection: String? = "Library"
    @FluentState private var sidebarVisible = true
    @FluentState private var reduceMotion = false
    @FluentState private var teachingTipVisible = false
    @FluentState private var rtlEnabled = false
    @FluentState private var accessibilityLabel = "Notifications control"
    @FluentState private var accessibilityValue = "Enabled"
    @FluentState private var customActionInvocations = 0
    @FluentState private var applicationTabbingMode = 1
    @FluentState private var applicationServiceStatus = "Ready for external events"
    @FluentState private var importPanelVisible = false
    @FluentState private var exportPanelVisible = false

    init(themeStore: FluentThemeStore? = nil) {
        if let themeStore {
            applicationTheme = themeStore
        } else {
            let requestedScheme = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_SCHEME"]
            let scheme: FluentThemeColorScheme = switch requestedScheme {
            case "light": .light
            case "dark": .dark
            case "system": .system
            default: .light
            }
            let contrast: FluentThemeContrast = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_CONTRAST"] == "high"
                ? .high
                : .standard
            applicationTheme = FluentThemeStore(
                FluentTheme.custom(
                    contrast: contrast,
                    colorScheme: scheme,
                    materialEffectsEnabled: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_MATERIALS"] != "0"
                )
            )
        }
        let requestedPage = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_PAGE"]
            .flatMap(GalleryPage.init(rawValue:)) ?? .overview
        _page = FluentState(wrappedValue: requestedPage)
        _isNavigationPaneOpen = FluentState(
            wrappedValue: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_PANE_OPEN"] != "0"
        )
        _reduceMotion = FluentState(
            wrappedValue: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_REDUCE_MOTION"] == "1"
        )
        _teachingTipVisible = FluentState(
            wrappedValue: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_TEACHING_TIP"] == "1"
        )
        _collectionLayout = FluentState(
            wrappedValue: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_COLLECTION_LAYOUT"] == "list"
                ? 1
                : 0
        )
        _rtlEnabled = FluentState(
            wrappedValue: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_DIRECTION"] == "rtl"
        )
    }

    var body: FluentAnyView {
        let theme = applicationTheme.resolvedTheme
        let content = pageContent(theme)
        return FluentAnyView(
            GalleryNavigationShell(
                page: page,
                selection: $page,
                isPaneOpen: $isNavigationPaneOpen,
                search: $search,
                content: content,
                theme: theme,
                reduceMotion: reduceMotion
            )
                .fluentTheme(applicationTheme)
                .fluentLayoutDirection(rtlEnabled ? .rightToLeft : .leftToRight)
        )
    }

    private func pageContent(_ theme: FluentTheme) -> FluentAnyView {
        switch page {
        case .overview: return overviewPage(theme)
        case .controls: return controlsPage(theme)
        case .inputs: return inputsPage(theme)
        case .collections: return collectionsPage(theme)
        case .navigation: return navigationPage(theme)
        case .motion: return motionPage(theme)
        case .application: return applicationPage(theme)
        case .accessibility: return accessibilityPage(theme)
        case .settings: return motionPage(theme)
        }
    }

    private func pageIntroduction(_ text: String, theme: FluentTheme) -> FluentAnyView {
        FluentAnyView(
            FluentText(text, style: .body, color: theme.textSecondary)
        )
    }

    private func overviewPage(_ theme: FluentTheme) -> FluentAnyView {
        let overviewColumns = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_NAV_MODE"] == "minimal"
            ? 2
            : 3
        return FluentAnyView(
            FluentVStack(spacing: 22) {
                FluentVStack(spacing: 8) {
                    FluentText("Build calm, capable desktop apps.", style: .largeTitle)
                    FluentText("A native Swift declaration model with Fluent surfaces, controls, and motion.", style: .body, color: theme.textSecondary)
                }
                .padding(NSEdgeInsets(top: 4, left: 0, bottom: 10, right: 0))
                FluentGrid(columns: overviewColumns, spacing: 12) {
                    FluentVStack(spacing: 5) {
                        FluentText("Design tokens", style: .headline)
                        FluentText("Mica, spacing, and type.", style: .caption, color: theme.textSecondary)
                    }
                    .cardStyle(FluentElevatedCardStyle())
                    .frame(width: 200, height: 110)
                    FluentVStack(spacing: 5) {
                        FluentText("Native controls", style: .headline)
                        FluentText("Native identity and visual states.", style: .caption, color: theme.textSecondary)
                    }
                    .cardStyle(FluentElevatedCardStyle())
                    .frame(width: 200, height: 110)
                    FluentVStack(spacing: 5) {
                        FluentText("Declarative motion", style: .headline)
                        FluentText("Transitions and bindings.", style: .caption, color: theme.textSecondary)
                    }
                    .cardStyle(FluentElevatedCardStyle())
                    .frame(width: 200, height: 110)
                }
                FluentVStack(spacing: 12) {
                    FluentText("Start with a page", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentButtonView("View controls", role: .primary) { page = .controls }
                        FluentButtonView("Explore inputs") { page = .inputs }
                    }
                }
                .padding(20)
                .cardStyle(FluentPlainCardStyle())
            }
        )
    }

    private func controlsPage(_ theme: FluentTheme) -> FluentAnyView {
        let progressState: FluentProgressState = switch progressMode {
        case 1: .paused
        case 2: .error
        default: .normal
        }
        let progressIsIndeterminate = progressMode == 3
        return FluentAnyView(
            FluentVStack(spacing: 20) {
                pageIntroduction("The baseline Fluent states use the same geometry and semantic colors.", theme: theme)
                FluentVStack(spacing: 12) {
                    FluentText("Buttons", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentButtonView("Primary", role: .primary)
                        FluentButtonView("Standard")
                        FluentButtonView("Outline").buttonStyle(FluentOutlineButtonStyle())
                        FluentButtonView("Subtle").buttonStyle(FluentBorderlessButtonStyle())
                        FluentRepeatButtonView("Hold +") { repeatButtonCount += 1 }
                        FluentText("Count \(repeatButtonCount)", style: .caption, color: theme.textSecondary)
                    }
                }
                FluentVStack(spacing: 12) {
                    FluentText("Menus", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentDropDownButton(title: "Menu flyout", items: [
                            FluentMenuItem(
                                "New item",
                                systemImageName: "plus",
                                keyEquivalent: "n"
                            ) {},
                            FluentMenuItem(
                                "Pin",
                                systemImageName: "pin",
                                state: checked ? .on : .off
                            ) { checked.toggle() },
                            .separator,
                            .submenu("More", systemImageName: "ellipsis.circle") {
                                FluentMenuItem("Archive", systemImageName: "archivebox") {}
                                FluentMenuItem("Share", systemImageName: "square.and.arrow.up") {}
                            }
                        ])
                        FluentButtonView("Button flyout")
                            .flyout {
                                FluentMenuItem("Open") {}
                                FluentMenuItem("Rename") {}
                                FluentMenuItem.separator
                                FluentMenuItem("Remove") {}
                            }
                        FluentButtonView("Command bar")
                            .commandBarFlyout {
                                FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") {}
                                FluentCommandBarItem.separator
                                FluentCommandBarItem.toggle(
                                    "Pin",
                                    systemImageName: "pin",
                                    isOn: checked
                                ) { checked = $0 }
                            } secondaryCommands: {
                                FluentCommandBarItem("Archive", systemImageName: "archivebox") {}
                                FluentCommandBarItem.separator
                                FluentCommandBarItem("Share", systemImageName: "square.and.arrow.up") {}
                            }
                        FluentButtonView("Context target")
                            .contextMenu {
                                FluentMenuItem("Open") {}
                                FluentMenuItem("Rename") {}
                                FluentMenuItem.separator
                                FluentMenuItem("Remove") {}
                            }
                    }
                }
                FluentVStack(spacing: 10) {
                    FluentText("Progress", style: .headline)
                    FluentSegmentedControl(
                        ["Normal", "Paused", "Error", "Indeterminate"],
                        selection: $progressMode
                    )
                    FluentProgressBar(
                        value: slider,
                        isIndeterminate: progressIsIndeterminate,
                        state: progressState
                    )
                        .frame(width: 360)
                    FluentText(
                        progressIsIndeterminate ? "Indeterminate" : "\(Int(slider * 100))% complete",
                        style: .caption,
                        color: theme.textSecondary
                    )
                }
                FluentVStack(spacing: 12) {
                    FluentText("Selection and range", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentToggleButtonView("Toggle button", isOn: $toggleButtonEnabled)
                        FluentToggleButtonView(
                            "Three state",
                            state: $toggleButtonState,
                            allowsMixedState: true
                        )
                        FluentToggleButtonView(
                            "Disabled",
                            isOn: FluentBinding(get: { true }, set: { _ in })
                        )
                        .disabled()
                    }
                    FluentHStack(spacing: 18) {
                        FluentToggleView("Notifications", isOn: $notifications)
                        FluentToggleView("Sync", isOn: $syncEnabled)
                        FluentToggleView(
                            "Disabled",
                            isOn: FluentBinding(get: { false }, set: { _ in })
                        )
                        .disabled()
                    }
                    FluentVStack(spacing: 6) {
                        FluentText("Value \(Int(slider * 100))%", style: .caption, color: theme.textSecondary)
                        FluentSliderView(value: $slider)
                            .frame(width: 360)
                    }
                    FluentVStack(spacing: 6) {
                        FluentText("Disabled", style: .caption, color: theme.textSecondary)
                        FluentSliderView(value: FluentBinding(get: { 0.35 }, set: { _ in }))
                            .disabled()
                            .frame(width: 360)
                    }
                    FluentHStack(spacing: 20) {
                        FluentCheckBoxView("Completed", isChecked: $checked)
                        FluentCheckBoxView(
                            "Disabled",
                            isChecked: FluentBinding(get: { false }, set: { _ in })
                        )
                        .disabled()
                    }
                    FluentHStack(spacing: 20) {
                        FluentRadioButtonView("Unselected", isSelected: $radio)
                        FluentRadioButtonView("Selected", isSelected: $selectedRadio)
                        FluentRadioButtonView(
                            "Disabled",
                            isSelected: FluentBinding(get: { false }, set: { _ in })
                        )
                        .disabled()
                    }
                    FluentHStack(spacing: 18) {
                        FluentVStack(spacing: 6) {
                            FluentText("Interactive", style: .caption, color: theme.textSecondary)
                            FluentSegmentedControl(["One", "Two", "Three"], selection: $selectedSegment)
                        }
                        FluentVStack(spacing: 6) {
                            FluentText("Disabled", style: .caption, color: theme.textSecondary)
                            FluentSegmentedControl(
                                ["One", "Two"],
                                selection: FluentBinding(get: { 1 }, set: { _ in })
                            )
                            .disabled()
                        }
                    }
                }
            }
        )
    }

    private func inputsPage(_ theme: FluentTheme) -> FluentAnyView {
        let inputWidth: CGFloat = 280
        let numberBoxPlacement: FluentNumberBoxSpinButtonPlacementMode =
            ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_NUMBERBOX_COMPACT"] == "1"
                ? .compact
                : .inline
        return FluentAnyView(
            FluentVStack(spacing: 20) {
                pageIntroduction("Consistent fields for search, credentials, choices, and values.", theme: theme)
                FluentHStack(spacing: 18, alignment: .top) {
                    FluentVStack(spacing: 16) {
                        FluentText("Text", style: .headline)
                        FluentBoundTextField($search, placeholder: "Search settings")
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                        FluentSecureField($password, placeholder: "Password")
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                        FluentSearchField($search, placeholder: "Filter")
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                    }
                    .frame(width: inputWidth)
                    FluentVStack(spacing: 16) {
                        FluentText("Structured values", style: .headline)
                        FluentDropDownButton(title: selectedAccount ?? "Choose account", items: [
                            FluentMenuItem("Personal", state: selectedAccount == "Personal" ? .on : .off) { selectedAccount = "Personal" },
                            FluentMenuItem("Work", state: selectedAccount == "Work" ? .on : .off) { selectedAccount = "Work" },
                            FluentMenuItem("Shared", state: selectedAccount == "Shared" ? .on : .off) { selectedAccount = "Shared" },
                            .separator,
                            .submenu("Account actions") {
                                FluentMenuItem("Rename account") {}
                                FluentMenuItem("Manage access") {}
                            }
                        ])
                        .frame(width: inputWidth, height: 32)
                        FluentVStack(spacing: 5) {
                            FluentText("Selection", style: .caption, color: theme.textSecondary)
                            FluentComboBox(
                                options: ["System", "Light", "Dark"],
                                selection: $selectedTheme,
                                title: { $0 }
                            )
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                        }
                        FluentVStack(spacing: 5) {
                            FluentText("Editable", style: .caption, color: theme.textSecondary)
                            FluentComboBox(
                                options: ["System", "Light", "Dark"],
                                selection: $editableThemeSelection,
                                mode: .editable,
                                text: $editableTheme,
                                title: { $0 }
                            )
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                        }
                        FluentComboBox(
                            options: Array(1...30),
                            selection: $selectedLongOption,
                            title: { "Option \($0)" }
                        )
                        .textFieldStyle(FluentAutomaticTextFieldStyle())
                        .frame(width: inputWidth, height: 32)
                        FluentDatePicker(selection: $date)
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                        FluentNumberBox(
                            "Items",
                            value: $quantity,
                            in: 1...12,
                            spinButtonPlacement: numberBoxPlacement
                        )
                        .frame(width: inputWidth)
                    }
                    .frame(width: inputWidth)
                }
                FluentVStack(spacing: 8) {
                    FluentText("Validation uses the same surface language.", style: .caption, color: theme.textSecondary)
                    FluentFormField("Workspace name", help: "Use a name teammates will recognize.", validation: .success("Ready to use"), required: true) {
                        FluentBoundTextField($search, placeholder: "Workspace")
                            .textFieldStyle(FluentAutomaticTextFieldStyle())
                            .frame(width: inputWidth, height: 32)
                    }
                }
            }
        )
    }

    private func collectionsPage(_ theme: FluentTheme) -> FluentAnyView {
        var snapshot = FluentCollectionSnapshot<String, Int>()
        snapshot.appendSections(["Pinned", "Recent"])
        snapshot.appendItems([1, 2, 3], toSection: "Pinned")
        snapshot.appendItems([4, 5, 6], toSection: "Recent")
        let layout = collectionLayout == 0
            ? FluentCollectionLayout.adaptiveGrid(minimumItemWidth: 148, itemHeight: 72, spacing: 8)
            : FluentCollectionLayout.list()
        return FluentAnyView(
            FluentVStack(spacing: 18) {
                pageIntroduction("Stable identity, selection, and virtualization for desktop data.", theme: theme)
                FluentSelectorBar([
                    FluentSelectorBarItem(value: 0, title: "Grid", systemImage: "square.grid.2x2"),
                    FluentSelectorBarItem(value: 1, title: "List", systemImage: "list.bullet")
                ], selection: $collectionLayout)
                FluentCollection(
                    snapshot: snapshot,
                    layout: layout,
                    selectionIDs: $selectedCollectionItems,
                    isEnabled: { $0 != 6 },
                    content: { item in
                    FluentText("Item \(item)", style: .body)
                }, header: { section in
                    FluentText(section, style: .caption)
                })
                .frame(height: 360)
                FluentText("Rows preserve their native identity while snapshots change.", style: .caption, color: theme.textSecondary)
            }
        )
    }

    private func navigationPage(_ theme: FluentTheme) -> FluentAnyView {
        FluentAnyView(
            FluentVStack(spacing: 16) {
                pageIntroduction("A split view keeps the sidebar and detail column mounted together.", theme: theme)
                FluentToggleView("Show sidebar", isOn: $sidebarVisible)
                FluentNavigationSplitView(["Home", "Library", "Settings"], id: { $0 }, selection: $navigationSelection, isSidebarVisible: $sidebarVisible, sidebarWidth: 180...300, idealSidebarWidth: 220) { item in
                    FluentText(item, style: .body)
                } detail: { item in
                    FluentVStack(spacing: 8) {
                        FluentText(item, style: .title2)
                        FluentText("Selection drives the detail column without rebuilding the window.", style: .body, color: theme.textSecondary)
                    }
                    .padding(24)
                } placeholder: {
                    FluentText("Choose a destination", style: .body)
                }
                .frame(height: 280)
            }
        )
    }

    private func motionPage(_ theme: FluentTheme) -> FluentAnyView {
        let materialBinding = FluentBinding<Bool>(
            get: { applicationTheme.resolvedTheme.materialEffectsEnabled },
            set: {
                applicationTheme.theme = applicationTheme.resolvedTheme.with(materialEffectsEnabled: $0)
            }
        )
        return FluentAnyView(
            FluentVStack(spacing: 18) {
                pageIntroduction("Material, contrast, and animation are application-level concerns.", theme: theme)
                FluentToggleView("Reduce motion", isOn: $reduceMotion)
                FluentToggleView("Liquid Glass surfaces", isOn: materialBinding)
                FluentHStack(spacing: 10) {
                    FluentButtonView("Light", role: theme.isDark ? .standard : .primary) {
                        applicationTheme.preference = .light
                    }
                    FluentButtonView("Dark", role: theme.isDark ? .primary : .standard) {
                        applicationTheme.preference = .dark
                    }
                }
                FluentButtonView("Show teaching tip") {
                    teachingTipVisible = true
                }
                .teachingTip(
                    isPresented: $teachingTipVisible,
                    placement: .top,
                    size: NSSize(width: 300, height: 126)
                ) {
                    FluentVStack(spacing: 7) {
                        FluentText("Motion follows intent", style: .headline)
                        FluentText("Separate entrance and exit curves.", style: .body, color: theme.textSecondary)
                        FluentText("Liquid Glass elevation preserves context.", style: .caption, color: theme.textSecondary)
                    }
                }
                .fluentReduceMotion(reduceMotion)
                FluentMaterialSurface(role: .transient, cornerRadius: theme.cardCornerRadius) {
                    FluentVStack(spacing: 10) {
                        FluentText("Material surface", style: .headline)
                        FluentText("Liquid Glass follows the global surface switch.", style: .body, color: theme.textSecondary)
                    }
                    .padding(20)
                }
                .frame(width: 500)
            }
        )
    }

    private func applicationPage(_ theme: FluentTheme) -> FluentAnyView {
        let tabbingTitles = ["Automatic", "Preferred", "Disabled"]
        let resolvedTabbing = tabbingTitles[min(max(applicationTabbingMode, 0), tabbingTitles.count - 1)]

        return FluentAnyView(
            FluentVStack(spacing: 18) {
                pageIntroduction(
                    "Scene roles and native macOS events remain declarative at the app boundary.",
                    theme: theme
                )
                FluentVStack(spacing: 10) {
                    FluentText("Settings scene", style: .headline)
                    FluentText("A singleton settings window opens from the standard application menu.", style: .body, color: theme.textSecondary)
                    FluentButtonView("Request settings scene") {
                        applicationServiceStatus = "Settings scene requested"
                    }
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 10) {
                    FluentText("Native window tabs", style: .headline)
                    FluentSegmentedControl(tabbingTitles, selection: $applicationTabbingMode)
                    FluentText("Tabbing policy: \(resolvedTabbing)", style: .caption, color: theme.textSecondary)
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 10) {
                    FluentText("Open events", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentButtonView("Open file") {
                            applicationServiceStatus = "Received Project.fluent"
                        }
                        FluentButtonView("Open URL") {
                            applicationServiceStatus = "Received fluentkit://workspace/42"
                        }
                    }
                    FluentText(applicationServiceStatus, style: .caption, color: theme.textSecondary)
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 10) {
                    FluentText("Files and restored state", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentButtonView("Import JSON") {
                            importPanelVisible = true
                        }
                        .fileImporter(
                            isPresented: $importPanelVisible,
                            configuration: FluentFileImportConfiguration(
                                allowedContentTypes: [.json],
                                prompt: "Import"
                            )
                        ) { result in
                            switch result {
                            case let .success(urls):
                                applicationServiceStatus = "Imported \(urls.count) file(s)"
                            case .failure:
                                applicationServiceStatus = "Import cancelled"
                            }
                        }
                        FluentButtonView("Export JSON") {
                            exportPanelVisible = true
                        }
                        .fileExporter(
                            isPresented: $exportPanelVisible,
                            configuration: FluentFileExportConfiguration(
                                contentType: .json,
                                defaultFilename: "workspace.json",
                                prompt: "Export"
                            )
                        ) { result in
                            switch result {
                            case let .success(url):
                                applicationServiceStatus = "Export destination: \(url.lastPathComponent)"
                            case .failure:
                                applicationServiceStatus = "Export cancelled"
                            }
                        }
                    }
                    FluentText("Restoration schema v2 - atomic migration ready", style: .caption, color: theme.textSecondary)
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 10) {
                    FluentText("System menus", style: .headline)
                    FluentHStack(spacing: 10) {
                        FluentDropDownButton(title: "Workspace actions", items: [
                        FluentMenuItem("New workspace") {
                            applicationServiceStatus = "New workspace requested"
                        },
                        FluentMenuItem("Show settings") {
                            applicationServiceStatus = "Settings scene requested"
                        }
                        ])
                        FluentButtonView("Run text service") {
                            applicationServiceStatus = "Service provider transformed selected text"
                        }
                    }
                    FluentText("Native Services providers use the same pasteboard routing boundary.", style: .caption, color: theme.textSecondary)
                }
                .cardStyle(FluentPlainCardStyle())
            }
        )
    }

    private func accessibilityPage(_ theme: FluentTheme) -> FluentAnyView {
        let auditStatus = galleryAccessibilityAuditStatus()
        let rotor = FluentAccessibilityRotor("Headings", entries: [
            FluentAccessibilityRotorEntry(identifier: "gallery.accessibility.heading.one", label: "Semantic heading"),
            FluentAccessibilityRotorEntry(identifier: "gallery.accessibility.heading.two", label: "Localized heading")
        ])

        return FluentAnyView(
            FluentVStack(spacing: 18) {
                pageIntroduction(
                    "Semantic composition, live labels, rotors, announcements, and right-to-left layout.",
                    theme: theme
                )
                FluentVStack(spacing: 10) {
                    FluentText("Layout direction", style: .headline)
                    FluentHStack(spacing: 12) {
                        FluentToggleView("Right-to-left", isOn: $rtlEnabled)
                        FluentText(
                            rtlEnabled ? "Right-to-left navigation and controls" : "Left-to-right navigation and controls",
                            style: .caption,
                            color: theme.textSecondary
                        )
                    }
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 10) {
                    FluentText("Live semantics", style: .headline)
                    FluentToggleView("Notifications", isOn: $notifications)
                        .accessibilityLabel($accessibilityLabel)
                        .accessibilityValue($accessibilityValue)
                    FluentText("Change the label or value in code and the mounted native control updates in place.", style: .caption, color: theme.textSecondary)
                    FluentLocalizedText(
                        "gallery.accessibility.localized",
                        defaultValue: "Localized content from FluentLocalization",
                        style: .body
                    )
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 10) {
                    FluentText("Actions and focus", style: .headline)
                    FluentButtonView("Invoke custom action") {
                        customActionInvocations += 1
                    }
                    .accessibilityAction(FluentAccessibilityAction("Reset custom action count") {
                        customActionInvocations = 0
                    })
                    .accessibilityAnnounceOnFocus("Custom action sample focused")
                    FluentText("Custom action invocations: \(customActionInvocations)", style: .caption, color: theme.textSecondary)
                }
                .cardStyle(FluentPlainCardStyle())
                FluentVStack(spacing: 8) {
                    FluentText("Semantic heading", style: .headline)
                        .accessibilityElement(children: .ignore, label: "Semantic heading", identifier: "gallery.accessibility.heading.one")
                    FluentHStack(spacing: 8) {
                        FluentText("Account", style: .body)
                        FluentText("Work", style: .body, color: theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine, label: "Account, Work", identifier: "gallery.accessibility.account")
                    FluentText("Localized heading", style: .headline)
                        .accessibilityElement(children: .ignore, label: "Localized heading", identifier: "gallery.accessibility.heading.two")
                }
                .accessibilityRotor(rotor)
                .cardStyle(FluentPlainCardStyle())
                FluentText(auditStatus, style: .caption, color: theme.textSecondary)
            }
        )
    }

    private func galleryAccessibilityAuditStatus() -> String {
        let root = NSView(frame: .zero)
        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.setAccessibilityElement(true)
        saveButton.setAccessibilityRole(.button)
        saveButton.setAccessibilityLabel("Save")
        root.addSubview(saveButton)
        let issueCount = FluentAccessibilityAudit.run(on: root).count
        return issueCount == 0
            ? "Sample semantic audit: passed (0 issues)"
            : "Sample semantic audit: \(issueCount) issue(s)"
    }
}

struct GalleryScreen: FluentView {
    private let undoCoordinator = FluentUndoCoordinator()
    private let applicationTheme = FluentThemeStore()
    @FluentState private var searchText = ""
    @FluentState private var searchFocused = false
    @FluentState private var sliderValue = 0.58
    @FluentState private var notificationsEnabled = true
    @FluentState private var selectedSetting: String? = "General"
    @FluentState private var showingConfirmation = false
    @FluentState private var advancedExpanded = true
    @FluentState private var selectedMode = 0
    @FluentState private var selectedDate = Date()
    @FluentState private var accentColor = NSColor.systemBlue
    @FluentState private var notes = ""
    @FluentState private var collectionLayout = 0
    @FluentState private var selectedCollectionItems = Set([2, 5])
    @FluentState private var selectedOutlineItem: String? = "design"
    @FluentState private var selectedTableRow: Int? = 2
    @FluentState private var password = ""
    @FluentState private var selectedTheme: String? = "System"
    @FluentState private var quantity = 2
    @FluentState private var richNotes = NSAttributedString(string: "Select text to try formatting, then use Replace all.")
    @FluentState private var richSelection = FluentTextSelection()
    @FluentState private var navigationSelection: String? = "Library"
    @FluentState private var navigationSidebarVisible = true
    @FluentState private var inspectorVisible = true
    @FluentState private var sheetVisible = false
    @FluentState private var popoverVisible = false
    @FluentState private var reduceMotion = false
    @FluentState private var choreographyExpanded = false
    @FluentState private var geometryExpanded = false
    @FluentState private var themeDensity = 1
    @FluentState private var highContrastTheme = false
    @FluentState private var showCompleted = true
    @FluentState private var primaryChoice = false
    @FluentNamespace private var geometryNamespace
    @FluentAnimatedState(animation: nil) private var motionProgress: CGFloat = 0

    var body: FluentAnyView {
        let undoState = undoCoordinator.state.value
        let notificationsBinding = $notificationsEnabled.undoable(
            using: undoCoordinator,
            actionName: "Toggle notifications"
        )
        let removeButton = FluentButton(title: "Remove selection")
        removeButton.onClick = { showingConfirmation = true }
        let undoButton = FluentButton(
            title: undoState.undoActionName.isEmpty ? "Undo" : "Undo \(undoState.undoActionName)"
        )
        undoButton.isEnabled = undoState.canUndo
        undoButton.onClick = undoCoordinator.undo
        let redoButton = FluentButton(
            title: undoState.redoActionName.isEmpty ? "Redo" : "Redo \(undoState.redoActionName)"
        )
        redoButton.isEnabled = undoState.canRedo
        redoButton.onClick = undoCoordinator.redo

        var collectionSnapshot = FluentCollectionSnapshot<String, Int>()
        collectionSnapshot.appendSections(["Pinned", "Recent"])
        collectionSnapshot.appendItems([1, 2, 3], toSection: "Pinned")
        collectionSnapshot.appendItems([4, 5, 6], toSection: "Recent")
        let collectionLayoutValue = collectionLayout == 0
            ? FluentCollectionLayout.adaptiveGrid(minimumItemWidth: 128, itemHeight: 64, spacing: 8)
            : FluentCollectionLayout.list(rowHeight: 38, spacing: 2)
        let outlineNodes = [
            FluentOutlineNode(id: "workspace", children: [
                FluentOutlineNode(id: "design") { FluentText("Design", size: 13) },
                FluentOutlineNode(id: "code") { FluentText("Code", size: 13) }
            ]) { FluentText("Workspace", size: 13, weight: .semibold) },
            FluentOutlineNode(id: "archive", children: [
                FluentOutlineNode(id: "history") { FluentText("History", size: 13) }
            ]) { FluentText("Archive", size: 13, weight: .semibold) }
        ]
        let tableRows = [
            GalleryTableRow(id: 1, name: "Alpha", state: "Ready"),
            GalleryTableRow(id: 2, name: "Beta", state: "Running"),
            GalleryTableRow(id: 3, name: "Gamma", state: "Paused")
        ]
        let richEditor = FluentRichTextEditor(
            $richNotes,
            selection: $richSelection,
            placeholder: "Compose formatted notes",
            minimumHeight: 128,
            maximumHeight: 210
        )
        let selectedDensity: FluentThemeDensity
        switch themeDensity {
        case 0: selectedDensity = .compact
        case 2: selectedDensity = .spacious
        default: selectedDensity = .regular
        }
        let selectedThemePreference = applicationTheme.preference
        let choreographyContent = choreographyExpanded
            ? FluentAnyView(
                FluentVStack(spacing: 4) {
                    FluentText("Expanded panel", size: 14, weight: .semibold)
                    FluentText("Insertion and removal use independent effects.", size: 12, color: FluentTheme.current.textSecondary)
                }
                .padding(10)
                .background(FluentTheme.current.cardFill, cornerRadius: 6)
            )
            : FluentAnyView(
                FluentText("Compact panel", size: 14, weight: .semibold)
                    .padding(10)
                    .background(FluentTheme.current.cardFill, cornerRadius: 6)
            )
        let geometryContent = geometryExpanded
            ? FluentAnyView(
                FluentVStack(spacing: 4) {
                    FluentText("Matched card", size: 14, weight: .semibold)
                    FluentText("The frame and size interpolate together.", size: 12, color: FluentTheme.current.textSecondary)
                }
                .padding(10)
                .background(FluentTheme.current.controlFillSecondary, cornerRadius: 8)
                .frame(width: 220, height: 62)
                .matchedGeometryEffect(id: "gallery-card", in: geometryNamespace)
            )
            : FluentAnyView(
                FluentZStack {
                    FluentAnyView(FluentText("Card", size: 14, weight: .semibold))
                }
                .background(FluentTheme.current.controlFillSecondary, cornerRadius: 8)
                .frame(width: 120, height: 46)
                .matchedGeometryEffect(id: "gallery-card", in: geometryNamespace)
            )

        let page = FluentVStack(spacing: 14) {
            FluentText("FluentKit", size: 28, weight: .semibold)
            FluentText("Declarative desktop UI, rendered natively with AppKit", size: 14, color: FluentTheme.current.textSecondary)
            FluentDivider()
            FluentText("Controls", size: 16, weight: .semibold)
            FluentText("Collection preview", size: 13, color: FluentTheme.current.textSecondary)
            FluentSelectorBar([
                FluentSelectorBarItem(value: 0, title: "Grid", systemImage: "square.grid.2x2"),
                FluentSelectorBarItem(value: 1, title: "List", systemImage: "list.bullet")
            ], selection: $collectionLayout)
            FluentCollection(
                snapshot: collectionSnapshot,
                layout: collectionLayoutValue,
                selectionIDs: $selectedCollectionItems,
                content: { item in FluentText("Item \(item)", size: 13) },
                header: { section in FluentText(section, size: 12, weight: .semibold) }
            )
            .frame(height: 142)
            FluentBoundTextField($searchText, placeholder: "Search settings")
                .accessibilityLabel("Search settings")
                .accessibilityHint("Filters the settings list")
                .focused($searchFocused)
            FluentTextEditor($notes, placeholder: "Notes", minimumHeight: 82)
                .accessibilityLabel("Settings notes")
            FluentFormSection("Rich text") {
                richEditor
                FluentHStack(spacing: 8) {
                    FluentButtonView("Bold", action: richEditor.toggleBold)
                    FluentButtonView("Italic", action: richEditor.toggleItalic)
                    FluentButtonView("Underline", action: richEditor.toggleUnderline)
                    FluentButtonView("Center", action: { richEditor.perform(.alignment(.center)) })
                    FluentButtonView("Replace", action: { _ = richEditor.replaceAll("text", with: "content") })
                }
                FluentHStack(spacing: 8) {
                    FluentButtonView("Add attachment") {
                        guard let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attachment") else { return }
                        richEditor.insertAttachment(FluentTextAttachment(
                            id: "gallery-paperclip",
                            image: image,
                            filename: "paperclip.tiff",
                            accessibilityLabel: "Paperclip attachment"
                        ))
                    }
                    FluentButtonView("Clear format", action: richEditor.clearFormatting)
                }
            }
            FluentFormSection("Navigation workspace") {
                FluentBoundToggle($navigationSidebarVisible, title: "Show navigation sidebar")
                FluentNavigationSplitView(
                    ["Home", "Library", "Settings"],
                    id: { $0 },
                    selection: $navigationSelection,
                    isSidebarVisible: $navigationSidebarVisible,
                    sidebarWidth: 170...280,
                    idealSidebarWidth: 210
                ) { item in
                    FluentText(item, size: 13)
                } detail: { item in
                    FluentVStack(spacing: 8) {
                        FluentText(item, size: 20, weight: .semibold)
                        FluentText("Stable selection drives this native detail column.", size: 13, color: FluentTheme.current.textSecondary)
                    }
                    .padding(24)
                } placeholder: {
                    FluentText("Choose a destination", size: 14, color: FluentTheme.current.textSecondary)
                        .padding(24)
                }
                .frame(height: 230)
            }
            FluentFormSection("Inspector presentation") {
                FluentBoundToggle($inspectorVisible, title: "Show inspector")
                FluentInspector(
                    isPresented: $inspectorVisible,
                    width: 180...280,
                    idealWidth: 220,
                    content: {
                        FluentVStack(spacing: 6) {
                            FluentText("Workspace", size: 15, weight: .semibold)
                            FluentText("The main content stays mounted while the pane resizes.", size: 12, color: FluentTheme.current.textSecondary)
                        }
                        .padding(16)
                    },
                    inspector: {
                        FluentVStack(spacing: 6) {
                            FluentText("Properties", size: 14, weight: .semibold)
                            FluentText("Trailing material pane", size: 12, color: FluentTheme.current.textSecondary)
                        }
                    }
                )
                .frame(height: 128)
            }
            FluentFormSection("Sheet presentation") {
                FluentButtonView("Open editor sheet") { sheetVisible = true }
            }
            FluentFormSection("Motion") {
                FluentBoundToggle($reduceMotion, title: "Reduce motion")
                FluentText("Progress: \(Int(motionProgress * 100))%", size: 13, color: FluentTheme.current.textSecondary)
                FluentProgressBar(value: Double(motionProgress))
                FluentText("Animated value", size: 15, weight: .semibold)
                    .opacity(0.25 + motionProgress * 0.75)
                    .scaleEffect(0.85 + motionProgress * 0.15)
                    .offset(x: (motionProgress - 0.5) * 48)
                FluentHStack(spacing: 8) {
                    FluentButtonView("Timing") {
                        _motionProgress.animatedValue.set(
                            motionProgress < 0.5 ? 1 : 0,
                            animation: FluentAnimationTransaction(duration: 0.45, curve: .easeInOut),
                            reduceMotion: reduceMotion
                        )
                    }
                    FluentButtonView("Spring") {
                        _motionProgress.animate(
                            to: motionProgress < 0.5 ? 1 : 0,
                            spring: FluentSpringAnimation(stiffness: 190, damping: 18)
                        )
                        if reduceMotion { _motionProgress.animatedValue.finish() }
                    }
                    FluentButtonView("Keyframes") {
                        _motionProgress.animatedValue.animate(
                            using: FluentKeyframeAnimation(
                                keyframes: [
                                    FluentKeyframe(offset: 0, value: motionProgress),
                                    FluentKeyframe(offset: 0.55, value: 1),
                                    FluentKeyframe(offset: 1, value: 0.35)
                                ],
                                duration: 0.7,
                                curve: .easeInOut
                            ),
                            reduceMotion: reduceMotion
                        )
                    }
                    FluentButtonView("Finish") { _motionProgress.animatedValue.finish() }
                }
                FluentButtonView(choreographyExpanded ? "Collapse panel" : "Expand panel") {
                    choreographyExpanded.toggle()
                }
                choreographyContent
                    .transition(
                        FluentTransition.asymmetric(
                            insertion: FluentTransition.move(edge: .trailing).combined(with: .crossFade),
                            removal: FluentTransition.scale.combined(with: .crossFade)
                        ),
                        animation: FluentAnimationTransaction(duration: 0.28, curve: .easeOut)
                    )
                    .fluentReduceMotion(reduceMotion)
                    .frame(height: 62)
                FluentButtonView(geometryExpanded ? "Reset matched card" : "Expand matched card") {
                    geometryExpanded.toggle()
                }
                geometryContent
                    .transition(.crossFade, animation: FluentAnimationTransaction(duration: 0.32, curve: .easeInOut))
                    .fluentReduceMotion(reduceMotion)
                    .frame(height: 72)
            }
            FluentFormSection("Styles and theming") {
                FluentSegmentedControl(["Compact", "Regular", "Spacious"], selection: $themeDensity)
                    .segmentedStyle(FluentNeutralSegmentedStyle())
                FluentBoundToggle($highContrastTheme, title: "High contrast")
                FluentHStack(spacing: 8) {
                    FluentButtonView("System", role: selectedThemePreference == .system ? .primary : .standard) {
                        applicationTheme.preference = .system
                    }
                    FluentButtonView("Light", role: selectedThemePreference == .light ? .primary : .standard) {
                        applicationTheme.preference = .light
                    }
                    FluentButtonView("Dark", role: selectedThemePreference == .dark ? .primary : .standard) {
                        applicationTheme.preference = .dark
                    }
                }
                FluentHStack(spacing: 8) {
                    FluentButtonView("Standard")
                    FluentButtonView("Accent").buttonStyle(FluentAccentButtonStyle())
                    FluentButtonView("Outline").buttonStyle(FluentOutlineButtonStyle())
                    FluentButtonView("Inline").buttonStyle(FluentBorderlessButtonStyle())
                }
                FluentToggleView("Styled notifications", isOn: $notificationsEnabled)
                    .toggleStyle(FluentMonochromeToggleStyle())
                FluentSliderView(value: $sliderValue, range: 0...1)
                    .sliderStyle(FluentNeutralSliderStyle())
                FluentTextFieldView(text: $searchText, placeholder: "Underline style")
                    .textFieldStyle(FluentUnderlineTextFieldStyle())
                FluentHStack(spacing: 14) {
                    FluentCheckBoxView("Completed", isChecked: $showCompleted)
                        .checkBoxStyle(FluentMonochromeCheckBoxStyle())
                    FluentRadioButtonView("Primary", isSelected: $primaryChoice)
                        .radioButtonStyle(FluentAutomaticRadioButtonStyle())
                }
                FluentVStack(spacing: 6) {
                    FluentText("A reusable card style", weight: .semibold)
                    FluentText("Density and contrast are inherited by this subtree.", style: .caption)
                }
                .cardStyle(FluentElevatedCardStyle())
            }
            .fluentDensity(selectedDensity)
            .fluentContrast(highContrastTheme ? .high : .standard)
            .fluentTheme(applicationTheme)
            FluentFormSection("Input and validation", footer: "Native AppKit editors share the same binding and validation model.") {
                FluentFormField(
                    "Account name",
                    help: "Required for workspace sharing.",
                    validation: searchText.isEmpty ? .error("Enter a name to continue") : .success("Ready to share"),
                    required: true
                ) {
                    FluentTextFieldView(text: $searchText, placeholder: "Name")
                }
                FluentFormField("Password", help: "Stored only in this sample.") {
                    FluentSecureField($password, placeholder: "Password")
                        .textFieldStyle(FluentUnderlineTextFieldStyle())
                }
                FluentFormField("Theme", help: "The selection keeps its stable value.") {
                    FluentComboBox(
                        options: ["System", "Light", "Dark"],
                        selection: $selectedTheme,
                        title: { $0 }
                    )
                    .textFieldStyle(FluentUnderlineTextFieldStyle())
                }
                FluentFormField("Quantity", help: "Clamped to the supported range.") {
                    FluentStepper("Items", value: $quantity, in: 1...12, step: 1)
                        .stepperStyle(FluentInlineStepperStyle())
                }
            }
            .controlSize(.regular)
            FluentHStack(spacing: 10) {
                FluentButtonView("Primary", role: .primary) { showingConfirmation = true }
                    .controlSize(.large)
                FluentButtonView("Delete", role: .destructive) { showingConfirmation = true }
                    .controlSize(.small)
            }
            FluentSearchField(
                $searchText,
                placeholder: "Search controls",
                style: FluentAutomaticTextFieldStyle(),
                onSubmit: { searchFocused = true }
            )
                .accessibilityLabel("Search controls")
            FluentHStack(spacing: 10) {
                FluentButton(title: "Primary action")
                FluentNativeView({
                    let button = FluentButton(title: "Disabled action")
                    button.isEnabled = false
                    return button
                }())
                FluentButtonView("Details") { popoverVisible = true }
                    .popover(isPresented: $popoverVisible, placement: .bottom, size: NSSize(width: 280, height: 180)) {
                        FluentVStack(spacing: 10) {
                            FluentText("Quick details", size: 16, weight: .semibold)
                            FluentText("Popover content is composed from the same Fluent view values.", size: 13, color: FluentTheme.current.textSecondary)
                        }
                    }
            }
            FluentHStack(spacing: 10) {
                FluentDragSource(NSString(string: "FluentKit sample")) {
                    FluentText("Drag this label", size: 13, color: FluentTheme.current.textSecondary)
                }
                FluentDropTarget(types: [.string]) {
                    FluentText("Drop text here", size: 13, color: FluentTheme.current.textSecondary)
                } onDrop: { _ in }
            }
            FluentBoundToggle(notificationsBinding, title: "Use notifications")
            FluentHStack(spacing: 10) {
                undoButton
                redoButton
            }
            FluentVStack(spacing: 8) {
                FluentText("Opacity: \(Int(sliderValue * 100))%", size: 13, color: FluentTheme.current.textSecondary)
                FluentBoundSlider($sliderValue)
            }
            FluentList(
                rows: [
                    FluentText("General", size: 13),
                    FluentText("Notifications", size: 13),
                    FluentText("Privacy", size: 13)
                ],
                id: { $0.value },
                selectionID: $selectedSetting
            )
            .frame(height: 118)
            FluentText("Tables and outline", size: 16, weight: .semibold)
            FluentTable(
                rows: tableRows,
                id: { $0.id },
                selectionID: $selectedTableRow
            ) {
                FluentTableColumn("name", title: "Name", width: 150) { row in
                    FluentText(row.name, size: 13)
                }
                FluentTableColumn("state", title: "State", width: 110) { row in
                    FluentText(row.state, size: 13)
                }
            }
            .frame(height: 142)
            FluentOutline(nodes: outlineNodes, selectionID: $selectedOutlineItem)
                .frame(height: 142)
            FluentHStack(spacing: 10) {
                FluentDropDownButton(title: "Options", items: [
                    FluentMenuItem("Focus search") { searchFocused = true },
                    .separator,
                    FluentMenuItem("Notifications", state: notificationsEnabled ? .on : .off) {
                        notificationsBinding.wrappedValue = !notificationsBinding.wrappedValue
                    }
                ])
                removeButton
            }
            FluentDisclosureGroup("Appearance", isExpanded: $advancedExpanded) {
                FluentVStack(spacing: 8) {
                    FluentSegmentedControl(["Light", "Dark", "System"], selection: $selectedMode)
                    FluentHStack(spacing: 10) {
                        FluentDatePicker(selection: $selectedDate)
                            .textFieldStyle(FluentUnderlineTextFieldStyle())
                        FluentColorPicker(selection: $accentColor, label: "Accent color")
                    }
                    FluentAnyView(FluentForEach(["Light", "Dark", "System"], id: { $0 }) { mode in
                        FluentText("Theme: \(mode)", size: 13, color: FluentTheme.current.textSecondary)
                            .contextMenu {
                                FluentMenuItem("Choose \(mode)") {}
                            }
                    })
                }
            }
        }
        let content = FluentScrollView(.vertical) {
            page
                .fluentFocusScope()
                .padding(NSEdgeInsets(top: 34, left: 44, bottom: 36, right: 44))
        }
        let presented = content
            .sheet(isPresented: $sheetVisible, title: "FluentKit editor", size: NSSize(width: 480, height: 300)) {
                FluentVStack(spacing: 10) {
                    FluentText("Editor sheet", size: 20, weight: .semibold)
                    FluentText("This window is presented by AppKit while its content remains declarative.", size: 13, color: FluentTheme.current.textSecondary)
                    FluentBoundTextField($searchText, placeholder: "Sheet text")
                }
            }
            .fluentUndoScope(undoCoordinator)
            .confirmationDialog(
            "Remove setting?",
            isPresented: $showingConfirmation,
            message: selectedSetting.map { "The \($0) setting will be removed from this sample." } ?? "No setting is selected."
        ) {
            FluentDialogAction("Remove", role: .destructive)
            FluentDialogAction("Cancel", role: .cancel)
        }.fluentCommandGroups {
            FluentCommandGroup("Editing") {
                FluentCommand("Focus search", keyEquivalent: "f") { searchFocused = true }
            }
        }.toolbar {
            FluentToolbarItem("search", label: "Search", toolTip: "Focus search") {
                FluentButtonView("Search") { searchFocused = true }
            }
            FluentToolbarItem.flexibleSpace
            FluentToolbarItem("remove", label: "Remove", toolTip: "Remove selected setting") {
                FluentButtonView("Remove") { showingConfirmation = true }
            }
        }
        return FluentAnyView(presented)
    }
}

private final class GalleryBackdropView: NSView {
    var fillColor: NSColor {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, fillColor: NSColor) {
        self.fillColor = fillColor
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        dirtyRect.fill()
    }
}

final class GalleryWindowController: NSWindowController {
    static let rootHostIdentifier = NSUserInterfaceItemIdentifier("FluentGallery.RootHost")
    private var appearanceCoordinator: FluentAppearanceCoordinator?
    private var appearanceRegistration: UUID?
    static var contentSize: NSSize {
        guard ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_PATH"] != nil else {
            return NSSize(width: 980, height: 680)
        }
        let environment = ProcessInfo.processInfo.environment
        let width = CGFloat(Double(environment["FLUENTKIT_SNAPSHOT_WIDTH"] ?? "") ?? 980)
        let height = CGFloat(Double(environment["FLUENTKIT_SNAPSHOT_HEIGHT"] ?? "") ?? 680)
        return NSSize(width: max(width, 420), height: max(height, 420))
    }

    convenience init() {
        let theme = Self.requestedTheme()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FluentKit Gallery"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        // Behind-window Liquid Glass needs a composited window so NavigationView and transient
        // surfaces can sample the desktop instead of only the Gallery's flat content fill.
        window.isOpaque = false
        window.backgroundColor = .clear
        self.init(window: window)
        let appearanceCoordinator = FluentAppearanceCoordinator(theme: theme)
        appearanceCoordinator.attach(to: window)
        self.appearanceCoordinator = appearanceCoordinator
        let contentView = makeContentView()
        contentView.frame = NSRect(origin: .zero, size: Self.contentSize)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        window.setContentSize(Self.contentSize)
        window.contentMinSize = ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_PATH"] == nil
            ? NSSize(width: 780, height: 540)
            : NSSize(width: 420, height: 420)
        window.center()
    }

    private func makeContentView() -> NSView {
        let requestedTheme = Self.requestedTheme()
        let themeStore = FluentThemeStore(requestedTheme)
        appearanceCoordinator?.bind(to: themeStore)
        let theme = appearanceCoordinator?.resolvedTheme ?? themeStore.resolvedTheme
        let root = GalleryBackdropView(frame: NSRect(origin: .zero, size: Self.contentSize), fillColor: theme.windowBackground)
        let base = GalleryBackdropView(frame: root.bounds, fillColor: theme.windowBackground)
        base.autoresizingMask = [.width, .height]
        root.addSubview(base)
        let material = FluentMaterialView(material: .mica)
        material.fluentTheme = theme
        material.tintColor = theme.micaTint.withAlphaComponent(theme.isDark ? 0.28 : 0.20)
        material.alphaValue = theme.isDark ? 0.22 : 0.18
        material.isMaterialEnabled = theme.materialEffectsEnabled
        material.fallbackColor = theme.windowBackground
        material.isHidden = ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_PATH"] != nil
        let content: FluentAnyView
        switch ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_SCENE"] {
        case "navigation":
            content = FluentAnyView(GalleryNavigationSnapshot())
        case "styles":
            content = FluentAnyView(GalleryStyleSnapshot())
        default:
            content = FluentAnyView(WinUIStyleGalleryScreen(themeStore: themeStore))
        }
        let host = FluentViewHost(
            content,
            context: FluentRenderContext(
                theme: theme,
                spacing: theme.designTokens.spacingMedium,
                appearanceCoordinator: appearanceCoordinator
            )
        )
        host.identifier = Self.rootHostIdentifier
        material.frame = root.bounds
        material.autoresizingMask = [.width, .height]
        root.addSubview(material)
        root.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            host.topAnchor.constraint(equalTo: root.topAnchor),
            host.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        if let appearanceCoordinator {
            appearanceRegistration = appearanceCoordinator.register(owner: root, updateImmediately: false) {
                [weak root, weak base, weak material] theme in
                root?.fillColor = theme.windowBackground
                base?.fillColor = theme.windowBackground
                material?.fluentTheme = theme
                material?.tintColor = theme.micaTint.withAlphaComponent(theme.isDark ? 0.28 : 0.20)
                material?.alphaValue = theme.isDark ? 0.22 : 0.18
                material?.isMaterialEnabled = theme.materialEffectsEnabled
                material?.fallbackColor = theme.windowBackground
            }
        }
        return root
    }

    private static func requestedTheme() -> FluentTheme {
        let scheme: FluentThemeColorScheme = switch ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_SCHEME"] {
        case "dark": .dark
        case "system": .system
        default: .light
        }
        let contrast: FluentThemeContrast = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_CONTRAST"] == "high"
            ? .high
            : .standard
        return FluentTheme.custom(
            contrast: contrast,
            colorScheme: scheme,
            materialEffectsEnabled: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_MATERIALS"] != "0"
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: GalleryWindowController!
    private var snapshotPresentationPrepared = false

    private var snapshotPresentationDelay: TimeInterval {
        let milliseconds = Double(ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_PRESENTATION_DELAY_MS"] ?? "200") ?? 200
        return min(max(milliseconds, 0), 2_000) / 1_000
    }

    private func captureAfterPresentationDelay(window: NSWindow) {
        DispatchQueue.main.asyncAfter(deadline: .now() + snapshotPresentationDelay) { [weak self, weak window] in
            guard let self, let window else { return }
            self.captureSnapshotIfRequested(window: window)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = GalleryWindowController()
        let snapshotRequested = ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_PATH"] != nil
        if !snapshotRequested {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let window = self?.controller.window else { return }
            window.setContentSize(GalleryWindowController.contentSize)
            if let contentView = window.contentView {
                contentView.autoresizingMask = [.width, .height]
                contentView.frame = NSRect(origin: .zero, size: GalleryWindowController.contentSize)
            }
            self?.prepareSnapshotPresentationIfRequested(window: window)
        }
    }

    private func prepareSnapshotPresentationIfRequested(window: NSWindow) {
        let openMenu = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_OPEN_MENU"] == "1"
        let openCombo = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_OPEN_COMBO"] == "1"
        let openDatePicker = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_OPEN_DATE_PICKER"] == "1"
        let openContextMenu = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_OPEN_CONTEXT_MENU"] == "1"
        let openTextCommands = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_OPEN_TEXT_COMMANDS"] == "1"
        let expandTextCommands = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_EXPAND_TEXT_COMMANDS"] == "1"
        let focusSearch = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_FOCUS_SEARCH"] == "1"
        let focusNumberBox = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_FOCUS_NUMBERBOX"] == "1"
        let navigationTarget = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_NAV_SELECT"]
        let toggleNavigationPane = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_TOGGLE_PANE"] == "1"
        let menuTitle = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_MENU_TITLE"]
        let highlightedMenuItem = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_HIGHLIGHT_MENU_ITEM"]
        let needsPresentationAction = openMenu
            || openCombo
            || openDatePicker
            || openContextMenu
            || openTextCommands
            || focusSearch
            || focusNumberBox
            || navigationTarget != nil
            || toggleNavigationPane
        guard needsPresentationAction, !snapshotPresentationPrepared else {
            captureSnapshotIfRequested(window: window)
            return
        }
        snapshotPresentationPrepared = true
        window.contentView?.layoutSubtreeIfNeeded()
        guard let root = window.contentView else {
            captureSnapshotIfRequested(window: window)
            return
        }
        if openTextCommands, let searchField = firstSearchField(in: root) {
            window.makeKeyAndOrderFront(nil)
            searchField.stringValue = "Search text"
            _ = window.makeFirstResponder(searchField)
            searchField.selectText(nil)
            postRightClick(on: searchField)
        } else if focusSearch, let searchField = firstSearchField(in: root) {
            window.makeKeyAndOrderFront(nil)
            _ = window.makeFirstResponder(searchField)
            searchField.selectText(nil)
        } else if focusNumberBox, let numberBox = firstNumberBox(in: root) {
            window.makeKeyAndOrderFront(nil)
            _ = window.makeFirstResponder(numberBox.textField)
            numberBox.textField.selectText(nil)
            numberBox.controlTextDidBeginEditing(
                Notification(name: NSControl.textDidBeginEditingNotification, object: numberBox.textField)
            )
        } else if openMenu, let menuButton = firstMenuButton(in: root, title: menuTitle) {
            window.makeKeyAndOrderFront(nil)
            postPrimaryClick(on: menuButton)
        } else if openMenu, let button = firstFluentButton(in: root, title: menuTitle) {
            window.makeKeyAndOrderFront(nil)
            postPrimaryClick(on: button)
        } else if openCombo, let comboBox = firstComboBoxTrigger(
            in: root,
            value: ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_COMBO_VALUE"]
        ) {
            window.makeKeyAndOrderFront(nil)
            postPrimaryClick(on: comboBox)
        } else if openDatePicker, let datePicker = firstDatePicker(in: root) {
            window.makeKeyAndOrderFront(nil)
            datePicker.performClick(nil)
        } else if openContextMenu,
                  let contextTarget = firstView(withAccessibilityTitle: "Context menu", in: root) {
            // Posted pointer events are only dispatched to an ordered window. This branch is
            // limited to the explicit context-menu snapshot mode.
            window.makeKeyAndOrderFront(nil)
            postRightClick(on: contextTarget)
        } else if let navigationTarget,
                  let item = firstView(withAccessibilityTitle: navigationTarget, in: root) {
            _ = item.accessibilityPerformPress()
            captureAfterPresentationDelay(window: window)
            return
        } else if toggleNavigationPane,
                  let toggle = firstView(identifier: "FluentKit.NavigationView.PaneToggle", in: root) {
            _ = toggle.accessibilityPerformPress()
            captureAfterPresentationDelay(window: window)
            return
        } else {
            captureSnapshotIfRequested(window: window)
            return
        }
        if openTextCommands, expandTextCommands {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
                guard let self, let window,
                      let commandContent = window.childWindows?.first?.contentView,
                      let moreButton = self.firstView(withAccessibilityTitle: "More", in: commandContent) else {
                    if let self, let window { self.captureSnapshotIfRequested(window: window) }
                    return
                }
                _ = moreButton.accessibilityPerformPress()
                self.captureAfterPresentationDelay(window: window)
            }
            return
        }
        guard openMenu else {
            captureAfterPresentationDelay(window: window)
            return
        }
        if let highlightedMenuItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
                guard let self, let window,
                      let menuContent = window.childWindows?.first?.contentView,
                      let row = self.firstView(withAccessibilityTitle: highlightedMenuItem, in: menuContent),
                      let event = NSEvent.mouseEvent(
                        with: .mouseMoved,
                        location: row.convert(NSPoint(x: 6, y: row.bounds.midY), to: nil),
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: row.window?.windowNumber ?? 0,
                        context: nil,
                        eventNumber: 1,
                        clickCount: 0,
                        pressure: 0
                      ) else {
                    if let self, let window { self.captureSnapshotIfRequested(window: window) }
                    return
                }
                row.mouseEntered(with: event)
                self.captureAfterPresentationDelay(window: window)
            }
            return
        }
        guard let submenuTitle = ProcessInfo.processInfo.environment["FLUENTKIT_GALLERY_OPEN_SUBMENU"] else {
            captureAfterPresentationDelay(window: window)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
            guard let self, let window,
                  let menuContent = window.childWindows?.first?.contentView,
                  let submenuRow = self.firstView(withAccessibilityTitle: submenuTitle, in: menuContent) else {
                if let self, let window { self.captureSnapshotIfRequested(window: window) }
                return
            }
            _ = submenuRow.accessibilityPerformPress()
            self.captureAfterPresentationDelay(window: window)
        }
    }

    private func postPrimaryClick(on view: NSView) {
        postMouseClick(on: view, downType: .leftMouseDown, upType: .leftMouseUp)
    }

    private func postRightClick(on view: NSView) {
        postMouseClick(on: view, downType: .rightMouseDown, upType: .rightMouseUp)
    }

    private func postMouseClick(
        on view: NSView,
        downType: NSEvent.EventType,
        upType: NSEvent.EventType
    ) {
        guard let window = view.window else { return }
        let localPoint: NSPoint
        if view is NSComboBox || view.identifier?.rawValue == "FluentKit.ComboBox.EditableText" {
            // Both selection and editable ComboBox paths reserve the trailing glyph column
            // for opening the popup. Center clicks must remain available for editable text.
            localPoint = NSPoint(x: view.bounds.maxX - 8, y: view.bounds.midY)
        } else {
            localPoint = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        let location = view.convert(localPoint, to: nil)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let eventNumber = 1
        guard let down = NSEvent.mouseEvent(
            with: downType,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: upType,
            location: location,
            modifierFlags: [],
            timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber + 1,
            clickCount: 1,
            pressure: 0
        ) else { return }
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)
    }

    private func firstMenuButton(in view: NSView, title: String? = nil) -> FluentDropDownButton? {
        if let button = view as? FluentDropDownButton,
           title == nil || button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap { self.firstMenuButton(in: $0, title: title) }.first
    }

    private func firstFluentButton(in view: NSView, title: String? = nil) -> FluentButton? {
        if let button = view as? FluentButton,
           title == nil || button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap { self.firstFluentButton(in: $0, title: title) }.first
    }

    private func firstComboBoxTrigger(in view: NSView, value: String? = nil) -> NSView? {
        if let field = view as? NSTextField,
           (field is NSComboBox || field.identifier?.rawValue == "FluentKit.ComboBox.EditableText"),
           value == nil || field.stringValue == value {
            return field
        }
        return view.subviews.lazy.compactMap { self.firstComboBoxTrigger(in: $0, value: value) }.first
    }

    private func firstDatePicker(in view: NSView) -> NSDatePicker? {
        if let datePicker = view as? NSDatePicker { return datePicker }
        return view.subviews.lazy.compactMap(firstDatePicker).first
    }

    private func firstSearchField(in view: NSView) -> NSSearchField? {
        if let searchField = view as? NSSearchField { return searchField }
        return view.subviews.lazy.compactMap(firstSearchField).first
    }

    private func firstNumberBox(in view: NSView) -> FluentNumberBoxControl? {
        if let numberBox = view as? FluentNumberBoxControl { return numberBox }
        return view.subviews.lazy.compactMap(firstNumberBox).first
    }

    private func firstView(withAccessibilityTitle title: String, in view: NSView) -> NSView? {
        if view.accessibilityTitle() == title { return view }
        return view.subviews.lazy.compactMap { self.firstView(withAccessibilityTitle: title, in: $0) }.first
    }

    private func firstView(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        return view.subviews.lazy.compactMap { self.firstView(identifier: identifier, in: $0) }.first
    }

    private func captureSnapshotIfRequested(window: NSWindow, attempt: Int = 0) {
        guard let outputPath = ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_PATH"] else { return }
        func fail(_ message: String) {
            fputs("FluentGallery snapshot failed: \(message)\n", stderr)
            NSApp.terminate(nil)
        }
        func retry(_ message: String) {
            guard attempt < 8 else {
                fail("\(message) after \(attempt + 1) attempts")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                guard let self, let window else { return }
                self.captureSnapshotIfRequested(window: window, attempt: attempt + 1)
            }
        }

        let targetView: NSView
        let snapshotSize: NSSize
        let childDepth = Int(ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_CHILD_DEPTH"] ?? "")
            ?? (ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_CHILD_PANEL"] == "1" ? 1 : 0)
        if childDepth > 0 {
            var targetWindow: NSWindow? = window
            for _ in 0..<childDepth { targetWindow = targetWindow?.childWindows?.first }
            guard let childView = targetWindow?.contentView else {
                retry("child panel at depth \(childDepth) did not appear")
                return
            }
            targetView = childView
            snapshotSize = childView.bounds.size
        } else {
            guard let contentView = window.contentView else {
                retry("window content view did not appear")
                return
            }
            let windowContentSize = GalleryWindowController.contentSize
            if windowContentSize.width > 0, windowContentSize.height > 0 {
                contentView.translatesAutoresizingMaskIntoConstraints = true
                contentView.autoresizingMask = [.width, .height]
                contentView.frame = NSRect(origin: .zero, size: windowContentSize)
                contentView.subviews
                    .filter { $0.identifier != GalleryWindowController.rootHostIdentifier }
                    .forEach { $0.frame = contentView.bounds }
            }
            targetView = contentView
            snapshotSize = windowContentSize
        }

        let bounds = targetView.bounds.integral
        guard bounds.width > 0, bounds.height > 0 else {
            retry("snapshot target remained at \(bounds.size)")
            return
        }
        targetView.window?.displayIfNeeded()
        targetView.layoutSubtreeIfNeeded()
        if ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_CAPTURE_PRESENTATION"] == "1" {
            freezeAnimatedPresentation(in: targetView)
        }
        targetView.displayIfNeeded()
        let snapshotBounds = NSRect(origin: .zero, size: snapshotSize).integral
        let requestedScale = CGFloat(Double(ProcessInfo.processInfo.environment["FLUENTKIT_SNAPSHOT_SCALE"] ?? "") ?? 1)
        let snapshotScale = min(max(requestedScale, 1), 3)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(snapshotBounds.width * snapshotScale),
            pixelsHigh: Int(snapshotBounds.height * snapshotScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fail("could not allocate a \(snapshotScale)x AppKit snapshot bitmap for \(snapshotBounds.size)")
            return
        }
        bitmap.size = snapshotBounds.size
        targetView.cacheDisplay(in: bounds, to: bitmap)
        guard snapshotContainsRenderedContent(bitmap) else {
            retry("captured bitmap remained visually empty")
            return
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fail("AppKit could not encode the rendered bitmap as PNG")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        } catch {
            fail("could not write \(outputPath): \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    private func freezeAnimatedPresentation(in view: NSView) {
        func freeze(_ layer: CALayer) {
            let presentationAnimationKeys = (layer.animationKeys() ?? []).filter {
                $0.hasPrefix("fluent.popup.")
                    || $0.hasPrefix("fluent.navigation.")
            }
            if !presentationAnimationKeys.isEmpty, let presentation = layer.presentation() {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.position = presentation.position
                layer.bounds = presentation.bounds
                layer.transform = presentation.transform
                layer.opacity = presentation.opacity
                CATransaction.commit()
                presentationAnimationKeys.forEach(layer.removeAnimation(forKey:))
            }
            if let mask = layer.mask { freeze(mask) }
            layer.sublayers?.forEach(freeze)
        }

        if let layer = view.layer { freeze(layer) }
        view.subviews.forEach { freezeAnimatedPresentation(in: $0) }
    }

    private func snapshotContainsRenderedContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let bytes = bitmap.bitmapData else { return false }
        let bytesPerPixel = max(bitmap.bitsPerPixel / 8, 1)
        guard bytesPerPixel >= 3 else { return false }
        var minimumChannel = UInt8.max
        var maximumChannel = UInt8.min
        let xStride = max(bitmap.pixelsWide / 360, 1)
        let yStride = max(bitmap.pixelsHigh / 300, 1)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStride) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStride) {
                let offset = y * bitmap.bytesPerRow + x * bytesPerPixel
                for channel in 0..<3 {
                    minimumChannel = min(minimumChannel, bytes[offset + channel])
                    maximumChannel = max(maximumChannel, bytes[offset + channel])
                }
                if Int(maximumChannel) - Int(minimumChannel) > 12 { return true }
            }
        }
        return false
    }

    private func snapshotHierarchyDescription(_ root: NSView, depth: Int = 0) -> String {
        guard depth < 5 else { return "..." }
        let name = String(describing: type(of: root))
        let children = root.subviews.map { snapshotHierarchyDescription($0, depth: depth + 1) }
        return "\(name)\(root.frame)[\(children.joined(separator: ","))]"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
