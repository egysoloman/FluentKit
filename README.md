# FluentKit

[![CI](https://github.com/egysoloman/FluentKit/actions/workflows/swift.yml/badge.svg)](https://github.com/egysoloman/FluentKit/actions/workflows/swift.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A declarative desktop UI framework inspired by Fluent Design, implemented in native Swift and AppKit.

FluentKit provides a composable foundation for desktop interfaces: Fluent theme tokens, adaptive light and dark appearance, wallpaper-backed Mica, Acrylic blend recipes and opt-in macOS materials, state-aware controls, single- and multiline text editing, localized view updates, and a Swift-native declarative view tree. It deliberately has no markup compatibility layer.

## Button content and document toolbars

Buttons support native images as content, including image-only, leading/trailing, and vertical
placements. Leading/trailing placement follows the reading direction; physical left/right does not.
Image content participates in measurement and survives declarative updates and flyout modifiers:

```swift
FluentButtonView(
    "Copy",
    image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil),
    imagePosition: .imageLeading
)
```

`FluentCommandBar` retains WinUI's default trailing primary-command area and leading content area.
Document toolbars can opt into `bar.primaryCommandAlignment = .leading`, or pass
`primaryCommandAlignment: .leading` to `FluentCommandBarView`. This is an explicit FluentKit
extension, not a change to WinUI's default. In leading mode, More follows the command strip and
custom content uses the remaining trailing space; both arrangements mirror in RTL.

CommandBar refreshes retain native controls and an open overflow menu. For commands that can be
inserted, reordered or moved between groups, provide a unique stable ID, for example
`FluentCommandBarItem(id: "save", "Save", action: save)`. Without an ID, identity follows the
command's group and position. Use `bar.setCommands(primary:secondary:)` to update both groups
together; `FluentCommandBarView` does this automatically. Updated labels, actions, enabled states
and toggle values take effect in the existing controls without invoking actions during rendering.

MenuBar retains open menus and submenus during updates. Use stable `FluentMenuBarItem.id` values
for top-level entries and unique `FluentMenuItem(id: ...)` values within each menu level when
inserting or reordering rows. A standalone `FluentMenuFlyout` accepts `update(items:theme:reduceMotion:)`;
empty menus dismiss their panel. Menu builders support conditions, loops and arrays. The
[MenuBar Gallery sample](FluentKitGallery/FluentKitGallery/MenuBarGallerySample.swift) demonstrates
an update while File › Export is open. Context-menu refreshes also update their wrapped content.

Extended `FluentWindowShell` instances anchor page content below the title bar and fill the
remaining viewport, including embedded `FluentNativeView` trees without an intrinsic height.

## SplitButton and ToggleSplitButton

`FluentSplitButtonView` separates the primary action from its trailing menu. Space/Return invokes
on key release; Option+Down or F4 opens the menu. `FluentToggleSplitButtonView` changes its binding
before invoking the primary action; opening the menu never toggles it. Disabled controls reject both actions.

Supply stable `FluentMenuItem(id:...)` values when menu items can change or reorder. An open menu
receives current labels, enabled states and closures without replacing its panel. Native
`showFlyout()` is idempotent; use `hideFlyout()` to close it. Detaching/hiding the control or closing
its window cancels presses and closes the menu. Toggle bindings also reflect values accepted by
validating setters and ignore deliveries from replaced subscriptions.

The secondary arrow moves downward while that region is pressed, and returns when released,
including while the menu is open. Layout, theme, size and backing changes preserve its current
motion; Reduce Motion settles it immediately. Primary or root keyboard activation changes
the appropriate button chrome without pressing the secondary arrow. Focus loss cancels a
captured press, so a later release cannot invoke an action.

The [interactive samples](FluentKitGallery/FluentKitGallery/SplitButtonGallerySample.swift) cover
both variants, shared checked state, disabled state and delayed menu refresh. Touch-state checks
use synthetic events; physical touch and VoiceOver acceptance remain open.

## AutoSuggestBox

Suggestion lists scroll and keep the keyboard-selected item visible. Supply stable, unique
`FluentAutoSuggestBoxSuggestion.id` values when results can refresh or reorder; omitting an ID
creates a new identity. Escape restores the user's original query in both the field and binding,
even if a refresh removed the selected suggestion. Tab/Shift-Tab restore it while the suggestion
list is open; an already closed list leaves normal Tab behavior unchanged. Clear and query
buttons retain their native actions and accessibility exposure, and are skipped by Tab.
Down/Up navigate an open list, and a single candidate remains selected. External model resets
invalidate old suggestions. Header, text insets, adornments and suggestion rows follow RTL.

`onTextChangedEvent` reports `.userInput`, `.suggestionChosen` or `.programmaticChange` with the
text. Events retain the 150 ms debounce; focus alone does not emit a text change. The existing
`onTextChanged` string callback remains available and receives all three kinds of change. The
callback runs before querying the suggestion provider, so it can update the available results.
Keyboard previews do not re-filter the provider using the previewed candidate title. Use
`.textInput(.init(commitPolicy: .committedText))` to defer publication and suggestion queries
until composition commits.

`maxSuggestionListHeight: 0` hides the popup; negative values use the available screen space,
matching WinUI. The [interactive Gallery sample](FluentKitGallery/FluentKitGallery/AutoSuggestBoxGallerySample.swift)
shows scrolling, delayed result reordering, query submission and external reset.

## Installation

FluentKit supports macOS 12 or later and Swift 5.9 language mode. Add the package dependency to
your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/egysoloman/FluentKit.git",
        from: "0.3.0"
    )
]
```

Then add `FluentKit` to the dependencies of your application target. See
[COMPATIBILITY.md](COMPATIBILITY.md) for the supported baseline and API stability policy.

```swift
struct SettingsView: FluentView {
    var body: some FluentView {
        FluentVStack(spacing: 14) {
            FluentText("Settings", size: 24, weight: .semibold)
            FluentNativeView(FluentTextField(placeholder: "Search"))
            FluentNativeView(FluentButton(title: "Save changes"))
            FluentNativeView(FluentToggle(title: "Use notifications", isOn: true))
            FluentNativeView(FluentProgressBar(value: 72))
        }
    }
}

let host = FluentViewHost(SettingsView())
```

When embedding a host in a manually created `NSWindow`, maintain the window's key-view loop
as content changes. Set `window.autorecalculatesKeyViewLoop = true` for AppKit's geometric
Tab order, or maintain `nextKeyView` explicitly for custom navigation. `FluentViewHost` leaves
the owning window's navigation policy to the application.
FluentKit-created scene, detached-tab and sheet windows enable automatic updates.

The included `FluentGallery` executable is a visual sandbox for the components. Build it with `swift build`, then run `.build/debug/FluentGallery`.

For the full native application catalog, open `FluentKitGallery/FluentKitGallery.xcodeproj` in Xcode. The app consumes the local `FluentKit` package and provides searchable component coverage, navigation history, appearance controls, and focused samples for the production Gallery surface.

Long pages use the same declarative composition and stay inside a native scrolling viewport. `FluentTextEditor` provides multiline binding, placeholder, undo, focus styling, and native text-area accessibility:

```swift
FluentScrollView(.vertical) {
    FluentVStack(spacing: 14) {
        FluentBoundTextField($title, placeholder: "Title")
        FluentTextEditor($notes, placeholder: "Notes", minimumHeight: 120)
    }
    .padding(24)
}
```

For a standalone application, conform an `@main` type to `FluentApp`. `FluentWindowScene` creates the native window, installs the optional macOS material, and hosts the same declarative view tree used by embedded `FluentViewHost` instances:

```swift
@main
struct SettingsApp: FluentApp {
    var body: FluentWindowScene<SettingsView> {
        FluentWindowScene(title: "Settings", material: .mica) {
            SettingsView()
        }
    }
}
```

Multiple windows can be composed with `FluentSceneGroup`; each scene keeps its own content, size, material, and stable identifier. IDs must be non-empty and unique within the scene tree:

```swift
@main
struct WorkspaceApp: FluentApp {
    var body: FluentSceneGroup {
        FluentSceneGroup {
            FluentWindowScene(id: "workspace", title: "Workspace") {
                FluentText("Workspace")
            }
            FluentWindowScene(id: "inspector", title: "Inspector", size: NSSize(width: 320, height: 240), material: nil) {
                FluentText("Inspector")
            }
        }
    }
}
```

Use `FluentWindowPlacement` when a scene needs a predictable initial position. `.automatic` centers the first scene and cascades later scenes; `.centered`, `.cascade`, corner placements, and `.origin(x:y:)` are also available. Positions are clamped to the visible screen frame. `FluentWindowRestoration.automatic` (the default) persists the last frame, open-window set, and active window ID by scene ID and restores them on the next launch; use `.disabled` for transient windows. Embedded hosts can call `FluentWindowCoordinator.saveRestorationState()` during termination and `openInitiallyVisibleWindows()` when reconstructing a scene group.

For application-scale window commands, conform the app to `FluentWindowLifecycle`. Its coordinator can open, close, focus, or toggle any scene by stable ID. Set `initiallyVisible: false` on utility scenes that should be created on demand; their presence keeps the application alive after the main window closes:

```swift
struct WorkspaceApp: FluentApp, FluentWindowLifecycle {
    var body: FluentSceneGroup {
        FluentSceneGroup {
            FluentWindowScene(id: "workspace", title: "Workspace") { FluentText("Workspace") }
            FluentWindowScene(id: "inspector", title: "Inspector", initiallyVisible: false) { FluentText("Inspector") }
        }
    }

