import SwiftUI
import Combine

struct ChallengeItem: Identifiable {
    let key: String
    let amount: Int
    let title: String
    let subtitle: String

    var id: String { key }
}

struct ChallengeView: View {
    @State private var monthlyItems: [ChallengeItem] = [
        .init(key: "monthly_start", amount: 0, title: "スタートボーナス", subtitle: "コイン+50"),
        .init(key: "monthly_bronze", amount: 5_000, title: "ブロンズ報酬", subtitle: "コイン+80"),
        .init(key: "monthly_silver", amount: 15_000, title: "シルバー報酬", subtitle: "コイン+120"),
        .init(key: "monthly_gold", amount: 30_000, title: "ゴールド報酬", subtitle: "コイン+200")
    ]

    @State private var cumulativeItems: [ChallengeItem] = [
        .init(key: "unlock_battle", amount: 50_000, title: "すれ違いバトル解放", subtitle: "新しいゲームが開放"),
        .init(key: "unlock_poker", amount: 100_000, title: "ポーカー解放", subtitle: "新しいゲームが開放"),
        .init(key: "unlock_slot", amount: 150_000, title: "スロット解放", subtitle: "新しいゲームが開放")
    ]

    @ObservedObject private var health = HealthKitManager.shared
    @State private var showStamp: Bool = false
    @State private var mode: Int = 0 // 0: 今月, 1: 累計
    @State private var showCalendar: Bool = false
    @State private var selectedMonth: Date = Date()
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonthNumber: Int = Calendar.current.component(.month, from: Date())
    @AppStorage("restep.challenge.unlock.battle") private var battleUnlocked: Bool = false
    @AppStorage("restep.challenge.unlock.poker") private var pokerUnlocked: Bool = false
    @AppStorage("restep.challenge.unlock.slot") private var slotUnlocked: Bool = false
    @State private var availableYears: [Int] = []
    @State private var availableMonthsByYear: [Int: [Int]] = [:]
    @State private var isLoadingAvailableMonths: Bool = false
    @State private var claimedMonthlyRewards: Set<String> = []
    @State private var claimedCumulativeRewards: Set<String> = []
    @State private var showingRewardDetail: ChallengeItem? = nil
    @State private var isClaiming: Bool = false
    @State private var alertMessage: String? = nil
    private let wallet = WalletAPIClient.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Text("運動（歩数）に応じて特典を獲得できます。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        HStack(alignment: .top) {
                            timelineColumn
                                .padding(.leading, 24)

                            VStack(spacing: 12) {
                                Picker(selection: $mode) {
                                    Text("今月").tag(0)
                                    Text("累計").tag(1)
                                } label: {
                                    EmptyView()
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)

                                HStack {
                                    let displayed = (mode == 0) ? health.monthlySteps : health.cumulativeSteps
                                    Text((mode == 0 ? "今月の歩数 " : "累計歩数 ") + "\(formatted(displayed)) 歩")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(Color.purple)
                                        .clipShape(Capsule())

                                    Spacer()
                                }
                                .padding(.horizontal)

                                if !health.isAuthorized {
                                    Button("HealthKit認証を行う") {
                                        Task { await health.requestAuthorization(); health.startObserving() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .padding(.horizontal)
                                }

                                let selectedItems = (mode == 0) ? monthlyItems : cumulativeItems
                                ForEach(selectedItems) { item in
                                    let displayed = (mode == 0) ? health.monthlySteps : health.cumulativeSteps
                                    let achieved = displayed >= item.amount
                                    let claimed = (mode == 0) ? claimedMonthlyRewards.contains(item.key) : claimedCumulativeRewards.contains(item.key)
                                    RewardCard(item: item, achieved: achieved, mode: mode, claimed: claimed)
                                        .onTapGesture {
                                            if achieved {
                                                showingRewardDetail = item
                                            }
                                        }
                                }
                                .padding(.horizontal)
                            }
                        }
                        // QRチャレンジセクション
                        VStack(alignment: .leading, spacing: 12) {
                            Text("体験チャレンジ")
                                .font(.headline)
                                .padding(.horizontal)

                            NavigationLink {
                                QRChallengeView()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "qrcode")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                        .frame(width: 44, height: 44)
                                        .background(Color.green.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("RIZAP / chocoZAP 体験")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("QRコードを表示して体験参加")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.05), radius: 4)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }

                        .padding(.bottom, 80)
                    }
                }
            }
            .navigationTitle("特典一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            isLoadingAvailableMonths = true
                            await loadAvailableMonths()
                            isLoadingAvailableMonths = false
                            showCalendar = true
                        }
                    }) {
                        if isLoadingAvailableMonths {
                            ProgressView()
                        } else {
                            Image(systemName: "calendar")
                        }
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { health.allowPreInstallOverride.toggle() }) {
                        Text(health.allowPreInstallOverride ? "PreOn" : "PreOff")
                    }
                }
                #endif
            }
            .sheet(isPresented: $showCalendar) {
                VStack(spacing: 16) {
                    Text("過去の記録")
                        .font(.title2)
                        .bold()
                        .padding(.top, 12)

                    HStack {
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Picker(selection: $selectedYear) {
                            if availableYears.isEmpty {
                                let currentYear = Calendar.current.component(.year, from: Date())
                                let years = Array((currentYear - 5)...currentYear)
                                ForEach(years, id: \.self) { y in
                                    Text(String(format: "%d年", y)).tag(y)
                                }
                            } else {
                                ForEach(availableYears, id: \.self) { y in
                                    Text(String(format: "%d年", y)).tag(y)
                                }
                            }
                        } label: { EmptyView() }
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .pickerStyle(.wheel)

                        Picker(selection: $selectedMonthNumber) {
                            if let months = availableMonthsByYear[selectedYear], !months.isEmpty {
                                ForEach(months, id: \.self) { m in
                                    Text(String(format: "%d", m)).tag(m)
                                }
                            } else {
                                ForEach(1...12, id: \.self) { m in
                                    Text(String(format: "%d", m)).tag(m)
                                }
                            }
                        } label: { EmptyView() }
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .pickerStyle(.wheel)
                    }
                    .frame(minHeight: 180, idealHeight: 220, maxHeight: 280)

                    Text(String(format: "%d年 %02d月", selectedYear, selectedMonthNumber))
                        .font(.title3)
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 20) {
                        Button(action: { showCalendar = false }) {
                            Text("キャンセル")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(UIColor.systemGray5))
                                .clipShape(Capsule())
                        }

                        Button(action: {
                            var comps = DateComponents()
                            comps.year = selectedYear
                            comps.month = selectedMonthNumber
                            comps.day = 1
                            guard let startOfMonth = Calendar.current.date(from: comps) else { return }
                            let startOfNextMonth = Calendar.current.date(byAdding: .month, value: 1, to: startOfMonth) ?? Date()

                            Task {
                                let value = await HealthKitManager.shared.stepsBetween(start: startOfMonth, end: startOfNextMonth)
                                await MainActor.run {
                                    health.monthlySteps = value
                                    mode = 0
                                    showCalendar = false
                                }
                            }
                        }) {
                            Text("OK")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(red: 0.29, green: 0.78, blue: 0.95))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .presentationDetents([.medium])
            }
                        .sheet(item: $showingRewardDetail) { item in
                            let displayed = (mode == 0) ? health.monthlySteps : health.cumulativeSteps
                            let achieved = displayed >= item.amount
                            let claimed = (mode == 0) ? claimedMonthlyRewards.contains(item.key) : claimedCumulativeRewards.contains(item.key)
                            RewardDetailView(
                                item: item,
                                achieved: achieved,
                                claimed: claimed,
                                isClaiming: isClaiming,
                                onClaim: {
                                    Task { await claimReward(item) }
                                }
                            )
                        }
            .onAppear {
                Task { await health.requestAuthorization(); health.startObserving() }
                Task { await loadChallengeList() }
                Task { await loadChallengeStatus() }
            }
            .onChange(of: mode) { _, _ in
                Task { await loadChallengeStatus() }
            }
            .onChange(of: selectedYear) { _, _ in
                Task { await loadChallengeStatus() }
            }
            .onChange(of: selectedMonthNumber) { _, _ in
                Task { await loadChallengeStatus() }
            }
            .alert("エラー", isPresented: Binding(
                get: { alertMessage != nil },
                set: { _ in alertMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func loadAvailableMonths() async {
        let cal = Calendar.current
        let defaultStart = cal.date(byAdding: .year, value: -5, to: Date()) ?? Date()
        let startDate: Date
        if health.allowPreInstallOverride {
            startDate = defaultStart
        } else if let install = health.installDate {
            startDate = install
        } else {
            startDate = defaultStart
        }

        let months = await health.monthsWithData(from: startDate, to: Date())

        if months.isEmpty {
            availableYears = []
            availableMonthsByYear = [:]
            return
        }

        var dict: [Int: [Int]] = [:]
        for d in months {
            let comps = cal.dateComponents([.year, .month], from: d)
            if let y = comps.year, let m = comps.month {
                var arr = dict[y] ?? []
                if !arr.contains(m) { arr.append(m) }
                dict[y] = arr
            }
        }

        for (y, arr) in dict {
            dict[y] = arr.sorted()
        }
        let years = dict.keys.sorted()

        await MainActor.run {
            availableYears = years
            availableMonthsByYear = dict
            if let firstYear = years.first {
                selectedYear = firstYear
                selectedMonthNumber = dict[firstYear]?.first ?? selectedMonthNumber
            }
        }
    }

    @MainActor
    private func loadChallengeList() async {
        do {
            let response = try await wallet.fetchChallengeList()
            let monthly = response.monthly.map {
                ChallengeItem(key: $0.key, amount: $0.requiredSteps, title: $0.title, subtitle: $0.subtitle)
            }.sorted { $0.amount < $1.amount }
            let cumulative = response.cumulative.map {
                ChallengeItem(key: $0.key, amount: $0.requiredSteps, title: $0.title, subtitle: $0.subtitle)
            }.sorted { $0.amount < $1.amount }

            if !monthly.isEmpty { monthlyItems = monthly }
            if !cumulative.isEmpty { cumulativeItems = cumulative }
        } catch {
            // Keep local defaults on error.
        }
    }

    @MainActor
    private func loadChallengeStatus() async {
        do {
            let year = (mode == 0) ? selectedYear : nil
            let month = (mode == 0) ? selectedMonthNumber : nil
            let response = try await wallet.fetchChallengeStatus(year: year, month: month)
            claimedMonthlyRewards = Set(response.claimedMonthly)
            claimedCumulativeRewards = Set(response.claimedCumulative)
            battleUnlocked = response.unlocks.battle || claimedCumulativeRewards.contains("unlock_battle")
            pokerUnlocked = response.unlocks.poker || claimedCumulativeRewards.contains("unlock_poker")
            slotUnlocked = response.unlocks.slot || claimedCumulativeRewards.contains("unlock_slot")
        } catch {
            // keep current state on error
        }
    }

    @MainActor
    private func claimReward(_ item: ChallengeItem) async {
        guard !isClaiming else { return }
        isClaiming = true
        defer { isClaiming = false }

        do {
            let year = (mode == 0) ? selectedYear : nil
            let month = (mode == 0) ? selectedMonthNumber : nil
            let requestId = "challenge_" + item.key + "_" + (mode == 0 ? String(format: "%04d-%02d", selectedYear, selectedMonthNumber) : "cumulative")
            let response = try await wallet.claimChallengeReward(
                key: item.key,
                year: year,
                month: month,
                clientRequestId: requestId
            )

            if mode == 0 {
                claimedMonthlyRewards.insert(item.key)
            } else {
                claimedCumulativeRewards.insert(item.key)
            }

            if let unlocks = response.unlocks {
                battleUnlocked = unlocks.battle
                pokerUnlocked = unlocks.poker
                slotUnlocked = unlocks.slot
            } else {
                if item.key == "unlock_battle" { battleUnlocked = true }
                if item.key == "unlock_poker" { pokerUnlocked = true }
                if item.key == "unlock_slot" { slotUnlocked = true }
            }
        } catch let apiErr as APIError {
            alertMessage = apiErr.userMessage()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// Progress ratio (0.0 - 1.0) for the vertical timeline fill based on selected mode
    private var progressRatio: Double {
        let displayed = (mode == 0) ? health.monthlySteps : health.cumulativeSteps
        let maxAmount: Int
        if mode == 0 {
            maxAmount = monthlyItems.map { $0.amount }.max() ?? 1
        } else {
            maxAmount = cumulativeItems.map { $0.amount }.max() ?? 1
        }

        guard maxAmount > 0 else { return 0 }
        return min(Double(displayed) / Double(maxAmount), 1.0)
    }

    private func formatted(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var activeItems: [ChallengeItem] {
        mode == 0 ? monthlyItems : cumulativeItems
    }

    private var activeMaxAmount: Int {
        let maxValue = activeItems.map { $0.amount }.max() ?? 1
        return max(maxValue, 1)
    }

    private var activeDisplayedSteps: Int {
        mode == 0 ? health.monthlySteps : health.cumulativeSteps
    }

    private var timelineColumn: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.purple.opacity(0.85))
                .frame(minWidth: 16, idealWidth: 18, maxWidth: 22)
                .aspectRatio(1, contentMode: .fit)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))

            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 2)

                    Rectangle()
                        .fill(Color.purple.opacity(0.85))
                        .frame(width: 2, height: max(0, geo.size.height * CGFloat(progressRatio)))
                        .animation(.easeOut(duration: 0.35), value: progressRatio)

                    ForEach(activeItems) { markerItem in
                        let ratio = max(0.0, min(1.0, Double(markerItem.amount) / Double(activeMaxAmount)))
                        let isAchieved = activeDisplayedSteps >= markerItem.amount

                        Circle()
                            .fill(isAchieved ? Color.green.opacity(0.9) : Color.white)
                            .frame(minWidth: 12, idealWidth: 14, maxWidth: 18)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(Circle().stroke(isAchieved ? Color.green : Color.purple.opacity(0.9), lineWidth: 2))
                            .shadow(radius: 1)
                            .position(x: geo.size.width / 2, y: CGFloat(max(8.0, geo.size.height * CGFloat(ratio))))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 16, idealWidth: 18, maxWidth: 22)
        }
    }
}

