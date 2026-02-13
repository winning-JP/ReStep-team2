import SwiftUI
import MapKit

struct ChocozapMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var isFollowingUser: Bool
    var userLocation: CLLocationCoordinate2D?
    var places: [ChocozapNearbyStore.Place]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(on: uiView, places: places)

        if isFollowingUser, let userLocation {
            let nextRegion = MKCoordinateRegion(center: userLocation, span: region.span)
            context.coordinator.setRegionIfNeeded(on: uiView, region: nextRegion, animated: true)
            return
        }

        if context.coordinator.shouldUpdateRegion(from: region) {
            context.coordinator.setRegionIfNeeded(on: uiView, region: region, animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let parent: ChocozapMapView
        private var isProgrammaticChange = false
        private var isChangingFromUser = false
        private var lastRegion: MKCoordinateRegion?

        init(_ parent: ChocozapMapView) {
            self.parent = parent
        }

        func setRegionIfNeeded(on mapView: MKMapView, region: MKCoordinateRegion, animated: Bool) {
            guard shouldUpdateRegion(from: region) else { return }
            isProgrammaticChange = true
            mapView.setRegion(region, animated: animated)
            DispatchQueue.main.async {
                self.isProgrammaticChange = false
                self.lastRegion = region
            }
        }

        func shouldUpdateRegion(from region: MKCoordinateRegion) -> Bool {
            guard let lastRegion else { return true }
            let centerChanged = abs(lastRegion.center.latitude - region.center.latitude) > 0.00001
                || abs(lastRegion.center.longitude - region.center.longitude) > 0.00001
            let spanChanged = abs(lastRegion.span.latitudeDelta - region.span.latitudeDelta) > 0.00001
                || abs(lastRegion.span.longitudeDelta - region.span.longitudeDelta) > 0.00001
            return centerChanged || spanChanged
        }

        func updateAnnotations(on mapView: MKMapView, places: [ChocozapNearbyStore.Place]) {
            let existing = mapView.annotations.compactMap { $0 as? MKPointAnnotation }
            let existingIds = Set(existing.compactMap { $0.subtitle ?? nil })
            let desiredIds = Set(places.map { $0.id })

            let toRemove = existing.filter { annotation in
                guard let id = annotation.subtitle else { return true }
                return !desiredIds.contains(id)
            }
            mapView.removeAnnotations(toRemove)

            let toAdd = places.filter { !existingIds.contains($0.id) }.map { place -> MKPointAnnotation in
                let annotation = MKPointAnnotation()
                annotation.title = place.name
                annotation.subtitle = place.id
                annotation.coordinate = place.coordinate
                return annotation
            }
            mapView.addAnnotations(toAdd)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard let view = mapView.subviews.first else {
                isChangingFromUser = false
                return
            }
            isChangingFromUser = view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) ?? false
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            lastRegion = mapView.region

            guard !isProgrammaticChange else { return }

            if isChangingFromUser {
                DispatchQueue.main.async {
                    self.parent.isFollowingUser = false
                }
            }

            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }
    }
}