    func applicationDidLaunch(with windows: FluentWindowCoordinator) {
        windows.perform(.open("inspector"))
    }
}
```

Use `FluentSettingsScene` for a singleton settings window. The runner adds the standard
Command-comma Settings item automatically. `FluentWindowTabbing` controls native window tabs, and
`FluentApplicationServices` receives open-file, open-URL, reopen, and Dock-menu events with the live
window coordinator:

```swift
struct WorkspaceApp: FluentApp, FluentApplicationServices {
    var body: FluentSceneGroup {
        FluentSceneGroup {
            FluentWindowScene(
                id: "workspace",
                title: "Workspace",
                tabbing: .preferred(identifier: "workspace.documents")
            ) {
                WorkspaceView()
            }
            FluentSettingsScene {
                SettingsView()
            }
        }
    }

    func applicationOpenFiles(_ urls: [URL], with windows: FluentWindowCoordinator) {
        _ = windows.open(id: "workspace")
        openDocuments(urls)
    }

    func applicationOpenURLs(_ urls: [URL], with windows: FluentWindowCoordinator) {
        route(urls)
    }

    var applicationDockMenuItems: [FluentMenuItem] {
        [FluentMenuItem("New Workspace") { createWorkspace() }]
    }
}
```

The default reopen behavior restores the first declared scene when no windows are visible. Override
`applicationShouldHandleReopen(hasVisibleWindows:with:)` when an app needs different routing.

The same application-services boundary can publish native macOS Services. `applicationProvidedServices`
routes the service message declared by the app bundle, while `applicationServicesMenuTypes` declares
the pasteboard types the current selection can send or receive from other providers:

```swift
struct WorkspaceApp: FluentApp, FluentApplicationServices {
    var applicationServicesMenuTypes: FluentServicesMenuTypes {
        .init(sendTypes: [.string], returnTypes: [.string])
    }

    var applicationProvidedServices: [FluentProvidedService] {
        [FluentProvidedService(
            identifier: "workspace.uppercase",
            acceptedTypes: [.string],
            returnedTypes: [.string]
        ) { pasteboard, _ in
            guard let value = pasteboard.string(forType: .string) else { return }
            pasteboard.clearContents()
            pasteboard.setString(value.uppercased(), forType: .string)
        }]
    }
}
```

Add one `NSServices` entry for each identifier in the application bundle's `Info.plist`, using
`performFluentService` as `NSMessage` and the identifier as `NSUserData`. This keeps service discovery
in the macOS registry while the handler remains pure Swift. FluentKit also installs the native
Services submenu in the generated application menu.

Binding-driven file dialogs keep native `NSOpenPanel` and `NSSavePanel` behavior while composing
with any declarative view. The binding returns to `false` after user completion or cancellation;
setting it to `false` programmatically dismisses the active sheet without reporting a user result:

```swift
FluentButtonView("Import") { showImporter = true }
    .fileImporter(
        isPresented: $showImporter,
        configuration: .init(
            allowedContentTypes: [.json],
            allowsMultipleSelection: true
        )
    ) { result in
        handleImportedFiles(result)
    }
    .fileExporter(
        isPresented: $showExporter,
        configuration: .init(contentType: .json, defaultFilename: "Workspace.json")
    ) { result in
        handleExportDestination(result)
    }
```

Run `swift test` for the deterministic package test suite used by CI. For the extended desktop acceptance
suite covering state, bindings, theme tokens, public identity APIs, performance, lifecycle cleanup, and
snapshot baselines, run `swift run FluentKitValidation` from an interactive macOS session. Release
compatibility and versioning policy live in [COMPATIBILITY.md](COMPATIBILITY.md), and the current release
is recorded in [VERSION](VERSION).

Gallery popup snapshots can freeze the real Core Animation presentation tree at a repeatable time.
This captures in-flight transforms and clipping instead of the final model layer:

```bash
FLUENTKIT_SNAPSHOT_PATH=/tmp/fluentkit-menu-125ms.png \
FLUENTKIT_GALLERY_PAGE=controls \
FLUENTKIT_GALLERY_OPEN_MENU=1 \
FLUENTKIT_GALLERY_MENU_TITLE="Menu flyout" \
FLUENTKIT_SNAPSHOT_CHILD_PANEL=1 \
FLUENTKIT_SNAPSHOT_PRESENTATION_DELAY_MS=125 \
FLUENTKIT_SNAPSHOT_CAPTURE_PRESENTATION=1 \
swift run FluentGallery
```

MenuFlyout and ComboBox popup dismissal is immediate, so the harness captures entrance motion only.
`FLUENTKIT_GALLERY_DIRECTION=rtl`, `FLUENTKIT_GALLERY_CONTRAST=high`, and
`FLUENTKIT_GALLERY_REDUCE_MOTION=1` exercise the corresponding environment variants. Set
`FLUENTKIT_SNAPSHOT_SCALE=2` for a Retina bitmap while preserving the same logical Gallery
dimensions. `FLUENTKIT_GALLERY_OPEN_DATE_PICKER=1` opens the source-derived
CalendarDatePicker so its shared Fluent calendar grid, hosted inside an AppKit popover, can be captured with
`FLUENTKIT_SNAPSHOT_CHILD_PANEL=1`.
`FLUENTKIT_GALLERY_FOCUS_SEARCH=1` captures the real SearchBox field editor and
`FLUENTKIT_GALLERY_OPEN_TEXT_COMMANDS=1` opens its application-owned text command presenter; combine
the latter with `FLUENTKIT_SNAPSHOT_CHILD_PANEL=1` to capture only that surface. Add
`FLUENTKIT_GALLERY_EXPAND_TEXT_COMMANDS=1` to expand the CommandBar overflow and capture its
secondary Undo, Redo, and Select All rows.

Navigation transitions use the same presentation capture path. `FLUENTKIT_GALLERY_NAV_SELECT`
invokes a destination by accessibility title, while `FLUENTKIT_GALLERY_TOGGLE_PANE=1` opens or
closes the current pane:

```bash
FLUENTKIT_SNAPSHOT_PATH=/tmp/fluentkit-navigation-150ms.png \
FLUENTKIT_GALLERY_PAGE=inputs \
FLUENTKIT_GALLERY_NAV_SELECT=Accessibility \
FLUENTKIT_SNAPSHOT_PRESENTATION_DELAY_MS=150 \
FLUENTKIT_SNAPSHOT_CAPTURE_PRESENTATION=1 \
swift run FluentGallery
```

Every `FluentApp` installs a native App/File/Edit/View/Window/Help menu through
`NSApplication.mainMenu`. Conform to `FluentApplicationCommands` to append application commands to
those standard menus (or create additional named menus). Command groups are rebuilt declaratively,
preserve key equivalents and modifier masks, and reevaluate `isEnabled` when the menu validates:

```swift
@main
struct EditorApp: FluentApp, FluentApplicationCommands {
    var applicationCommandGroups: [FluentCommandGroup] {
        [FluentCommandGroup("File") {
            FluentCommand("Export", keyEquivalent: "e", modifiers: [.command, .shift]) {
                exportDocument()
            }
        }]
    }

