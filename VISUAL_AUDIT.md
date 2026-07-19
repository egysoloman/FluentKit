# FluentKit Gallery Visual and Motion Audit

Date: 2026-07-19  
Scope: `Sources/FluentKit`, `Sources/FluentGallery`, and the bundled WinUI 3 source tree  
Status: Audit baseline with implementation progress tracked below.

## Implementation Update - 2026-07-19

Completed in the first layout and motion hardening pass:

- `FluentDivider` now has explicit horizontal and vertical orientations; the Gallery column divider
  uses the vertical contract.
- The shared list selection rail now follows flow-layout document coordinates, updates after layout,
  scrolling, bounds changes, frame changes, selection, and stable-ID reordering, and has executable
  selected-row alignment coverage.
- Gallery page content is keyed by `GalleryPage` inside a persistent transition host with a Fluent
  cubic-bezier token, latest-update coalescing, RTL-aware direction, and Reduce Motion behavior.
- Transition cleanup is driven by a Core Animation completion callback with a generation-checked
  dispatch fallback for non-presenting validation environments; rapid updates resolve to the latest
  requested page without retaining outgoing entries.
- The shared vertical list rail now keeps separate active and outgoing indicator layers and follows
  the WinUI same-level NavigationView choreography: 3 x 16 geometry, 600ms two-phase Scale/Offset,
  1/3 connected-rect peak, outgoing opacity hold/fade, upward/downward direction, RTL leading edge,
  cancellation, rapid-target replacement, and Reduce Motion snapping.
- Duplicate page-local titles were removed, the Collections viewport was expanded to show both
  sections completely, and Controls/Inputs Light and Dark captures were regenerated.
- `FluentKitValidation` now verifies every documented bitmap baseline for existence, dimensions,
  and visible pixel variation.

Completed in the NavigationView and TitleBar pass:

- Public `FluentNavigationView` now supplies Auto, Left, LeftCompact, LeftMinimal overlay, and Top
  modes, primary/footer destinations, bound pane state, explicit 350ms open and 120ms close motion,
  keyboard/accessibility behavior, RTL, Reduce Motion, and custom Top overflow.
- The reusable navigation indicator now uses the two-indicator choreography in both vertical and
  horizontal orientations. Primary-to-footer changes exercise the cross-section path; Top overflow
  selection routes the horizontal indicator through `More`.
- Navigation item rendering owns normal, pointer-over, pressed, selected combinations, disabled,
  and keyboard-focus states instead of relying on Gallery-specific rows.
- Public `FluentTitleBar` now supplies 32pt compact and 48pt expanded/automatic layouts, pane and
  back actions, icon/title/subtitle, left/center/right slots, RTL, inactive-window state, native
  dragging and double-click behavior, and native traffic-light exclusion/restoration.
- Gallery uses one shared pane binding between `FluentTitleBar` and `FluentNavigationView`, removes
  the duplicate native-rendering label, and retains one shell-owned page title.
- Fourteen Light/Dark/RTL/responsive bitmap baselines now include the integrated title bar.

Still open by design:

- Exact control state machines and geometry remain open in the order documented in section 20:
  ToggleSwitch, Slider, CheckBox/RadioButton, SegmentedControl, then ProgressBar.
- Transient material work is deferred. This pass does not change Acrylic, Mica, menu, TeachingTip,
  Popover, or overlay material behavior. The verified MenuFlyout motion specification in section 17
  remains the implementation contract for the later menu pass.
- Full XCTest integration remains blocked until a complete Xcode toolchain provides `XCTest`.

## 1. Objective

The target is not a WinUI runtime compatibility layer. FluentKit should preserve AppKit windowing, input, keyboard, accessibility, and native control behavior while reproducing the visible appearance, visual states, and motion character of WinUI 3.

The material direction is now explicit:

- Acrylic is not part of the target design.
- In-application transient surfaces must use Liquid Glass.
- The macOS system main menu remains native `NSMenu`.
- WinUI source remains the authority for geometry, state sequences, durations, curves, and keyframes where the target deliberately reproduces WinUI behavior.

## 2. Executive Summary

The project already contains a broad AppKit-based declarative control library, custom drawing, theme tokens, state-aware controls, menu flyouts, transition hosts, keyframe/value animation, and matched geometry infrastructure. The current Gallery, however, does not yet provide a reliable visual proof of WinUI fidelity.

The most visible failures have different owners:

| Symptom | Owner | Primary cause |
|---|---|---|
| Gallery page changes have no visible transition | Resolved | Stable keyed transition host, RTL direction, Reduce Motion, and rapid-update coalescing |
| Navigation indicator appears near the top | Resolved | Explicit document-to-layer conversion plus layout/scroll/resize synchronization |
| Menu content looks doubled or ghosted | FluentKit surface | Acrylic transparency allows underlying text to remain legible; panel shadow and inner border create a second outline |
| Menu motion does not feel specific to a menu | FluentKit motion | Menu reuses TeachingTip motion tokens |
| Navigation selection does not resemble WinUI | Visual acceptance | Reusable row states and two-indicator motion exist; exact token/pixel comparison remains |
| Controls have inconsistent motion | FluentKit motion architecture | WinUI tokens coexist with generic Core Animation defaults and component-local timing choices |

The correct order is to stabilize coordinates and host lifecycles first, then replace the material layer, then reproduce component visuals and choreography. Adjusting colors before those structural issues are fixed will not produce reliable results.

## 3. Audit Method

This audit used:

- The two supplied Gallery screenshots.
- Static inspection of the Gallery shell and FluentKit component implementations.
- Comparison with motion constants and algorithms in the bundled WinUI 3 source.
- A clean `swift build`, which completed successfully.

The audit did not include frame-by-frame runtime capture, automated pixel comparison, or interaction recording. Those are required in the verification phase.

