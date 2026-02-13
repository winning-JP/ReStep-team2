import SwiftUI
import CoreBluetooth

struct EncounterView: View {
    @StateObject private var manager = BluetoothEncounterManager.shared
    @State private var myTraveler: Traveler?
    @State private var encounters: [Encounter] = []
    @State private var statusText: String = "探索を開始してください"
    @State private var selectedTab: EncounterTab = .all
    @State private var historySort: HistorySort = .newest
    @State private var processedTravelerIds: Set<UUID> = []
    @State private var partyActionMessage: String?
    @State private var showPartyMessage: Bool = false
    @State private var stampProgress = EncounterStampProgress(count: 0, awardedCount: 0, thresholds: [])
    @EnvironmentObject private var session: AuthSession
    @AppStorage("restep.profile.nickname") private var nickname: String = ""
    @AppStorage("restep.encounter.enabled") private var encounterEnabled: Bool = false
    @AppStorage("restep.encounter.shareNickname") private var shareNickname: Bool = true
    @AppStorage("restep.encounter.batterySaver") private var batterySaver: Bool = false
    @AppStorage("restep.encounter.historyDays") private var historyDays: Int = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("すれ違い")
                    .font(.title2.bold())

                EncounterStampProgressCard(progress: stampProgress)

                HStack(spacing: 10) {
                    NavigationLink {
                        TravelerListView()
                    } label: {
                        Text("旅人")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }

                    NavigationLink {
                        PartyBuilderView()
                    } label: {
                        Text("パーティ")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }

                    NavigationLink {
                        DungeonView()
                    } label: {
                        Text("迷宮")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }

                Text(statusText)
                    .font(.footnote)
                    .foregroundColor(.secondary)

                encounterControls

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if selectedTab == .all || selectedTab == .received {
                            sectionHeader("受け取った旅人")
                            if manager.nearbyUsers.isEmpty {
                                emptyState("まだ旅人がいません")
                            } else {
                                ForEach(manager.nearbyUsers, id: \.id) { payload in
                                    let traveler = EncounterRecorder.shared.traveler(from: payload)
                                    receivedCard(traveler, isAdded: processedTravelerIds.contains(traveler.id))
                                }
                            }
                        }

                        if selectedTab == .all || selectedTab == .history {
                            sectionHeader("履歴（7日）")
                            if sortedEncounters.isEmpty {
                                emptyState("履歴がありません")
                            } else {
                                ForEach(sortedEncounters) { encounter in
                                    historyCard(encounter)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .navigationTitle("すれ違い")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                refreshEncounterState()
                loadStampProgress()
                if myTraveler == nil {
                    myTraveler = GameStore.shared.loadTravelers().first
                }
                if encounterEnabled {
                    startEncounterFlow()
                } else {
                    statusText = "すれ違い通信はOFFです"
                }
            }
            .onDisappear {
                statusText = encounterEnabled ? "Bluetooth探索中" : "すれ違い通信はOFFです"
            }
            .onChange(of: encounterEnabled) { _, newValue in
                if newValue {
                    startEncounterFlow()
                } else {
                    manager.stop()
                    statusText = "すれ違い通信はOFFです"
                }
            }
            .onChange(of: shareNickname) { _, _ in
                guard encounterEnabled else { return }
                startEncounterFlow()
            }
            .onChange(of: batterySaver) { _, newValue in
                manager.setBatterySaverEnabled(newValue)
            }
            .onChange(of: manager.isBluetoothPoweredOn) { _, newValue in
                guard encounterEnabled else { return }
                if newValue {
                    startEncounterFlow()
                } else {
                    manager.stop()
                    if BluetoothEncounterManager.isBluetoothDenied {
                        statusText = "Bluetooth権限が必要です"
                        encounterEnabled = false
                    } else {
                        statusText = "BluetoothがOFFです"
                    }
                }
            }
            .onChange(of: manager.nearbyUsers) { _, newValue in
                refreshEncounterState()
            }
            .onReceive(NotificationCenter.default.publisher(for: EncounterRecorder.didUpdateNotification)) { _ in
                refreshEncounterState()
                loadStampProgress()
            }
            .onReceive(NotificationCenter.default.publisher(for: EncounterStampTracker.didAwardStampsNotification)) { _ in
                loadStampProgress()
            }
            .alert("パーティ", isPresented: $showPartyMessage) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(partyActionMessage ?? "")
            }
        }
    }

    private func addEncounter(_ traveler: Traveler) {
        guard EncounterRecorder.shared.record(traveler: traveler) else {
            refreshEncounterState()
            return
        }
        refreshEncounterState()
    }

