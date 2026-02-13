import Foundation

final class EncounterStampTracker {
    static let shared = EncounterStampTracker()

    static let didAwardStampsNotification = Notification.Name("restep.encounter.stamps.awarded")

    private let storageKey = "restep.encounter.dailyState"
    private let thresholds: [Int] = [3, 6, 10]

    private init() {}

    func todayProgress(date: Date = Date()) -> EncounterStampProgress {
        let state = loadState(for: date)
        return EncounterStampProgress(
            count: state.count,
            awardedCount: state.awardedCount,
            thresholds: thresholds
        )
    }

    func registerEncounter(travelerId: UUID, date: Date = Date()) {
        var state = loadState(for: date)
        let idString = travelerId.uuidString

        if state.travelerIds.contains(idString) {
            return
        }

        state.travelerIds.insert(idString)
        state.count += 1

        let reached = thresholds.filter { state.count >= $0 }.count
        if reached > state.awardedCount {
            let newlyAwarded = reached - state.awardedCount
            state.awardedCount = reached
            NotificationCenter.default.post(
                name: Self.didAwardStampsNotification,
                object: nil,
                userInfo: ["count": newlyAwarded]
            )
        }

        saveState(state)
    }

    private func loadState(for date: Date) -> DailyEncounterState {
        let todayKey = Self.todayKey(from: date)
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(DailyEncounterState.self, from: data) else {
            return DailyEncounterState(dateKey: todayKey)
        }

        if decoded.dateKey != todayKey {
            return DailyEncounterState(dateKey: todayKey)
        }
        return decoded
    }

    private func saveState(_ state: DailyEncounterState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func todayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

struct EncounterStampProgress: Equatable {
    let count: Int
    let awardedCount: Int
    let thresholds: [Int]

    var nextThreshold: Int? {
        thresholds.first { $0 > count }
    }

    var remainingToNext: Int? {
        guard let next = nextThreshold else { return nil }
        return max(0, next - count)
    }
}

private struct DailyEncounterState: Codable {
    let dateKey: String
    var travelerIds: Set<String>
    var count: Int
    var awardedCount: Int

    init(dateKey: String) {
        self.dateKey = dateKey
        self.travelerIds = []
        self.count = 0
        self.awardedCount = 0
    }
}