## 4. Architecture Assessment

### 4.1 What the project currently is

FluentKit is a Swift/AppKit declarative UI layer. Its native behavior comes from AppKit, while custom `NSView`, `NSControl`, Core Graphics, and Core Animation code supplies Fluent visuals.

This is appropriate for the stated target:

```text
WinUI source and reference behavior
        -> Swift visual/state/motion specifications
        -> AppKit controls and event handling
        -> Core Graphics/Core Animation/Liquid Glass rendering
```

Windows Composition and XAML runtime objects cannot be reused directly. Algorithms and specifications must be rewritten in Swift; only their final low-level operations map to macOS rendering primitives.

### 4.2 Existing strengths

- Stable declarative primitives and AppKit hosting exist.
- Core controls expose semantic states and theme inputs.
- Duration and cubic-bezier tokens have begun to use WinUI values.
- A custom in-application menu presenter exists.
- Transition, value animation, keyframe, spring, and matched geometry infrastructure exists.
- Reduce Motion is represented in the rendering context.
- The project builds successfully.

### 4.3 Structural weaknesses

- Motion is opt-in and inconsistently connected to the Gallery.
- Generic animation defaults remain alongside WinUI-specific tokens.
- Several visual components mix AppKit view coordinates with CALayer coordinates.
- Some components update animated geometry and then overwrite it in a nonanimated layout pass.
- Material behavior is encoded inside individual presenters instead of a single surface system.
- NavigationView and TitleBar structure is now reusable; remaining weaknesses are component-level
  visual token fidelity rather than Gallery-owned shell drawing.

## 5. Critical Findings

### P0-1: Navigation indicator coordinate failure - resolved

Owner: FluentKit `FluentList`  
File: `Sources/FluentKit/FluentList.swift`, `updateSelectionIndicator`

The selection indicator is a sublayer of `collectionView.layer`. Its target frame is calculated directly from `NSCollectionViewFlowLayout` attributes and assigned to the sublayer. The implementation does not establish whether the sublayer geometry matches the collection view's flipped coordinate system.

Impact:

- The selected row and accent indicator can disagree.
- The indicator may appear near the top or opposite side of the list.
- Animation keyframes inherit the same invalid coordinates.
- Scrolling and relayout can move the indicator unpredictably.

Required correction:

- Define one coordinate space for layout and animation.
- Convert item frames explicitly into the indicator host's layer coordinates.
- Recompute after layout, scrolling, bounds changes, row insertion, and selection changes.
- Test flipped and nonflipped hosts instead of relying on CALayer defaults.

Acceptance criteria:

- Indicator center aligns with the selected row before, during, and after animation.
- Alignment remains correct after scrolling, resizing, theme changes, and rapid selection changes.

Current status: complete with executable selected-row, scrolling, resize, stable-ID update, RTL, and
Reduce Motion coverage. `FluentList` converts layout document frames into its layer coordinate space
before calculating the rail frame.

### P0-2: Gallery main navigation has no page transition - resolved

Owner: FluentGallery  
File: `Sources/FluentGallery/main.swift`, `GalleryNavigationShell`

The page body is inserted directly into the scroll view. It is not wrapped by a persistent transition host keyed by the selected page. The existing transition component therefore never receives an old/new page pair.

Impact:

- Sidebar selection changes immediately replace the page.
- Users cannot see the motion system while using the primary Gallery workflow.
- The Gallery understates the framework's existing animation capability.

Required correction:

- Keep a stable content host across page changes.
- Track old and new page identities explicitly.
- Apply direction-aware entrance/exit choreography.
- Preserve scroll position according to an explicit policy.
- Respect system and Gallery Reduce Motion settings.

Acceptance criteria:

- Every primary navigation change has a visible, interruptible transition when motion is enabled.
- No stale page remains mounted after completion.
- Rapid navigation settles on the last requested page without flashing.

Current status: complete. Gallery keys page content by `GalleryPage` inside a persistent transition
host and uses a Fluent 250ms cubic-bezier token with RTL direction, Reduce Motion, generation-safe
completion cleanup, and latest-update coalescing.

### P0-3: Transient surface system uses the rejected material

Owner: FluentKit material/presentation layer  
Files: `FluentMaterialView.swift`, `FluentMenus.swift`, `FluentTeachingTip.swift`, `FluentOverlays.swift`

MenuFlyout and TeachingTip instantiate `.acrylic`. Acrylic is no longer part of the target direction.

Impact:

- Underlying text remains readable through menus, producing perceived ghosting.
- Material appearance does not match the chosen macOS-native Liquid Glass direction.
- Material tuning is duplicated across presenters.

Required correction:

- Introduce one Liquid Glass surface renderer.
- Route MenuFlyout, TeachingTip, Popover, transient panels, and optional navigation surfaces through it.
- Centralize glass tint, blur, saturation, edge highlight, border, shadow, active state, and contrast behavior.
- Provide graceful fallback for systems without the desired Liquid Glass API.
- Remove component-local Acrylic alpha tuning.

Acceptance criteria:

- Text behind a menu cannot be read as a duplicate of foreground content.
- Glass remains visibly distinct from opaque content surfaces.
- Light, dark, inactive-window, and increased-contrast states remain legible.

## 6. Navigation Audit

### P1-1: Navigation row state ownership - implemented, visual acceptance open

Gallery no longer owns a private row renderer. `FluentNavigationItemButton` now draws the reusable
normal, pointer-over, pressed, selected, selected-pointer-over, selected-pressed, disabled, and
keyboard-focus states. Exact WinUI resource colors and pixel comparison remain part of visual
acceptance rather than a missing state-model capability.

Required states:

- Normal
- PointerOver
- Pressed
- Selected
- SelectedPointerOver
- SelectedPressed
- Disabled where applicable
- Keyboard focused