    private func loadRecentEncounters() -> [Encounter] {
        let all = GameStore.shared.loadEncounters()
        let days = max(1, historyDays)
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return all.filter { $0.date >= cutoff }
    }

    private func refreshEncounterState() {
        let recent = loadRecentEncounters()
        encounters = recent
        processedTravelerIds = Set(recent.map { $0.traveler.id })
    }

    private func loadStampProgress() {
        stampProgress = EncounterStampTracker.shared.todayProgress()
    }

    private func startEncounterFlow() {
        guard BluetoothEncounterManager.isBluetoothDenied == false else {
            statusText = "Bluetooth権限が必要です"
            encounterEnabled = false
            manager.stop()
            return
        }
        if CBManager.authorization == .notDetermined {
            statusText = "Bluetooth権限の確認中..."
        }
        let nick = shareNickname ? nickname : "名無しの旅人"
        manager.setBatterySaverEnabled(batterySaver)
        let payload = manager.makePayload(nickname: nick)
        manager.start(with: payload)
        statusText = manager.isBluetoothPoweredOn ? "Bluetooth探索中" : "BluetoothがOFFです"
    }
}

private enum EncounterTab: String, CaseIterable, Identifiable {
    case all = "すべて"
    case received = "受け取った"
    case history = "履歴"

    var id: String { rawValue }
}

private enum HistorySort: String, CaseIterable, Identifiable {
    case newest = "新着"
    case oldest = "古い順"
    case name = "名前"

    var id: String { rawValue }
}

private extension EncounterView {
    var encounterControls: some View {
        VStack(spacing: 8) {
            Picker("", selection: $selectedTab) {
                ForEach(EncounterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if selectedTab == .all || selectedTab == .history {
                HStack {
                    Text("並び替え")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $historySort) {
                        ForEach(HistorySort.allCases) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    var sortedEncounters: [Encounter] {
        switch historySort {
        case .newest:
            return encounters.sorted { $0.date > $1.date }
        case .oldest:
            return encounters.sorted { $0.date < $1.date }
        case .name:
            return encounters.sorted { $0.traveler.name < $1.traveler.name }
        }
    }

    func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 6)
    }

    func emptyState(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func receivedCard(_ traveler: Traveler, isAdded: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cyan.opacity(0.2))
                .frame(width: 42, height: 42)
                .overlay(
                    Text(String(traveler.name.prefix(1)))
                        .font(.headline)
                        .foregroundColor(.cyan)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(traveler.name)
                    .font(.headline)
                Text(traveler.job)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 6) {
                if isAdded {
                    Text("追加済み")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                } else {
                    Button {
                        addEncounter(traveler)
                    } label: {
                        Text("追加")
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }

                Button {
                    addToParty(traveler)
                } label: {
                    Text("パーティへ")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.cyan)
                        .clipShape(Capsule())
                }
            }
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

    func historyCard(_ encounter: Encounter) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.18))
                .frame(width: 42, height: 42)
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

    func addToParty(_ traveler: Traveler) {
        var party = GameStore.shared.loadParty()
        if party.memberIds.contains(traveler.id) {
            partyActionMessage = "\(traveler.name) は既にパーティにいます"
            showPartyMessage = true
            return
        }
        if party.memberIds.count >= 4 {
            partyActionMessage = "パーティが満員です（最大4人）"
            showPartyMessage = true
            return
        }
        party.memberIds.append(traveler.id)
        party.setMembers(party.memberIds)
        GameStore.shared.saveParty(party)
        partyActionMessage = "\(traveler.name) をパーティに追加しました"
        showPartyMessage = true
    }
}

private struct EncounterStampProgressCard: View {
    let progress: EncounterStampProgress

    var body: some View {
        let nextText: String = {
            if let remaining = progress.remainingToNext, let next = progress.nextThreshold {
                return "次のスタンプまであと\(remaining)回（\(next)回目）"
            }
            if progress.thresholds.isEmpty {
                return "スタンプ条件を準備中"
            }
            return "本日のスタンプ上限達成"
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日のすれ違い")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(progress.count)回")
                        .font(.title2.bold())
                }
                Spacer()
                Text("獲得 \(progress.awardedCount)")
                    .font(.caption.bold())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            }

            Text(nextText)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(progress.thresholds, id: \.self) { threshold in
                    let reached = progress.count >= threshold
                    Text("\(threshold)")
                        .font(.caption2.bold())
                        .foregroundColor(reached ? .white : .secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(reached ? Color.orange : Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterView_Previews: PreviewProvider {
    static var previews: some View {
        EncounterView()
    }
}
#endif