    var body: FluentWindowScene<EditorView> {
        FluentWindowScene(title: "Editor") { EditorView() }
    }
}
```

## Roadmap

The framework is built in layers. Milestones 1-13, 16, 18, 20, and 21 are complete. Milestones 14-15
continue to expand text and presentation depth. Milestones 17 and 19 remain in visual acceptance:
their behavior foundations exist, while transient-surface fidelity and the long-tail control set are
still being audited and implemented. The primary Button, ToggleSwitch, Slider, CheckBox, RadioButton,
RatingControl, PipsPager, BreadcrumbBar, Expander, SegmentedControl, ProgressBar, and MenuFlyout state/motion
foundations are now covered by shared
visual-state or presentation contracts and executable validation.

1. Declarative tree, AppKit host, reconciliation, state, bindings, and environment values.
2. Fluent materials, theme tokens, layout containers, native controls, lists, menus, overlays, drag/drop, lifecycle, focus, and accessibility.
3. Scoped keyboard commands, source-aligned Expander (`DisclosureGroup` compatibility), SegmentedControl, DatePicker, ColorPicker, and value-driven navigation.
4. Gallery and executable smoke validation, including native bitmap snapshots for visual regression checks.
5. Native app entry point with single-window scenes, multi-window groups, stable IDs, placement policies, window commands, and lifecycle callbacks.
6. Window frame restoration with opt-out policy, deferred utility windows, and runtime window coordination.
7. Native multiline text editing, unbounded sibling composition in the result builder, stable-ID `FluentForEach` reconciliation, collection accessibility children, and a scrollable Gallery page.
8. Native application main-menu command routing, dynamic command validation, and shared animation timing propagation across environment, transitions, navigation, and disclosure controls.
9. Conservative initial-focus requests, two-way focus bindings, and scoped AppKit key-view loops with nested-scope isolation.
10. Codable application-state restoration with namespaced stores, observable restored bindings, cross-window synchronization, reset semantics, and accessibility-tree reconciliation coverage.
11. Native undo/redo transactions, grouped undoable bindings, observable command state, document dirty tracking, atomic save/revert, delayed autosave, and document-scoped restoration.
12. Sectioned diffable collections with native headers and adaptive grids, stable single- and multi-selection, virtualized tables and outlines, expansion restoration, drag-reorder intents, and large-data smoke benchmarks.
13. Native secure/search input, stable-value combo boxes, range-clamped steppers, validation-aware forms, semantic control sizing, labeled content, and default/cancel keyboard actions.
14. Attributed text and selection bindings, native formatting and find/replace commands, formatting-state observation, stable text attachments, and attachment insertion/enumeration/removal.
15. Stable-ID two-column navigation with a native resizable/collapsible sidebar, bound selection and visibility, declarative detail resolution, stale-selection cleanup, type-safe destination registration, and Codable typed path restoration.
16. Display-driven values, springs, keyframes, Reduce Motion, composable branch transitions, visual transforms, and namespace-scoped matched geometry.
17. Observable application themes, semantic density, contrast, color schemes and typography, plus reusable button, toggle, slider, progress, text-field, and card styles.
18. Scene-specific cubic-bezier motion tokens and Fluent control/presentation choreography.
19. Fluent transient surfaces with opt-in Liquid Glass and a native macOS main menu.
20. Accessibility and localization depth, including RTL behavior and automated semantic audits.
21. Application services such as settings, open events, printing, sharing, and import/export.
22. Production hardening, snapshot baselines, performance/leak tests, documentation, and compatibility policy.

Milestone 13 adds a complete input and form layer: secure and search fields, stable-value combo boxes, range-clamped steppers, validation states, form sections, labeled content, semantic control sizing, and Return/Escape default and cancel actions. Every control is implemented as a native AppKit view and can be embedded directly or through `FluentNativeView`. See [ROADMAP.md](ROADMAP.md) for the staged path toward a complete application framework.

The foundational Milestone 14 text-system slice adds `FluentRichTextEditor`, an attributed `NSTextView` editor with a two-way `NSAttributedString` binding, optional selection binding, native undo, bold/italic/underline, font size, color and alignment operations, formatting-state observation, case-insensitive find, and replace-all. Stable-ID text attachments can be inserted, enumerated, and removed without coupling application models to AppKit attachment identity. Selection remains AppKit-owned while binding updates are de-duplicated and external ranges are coalesced, so drag selection cannot create a main-thread replay queue. The editor remains a normal Fluent view, so it can live inside forms, scroll views, sheets, and navigation destinations.

The current foundation includes automatic dependency tracking for state read while evaluating a view, localized reconciliation for compatible branches, two-way bindings, single- and multiline text editing, native material surfaces, scrolling/list/navigation primitives, single- and multi-window app scenes, stable window commands and frame restoration, native window toolbars, a declarative native main menu coordinator, context menus, popovers, sheets, confirmation dialogs, native drag/drop wrappers, lifecycle callbacks, hover events, composable accessibility modifiers and semantic groups, two-way focus bindings, scoped keyboard command groups, collapsible disclosure groups, segmented selection controls, native date/color pickers, and a value-driven navigation stack. Result-builder composition is not capped at a fixed sibling count. Lists use an NSCollectionView backing store so only visible rows are mounted. Stable-ID lists preserve identity-based selection and move existing native rows during reordering, and support arrow, Home, End, Page Up, and Page Down navigation.

Dynamic branches can opt into explicit identity with `fluentID`: when an identity changes, FluentKit replaces that branch while preserving sibling controls and their native state. Lists also accept an `id:` closure for stable row identities, and `FluentForEach` reuses rows by ID for insertions, removals, reordering, and compatible content updates. A `FluentForEach` host exposes its mounted rows as an accessibility child tree; duplicate IDs deliberately fall back to rebuilding the affected collection so native state is never assigned to an ambiguous row. `FluentCollectionSnapshot` adds section/item identity, cross-section moves, and native `CollectionDifference` reporting. `FluentCollection` renders those snapshots with `NSCollectionView` diffable data, virtualized cells, optional declarative section headers, list or adaptive-grid metrics, and stable single- or multi-selection. `FluentTable` maps stable row IDs and declarative `FluentTableColumn` values to `NSTableViewDiffableDataSource`, while `FluentOutline` preserves expanded and selected node IDs across hierarchy updates. Milestone 20 adds semantic child behavior, live accessibility labels and values, custom actions, focus announcements, custom rotors, locale-aware text, subtree layout direction, and deterministic `FluentAccessibilityAudit` checks.

### Accessibility and localization

Accessibility modifiers preserve the native AppKit identity while making composed branches explicit:

```swift
@FluentState var enabled = true
@FluentState var status = "On"
let label = FluentState(wrappedValue: "Notifications")

FluentToggleView("Updates", isOn: $enabled)
    .accessibilityLabel(label.projectedValue)
    .accessibilityValue($status)
    .accessibilityAction(FluentAccessibilityAction("Reset") { reset() })
    .accessibilityAnnounceOnFocus("Updates control focused")

FluentVStack(spacing: 6) {
    FluentText("Account")
    FluentText("Work")
}
.accessibilityElement(children: .combine, label: "Account, Work", identifier: "account.summary")
.accessibilityRotor(FluentAccessibilityRotor("Headings", entries: [
    FluentAccessibilityRotorEntry(identifier: "heading.account", label: "Account")
]))
```

Use `FluentLocalizedText` for locale-aware resources and apply direction or locale to any subtree:

```swift
FluentLocalizedText("settings.title", defaultValue: "Settings", style: .title)
    .fluentLocale(Locale(identifier: "en_US"))

content.fluentLayoutDirection(isRTL ? .rightToLeft : .leftToRight)
```

Mounted trees can be checked in executable validation or UI tests with
`FluentAccessibilityAudit.run(on:)`; unlabeled interactive roles and duplicate identifiers are
reported as structured issues.

```swift
var snapshot = FluentCollectionSnapshot<String, Int>()
snapshot.appendSections(["pinned", "recent"])
snapshot.appendItems([1, 2], toSection: "pinned")
snapshot.appendItems([3, 4], toSection: "recent")

FluentCollection(
    snapshot: snapshot,
    layout: .adaptiveGrid(minimumItemWidth: 160),
    selectionIDs: $selectedIDs,
    content: { item in FluentText("Item \(item)") },
    header: { section in FluentText(section) }
)
```

`FluentListMoveIntent` makes drag reordering deterministic for model code: its destination is the pre-removal insertion offset, and `applying(to:)` provides a small reference implementation useful for tests and previews.

## Styling and themes

`FluentTheme` carries semantic colors, typography, and control metrics instead of resolved
per-control constants. A theme can select compact, regular, or spacious density;
standard, high, or system-derived contrast; and light, dark, or system color schemes. Subtree
modifiers preserve the inherited accent, material, and other theme values:

```swift
let editorTheme = FluentTheme.custom(
    accent: .systemTeal,
    material: .acrylic,
    density: .compact,
    contrast: .system,
    colorScheme: .system,
    typography: FluentTypography(scale: 1.05)
)

EditorView()
    .fluentTheme(editorTheme)
    .fluentDensity(.spacious)
    .fluentContrast(.high)
    .fluentColorScheme(.dark)
```

`FluentDesignTokens` provides the shared spacing, 32pt control height, 4pt control radius, 8pt
card/overlay radius, content inset, and navigation-pane geometry. All metrics scale through the
selected density. `with(accent:)`, `with(material:)`, `with(colorScheme:)`, `with(density:)`, and
`with(contrast:)` derive a theme without discarding unrelated settings.

Material presets remain the default. Developers can override individual fields through
`FluentMaterialConfiguration`: **local configuration → theme role → control preset**.
Roles are `.window`, `.navigation`, `.transient`, `.toolTip` and `.container`; ToolTips inherit
transient overrides before applying their own role. Optional fields inherit, while a clear
tint explicitly removes an inherited tint. `with(materialConfiguration:nil, for:)` removes
that role's theme override. Theme-copy helpers preserve the other roles.

```swift
let materialTheme = editorTheme
    .with(materialConfiguration: .init(material: .nativeAcrylic), for: .transient)
    .with(materialConfiguration: .init(material: .nativeMica), for: .window)

FluentCardView(configuration: .init(material: .liquidGlass,
    tintColor: NSColor.systemTeal.withAlphaComponent(0.12))) {
    FluentText("Locally customized card")
}

FluentText("A custom surface")
    .padding(16)
    .materialBackground(.nativeAcrylic, cornerRadius: 12)

FluentButtonView("Help") {}
    .toolTip("Themed help")
    .materialConfiguration(.init(material: .nativeAcrylic), for: .toolTip)
```

Cards retain their ordinary style fill unless a local configuration or a `.container` theme
configuration opts them in. `.cardStyle(_:material:configuration:)` offers the same choice.
A generic material background sits behind its content; it does not erase an opaque fill owned
by a nested control. Container visual effects default to `withinWindow`; windows and
transient surfaces use `behindWindow`. An automatic NavigationView pane stays transparent
while inline or closed, and uses in-app Acrylic while open over content. Explicit `.standalone`
ownership retains the theme's persistent navigation material. `blendingMode` can override AppKit visual effects;
system Glass owns its own sampling behavior.

`.mica` reads the desktop image reported by AppKit for each display, caches a blurred version,
and applies the WinUI Mica luminosity and tint stages. It does not sample covered applications.
Inactive windows, unavailable wallpaper images and accessibility policies use an opaque fallback.
Animated wallpaper frames are not captured; the result depends on the still image that AppKit
reports. Image decoding and blur run off the main thread, with a shared cache per display.

`.acrylic` combines AppKit live blur with WinUI luminosity, tint and 2% noise. Its blur kernel
and underlying sampling remain controlled by macOS, so it is not pixel-identical to Windows.
AppKit also colors its backdrop before these blend stages; high-contrast patterns can produce
color contours that differ from a direct Gaussian-blur Acrylic pipeline.
`FluentMaterialConfiguration.tintOpacity` and `.luminosityOpacity` override preset strengths;
nil follows the light/dark preset. `.nativeMica`, `.nativeAcrylic` and `.sidebar` retain AppKit
material backends; `.liquidGlass` uses native Glass when available, with an AppKit popover-effect
fallback on older systems.
Scene windows now default to `.automatic`, allowing theme window overrides; explicit `.mica`
remains an explicit local choice, and `nil` still removes the material surface.
WindowShell lets the Fluent Mica/Acrylic recipe own its tint instead of adding a second blue
chrome overlay. Role and local material configurations still override the presets.

The global material-effects switch, Reduce Transparency and Increase Contrast take precedence
over developer enablement. Translucent fallback colors are flattened over the theme's window
background; High Contrast uses semantic opaque colors. Runtime configuration changes preserve
content and editing identity. Native users can call `FluentMaterialView.configure(theme:role:
configuration:)`; subsequent `fluentTheme` changes retain that binding. The Gallery's
**SystemBackdrops** sample demonstrates scope, local overrides, tint and live editing.

Use `FluentThemeStore` when a running application needs to switch themes. The store participates
in dependency tracking, so replacing its theme reconciles the existing native subtree instead of
rebuilding the host:

```swift
let applicationTheme = FluentThemeStore()