The selected surface and accent indicator must be coordinated. They should not be implemented as unrelated visual updates.

### P1-2: Indicator choreography - complete for list and NavigationView paths

The shared list renderer now maintains separate previous and next indicator layers. Its vertical
same-level path uses a stable 3 x 16 rail, a 600ms `0`, `0.333`, `1` timeline, WinUI source curves,
connected-rectangle peak scaling, outgoing opacity hold/fade, and explicit direction-aware geometry.
The model frame remains stable while the effective position keyframes encode the visual result of the
WinUI CenterPoint transition; this avoids the AppKit frame jump that a raw anchor-point mutation would
cause.

The reusable NavigationView uses the same two-indicator engine vertically for primary/footer
destinations and horizontally for Top navigation. Hidden Top selections route through `More` without
moving the model indicator to an invalid destination. Same-target repetition, target replacement,
cancellation, RTL leading-rail placement, primary-to-footer changes, Top overflow, and Reduce Motion
are covered by executable validation. The CenterPoint behavior is represented internally through
stable model frames plus effective position/scale keyframes; a public anchor API is not required for
the component acceptance contract.

### P1-3: Gallery navigation is not a reusable NavigationView proof - resolved

Original finding: the shell combined `FluentList` with Gallery-specific native rows and a separate
footer button, so it did not demonstrate a coherent public NavigationView component.

Required correction:

- Move item layout, state rendering, selection indicator, footer/settings placement, pane sizing, and pane motion into a reusable navigation presenter.
- Keep Gallery data and destination content outside the component.

Current status: complete. Gallery supplies only destination metadata, selection, pane binding, and
page content to public `FluentNavigationView`; the component owns item/footer layout, pane modes,
selection surfaces, overflow, indicator geometry, pane motion, keyboard, and accessibility.

## 7. Menu and Popup Audit

### P1-4: Menu positioning API is ambiguous

`present(relativeTo:at:)` mixes anchor-view bounds, local points, window coordinates, and screen coordinates. Menu buttons pass a local `bounds.minY` point even though a button-relative placement mode would be more reliable.

Required correction:

- Separate anchor-rect placement from pointer placement.
- Use explicit placement modes such as bottom-start, bottom-end, top-start, pointer, and submenu-leading/trailing.
- Calculate the final screen frame before creating or animating the panel.
- Record whether the surface was flipped above/below so motion direction matches placement.

### P1-5: Menu motion is borrowed from TeachingTip

The menu currently uses TeachingTip open/close tokens: scale, vertical translation, opacity, `300ms` open, and `200ms` close.

Required correction:

- Define MenuFlyout-specific motion specifications from the relevant WinUI MenuFlyout resources and behavior.
- Adapt only the final rendering to Liquid Glass/Core Animation.
- Animate from the placement edge or transform origin.
- Coordinate panel opacity, glass highlight, shadow, content reveal, and submenu opening.

### P1-6: Menu outline appears doubled

The panel has a native shadow while the material view adds its own border and clips to rounded corners. With a translucent surface this produces an outer shadow, inner border, and visible underlying geometry.

Required correction:

- Make the Liquid Glass surface the single owner of edge highlight, border, and shadow.
- Avoid layering a generic panel shadow with an unrelated inner stroke unless both values are deliberately specified.

### P2-1: Menu item model is visually incomplete

The current item model supports title, state, shortcut, separator, submenu, and action. It does not expose a leading icon/glyph or richer command presentation.

Required additions:

- Optional leading icon.
- Check/radio/icon slot rules.
- Accelerator column metrics.
- Submenu indicator slot.
- Destructive or emphasized command role if required by the target Gallery.
- Explicit disabled and focus visuals.

## 8. Control Appearance Audit

### P1-7: Several controls retain visibly native macOS chrome

The supplied Inputs screenshot shows native date and stepper arrows and other AppKit-specific geometry. Preserving AppKit behavior is correct, but their visible chrome must be replaced or overlaid when the target is WinUI appearance.

High-priority controls:

- DatePicker
- Stepper/NumberBox
- ComboBox
- TextField/SecureField
- Slider
- ToggleSwitch
- CheckBox and RadioButton

Required approach:

- Keep the native editor/control for event handling and accessibility.
- Hide or neutralize incompatible native chrome.
- Draw the Fluent visual surface and states in the owning wrapper.
- Preserve native first responder, text input, selection, keyboard, and accessibility behavior.

### P1-8: Control state animations can be overwritten by layout

Toggle geometry is changed in an animated CATransaction, then the control requests layout. The layout path writes the same geometry with actions disabled. This can collapse a visible transition into an immediate final state.

Required correction:

- Separate model geometry from presentation animation.
- Do not rewrite animated layer properties in the next nonanimated layout pass unless bounds actually changed.
- On resize, sample or cancel the current animation deliberately and continue from a defined state.

### P2-2: Theme colors are approximations rather than generated resources

Many surfaces use manually chosen calibrated colors and alpha values. This creates a generally gray, washed hierarchy and makes state differences subtle.

Required correction:

- Parse or transcribe relevant WinUI resource keys into semantic Swift tokens.
- Keep Liquid Glass material tokens separate from WinUI opaque fill tokens.
- Define Light, Dark, High Contrast, Disabled, PointerOver, Pressed, and Selected variants centrally.
- Prevent components from inventing their own opacity values.

### P2-3: Metrics are globally scaled approximations

Spacing, control height, corner radius, card radius, and navigation width are derived from a small handcrafted token set. This is useful infrastructure but insufficient for exact control fidelity.

Required correction:

- Add component-specific metrics sourced from WinUI theme resources.
- Avoid multiplying corner radii blindly with density.
- Keep macOS-specific hit target adjustments separate from visible WinUI geometry.

## 9. Motion System Audit

### P1-9: Two timing systems coexist