private struct RewardCard: View {
    let item: ChallengeItem
    let achieved: Bool
    let mode: Int // 0: 今月, 1: 累計
    let claimed: Bool

    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.purple.opacity(0.9), Color.pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(minWidth: 48, idealWidth: 56, maxWidth: 64)
                    .aspectRatio(1, contentMode: .fit)

                Image(systemName: "figure.walk")
                    .font(.title3)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(mode == 0 ? "今月の歩数 " : "累計歩数 ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(formatted(item.amount)) 歩で")
                        .font(.subheadline.bold())
                        .foregroundColor(.purple)
                }

                Text("\(item.title) \(item.subtitle)")
                    .font(.body)
            }

            Spacer()

            if !achieved {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            } else if claimed {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func formatted(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// =========================
// Preview
// =========================
struct ChallengeView_Previews: PreviewProvider {
    static var previews: some View {
        ChallengeView()
    }
}

private struct RewardDetailView: View {
    let item: ChallengeItem
    let achieved: Bool
    let claimed: Bool
    let isClaiming: Bool
    let onClaim: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                    .padding(.top, 40)
                    .minimumScaleFactor(0.5)

                Text(item.title)
                    .font(.title2.bold())

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if achieved {
                    Button {
                        onClaim()
                    } label: {
                        Text(claimed ? "受け取り済み" : (isClaiming ? "処理中..." : "受け取る"))
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(claimed ? Color.gray : Color.purple)
                            .clipShape(Capsule())
                    }
                    .disabled(claimed || isClaiming)
                    .padding(.horizontal, 20)
                } else {
                    Text("条件達成後に受け取れます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("特典")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