SettingsView()
    .fluentTheme(applicationTheme)

applicationTheme.theme = applicationTheme.theme.with(colorScheme: .dark)
```

Semantic text styles resolve through the current theme's `FluentTypography`. This keeps hierarchy
consistent while allowing application-wide scaling:

```swift
FluentVStack(spacing: 6) {
    FluentText("Workspace", style: .title)
    FluentText("Three pending changes", style: .body)
    FluentText("Updated just now", style: .caption)
}
```

Buttons, repeat/toggle buttons, toggles, sliders, progress bars, check boxes, radio buttons,
segmented controls, and text fields accept reusable state-dependent styles while retaining their native identities and bindings.
The built-in styles cover common action and input emphasis:

```swift
FluentHStack(spacing: 8) {
    FluentButtonView("Save").buttonStyle(FluentAccentButtonStyle())
    FluentButtonView("Preview").buttonStyle(FluentOutlineButtonStyle())
    FluentButtonView("More").buttonStyle(FluentBorderlessButtonStyle())

    FluentRepeatButtonView("Increase", delay: 0.5, interval: 0.033) {
        quantity += 1
    }
}

FluentToggleButtonView("Pin", isOn: $isPinned)

// HyperlinkButton uses WinUI's subtle 83ms hover/pressed surface.
FluentHyperlinkButtonView("Learn more", action: openHelp)

// SplitButton reserves a 35pt trailing MenuFlyout region.
FluentSplitButtonView("Save", action: save) {
    FluentMenuItem("Save as…", action: saveAs)
    FluentMenuItem("Save a copy", action: saveCopy)
}

// Only the primary region toggles; the secondary region opens the MenuFlyout.
FluentToggleSplitButtonView("Favorite", isChecked: $isFavorite) {
    FluentMenuItem("Manage favorites", action: manageFavorites)
}

FluentToggleView("Notifications", isOn: $notifications)
    .toggleStyle(FluentMonochromeToggleStyle())

FluentSliderView(value: $volume)
    .sliderStyle(FluentNeutralSliderStyle())

// ProgressBar follows WinUI RangeBase semantics and defaults to 0...100.
FluentProgressBar(value: downloadFraction * 100)
    .progressStyle(FluentNeutralProgressStyle())

FluentCheckBoxView("Completed", isChecked: $completed)
    .checkBoxStyle(FluentMonochromeCheckBoxStyle())

FluentRadioButtonView("Primary", isSelected: $primary)
    .radioButtonStyle(FluentAutomaticRadioButtonStyle())

// Prefer RadioButtons when several options form one source-compatible selection group.
FluentRadioButtons(
    ["Primary", "Secondary", "Tertiary"],
    selection: $selectedPriority,
    header: "Priority",
    maxColumns: 3
)

FluentRatingControlView(
    value: $rating,
    placeholderValue: 3.5,
    caption: "312 ratings"
)

FluentPipsPagerView(
    selectedPageIndex: $pageIndex,
    numberOfPages: pages.count,
    maxVisiblePips: 5,
    previousButtonVisibility: .visibleOnPointerOver,
    nextButtonVisibility: .visibleOnPointerOver,
    wrapMode: .wrap
)

FluentBreadcrumbBarView(items: breadcrumbPath) { _, index in
    breadcrumbPath = Array(breadcrumbPath.prefix(index + 1))
}
.frame(width: 360, height: 32)

FluentSegmentedControl(["One", "Two"], selection: $mode)
    .segmentedStyle(FluentNeutralSegmentedStyle())

// Page and view switching uses the source-derived per-item SelectorBar pill.
FluentSelectorBar([
    FluentSelectorBarItem(value: 0, title: "Grid", systemImage: "square.grid.2x2"),
    FluentSelectorBarItem(value: 1, title: "List", systemImage: "list.bullet")
], selection: $layout)

FluentTextFieldView(text: $query, placeholder: "Search")
    .textFieldStyle(FluentUnderlineTextFieldStyle())

// Compound inputs reuse the same field appearance contract.
FluentSecureField($password, placeholder: "Password")
    .textFieldStyle(FluentUnderlineTextFieldStyle())

FluentSearchField($query, placeholder: "Filter")
    .textFieldStyle(FluentUnderlineTextFieldStyle())

FluentComboBox(
    options: accounts,
    selection: $selectedAccount,
    title: \.displayName
)
.textFieldStyle(FluentUnderlineTextFieldStyle())

FluentComboBox(
    options: accounts,
    selection: $matchedAccount,
    mode: .editable,
    text: $accountQuery,
    title: \.displayName
)

FluentDatePicker(selection: $dueDate, range: allowedDates)
    .textFieldStyle(FluentUnderlineTextFieldStyle())

// TimePicker keeps a nullable, date-independent time-of-day value. MinuteIncrement accepts
// WinUI's 0...59 range; zero represents a single `00` minute entry.
FluentTimePickerView(
    selection: $departureTime,
    minuteIncrement: 5,
    clockIdentifier: .twelveHour,
    header: "Departure time"
)

FluentNumberBox(
    "Items",
    value: $quantity,
    in: 1...12,
    spinButtonPlacement: .inline
)
```

`FluentNumberBox` is a dedicated NumberBox composition rather than an `NSStepper` skin. Its
`spinButtonPlacement` supports `.hidden`, `.compact`, and `.inline`: Inline reserves the source
76-point trailing column for 32pt increase/decrease buttons separated by 4pt (mirrored in RTL),
while Compact presents the source-sized
vertical spin-button popup only while the native text editor has focus. Empty input maps to `NaN`;
validation, range clamping, wrapping, keyboard stepping, wheel stepping, and accessibility remain
native AppKit behaviors routed through the Fluent control.

`FluentRepeatButton` follows press-mode semantics: pointer-down or Space invokes immediately, the
first repeat occurs after `delay`, and later repeats use `interval`. Its defaults match the source
contract at 500ms and 33ms. Pointer exit, release, focus loss, disabling, Escape, and view removal
cancel the timer; re-entering while pressed starts a fresh delay. Return and accessibility press
remain single invocations.

Hiding the control or an ancestor, moving it to another parent, or deactivating/closing its
window also cancels the captured press. Showing it again does not resume repeating. A callback
that starts a new press retains that press's initial delay. Directional chevrons keep their
position and change foreground color while pressed; they do not use a dropdown arrow's
displacement. Up/down glyphs follow the host's actual coordinate axis, and layout/drawing
preserve foreground transitions under the resolved Reduce Motion policy.

`FluentToggleButton` is distinct from ToggleSwitch: it keeps Button geometry while its bound state
selects Unchecked, Checked, or optional Indeterminate resources. Pointer release, Space/Return,
accessibility, external bindings, and Reduce Motion share the same native state path.

The automatic ToggleSwitch style uses a 40 x 20 track with 12 x 12 normal, 14 x 14 hover, and
17 x 14 pressed/dragging knob geometry. Pointer down changes only the visual state; the binding is
committed once on release, while drag, cancellation, keyboard/accessibility activation, RTL, and
Reduce Motion remain part of the same native control lifecycle.

The automatic Slider style uses a stable 18 x 18 outer thumb around a 12 x 12 accent inner thumb.
The inner visual grows to 14 x 14 on hover, contracts to 10 x 10 while pressed, and returns with the
source-derived 167ms/250ms motion tokens. Pointer position stays direct during dragging; RTL,
Home/End, accessibility increments, cancellation, external bindings, and Reduce Motion share the
same control lifecycle.

CheckBox and RadioButton keep native AppKit control semantics while FluentKit owns their complete
visual surfaces. Pointer down enters a pressed state without changing the binding; release inside
commits once and release outside cancels. CheckBox draws and clears its stable check path with the
source AnimatedAccept 19-frame/four-frame curves. RadioButton uses a 20pt outer circle with
12/14/10/14 dot states and a separate pressed-feedback dot for an unselected press. Both support
RTL, keyboard focus, accessibility activation, external-binding cancellation, and Reduce Motion.
Independent RadioButton values can opt into mutual exclusion with `groupName`; the recommended
`FluentRadioButtons` container owns one optional selection, lays items out column-major, skips
disabled choices, contains arrow navigation at group boundaries, and follows WinUI's
Control+Arrow focus-without-selection behavior.

RatingControl preserves WinUI's `-1` unset sentinel, fractional programmatic and placeholder
values, 16pt star geometry with 8pt spacing, pointer-proximity scaling, preview-before-commit,
click-current-to-clear, drag-to-start-edge clearing, and the fractional keyboard rounding rules.
Left/Right follow layout direction while Up/Down retain logical increase/decrease semantics;
read-only and accessibility adjustment paths share the same bound value lifecycle.

PipsPager preserves WinUI's zero-based selection, `-1` unbounded-page mode, five-pip default
viewport, 4pt normal and 6pt selected/hover glyphs, 12x24 horizontal and 24x12 vertical hit areas,
and 24pt navigation buttons. Finite collections virtualize around the visible range; the selected
pip is centered with source-style scrolling, while edge hiding, pointer-only visibility, Wrap,
RTL mirroring, focus-without-selection arrow navigation, and Selection accessibility remain part
of the same bound control lifecycle.

Changing PipsPager's Reduce Motion policy updates its existing pip and navigation buttons
immediately, without waiting for layout or changing selection.

CalendarView is an embedded Fluent calendar; CalendarDatePicker shares its grid inside an AppKit
popover. It supports single/multiple/no selection, blackout dates, inclusive date ranges, and
continuous, virtualized Month/Year/Decade scrolling (4×4 in Year/Decade). Arrow keys move focus; Space/Enter activates;
Home/End target the visible scope; PageUp/PageDown retain the day where valid; Ctrl+Up/Down change levels.

```swift
@FluentState private var selectedDays: [Date] = []

