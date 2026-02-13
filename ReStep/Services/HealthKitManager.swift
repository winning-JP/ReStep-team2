import Foundation
import HealthKit
import Combine

@MainActor
class HealthKitManager: ObservableObject {

    enum AuthorizationState: Equatable {
        case unavailable
        case authorized
        case partial
        case denied
        case notDetermined
    }

    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()
    private let installDateKey = "AppInstallDate"
    private let accountCreatedAtKey = "restep.account.createdAt"
    private(set) var installDate: Date?
    private(set) var accountCreatedAt: Date?

    @Published var steps: Int = 0
    @Published var activeCalories: Int = 0
    @Published var totalCalories: Int = 0
    @Published var walkingRunningDistanceKm: Double = 0
    @Published var isAuthorized: Bool = false
    @Published private(set) var authorizationState: AuthorizationState = .notDetermined
    @Published private(set) var requestStatus: HKAuthorizationRequestStatus = .unknown
    @Published var errorMessage: String?
    @Published var monthlySteps: Int = 0
    @Published var cumulativeSteps: Int = 0
    @Published var allowPreInstallOverride: Bool = false

    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.distanceWalkingRunning)
    ]

    private init() {
        loadInstallDate()
        loadAccountCreatedAt()
    }

    private func fetchQuantitySum(identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async -> Double {
        guard let qtyType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let unit: HKUnit
        switch identifier {
        case .stepCount:
            unit = HKUnit.count()
        case .activeEnergyBurned:
            unit = HKUnit.kilocalorie()
        case .basalEnergyBurned:
            unit = HKUnit.kilocalorie()
        case .distanceWalkingRunning:
            unit = HKUnit.meter()
        default:
            unit = HKUnit.count()
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double, Never>) in
            let query = HKStatisticsQuery(quantityType: qtyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                if let sum = result?.sumQuantity() {
                    continuation.resume(returning: sum.doubleValue(for: unit))
                } else {
                    // No data -> return 0 quietly
                    continuation.resume(returning: 0)
                }
            }
            healthStore.execute(query)
        }
    }

    /// Load install date from UserDefaults if present
    private func loadInstallDate() {
        if let t = UserDefaults.standard.object(forKey: installDateKey) as? Date {
            installDate = t
        }
    }

    /// Load account created-at date from UserDefaults if present
    private func loadAccountCreatedAt() {
        if let t = UserDefaults.standard.object(forKey: accountCreatedAtKey) as? Date {
            accountCreatedAt = t
        }
    }

    /// Ensure install date exists (set to now on first run)
    private func ensureInstallDate() {
        if installDate == nil {
            let now = Date()
            UserDefaults.standard.set(now, forKey: installDateKey)
            installDate = now
        }
    }

    /// Ensure install date exists (public wrapper for other services)
    func ensureInstallDateIfNeeded() {
        ensureInstallDate()
    }

    /// Store account created-at date (from API)
    func updateAccountCreatedAt(_ date: Date?) {
        accountCreatedAt = date
        if let date {
            UserDefaults.standard.set(date, forKey: accountCreatedAtKey)
        } else {
            UserDefaults.standard.removeObject(forKey: accountCreatedAtKey)
        }
    }

    /// Earliest date we should consider for fetching health data
    private func earliestKnownDate() -> Date? {
        switch (installDate, accountCreatedAt) {
        case (nil, nil):
            return nil
        case (let install?, nil):
            return install
        case (nil, let created?):
            return created
        case (let install?, let created?):
            return min(install, created)
        }
    }

    /// Public helper to expose earliest fetch date (install date or account created-at)
    func earliestFetchDate() -> Date? {
        return earliestKnownDate()
    }

    /// Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Request authorization to read health data
    func requestAuthorization() async {
        guard isHealthKitAvailable else {
            errorMessage = "HealthKitはこのデバイスで利用できません"
            authorizationState = .unavailable
            isAuthorized = false
            return
        }

        do {
            // Request read-only access (nil for write types)
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            refreshAuthorizationStatus()

            // Fetch initial data after authorization
            // ensure install date recorded and fetch data
            ensureInstallDate()
            await fetchTodayData()
        } catch {
            errorMessage = "HealthKit認証エラー: \(error.localizedDescription)"
            isAuthorized = false
#if DEBUG
            print("[HealthKit] requestAuthorization error=\(error.localizedDescription)")
#endif
        }
    }

    /// Refresh current authorization status without prompting.
    func refreshAuthorizationStatus() {
        guard isHealthKitAvailable else {
            authorizationState = .unavailable
            isAuthorized = false
            return
        }

        healthStore.getRequestStatusForAuthorization(toShare: [], read: typesToRead) { status, _ in
            Task { @MainActor in
                self.requestStatus = status
                let computed = self.resolveAuthorizationState(requestStatus: status)
                self.authorizationState = computed
                self.isAuthorized = (computed == .authorized)
#if DEBUG
                print("[HealthKit] requestStatus=\(status) resolved=\(computed)")
#endif
            }
        }
    }

    private func resolveAuthorizationState(requestStatus: HKAuthorizationRequestStatus? = nil) -> AuthorizationState {
        guard isHealthKitAvailable else { return .unavailable }

        switch requestStatus {
        case .some(.unnecessary):
            // For read-only, "unnecessary" means user has already responded.
            return .authorized
        case .some(.shouldRequest):
            return .notDetermined
        case .some(.unknown):
            return .notDetermined
        case .none:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    /// Fetch today's step count and active calories
    func fetchTodayData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchTodaySteps() }
            group.addTask { await self.fetchTodayActiveCalories() }
            group.addTask { await self.fetchTodayTotalCalories() }
            group.addTask { await self.fetchTodayDistance() }
            group.addTask { await self.fetchMonthlySteps() }
            group.addTask { await self.fetchCumulativeSteps() }
        }
    }

    /// Fetch today's step count
    private func fetchTodaySteps() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        do {
            let statistics = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKStatistics, Error>) in
                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let result = result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: HealthKitError.noData)
                    }
                }
                healthStore.execute(query)
            }

            if let sum = statistics.sumQuantity() {
                steps = Int(sum.doubleValue(for: HKUnit.count()))
            }
        } catch {
            print("歩数取得エラー: \(error)")
        }
    }

    /// Generic fetch for steps between two dates
    private func fetchSteps(from start: Date, to end: Date) async -> Int {
        let value = await fetchQuantitySum(identifier: .stepCount, from: start, to: end)
        return Int(value)
    }

    /// Fetch this month's steps (month-to-date)
    private func fetchMonthlySteps() async {
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        let startOfMonth = Calendar.current.date(from: comps) ?? Calendar.current.startOfDay(for: now)

        // cap start to install date if available
        let effectiveStart: Date
        if let earliest = earliestKnownDate() {
            effectiveStart = max(startOfMonth, earliest)
        } else {
            effectiveStart = startOfMonth
        }

        if effectiveStart >= now {
            monthlySteps = 0
            return
        }

        let value = await fetchSteps(from: effectiveStart, to: now)
        monthlySteps = value
    }

    /// Fetch cumulative steps (from distant past to now)
    private func fetchCumulativeSteps() async {
        let now = Date()
        if allowPreInstallOverride {
            // allow full history when debug override enabled
            let value = await fetchSteps(from: Date.distantPast, to: now)
            cumulativeSteps = value
            return
        }

        if let earliest = earliestKnownDate() {
            if earliest >= now {
                cumulativeSteps = 0
                return
            }
            let value = await fetchSteps(from: earliest, to: now)
            cumulativeSteps = value
        } else {
            let value = await fetchSteps(from: Date.distantPast, to: now)
            cumulativeSteps = value
        }
    }

    /// Public helper to fetch steps between arbitrary dates
    /// - Returns: step count between `start` (inclusive) and `end` (exclusive)
    func stepsBetween(start: Date, end: Date) async -> Int {
        // ensure install date exists and cap start to installDate unless debug override enabled
        let effectiveStart: Date
        if allowPreInstallOverride {
            effectiveStart = start
        } else if let earliest = earliestKnownDate() {
            effectiveStart = max(start, earliest)
        } else {
            effectiveStart = start
        }

        if effectiveStart >= end {
            return 0
        }

        return await fetchSteps(from: effectiveStart, to: end)
    }

    /// Return daily stats (steps, active calories, distance) for each day in [start, end)
    func dailyStats(from start: Date, to end: Date) async -> [DailyHealthStat] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        if startDay >= endDay {
            return []
        }

        let effectiveStart: Date
        if allowPreInstallOverride {
            effectiveStart = startDay
        } else if let earliest = earliestKnownDate() {
            effectiveStart = max(startDay, earliest)
        } else {
            effectiveStart = startDay
        }

        let effectiveStartDay = calendar.startOfDay(for: effectiveStart)
        if effectiveStartDay >= endDay {
            return []
        }

        async let stepsByDay = dailySums(identifier: .stepCount, from: effectiveStartDay, to: endDay)
        async let caloriesByDay = dailySums(identifier: .activeEnergyBurned, from: effectiveStartDay, to: endDay)
        async let distanceByDay = dailySums(identifier: .distanceWalkingRunning, from: effectiveStartDay, to: endDay)

        let (stepsMap, caloriesMap, distanceMap) = await (stepsByDay, caloriesByDay, distanceByDay)
        let allDates = Set(stepsMap.keys)
            .union(caloriesMap.keys)
            .union(distanceMap.keys)

        let sortedDates = allDates.sorted()
        return sortedDates.map { date in
            let steps = Int(stepsMap[date] ?? 0)
            let calories = Int(caloriesMap[date] ?? 0)
            let distanceKm = (distanceMap[date] ?? 0) / 1000.0
            return DailyHealthStat(date: date, steps: steps, activeCalories: calories, distanceKm: distanceKm)
        }
    }

    /// Daily cumulative sums for a quantity type over [start, end)
    private func dailySums(identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async -> [Date: Double] {
        guard let qtyType = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        if startDay >= endDay {
            return [:]
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDay, end: endDay, options: .strictStartDate)
        let anchorDate = startDay
        let interval = DateComponents(day: 1)

        let unit: HKUnit
        switch identifier {
        case .stepCount:
            unit = HKUnit.count()
        case .activeEnergyBurned:
            unit = HKUnit.kilocalorie()
        case .basalEnergyBurned:
            unit = HKUnit.kilocalorie()
        case .distanceWalkingRunning:
            unit = HKUnit.meter()
        default:
            unit = HKUnit.count()
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<[Date: Double], Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: qtyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var results: [Date: Double] = [:]
                if let collection = collection {
                    collection.enumerateStatistics(from: startDay, to: endDay) { stats, _ in
                        let day = calendar.startOfDay(for: stats.startDate)
                        let value = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                        results[day] = value
                    }
                }
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }

    /// Return months (start-of-month dates) that have step data in the given range.
    /// Uses `HKStatisticsCollectionQuery` with monthly interval to efficiently find months with >0 steps.
    func monthsWithData(from start: Date, to end: Date) async -> [Date] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }

        let calendar = Calendar.current
        let startComps = calendar.dateComponents([.year, .month], from: start)
        let anchorDate = calendar.date(from: startComps) ?? calendar.startOfDay(for: start)
        let interval = DateComponents(month: 1)

        return await withCheckedContinuation { (continuation: CheckedContinuation<[Date], Never>) in
            let query = HKStatisticsCollectionQuery(quantityType: stepType, quantitySamplePredicate: nil, options: .cumulativeSum, anchorDate: anchorDate, intervalComponents: interval)
            query.initialResultsHandler = { _, collection, error in
                var months: [Date] = []
                if let collection = collection {
                    collection.enumerateStatistics(from: start, to: end) { stats, _ in
                        if let sum = stats.sumQuantity(), sum.doubleValue(for: HKUnit.count()) > 0 {
                            months.append(stats.startDate)
                        }
                    }
                }
                continuation.resume(returning: months)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch today's active calories burned
    private func fetchTodayActiveCalories() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let value = await fetchQuantitySum(identifier: .activeEnergyBurned, from: startOfDay, to: now)
        activeCalories = Int(value)
    }

    /// Fetch today's total calories burned (active + basal)
    private func fetchTodayTotalCalories() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        async let active = fetchQuantitySum(identifier: .activeEnergyBurned, from: startOfDay, to: now)
        async let basal = fetchQuantitySum(identifier: .basalEnergyBurned, from: startOfDay, to: now)
        let total = await (active + basal)
        totalCalories = Int(total)
    }

    /// Fetch today's walking/running distance (km)
    private func fetchTodayDistance() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let meters = await fetchQuantitySum(identifier: .distanceWalkingRunning, from: startOfDay, to: now)
        walkingRunningDistanceKm = meters / 1000.0
    }

    /// Start observing health data changes in real-time
    func startObserving() {
        guard isHealthKitAvailable else { return }

        for type in typesToRead {
            guard let sampleType = type as? HKSampleType else { continue }

            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, _, error in
                if error == nil {
                    Task { @MainActor in
                        await self?.fetchTodayData()
                    }
                }
            }
            healthStore.execute(query)
        }
    }
}

/// Custom errors for HealthKit operations
enum HealthKitError: Error {
    case noData
    case notAvailable
    case authorizationDenied
}

struct DailyHealthStat: Sendable {
    let date: Date
    let steps: Int
    let activeCalories: Int
    let distanceKm: Double
}
