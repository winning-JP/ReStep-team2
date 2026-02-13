import SwiftUI

struct EncounterGameSelectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var manager = EncounterManager()
    @State private var myTraveler: Traveler?
    @State private var encounterCount: Int = 0
    @State private var recentEncounters: [Encounter] = []
    @AppStorage("restep.profile.birthday") private var birthdayRaw: String = ""
    @AppStorage("restep.challenge.unlock.battle") private var battleUnlocked: Bool = false
    @AppStorage("restep.challenge.unlock.poker") private var pokerUnlocked: Bool = false
    @AppStorage("restep.challenge.unlock.slot") private var slotUnlocked: Bool = false
    @State private var coinBalance: Int = 0
    @State private var isLoadingBalance = false
    @State private var processedTravelerIds: Set<UUID> = []
    @ObservedObject private var health = HealthKitManager.shared
    private let wallet = WalletAPIClient.shared

    private var games: [EncounterGameItem] {
        var items: [EncounterGameItem] = [
            .init(title: "すれ違いレイド", subtitle: "協力で討伐", imageName: "すれ違い", isEnabled: true, lockText: nil, destination: AnyView(EncounterRaidView())),
            .init(title: "すれちがい伝説", subtitle: "冒険へ出発", imageName: "すれ違い", isEnabled: true, lockText: nil, destination: AnyView(EncounterLegendStartView())),
            .init(title: "宝箱さがし", subtitle: "運試しミニゲーム", imageName: "宝探しゲーム", isEnabled: true, lockText: nil, destination: AnyView(EncounterTreasureView())),
            .init(
                title: "すれ違いバトル",
                subtitle: "1回限りの対決",
                imageName: "すれ違いバトル",
                isEnabled: battleUnlocked,
                lockText: battleUnlocked ? nil : "累計50,000歩の特典で解放",
                destination: AnyView(EncounterBattleListView())
            ),
            .init(title: "旅人図鑑", subtitle: "仲間を確認", imageName: "旅人図鑑", isEnabled: true, lockText: nil, destination: AnyView(TravelerListView()))
        ]
        items.insert(
            .init(
                title: "スロット",
                subtitle: "運試し",
                imageName: "スロット",
                isEnabled: slotUnlocked,
                lockText: slotUnlocked ? nil : "累計150,000歩の特典で解放",
                destination: AnyView(EncounterSlotView())
            ),
            at: 2
        )
        items.insert(
            .init(
                title: "ポーカー",
                subtitle: "5枚ドロー",
                imageName: "ポーカー",
                isEnabled: pokerUnlocked,
                lockText: pokerUnlocked ? nil : "累計100,000歩の特典で解放",
                destination: AnyView(EncounterPokerView())
            ),
            at: 4
        )
        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(games) { game in
                        NavigationLink {
                            game.destination
                        } label: {
                            GameSelectCard(
                                title: game.title,
                                subtitle: game.subtitle,
                                imageName: game.imageName,
                                isEnabled: game.isEnabled,
                                lockText: game.lockText
                            )
                        }
                        .disabled(game.isEnabled == false)
                    }
                }
                .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("すれ違い履歴")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)

                        NavigationLink {
                            EncounterListView()
                        } label: {
                            HStack {
                                Text("すべて表示")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.cyan)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.cyan)
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if recentEncounters.isEmpty {
                            HStack {
                                Text("まだ履歴がありません")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            ForEach(recentEncounters) { encounter in
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.orange.opacity(0.18))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(String(encounter.traveler.name.prefix(1)))
                                                .font(.headline)
                                                .foregroundColor(.orange)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(encounter.traveler.name)
                                            .font(.headline)
                                        Text(encounter.traveler.job)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text(encounter.displayDateTime)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 12)
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
            .onAppear {
                let all = GameStore.shared.loadEncounters()
                encounterCount = all.count
                recentEncounters = all.sorted { $0.date > $1.date }.prefix(5).map { $0 }
                processedTravelerIds = Set(all.map { $0.traveler.id })
                if myTraveler == nil {
                    myTraveler = GameStore.shared.loadTravelers().first
                }
                manager.start()
                if let traveler = myTraveler {
                    manager.sendTraveler(traveler)
                }
                Task { await bootstrapWallet() }
                Task { await loadChallengeUnlocks() }
            }
            .onDisappear {
                manager.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: EncounterRecorder.didUpdateNotification)) { _ in
                let all = GameStore.shared.loadEncounters()
                encounterCount = all.count
                recentEncounters = all.sorted { $0.date > $1.date }.prefix(5).map { $0 }
                processedTravelerIds = Set(all.map { $0.traveler.id })
            }
            .onChange(of: manager.nearbyTravelers) { _, newValue in
                for traveler in newValue where !processedTravelerIds.contains(traveler.id) {
                    addEncounter(traveler)
                }
            }
        }
    }

    private func addEncounter(_ traveler: Traveler) {
        var encounters = GameStore.shared.loadEncounters()
        let new = Encounter(traveler: traveler, source: .mpc)
        encounters.insert(new, at: 0)
        GameStore.shared.saveEncounters(encounters)

        var travelers = GameStore.shared.loadTravelers()
        if travelers.contains(where: { $0.id == traveler.id }) == false {
            travelers.append(traveler)
            GameStore.shared.saveTravelers(travelers)
        }

        NotificationCenter.default.post(
            name: EncounterRecorder.didDetectEncounterNotification,
            object: nil,
            userInfo: ["name": traveler.name]
        )

        processedTravelerIds.insert(traveler.id)
        encounterCount = encounters.count
        recentEncounters = encounters.sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if presentationMode.wrappedValue.isPresented {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .accessibilityLabel("戻る")
            }

            Spacer()

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(isLoadingBalance ? "..." : "\(coinBalance)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(.systemGray6))
                .clipShape(Capsule())

                NavigationLink {
                    EncounterListView()
                } label: {
                    Text(String(format: "すれ違った人数：%03d", encounterCount))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color(.systemTeal).opacity(0.18))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    @MainActor
    private func bootstrapWallet() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        do {
            let localCoins = GameStore.shared.loadInventory().coins
            let response = try await wallet.registerWallet(initialBalance: localCoins)
            coinBalance = response.balance
            if response.registered, localCoins > 0 {
                var inventory = GameStore.shared.loadInventory()
                inventory.coins = 0
                GameStore.shared.saveInventory(inventory)
            }
        } catch {
            // Keep the previous balance on error.
        }
    }

    private func parseBirthday(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.date(from: trimmed)
    }

    @MainActor
    private func loadChallengeUnlocks() async {
        do {
            let response = try await wallet.fetchChallengeStatus()
            let claimed = Set(response.claimedCumulative)
            // Fallback: honor claimed unlock rewards even if unlock flags are not reflected in DB yet.
            battleUnlocked = response.unlocks.battle || claimed.contains("unlock_battle")
            pokerUnlocked = response.unlocks.poker || claimed.contains("unlock_poker")
            slotUnlocked = response.unlocks.slot || claimed.contains("unlock_slot")
        } catch {
            // keep current state on error
        }
    }
}

