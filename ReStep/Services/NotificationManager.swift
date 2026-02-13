import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            Task { await applyEnabledChange(previous: oldValue) }
        }
    }

    private let center = UNUserNotificationCenter.current()
    private static let enabledKey = "restep.notifications.enabled"

    override init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if isEnabled, !(authorizationStatus == .authorized || authorizationStatus == .provisional) {
            isEnabled = false
        }
    }

    func notifyStampEarned(locationName: String) {
        guard isEnabled else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "chocoZAPに来店"
        content.body = "\(locationName) に到着しました。スタンプを1個付与しました。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "restep.chocozap.stamp.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func notifyEncounter(name: String) {
        guard isEnabled else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "すれ違い"
        content.body = "\(name) とすれ違いました"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "restep.encounter.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func applyEnabledChange(previous: Bool) async {
        guard isEnabled != previous else { return }

        if isEnabled {
            let granted = await requestAuthorizationIfNeeded()
            if !granted {
                isEnabled = false
            }
        } else {
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                let updated = await center.notificationSettings()
                authorizationStatus = updated.authorizationStatus
                return granted
            } catch {
                authorizationStatus = .denied
                return false
            }
        case .denied, .ephemeral:
            return false
        @unknown default:
            return false
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
