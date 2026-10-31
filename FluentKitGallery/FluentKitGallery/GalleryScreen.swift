import AppKit
import FluentKit

struct GalleryScreen: FluentView {
    let themeStore: FluentThemeStore
    let navigationCoordinator: FluentNavigationCoordinator<GalleryRoute>
    let undoCoordinator: FluentUndoCoordinator
    @FluentState private var destination: GalleryDestination? = .home
    @FluentState private var selectedItemID: String?
    @FluentState private var isPaneOpen = true
    @FluentState private var searchText = ""
    @FluentState private var toggleValue = true
    @FluentState private var checkValue = true
    @FluentState private var radioValue = false
    @FluentState private var ratingValue = -1.0
    @FluentState private var pipsPage = 2
    @FluentState private var flipPage = 0
    @FluentState private var flipPages = ["Mountains", "Coast", "Forest"]
    @FluentState private var pivotSelection = 0
    @FluentState private var pivotLocked = false
    private let pivotSections = ["All", "Unread", "Flagged", "Urgent"]
    @FluentState private var breadcrumbItems = [
        FluentBreadcrumbBarItem("Home", id: "home", systemImageName: "house"),
        FluentBreadcrumbBarItem("Documents", id: "documents", systemImageName: "folder"),
        FluentBreadcrumbBarItem("Design", id: "design"),
        FluentBreadcrumbBarItem("Northwind", id: "northwind"),
        FluentBreadcrumbBarItem("Images", id: "images"),
        FluentBreadcrumbBarItem("Folder 1", id: "folder-1")
    ]
    @FluentState private var sliderValue = 0.58
    @FluentState private var textValue = ""
    @FluentState private var secureValue = ""
    @FluentState private var comboSelection: String? = "Option 1"
    @FluentState private var numberValue = 3
    @FluentState private var selectorValue: String? = "Recent"
    @FluentState private var dateValue = Date()
    @FluentState private var segmentedDate: Date?
    @FluentState private var selectedTime: FluentTime? = FluentTime(hour: 9, minute: 30)
    @FluentState private var calendarDates: [Date] = []
    @FluentState private var colorValue = NSColor.systemBlue
    @FluentState private var reduceMotion = false
    @FluentState private var infoBarOpen = true
    @FluentState private var sampleExpanded = true
    @FluentState private var expanderExpanded = true
    @FluentState private var expanderUpExpanded = true
    @FluentState private var canGoBack = false
    @FluentState private var canGoForward = false

    var body: FluentAnyView {
        let theme = themeStore.resolvedTheme
        let categoryItems = GalleryCatalog.navigationCategories.map {
            FluentNavigationItem(
                id: GalleryDestination.category($0.id),
                title: $0.title,
                systemImageName: $0.symbolName
            )
        }
        let navigationItems = [
            FluentNavigationItem(id: GalleryDestination.home, title: "Home", systemImageName: "house"),
            FluentNavigationItem(
                id: GalleryDestination.all,
                title: "All controls",
                systemImageName: "square.grid.3x3",
                children: categoryItems,
                isExpanded: true
            )
        ]
        let footer = [
            FluentNavigationItem(id: GalleryDestination.settings, title: "Settings", systemImageName: "gearshape")
        ]
        let selection = FluentBinding<GalleryDestination?>(
            get: { destination },
            set: { value in
                pushRoute(GalleryRoute(destination: value))
            }
        )

        return FluentAnyView(
            FluentWindowShell(
                configuration: FluentWindowConfiguration(
                    layout: .settings,
                    searchPlacement: .titleBar,
                    backdrop: .liquidGlass,
                    contentTransition: .bottomUp
                ),
                title: "FluentKit Gallery",
                subtitle: "WinUI Gallery source comparison",
                systemImageName: "square.grid.2x2.fill",
                isBackButtonVisible: canGoBack || canGoForward,
                isBackButtonEnabled: canGoBack,
                isForwardButtonVisible: canGoBack || canGoForward,
                isForwardButtonEnabled: canGoForward,
                onBack: { goBack() },
                onForward: { goForward() },
                items: navigationItems,
                footerItems: footer,
                selection: selection,
                isPaneOpen: $isPaneOpen,
                openPaneLength: 248,
                compactPaneLength: 48,
                rowHeight: 40,
                paneSectionTitle: nil,
                titleBarContent: {
                    FluentSearchField(
                        $searchText,
                        placeholder: "Search controls and samples...",
                        onSubmit: {
                            pushRoute(
                                GalleryRoute(
                                    destination: destination,
                                    searchText: searchText
                                )
                            )
                        }
                    )
                    .frame(width: 340, height: 32)
                },
                header: {
                    GalleryPageHeader(title: pageTitle, subtitle: pageSubtitle, theme: theme)
                },
                content: {
                    pageViewport(theme)
                }
            )
            .fluentReduceMotion(reduceMotion)
            .fluentNavigationHistory(navigationCoordinator, onNavigate: apply)
            .fluentUndoScope(undoCoordinator)
            .onChange(of: navigationCoordinator.state) { snapshot in
                guard let route = snapshot.current else { return }
                apply(route)
                refreshHistoryAvailability()
            }
        )
    }

