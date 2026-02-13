import Foundation
import Combine
import CoreLocation
import MapKit

final class ChocozapStampManager: ObservableObject {
    @Published private(set) var lastAwardedLocationName: String?
    @Published private(set) var lastAwardedAt: Date?

    private let stampsStore: StampsStore
    private let locationManager: LocationManager
    private let notificationManager: NotificationManager?
    private let addressIndex: ChocozapAddressIndex
    private var visitCache: [String: String]
    private var cancellables: Set<AnyCancellable> = []

    private var lastGeocodeLocation: CLLocation?
    private var lastGeocodeAt: Date?
    private var isGeocoding = false

    private let minGeocodeInterval: TimeInterval = 300
    private let minGeocodeDistance: CLLocationDistance = 75

    init(stampsStore: StampsStore, locationManager: LocationManager, notificationManager: NotificationManager? = nil) {
        self.stampsStore = stampsStore
        self.locationManager = locationManager
        self.notificationManager = notificationManager
        self.addressIndex = ChocozapAddressIndex.loadFromBundle()
        self.visitCache = Self.loadVisitCache()
        bindLocationUpdates()
    }

    private func bindLocationUpdates() {
        locationManager.$lastLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handle(location)
            }
            .store(in: &cancellables)
    }

    private func handle(_ location: CLLocation) {
        guard addressIndex.hasEntries else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }

        if let lastLocation = lastGeocodeLocation, let lastAt = lastGeocodeAt {
            let recent = Date().timeIntervalSince(lastAt) < minGeocodeInterval
            let nearby = location.distance(from: lastLocation) < minGeocodeDistance
            if recent && nearby { return }
        }

        lastGeocodeLocation = location
        lastGeocodeAt = Date()

        guard !isGeocoding else { return }
        isGeocoding = true
        reverseGeocodeAddressKey(for: location) { [weak self] addressKey in
            guard let self = self else { return }
            self.isGeocoding = false
            guard let addressKey, !addressKey.isEmpty else { return }

            guard let match = self.addressIndex.match(for: addressKey) else { return }
            self.awardStampIfNeeded(locationKey: match.key, locationName: match.name)
        }
    }

    private func reverseGeocodeAddressKey(for location: CLLocation, completion: @escaping (String?) -> Void) {
        if #available(iOS 26.0, *) {
            Task {
                let key = await reverseGeocodeAddressKeyMapKit(for: location)
                await MainActor.run {
                    completion(key)
                }
            }
        } else {
            reverseGeocodeAddressKeyLegacy(for: location, completion: completion)
        }
    }

    @available(iOS 26.0, *)
    private func reverseGeocodeAddressKeyMapKit(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            guard let item = mapItems.first else { return nil }
            let addressText = item.address?.fullAddress ?? item.address?.shortAddress ?? item.name ?? ""
            return ChocozapAddressIndex.addressKey(from: addressText)
        } catch {
            return nil
        }
    }

    private func reverseGeocodeAddressKeyLegacy(for location: CLLocation, completion: @escaping (String?) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                guard error == nil, let placemark = placemarks?.first else {
                    completion(nil)
                    return
                }
                let addressKey = ChocozapAddressIndex.addressKey(from: placemark)
                completion(addressKey.isEmpty ? nil : addressKey)
            }
        }
    }

    private func awardStampIfNeeded(locationKey: String, locationName: String) {
        let todayKey = Self.todayKey()
        if visitCache[locationKey] == todayKey { return }

        visitCache[locationKey] = todayKey
        Self.saveVisitCache(visitCache)

        stampsStore.addBonusStamp(reason: "chocozap_bonus")
        lastAwardedLocationName = locationName
        lastAwardedAt = Date()
        notificationManager?.notifyStampEarned(locationName: locationName)
    }

    private static let visitCacheKey = "restep.chocozap.visitCache"

    private static func loadVisitCache() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: visitCacheKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveVisitCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: visitCacheKey)
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct ChocozapAddressEntry: Decodable {
    let name: String
    let address: String
}

