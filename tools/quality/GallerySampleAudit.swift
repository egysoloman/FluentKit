import AppKit
import FluentKit

@main struct GallerySampleAudit {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let screen = GalleryScreen(themeStore: FluentThemeStore(),
            navigationCoordinator: FluentNavigationCoordinator(initial: GalleryRoute(destination: .home)),
            undoCoordinator: FluentUndoCoordinator())
        let catalogIDs = Set(GalleryCatalog.allItems.map(\.id))
        precondition(Set(GallerySampleID.allCases.map(\.rawValue)).isSubset(of: catalogIDs))
        var results: [[String: Any]] = []
        for item in GalleryCatalog.allItems {
            let hasSample = GallerySampleID(rawValue: item.id) != nil
            precondition(item.coverage != .implemented || hasSample, "Implemented requires a direct sample: \(item.id)")
            var mounted: [String] = []
            if hasSample {
                for variant in ["light", "dark", "rtl"] {
                    let theme = FluentTheme.custom(colorScheme: variant == "dark" ? .dark : .light, materialEffectsEnabled: false)
                    let host = FluentViewHost(screen.sample(for: item, theme: theme),
                        context: .init(theme: theme, reduceMotion: true, layoutDirection: variant == "rtl" ? .rightToLeft : .leftToRight))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    precondition(!host.subviews.isEmpty)
                    func verify(_ view: NSView) {
                        precondition([view.frame.minX, view.frame.minY, view.frame.width, view.frame.height].allSatisfy(\.isFinite), "Nonfinite sample frame: \(item.id)")
                        view.subviews.forEach(verify)
                    }
                    verify(host)
                    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
                    let mountedViews = descendants(host)
                    switch item.id {
                    case "DatePicker":
                        precondition(mountedViews.contains { $0 is FluentWinUIDatePickerControl })
                        precondition(!mountedViews.contains { $0 is NSDatePicker })
                    case "CalendarDatePicker":
                        precondition(mountedViews.contains { $0 is NSDatePicker })
                        precondition(!mountedViews.contains { $0 is FluentWinUIDatePickerControl })
                    case "TimePicker": precondition(mountedViews.contains { $0 is FluentTimePicker })
                    case "Pivot": precondition(mountedViews.contains { $0.identifier?.rawValue == "FluentKit.Pivot" })
                    default: break
                    }
                    window.close()
                    mounted.append(variant)
                }
            }
            results.append(["id": item.id, "coverage": item.coverage.rawValue, "directSample": hasSample,
                "mountingVerified": mounted, "interactionStates": "requires per-control acceptance",
                "windowsComparison": "pending", "voiceOver": "pending"])
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
