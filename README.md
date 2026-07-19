# FluentKit

A declarative desktop UI framework inspired by Fluent Design, implemented in native Swift and AppKit.

FluentKit provides a composable foundation for desktop interfaces: Fluent theme tokens, adaptive light and dark appearance, native macOS materials, state-aware controls, single- and multiline text editing, localized view updates, and a Swift-native declarative view tree. It deliberately has no markup compatibility layer.

```swift
struct SettingsView: FluentView {
    var body: FluentAnyView {
        FluentAnyView(FluentVStack(spacing: 14) {
            FluentText("Settings", size: 24, weight: .semibold)
            FluentNativeView(FluentTextField(placeholder: "Search"))
            FluentNativeView(FluentButton(title: "Save changes"))
            FluentNativeView(FluentToggle(title: "Use notifications", isOn: true))
            FluentNativeView(FluentProgressBar(value: 0.72))
        })
    }
}

let host = FluentViewHost(SettingsView())
```

The included `FluentGallery` executable is a visual sandbox for the components. Build it with `swift build`, then run `.build/debug/FluentGallery`.

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

Use `FluentWindowPlacement` when a scene needs a predictable initial position. `.automatic` centers the first scene and cascades later scenes; `.centered`, `.cascade`, corner placements, and `.origin(x:y:)` are also available. Positions are clamped to the visible screen frame. `FluentWindowRestoration.automatic` (the default) persists the last frame by scene ID and restores it on the next launch; use `.disabled` for transient windows.

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

For command-line smoke validation of state, bindings, theme tokens, public identity APIs, performance,
lifecycle cleanup, and snapshot baselines, run `swift run FluentKitValidation`. XCTest is intentionally
not declared yet because the current Command Line Tools installation does not provide the XCTest module;
the validation executable keeps CI checks useful until a full Xcode toolchain is available. Release
compatibility and versioning policy live in [COMPATIBILITY.md](COMPATIBILITY.md), and the current release
is recorded in [VERSION](VERSION).

Application-wide commands can opt into a native macOS main menu by conforming the app to `FluentApplicationCommands`. Command groups are rebuilt declaratively, preserve key equivalents and modifier masks, and reevaluate `isEnabled` when the menu validates:

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

The framework is built in layers. Milestones 1-13, 16, and 18-20 are complete. Milestones 14-15
continue to expand text and presentation depth. Milestone 17 is in visual acceptance after closing
its theme/style implementation scope, and Milestone 21 has begun with native application event and
scene services:

1. Declarative tree, AppKit host, reconciliation, state, bindings, and environment values.
2. Fluent materials, theme tokens, layout containers, native controls, lists, menus, overlays, drag/drop, lifecycle, focus, and accessibility.
3. Scoped keyboard commands, DisclosureGroup, SegmentedControl, DatePicker, ColorPicker, and value-driven navigation.
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
19. Acrylic application flyouts and context menus while preserving the native macOS main menu.
20. Accessibility and localization depth, including RTL behavior and automated semantic audits.
21. Application services such as settings, open events, printing, sharing, and import/export.
22. Production hardening, snapshot baselines, performance/leak tests, documentation, and compatibility policy.

Milestone 13 adds a complete input and form layer: secure and search fields, stable-value combo boxes, range-clamped steppers, validation states, form sections, labeled content, semantic control sizing, and Return/Escape default and cancel actions. Every control is implemented as a native AppKit view and can be embedded directly or through `FluentNativeView`. See [ROADMAP.md](ROADMAP.md) for the staged path toward a complete application framework.

The foundational Milestone 14 text-system slice adds `FluentRichTextEditor`, an attributed `NSTextView` editor with a two-way `NSAttributedString` binding, optional selection binding, native undo, bold/italic/underline, font size, color and alignment operations, formatting-state observation, case-insensitive find, and replace-all. Stable-ID text attachments can be inserted, enumerated, and removed without coupling application models to AppKit attachment identity. The editor remains a normal Fluent view, so it can live inside forms, scroll views, sheets, and navigation destinations.

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

Buttons, toggles, sliders, progress bars, check boxes, radio buttons, segmented controls, and text
fields accept reusable state-dependent styles while retaining their native identities and bindings.
The built-in styles cover common action and input emphasis:

