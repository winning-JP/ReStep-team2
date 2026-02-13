import SwiftUI
import Combine
import CoreLocation
import MapKit

struct ChocozapNearbyView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @StateObject private var store = ChocozapNearbyStore()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var isFollowingUser = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if !locationManager.isEnabled {
                    disabledState
                } else if locationManager.lastLocation == nil {
                    loadingState
                } else {
                    contentState
                }

                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle("近くのchocoZAP")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshIfPossible(force: false)
        }
        .refreshable {
            await refreshIfPossible(force: true)
        }
        .onReceive(locationManager.$lastLocation.compactMap { $0 }) { location in
            if isFollowingUser {
                region = MKCoordinateRegion(center: location.coordinate, span: region.span)
            }
            Task {
                await refreshWithLocation(location, force: false)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("現在地の近くにあるchocoZAPを表示します。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disabledState: some View {
        VStack(spacing: 12) {
            Text("位置情報がオフになっています。")
                .font(.headline)
            Button {
                locationManager.startUpdating()
            } label: {
                Text("位置情報をオンにする")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("位置情報を取得中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var contentState: some View {
        VStack(spacing: 12) {
            mapSection

            if store.state == .loading {
                ProgressView()
            }

            if case let .failed(message) = store.state {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.places.isEmpty, store.state == .loaded {
                Text("近くの店舗が見つかりませんでした。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(store.places) { place in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(place.name)
                            .font(.headline)
                        Spacer()
                        Text(place.distanceText)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    Text(place.address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let access = place.access, !access.isEmpty {
                        Text(access)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture {
                    isFollowingUser = false
                    region = MKCoordinateRegion(center: place.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                }
            }
        }
    }

    private func refreshIfPossible(force: Bool) async {
        await Task.yield()
        guard let location = locationManager.lastLocation else { return }
        await refreshWithLocation(location, force: force)
    }

    private var mapSection: some View {
        ChocozapMapView(
            region: $region,
            isFollowingUser: $isFollowingUser,
            userLocation: locationManager.lastLocation?.coordinate,
            places: store.places
        )
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottomTrailing) {
            if !isFollowingUser, let location = locationManager.lastLocation {
                Button {
                    isFollowingUser = true
                    region = MKCoordinateRegion(center: location.coordinate, span: region.span)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.caption.weight(.semibold))
                        Text("現在地")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                }
                .padding(12)
            }
        }
    }

    private func refreshWithLocation(_ location: CLLocation, force: Bool) async {
        store.updateDistances(currentLocation: location)
        await store.refresh(currentLocation: location, force: force)
    }
}

@MainActor
final class ChocozapNearbyStore: ObservableObject {
    struct Place: Identifiable {
        let id: String
        let name: String
        let address: String
        let access: String?
        let distanceMeters: CLLocationDistance
        let coordinate: CLLocationCoordinate2D

        var distanceText: String {
            if distanceMeters < 1000 {
                return "\(Int(distanceMeters))m"
            }
            return String(format: "%.1fkm", distanceMeters / 1000)
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var places: [Place] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var lastUpdatedAt: Date?

    private let maxGeocodeCount = 30
    private let maxGeocodeCountUnfiltered = 80
    private let maxDisplayCount = 20
    private let maxDistanceMeters: CLLocationDistance = 12000
    private let minRefreshInterval: TimeInterval = 120
    private let minRefreshDistance: CLLocationDistance = 500

    private var entries: [ChocozapNearbyEntry] = []
    private var cache: [String: CachedCoordinate] = [:]
    private var lastRefreshAt: Date?
    private var lastRefreshLocation: CLLocation?

    init() {
        entries = Self.loadEntries()
        cache = Self.loadCache()
    }

    func refresh(currentLocation: CLLocation, force: Bool) async {
        if state == .loading { return }
        let movedFarEnough = lastRefreshLocation.map { currentLocation.distance(from: $0) >= minRefreshDistance } ?? true
        if let lastRefreshAt, !force, !movedFarEnough, Date().timeIntervalSince(lastRefreshAt) < minRefreshInterval {
            return
        }

        state = .loading
        lastRefreshAt = Date()
        lastRefreshLocation = currentLocation
        let previousPlaces = places

        guard !entries.isEmpty else {
            state = .failed("店舗データを読み込めませんでした。")
            return
        }

        do {
            let candidates = try await selectCandidates(using: currentLocation)
            let isUnfiltered = candidates.count == entries.count
            let maxCount = (isUnfiltered && cache.isEmpty) ? maxGeocodeCountUnfiltered : maxGeocodeCount
            let limited = Array(candidates.prefix(maxCount))
            var results: [Place] = []

            for entry in limited {
                if Task.isCancelled { break }
                guard let coordinate = await geocodeCoordinate(for: entry) else { continue }
                let distance = currentLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                if distance <= maxDistanceMeters {
                    results.append(Place(
                        id: entry.id,
                        name: entry.name,
                        address: entry.address,
                        access: entry.access,
                        distanceMeters: distance,
                        coordinate: coordinate
                    ))
                    if results.count >= maxDisplayCount { break }
                }
            }

            results.sort { $0.distanceMeters < $1.distanceMeters }
            if results.isEmpty, !previousPlaces.isEmpty {
                places = previousPlaces
                state = .loaded
            } else {
                places = Array(results.prefix(maxDisplayCount))
                state = .loaded
                lastUpdatedAt = Date()
            }
        } catch {
            state = .failed("位置情報の取得に失敗しました。")
        }
    }

    func updateDistances(currentLocation: CLLocation) {
        guard !places.isEmpty else { return }
        let updated = places.map { place -> Place in
            let distance = currentLocation.distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
            return Place(
                id: place.id,
                name: place.name,
                address: place.address,
                access: place.access,
                distanceMeters: distance,
                coordinate: place.coordinate
            )
        }
        places = updated.sorted { $0.distanceMeters < $1.distanceMeters }
        lastUpdatedAt = Date()
    }

    private func selectCandidates(using location: CLLocation) async throws -> [ChocozapNearbyEntry] {
        if #available(iOS 26.0, *) {
            let addressText = try await reverseGeocodeAddressText(using: location)
            return selectCandidates(usingAddressText: addressText, currentLocation: location)
        } else {
            return try await selectCandidatesLegacy(using: location)
        }
    }

    private func selectCandidates(usingAddressText addressText: String?, currentLocation: CLLocation) -> [ChocozapNearbyEntry] {
        guard let addressText, !addressText.isEmpty else { return fallbackCandidates(using: currentLocation) }

        let cleaned = normalizedAddressText(addressText)
        let keywords = extractAreaKeywords(from: cleaned)
        var scored: [(entry: ChocozapNearbyEntry, score: Int)] = []

        for entry in entries {
            var score = 0
            for (index, keyword) in keywords.enumerated() where !keyword.isEmpty {
                if entry.address.contains(keyword) {
                    score = max(score, keywords.count - index)
                }
            }

            if score > 0 {
                scored.append((entry, score))
            }
        }

        if scored.isEmpty {
            return fallbackCandidates(using: currentLocation)
        }

        return scored.sorted { $0.score > $1.score }.map { $0.entry }
    }

    private func geocodeCoordinate(for entry: ChocozapNearbyEntry) async -> CLLocationCoordinate2D? {
        if let cached = cache[entry.cacheKey] {
            return CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
        }

        if #available(iOS 26.0, *) {
            return await geocodeCoordinateMapKit(for: entry)
        } else {
            return await geocodeCoordinateLegacy(for: entry)
        }
    }

    private static func loadEntries() -> [ChocozapNearbyEntry] {
        guard let url = Bundle.main.url(forResource: "chocozap_addresses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ChocozapNearbyEntry.Raw].self, from: data) else {
            return []
        }

        return decoded.map { ChocozapNearbyEntry(raw: $0) }
    }

    private static let cacheKey = "restep.chocozap.geocode.cache"

    private static func loadCache() -> [String: CachedCoordinate] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: CachedCoordinate].self, from: data)) ?? [:]
    }

    private static func saveCache(_ cache: [String: CachedCoordinate]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    @available(iOS 26.0, *)
    private func reverseGeocodeAddressText(using location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try await request.mapItems
        guard let item = mapItems.first else { return nil }
        if let address = item.address?.fullAddress, !address.isEmpty {
            return address
        }
        if let address = item.address?.shortAddress, !address.isEmpty {
            return address
        }
        return item.name
    }

    private func selectCandidatesLegacy(using location: CLLocation) async throws -> [ChocozapNearbyEntry] {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        let placemark = placemarks.first
        return selectCandidates(using: placemark, currentLocation: location)
    }

    private func selectCandidates(using placemark: CLPlacemark?, currentLocation: CLLocation) -> [ChocozapNearbyEntry] {
        guard let placemark else { return fallbackCandidates(using: currentLocation) }

        let admin = placemark.administrativeArea ?? ""
        let locality = placemark.locality ?? ""
        let subLocality = placemark.subLocality ?? ""

        let full = admin + locality + subLocality
        let mid = admin + locality
        let city = locality

        _ = [full, mid, city].filter { !$0.isEmpty }
        var scored: [(entry: ChocozapNearbyEntry, score: Int)] = []

        for entry in entries {
            var score = 0
            if !full.isEmpty, entry.address.contains(full) { score = 3 }
            else if !mid.isEmpty, entry.address.contains(mid) { score = 2 }
            else if !city.isEmpty, entry.address.contains(city) { score = 1 }

            if score > 0 {
                scored.append((entry, score))
            }
        }

        if scored.isEmpty {
            return fallbackCandidates(using: currentLocation)
        }

        return scored.sorted { $0.score > $1.score }.map { $0.entry }
    }

    @available(iOS 26.0, *)
    private func geocodeCoordinateMapKit(for entry: ChocozapNearbyEntry) async -> CLLocationCoordinate2D? {
        do {
            let request = MKGeocodingRequest(addressString: entry.geocodeAddress)
            let mapItems = try await request?.mapItems
            guard let coordinate = mapItems?.first?.location.coordinate else { return nil }
            cache[entry.cacheKey] = CachedCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            Self.saveCache(cache)
            return coordinate
        } catch {
            return nil
        }
    }

    private func geocodeCoordinateLegacy(for entry: ChocozapNearbyEntry) async -> CLLocationCoordinate2D? {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(entry.geocodeAddress)
            guard let coordinate = placemarks.first?.location?.coordinate else { return nil }
            cache[entry.cacheKey] = CachedCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            Self.saveCache(cache)
            return coordinate
        } catch {
            return nil
        }
    }

    private func normalizedAddressText(_ address: String) -> String {
        var text = address
        text = text.replacingOccurrences(of: "日本", with: "")
        text = text.replacingOccurrences(of: "Japan", with: "")
        text = text.replacingOccurrences(of: "〒\\d{3}-?\\d{4}", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "、", with: "")
        text = text.replacingOccurrences(of: ",", with: "")
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "　", with: "")
        return text
    }

    private func extractAreaKeywords(from address: String) -> [String] {
        guard let prefectureRange = address.range(of: "[都道府県]", options: .regularExpression) else {
            return [address]
        }

        let prefecture = String(address[..<prefectureRange.upperBound])
        let rest = address[prefectureRange.upperBound...]

        if let cityRange = rest.range(of: "[市区町村]", options: .regularExpression) {
            let city = String(rest[..<cityRange.upperBound])
            return [prefecture + city, prefecture, city]
        }

        return [prefecture, address]
    }

    private func fallbackCandidates(using location: CLLocation) -> [ChocozapNearbyEntry] {
        if cache.isEmpty { return entries }

        let scored = entries.compactMap { entry -> (ChocozapNearbyEntry, CLLocationDistance)? in
            guard let cached = cache[entry.cacheKey] else { return nil }
            let distance = location.distance(from: CLLocation(latitude: cached.latitude, longitude: cached.longitude))
            return (entry, distance)
        }

        if scored.isEmpty { return entries }

        return scored.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}

private struct CachedCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

private struct ChocozapNearbyEntry {
    struct Raw: Decodable {
        let name: String
        let address: String
        let access: String?
    }

    let id: String
    let name: String
    let address: String
    let access: String?
    let geocodeAddress: String
    let cacheKey: String

    init(raw: Raw) {
        name = raw.name
        address = raw.address
        access = raw.access
        geocodeAddress = Self.baseAddress(from: raw.address)
        cacheKey = geocodeAddress
        id = "\(raw.name)-\(raw.address)"
    }

    private static func baseAddress(from address: String) -> String {
        if let range = address.range(of: " ") ?? address.range(of: "　") {
            return String(address[..<range.lowerBound])
        }
        return address
    }
}
