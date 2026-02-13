import Foundation
import Combine

@MainActor
final class AuthSession: ObservableObject {

    enum AuthRoute {
        case login
        case register
    }

    @Published var route: AuthRoute = .login

    @Published var isLoggedIn: Bool = false

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var didRestore: Bool = false
    @Published private(set) var user: UserProfile?
    @Published private(set) var lastErrorMessage: String?

    private let apiClient = UserAPIClient.shared

    init() {
        Task { await restoreSession() }
    }

    func login(userIdOrEmail: String, password: String) async -> Bool {
        guard !userIdOrEmail.isEmpty, !password.isEmpty else {
            lastErrorMessage = "入力してください"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.login(
                identifier: userIdOrEmail,
                password: password
            )
            user = response.user
            isLoggedIn = true
            lastErrorMessage = nil
            applyAccountCreatedAt(from: response.user)
            await fetchAndApplyProfile()
            return true
        } catch let apiErr as APIError {
            lastErrorMessage = apiErr.userMessage()
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func logout() {
        isLoggedIn = false
        route = .login
        user = nil
        HealthKitManager.shared.updateAccountCreatedAt(nil)

        // すべてのユーザーデータをクリア
        ProfileStore.clearAll()
        GameStore.shared.clearAll()
        StampsStore.shared.reset()

        // UserDefaults から他のユーザー関連データをクリア
        let defaults = UserDefaults.standard

        // プロフィール関連のキーを削除（@AppStorage で使用されているもの）
        defaults.removeObject(forKey: "restep.profile.height")
        defaults.removeObject(forKey: "restep.profile.weight")
        defaults.removeObject(forKey: "restep.profile.gender")
        defaults.removeObject(forKey: "restep.profile.birthday")
        defaults.removeObject(forKey: "restep.goal.steps")
        defaults.removeObject(forKey: "restep.goal.calories")
        defaults.removeObject(forKey: "restep.goal.distanceKm")

        // スタンプ関連のデータを削除
        defaults.removeObject(forKey: "restep.stamps.balance")
        defaults.removeObject(forKey: "restep.stamps.totalEarned")
        defaults.removeObject(forKey: "restep.stamps.lastDateKey")

        // その他のキャッシュデータを削除
        defaults.removeObject(forKey: "restep.lastStatsSync")
        defaults.removeObject(forKey: "restep.loginBonus.lastClaimed")
    }

    func goRegister() {
        route = .register
    }

    func goLogin() {
        route = .login
    }

    func register(userId: String, email: String, password: String) async -> Bool {
        guard !userId.isEmpty, !email.isEmpty, !password.isEmpty else {
            lastErrorMessage = "入力してください"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await apiClient.register(loginId: userId, email: email, password: password)
            user = response.user
            isLoggedIn = true
            lastErrorMessage = nil
            applyAccountCreatedAt(from: response.user)
            await fetchAndApplyProfile()
            return true
        } catch let apiErr as APIError {
            lastErrorMessage = apiErr.userMessage()
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func logoutCurrentDevice() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await apiClient.logout()
            lastErrorMessage = nil
        } catch let apiErr as APIError {
            lastErrorMessage = apiErr.userMessage()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        logout()
    }

    func restoreSession() async {
        isLoading = true
        defer {
            isLoading = false
            didRestore = true
        }

        do {
            let status = try await apiClient.status()
            if status.loggedIn == false {
                isLoggedIn = false
                return
            }
            if let user = status.user {
                self.user = user
                isLoggedIn = true
                applyAccountCreatedAt(from: user)
                await fetchAndApplyProfile()
            } else {
                isLoggedIn = false
            }
        } catch {
            isLoggedIn = false
        }
    }

    private func fetchAndApplyProfile() async {
        do {
            let response = try await apiClient.fetchUserProfile()
            ProfileStore.applyFromServer(response.profile)
        } catch {
            // Ignore profile fetch errors; keep local values.
        }
    }

    private func applyAccountCreatedAt(from user: UserProfile?) {
        guard let raw = user?.createdAt, !raw.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: raw) {
            HealthKitManager.shared.updateAccountCreatedAt(date)
        }
    }

    func updateAccount(loginId: String, email: String, password: String, confirmPassword: String) async -> Bool {
        let trimmedLoginId = loginId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLoginId.isEmpty || trimmedEmail.isEmpty {
            lastErrorMessage = "ユーザーIDとメールアドレスは必須です"
            return false
        }
        if !password.isEmpty || !confirmPassword.isEmpty {
            guard password == confirmPassword else {
                lastErrorMessage = "パスワードが一致しません"
                return false
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await apiClient.updateProfile(
                loginId: trimmedLoginId.isEmpty ? nil : trimmedLoginId,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                password: trimmedPassword.isEmpty ? nil : trimmedPassword
            )
            lastErrorMessage = nil

            let status = try await apiClient.status()
            if let user = status.user {
                self.user = user
                applyAccountCreatedAt(from: user)
            }
            return true
        } catch let apiErr as APIError {
            lastErrorMessage = apiErr.userMessage()
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }
}