// In a Fluent body:
FluentCalendarView(selection: $selectedDays, selectionMode: .multiple)
    .frame(width: 310, height: 350)
```

Pass `calendar` to configure locale and time zone, and `firstWeekday` to override the week start.
Pass `numberOfWeeksInView: 2` (2–8) to set the month viewport (default 6; values are clamped).
An omitted minimum defaults to January 1 of the current Gregorian year minus 100; an omitted
maximum defaults to December 31 of the current year plus 100, in the configured time zone.
Specify both bounds for a range outside those defaults.
Dates are compared by local calendar day. Activating a selected day removes it; in multiple mode,
all equivalent duplicate entries are removed. Range/blackout/mode changes normalize the bound
selection. CalendarDatePicker retains its nonoptional-date API and commits an already selected day.
`displayDate`, `displayMode`, and unbound `selectedDates` apply initially and when their values
change; unchanged parent values preserve browsing and scroll position. Scroll headers follow the
visible scope; switching levels retains the browsed location and preserves smaller date fields
where valid. Month/year items split at era boundaries: Heisei 31 and Reiwa 1 are separate items
in 2019. Decade scopes stay inside one era, with years 1–9 forming its first decade. Partial
months/years participate in paging, keyboard focus and date clamping without building a full
date array. The Calendar Gallery includes a Japanese-era example.
Coverage remains partial: optional snap points and scope-label/motion parity, broader calendar
comparison on Windows, item templates/density indicators, Windows screenshot comparison,
and real VoiceOver acceptance are pending.

FlipView lazily mounts the current page and its neighbors (at most three idle pages, with one
additional outgoing page during a distant animated jump). The default initializer identifies pages
by position; pass `id: \.id` or `id: \.self` to retain mounted content and the selected item across
insertions/reordering. IDs should be unique. Explicit IDs require an O(n) identity scan when the
parent updates, but only cached page content is evaluated. Keep durable state in your model:
pages outside the cache are unmounted.

Pass `orientation: .vertical` for Up/Down navigation and top/bottom buttons; horizontal pages use
Left/Right with RTL mirroring. Both support Home/End and single-page trackpad/direct-touch settling.
Traditional wheel bursts advance once until a 200 ms pause or direction reversal; Control+wheel,
cross-axis trackpad gestures and eligible traditional wheel events at a boundary chain to the parent.
A new outward phased gesture at a settled first/last page also chains, preserving the original
begin event, small initial deltas and momentum. Inward gestures stay owned by the pager.
Navigation buttons are 16×38 horizontally and 38×16 vertically, with a 1pt margin and three-second
idle hiding. Selection is clamped, or `-1` when empty; rejected or redirected binding setters are
respected. Disabled lazy pages inherit and restore their own enabled state.

The Gallery demonstrates 1,000 pages, orientation changes and stable-ID insertion/removal. Coverage
remains partial: exact DirectManipulation physics and residual scroll transfer after an already
owned gesture reaches an edge, complete item-container
semantics, button glyph/material fidelity, Windows screenshots, physical touch and real VoiceOver
acceptance remain open. Gesture settling is a local macOS adaptation of single-page snapping.

BreadcrumbBar preserves WinUI's suffix-overflow layout: the current final item always remains
visible, earlier items collapse behind an ellipsis only when required, and the flyout lists the
hidden prefix from nearest to farthest. `ItemClicked` reports the original zero-based source index;
the same controls provide Left/Right focus traversal, RTL mirroring, current-location semantics,
keyboard invocation, and an accessibility-only view of the visible path.

Popup density follows the input that opened it. Mouse, trackpad and keyboard use desktop rows:
ComboBox row pitch 36pt and MenuFlyout row pitch 36pt (32pt painted row plus margins). Direct touch
uses 48pt ComboBox rows with a 240pt minimum popup width, and 44pt MenuFlyout row pitch. Trackpad
mouse events can have AppKit's `.touch` subtype; that alone does not select touch density. Input
records are window-local, and direct gesture recognizers report their modality explicitly.

Combo-box fields keep a native `NSComboBox` option/accessibility bridge while FluentKit owns the
visible 32pt host, trailing glyph column, focus visuals, popup, and item template. Selection mode
centers the current item over the closed faceplate and reveals the popup around that row. Editable
mode uses a native `NSTextField` for editing and IME behavior; only its glyph column opens the popup
below the field (or above when space requires it). Arbitrary text updates the optional text binding,
and exact option titles synchronize the stable selection. Both modes provide keyboard navigation,
type-ahead, Escape/outside-click dismissal, RTL placement, and the source-derived partial-content
entrance rather than the native AppKit combo-box popup.

Progress bars use stable Fluent-owned track and indicator layers. Determinate values interpolate with
the 250ms control-normal token; indeterminate mode uses a coordinated dual-layer loop, while paused
and error states settle without losing the native accessibility role. RTL and Reduce Motion are
inherited from the render environment.

Segmented controls use a custom Fluent renderer while preserving `NSSegmentedControl` identity.
One shared selection surface moves between segments with the source-derived 167ms control-fast
curve; labels, hover/pressed states, focus outlines, release-inside selection, and keyboard
navigation are rendered and synchronized by FluentKit rather than by the native segmented cell.
Compatible declarative updates preserve label and indicator identity, same-bounds layout preserves
active presentation motion, and RTL plus Reduce Motion are inherited from the render environment.

Applications can implement `FluentButtonStyle`, `FluentToggleStyle`, `FluentSliderStyle`,
`FluentProgressStyle`, `FluentCheckBoxStyle`, `FluentRadioButtonStyle`, or
`FluentSegmentedStyle` to resolve native appearance metrics from the current control state and
inherited theme. `FluentTextFieldStyle` is shared by single-line, secure, search, combo-box, and
date-picker inputs, so focus chrome, semantic fonts, density, and contrast remain consistent.
`FluentStepperStyle` controls the label, value field, spacing, and nested text-field style. Containers
use the corresponding `FluentCardStyle` contract:

```swift
FluentVStack(spacing: 6) {
    FluentText("Workspace", weight: .semibold)
    FluentText("Three pending changes")
}
.cardStyle(FluentElevatedCardStyle())
```

`FluentCardView` preserves both its native card host and declarative content during compatible
updates; changing style or theme updates only the container surface and inset constraints.

## Commands

Attach keyboard commands to a view subtree with native AppKit key equivalents. Commands are evaluated during rendering, so actions can safely capture `FluentState` and enabled predicates can reflect current application state.

```swift
content.fluentCommands {
    FluentCommand("Focus search", keyEquivalent: "f") { searchFocused = true }
}
```

Native window toolbars host ordinary Fluent views, so toolbar controls use the same state and binding system as window content.

```swift
content.toolbar {
    FluentToolbarItem("save", label: "Save") {
        FluentButtonView("Save", action: save)
    }
    FluentToolbarItem.flexibleSpace
}
```

`FluentTabView` remains a lightweight in-window control. Set `canDragTabs` and a shared
`dragScopeIdentifier` when separate tab views should exchange stable-ID items. For a complete
browser-style workspace, `FluentWindowTabCoordinator` combines the Windows Fluent tab strip with
native macOS windows: dragging within a strip reorders, dropping on another coordinated strip
merges, and dropping elsewhere tears the tab into a new window. It disables AppKit's unrelated
native title-bar tab system and keeps the same `FluentWindowTab` content value across moves.
Within the strip's `tearOutDistance` buffer, the tab follows the pointer and neighboring tabs open
a live insertion gap; after the pointer crosses that boundary, the drag switches to a scaled window
preview for tear-out or cross-window merging.

```swift
let tabs = FluentWindowTabCoordinator(
    configuration: FluentWindowTabConfiguration(windowControlsStyle: .windows),
    onAddTabRequested: { groupID in makeDocumentTab() }
)
let groupID = tabs.open(
    FluentWindowTab(id: document.id, title: document.title, systemImage: "doc.text") {
        DocumentEditor(document)
    }
)
_ = tabs.open(makeDocumentTab(), in: groupID)
```

The coordinator also exposes `move(tabID:to:at:)`, `detach(tabID:at:)`, close vetoes, group/window
lookup, and a content-wrapper hook for applications that need an additional shell around each tab
window. Keep the coordinator alive for as long as any of its windows are open.

Value-driven navigation uses a binding to route identities and a destination closure: the native host keeps the window and responder chain alive while replacing only the route content.

```swift
FluentNavigationStack(
    path: $path,
    root: { HomeView() },
    destination: { route in FluentAnyView(DetailView(route: route)) }
)
```

For desktop workspaces, `FluentNavigationSplitView` keeps a native `NSSplitView` mounted while a
stable selection drives the detail column. The sidebar is keyboard navigable, user resizable, and
optionally collapsible through a binding; deleting the selected item clears stale selection and
shows the placeholder:

```swift
FluentNavigationSplitView(
    destinations,
    id: \.id,
    selection: $selectedDestination,
    isSidebarVisible: $isSidebarVisible,
    sidebarWidth: 180...360,
    idealSidebarWidth: 240
) { destination in
    FluentText(destination.title)
} detail: { destination in
    DestinationView(destination)
} placeholder: {
    FluentText("Select a destination")
}
```

`FluentNavigationView` provides a reusable application shell with stable primary/footer destinations,
an optional pane header and content header, and adaptive Left, Compact, Minimal, and Top layouts. Its
default thresholds are 641pt for Minimal/Compact and 1008pt for Compact/Expanded. Top navigation
keeps a stable leading prefix and moves the remaining destinations into an application-owned
`FluentMenuFlyout`; a hidden selection is represented by the `More` button and shared indicator.

```swift
let destinations = [
    FluentNavigationItem(id: Page.home, title: "Home", systemImageName: "house"),
    FluentNavigationItem(id: Page.library, title: "Library", systemImageName: "books.vertical")
]

