import Foundation
import Combine

final class StampsStore: ObservableObject {
    static let shared = StampsStore()

    @Published private(set) var balance: Int {
        didSet {
            UserDefaults.standard.set(balance, forKey: Self.balanceKey)
        }
    }

    @Published private(set) var totalEarned: Int {
        didSet {
            UserDefaults.standard.set(totalEarned, forKey: Self.totalEarnedKey)
        }
    }

    private static let balanceKey = "restep.stamps.balance"
    private static let totalEarnedKey = "restep.stamps.totalEarned"
    private static let lastDateKey = "restep.stamps.lastDateKey"
    private let wallet = WalletAPIClient.shared
    private var lastDateKeyValue: String {
        didSet {
            UserDefaults.standard.set(lastDateKeyValue, forKey: Self.lastDateKey)
        }
    }

    private init() {
        balance = UserDefaults.standard.integer(forKey: Self.balanceKey)
        totalEarned = UserDefaults.standard.integer(forKey: Self.totalEarnedKey)
        lastDateKeyValue = UserDefaults.standard.string(forKey: Self.lastDateKey) ?? ""
    }

    func refreshBalance() {
        Task { await refreshBalanceAsync() }
    }

    @MainActor
    func refreshBalanceAsync() async {
        do {
            let response = try await wallet.fetchStampBalance()
            balance = response.balance
        } catch {
            // Keep local balance on error.
        }
    }

    func syncEarned(currentEarned: Int, dateKey: String) {
        if dateKey != lastDateKeyValue {
            totalEarned = 0
            lastDateKeyValue = dateKey
        }
        guard currentEarned > totalEarned else { return }
        let requestId = "stamp_sync_\(dateKey)_\(currentEarned)"
        Task {
            do {
                let response = try await wallet.syncStamps(
                    dateKey: dateKey,
                    currentEarned: currentEarned,
                    clientRequestId: requestId
                )
                await MainActor.run {
                    balance = response.balance
                    totalEarned = response.earnedToday
                    lastDateKeyValue = dateKey
                }
            } catch {
                // Keep local values on error.
            }
        }
    }

    @discardableResult
    func spend(_ cost: Int, reason: String = "reward") async -> Bool {
        guard cost > 0 else { return false }
        let requestId = "stamp_spend_" + UUID().uuidString
        do {
            let response = try await wallet.spendStamps(amount: cost, reason: reason, clientRequestId: requestId)
            await MainActor.run {
                balance = response.balance
            }
            return true
        } catch {
            return false
        }
    }

    func addBonusStamp(count: Int = 1, reason: String = "bonus") {
        guard count > 0 else { return }
        let requestId = "stamp_add_" + UUID().uuidString
        Task {
            do {
                let response = try await wallet.addStamps(amount: count, reason: reason, clientRequestId: requestId)
                await MainActor.run {
                    balance = response.balance
                }
            } catch {
                // Keep local balance on error.
            }
        }
    }

    func reset() {
        balance = 0
        totalEarned = 0
        lastDateKeyValue = ""
        UserDefaults.standard.removeObject(forKey: Self.balanceKey)
        UserDefaults.standard.removeObject(forKey: Self.totalEarnedKey)
        UserDefaults.standard.removeObject(forKey: Self.lastDateKey)
    }
}
