import SwiftUI
import Combine

@MainActor
final class CoinUsageTracker: ObservableObject {
    static let shared = CoinUsageTracker()

    @AppStorage("restep.coin.daily_used") private var storedDailyUsed: Int = 0
    @AppStorage("restep.coin.daily_limit") private var storedDailyLimit: Int = 500
    @AppStorage("restep.coin.daily_date_key") private var storedDateKey: String = ""

    @Published var dailyUsed: Int = 0
    @Published var dailyLimit: Int = 500

    var remaining: Int { max(0, dailyLimit - dailyUsed) }

    private let wallet = WalletAPIClient.shared

    init() {
        let today = Self.todayKey()
        if storedDateKey != today {
            storedDailyUsed = 0
            storedDailyLimit = 500
            storedDateKey = today
        }
        dailyUsed = storedDailyUsed
        dailyLimit = storedDailyLimit
    }

    func canUse(_ amount: Int) -> Bool {
        resetIfNewDay()
        return amount <= remaining
    }

    func refresh() async {
        do {
            let response = try await wallet.fetchCoinDailyUsage()
            dailyUsed = response.used
            dailyLimit = response.dailyLimit
            storedDailyUsed = response.used
            storedDailyLimit = response.dailyLimit
            storedDateKey = response.dateKey
        } catch {
            DebugLog.log("CoinUsageTracker.refresh error: \(error.localizedDescription)")
        }
    }

    func recordUsage(_ amount: Int) {
        dailyUsed += amount
        storedDailyUsed = dailyUsed
    }

    func updateLimit(_ newLimit: Int) {
        dailyLimit = newLimit
        storedDailyLimit = newLimit
    }

    private func resetIfNewDay() {
        let today = Self.todayKey()
        if storedDateKey != today {
            dailyUsed = 0
            dailyLimit = 500
            storedDailyUsed = 0
            storedDailyLimit = 500
            storedDateKey = today
        }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