FluentNavigationView(
    destinations,
    footerItems: [FluentNavigationItem(
        id: Page.settings,
        title: "Settings",
        systemImageName: "gearshape"
    )],
    selection: $selection,
    isPaneOpen: $isPaneOpen,
    paneDisplayMode: .automatic,
    contentTransition: .automatic,
    selectionIndicatorMode: .adaptive
) {
    FluentText("FluentKit")
} header: {
    PageHeader(selection)
} content: {
    PageContent(selection)
}
```

Pane opening uses separate 350ms/120ms open and close curves. Selection-indicator motion can use
the WinUI-style two-rail masked jump (`.jump`), a connected nearby transition (`.continuous`), or
the default `.adaptive`, which stays continuous between nearby destinations and switches to the
two-rail jump between distant destinations. All three support vertical and horizontal layouts and snap under Reduce
Motion. Arrow keys, Home/End, disabled destinations, accessibility selection, RTL ordering, overlay
dismissal, and Top overflow all use the same stable selection model.

`FluentNavigationView` also owns its page transition presenter. `.automatic` follows the WinUI
recommendation by using a direction-aware Slide transition for ordered Top destinations and an
Entrance transition elsewhere. `.crossFade`, `.slide`, `.drillIn`, `.entrance`, `.none`, and
`.suppress` are available as explicit policies. The presenter keeps outgoing and incoming pages
only for the required phase, resumes interruptions from presentation values, settles rapid changes
on the newest destination, and replaces immediately under Reduce Motion.

`FluentTitleBar` provides reusable custom window chrome while keeping the native main menu.
Back/forward buttons retain a 40pt-wide hit target while their arrow compresses on press and
rebounds on release; reduced motion applies the endpoint immediately. Dragging outside cancels
activation, and moving back inside re-arms it. Space activates on release, Return on the first
key-down. Hidden/disabled controls cannot navigate. The application supplies navigation/history
through `onBack` and `onForward`.

`windowControlsStyle` independently chooses native macOS traffic lights on the left or Windows-style
Minimize/Maximize/Close controls on the right; both styles route commands through `NSWindow`, and
switching back to `.macOS` restores the prior native buttons. Compact and expanded modes use 32pt
and 48pt geometry; the title bar can own a
shared pane binding, back action, icon, title/subtitle, and left/center/right declarative slots. It
synchronizes the native window title, preserves drag and double-click behavior, mirrors content in
RTL, and restores the prior AppKit chrome configuration when detached.

```swift
FluentVStack(spacing: 0, alignment: .width) {
    FluentTitleBar(
        title: "Workspace",
        heightMode: .expanded,
        windowControlsStyle: .windows,
        isPaneToggleButtonVisible: true,
        isPaneOpen: $isPaneOpen
    )
    FluentNavigationView(
        destinations,
        selection: $selection,
        isPaneOpen: $isPaneOpen,
        paneDisplayMode: .automatic,
        isPaneToggleButtonVisible: false
    ) {
        PageContent(selection)
    }
}
```

`FluentWindowShell` composes the same pieces into independent window states. Native AppKit chrome and
extended Fluent chrome are explicit; extended chrome can include a centered search view or omit it,
place the shared pane toggle in the title bar or the vertical NavigationView, and choose Left,
Compact, Minimal, or Top navigation. It also owns the shared pane binding, optional Back action,
Liquid Glass/Mica/Solid backdrop, and clipped ContentSurface. When native chrome is selected, a
requested Fluent search is suppressed and a title-bar toggle is normalized to the vertical pane so
the action is never silently lost.

```swift
FluentWindowShell(
    configuration: FluentWindowConfiguration(
        layout: .settings,
        paneTogglePlacement: .titleBar,
        searchPlacement: .titleBar,
        backdrop: .liquidGlass,
        selectionIndicatorMode: .adaptive
    ),
    title: "Workspace",
    isBackButtonVisible: true,
    onBack: { navigation.popLast() },
    items: destinations,
    selection: $selection,
    isPaneOpen: $isPaneOpen,
    titleBarContent: {
        FluentSearchField($query, placeholder: "Search")
            .frame(width: 360, height: 32)
    },
    paneHeader: { FluentText("Explore", style: .headline) },
    header: { PageHeader(selection) },
    content: { PageContent(selection) }
)
```

For route-specific metadata, return a `FluentNavigationDestination` so the title and content are resolved together. Route changes can use `.none`, `.crossFade`, or `.slide` transitions:

```swift
FluentNavigationStack(path: $path, root: { HomeView() }, transition: .slide) { route in
    FluentNavigationDestination(title: "Item \(route)") {
        DetailView(route: route)
    }
}
```

A `FluentNavigationDestinationRegistry` keeps route handlers isolated by their concrete Swift type. Unknown persisted routes render an explicit unavailable destination instead of crashing:

```swift
enum WorkspaceRoute: Hashable, Codable { case article(Int); case settings }
let registry = FluentNavigationDestinationRegistry()
registry.register(WorkspaceRoute.self) { route in
    FluentNavigationDestination(title: String(describing: route)) {
        FluentText("Destination for \(route)")
    }
}
var path = FluentNavigationPath<WorkspaceRoute>()
path.append(.settings)
let restored = FluentRestoredState(wrappedValue: path, "navigation.path")
FluentNavigationStack(path: restored.projectedValue, root: { HomeView() }, registry: registry)
```

`FluentNavigationPath<Route>` is homogeneous, `Hashable`, and `Codable`; it exposes `append`, `popLast`, `removeAll`, `last`, and `elements` for type-safe navigation restoration.

Trailing inspectors use the same native split-host strategy. The pane can be resized within a
closed range, collapsed through a binding, and updated without replacing the surrounding content
host:

```swift
FluentInspector(isPresented: $showInspector, width: 240...420, idealWidth: 300) {
    EditorView(document: document)
} inspector: {
    PropertiesView(selection: selection)
}
```

The inspector pane uses macOS sidebar material and exposes semantic accessibility labels for the
content and properties columns.

When a conditional branch changes its native shape, `transition(_:)` keeps the parent hierarchy stable and animates the replacement:

```swift
(isExpanded ? FluentAnyView(ExpandedView()) : FluentAnyView(CompactView()))
    .transition(.crossFade)
```

Transitions can move or scale content, compose multiple effects, and give insertion and removal
independent choreography. The transition host animates an internal entry wrapper, so a content
view's own `transformEffect` remains intact:

```swift
let panelTransition = FluentTransition.asymmetric(
    insertion: FluentTransition.move(edge: .trailing).combined(with: .crossFade),
    removal: FluentTransition.scale.combined(with: .crossFade)
)

panel.transition(
    panelTransition,
    animation: FluentAnimationTransaction(duration: 0.28, curve: .easeOut)
)
```

Compatible declarative updates retain the entry and native content identity. Incompatible branch
changes briefly retain incoming and outgoing entries, then deterministically remove the outgoing
entry on the main run loop even when no window is attached.

For matched geometry, keep a namespace in the view's declarative state and mark corresponding
content with the same identifier. During an incompatible branch replacement FluentKit computes
the old and new native frames and animates the incoming marker's position and size:

```swift
struct CardSwitcher: FluentView {
    @FluentNamespace private var namespace
    @FluentState private var expanded = false

    var body: some FluentView {
        let card = expanded
            ? FluentAnyView(ExpandedCard().matchedGeometryEffect(id: "card", in: namespace, configuration: .gravity))
            : FluentAnyView(CompactCard().matchedGeometryEffect(id: "card", in: namespace, configuration: .gravity))

        return card
            .transition(.crossFade)
            .fluentReduceMotion(false)
    }
}
```

Matched geometry is scoped to the transition host and does not require a global registry. Reduced
motion and zero-duration transitions replace the branch immediately, while content-level affine
transforms remain isolated from the geometry wrapper. Its configuration can select the default
300ms connected motion, a direct 200ms path, or a gravity path with a lifted scale/shadow peak.

For visual choreography, use the scene-specific values in `FluentMotion` rather than a single
global ease. The public tokens include 83ms/167ms/250ms control transitions, 200ms/300ms connected
motion, a 600ms navigation indicator, and separate 300ms open and 200ms close presentation curves:

```swift
let hover = FluentMotion.controlFaster
let connected = FluentMotion.connectedDefault

panel.transition(.crossFade, animation: connected.transaction)
```

Execution is coordinated per control or presenter, not through one process-wide animation queue.
`FluentAnimationCoordinator` separates visual-state selection from structural transitions, while
its layer backend samples presentation values, performs keyed replacement, commits model values,
suppresses stale completions, and applies Reduce Motion consistently.

Single-selection `FluentList` instances use one shared active selection indicator. During movement
between stable row identities, that layer follows the source-to-midpoint-to-destination path while
its bounds stretch and settle on the target geometry. The Gallery navigation shell uses this same
renderer and its directional 600ms choreography, so application navigation does not need a private
indicator implementation.

Animation duration and timing function can be supplied through the render environment. The same transaction is used by branch transitions, navigation route changes, and disclosure expansion:

```swift
content
    .fluentAnimationDuration(0.24)
    .fluentAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
```

Use the public curve names for common timing choices, and opt a subtree into immediate final-state
updates when the user or product setting requests reduced motion:

```swift
let motion = FluentAnimationTransaction(duration: 0.22, curve: .easeOut)
content
    .transition(.crossFade, animation: motion)
    .fluentReduceMotion(reduceMotionEnabled)
```

fluentReduceMotion is inherited by nested content and keeps the configured final-state
values while skipping transition interpolation.

For value-driven motion, `FluentAnimatedValue` publishes display-clock samples through the same
dependency tracker used by state and bindings. `@FluentAnimatedState` provides declarative storage,
while its backing animated value supports timing curves, physical springs, keyframes, cancellation,
and deterministic finishing:

```swift
struct MotionExample: FluentView {
    @FluentAnimatedState(animation: nil) private var progress: CGFloat = 0

