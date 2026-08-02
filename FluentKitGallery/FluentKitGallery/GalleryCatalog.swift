import Foundation

enum GalleryCatalog {
    static let categories: [GalleryCategory] = [
        group("FundamentalsItem", "Fundamentals", "building.columns", special: true, [
            ("XamlResources", "Resources"), ("XamlStyles", "Styles"), ("Binding", "Binding"),
            ("Templates", "Templates"), ("CustomUserControls", "Custom & User Controls"),
            ("CustomXamlConditionals", "XAML Conditions"), ("ScratchPad", "Scratch Pad")
        ]),
        group("DesignItem", "Design", "paintpalette", special: true, [
            ("Color", "Color"), ("Geometry", "Geometry"), ("Iconography", "Iconography"),
            ("Spacing", "Spacing"), ("Typography", "Typography")
        ]),
        group("AccessibilityItem", "Accessibility", "accessibility", special: true, [
            ("AccessibilityColorContrast", "Color contrast"),
            ("AccessibilityKeyboard", "Keyboard support"),
            ("AccessibilityScreenReader", "Screen reader support")
        ]),
        group("MenusAndToolbars", "Menus & toolbars", "menubar.rectangle", [
            ("AppBarButton", "AppBarButton"), ("AppBarSeparator", "AppBarSeparator"),
            ("AppBarToggleButton", "AppBarToggleButton"), ("CommandBar", "CommandBar"),
            ("CommandBarFlyout", "CommandBarFlyout"), ("MenuBar", "MenuBar"),
            ("MenuFlyout", "MenuFlyout"), ("SwipeControl", "SwipeControl"),
            ("StandardUICommand", "StandardUICommand"), ("XamlUICommand", "XamlUICommand")
        ]),
        group("Collections", "Collections", "square.grid.3x3", [
            ("FlipView", "FlipView"), ("GridView", "GridView"), ("ItemsRepeater", "ItemsRepeater"),
            ("ItemsView", "ItemsView"), ("ListBox", "ListBox"), ("ListView", "ListView"),
            ("PullToRefresh", "PullToRefresh"), ("TreeView", "TreeView")
        ]),
        group("DateAndTime", "Date & time", "calendar", [
            ("CalendarDatePicker", "CalendarDatePicker"), ("CalendarView", "CalendarView"),
            ("DatePicker", "DatePicker"), ("TimePicker", "TimePicker")
        ]),
        group("BasicInput", "Basic input", "cursorarrow.click.2", [
            ("Button", "Button"), ("DropDownButton", "DropDownButton"),
            ("HyperlinkButton", "HyperlinkButton"), ("RepeatButton", "RepeatButton"),
            ("ToggleButton", "ToggleButton"), ("SplitButton", "SplitButton"),
            ("ToggleSplitButton", "ToggleSplitButton"), ("CheckBox", "CheckBox"),
            ("ColorPicker", "ColorPicker"), ("ComboBox", "ComboBox"),
            ("RadioButton", "RadioButton"), ("RatingControl", "RatingControl"),
            ("Slider", "Slider"), ("ToggleSwitch", "ToggleSwitch")
        ]),
        group("StatusAndInfo", "Status & info", "info.circle", [
            ("InfoBadge", "InfoBadge"), ("InfoBar", "InfoBar"), ("ProgressBar", "ProgressBar"),
            ("ProgressRing", "ProgressRing"), ("ToolTip", "ToolTip")
        ]),
        group("DialogsAndFlyouts", "Dialogs & flyouts", "rectangle.on.rectangle", [
            ("ContentDialog", "ContentDialog"), ("Flyout", "Flyout"),
            ("Popup", "Popup"), ("TeachingTip", "TeachingTip")
        ]),
        group("Scrolling", "Scrolling", "scroll", [
            ("AnnotatedScrollBar", "AnnotatedScrollBar"), ("PipsPager", "PipsPager"),
            ("ScrollView", "ScrollView"), ("ScrollViewer", "ScrollViewer"),
            ("SemanticZoom", "SemanticZoom")
        ]),
        group("Layout", "Layout", "rectangle.3.group", [
            ("Border", "Border"), ("Canvas", "Canvas"), ("Expander", "Expander"),
            ("Grid", "Grid"), ("RelativePanel", "RelativePanel"), ("SplitView", "SplitView"),
            ("StackPanel", "StackPanel"), ("VariableSizedWrapGrid", "VariableSizedWrapGrid"),
            ("Viewbox", "Viewbox")
        ]),
        group("Navigation", "Navigation", "sidebar.left", [
            ("BreadcrumbBar", "BreadcrumbBar"), ("NavigationView", "NavigationView"),
            ("Pivot", "Pivot"), ("SelectorBar", "SelectorBar"), ("TabView", "TabView")
        ]),
        group("Media", "Media", "photo.on.rectangle", [
            ("AnimatedVisualPlayer", "AnimatedVisualPlayer"),
            ("CaptureElementPreview", "Capture Element / Camera Preview"), ("Image", "Image"),
            ("MapControl", "MapControl"), ("MediaPlayerElement", "MediaPlayerElement"),
            ("PersonPicture", "PersonPicture"), ("Sound", "Sound"), ("WebView2", "WebView2")
        ]),
        group("Styles", "Styles", "paintbrush", [
            ("Acrylic", "AcrylicBrush"), ("AnimatedIcon", "AnimatedIcon"),
            ("CompactSizing", "Compact Sizing"), ("IconElement", "IconElement"),
            ("Line", "Line"), ("Shape", "Shape"), ("RadialGradientBrush", "RadialGradientBrush"),
            ("SystemBackdrops", "System Backdrops (Mica/Acrylic)"),
            ("SystemBackdropElement", "SystemBackdropElement"), ("ThemeShadow", "ThemeShadow")
        ]),
        group("Text", "Text", "textformat", [
            ("AutoSuggestBox", "AutoSuggestBox"), ("NumberBox", "NumberBox"),
            ("PasswordBox", "PasswordBox"), ("RichEditBox", "RichEditBox"),
            ("RichTextBlock", "RichTextBlock"), ("TextBlock", "TextBlock"), ("TextBox", "TextBox")
        ]),
        group("Motion", "Motion", "sparkles", [
            ("XamlCompInterop", "Animation interop"), ("ConnectedAnimation", "Connected Animation"),
            ("EasingFunction", "Easing Functions"), ("ImplicitTransition", "Implicit Transitions"),
            ("PageTransition", "Page Transitions"), ("ThemeTransition", "Theme Transitions"),
            ("ParallaxView", "ParallaxView")
        ]),
        group("MultipleWindows", "Windowing", "macwindow.on.rectangle", [
            ("AppWindow", "AppWindow"), ("AppWindowTitleBar", "AppWindowTitleBar"),
            ("CreateMultipleWindows", "Multiple windows"), ("TitleBar", "TitleBar")
        ]),
        group("System", "System", "desktopcomputer", [
            ("Clipboard", "Clipboard"), ("ContentIsland", "ContentIsland"),
            ("StoragePickers", "Storage pickers")
        ]),
        group("Shell", "Shell", "app.badge", [
            ("AppNotification", "App notifications"),
            ("BadgeNotificationManager", "Badge notifications"), ("JumpList", "JumpList")
        ])
    ]