    private var selectedItem: GalleryItem? {
        selectedItemID.flatMap { id in GalleryCatalog.allItems.first { $0.id == id } }
    }

    private var pageTitle: String {
        if !searchText.isEmpty { return "Search results" }
        if let selectedItem { return selectedItem.title }
        switch destination ?? .home {
        case .home: return "FluentKit Gallery"
        case .all: return "All controls"
        case let .category(id): return GalleryCatalog.category(id: id)?.title ?? "Controls"
        case .settings: return "Settings"
        }
    }

    private var pageSubtitle: String {
        if !searchText.isEmpty { return "Results for \"\(searchText)\"" }
        if let selectedItem { return "\(selectedItem.coverage.title) · \(selectedItem.id)" }
        switch destination ?? .home {
        case .home: return "A source-driven catalog based on WinUI Gallery 2.9.3"
        case .all: return "121 reference entries across 19 source groups"
        case let .category(id):
            let count = GalleryCatalog.category(id: id)?.items.count ?? 0
            return "\(count) reference entries"
        case .settings: return "Gallery appearance and motion preferences"
        }
    }

    private func pageContent(_ theme: FluentTheme) -> FluentAnyView {
        if !searchText.isEmpty {
            return itemList(GalleryCatalog.search(searchText), emptyMessage: "No results match your search.", theme: theme)
        }
        if let selectedItem { return itemPage(selectedItem, theme: theme) }
        switch destination ?? .home {
        case .home: return homePage(theme)
        case .all: return itemList(GalleryCatalog.allItems, emptyMessage: "No controls.", theme: theme)
        case let .category(id):
            return itemList(GalleryCatalog.category(id: id)?.items ?? [], emptyMessage: "No controls in this category.", theme: theme)
        case .settings: return settingsPage(theme)
        }
    }

    private func pageViewport(_ theme: FluentTheme) -> FluentAnyView {
        if !searchText.isEmpty {
            return itemList(GalleryCatalog.search(searchText), emptyMessage: "No results match your search.", theme: theme)
        }
        if selectedItem == nil {
            switch destination ?? .home {
            case .all:
                return itemList(GalleryCatalog.allItems, emptyMessage: "No controls.", theme: theme)
            case let .category(id):
                return itemList(
                    GalleryCatalog.category(id: id)?.items ?? [],
                    emptyMessage: "No controls in this category.",
                    theme: theme
                )
            case .home, .settings:
                break
            }
        }
        return FluentAnyView(
            FluentScrollView(.vertical) {
                pageContent(theme)
                    .padding(NSEdgeInsets(top: 24, left: 32, bottom: 40, right: 32))
            }
        )
    }

    private func homePage(_ theme: FluentTheme) -> FluentAnyView {
        let counts = GalleryCatalog.coverageCounts
        return FluentAnyView(
            FluentVStack(spacing: 18) {
                FluentSettingsSection("Catalog status", description: "WinUI Gallery 2.9.3 coverage mapped to FluentKit") {
                    FluentSettingsCard(
                        "Implemented",
                        description: "\(counts[.implemented, default: 0]) entries with a direct FluentKit counterpart",
                        systemImageName: "checkmark.circle"
                    )
                    FluentSettingsCard(
                        "Partial",
                        description: "\(counts[.partial, default: 0]) entries with behavior or visual gaps",
                        systemImageName: "circle.lefthalf.filled"
                    )
                    FluentSettingsCard(
                        "macOS alternative",
                        description: "\(counts[.platformAlternative, default: 0]) entries mapped to native facilities",
                        systemImageName: "macwindow"
                    )
                    FluentSettingsCard(
                        "Missing",
                        description: "\(counts[.missing, default: 0]) entries retained as implementation gaps",
                        systemImageName: "questionmark.circle"
                    )
                }
                FluentVStack(spacing: 10) {
                    FluentText("Recently added or updated", style: .headline)
                    FluentText("Entries changed in the WinUI source catalog", style: .caption, color: theme.textSecondary)
                    itemGrid(
                        GalleryCatalog.allItems.filter { $0.isNew || $0.isUpdated },
                        theme: theme
                    )
                    .frame(height: 360)
                }
            }
        )
    }

