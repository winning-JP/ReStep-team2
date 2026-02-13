import SwiftUI

struct TargetView: View {
    @StateObject private var healthManager = HealthKitManager.shared
    @EnvironmentObject private var statsSyncManager: StatsSyncManager
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var stampsStore: StampsStore

    @AppStorage("restep.goal.steps") private var stepTarget: Int = 5000
    @AppStorage("restep.goal.calories") private var calorieTarget: Int = 300
    @AppStorage("restep.goal.distanceKm") private var distanceTargetKm: Double = 3.0
    @State private var showStampEffect = false
    @State private var hasShownTodayStamp = false
    @State private var yesterdaySteps: Int?

    private struct GrowthStage {
        let name: String
        let minProgress: Double
        let theme: Color
        let subtitle: String
    }

    private let stages: [GrowthStage] = [
        GrowthStage(name: "芽", minProgress: 0.0, theme: Color.green, subtitle: "小さな一歩が根を張る"),
        GrowthStage(name: "若木", minProgress: 0.25, theme: Color.teal, subtitle: "日々の積み重ねが形になる"),
        GrowthStage(name: "成木", minProgress: 0.5, theme: Color.blue, subtitle: "継続が強さを作る"),
        GrowthStage(name: "古木", minProgress: 0.75, theme: Color.orange, subtitle: "安定した習慣の証"),
        GrowthStage(name: "聖樹", minProgress: 1.0, theme: Color.pink, subtitle: "今日の成長が完成した"),
    ]

    private var progressSteps: Double {
        guard stepTarget > 0 else { return 0 }
        return min(1.0, Double(healthManager.steps) / Double(stepTarget))
    }

