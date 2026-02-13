import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var statsSyncManager: StatsSyncManager
    @State private var isManualSyncInProgress: Bool = false
    @State private var syncResultMessage: String?
#if DEBUG
    @State private var showOnboardingDebug = false
#endif

    private var cardColor: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.12, green: 0.27, blue: 0.30, alpha: 1.0)
            }
            return UIColor(red: 0.82, green: 1.0, blue: 1.0, alpha: 1.0)
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.largeTitle.bold())
                        Text("設定")
                            .font(.largeTitle.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                    SettingsCard(tint: cardColor) {
                        VStack(spacing: 18) {
                            UnderlineToggleRow(title: "通知", isOn: $notificationManager.isEnabled)
                            UnderlineToggleRow(
                                title: "位置情報",
                                isOn: Binding(
                                    get: { locationManager.isEnabled },
                                    set: { newValue in
                                        locationManager.isEnabled = newValue
                                        if newValue, locationManager.authorizationStatus == .notDetermined {
                                            locationManager.requestPermission()
                                        }
                                    }
                                )
                            )
                            UnderlineExternalLinkRow(title: "ダッシュボード", urlString: "https://restep.winning.moe/dashboard/index.html")
                            UnderlineChevronLinkRow(title: "すれ違い設定", destination: EncounterSettingsView())
                            UnderlineChevronRow(title: "手動同期") {
                                Task {
                                    await runFullManualSync()
                                }
                            }
                            UnderlineChevronLinkRow(title: "近くのchocoZAP", destination: ChocozapNearbyView())
                            UnderlineChevronLinkRow(title: "アカウント設定", destination: AccountSettingsView())
                            UnderlineChevronLinkRow(title: "プロフィール", destination: ProfileView())
#if DEBUG
                            UnderlineChevronRow(title: "オンボーディング (デバッグ)") {
                                showOnboardingDebug = true
                            }
#endif
                        }
                    }
                    .padding(.horizontal, 22)

                    SettingsCard(tint: cardColor) {
                        VStack(spacing: 18) {
                            UnderlineChevronLinkRow(title: "よくある質問・お問い合わせ", destination: FaqContactView())
                            UnderlineChevronLinkRow(title: "利用規約", destination: TermsView())
                            UnderlineChevronLinkRow(title: "プライバシーポリシー", destination: PrivacyPolicyView())
                        }
                    }
                    .padding(.horizontal, 22)

                    Button {
                        Task { await session.logoutCurrentDevice() }
                    } label: {
                        Text("ログアウト")
                            .font(.body.bold())
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(cardColor)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                    Spacer(minLength: 12)
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .alert("同期", isPresented: Binding(
                get: { syncResultMessage != nil },
                set: { _ in syncResultMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncResultMessage ?? "")
            }
        }
#if DEBUG
        .fullScreenCover(isPresented: $showOnboardingDebug) {
            OnboardingFlowView(mode: .debug)
        }
#endif
    }

    @MainActor
    private func runFullManualSync() async {
        guard !isManualSyncInProgress else { return }
        guard session.isLoggedIn else {
            syncResultMessage = "ログイン後に同期してください。"
            return
        }

        isManualSyncInProgress = true
        defer { isManualSyncInProgress = false }

        await statsSyncManager.seedContinuityFromLocalIfNeeded(isLoggedIn: true)
        await statsSyncManager.recordContinuityIfNeeded(isLoggedIn: true)
        await statsSyncManager.refreshContinuity(isLoggedIn: true)
        await statsSyncManager.syncIfNeeded(reason: "manual_full", isLoggedIn: true, backfill: .full)

        if let response = try? await UserAPIClient.shared.fetchUserProfile() {
            ProfileStore.applyFromServer(response.profile)
        }

        await StampsStore.shared.refreshBalanceAsync()
        if let challenge = try? await WalletAPIClient.shared.fetchChallengeStatus() {
            UserDefaults.standard.set(challenge.unlocks.battle, forKey: "restep.challenge.unlock.battle")
            UserDefaults.standard.set(challenge.unlocks.poker, forKey: "restep.challenge.unlock.poker")
            UserDefaults.standard.set(challenge.unlocks.slot, forKey: "restep.challenge.unlock.slot")
        }

        syncResultMessage = "同期が完了しました。"
    }
}

struct SettingsCard<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack { content }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct CapsuleButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .underline()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.bold())
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(tint)
            .clipShape(Capsule())
        }
    }
}

struct UnderlineChevronRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .underline()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.bold())
            }
            .foregroundColor(.primary)
        }
        .padding(.top, 2)

        Divider()
            .background(Color.secondary.opacity(0.5))
    }
}

struct UnderlineChevronLinkRow<Destination: View>: View {
    let title: String
    let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .underline()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.bold())
            }
            .foregroundColor(.primary)
        }
        .padding(.top, 2)

        Divider()
            .background(Color.secondary.opacity(0.5))
    }
}

struct UnderlineExternalLinkRow: View {
    let title: String
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack {
                    Text(title)
                        .font(.title3.bold())
                        .underline()
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.body.bold())
                }
                .foregroundColor(.primary)
            }
            .padding(.top, 2)

            Divider()
                .background(Color.secondary.opacity(0.5))
        }
    }
}

struct UnderlineToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .underline()
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }

        Divider()
            .background(Color.secondary.opacity(0.5))
    }
}