    private func itemList(_ items: [GalleryItem], emptyMessage: String, theme: FluentTheme) -> FluentAnyView {
        guard !items.isEmpty else {
            return FluentAnyView(
                FluentText(emptyMessage, style: .body, color: theme.textSecondary)
                    .padding(NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32))
            )
        }
        return FluentAnyView(
            itemGrid(items, theme: theme)
                .padding(NSEdgeInsets(top: 8, left: 24, bottom: 24, right: 24))
        )
    }

    private func itemGrid(_ items: [GalleryItem], theme: FluentTheme) -> FluentAnyView {
        var snapshot = FluentCollectionSnapshot<String, String>()
        snapshot.appendSections(["controls"])
        snapshot.appendItems(items.map(\.id), toSection: "controls")
        let selection = FluentBinding<String?>(
            get: { nil },
            set: { id in
                guard let id else { return }
                pushRoute(
                    GalleryRoute(
                        destination: destination,
                        selectedItemID: id
                    )
                )
            }
        )
        return FluentAnyView(
            FluentCollection(
                snapshot: snapshot,
                layout: .adaptiveGrid(
                    minimumItemWidth: 300,
                    itemHeight: 112,
                    spacing: 12,
                    headerHeight: 0
                ),
                selectionID: selection,
                itemStyle: GalleryGridItemStyle()
            ) { id in
                let item = GalleryCatalog.item(id: id)
                GalleryGridTile(item: item, theme: theme)
            }
        )
    }

    private func pushRoute(_ route: GalleryRoute) {
        apply(route)
        _ = navigationCoordinator.push(route)
        refreshHistoryAvailability()
    }

    private func goBack() {
        guard navigationCoordinator.canGoBack,
              let route = navigationCoordinator.goBack() else { return }
        apply(route)
        refreshHistoryAvailability()
    }

    private func goForward() {
        guard navigationCoordinator.canGoForward,
              let route = navigationCoordinator.goForward() else { return }
        apply(route)
        refreshHistoryAvailability()
    }

    private func apply(_ route: GalleryRoute) {
        destination = route.destination
        selectedItemID = route.selectedItemID
        searchText = route.searchText
    }

    private func refreshHistoryAvailability() {
        canGoBack = navigationCoordinator.canGoBack
        canGoForward = navigationCoordinator.canGoForward
    }

    private func itemPage(_ item: GalleryItem, theme: FluentTheme) -> FluentAnyView {
        return FluentAnyView(
            FluentVStack(spacing: 18) {
                FluentSettingsSection("Overview") {
                    FluentSettingsCard(
                        "Coverage",
                        description: coverageExplanation(item.coverage),
                        systemImageName: GalleryCatalog.category(id: item.categoryID)?.symbolName
                    )
                }
                FluentSettingsExpander(
                    "Interactive sample",
                    description: GallerySampleID(rawValue: item.id) == nil ? "No dedicated sample yet" : "Light, Dark and RTL mounting checked; interactive states need the acceptance matrix",
                    systemImageName: "play.circle",
                    isExpanded: $sampleExpanded
                ) {
                    sample(for: item, theme: theme)
                        .padding(24)
                }
                FluentSettingsSection("Source identity") {
                    FluentSettingsCard(
                        "WinUI Gallery reference",
                        description: "\(item.id) · FluentKit coverage: \(item.coverage.title)",
                        systemImageName: "link"
                    )
                }
            }
        )
    }

    func sample(for item: GalleryItem, theme: FluentTheme) -> FluentAnyView {
        guard let sample = GallerySampleID(rawValue: item.id) else {
            return FluentAnyView(FluentText(sampleMessage(for: item), style: .body, color: theme.textSecondary).frame(width: 620))
        }
        switch sample {
        case .Button:
            return FluentAnyView(FluentHStack(spacing: 10) {
                FluentButtonView("Standard")
                FluentButtonView("Primary", role: .primary)
                FluentButtonView("Copy", image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil))
                FluentButtonView("Disabled").disabled(true)
            })
        case .MenuFlyout:
            return FluentAnyView(FluentButtonView("Open menu").flyout {
                FluentMenuItem("New", systemImageName: "doc", action: {})
                FluentMenuItem("Open", systemImageName: "folder", action: {})
                FluentMenuItem.separator
                FluentMenuItem("Settings", systemImageName: "gearshape", action: {})
            })
        case .ToggleSwitch:
            return FluentAnyView(
                FluentToggleView(
                    "Notifications",
                    isOn: $toggleValue.undoable(using: undoCoordinator, actionName: "Toggle Notifications")
                )
            )
        case .CheckBox:
            return FluentAnyView(
                FluentCheckBoxView(
                    "Remember selection",
                    isChecked: $checkValue.undoable(using: undoCoordinator, actionName: "Change Selection")
                )
            )
        case .RadioButton: return FluentAnyView(FluentRadioButtonView("Recommended", isSelected: $radioValue))
        case .RatingControl:
            return FluentAnyView(FluentRatingControlView(
                value: $ratingValue,
                placeholderValue: 3.5,
                caption: "312 ratings"
            ))
        case .PipsPager:
            return FluentAnyView(FluentVStack(spacing: 10) {
                FluentText("Page \(pipsPage + 1) of 8", style: .caption, color: theme.textSecondary)
                FluentPipsPagerView(
                    selectedPageIndex: $pipsPage,
                    numberOfPages: 8,
                    previousButtonVisibility: .visible,
                    nextButtonVisibility: .visible,
                    wrapMode: .wrap
                )
            })
        case .FlipView:
            return FluentAnyView(FluentVStack(spacing: 12) {
                FluentText(flipPages.isEmpty ? "No pages" : "Page \(flipPage + 1) of \(flipPages.count)",
                    style: .caption, color: theme.textSecondary)
                FluentFlipView(flipPages, selection: $flipPage) { title in
                    FluentVStack(spacing: 12) {
                        FluentText(title, style: .title)
                        FluentText("Use the arrows to explore each page.", style: .body,
                            color: theme.textSecondary)
                    }
                    .padding(24)
                    .frame(width: 420, height: 180)
                    .background(theme.cardFill, cornerRadius: 8)
                }
                .frame(width: 420, height: 180)
                FluentHStack(spacing: 8) {
                    FluentButtonView("Last page") { flipPage = flipPages.count - 1 }
                        .disabled(flipPages.isEmpty)
                    FluentButtonView("Remove last") { if !flipPages.isEmpty { flipPages.removeLast() } }
                        .disabled(flipPages.isEmpty)
                    FluentButtonView("Reset") { flipPages = ["Mountains", "Coast", "Forest"]; flipPage = 0 }
                }
                FluentText("Move the pointer to reveal arrows. Scroll or press Left/Right to change pages.",
                    style: .caption, color: theme.textSecondary)
                FluentText("Home/End selects the first/last page. Horizontal navigation mirrors in RTL.",
                    style: .caption, color: theme.textSecondary)
            })
        case .Pivot:
            return FluentAnyView(FluentVStack(spacing: 12) {
                FluentPivot(pivotSections, selection: $pivotSelection, title: "EMAIL", isLocked: pivotLocked,
                    header: { $0 }) { section in
                    FluentVStack(spacing: 8) {
                        FluentText(section, style: .subtitle)
                        FluentText("Messages filtered by \(section.lowercased()).", style: .body,
                            color: theme.textSecondary)
                    }
                    .padding(12)
                }
                .frame(width: 420, height: 220)
                FluentToggleView("Lock to the current item", isOn: $pivotLocked)
                FluentText("Narrow the window to switch to the carousel header. Ctrl+Tab and Ctrl+PageUp/PageDown change items.",
                    style: .caption, color: theme.textSecondary)
            })
        case .BreadcrumbBar:
            return FluentAnyView(FluentVStack(spacing: 10) {
                FluentBreadcrumbBarView(items: breadcrumbItems) { _, index in
                    guard breadcrumbItems.indices.contains(index) else { return }
                    breadcrumbItems = Array(breadcrumbItems.prefix(index + 1))
                }
                .frame(width: 360, height: 32)
                FluentText(
                    "Narrow the sample to reveal source-ordered overflow; choose a level to truncate the path.",
                    style: .caption,
                    color: theme.textSecondary
                )
            })
        case .Slider:
            return FluentAnyView(
                FluentSliderView(
                    value: $sliderValue.undoable(using: undoCoordinator, actionName: "Change Slider")
                ).frame(width: 280)
            )
        case .ProgressBar: return FluentAnyView(FluentProgressBar(value: sliderValue * 100).frame(width: 300))
        case .ProgressRing: return FluentAnyView(FluentNativeView(FluentProgressRing()).frame(width: 32, height: 32))
        case .TextBox: return FluentAnyView(FluentTextFieldView(text: $textValue, placeholder: "Enter text").frame(width: 280))
        case .PasswordBox: return FluentAnyView(FluentSecureField($secureValue, placeholder: "Password").frame(width: 280))
        case .ComboBox:
            return FluentAnyView(
                FluentComboBox(
                    options: ["Option 1", "Option 2", "Option 3"],
                    selection: $comboSelection.undoable(using: undoCoordinator, actionName: "Choose Option")
                ).frame(width: 240)
            )
        case .NumberBox:
            return FluentAnyView(
                FluentNumberBox(
                    "Quantity",
                    value: $numberValue.undoable(using: undoCoordinator, actionName: "Change Quantity"),
                    in: 0...100,
                    spinButtonPlacement: .inline
                ).frame(width: 280)
            )
        case .SelectorBar:
            return FluentAnyView(FluentSelectorBar([
                FluentSelectorBarItem(value: "Recent", title: "Recent", systemImage: "clock"),
                FluentSelectorBarItem(value: "Favorites", title: "Favorites", systemImage: "star")
            ], selection: $selectorValue))
        case .DatePicker:
            return FluentAnyView(FluentVStack(spacing: 12) {
                FluentWinUIDatePickerView(selection: $segmentedDate).frame(width: 296)
                FluentButtonView("Clear date") { segmentedDate = nil }
            })
        case .CalendarDatePicker:
            return FluentAnyView(FluentDatePickerView(selection: $dateValue).frame(width: 240))
        case .TimePicker:
            return FluentAnyView(FluentVStack(spacing: 12) {
                FluentTimePickerView(selection: $selectedTime, minuteIncrement: 5).frame(width: 242)
                FluentButtonView("Clear time") { selectedTime = nil }
            })
        case .CalendarView:
            return FluentAnyView(FluentVStack(spacing: 12) {
                FluentCalendarView(selection: $calendarDates, selectionMode: .multiple)
                    .frame(width: 310, height: 350)
                FluentText("Selected dates: \(calendarDates.count)")
                FluentText("Click the header or press Ctrl+Up / Ctrl+Down to change calendar level.", style: .caption)
            })
        case .ColorPicker: return FluentAnyView(FluentColorPickerView(selection: $colorValue, label: "Accent color"))
        case .ContentDialog:
            return FluentAnyView(ContentDialogGallerySample(theme: theme))
        case .Expander:
            return FluentAnyView(FluentVStack(spacing: 20) {
                FluentExpander(
                    "More details",
                    isExpanded: $expanderExpanded
                ) {
                    FluentText(
                        "The content enters below the 48pt header using WinUI's 333ms expand motion.",
                        style: .body,
                        color: theme.textSecondary
                    )
                }
                .frame(width: 520)
                FluentExpander(
                    "Open upward",
                    isExpanded: $expanderUpExpanded,
                    expandDirection: .up
                ) {
                    FluentText(
                        "ExpandDirection.up places the content surface above its header.",
                        style: .body,
                        color: theme.textSecondary
                    )
                }
                .frame(width: 520)
            })
        case .ToolTip:
            return FluentAnyView(FluentVStack(spacing: 10) {
                FluentHStack(spacing: 12) {
                    FluentButtonView("Pointer ToolTip")
                        .toolTip("Opens after the WinUI pointer delay and remains inside the safe zone.")
                    FluentButtonView("Left placement")
                        .toolTip("Left placement mirrors in right-to-left layouts.", placement: .left)
                }
                FluentText(
                    "Hover a target or reach it from the keyboard; only one automatic ToolTip is visible at a time.",
                    style: .caption,
                    color: theme.textSecondary
                )
            })
        case .AppBarButton:
            return FluentAnyView(FluentAppBarButtonView("查看", systemImageName: "list.bullet", defaultLabelPosition: .right,
                flyoutItems: [FluentMenuItem("Details", action: {}), FluentMenuItem("Properties", isEnabled: false, action: {})]))
        case .CommandBar:
            return FluentAnyView(FluentNativeView(make: {
                let view = FluentCommandBar(primaryCommands: [], secondaryCommands: [FluentCommandBarItem("More commands", systemImageName: "folder", action: {})])
                return view
            }, update: { (view: FluentCommandBar, context) in view.theme = context.theme }).frame(width: 400, height: 48))
        case .Typography:
            return FluentAnyView(FluentVStack {
                FluentText("Display 68", style: .display)
                FluentText("Title Large 40", style: .titleLarge)
                FluentText("Title 28", style: .title)
                FluentText("Subtitle 20", style: .subtitle)
                FluentText("Body 14 · Caption 12", style: .body)
            })
        case .IconElement:
            return FluentAnyView(FluentButtonView("Custom glyph menu").flyout {
                FluentMenuItem("Symbol", icon: .systemSymbol("folder"), action: {})
                FluentMenuItem("Glyph", icon: .glyph("★", font: .systemFont(ofSize: 16)), action: {})
                FluentMenuItem("Path", icon: .path(CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 20, height: 12), transform: nil)), action: {})
            })
        case .SystemBackdrops:
            return FluentAnyView(FluentHStack {
                FluentMaterialSurface(material: .mica) { FluentText("Mica base recipe") }.frame(width: 200, height: 100)
                FluentMaterialSurface(material: .nativeMica) { FluentText("macOS native effect") }.frame(width: 200, height: 100)
            })
        case .AutoSuggestBox:
            return FluentAnyView(FluentAutoSuggestBox($textValue.textInput(.init(commitPolicy: .committedText)), placeholder: "Search after IME commit",
                suggestions: { query in ["Documents", "Downloads", "Desktop"].filter { $0.localizedCaseInsensitiveContains(query) }.map { .init(id: $0, title: $0) } }).frame(width: 320))
        case .ListView:
            return FluentAnyView(FluentListView(Array(0..<5000)) { FluentText("Item \($0)") }.contentVersion { $0 }.frame(width: 420, height: 320))
        case .GridView:
            return FluentAnyView(FluentGridView(Array(0..<100)) { FluentText("Item \($0)") }.contentVersion { $0 }.frame(width: 420, height: 320))
        case .InfoBadge:
            return FluentAnyView(FluentHStack { FluentInfoBadge(); FluentInfoBadge(value: 12); FluentInfoBadge(systemImageName: "checkmark") })
        case .InfoBar:
            return FluentAnyView(FluentVStack {
                FluentButtonView("Show message", action: { infoBarOpen = true })
                FluentInfoBar(isOpen: $infoBarOpen, title: "Saved", message: "Your settings were updated.", severity: .success)
            }.frame(width: 480))
        case .TextBlock:
            return FluentAnyView(FluentVStack { FluentText("Title", style: .title); FluentText("Readable body", style: .body); FluentText("Caption", style: .caption) })
        }
    }

    private func settingsPage(_ theme: FluentTheme) -> FluentAnyView {
        let preferenceSelection: FluentBinding<String?> = themeStore.preferenceBinding.map(
            { (preference: FluentThemePreference) -> String? in
                switch preference {
                case .system: return "System"
                case .light: return "Light"
                case .dark: return "Dark"
                }
            },
            { selection in
                switch selection {
                case "Light": return .light
                case "Dark": return .dark
                default: return .system
                }
            }
        )
        return FluentAnyView(
            FluentVStack(spacing: 16) {
                FluentSettingsSection("Appearance & behavior", description: "Gallery presentation preferences") {
                    FluentSettingsCard(
                        "Application theme",
                        description: "Follow macOS or use an explicit appearance",
                        systemImageName: "circle.lefthalf.filled",
                        showsChevron: false
                    ) {
                        FluentComboBox(
                            options: ["System", "Light", "Dark"],
                            selection: preferenceSelection
                        )
                        .frame(width: 160)
                    }
                    FluentSettingsCard(
                        "Reduce motion",
                        description: "Use static transitions while browsing samples",
                        systemImageName: "figure.walk.motion",
                        showsChevron: false
                    ) {
                        FluentToggleView("Reduce motion", isOn: $reduceMotion)
                    }
                }
                FluentSettingsSection("About") {
                    FluentSettingsCard(
                        "FluentKit Gallery",
                        description: "WinUI Gallery 2.9.3 catalog baseline",
                        systemImageName: "square.grid.2x2.fill"
                    )
                    FluentSettingsCard(
                        "Source compatibility",
                        description: "The original FluentGallery executable remains unchanged for snapshot compatibility.",
                        systemImageName: "checkmark.seal"
                    )
                }
            }
        )
    }

    private func coverageExplanation(_ coverage: GalleryCoverage) -> String {
        switch coverage {
        case .implemented: return "FluentKit has a direct component or service counterpart. This entry has a directly registered sample. State and Windows parity checks remain separate."
        case .partial: return "FluentKit covers the central behavior, but the WinUI surface, variants, or Gallery sample matrix is incomplete."
        case .platformAlternative: return "The Windows-specific concept maps to a native AppKit/macOS facility rather than a literal API clone."
        case .missing: return "No stable FluentKit counterpart is present yet. This entry is retained so the gap stays visible and searchable."
        case .notApplicable: return "This entry depends on XAML or Windows composition infrastructure and should not be reproduced as a public macOS control."
        }
    }

    private func sampleMessage(for item: GalleryItem) -> String {
        switch item.coverage {
        case .implemented: return "A registered sample is available."
        case .partial: return "A partial implementation exists. Add a focused sample only after its visual and interaction contract is audited."
        case .platformAlternative: return "This page will demonstrate the native macOS alternative and document the mapping to WinUI."
        case .missing: return "Planned placeholder. No component is being simulated here."
        case .notApplicable: return "Documentation-only entry for source parity."
        }
    }
}

