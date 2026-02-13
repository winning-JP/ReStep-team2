import Foundation
import Observation

@MainActor
@Observable
final class BluetoothEncounterDebugController {
    static let shared = BluetoothEncounterDebugController()

    private let manager = BluetoothEncounterManager.shared
    private(set) var isRunning: Bool = false

    func start(overrideNickname: String? = nil) {
        guard isRunning == false else { return }
        let defaults = UserDefaults.standard
        let shareNickname = defaults.object(forKey: "restep.encounter.shareNickname") as? Bool ?? true
        let nickname = resolveNickname(overrideNickname)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadNickname = shareNickname ? trimmedNickname : "名無しの旅人"
        let payload = manager.makePayload(nickname: payloadNickname)
        manager.setBatterySaverEnabled(false)
        manager.start(with: payload)
        isRunning = true

        Task {
            let syncNickname = (shareNickname && !trimmedNickname.isEmpty) ? trimmedNickname : nil
            _ = try? await UserAPIClient.shared.syncEncounterProfile(
                bluetoothUserId: payload.id,
                shareNickname: shareNickname,
                nickname: syncNickname
            )
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stop()
        isRunning = false
    }

    func restart(overrideNickname: String? = nil) {
        stop()
        start(overrideNickname: overrideNickname)
    }

    private func resolveNickname(_ override: String?) -> String {
        let trimmedOverride = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedOverride.isEmpty == false {
            return trimmedOverride
        }
        let key = "restep.profile.nickname"
        let stored = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "デバッグ" : stored
    }
}

@MainActor
final class BluetoothEncounterRuntimeController {
    static let shared = BluetoothEncounterRuntimeController()

    private let manager = BluetoothEncounterManager.shared
    private var isRunning: Bool = false
    private let lastKnownLoggedInKey = "restep.encounter.lastKnownLoggedIn"

    func bootstrap() {
        let defaults = UserDefaults.standard
        let cachedLoggedIn = defaults.object(forKey: lastKnownLoggedInKey) as? Bool ?? false
        refresh(isLoggedIn: cachedLoggedIn, persist: false)
    }

    func refresh(isLoggedIn: Bool, persist: Bool = true) {
        let defaults = UserDefaults.standard
        let debugRunning = defaults.bool(forKey: "restep.encounter.debugRunning")
        let enabled = defaults.bool(forKey: "restep.encounter.enabled")
        let shareNickname = defaults.object(forKey: "restep.encounter.shareNickname") as? Bool ?? true
        let batterySaver = defaults.bool(forKey: "restep.encounter.batterySaver")
        let nickname = defaults.string(forKey: "restep.profile.nickname") ?? ""

        if persist {
            defaults.set(isLoggedIn, forKey: lastKnownLoggedInKey)
        }

        if debugRunning {
            return
        }

        guard isLoggedIn, enabled else {
            stop()
            return
        }

        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        manager.setBatterySaverEnabled(batterySaver)
        let payloadNickname = shareNickname ? trimmedNickname : "名無しの旅人"
        let payload = manager.makePayload(nickname: payloadNickname)
        manager.start(with: payload)
        isRunning = true

        Task {
            let syncNickname = trimmedNickname.isEmpty ? nil : trimmedNickname
            _ = try? await UserAPIClient.shared.syncEncounterProfile(
                bluetoothUserId: payload.id,
                shareNickname: shareNickname,
                nickname: syncNickname
            )
        }
    }

    func stop() {
        guard isRunning else { return }
        manager.stop()
        isRunning = false
    }
}