WinUI-derived motion tokens exist, but the default rendering context still uses Core Animation's generic `easeInEaseOut`. Components also choose local curves and durations.

Impact:

- Similar state changes feel unrelated.
- Page, control, navigation, and popup motion have inconsistent acceleration.
- Correct tokens can be bypassed accidentally.

Required correction:

- Make semantic motion tokens the only public default path.
- Group tokens by interaction: control state, navigation, connected animation, popup/menu, teaching tip, dialog, and emphasis.
- Require explicit exceptions rather than component-local raw durations.

### P1-10: Connected and Gravity motion are incomplete

The token layer contains default/direct/gravity-related values, but the connected-animation service lifecycle and full Gravity keyframe algorithm are not yet represented.

Required implementation:

- Source/target registration by stable identity.
- Snapshot or overlay hosting when source and target do not coexist.
- Old/new frame capture in one coordinate system.
- Direct and Gravity configurations.
- Coordinated elements.
- Interruption, cancellation, timeout, and cleanup.
- Gravity peak at the WinUI source phase with separate in/out curves, Y/Z displacement, scale, and shadow behavior.

### P1-11: Transition cleanup uses timers rather than animation completion - resolved

The transition host removes old content using a timer based on expected duration. Timers can drift from actual presentation completion during run-loop pressure, Reduce Motion changes, cancellation, or nested animations.

Required correction:

- Use animation completion callbacks or a transaction completion contract.
- Make cancellation idempotent.
- Remove old content exactly once.
- Clear transforms, opacity, shadows, and overlays on every exit path.

This area is a likely source of genuine stale-view ghosting once page transitions are enabled, even though the supplied menu screenshot is primarily material transparency.

Current status: complete. `FluentTransitionHost` installs a Core Animation completion delegate,
guards cleanup by transition generation, cancels superseded work, resets matched-geometry transforms
and shadows, and retains a dispatch fallback only for non-presenting validation environments.

### P2-4: Gallery motion-system coverage - partially resolved

The Motion page contains local examples, but primary workflows do not demonstrate page navigation, popup placement, menu hierarchy, selection movement, dialog presentation, and connected transitions together.

Required correction:

- Add representative motion to normal Gallery workflows.
- Keep a dedicated diagnostics page for replay, slow motion, reduced motion, and interruption testing.

Current status: navigation selection, page replacement, adaptive pane motion, Top overflow, menus,
and TeachingTip are reachable through normal Gallery workflows. Deterministic replay/slow-motion
diagnostics and connected-animation workflow coverage remain open.

## 10. Liquid Glass Surface Requirements

The Liquid Glass renderer should be a reusable surface abstraction rather than a renamed Acrylic enum case.

Required inputs:

- Surface role: menu, teaching tip, popover, dialog, navigation, toolbar, transient overlay.
- Color scheme and contrast.
- Window active state.
- Corner radius and shape.
- Elevation/shadow role.
- Placement edge and motion origin.
- Fallback capability.

Required rendering responsibilities:

- Native glass/backdrop effect where available.
- Stable tint and saturation control.
- Edge highlight and inner stroke.
- Shadow/elevation.
- Content legibility layer.
- Clipping and corner continuity.
- Active/inactive transition.
- Motion-safe opacity/highlight/shadow animation.

Liquid Glass must not allow background text to appear as a readable duplicate under foreground text. Glass character should come from material response and edge behavior, not uncontrolled low alpha.

## 11. Gallery-Specific Corrections

The Gallery must become a verification application rather than a loose component showcase.

Required changes:

1. **Complete:** use the reusable navigation component instead of Gallery-specific navigation drawing.
2. **Complete:** add a stable page transition host keyed by page identity.
3. Demonstrate every visual state for every core control.
4. Provide light, dark, increased-contrast, and Reduce Motion modes.
5. Include popup/menu placement near every screen edge.
6. Include rapid interaction and interruption scenarios.
7. **Complete:** remove explanatory labels such as "Native macOS rendering" when they distract from the target visual comparison.
8. Keep component examples aligned to a consistent grid and width system.
9. Add WinUI reference captures beside automated Gallery captures outside the shipping UI.

## 12. Prioritized Remediation Plan

### Phase 1: Rendering correctness

1. **Complete:** fix list/indicator coordinate conversion.
2. **Complete for page/navigation; popup placement remains:** establish stable page and popup hosts.
3. **Complete for page/navigation:** replace timer-only cleanup with completion-driven cleanup.
4. **Complete for page/navigation:** add interruption and cancellation handling.

### Phase 2: Surface architecture

5. Implement the Liquid Glass renderer.
6. Migrate MenuFlyout, TeachingTip, Popover, and overlays.
7. Centralize edge, border, shadow, and contrast ownership.

### Phase 3: Navigation fidelity

8. **Complete:** implement reusable NavigationView visual states.
9. **Complete:** rewrite the selection indicator using the WinUI two-indicator algorithm.
10. **Complete:** add pane open/close and page transition choreography.

### Phase 4: Core control fidelity

11. Normalize motion token consumption.
12. Fix animated geometry/layout conflicts.
13. Replace incompatible native chrome on core inputs.
14. Generate semantic visual tokens from WinUI resources.

### Phase 5: Verification

15. Add deterministic screenshot scenarios.
16. Add animation frame capture at defined normalized times.
17. Test light/dark/high contrast/reduced motion.
18. Test resize, scrolling, rapid selection, popup flipping, cancellation, and window deactivation.

## 13. Verification Matrix

Each audited component should pass:

| Area | Required checks |
|---|---|
| Geometry | 1x/2x scale, resize, scroll, flipped coordinates, edge placement |
| States | normal, hover, pressed, selected, focused, disabled |
| Themes | light, dark, increased contrast, inactive window |
| Motion | start, midpoint, end, rapid repeat, cancellation, Reduce Motion |
| Material | legibility, edge highlight, shadow, background response, fallback |
| Accessibility | keyboard, focus order, VoiceOver role/value/action |
| Performance | no stale views, no retained panels, no layout thrash, stable frame pacing |