private struct GalleryPageHeader: FluentView {
    let title: String
    let subtitle: String
    let theme: FluentTheme

    var body: FluentAnyView {
        FluentAnyView(
            FluentVStack(spacing: 5) {
                FluentText(title, style: .title)
                FluentText(subtitle, style: .caption, color: theme.textSecondary)
            }
            .padding(NSEdgeInsets(top: 22, left: 32, bottom: 18, right: 32))
        )
    }
}

private struct GalleryGridTile: FluentView {
    let item: GalleryItem?
    let theme: FluentTheme

    var body: FluentAnyView {
        let category = item.flatMap { GalleryCatalog.category(id: $0.categoryID) }
        return FluentAnyView(
            FluentHStack(spacing: 16) {
                FluentNativeView(gallerySymbolView(
                    name: category?.symbolName ?? "square.dashed",
                    title: item?.title ?? "Control",
                    color: theme.accent
                ))
                .frame(width: 32, height: 32)
                FluentVStack(spacing: 4) {
                    FluentText(item?.title ?? "Unknown control", size: 14, weight: .semibold)
                    FluentText(
                        "\(item?.coverage.title ?? "Missing") · \(category?.title ?? "Controls")",
                        style: .caption,
                        color: theme.textSecondary
                    )
                }
                FluentSpacer()
                FluentText(
                    item?.isNew == true ? "New" : (item?.isUpdated == true ? "Updated" : ""),
                    style: .caption,
                    color: theme.accentFillDefault
                )
            }
        )
    }
}

