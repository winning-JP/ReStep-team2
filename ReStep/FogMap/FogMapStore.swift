import SwiftUI
import Combine
import CoreLocation

struct VisitPoint: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let visitedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Waypoint: Codable, Identifiable {
    let id: UUID
    var latitude: Double
    var longitude: Double
    var title: String
    var note: String
    var photoFileName: String?  // ローカル保存用（レガシー）
    var photoUrl: String?       // S3 URL
    var createdAt: Date
    var serverId: Int?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class FogMapStore: ObservableObject {
    static let shared = FogMapStore()

    @Published var visitPoints: [VisitPoint] = []
    @Published var waypoints: [Waypoint] = []
    @Published var isSyncing = false

    private let minDistance: CLLocationDistance = 50 // 50m以上離れたら新しい地点を記録
    private let fogMapAPI = FogMapAPIClient.shared

    init() {
        clearLegacyLocalCache()
    }

    func recordVisit(at location: CLLocation) {
        let coord = location.coordinate

        // 既存の訪問地点から50m以内なら記録しない
        let isDuplicate = visitPoints.contains { point in
            let existing = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return location.distance(from: existing) < minDistance
        }

        guard !isDuplicate else { return }

        let visit = VisitPoint(
            id: UUID(),
            latitude: coord.latitude,
            longitude: coord.longitude,
            visitedAt: Date()
        )

        Task {
            do {
                try await syncVisits([visit])
                visitPoints.append(visit)
            } catch {
                DebugLog.log("FogMapStore.recordVisit error: \(error.localizedDescription)")
            }
        }
    }

    /// 指定座標が訪問済みエリア（200m以内）かチェック
    func isVisited(coordinate: CLLocationCoordinate2D) -> Bool {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return visitPoints.contains { point in
            let existing = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return target.distance(from: existing) <= 200
        }
    }

    func addWaypoint(coordinate: CLLocationCoordinate2D, title: String, note: String, photoData: Data? = nil) {
        Task {
            do {
                // 写真がある場合はまずアップロード
                var uploadedUrl: String?
                if let photoData {
                    let uploadResponse = try await fogMapAPI.uploadImage(imageData: photoData, category: "waypoint")
                    uploadedUrl = uploadResponse.url
                }

                _ = try await fogMapAPI.addWaypoint(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    title: title,
                    note: note,
                    photoUrl: uploadedUrl
                )
                await loadFromServer()
            } catch {
                DebugLog.log("FogMapStore.addWaypoint sync error: \(error.localizedDescription)")
            }
        }
    }

    func updateWaypoint(id: UUID, title: String, note: String, photoData: Data? = nil, removePhoto: Bool = false) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        let serverId = waypoints[index].serverId
        let currentPhotoUrl = waypoints[index].photoUrl
        guard let serverId else { return }

        Task {
            do {
                var newPhotoUrl: String? = currentPhotoUrl

                if removePhoto {
                    newPhotoUrl = nil
                } else if let photoData {
                    let uploadResponse = try await fogMapAPI.uploadImage(imageData: photoData, category: "waypoint")
                    newPhotoUrl = uploadResponse.url
                }

                _ = try await fogMapAPI.updateWaypoint(
                    waypointId: serverId,
                    title: title,
                    note: note,
                    photoUrl: newPhotoUrl
                )
                await loadFromServer()
            } catch {
                DebugLog.log("FogMapStore.updateWaypoint error: \(error.localizedDescription)")
            }
        }
    }

    func removeWaypoint(_ waypoint: Waypoint) {
        if let serverId = waypoint.serverId {
            Task {
                do {
                    _ = try await fogMapAPI.deleteWaypoint(waypointId: serverId)
                    await loadFromServer()
                } catch {
                    DebugLog.log("FogMapStore.removeWaypoint error: \(error.localizedDescription)")
                }
            }
        }
    }

    func syncToServer() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await loadFromServer()
    }

    func loadFromServer() async {
        do {
            let response = try await fogMapAPI.fetchVisits(limit: 5000)
            let serverVisits = response.items.map { item in
                VisitPoint(
                    id: UUID(),
                    latitude: item.latitude,
                    longitude: item.longitude,
                    visitedAt: Self.parseDate(item.visitedAt)
                )
            }

            visitPoints = serverVisits

            // ウェイポイントも同期
            let wpResponse = try await fogMapAPI.fetchWaypoints()
            waypoints = wpResponse.items.map { item in
                Waypoint(
                    id: UUID(),
                    latitude: item.latitude,
                    longitude: item.longitude,
                    title: item.title ?? "",
                    note: item.note ?? "",
                    photoFileName: nil,
                    photoUrl: item.photoUrl,
                    createdAt: Self.parseDate(item.createdAt),
                    serverId: item.id
                )
            }
        } catch {
            DebugLog.log("FogMapStore.loadFromServer error: \(error.localizedDescription)")
        }
    }

    private func syncVisits(_ visits: [VisitPoint]) async throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let payload = visits.map { v in
            (latitude: v.latitude, longitude: v.longitude, visitedAt: formatter.string(from: v.visitedAt))
        }
        _ = try await fogMapAPI.syncVisits(payload)
    }

    private func clearLegacyLocalCache() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs else { return }
        let paths = ["fogmap_visits.json", "fogmap_waypoints.json"]
        for path in paths {
            let url = docs.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func parseDate(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string) ?? Date()
    }
}
