import Foundation
import Combine

@MainActor
final class StatsSyncManager: ObservableObject {
    static let shared = StatsSyncManager()

    enum BackfillMode {
        case none
        case missing
        case full
    }

    @Published var continuityDays: Int = 0
    @Published var continuityLongestDays: Int = 0
    @Published var continuityLastActiveDate: String?

    private var timer: Timer?
    private var lastPayloadHash: Int?
    private var lastSentAt: Date?
    private let minInterval: TimeInterval = 60
    private let lastSyncedDateKey = "restep.stats.lastSyncedDate"
    private let lastOpenDateKey = "restep.stats.lastOpenDate"
    private let lastContinuityRecordKey = "restep.continuity.lastRecordDate"
    private let continuitySeededKey = "restep.continuity.seeded"
    private let loginBonusStreakKey = "restep.loginBonus.streak"
    private let loginBonusLastClaimKey = "restep.loginBonus.lastClaimDate"

    private let healthManager = HealthKitManager.shared
    private let apiClient = UserAPIClient.shared

    func startPeriodic(interval: TimeInterval = 15 * 60) {
        stopPeriodic()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncIfNeeded(reason: "timer")
            }
        }
    }

    func stopPeriodic() {
        timer?.invalidate()
        timer = nil
    }

    func recordContinuityIfNeeded(isLoggedIn: Bool = true) async {
        guard isLoggedIn else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        let today = formatter.string(from: Date())

        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastContinuityRecordKey) == today {
            return
        }

        do {
            let response = try await apiClient.recordContinuity(date: today)
            applyContinuity(response)
            defaults.set(today, forKey: lastContinuityRecordKey)
        } catch {
            // ignore continuity errors to avoid user-facing errors
        }
    }

    func seedContinuityFromLocalIfNeeded(isLoggedIn: Bool = true) async {
        guard isLoggedIn else { return }
        let defaults = UserDefaults.standard
        let streak = defaults.integer(forKey: loginBonusStreakKey)
        let lastClaimRaw = defaults.string(forKey: loginBonusLastClaimKey)
        let lastActiveDate = convertLoginBonusDateToAPIFormat(lastClaimRaw)

        var remote: ContinuityResponse?
        do {
            let response = try await apiClient.fetchContinuity()
            applyContinuity(response)
            remote = response
        } catch {
            // ignore fetch errors; will try seeding if local data exists
        }

        if streak <= 0 {
            return
        }

        if let remote, remote.currentStreak >= streak {
            defaults.set(true, forKey: continuitySeededKey)
            return
        }

        do {
            let response = try await apiClient.seedContinuity(
                currentStreak: streak,
                longestStreak: max(streak, remote?.longestStreak ?? 0),
                lastActiveDate: lastActiveDate
            )
            applyContinuity(response)
            defaults.set(true, forKey: continuitySeededKey)
        } catch {
            // ignore continuity seed errors to avoid user-facing errors
        }
    }

    func refreshContinuity(isLoggedIn: Bool = true) async {
        guard isLoggedIn else { return }
        do {
            let response = try await apiClient.fetchContinuity()
            applyContinuity(response)
        } catch {
            // ignore continuity errors to avoid user-facing errors
        }
    }

    func fetchTodayStatsFromAPI(isLoggedIn: Bool = true) async throws -> DailyStatsResponse {
        guard isLoggedIn else { throw APIError.invalidResponse }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        let date = formatter.string(from: Date())
        return try await apiClient.fetchDailyStats(date: date)
    }

    func syncIfNeeded(reason: String, forceFetch: Bool = true, isLoggedIn: Bool = true, backfill: BackfillMode = .missing) async {
        guard isLoggedIn else { return }
        guard healthManager.isAuthorized else { return }
        healthManager.ensureInstallDateIfNeeded()
        updateLastOpenDate()
        if forceFetch {
            await healthManager.fetchTodayData()
        }

        await syncMissingDaysIfNeeded(mode: backfill)

        let payload = currentPayload()
        if payload.steps == 0, payload.calories == 0, payload.distanceKm == 0 {
            return
        }
        let hash = payload.hashValue
        let now = Date()

        if let lastSentAt, now.timeIntervalSince(lastSentAt) < minInterval, lastPayloadHash == hash {
            return
        }

        do {
            _ = try await apiClient.saveDailyStats(
                date: payload.date,
                steps: payload.steps,
                calories: payload.calories,
                distanceKm: payload.distanceKm
            )
            lastPayloadHash = hash
            lastSentAt = now
        } catch {
            // ignore to avoid user-facing errors; will retry on next trigger
        }
    }

    private func currentPayload() -> DailyStatsPayload {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        let date = formatter.string(from: Date())

        return DailyStatsPayload(
            date: date,
            steps: healthManager.steps,
            calories: healthManager.activeCalories,
            distanceKm: healthManager.walkingRunningDistanceKm
        )
    }

    private func syncMissingDaysIfNeeded(mode: BackfillMode) async {
        if mode == .none {
            return
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        let lastSynced = loadLastSyncedDate()
        let lastOpen = loadLastOpenDate()

        var baseStart: Date?
        if mode == .full {
            baseStart = healthManager.earliestFetchDate()
        } else if let lastSynced {
            baseStart = calendar.date(byAdding: .day, value: 1, to: lastSynced)
        } else {
            baseStart = lastOpen
        }

        guard var startDate = baseStart else {
            return
        }

        if mode == .missing, let lastOpen, lastOpen > startDate {
            startDate = lastOpen
        }

        if startDate >= todayStart {
            return
        }

        let stats = await healthManager.dailyStats(from: startDate, to: todayStart)
        if stats.isEmpty {
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")

        for item in stats.sorted(by: { $0.date < $1.date }) {
            if item.steps == 0, item.activeCalories == 0, item.distanceKm == 0 {
                continue
            }
            let dateString = formatter.string(from: item.date)
            do {
                _ = try await apiClient.saveDailyStats(
                    date: dateString,
                    steps: item.steps,
                    calories: item.activeCalories,
                    distanceKm: item.distanceKm
                )
                updateLastSyncedDate(date: item.date)
            } catch {
                // stop on failure to retry later in order
                break
            }
        }
    }

    private func loadLastSyncedDate() -> Date? {
        if let date = UserDefaults.standard.object(forKey: lastSyncedDateKey) as? Date {
            return Calendar.current.startOfDay(for: date)
        }
        return nil
    }

    private func updateLastSyncedDate(date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        UserDefaults.standard.set(day, forKey: lastSyncedDateKey)
    }

    private func loadLastOpenDate() -> Date? {
        if let date = UserDefaults.standard.object(forKey: lastOpenDateKey) as? Date {
            return Calendar.current.startOfDay(for: date)
        }
        return nil
    }

    private func updateLastOpenDate() {
        let day = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(day, forKey: lastOpenDateKey)
    }

    private func applyContinuity(_ response: ContinuityResponse) {
        continuityDays = response.currentStreak
        continuityLongestDays = response.longestStreak
        continuityLastActiveDate = response.lastActiveDate
    }

    private func convertLoginBonusDateToAPIFormat(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "ja_JP")
        input.timeZone = TimeZone.current
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: raw) else { return nil }

        let output = DateFormatter()
        output.locale = Locale(identifier: "ja_JP")
        output.timeZone = TimeZone.current
        output.dateFormat = "yyyy/MM/dd"
        return output.string(from: date)
    }
}

private struct DailyStatsPayload: Hashable {
    let date: String
    let steps: Int
    let calories: Int
    let distanceKm: Double
}