private struct GalleryGridItemStyle: FluentCollectionItemStyle {
    func appearance(for configuration: FluentCollectionItemStyleConfiguration) -> FluentCollectionItemAppearance {
        let theme = configuration.theme
        let state = configuration.isEnabled ? configuration.controlState : .disabled
        let fill: NSColor = switch state {
        case .pointerOver: theme.controlFillSecondary
        case .pressed: theme.controlFillTertiary
        case .disabled: theme.controlFillDisabled
        default: theme.controlFill
        }
        return FluentCollectionItemAppearance(
            backgroundColor: fill,
            contentInsets: NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
            contentOpacity: configuration.isEnabled ? 1 : 0.4,
            cornerRadius: 8,
            outerBorderColor: theme.cardStroke,
            outerBorderWidth: theme.controlStrokeWidth,
            focusOuterColor: configuration.isFocused ? theme.focusStrokeOuter : .clear,
            focusInnerColor: configuration.isFocused ? theme.focusStrokeInner : .clear
        )
    }
}

private func gallerySymbolView(name: String, title: String, color: NSColor) -> NSImageView {
    let view = NSImageView()
    view.image = NSImage(systemSymbolName: name, accessibilityDescription: title)
    view.imageScaling = .scaleProportionallyDown
    view.contentTintColor = color
    view.setAccessibilityLabel(title)
    return view
}
