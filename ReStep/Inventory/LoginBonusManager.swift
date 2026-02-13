import Foundation

struct LoginBonusResult {
    let coins: Int
    let streak: Int
    let isStreakContinued: Bool
}

final class LoginBonusManager {
    static let shared = LoginBonusManager()

    private let lastClaimKey = "restep.loginBonus.lastClaimDate"
    private let streakKey = "restep.loginBonus.streak"
    private let claimHistoryKey = "restep.loginBonus.claimHistory"
    private let wallet = WalletAPIClient.shared

    private init() {}

    func checkAndGrant() async -> LoginBonusResult? {
        let today = Self.dayKey(Date())
        let defaults = UserDefaults.standard

        if let lastClaim = defaults.string(forKey: lastClaimKey), lastClaim == today {
            return nil
        }

        let yesterday = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let previous = defaults.string(forKey: lastClaimKey)
        let isStreakContinued = (previous == yesterday)

        let currentStreak = defaults.integer(forKey: streakKey)
        let newStreak = isStreakContinued ? max(1, currentStreak + 1) : 1
        let cappedStreak = min(newStreak, 7)
        let coins = Self.rewardCoins(forStreak: cappedStreak)

        do {
            let localCoins = GameStore.shared.loadInventory().coins
            let register = try await wallet.registerWallet(initialBalance: localCoins)
            if register.registered, localCoins > 0 {
                var inventory = GameStore.shared.loadInventory()
                inventory.coins = 0
                GameStore.shared.saveInventory(inventory)
            }

            let requestId = "login_bonus_" + today
            _ = try await wallet.earnCoins(amount: coins, reason: "login_bonus", clientRequestId: requestId)

            defaults.set(today, forKey: lastClaimKey)
            defaults.set(newStreak, forKey: streakKey)
            recordClaimDate(today, defaults: defaults)

            return LoginBonusResult(coins: coins, streak: newStreak, isStreakContinued: isStreakContinued)
        } catch {
            return nil
        }
    }

    private static func rewardCoins(forStreak streak: Int) -> Int {
        let table = [50, 60, 70, 80, 90, 100, 150]
        let index = max(0, min(streak, table.count) - 1)
        return table[index]
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func recordClaimDate(_ dayKey: String, defaults: UserDefaults) {
        let raw = defaults.string(forKey: claimHistoryKey) ?? ""
        var values = raw
            .split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty }

        if values.contains(dayKey) == false {
            values.append(dayKey)
        }

        values.sort()
        let recent = Array(values.suffix(366))
        defaults.set(recent.joined(separator: ","), forKey: claimHistoryKey)
    }
}