    var body: some FluentView {
        FluentVStack(spacing: 10) {
            FluentText("Progress \(Int(progress * 100))%")
                .opacity(0.25 + progress * 0.75)
                .scaleEffect(0.85 + progress * 0.15)
                .offset(x: progress * 32)

            FluentButtonView("Spring") {
                _progress.animatedValue.set(
                    progress < 0.5 ? 1 : 0,
                    spring: FluentSpringAnimation(stiffness: 190, damping: 18)
                )
            }
        }
    }
}
```

Keyframes contain absolute values at normalized offsets. If the same offset is declared more than
once, the later declaration wins, making generated and conditionally assembled timelines
predictable:

```swift
let pulse = FluentKeyframeAnimation<CGFloat>(
    keyframes: [
        FluentKeyframe(offset: 0, value: 0),
        FluentKeyframe(offset: 0.55, value: 1),
        FluentKeyframe(offset: 1, value: 0.35)
    ],
    duration: 0.7,
    curve: .easeInOut
)

_progress.animatedValue.animate(using: pulse, reduceMotion: reduceMotionEnabled)
```

Built-in interpolation covers scalar values, points, sizes, rectangles, edge insets, affine
transforms, and colors. Numeric and geometric values extrapolate so underdamped springs can
overshoot; colors remain clamped in extended sRGB. `transformEffect`, `offset`, `scaleEffect`, and
`rotationEffect` are visual transforms and do not change the view's layout footprint.

FluentButton participates in Tab navigation even when the system’s native-button keyboard navigation setting is off. Disabled, hidden, fully clipped or unattached buttons remain excluded; native applications can opt out using `refusesFirstResponder`.

Focus behavior is also declarative. `fluentInitialFocus()` requests the first enabled focusable descendant once a view enters a window, while preserving an existing responder. `fluentFocusScope()` gives controls inside the subtree a deterministic Tab loop; nested scopes keep their own loops. Use `focused(_:)` when application state needs to follow or drive the native responder:

Scopes and ContentDialog retain Tab/Shift-Tab cycles when AppKit rebuilds its window key-view
loop. Stack traversal follows the current arranged order. Text command delegates and editing
validation can consume navigation, and marked-text sessions retain their native input handling.
Explicit programmatic focus requests, including `NSWindow.selectNextKeyView`, remain AppKit
operations; the keyboard cycle does not intercept them.

```swift
FluentVStack(spacing: 10) {
    FluentBoundTextField($search, placeholder: "Search")
    FluentButton(title: "Apply")
}
.fluentFocusScope()
.fluentInitialFocus()

FluentTextField(placeholder: "Search")
    .focused($searchFocused)
```

Codable workspace and document state can be restored with the same binding and dependency-tracking behavior as `FluentState`. Values are isolated by store namespace, synchronized between wrappers that share a key, and can be reset to their declared defaults:

```swift
struct EditorWorkspace: FluentView {
    @FluentRestoredState("editor.notes") private var notes = ""
    @FluentRestoredState("editor.selection") private var selectedDocumentID: String? = nil

    var body: some FluentView {
        FluentTextEditor($notes, placeholder: "Notes")
    }
}

let documentStore = FluentRestorationStore(namespace: "com.example.editor.document-42")
let zoom = FluentRestoredState(wrappedValue: 1.0, "zoom", store: documentStore)
zoom.reset()
```

Model edits can participate in native Undo/Redo without changing control APIs. An undo scope shares one `UndoManager` across a subtree, while an undoable binding registers inverse mutations and publishes command availability:

```swift
let undo = FluentUndoCoordinator()
let editableTitle = $title.undoable(using: undo, actionName: "Rename")

FluentVStack {
    FluentBoundTextField(editableTitle, placeholder: "Title")
    FluentButtonView("Undo", action: undo.undo)
}
.fluentUndoScope(undo)
```

`FluentDocumentSession` builds document lifecycle semantics on the same mechanism. It tracks the saved revision, derives dirty state across undo and redo, writes atomically, supports Save As and revert, schedules optional delayed autosave, and provides a restoration namespace for document UI state:

```swift
struct Draft: Codable, Equatable {
    var title = "Untitled"
    var body = ""
}

let session = FluentDocumentSession(
    id: "draft-42",
    document: Draft(),
    fileURL: documentURL,
    autosave: .delayed(1.5)
)

session.mutate(actionName: "Edit body") { $0.body = "Updated text" }
try session.save()
try session.revert()
```

Import loads a clean untitled revision, so the next Save requires a destination. Export writes a
copy while preserving the session's file URL, saved revision, dirty state, and undo history:

```swift
try session.importDocument(from: importedURL)
try session.exportDocument(to: exportedCopyURL)
```

`FluentDocumentCoordinator` coordinates several sessions without taking ownership of their encoding
or undo policy. It exposes an observable active document ID, routes file opens, protects dirty close,
and supports batch save/close:

```swift
let documents = FluentDocumentCoordinator(sessions: [session, anotherSession])
documents.activate(id: "draft-42")
try documents.open(id: "draft-42", from: documentURL)
try documents.saveAll()
guard documents.close(id: "draft-42") else {
    // Present a discard confirmation before calling close(..., discardChanges: true).
    return
}
```

Version restoration state before changing its encoded schema. `FluentStateMigrator` applies a
strictly forward sequence in memory and commits the namespace once; an error leaves both values and
the schema version unchanged:

```swift
let migrator = FluentStateMigrator(targetVersion: 2, steps: [
    FluentStateMigrationStep(from: 0, to: 1) { context in
        context.renameValue(fromKey: "displayName", toKey: "profileName")
    },
    FluentStateMigrationStep(from: 1, to: 2) { context in
        try context.set([String](), forKey: "recentFiles")
    }
])

try migrator.migrate(workspaceStore)
```

Printing and sharing retain native AppKit presentation while allowing injected presenters in tests or
embedded hosts:

```swift
let printSession = FluentNativePrintPresenter.shared.presentPrint(
    view: printableView,
    in: window,
    configuration: .init(jobTitle: "Workspace")
) { result in
    handlePrintResult(result)
}

let shareSession = FluentNativeSharingPresenter.shared.presentSharing(
    items: ["Workspace", exportedCopyURL],
    from: shareButton
)
```

## Overlays

Use `.toolTip("Help")` for the default delayed ToolTip. Adjacent targets can opt into
`.toolTip("Help", placement: .bottom, motion: .continuous)` to share a moving, resizing
surface with a content transition. This is a FluentKit extension, independently implemented
from a visual reference, and is enabled for the Windows-style caption buttons. The first
target retains its hover delay; subsequent targets in the same window transition immediately.
Placement stays at the activation point while moving inside one target. Keyboard activation
keeps the default delay, and reduced motion switches directly to the final state.

Overlays use native macOS presentation hosts while keeping their content declarative. Use `FluentPopoverButton` for transient content, `FluentSheet` (or the `sheet(isPresented:title:size:)` modifier) for custom modal content, and `confirmationDialog` or `FluentAlert` for native confirmation sheets. A window-owned presentation coordinator serializes custom sheets, native alerts, and file panels because AppKit permits only one attached document-modal sheet at a time. Request tokens isolate stale native completion callbacks, preserve rapid close/reopen state, and restore the parent responder after dismissal. Sheets keep their native window while updating content, title, requested size, theme, and the global material-effects switch in place.

For a binding-driven transient surface, attach `popover(isPresented:placement:size:behavior:)` to the anchor view. The anchor remains mounted, `automatic` placement chooses a fitting edge using the current screen and layout direction, same-size content updates preserve the native popover content identity, and a size change replaces the AppKit presenter without changing the binding state:

```swift
FluentButtonView("Details") { showingDetails = true }
    .popover(isPresented: $showingDetails, placement: .bottom, size: NSSize(width: 280, height: 180)) {
        FluentText("Details", style: .headline)
    }
```

`teachingTip` presents a target-relative WinUI TeachingTip in an application-owned child panel. The
default non-light-dismiss presenter uses a solid tertiary surface, does not steal focus, and remains
open when the user clicks outside. Opting into `isLightDismissEnabled` switches to a transient
material, modal accessibility semantics, and outside-click dismissal. Title, subtitle, icon, Hero
content, action/close buttons, tail visibility, all thirteen WinUI placements, RTL mirroring, root
boundary fallback, cancellable `onClosing`, and close reasons are binding-driven while the anchor
keeps its native identity:

```swift
FluentButtonView("Help")
    .teachingTip(
        isPresented: $showHelp,
        title: "Keyboard navigation",
        subtitle: "Move through the current group without leaving the keyboard.",
        systemImageName: "keyboard",
        placement: .top,
        size: NSSize(width: 320, height: 150),
        actionButtonTitle: "Show shortcuts",
        closeButtonTitle: "Got it"
    ) {
        FluentText("Use arrow keys to move between items.", style: .body)
}
```

Attach `toolTip` for short, non-interactive help. Pointer-triggered directional placements are
anchored to the current pointer, keyboard-triggered placements use the target bounds, and only one
automatic ToolTip is active application-wide. The presenter follows WinUI's pointer delay,
owner-to-popup safe zone, 320pt width limit, fixed 4pt corner, 1px flyout stroke, RTL placement, and
five-second fallback duration while preserving the anchor's native identity and accessibility help:

```swift
FluentButtonView("Save")
    .toolTip("Save changes", placement: .top)
```

The macOS application menu deliberately remains an `NSMenu`. In-application button flyouts,
DropDownButtons, and `contextMenu` use the custom `FluentMenuFlyout` panel. Its transient surface uses
the global material setting with one opaque fallback edge owner. Item spacing, state fills,
checkmarks, system-icon placeholders, separators, accelerators, keyboard navigation, and dismissal
remain controlled by FluentKit rather than the system menu renderer. Menu items can declare icons,
shortcuts, and nested flyouts without leaving the Swift API:

```swift
FluentButtonView("Options")
    .flyout {
        FluentMenuItem(
            "Focus search",
            systemImageName: "magnifyingglass",
            keyEquivalent: "f"
        ) { focusSearch() }
        FluentMenuItem.separator
        FluentMenuItem.submenu("Account actions", systemImageName: "person.crop.circle") {
            FluentMenuItem("Rename", systemImageName: "pencil") { renameAccount() }
            FluentMenuItem("Manage access", systemImageName: "person.2") { manageAccess() }
        }
    }