## 14. Definition of Visual Completion

The Gallery should be considered visually complete only when:

- Core components are recognizable as WinUI 3 without relying on labels.
- AppKit behavior remains intact but incompatible native chrome is not visible.
- Navigation selection and page changes reproduce the intended WinUI state sequence and motion character.
- Transient surfaces consistently use Liquid Glass and remain legible.
- No indicator, overlay, shadow, or old page remains in an incorrect coordinate or lifecycle state.
- Motion parameters are traceable to WinUI source or to an explicitly documented macOS Liquid Glass adaptation.
- Automated screenshots and keyframe captures pass across supported appearances and window sizes.

## 15. Final Assessment

FluentKit now has stable shell coordinates, transition hosting, reusable navigation choreography, and
custom title-bar integration. The Gallery is a reliable proof of those structural paths, but it is
not yet a complete proof of WinUI control fidelity. The immediate non-material blockers are the
ToggleSwitch, Slider, CheckBox/RadioButton, SegmentedControl, and ProgressBar state/geometry defects
in section 20. The obsolete Acrylic surface path remains an explicit later phase.

The target architecture should remain AppKit-native in behavior while becoming WinUI-source-driven in visible state and motion, with Liquid Glass as the macOS material adaptation for transient surfaces.

## 16. Follow-up Ownership Findings

The screenshot review identifies four additional issues and clarifies ownership. These are not one common Gallery bug.

### P0-4: Divider orientation is missing - resolved

Owner: FluentKit layout component  
File: `Sources/FluentKit/FluentContainers.swift`, `FluentDivider`

`FluentDivider` always creates a one-point-high view. When inserted into the Gallery's horizontal root `FluentHStack`, it has no fixed width and becomes the flexible consumer of the stack's remaining width. This produces the large empty center region and the long one-point horizontal line visible in the screenshot.

Required correction:

- Make divider orientation explicit, or derive it from the containing stack.
- Horizontal divider: flexible width, fixed height.
- Vertical divider: fixed width, flexible height.
- Do not rely on an unconstrained `NSStackView` arranged subview to infer orientation.

Current status: complete through explicit horizontal/vertical APIs and Gallery/validation coverage.

### P1-12: Gallery duplicates the page title - resolved

Owner: Gallery composition  
Files: `Sources/FluentGallery/main.swift`, `GalleryNavigationShell` and `collectionsPage`

The shell renders a header containing `page.title`, while each page also renders its own `pageHeading`. The Collections screenshot therefore shows two independent titles.

Required correction:

- Choose one title owner.
- Prefer a NavigationView/Header contract: the shell owns the page title and page content owns only its local section headings.
- Do not remove titles by visual hiding; define the hierarchy explicitly so accessibility exposes one page title.

Current status: complete. The shell owns the page title and page bodies own only section headings.

### P1-13: Collection content is constrained below its required extent - resolved for Gallery

Owner: Gallery sizing, with a component clipping contract to verify  
File: `Sources/FluentGallery/main.swift`, `collectionsPage`

The Gallery fixes the collection surface at `220pt`, while two section headers, item rows, spacing, and the following explanatory text require more vertical space. The result is content visually reaching into the following caption or being clipped at the wrong boundary.

Required correction:

- Decide whether the example is a fixed viewport with scrolling or an intrinsic collection preview.
- If it is a viewport, the collection owns scrolling and clips strictly to its bounds.
- If it is an intrinsic preview, derive height from layout content and place the caption after the measured result.
- Add a test for section headers and the last row at the lower edge.

Current status: Gallery uses a 360pt collection viewport that exposes both audited sections without
overlapping the following caption. A general intrinsic collection-sizing API remains separate work.

### P1-14: NavigationView and TitleBar capabilities - resolved

Owner: FluentKit capability plus Gallery integration

Original finding: WinUI 3 NavigationView exposes `Auto`, `Left`, `Top`, `LeftCompact`, and
`LeftMinimal` pane modes, together with bound pane state, toggle visibility, pane lengths, and
responsive thresholds. Gallery originally used a fixed-width stack/list and only exposed the
separate two-column `FluentNavigationSplitView` capability.

Original finding: WinUI 3 TitleBar also supports a compact/expanded height model, pane toggle, back
button, icon, title, subtitle, left header, centered content, and right header. Gallery originally
used an independent AppKit title bar and FluentKit did not expose that reusable capability.

Required correction:

- Add a reusable `FluentNavigationView` capability with expanded, compact, minimal/overlay, and optional top modes.
- Add a reusable `FluentTitleBar` capability with compact/expanded layout and drag-region ownership.
- Keep AppKit traffic lights, window controls, keyboard behavior, and accessibility semantics native underneath the visual layer.
- Refactor Gallery to consume those components instead of manually composing a fixed sidebar and independent title header.

Current status: complete. `FluentNavigationView` implements all listed pane modes and bindings.
`FluentTitleBar` implements compact/expanded geometry, pane/back controls, icon/title/subtitle,
left/center/right slots, drag-region behavior, RTL/inactive states, native title synchronization,
and reversible full-size chrome integration. Gallery composes the two components around one pane
binding and disables the NavigationView's internal toggle.

### Ownership summary

```text
FluentKit component defects:
  collection intrinsic-size contract
  exact core-control state geometry and motion
  Liquid Glass surface and motion ownership

Gallery composition defects:
  deterministic motion diagnostics remain incomplete
  edge-placement popup scenarios remain incomplete
```

The next non-material remediation order is ToggleSwitch, Slider, CheckBox/RadioButton,
SegmentedControl, and ProgressBar. Menu motion/placement follows the verified section 17 contract;
Liquid Glass remains explicitly deferred until layout, state, and motion are stable.