    static let allItems = categories.flatMap(\.items)
    static let navigationCategories = categories.filter { !$0.isSpecial }

    static func item(id: String) -> GalleryItem? { allItems.first { $0.id == id } }
    static func category(id: String) -> GalleryCategory? { categories.first { $0.id == id } }

    static func search(_ query: String) -> [GalleryItem] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        return allItems.filter { item in
            let categoryTitle = category(id: item.categoryID)?.title ?? ""
            let haystack = "\(item.id) \(item.title) \(categoryTitle)".lowercased()
            return tokens.allSatisfy(haystack.contains)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static var coverageCounts: [GalleryCoverage: Int] {
        Dictionary(grouping: allItems, by: \.coverage).mapValues(\.count)
    }

    private static func group(
        _ id: String,
        _ title: String,
        _ symbolName: String,
        special: Bool = false,
        _ entries: [(String, String)]
    ) -> GalleryCategory {
        GalleryCategory(
            id: id,
            title: title,
            symbolName: symbolName,
            isSpecial: special,
            items: entries.map {
                GalleryItem(
                    id: $0.0,
                    title: $0.1,
                    categoryID: id,
                    coverage: coverage(for: $0.0),
                    isNew: newItems.contains($0.0),
                    isUpdated: updatedItems.contains($0.0)
                )
            }
        )
    }

    private static let implemented: Set<String> = [
        "Button", "RepeatButton", "ToggleButton", "CheckBox", "ColorPicker", "ComboBox",
        "RadioButton", "Slider", "ToggleSwitch", "ProgressBar", "ProgressRing", "TeachingTip",
        "Grid", "SplitView", "StackPanel", "NavigationView", "SelectorBar", "TabView",
        "NumberBox", "PasswordBox", "RichEditBox", "TextBlock", "TextBox", "MenuFlyout",
        "CommandBarFlyout", "ContentDialog", "DatePicker", "Clipboard", "StoragePickers", "TitleBar"
    ]

    private static let partial: Set<String> = [
        "AppBarButton", "AppBarSeparator", "AppBarToggleButton", "CommandBar", "MenuBar",
        "StandardUICommand", "XamlUICommand", "GridView", "ItemsRepeater", "ItemsView", "ListBox",
        "ListView", "TreeView", "CalendarDatePicker", "TimePicker", "DropDownButton",
        "HyperlinkButton", "SplitButton", "ToggleSplitButton", "InfoBadge", "InfoBar", "ToolTip",
        "Flyout", "Popup", "ScrollView", "ScrollViewer", "Border", "Canvas",
        "Expander", "Viewbox", "Image", "IconElement", "Line", "Shape", "SystemBackdrops",
        "SystemBackdropElement", "ThemeShadow", "AutoSuggestBox", "RichTextBlock", "ConnectedAnimation",
        "EasingFunction", "ImplicitTransition", "PageTransition", "ThemeTransition", "AppWindow",
        "AppWindowTitleBar", "CreateMultipleWindows", "Color", "Geometry", "Iconography", "Spacing",
        "Typography", "AccessibilityColorContrast", "AccessibilityKeyboard", "AccessibilityScreenReader"
    ]

    private static let platformAlternative: Set<String> = [
        "CalendarView", "RatingControl", "MediaPlayerElement", "PersonPicture", "Sound", "WebView2",
        "Acrylic", "CompactSizing", "RadialGradientBrush", "XamlResources", "XamlStyles", "Binding",
        "Templates", "CustomUserControls", "ScratchPad", "AppNotification", "BadgeNotificationManager",
        "JumpList"
    ]

    private static let notApplicable: Set<String> = ["CustomXamlConditionals", "XamlCompInterop", "ContentIsland"]

    private static let newItems: Set<String> = [
        "XamlResources", "XamlStyles", "Binding", "Templates", "CustomUserControls",
        "CustomXamlConditionals", "Popup", "SelectorBar", "CaptureElementPreview",
        "SystemBackdropElement", "ThemeShadow", "AppWindow", "ContentIsland", "AppNotification",
        "BadgeNotificationManager", "JumpList"
    ]

    private static let updatedItems: Set<String> = [
        "Iconography", "TabView", "Acrylic", "CompactSizing", "RichEditBox", "TitleBar", "StoragePickers"
    ]

    private static func coverage(for id: String) -> GalleryCoverage {
        if implemented.contains(id) { return .implemented }
        if partial.contains(id) { return .partial }
        if platformAlternative.contains(id) { return .platformAlternative }
        if notApplicable.contains(id) { return .notApplicable }
        return .missing
    }
}