FluentDropDownButton(title: "More", items: [
    FluentMenuItem("Settings") { openSettings() }
])
```

Use `FluentCommandBarFlyout` when commands need WinUI's compact primary icon bar and expandable
secondary overflow rather than MenuFlyout rows. It supports action, toggle, and separator elements,
`AlwaysExpanded`, direct `present(relativeTo:at:)`, and a declarative Button attachment:

```swift
FluentButtonView("Formatting")
    .commandBarFlyout {
        FluentCommandBarItem("Copy", systemImageName: "doc.on.doc") { copy() }
        FluentCommandBarItem.separator
        FluentCommandBarItem.toggle("Bold", systemImageName: "bold", isOn: isBold) {
            isBold = $0
        }
    } secondaryCommands: {
        FluentCommandBarItem("Archive", systemImageName: "archivebox") { archive() }
        FluentCommandBarItem.separator
        FluentCommandBarItem("Share", systemImageName: "square.and.arrow.up") { share() }
    }
```

CommandBarFlyout and TextCommandBarFlyout share the source 40pt primary geometry and 250ms More
clip, but TextBox-family controls keep their private, editor-derived secondary-only mouse command
composition. Neither path is implemented as a MenuFlyout, and all three presenters dismiss
immediately without an exit animation.

Submenus open after a short pointer hover delay or immediately from keyboard/accessibility input.
Arrow keys move between levels, printable keys perform type-ahead matching, and the presenter mirrors
its chevrons, checkmarks, accelerator columns, and anchor placement for right-to-left layouts.

## Contributing and security

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
Release maintainers should follow [RELEASING.md](RELEASING.md). Report potential vulnerabilities
according to [SECURITY.md](SECURITY.md) rather than disclosing them in a public issue.

## License

FluentKit is released under the MIT License. See [LICENSE](LICENSE).


## Audit-driven rendering and input contracts

The contracts below are covered by maintained tests and [quality checks](tools/quality/README.md).
[ROADMAP.md](ROADMAP.md) records the remaining acceptance work. Raw audit reports, screenshots
and logs stay outside version control. Passing tests is not evidence of complete visual parity
with Windows.

- Use `host.update(content, context: context)` to commit a new tree and environment in one pass.
  `FluentNativeView(existingView)` retains that instance; for creation plus configuration use
  `FluentNativeView(make:update:)`. The factory runs once per mount, and the update receives the retained native view.
- External text values replace active unmarked text and survive blur. An external value received
  during IME composition is deferred until composition finishes, then wins. Native undo/redo
  publishes the editor's resulting value. To defer search or validation until IME commit, use
  `$query.textInput(.init(commitPolicy: .committedText, onEditingChange: { change in /* text, isComposing */ }))`.
  The compatibility default remains `.continuous`. Closure-only bindings are checked when updated or committed;
  use an observable binding for immediate external delivery.
- Collections apply native snapshots only for structural changes. Without a content version, only
  visible rows update conservatively. Opt in with `.contentVersion { id in model[id].revision }`
  on `FluentCollection`, `FluentListView` or `FluentGridView` to skip unchanged row content.
  Include every captured content dependency in that version. Theme and environment changes still
  refresh visible content; offscreen rows use the latest provider when mounted. Building a new ID
  array and comparing structure still costs O(n); this API does not promise constant-time arbitrary data updates.
- `FluentObservable` and `FluentState` deduplicate concrete Equatable values. Custom values can
  supply `areEquivalent:`; `.observableValue.send()` explicitly publishes an unchanged state.
- ComboBox preserves its chevron press animation through drawing, layout, content, theme
  and backing changes in both modes, using the resolved Reduce Motion policy. Hidden or
  detached controls, disabling, focus loss, window closure and mode/option replacement cancel
  captured pointer input and queued opens. Editable glyph releases must remain in bounds;
  native text editing and field-editor focus ownership remain in place. Ordinary pointer
  states keep the secondary glyph foreground, as specified by the ComboBox resource template.
  An already open popup retains its panel during same-turn reattachment in the original window;
  its anchor observer still closes it on lasting detachment or a move to another window.
- DropDownButton preserves chevron press motion through layout, content, theme and backing
  updates, following the resolved Reduce Motion policy. Space and Return activate on release;
  repeated key-down events do not invoke it. Hiding, detachment, disabling, window closure
  and focus loss cancel pending activation. Open menus retain rows and selection while using
  updated content and actions. Hover/press chevron colors follow the WinUI resource roles.
- Navigation group chevrons use WinUI's down-collapsed/up-expanded directions in side and top
  layouts. RTL mirrors their placement. Rotation survives layout, content, theme and hover
  updates; mode changes, hiding/detachment, disabling and Reduce Motion settle it. Backing-scale
  changes update geometry without restarting motion. Top items reserve the chevron's width and
  text gap before applying the existing width cap and overflow policy. This preserves native navigation
  behavior; full WinUI hierarchical flyouts and AnimatedIcon frame parity remain follow-up work.
- SettingsExpander and Expander preserve chevron transitions through layout, content and hover
  refreshes. Initial display is static; detachment, disabling and Reduce Motion settle rotation
  without replaying it on reattachment or re-enabling. The chevron follows the resolved render
  context's motion policy, including explicit overrides. Chevron motion uses FluentKit's shared
  primitive; it does not reproduce every frame of WinUI's AnimatedIcon asset.
- TreeView reconciles native nodes by stable ID and updates visible content in place when the
  topology is unchanged. Structural updates still reload the outline; reconciliation still walks
  the supplied nodes. Reordering preserves selection by ID. The interactive Gallery sample covers
  tri-state selection, lazy loading and expansion. `onMoveItems` reports an atomic move of the
  checked subtrees: remove every `move.ids` root first, then insert them in order under
  `move.parentID` starting at `move.index`. Descendants move with their selected ancestor.
  Selection order is preserved; initial unordered Set selections use tree order. With no checks,
  it moves the dragged row. Existing `onMove` remains a single-row callback; the last move-handler
  modifier wins. Disclosure rotation survives layout, theme and content refreshes; reused cells,
  detachment and Reduce Motion settle it at the current node's direction. Native drag/drop
  acceptance, cross-tree transfer and container entrance/content/reorder transitions remain pending.
  WinUI's default TreeView transitions distinguish initial entrance from inserted rows; they do
  not specify an Expander-style height animation for every expansion.
- TreeView disclosure availability queries do not call `onExpanding`. Actual changes to
  `expandedIDs` after mounting emit `onExpanding` / `onCollapsed`; initial state and restoration
  after reloading children do not repeat them. `onCollapsed` observes the updated binding, so a
  callback can request reopening.
- Typography uses Caption 12, Body 14, BodyLarge 18, Subtitle 20, Title 28, TitleLarge 40 and Display 68.
  Legacy aliases map `largeTitle` to `titleLarge`, `title2` to `subtitle`, `headline` to `bodyStrong`
  and `callout` to `body`. `FluentTypography(overrides:fontProvider:)` supports per-style size, weight,
  optional line height and application-supplied fonts. The default font remains the macOS system font;
  FluentKit does not bundle Segoe fonts or claim matching glyph metrics.
- `FluentIconSource` supports symbols, glyphs, NSImage and CGPath. Menu items, navigation items,
  title bars, AppBar buttons and CommandBar items accept `icon:`. Sources preserve aspect ratio,
  expose alignment and RTL mirroring, and distinguish template tint from original image colors.
  Existing `systemImageName:` and button `image:` APIs remain available.
- `.mica` samples cached desktop wallpaper; `.acrylic` uses live AppKit blur with WinUI
  luminosity, tint and noise stages. Default transient surfaces use Acrylic. Explicit native
  materials and Liquid Glass remain available. Disabled effects and accessibility policies
  select opaque fallbacks. Windows pixel parity, animated wallpapers and physical mixed-DPI
  multi-monitor behavior still require separate acceptance.
- AppBar horizontal labels reserve a separate chevron slot in LTR and RTL. `commandHeight: 32`
  on `FluentAppBarButtonView` (or `commandHeight` on the native button) opts into a denser application
  command; the default WinUI AppBar height remains 48. Hover and expanded backgrounds follow that geometry.
- Framework defaults are resolved from the host's locale, first through the application's
  `FluentKit.strings`, then the bundled English, Simplified Chinese and Traditional Chinese resources.
  Keys use `FluentKit.Copy`, `FluentKit.Back`, etc. Applications can override the locale/bundle
  through the render context or `view.fluentSetLocalization(locale:bundle:)` for native subtrees.

Run `swift test` for behavior and work-count regressions, and
`./tools/run-quality-checks.sh` for Release raw data, registered Gallery sample mounting and
controlled screenshots. `tools/compare_snapshots.py` compares reviewed image pairs without
rewriting their baselines; capture OS, scale and fonts must match.
CI also checks XCTest output with `tools/check_test_diagnostics.py` so AppKit constraint conflicts
fail the build even when the test assertions pass.

## Acknowledgements

Thanks to [HO-COOH/WinUIEssentials](https://github.com/HO-COOH/WinUIEssentials) for the material
implementation reference: TenMica's cached, heavily blurred wallpaper and luminosity/tint
composition, and InAppAcrylicVisual's blend stages and theme values. FluentKit adapts these
ideas to AppKit and Core Image; it does not depend on the Windows library or claim identical
rendering. Copyright (c) 2023 HO-COOH; [MIT license](LICENSES/WinUIEssentials.txt).