    private var progressCalories: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(1.0, Double(healthManager.activeCalories) / Double(calorieTarget))
    }

    private var progressDistance: Double {
        guard distanceTargetKm > 0 else { return 0 }
        return min(1.0, healthManager.walkingRunningDistanceKm / distanceTargetKm)
    }

    private var growthProgress: Double {
        let weighted = (progressSteps * 0.5) + (progressCalories * 0.3) + (progressDistance * 0.2)
        return min(1.0, weighted)
    }

    private var currentStage: GrowthStage {
        stages.last(where: { growthProgress >= $0.minProgress }) ?? stages[0]
    }

    private var nextStage: GrowthStage? {
        stages.first(where: { growthProgress < $0.minProgress })
    }

    private var nextStageText: String {
        guard let next = nextStage else { return "今日の成長は完成しました" }
        let percent = max(0, Int((next.minProgress - growthProgress) * 100))
        return "次の「\(next.name)」まであと\(percent)%"
    }

    private var actionTips: [String] {
        var tips: [String] = []
        if progressSteps < 1.0 {
            tips.append("3分歩いて“根”を育てる")
        }
        if progressCalories < 1.0 {
            tips.append("階段を一回だけ使う")
        }
        if progressDistance < 1.0 {
            tips.append("少し遠回りして距離を伸ばす")
        }
        if tips.isEmpty {
            tips.append("今日は達成済み。深呼吸で整える")
        }
        return Array(tips.prefix(2))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroGrowthSection
                    nourishmentSection
                    growthBonusSection
                    actionSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("成長")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await healthManager.requestAuthorization()
                healthManager.startObserving()
                await statsSyncManager.syncIfNeeded(reason: "target", isLoggedIn: session.isLoggedIn)
                if session.isLoggedIn {
                    stampsStore.refreshBalance()
                }
                await loadYesterdaySteps()
            }
            .onChange(of: growthProgress) { _, newValue in
                guard newValue >= 1.0, !hasShownTodayStamp else { return }
                hasShownTodayStamp = true
                triggerStampEffect()
            }
            .refreshable {
                await healthManager.fetchTodayData()
                await statsSyncManager.syncIfNeeded(reason: "target_refresh", forceFetch: false, isLoggedIn: session.isLoggedIn)
                if session.isLoggedIn {
                    stampsStore.refreshBalance()
                }
            }
            .overlay {
                if showStampEffect {
                    StampImpactOverlay()
                        .transition(.opacity)
                }
            }
        }
    }

    private var heroGrowthSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今日の成長")
                    .font(.title2.bold())
                Spacer()
                InfoChip(text: "スタンプ \(stampsStore.balance)")
            }

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 26)
                    .fill(
                        LinearGradient(
                            colors: [currentStage.theme.opacity(0.18), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(currentStage.name)
                                    .font(.largeTitle.bold())
                                    .foregroundColor(currentStage.theme)
                                Text("ステージ")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            Text(currentStage.subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            ProgressBar(progress: growthProgress, accentColor: currentStage.theme, showPercentage: true)
                                .frame(height: 18)

                            Text(nextStageText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        GrowthAvatarBadge(
                            stageName: currentStage.name,
                            tint: currentStage.theme,
                            progress: growthProgress,
                            isMaxStage: nextStage == nil
                        )
                    }

                    HStack(spacing: 12) {
                        GrowthStat(title: "成長率", value: "\(Int(growthProgress * 100))%")
                        GrowthStat(title: "歩数", value: "\(healthManager.steps.formatted(.number))")
                        GrowthStat(title: "距離", value: String(format: "%.1fkm", healthManager.walkingRunningDistanceKm))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let delta = yesterdayDeltaText {
                            Text("前日比 \(delta)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(nextDayPreviewText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .padding(.top, 8)
    }

    private var nourishmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成長の栄養")
                .font(.headline)

            VStack(spacing: 12) {
                GrowthMetricCard(
                    title: "歩数",
                    current: "\(healthManager.steps.formatted(.number)) 歩",
                    target: "目標 \(stepTarget) 歩",
                    progress: progressSteps,
                    icon: "figure.walk",
                    tint: .pink
                )

                GrowthMetricCard(
                    title: "アクティブ消費",
                    current: "\(healthManager.activeCalories.formatted(.number)) kcal",
                    target: "目標 \(calorieTarget) kcal",
                    progress: progressCalories,
                    icon: "flame.fill",
                    tint: .orange
                )

                GrowthMetricCard(
                    title: "移動距離",
                    current: String(format: "%.1f km", healthManager.walkingRunningDistanceKm),
                    target: String(format: "目標 %.1f km", distanceTargetKm),
                    progress: progressDistance,
                    icon: "location.fill",
                    tint: .green
                )
            }
        }
    }

    private var growthBonusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("進化ボーナス")
                .font(.headline)

            HStack(spacing: 12) {
                BonusCard(title: "所持スタンプ", value: "\(stampsStore.balance)", subtitle: "成長素材", tint: .teal)
                BonusCard(title: "今日の報酬", value: "開放中", subtitle: "ご褒美へ", tint: .purple)
            }

            NavigationLink {
                RewardView()
            } label: {
                HStack {
                    Text("ご褒美を確認する")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日の成長アクション")
                .font(.headline)

            ForEach(actionTips, id: \.self) { tip in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.teal.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "leaf.fill")
                                .foregroundColor(.teal)
                        )

                    Text(tip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
        }
    }

    private func triggerStampEffect() {
        showStampEffect = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showStampEffect = false
        }
    }

    private var yesterdayDeltaText: String? {
        guard let yesterdaySteps else { return nil }
        let delta = healthManager.steps - yesterdaySteps
        if delta == 0 { return "±0歩" }
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(delta)歩"
    }

    private var nextDayPreviewText: String {
        if growthProgress >= 1.0 {
            let boosted = Int(Double(stepTarget) * 1.05)
            return "明日は \(boosted)歩に挑戦しよう"
        }
        let remaining = max(0, stepTarget - healthManager.steps)
        return "明日はまず \(remaining)歩で芽を育てる"
    }

    private func loadYesterdaySteps() async {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else { return }
        let steps = await healthManager.stepsBetween(start: startOfYesterday, end: startOfToday)
        yesterdaySteps = steps
    }
}

private struct InfoChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}

private struct GrowthStat: View {
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

private struct GrowthMetricCard: View {
    let title: String
    let current: String
    let target: String
    let progress: Double
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(target)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(current)
                    .font(.subheadline.bold())
            }

            ProgressBar(progress: progress, accentColor: tint)
                .frame(height: 8)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

private struct BonusCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundColor(tint)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct GrowthAvatarBadge: View {
    let stageName: String
    let tint: Color
    let progress: Double
    let isMaxStage: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.22), Color(.systemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 128, height: 128)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.2), lineWidth: 2)
                )

            Circle()
                .trim(from: 0, to: max(0.08, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 120, height: 120)

            AvatarThumbnailView()
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .shadow(color: tint.opacity(0.25), radius: 8, x: 0, y: 4)

            if isMaxStage {
                Image(systemName: "crown.fill")
                    .font(.headline)
                    .foregroundColor(.yellow)
                    .offset(x: 36, y: -38)
            } else {
                Text(stageName)
                    .font(.caption.bold())
                    .foregroundColor(tint)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                    .offset(y: 48)
            }
        }
        .frame(width: 128, height: 128)
    }
}

// =========================
// ProgressBar Component
// =========================
struct ProgressBar: View {
    var progress: Double
    var accentColor: Color = .blue
    var showPercentage: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                Capsule()
                    .fill(accentColor)
                    .frame(width: geo.size.width * CGFloat(min(progress, 1.0)))
                if showPercentage {
                    HStack {
                        Spacer()
                        Text(String(format: "%d%%", Int(min(progress, 1.0) * 100)))
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct StampImpactOverlay: View {
    @State private var show = false

    var body: some View {
        ZStack {
            Color.black.opacity(show ? 0.25 : 0.0)
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 6)
                    .frame(width: 220, height: 220)
                    .scaleEffect(show ? 1.0 : 0.6)
                    .opacity(show ? 1.0 : 0.0)

                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 200, height: 200)
                    .scaleEffect(show ? 1.0 : 0.7)
                    .opacity(show ? 1.0 : 0.0)

                VStack(spacing: 6) {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 42, weight: .bold))
                    Text("STAMP")
                        .font(.title3.bold())
                }
                .foregroundColor(.red)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
                .rotationEffect(.degrees(show ? -8 : -24))
                .scaleEffect(show ? 1.0 : 0.6)
                .opacity(show ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                show = true
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.6)) {
                show = false
            }
        }
    }
}