## 17. Menu Inventory and Gaps

Menus are present in the project, but they were previously grouped under the broader popup/command category rather than counted as a separate component family.

### Existing menu APIs

| API | Role | Current implementation |
|---|---|---|
| `FluentMenuItem` | Declarative item model | Title, enabled state, check state, shortcut, submenu, action |
| `FluentMenuFlyout` | In-app popup menu | Custom borderless `NSPanel` and custom item presenter |
| `FluentMenuButton` | Button-triggered menu | Opens a `FluentMenuFlyout` relative to the button |
| `FluentContextMenuView` | Context menu modifier/view | Opens a `FluentMenuFlyout` at the pointer location |
| `FluentCommandsView` | Declarative command integration | Connects command data to application/menu behavior |
| `FluentMainMenuCoordinator` | macOS main menu | Native `NSMenu`, retained for AppKit behavior |

Relevant files:

- `Sources/FluentKit/FluentMenus.swift`
- `Sources/FluentKit/FluentCommands.swift`

### Menu gaps

The current implementation does not yet expose a complete WinUI-style menu hierarchy:

- No explicit public `FluentMenu` container.
- No public `FluentMenuBar` or top-level in-app menu bar.
- MenuFlyout and ContextMenu share one presenter even though their placement and invocation semantics differ.
- Menu item visuals do not have a full icon/content/accelerator slot model.
- Menu placement is based on mixed local, window, and screen coordinates.
- Menu motion reuses TeachingTip tokens rather than a menu-specific specification.
- Menu surfaces still use the rejected Acrylic path and must migrate to Liquid Glass.
- Native main menu and in-app MenuFlyout are intentionally different systems, but this distinction is not yet reflected in a unified public API/documentation model.

The menu family should therefore be counted separately in the component plan. It currently contains six relevant public APIs, with three major visual components requiring focused work: MenuFlyout, ContextMenu, and the menu-triggering control. A complete target family should additionally define `FluentMenu` and, where needed, `FluentMenuBar`.

### WinUI MenuFlyout motion specification

WinUI does not open a menu with a generic two-axis scale-and-fade animation. It uses the dedicated internal `MenuPopupThemeTransition`, which reveals the menu vertically from the edge nearest its placement anchor.

Source locations:

- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/LayoutTransition_partial.cpp`, `MenuPopupThemeTransition::CreateStoryboardImpl`
- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/MenuPopupThemeTransition_Partial.h`
- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/MenuFlyout_Partial.cpp`, `PreparePopupTheme`
- `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/MenuFlyoutSubItem_Partial.cpp`, submenu transition setup

Verified parameters and behavior:

- Root MenuFlyout uses `ClosedRatio = 0.5`. Its border begins at `scaleY = 0.5` and expands to `1.0`.
- A submenu uses `ClosedRatio = 0.67`. Its border begins at `scaleY = 0.33` and expands to `1.0`.
- Open duration is `250 ms`.
- Open easing is cubic Bezier `(0,0,0,1)`.
- Opening animates clip translation, content translation, and border Y scale together. It does not scale the menu in X.
- Direction is placement-aware. A menu placed below its target reveals downward from its top edge; a menu placed above the target reverses the animation and reveals upward from its bottom edge.
- Closing is not the opening animation played backward. The menu fades from opacity `1` to `0` linearly over `83 ms` while preserving an interrupted opening clip if dismissal occurs mid-transition.
- An associated light-dismiss overlay, when present, fades linearly over `83 ms`.
- Menu-item `Normal`, `PointerOver`, `Pressed`, `Disabled`, and `SubMenuOpened` states primarily switch semantic brushes immediately. The template does not stagger menu-item entrance animations.
- Open/close motion is skipped when WinUI's `AreOpenCloseAnimationsEnabled` is false; FluentKit must connect the equivalent behavior to Reduce Motion.

The intended visual result is therefore a fast anchored reveal: the attachment edge remains visually stable while the remaining menu height is uncovered. It should not look like a floating card zooming toward the viewer.

Current FluentKit divergence:

- `FluentMenuFlyout` reuses `FluentMotion.teachingTipOpen` and `teachingTipClose`.
- Opening currently combines panel opacity with vertical translation and uniform X/Y scaling.
- Closing applies the same translated/scaled card treatment plus a fade.
- The motion does not derive its origin or direction from final menu placement.
- Root menus and submenus use the same geometry instead of the WinUI `0.5` versus `0.67` closed ratios.
- Submenu hover delay is an interaction policy and must remain separate from the submenu reveal animation.

Required correction:

- Add dedicated `menuOpen`, `submenuOpen`, and `menuClose` motion specifications instead of reusing TeachingTip tokens.
- Implement the reveal with a stable edge anchor, an animatable vertical mask/clip, content translation, and Y-only surface scaling.
- Select the reveal direction only after placement and edge-flipping have resolved.
- Open root menus from 50% height and submenus from 33% height over 250 ms with `(0,0,0,1)`.
- Close with an 83 ms linear opacity transition and completion-driven panel removal; do not reverse-collapse the surface.
- Preserve the current presentation clip when close interrupts open.
- Disable geometry motion under Reduce Motion while retaining correct final placement and visibility.
- Apply this motion to the required Liquid Glass menu surface. The WinUI Acrylic material is not part of the target; only its menu geometry and choreography are being replicated.

## 18. Consolidated Problem List

### Rendering and layout

1. **Resolved:** `FluentDivider` has explicit horizontal and vertical contracts.
2. **Resolved:** `FluentList` converts collection layout coordinates before positioning CALayers.
3. `FluentCollection` examples and Gallery pages use fixed heights without a clear viewport/intrinsic sizing contract.
4. Some animated layer geometry can be overwritten by subsequent nonanimated layout passes.
5. Transient surfaces can have multiple independent border/shadow owners.

### Gallery composition

6. **Resolved:** Gallery page content uses a persistent keyed transition host.
7. **Resolved:** the shell is the single page-title owner.
8. **Resolved:** Gallery uses public `FluentNavigationView` pane modes.
9. **Resolved:** Gallery uses public `FluentTitleBar` above the navigation shell.
10. **Partially resolved:** pane modes and page transitions are normal workflows; comprehensive menu
    edge placement remains open.

### Navigation and window chrome

11. **Resolved:** public `FluentNavigationView` covers Expanded, Compact, Minimal/Overlay, Auto, and Top.
12. **Resolved:** public `FluentTitleBar` covers compact/expanded height and all audited content slots.
13. **Implemented, awaiting pixel acceptance:** navigation rows own selected/hover/pressed/focus/disabled states.
14. **Resolved:** reusable NavigationView covers vertical primary/footer and horizontal Top indicator paths.

### Menus and transient surfaces

15. Existing MenuFlyout uses Acrylic, contrary to the Liquid Glass direction.
16. Menu transparency permits readable background content and creates the reported ghosting.
17. Menu positioning does not have explicit placement modes or a stable anchor-rect contract.
18. Menu animation is borrowed from TeachingTip and does not account for placement direction.
19. Menu item content slots are incomplete.
20. There is no explicit public `FluentMenu`/`FluentMenuBar` layer.

### Motion and verification

21. Generic `easeInEaseOut` defaults coexist with WinUI-derived motion tokens.
22. Connected and Gravity animation lifecycles are incomplete.
23. **Resolved for transitions/navigation:** completion-driven cleanup has a deterministic fallback.
24. **Partially resolved:** 14 deterministic responsive screenshots and normalized navigation
    keyframe checks exist; per-core-control keyframe captures remain open.

## 19. Implementation Plan

The plan is intentionally component-oriented. Each component must be inspected against the bundled WinUI source before implementation.

### Phase 0: Establish contracts

1. Define semantic resource/token namespaces for geometry, color, state, motion, surface, and accessibility.
2. Define a shared coordinate-space policy for AppKit views, flipped views, collection layout frames, CALayers, screen frames, and popup anchors.
3. Define Liquid Glass surface roles and fallback behavior.
4. Define the component acceptance harness: light, dark, high contrast, reduced motion, resize, scroll, keyboard, and interruption cases.

### Phase 1: Fix shared geometry

5. **Complete:** make `FluentDivider` orientation explicit.
6. **Complete:** correct `FluentList` indicator coordinate conversion and relayout behavior.
7. Establish collection viewport versus intrinsic-size behavior.
8. Make animated geometry resilient to layout passes and resizing.

### Phase 2: Build shared surface and window chrome

9. Implement `FluentLiquidGlassSurface`.
10. Migrate MenuFlyout, ContextMenu, TeachingTip, Popover, dialogs, and transient overlays from Acrylic to Liquid Glass.
11. **Complete:** implement `FluentTitleBar` with compact/expanded modes and AppKit drag-region integration.
12. **Complete:** verify title-bar content does not conflict with native traffic lights or window controls.

### Phase 3: Implement NavigationView

13. **Complete:** implement Expanded/Left mode.
14. **Complete:** implement LeftCompact mode with icon-only pane.
15. **Complete:** implement LeftMinimal/overlay mode and pane toggle.
16. **Complete:** implement Auto thresholds and Top mode.
17. **Complete structurally, pixel acceptance open:** implement row states and the WinUI indicator algorithm.
18. **Complete:** add pane open/close and selection motion with interruption handling.

### Phase 4: Implement menu family

19. Separate MenuFlyout, ContextMenu, and menu-bar invocation/placement contracts.
20. Add explicit `FluentMenu` and, if required by the application shell, `FluentMenuBar` APIs.
21. Add icon/content/accelerator/submenu slots to `FluentMenuItem`.
22. Implement stable placement modes and edge flipping.
23. Implement menu-specific open, close, hover, pressed, and submenu motion from WinUI resources.
24. Preserve native `NSMenu` for the macOS system main menu.

### Phase 5: Migrate core controls

25. Button and ToggleSwitch.
26. CheckBox, RadioButton, Slider, ProgressBar, and SegmentedControl.
27. TextBox, SearchBox, ComboBox, DatePicker, and NumberBox/Stepper.
28. ListView, GridView/CollectionView, Table, and Outline.
29. Dialogs, TeachingTip, Popover, Disclosure, and remaining long-tail controls.

### Phase 6: Rebuild Gallery as the verification surface

30. **Complete:** replace the fixed Gallery shell with `FluentNavigationView` and `FluentTitleBar`.
31. **Complete for audited title/collection defects:** remove duplicate page titles and clipping patches.
32. **Complete for page/pane, menu edge cases open:** add visible transitions and normal-workflow demonstrations.
33. Add Liquid Glass, theme, contrast, and Reduce Motion diagnostics.
34. Add screenshots and animation keyframe captures for every primary component.

### Phase 7: Completion gate

35. Compare screenshots against WinUI reference states.
36. Verify no stale indicator, old page, panel, shadow, or transform survives completion/cancellation.
37. Run build, accessibility, keyboard, resize, scrolling, and rapid-interaction checks.
38. Mark a component complete only when appearance, state behavior, motion, and fallback behavior all pass.

## 20. Core Controls Source Audit

The Controls screenshot exposes component-level state and motion gaps. The Gallery uses the public bindings directly and does not apply custom offsets or animation to these controls, so these findings belong to FluentKit rather than Gallery composition.

### Segmented selection

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentSegmentedControl.swift`, `Sources/FluentKit/FluentStyles.swift`

The component contains a 250 ms selection-indicator animation, but its presentation is not reliable:

- `FluentSegmentedControlNative` remains an `NSSegmentedControl` with native labels and selection state while also overlaying custom labels and a custom `selectionIndicatorView`.
- Every declarative update assigns theme/style again, rebuilds all overlay labels, and performs another indicator synchronization.
- `layout()` always calls `updateSelectionIndicator(animated: false)`, so a layout or state reconciliation during the 250 ms transition can replace the animated geometry with its final frame.
- The custom animation adds arbitrary scale and opacity keyframes (`1 -> 0.94 -> 1`, `1 -> 0.78 -> 1`) that are not sourced from the WinUI selection-control templates.

Required correction:

- Use one visual owner: retain AppKit interaction/semantics but suppress native segment chrome, or replace the native cell presenter with a dedicated AppKit container.
- Keep stable label and indicator objects across declarative updates.
- Separate model geometry from presentation geometry and do not write nonanimated frames while a transition is active.
- Derive the selected/pressed transition from the matching WinUI control template instead of treating the current approximation as verified WinUI motion.

### Slider thumb

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentSlider.swift`, `Sources/FluentKit/FluentStyles.swift`

The circle at the end of the upper range track is the Slider thumb; the lower `FluentProgressBar` has no thumb. WinUI defines the thumb as an 18 x 18 outer circle containing a 12 x 12 accent inner circle. Its inner circle transitions through separate visual states:

- Normal: 12 px visual size (`0.86` relative scale in the template), returning over 167 ms.
- PointerOver: 14 px (`1.167` relative scale), over 250 ms.
- Pressed: 10 px (`0.71` relative scale), over 250 ms.
- Curve: `ControlFastOutSlowInKeySpline`, `(0,0,0,1)`.

Source: `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/CommonStyles/Slider_themeresources.xaml`, especially the `SliderThumbStyle` CommonStates.

The current FluentKit slider draws one 14 px accent circle and shows a larger translucent halo for hover/drag. It redraws immediately and has no animatable outer/inner thumb layers, so it cannot reproduce the WinUI pressed contraction or hover expansion.

Required correction:

- Build a stable outer thumb layer and inner accent layer.
- Animate only the inner circle scale/color using the WinUI state values and motion tokens.
- Keep drag position animation separate from thumb-state animation so pointer motion remains direct while the pressed visual remains interpolated.

### ToggleSwitch pressed and dragging states

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentToggle.swift`, `Sources/FluentKit/FluentStyles.swift`

WinUI explicitly separates interaction state from logical value. Its template has `Normal`, `PointerOver`, `Pressed`, and `Disabled` common states, plus `Dragging`, `Off`, and `On` toggle states and dedicated `DraggingToOn`, `OnToDragging`, and `DraggingToOff` transitions. The 40 x 20 track uses a 12 x 12 normal knob, a 14 x 14 hover knob, and a 17 x 14 pressed knob. State-size changes use the 83 ms faster token and `(0,0,0,1)` curve; drag release uses reposition transitions and resolves to the final On or Off state.

Source: `microsoft-ui-xaml-winui3-release-2.3.1/src/controls/dev/CommonStyles/ToggleSwitch_themeresources_perf2026.xaml`.

The FluentKit style already contains the correct 12 x 12, 14 x 14, and 17 x 14 geometry, but the control state machine does not expose it correctly:

- `mouseDown` sets pressed and immediately toggles `isOn`; therefore there is no pressed-without-commit state.
- Pressed is cleared by an 83 ms timer rather than by pointer release/cancel.
- There is no `mouseDragged` or drag position.
- `refreshAppearance` animates layer frames and then requests layout; `layout()` writes the same frames with actions disabled, which can suppress or interrupt the visible transition.

Required correction:

- Track `idle`, `pressed`, and `dragging` interaction states independently from the committed Boolean value.
- On pointer down, preserve the current On/Off value and show the 17 x 14 pressed knob.
- During drag, move the knob continuously within the track while retaining only two commit outcomes: On or Off.
- On release/cancel, resolve by the midpoint/gesture direction and animate from the current presentation position to the selected endpoint.
- Commit the binding exactly once after resolution, not on pointer down.

### CheckBox and RadioButton selection motion

Owner: FluentKit component  
Files: `Sources/FluentKit/FluentChoiceControls.swift`, `Sources/FluentKit/FluentStyles.swift`

Both controls currently mutate their Boolean state in `mouseDown` and immediately redraw. Their style configurations do not contain a pressed state; RadioButton does not even expose pointer-over state. Consequently the selected glyphs have no WinUI visual-state transition.

Required correction:

- Add independent pointer-over, pressed, checked/unchecked or selected/unselected states.
- Commit on pointer release inside the control and cancel when released outside.
- Give the check mark and radio inner dot stable presentation layers so their size/opacity can animate with WinUI's 83/167/250 ms state tokens.

### ProgressBar clarification

Owner: FluentKit component  
File: `Sources/FluentKit/FluentProgressBar.swift`

The lower horizontal control is a determinate ProgressBar and should not receive a Slider thumb. Its current `NSAnimationContext` only marks an immediate-mode `draw()` view as needing display; `progressValue` itself is not animatable, so the fill is likely to jump rather than interpolate. This is a separate ProgressBar animation defect and must not be solved by adding the Slider circle to it.

### Additional problem-list entries

25. SegmentedControl mixes native segmented chrome with custom overlay chrome and allows nonanimated layout/update passes to interrupt its selection animation.
26. Slider lacks the WinUI outer/inner thumb structure and Normal/PointerOver/Pressed scale transitions.
27. ToggleSwitch commits on pointer down, has no drag state, and allows layout to overwrite animated knob geometry.
28. CheckBox and RadioButton lack independent pressed state and selected-glyph motion.
29. ProgressBar marks immediate drawing dirty inside an animation context without an interpolated presentation property.