private struct GameSelectCard: View {
    let title: String?
    let subtitle: String?
    let imageName: String?
    let isEnabled: Bool
    let lockText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(.systemGray5))
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay(
                    Group {
                        if let imageName {
                            GeometryReader { proxy in
                                let inset = max(8.0, min(18.0, min(proxy.size.width, proxy.size.height) * 0.08))
                                Image(imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(inset)
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                            }
                        }
                        if let lockText {
                            VStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                Text(lockText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(12)
                            .background(Color.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                )
                .overlay(alignment: .bottomLeading) {
                    if title != nil || subtitle != nil {
                        VStack(alignment: .leading, spacing: 2) {
                            if let title {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                            if let subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(10)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(isEnabled ? Color.clear : Color.white.opacity(0.4), lineWidth: 1)
                )
                .saturation(isEnabled ? 1.0 : 0.3)

            // Title is displayed on the card for better scanability.
        }
        .frame(maxWidth: .infinity)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

private struct EncounterGameItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let imageName: String?
    let isEnabled: Bool
    let lockText: String?
    let destination: AnyView
}

struct EncounterTreasureView: View {
    @State private var resultText: String = "宝箱を見つけた！"
    @State private var hasOpened = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("宝箱さがし")
                .font(.title2.bold())

            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .frame(height: 180)
                .overlay(
                    Image(systemName: hasOpened ? "shippingbox.fill" : "shippingbox")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundColor(.orange)
                )

            Text(resultText)
                .font(.body.weight(.semibold))
                .foregroundColor(.secondary)

            Button {
                let rewards = [
                    "コイン +50",
                    "スタンプ +1",
                    "回復アイテム +1",
                    "経験値 +20"
                ]
                resultText = rewards.randomElement() ?? "何も起きなかった"
                hasOpened = true
            } label: {
                Text(hasOpened ? "もう一度ひく" : "宝箱を開ける")
                    .font(.body.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding()
        .navigationTitle("宝箱さがし")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterGameSelectView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterGameSelectView()
        }
    }
}
#endif