private struct ChocozapAddressMatch {
    let key: String
    let name: String
}

private struct ChocozapAddressIndex {
    let entries: [ChocozapAddressMatch]
    let lookup: [String: String]

    var hasEntries: Bool {
        !entries.isEmpty
    }

    func match(for candidateKey: String) -> ChocozapAddressMatch? {
        if let exact = lookup[candidateKey] {
            return ChocozapAddressMatch(key: candidateKey, name: exact)
        }

        if let entry = entries.first(where: { candidateKey.hasPrefix($0.key) || $0.key.hasPrefix(candidateKey) }) {
            return entry
        }

        return nil
    }

    static func loadFromBundle() -> ChocozapAddressIndex {
        guard let url = Bundle.main.url(forResource: "chocozap_addresses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ChocozapAddressEntry].self, from: data) else {
            return ChocozapAddressIndex(entries: [], lookup: [:])
        }

        let entries = decoded.compactMap { entry -> ChocozapAddressMatch? in
            let key = normalizedAddressKey(entry.address)
            guard !key.isEmpty else { return nil }
            return ChocozapAddressMatch(key: key, name: entry.name)
        }

        var lookup: [String: String] = [:]
        for entry in entries {
            if lookup[entry.key] == nil {
                lookup[entry.key] = entry.name
            }
        }

        return ChocozapAddressIndex(entries: entries, lookup: lookup)
    }

    static func addressKey(from placemark: CLPlacemark) -> String {
        let parts: [String] = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ].compactMap { $0 }

        let joined = parts.joined()
        if !joined.isEmpty {
            return normalizedAddressKey(joined)
        }

        if let name = placemark.name {
            return normalizedAddressKey(name)
        }

        return ""
    }

    static func addressKey(from addressText: String) -> String {
        let cleaned = cleanedAddressText(addressText)
        return normalizedAddressKey(cleaned)
    }

    static func normalizedAddressKey(_ address: String) -> String {
        let trimmed = baseAddress(from: address)
        let normalizedChome = replacingKanjiChome(in: trimmed)
        let folded = normalizedChome.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
        let withoutChome = folded.replacingOccurrences(of: "丁目", with: "")
        let withoutUnits = withoutChome
            .replacingOccurrences(of: "番地", with: "")
            .replacingOccurrences(of: "番", with: "")
            .replacingOccurrences(of: "号", with: "")
        let collapsed = withoutUnits
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "ー", with: "-")
        let withoutHyphens = collapsed.replacingOccurrences(of: "-", with: "")
        let withoutSpaces = withoutHyphens.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return withoutSpaces
    }

    private static func baseAddress(from address: String) -> String {
        if let range = address.range(of: " ") ?? address.range(of: "　") {
            return String(address[..<range.lowerBound])
        }
        return address
    }

    private static func cleanedAddressText(_ address: String) -> String {
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

    private static func replacingKanjiChome(in address: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "([一二三四五六七八九十]+)丁目") else { return address }
        let matches = regex.matches(in: address, range: NSRange(address.startIndex..., in: address))
        if matches.isEmpty { return address }

        var output = address
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let kanjiRange = Range(match.range(at: 1), in: output),
                  let fullRange = Range(match.range(at: 0), in: output) else { continue }
            let kanji = String(output[kanjiRange])
            guard let number = kanjiNumberToInt(kanji) else { continue }
            output.replaceSubrange(fullRange, with: "\(number)丁目")
        }

        return output
    }

    private static func kanjiNumberToInt(_ value: String) -> Int? {
        let map: [Character: Int] = [
            "一": 1,
            "二": 2,
            "三": 3,
            "四": 4,
            "五": 5,
            "六": 6,
            "七": 7,
            "八": 8,
            "九": 9
        ]

        var result = 0
        var temp = 0

        for char in value {
            if char == "十" {
                let base = temp == 0 ? 1 : temp
                result += base * 10
                temp = 0
                continue
            }

            guard let digit = map[char] else { return nil }
            temp += digit
        }

        result += temp
        return result == 0 ? nil : result
    }
}
