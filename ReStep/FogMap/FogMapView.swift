import SwiftUI
import MapKit

struct FogMapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @StateObject private var store = FogMapStore.shared
    @State private var showAddWaypoint = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var trackingUser = true
    @State private var showNotVisitedAlert = false
    @State private var selectedWaypointServerId: Int?
    @State private var selectedWaypointFallback: Waypoint?
    @State private var showWaypointDetail = false
    @State private var showWaypointEdit = false
    @State private var showWaypointList = false

    private var selectedWaypoint: Waypoint? {
        if let serverId = selectedWaypointServerId,
           let latest = store.waypoints.first(where: { $0.serverId == serverId }) {
            return latest
        }
        return selectedWaypointFallback
    }

    var body: some View {
        ZStack {
            FogMapRepresentable(
                visitPoints: store.visitPoints,
                waypoints: store.waypoints,
                trackingUser: $trackingUser,
                onLongPress: { coordinate in
                    if store.isVisited(coordinate: coordinate) {
                        selectedCoordinate = coordinate
                        showAddWaypoint = true
                    } else {
                        showNotVisitedAlert = true
                    }
                },
                onWaypointTap: { waypoint in
                    openWaypointDetail(waypoint)
                }
            )
            .ignoresSafeArea(edges: .bottom)

            // フローティングボタン
            VStack {
                Spacer()
                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        // 現在地追従ボタン
                        Button {
                            trackingUser = true
                        } label: {
                            Image(systemName: trackingUser ? "location.fill" : "location")
                                .font(.title3)
                                .foregroundStyle(trackingUser ? .blue : .primary)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }

                        Button {
                            showWaypointList = true
                            Task { await store.loadFromServer() }
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }

            // 統計オーバーレイ
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("訪問: \(store.visitPoints.count)地点")
                            .font(.caption.bold())
                        Text("WP: \(store.waypoints.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationTitle("地図埋め")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.refreshIfEnabled()
            Task { await store.loadFromServer() }
        }
        .onReceive(locationManager.$lastLocation) { location in
            guard let location else { return }
            store.recordVisit(at: location)
        }
        .sheet(isPresented: $showAddWaypoint) {
            if let coord = selectedCoordinate {
                WaypointDetailView(coordinate: coord) { title, note, photoData in
                    store.addWaypoint(coordinate: coord, title: title, note: note, photoData: photoData)
                }
            }
        }
        .sheet(isPresented: $showWaypointDetail) {
            if let wp = selectedWaypoint {
                WaypointInfoView(
                    waypoint: wp,
                    onDelete: {
                        store.removeWaypoint(wp)
                        showWaypointDetail = false
                    },
                    onEdit: {
                        showWaypointDetail = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showWaypointEdit = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showWaypointEdit) {
            if let wp = selectedWaypoint {
                WaypointEditView(waypoint: wp) { title, note, newPhotoData, removePhoto in
                    store.updateWaypoint(id: wp.id, title: title, note: note, photoData: newPhotoData, removePhoto: removePhoto)
                }
            }
        }
        .sheet(isPresented: $showWaypointList) {
            WaypointListSheet(
                waypoints: store.waypoints,
                isSyncing: store.isSyncing,
                onSync: {
                    Task { await store.syncToServer() }
                }
            ) { waypoint in
                showWaypointList = false
                openWaypointDetail(waypoint)
            }
        }
        .alert("ウェイポイントを追加できません", isPresented: $showNotVisitedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("まだ訪問していない場所にはウェイポイントを追加できません。実際にその場所を訪れてから追加してください。")
        }
    }

    private func openWaypointDetail(_ waypoint: Waypoint) {
        selectedWaypointServerId = waypoint.serverId
        selectedWaypointFallback = waypoint
        Task {
            await store.loadFromServer()
            showWaypointDetail = true
        }
    }
}

// MARK: - UIKit Map Wrapper with Fog Overlay

struct FogMapRepresentable: UIViewRepresentable {
    let visitPoints: [VisitPoint]
    let waypoints: [Waypoint]
    @Binding var trackingUser: Bool
    let onLongPress: (CLLocationCoordinate2D) -> Void
    let onWaypointTap: (Waypoint) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false
        mapView.userTrackingMode = .follow

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // trackingUser の状態に応じてトラッキングモードを切り替え
        if trackingUser && mapView.userTrackingMode == .none {
            mapView.setUserTrackingMode(.follow, animated: true)
        }

        // フォグオーバーレイの更新（訪問地点数が変わった時のみ）
        if visitPoints.count != context.coordinator.lastVisitCount {
            context.coordinator.lastVisitCount = visitPoints.count

            let fogOverlays = mapView.overlays.filter { $0 is FogOverlay }
            mapView.removeOverlays(fogOverlays)

            let fogOverlay = FogOverlay(visitPoints: visitPoints)
            mapView.addOverlay(fogOverlay, level: .aboveLabels)
        }

        // ウェイポイントアノテーションの更新（変更があった時のみ）
        let currentWaypointIDs = Set(waypoints.map(\.id))
        if currentWaypointIDs != context.coordinator.lastWaypointIDs {
            context.coordinator.lastWaypointIDs = currentWaypointIDs

            let existingAnnotations = mapView.annotations.filter { $0 is WaypointAnnotation }
            mapView.removeAnnotations(existingAnnotations)

            for wp in waypoints {
                let annotation = WaypointAnnotation(waypoint: wp)
                mapView.addAnnotation(annotation)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FogMapRepresentable
        var lastVisitCount: Int = 0
        var lastWaypointIDs: Set<UUID> = []

        init(parent: FogMapRepresentable) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onLongPress(coordinate)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let fogOverlay = overlay as? FogOverlay {
                return FogOverlayRenderer(overlay: fogOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let wpAnnotation = annotation as? WaypointAnnotation else { return nil }
            let identifier = "WaypointPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: wpAnnotation, reuseIdentifier: identifier)
            view.annotation = wpAnnotation
            view.markerTintColor = .purple
            view.glyphImage = UIImage(systemName: "mappin.circle.fill")
            view.canShowCallout = true

            let infoButton = UIButton(type: .detailDisclosure)
            view.rightCalloutAccessoryView = infoButton
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let wpAnnotation = view.annotation as? WaypointAnnotation else { return }
            parent.onWaypointTap(wpAnnotation.waypoint)
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            // ユーザーがパン/ズームするとMKMapViewが自動的にトラッキングを解除する
            // その変化を検知してSwiftUI側のstateに反映
            DispatchQueue.main.async {
                self.parent.trackingUser = (mode != .none)
            }
        }
    }
}

// MARK: - Fog Overlay

class FogOverlay: NSObject, MKOverlay {
    let visitPoints: [VisitPoint]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(visitPoints: [VisitPoint]) {
        self.visitPoints = visitPoints
        self.coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        self.boundingMapRect = MKMapRect.world
        super.init()
    }
}

class FogOverlayRenderer: MKOverlayRenderer {
    private let clearRadius: CLLocationDistance = 200 // 200m半径

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let fogOverlay = overlay as? FogOverlay else { return }

        let rect = self.rect(for: overlay.boundingMapRect)

        // 霧で塗りつぶし
        context.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        context.fill(rect)

        // 訪問済み地点を透明に切り抜く
        context.setBlendMode(.clear)

        for point in fogOverlay.visitPoints {
            let center = MKMapPoint(point.coordinate)
            let radiusInMapPoints = clearRadius * MKMapPointsPerMeterAtLatitude(point.latitude)

            let circleRect = MKMapRect(
                x: center.x - radiusInMapPoints,
                y: center.y - radiusInMapPoints,
                width: radiusInMapPoints * 2,
                height: radiusInMapPoints * 2
            )

            let drawRect = self.rect(for: circleRect)
            context.fillEllipse(in: drawRect)
        }
    }
}

// MARK: - Waypoint Annotation

class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: Waypoint
    var coordinate: CLLocationCoordinate2D { waypoint.coordinate }
    var title: String? { waypoint.title }
    var subtitle: String? { waypoint.note.isEmpty ? nil : waypoint.note }

    init(waypoint: Waypoint) {
        self.waypoint = waypoint
        super.init()
    }
}

struct WaypointListSheet: View {
    let waypoints: [Waypoint]
    let isSyncing: Bool
    let onSync: () -> Void
    let onSelect: (Waypoint) -> Void
    @Environment(\.dismiss) private var dismiss

    private var sortedWaypoints: [Waypoint] {
        waypoints.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List(sortedWaypoints) { waypoint in
                Button {
                    onSelect(waypoint)
                } label: {
                    WaypointListRowView(waypoint: waypoint)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.systemBackground))
            }
            .scrollContentBackground(.hidden)
            .background(Color(.secondarySystemBackground))
            .navigationTitle("保存済みウェイポイント")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSync()
                    } label: {
                        Image(systemName: isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                    }
                    .disabled(isSyncing)
                    .accessibilityLabel("同期")
                }
            }
        }
    }

}

private struct WaypointListRowView: View {
    let waypoint: Waypoint
    @State private var placeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(waypoint.title.isEmpty ? "ウェイポイント" : waypoint.title)
                .font(.headline)
                .foregroundStyle(Color.primary)
            Text(String(format: "%.6f, %.6f", waypoint.latitude, waypoint.longitude))
                .font(.caption)
                .foregroundStyle(Color.secondary)
            if let placeName, !placeName.isEmpty {
                Text(placeName)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            Text(formatDate(waypoint.createdAt))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 4)
        .task(id: waypoint.id) {
            placeName = await PlaceNameResolver.shared.resolveName(latitude: waypoint.latitude, longitude: waypoint.longitude)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
