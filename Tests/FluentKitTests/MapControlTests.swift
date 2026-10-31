import XCTest
import MapKit
@testable import FluentKit

final class MapControlTests: XCTestCase {
    func testWebMercatorZoomConversionRoundTrips() {
        XCTAssertEqual(FluentMapZoom.longitudeDelta(zoom: 0, width: 256), 360, "Level 0 shows the world in 256pt")
        XCTAssertEqual(FluentMapZoom.longitudeDelta(zoom: 1, width: 256), 180)
        XCTAssertEqual(FluentMapZoom.longitudeDelta(zoom: 10, width: 512), 360 * 512 / (256 * 1_024), accuracy: 1e-9)
        for zoom in [0.0, 3.5, 12, 18.25] {
            let delta = FluentMapZoom.longitudeDelta(zoom: zoom, width: 640)
            XCTAssertEqual(FluentMapZoom.zoom(longitudeDelta: delta, width: 640), max(zoom, log2(640.0 / 256)), accuracy: 1e-6)
        }
        XCTAssertEqual(FluentMapZoom.zoom(longitudeDelta: 0, width: 400), 22)
    }

    @MainActor
    func testIconsSyncByIdentityAndClicksReportTheIcon() throws {
        _ = NSApplication.shared
        let center = FluentState(wrappedValue: FluentGeopoint(latitude: 47.6, longitude: -122.3))
        let zoom = FluentState(wrappedValue: 10.0)
        var clicked: [String] = []
        let icons = [FluentMapIcon(id: "a", location: FluentGeopoint(latitude: 47.6, longitude: -122.3), title: "A"),
                     FluentMapIcon(id: "b", location: FluentGeopoint(latitude: 47.7, longitude: -122.2), title: "B")]
        let view = try XCTUnwrap(FluentMapControl(center: center.projectedValue, zoomLevel: zoom.projectedValue, icons: icons,
                                                  onMapElementClick: { clicked.append($0.id) })
            ._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentMapControlView)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(Set(view.annotations.map(\.icon.id)), ["a", "b"])
        let keptA = try XCTUnwrap(view.annotations.first { $0.icon.id == "a" })

        let moved = [icons[0], FluentMapIcon(id: "b", location: FluentGeopoint(latitude: 0, longitude: 0), title: "B")]
        XCTAssertTrue(FluentMapControl(center: center.projectedValue, zoomLevel: zoom.projectedValue, icons: moved)
            ._updateView(view, in: FluentRenderContext(reduceMotion: true)))
        XCTAssertTrue(view.annotations.contains { $0 === keptA }, "Unchanged icons keep their annotation")
        XCTAssertEqual(view.annotations.first { $0.icon.id == "b" }?.coordinate.latitude, 0)

        XCTAssertTrue(FluentMapControl(center: center.projectedValue, zoomLevel: zoom.projectedValue, icons: moved,
                                       onMapElementClick: { clicked.append($0.id) })
            ._updateView(view, in: FluentRenderContext(reduceMotion: true)))
        view.iconClicked(moved[1])
        XCTAssertEqual(clicked, ["b"])
    }

    @MainActor
    func testUserPansWriteBackAndInteractiveControlsToggle() throws {
        _ = NSApplication.shared
        let center = FluentState(wrappedValue: FluentGeopoint(latitude: 0, longitude: 0))
        let zoom = FluentState(wrappedValue: 4.0)
        let view = try XCTUnwrap(FluentMapControl(center: center.projectedValue, zoomLevel: zoom.projectedValue,
                                                  interactiveControlsVisible: false)
            ._makeView(in: FluentRenderContext(reduceMotion: true)) as? FluentMapControlView)
        view.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.mapView.showsZoomControls)
        XCTAssertFalse(view.mapView.showsCompass)
        // Simulate MapKit reporting a user pan and zoom.
        view.mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 10, longitude: 20),
                                                  span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 22.5)), animated: false)
        view.regionDidChange()
        XCTAssertEqual(center.wrappedValue.latitude, view.mapView.region.center.latitude, accuracy: 1e-6)
        XCTAssertEqual(center.wrappedValue.longitude, view.mapView.region.center.longitude, accuracy: 1e-6)
        XCTAssertEqual(zoom.wrappedValue, FluentMapZoom.zoom(longitudeDelta: view.mapView.region.span.longitudeDelta, width: 512),
                       accuracy: 1e-6)
    }
}
