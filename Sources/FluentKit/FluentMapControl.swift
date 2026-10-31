import AppKit
import MapKit

/// A geographic position (`Windows.Devices.Geolocation.Geopoint`).
public struct FluentGeopoint: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// A pin on a MapControl (`MapIcon` in a `MapElementsLayer`).
public struct FluentMapIcon: Identifiable, Hashable, Sendable {
    public var id: String
    public var location: FluentGeopoint
    public var title: String?

    public init(id: String, location: FluentGeopoint, title: String? = nil) {
        self.id = id
        self.location = location
        self.title = title
    }
}

/// A WinUI-style MapControl backed by MapKit (WinUI 3's control is backed by Azure Maps, so no
/// `MapServiceToken` is needed here). `center` and `zoomLevel` are two-way; zoom levels use the
/// same Web Mercator scale (level 0 shows the world in 256 points). Trackpad, mouse and touch
/// gestures are MapKit's own.
public struct FluentMapControl: FluentUpdatablePrimitiveView {
    private let configuration: FluentMapConfiguration

    public init(
        center: FluentBinding<FluentGeopoint>,
        zoomLevel: FluentBinding<Double>,
        icons: [FluentMapIcon] = [],
        interactiveControlsVisible: Bool = true,
        onMapElementClick: ((FluentMapIcon) -> Void)? = nil
    ) {
        configuration = FluentMapConfiguration(center: center, zoomLevel: zoomLevel, icons: icons,
                                               interactiveControlsVisible: interactiveControlsVisible,
                                               onMapElementClick: onMapElementClick)
    }

    public var body: NeverFluentView { NeverFluentView() }

    public func _makeView(in context: FluentRenderContext) -> NSView {
        let view = FluentMapControlView()
        view.update(configuration: configuration)
        return view
    }

    public func _updateView(_ view: NSView, in context: FluentRenderContext) -> Bool {
        guard let view = view as? FluentMapControlView else { return false }
        view.update(configuration: configuration)
        return true
    }
}

struct FluentMapConfiguration {
    var center: FluentBinding<FluentGeopoint>
    var zoomLevel: FluentBinding<Double>
    var icons: [FluentMapIcon]
    var interactiveControlsVisible: Bool
    var onMapElementClick: ((FluentMapIcon) -> Void)?
}

enum FluentMapZoom {
    static let tileSize: Double = 256
    static let minimumZoom: Double = 0
    static let maximumZoom: Double = 22

    /// Longitude span visible across `width` points at a Web Mercator zoom level.
    static func longitudeDelta(zoom: Double, width: Double) -> Double {
        min(360, 360 * max(width, 1) / (tileSize * pow(2, zoom)))
    }

    static func zoom(longitudeDelta: Double, width: Double) -> Double {
        guard longitudeDelta > 0 else { return maximumZoom }
        return min(max(log2(360 * max(width, 1) / (tileSize * longitudeDelta)), minimumZoom), maximumZoom)
    }
}

final class FluentMapIconAnnotation: NSObject, MKAnnotation {
    let icon: FluentMapIcon
    var coordinate: CLLocationCoordinate2D { icon.location.coordinate }
    var title: String? { icon.title }
    init(icon: FluentMapIcon) { self.icon = icon }
}

final class FluentMapControlView: NSView, MKMapViewDelegate {
    let mapView = MKMapView()
    private(set) var configuration: FluentMapConfiguration?
    private var isApplyingRegion = false
    private var isWritingBindings = false
    private var appliedCenter: FluentGeopoint?
    private var appliedZoom: Double?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("FluentKit.MapControl")
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = true
        mapView.autoresizingMask = [.width, .height]
        addSubview(mapView)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 400, height: 300) }

    var annotations: [FluentMapIconAnnotation] { mapView.annotations.compactMap { $0 as? FluentMapIconAnnotation } }

    func update(configuration next: FluentMapConfiguration) {
        configuration = next
        // `InteractiveControlsVisible`: zoom buttons, compass and scale.
        mapView.showsZoomControls = next.interactiveControlsVisible
        mapView.showsCompass = next.interactiveControlsVisible
        mapView.showsScale = next.interactiveControlsVisible
        syncIcons(next.icons)
        applyRegionIfNeeded()
    }

    override func layout() {
        super.layout()
        mapView.frame = bounds
        applyRegionIfNeeded(force: appliedZoom == nil)
    }

    private func applyRegionIfNeeded(force: Bool = false) {
        guard let configuration, bounds.width > 0 else { return }
        let center = configuration.center.get()
        let zoom = min(max(configuration.zoomLevel.get(), FluentMapZoom.minimumZoom), FluentMapZoom.maximumZoom)
        guard force || center != appliedCenter || zoom != appliedZoom else { return }
        appliedCenter = center
        appliedZoom = zoom
        let longitudeDelta = FluentMapZoom.longitudeDelta(zoom: zoom, width: bounds.width)
        let latitudeDelta = min(180, longitudeDelta * Double(max(bounds.height, 1) / max(bounds.width, 1)))
        isApplyingRegion = true
        mapView.setRegion(MKCoordinateRegion(center: center.coordinate,
                                             span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)),
                          animated: false)
        isApplyingRegion = false
    }

    private func syncIcons(_ icons: [FluentMapIcon]) {
        let existing = Dictionary(uniqueKeysWithValues: annotations.map { ($0.icon.id, $0) })
        let wanted = Dictionary(uniqueKeysWithValues: icons.map { ($0.id, $0) })
        let removed = existing.filter { wanted[$0.key] != $0.value.icon }.map(\.value)
        mapView.removeAnnotations(removed)
        let kept = Set(existing.keys).subtracting(removed.map(\.icon.id))
        mapView.addAnnotations(icons.filter { !kept.contains($0.id) }.map(FluentMapIconAnnotation.init))
    }

    /// Writes the user's pans and zooms back to `center` and `zoomLevel`.
    func regionDidChange() {
        guard !isApplyingRegion, let configuration, bounds.width > 0 else { return }
        let region = mapView.region
        let center = FluentGeopoint(latitude: region.center.latitude, longitude: region.center.longitude)
        let zoom = FluentMapZoom.zoom(longitudeDelta: region.span.longitudeDelta, width: bounds.width)
        appliedCenter = center
        appliedZoom = zoom
        isWritingBindings = true
        if configuration.center.get() != center { configuration.center.set(center) }
        if abs(configuration.zoomLevel.get() - zoom) > 0.0001 { configuration.zoomLevel.set(zoom) }
        isWritingBindings = false
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { regionDidChange() }

    /// `MapElementClick`: selecting an icon reports it and clears the selection.
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation as? FluentMapIconAnnotation else { return }
        iconClicked(annotation.icon)
        mapView.deselectAnnotation(annotation, animated: false)
    }

    func iconClicked(_ icon: FluentMapIcon) {
        configuration?.onMapElementClick?(icon)
    }
}
