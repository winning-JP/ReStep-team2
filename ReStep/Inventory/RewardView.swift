import SwiftUI

struct RewardView: View {
    enum Tier: String, CaseIterable, Identifiable {
        case sprout = "芽"
        case grove = "森"
        case bloom = "開花"
        case aurora = "オーロラ"

        var id: String { rawValue }

        var tint: Color {
            switch self {
            case .sprout: return .green
            case .grove: return .teal
            case .bloom: return .orange
            case .aurora: return .pink
            }
        }

        var subtitle: String {
            switch self {
            case .sprout: return "小さな喜び"
            case .grove: return "気分を整える"
            case .bloom: return "しっかり癒やす"
            case .aurora: return "特別なご褒美"
            }
        }

        var minCost: Int {
            switch self {
            case .sprout: return 2
            case .grove: return 4
            case .bloom: return 6
            case .aurora: return 9
            }
        }

        var icon: String {
            switch self {
            case .sprout: return "leaf.fill"
            case .grove: return "tree.fill"
            case .bloom: return "sparkles"
            case .aurora: return "crown.fill"
            }
        }
    }

    struct RewardItem: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let stampCost: Int
        let icon: String
        let impact: String
        let duration: String
        let tier: Tier
    }

    @EnvironmentObject private var stampsStore: StampsStore
    @StateObject private var healthManager = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTier: Tier = .sprout
    @State private var selectedItemID: UUID?
    @State private var showInsufficientAlert = false
    @State private var showConfirm = false
    @State private var showSuccess = false
    @State private var showUnlockOverlay = false
    @State private var lastExchange: RewardItem?
    @State private var todayLog: [RewardLogEntry] = []

    @AppStorage("restep.goal.steps") private var stepTarget: Int = 5000
    @AppStorage("restep.goal.calories") private var calorieTarget: Int = 300
    @AppStorage("restep.goal.distanceKm") private var distanceTargetKm: Double = 3.0

    private let items: [RewardItem] = [
        RewardItem(title: "3分散歩", description: "音楽1曲だけ歩く", stampCost: 2, icon: "figure.walk", impact: "気分リセット", duration: "3分", tier: .sprout),
        RewardItem(title: "あたたかい飲み物", description: "温かい1杯で整える", stampCost: 2, icon: "cup.and.saucer.fill", impact: "回復", duration: "5分", tier: .sprout),
        RewardItem(title: "スローストレッチ", description: "寝る前にゆっくり", stampCost: 4, icon: "figure.yoga", impact: "疲労ケア", duration: "7分", tier: .grove),
        RewardItem(title: "お風呂を丁寧に", description: "香りや照明で整える", stampCost: 4, icon: "drop.fill", impact: "深呼吸", duration: "10分", tier: .grove),
        RewardItem(title: "お気に入りスイーツ", description: "一番好きなものを選ぶ", stampCost: 6, icon: "birthday.cake.fill", impact: "幸福感", duration: "10分", tier: .bloom),
        RewardItem(title: "夜のゆっくり映画", description: "30分だけ観る", stampCost: 6, icon: "play.rectangle.fill", impact: "集中と解放", duration: "30分", tier: .bloom),
        RewardItem(title: "小さな冒険", description: "知らない道を少し歩く", stampCost: 9, icon: "map.fill", impact: "刺激", duration: "20分", tier: .aurora),
        RewardItem(title: "特別な外食", description: "本当に行きたい場所へ", stampCost: 10, icon: "fork.knife", impact: "リフレッシュ", duration: "60分", tier: .aurora)
    ]

    private var growthProgress: Double {
        let step = stepTarget > 0 ? Double(healthManager.steps) / Double(stepTarget) : 0
        let cal = calorieTarget > 0 ? Double(healthManager.activeCalories) / Double(calorieTarget) : 0
        let dist = distanceTargetKm > 0 ? healthManager.walkingRunningDistanceKm / distanceTargetKm : 0
        return min(1.0, (step * 0.5) + (cal * 0.3) + (dist * 0.2))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroSection
                recommendationSection
                tierRail
                rewardGrid
                logSection
                confirmSection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("成長のご褒美")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                }
            }
        }
        .alert("スタンプが足りません", isPresented: $showInsufficientAlert) {
            Button("OK", role: .cancel) { }
        }
        .confirmationDialog("解放しますか？", isPresented: $showConfirm, titleVisibility: .visible) {
            if let item = selectedItem {
                Button("解放する（\(item.stampCost)スタンプ）") {
                    Task {
                        let didSpend = await stampsStore.spend(item.stampCost)
                        await MainActor.run {
                            if didSpend {
                                lastExchange = item
                                selectedItemID = nil
                                showSuccess = true
                                showUnlockOverlay = true
                                appendLog(item)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                    showSuccess = false
                                    showUnlockOverlay = false
                                }
                            } else {
                                showInsufficientAlert = true
                            }
                        }
                    }
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            if let item = selectedItem {
                Text("\(item.title) を解放します。残りスタンプは \(max(0, stampsStore.balance - item.stampCost)) です。")
            }
        }
        .task {
            await healthManager.requestAuthorization()
            healthManager.startObserving()
            await healthManager.fetchTodayData()
            loadTodayLog()
        }
        .overlay(alignment: .top) {
            if showSuccess, let item = lastExchange {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("解放完了")
                            .font(.subheadline.weight(.semibold))
                        Text("\(item.title) を解放しました（-\(item.stampCost)）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if showUnlockOverlay, let item = lastExchange {
                UnlockCelebrationOverlay(item: item, tint: item.tier.tint)
                    .transition(.opacity)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("成長の祭壇")
                        .font(.title2.bold())
                    Text("今日の成長率: \(Int(growthProgress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("スタンプ \(stampsStore.balance)")
                    .font(.caption.bold())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color(.systemBackground))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                RewardHeroStat(title: "歩数", value: "\(healthManager.steps.formatted(.number))")
                RewardHeroStat(title: "消費", value: "\(healthManager.activeCalories) kcal")
                RewardHeroStat(title: "距離", value: String(format: "%.1f km", healthManager.walkingRunningDistanceKm))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color.teal.opacity(0.18), Color(.systemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日のおすすめ")
                .font(.headline)

            if let item = recommendedItem {
                HStack(spacing: 12) {
                    Circle()
                        .fill(item.tier.tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: item.icon)
                                .foregroundColor(item.tier.tint)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.bold())
                        Text(item.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("\(item.stampCost)")
                        .font(.caption.bold())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(item.tier.tint.opacity(0.15))
                        .clipShape(Capsule())
                }
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            } else {
                Text("スタンプが貯まるとおすすめが表示されます")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var tierRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Tier.allCases) { tier in
                    Button {
                        selectedTier = tier
                        selectedItemID = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: tier.icon)
                                    .foregroundColor(tier.tint)
                                Spacer()
                                Text("\(tier.minCost)+")
                                    .font(.caption.bold())
                                    .foregroundColor(tier.tint)
                            }
                            Text(tier.rawValue)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(tier.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(width: 140, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(selectedTier == tier ? tier.tint.opacity(0.18) : Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(selectedTier == tier ? tier.tint : Color.black.opacity(0.05), lineWidth: selectedTier == tier ? 2 : 1)
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var rewardGrid: some View {
        let tierItems = items.filter { $0.tier == selectedTier }
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tierItems) { item in
                let affordable = stampsStore.balance >= item.stampCost
                Button {
                    selectedItemID = item.id
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundColor(selectedTier.tint)
                                .font(.title3.bold())
                            Spacer()
                            Text("\(item.stampCost)")
                                .font(.caption.bold())
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(selectedTier.tint.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        Text(item.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        Text(item.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Text(item.impact)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("・")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(item.duration)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if !affordable {
                            Text("スタンプ不足")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selectedItemID == item.id ? selectedTier.tint : Color.black.opacity(0.04), lineWidth: selectedItemID == item.id ? 2 : 1)
                    )
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日の解放ログ")
                .font(.headline)

            if todayLog.isEmpty {
                Text("まだ解放がありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(todayLog) { entry in
                    HStack {
                        Image(systemName: entry.icon)
                            .foregroundColor(entry.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.bold())
                            Text(entry.timeText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("-\(entry.stampCost)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var confirmSection: some View {
        VStack(spacing: 8) {
            Text("解放したご褒美は“今日の成長ログ”に記録されます")
                .font(.footnote)
                .foregroundColor(.secondary)

            Button {
                guard selectedItem != nil else { return }
                showConfirm = true
            } label: {
                Text(selectedItemID == nil ? "ご褒美を選んでね" : "このご褒美を解放する")
                    .font(.body.bold())
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .disabled(selectedItemID == nil)
        }
        .padding(.top, 6)
    }

    private var selectedItem: RewardItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    private var recommendedItem: RewardItem? {
        let affordable = items.filter { $0.stampCost <= stampsStore.balance }
        guard !affordable.isEmpty else { return nil }
        let tier = recommendedTier
        return affordable.first(where: { $0.tier == tier }) ?? affordable.first
    }

    private var recommendedTier: Tier {
        switch growthProgress {
        case 0..<0.35: return .sprout
        case 0.35..<0.65: return .grove
        case 0.65..<0.9: return .bloom
        default: return .aurora
        }
    }

    private func loadTodayLog() {
        todayLog = RewardLogStore.shared.loadToday()
    }

    private func appendLog(_ item: RewardItem) {
        let entry = RewardLogEntry(
            title: item.title,
            icon: item.icon,
            tintHex: item.tier.tintHex,
            stampCost: item.stampCost,
            timestamp: Date()
        )
        RewardLogStore.shared.append(entry)
        todayLog = RewardLogStore.shared.loadToday()
    }
}

private struct RewardLogEntry: Identifiable, Codable {
    let id: UUID
    let title: String
    let icon: String
    let tintHex: String
    let stampCost: Int
    let timestamp: Date

    init(title: String, icon: String, tintHex: String, stampCost: Int, timestamp: Date) {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.tintHex = tintHex
        self.stampCost = stampCost
        self.timestamp = timestamp
    }

    var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: timestamp)
    }

    var tint: Color {
        Color(hex: tintHex) ?? .teal
    }
}

private final class RewardLogStore {
    static let shared = RewardLogStore()
    private let storageKeyPrefix = "restep.reward.log."

    func append(_ entry: RewardLogEntry) {
        var current = loadToday()
        current.insert(entry, at: 0)
        save(current)
    }

    func loadToday() -> [RewardLogEntry] {
        let key = storageKeyPrefix + Self.todayKey()
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RewardLogEntry].self, from: data)) ?? []
    }

    private func save(_ entries: [RewardLogEntry]) {
        let key = storageKeyPrefix + Self.todayKey()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }
}

private struct UnlockCelebrationOverlay: View {
    let item: RewardView.RewardItem
    let tint: Color
    @State private var show = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(show ? 0.45 : 0.0))
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [tint.opacity(0.6), tint.opacity(0.15), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .scaleEffect(show ? 1.0 : 0.7)
                        .opacity(show ? 1.0 : 0.0)

                    Circle()
                        .stroke(tint.opacity(0.6), lineWidth: 2)
                        .frame(width: 180, height: 180)
                        .scaleEffect(show ? 1.0 : 0.6)
                        .opacity(show ? 1.0 : 0.0)

                    Image(systemName: item.icon)
                        .font(.system(size: 52, weight: .bold))
                        .foregroundColor(.white)
                        .padding(22)
                        .background(tint)
                        .clipShape(Circle())
                        .shadow(color: tint.opacity(0.35), radius: 16, x: 0, y: 10)
                        .scaleEffect(show ? 1.0 : 0.6)
                        .opacity(show ? 1.0 : 0.0)
                }

                Text("解放完了")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text(item.title)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .stroke(tint.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(show ? 1.0 : 0.8)
            .opacity(show ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                show = true
            }
        }
    }
}

private struct RewardHeroStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private extension RewardView.Tier {
    var tintHex: String {
        switch self {
        case .sprout: return "#2ECC71"
        case .grove: return "#1ABC9C"
        case .bloom: return "#F39C12"
        case .aurora: return "#E84393"
        }
    }
}

private extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 6, let value = Int(sanitized, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

#if DEBUG
@available(iOS 17, *)
struct RewardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RewardView()
                .environmentObject(StampsStore.shared)
        }
    }
}
#endif