```swift
FluentHStack(spacing: 8) {
    FluentButtonView("Save").buttonStyle(FluentAccentButtonStyle())
    FluentButtonView("Preview").buttonStyle(FluentOutlineButtonStyle())
    FluentButtonView("More").buttonStyle(FluentBorderlessButtonStyle())
}

FluentToggleView("Notifications", isOn: $notifications)
    .toggleStyle(FluentMonochromeToggleStyle())

FluentSliderView(value: $volume)
    .sliderStyle(FluentNeutralSliderStyle())

FluentProgressBar(value: downloadFraction)
    .progressStyle(FluentNeutralProgressStyle())

FluentCheckBoxView("Completed", isChecked: $completed)
    .checkBoxStyle(FluentMonochromeCheckBoxStyle())

FluentRadioButtonView("Primary", isSelected: $primary)
    .radioButtonStyle(FluentAutomaticRadioButtonStyle())

FluentSegmentedControl(["One", "Two"], selection: $mode)
    .segmentedStyle(FluentNeutralSegmentedStyle())

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

FluentDatePicker(selection: $dueDate, range: allowedDates)
    .textFieldStyle(FluentUnderlineTextFieldStyle())

FluentStepper("Items", value: $quantity, in: 1...12)
    .stepperStyle(FluentInlineStepperStyle())
```

Combo-box fields keep their native `NSComboBox` identity and accessibility role, but their option
popup is an application-owned `FluentMenuFlyout`. The popup uses the same Acrylic surface, checked
state, keyboard navigation, type-ahead, Escape/outside-click dismissal, and RTL placement as other
in-app menus; AppKit's native combo-box popup is not used.

Segmented controls use a custom Fluent renderer while preserving `NSSegmentedControl` identity.
One shared selection surface moves between segments with tokenized position, scale, and opacity
motion; labels, hover states, focus outlines, mouse selection, and keyboard navigation are rendered
and synchronized by FluentKit rather than by the native segmented cell.

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

Single-selection `FluentList` instances use one shared active selection indicator plus a transient
outgoing indicator during movement between stable row identities. The Gallery navigation shell uses
this same renderer and its directional 600ms choreography, so application navigation does not need a
private indicator implementation.

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

Focus behavior is also declarative. `fluentInitialFocus()` requests the first enabled focusable descendant once a view enters a window, while preserving an existing responder. `fluentFocusScope()` gives controls inside the subtree a deterministic Tab loop; nested scopes keep their own loops. Use `focused(_:)` when application state needs to follow or drive the native responder:

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

Overlays use native macOS presentation hosts while keeping their content declarative. Use `FluentPopoverButton` for transient content, `FluentSheet` (or the `sheet(isPresented:title:size:)` modifier) for custom modal content, and `confirmationDialog` for native confirmation sheets. Sheets clamp their requested size to a usable minimum, update presented content in place, and synchronize dismissal back to the binding.

`teachingTip` presents a directional, application-owned Acrylic child panel next to its anchor.
The panel preserves the anchor identity, provides a close command and accessibility group, dismisses
on Escape or outside clicks, synchronizes its binding, and uses distinct entrance/exit motion while
honoring Reduce Motion:

```swift
FluentButtonView("Help")
    .teachingTip(
        isPresented: $showHelp,
        placement: .top,
        size: NSSize(width: 300, height: 126)
    ) {
        FluentVStack(spacing: 6) {
            FluentText("Keyboard navigation", style: .headline)
            FluentText("Use arrow keys to move between items.", style: .body)
        }
    }
```

The macOS application menu deliberately remains an `NSMenu`. In-application menu buttons and
`contextMenu` use the custom `FluentMenuFlyout` Acrylic panel instead, so item spacing, state fills,
checkmarks, separators, accelerators, keyboard navigation, and dismissal behavior are controlled by
FluentKit rather than inherited from the system menu renderer. Menu items can declare nested flyouts
without leaving the Swift API:

```swift
FluentMenuButton(title: "Options", items: [
    FluentMenuItem("Focus search") { focusSearch() },
    .separator,
    .submenu("Account actions") {
        FluentMenuItem("Rename") { renameAccount() }
        FluentMenuItem("Manage access") { manageAccess() }
    }
])
```

Submenus open after a short pointer hover delay or immediately from keyboard/accessibility input.
Arrow keys move between levels, printable keys perform type-ahead matching, and the presenter mirrors
its chevrons, checkmarks, accelerator columns, and anchor placement for right-to-left layouts.

## License

FluentKit is released under the MIT License. See [LICENSE](LICENSE).
