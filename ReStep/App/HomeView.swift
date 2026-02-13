import SwiftUI
import CoreLocation

struct HomeView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var session: AuthSession
    @StateObject private var healthManager = HealthKitManager.shared
    @EnvironmentObject private var statsSyncManager: StatsSyncManager
    @EnvironmentObject private var stampsStore: StampsStore
    @StateObject private var encounterManager = EncounterManager()
    @State private var myTraveler: Traveler?
    @State private var processedTravelerIds: Set<UUID> = []
    @AppStorage("restep.profile.height") private var heightCm: Double = 170
    @AppStorage("restep.profile.weight") private var weightKg: Double = 65
    @AppStorage("restep.profile.gender") private var gender: String = "男性"
    @AppStorage("restep.profile.birthday") private var birthdayRaw: String = ""
    @AppStorage("restep.goal.steps") private var stepTarget: Int = 5000
    @AppStorage("restep.goal.calories") private var calorieTarget: Int = 300
    @AppStorage("restep.goal.distanceKm") private var distanceTargetKm: Double = 3.0
    @AppStorage("restep.loginBonus.streak") private var loginBonusStreak: Int = 0
    @AppStorage("restep.loginBonus.lastClaimDate") private var loginBonusLastClaimDate: String = ""
    @AppStorage("restep.loginBonus.claimHistory") private var loginBonusClaimHistoryRaw: String = ""
    @State private var showLoginBonus = false
    @State private var loginBonusResult: LoginBonusResult?
    @State private var weeklySteps: [Int] = []
    @State private var streakDays: Int = 0
    @State private var showLoginCalendar = false
    @State private var useApiFallback = false
    @State private var apiSteps: Int = 0
    @State private var apiCalories: Int = 0
    @State private var apiDistanceKm: Double = 0
    @State private var statsNoticeMessage: String?

    private var localStreakFresh: Bool {
        guard let last = parseLocalDate(loginBonusLastClaimDate) else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: last)
        let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 999
        return diff == 0 || diff == 1
    }

    private var localStreakForDisplay: Int {
        localStreakFresh ? loginBonusStreak : 0
    }

    private var apiStreakFresh: Bool {
        guard let apiDate = statsSyncManager.continuityLastActiveDate,
              let last = parseApiDate(apiDate) else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: last)
        let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 999
        return diff == 0 || diff == 1
    }

    private var apiStreakForDisplay: Int {
        apiStreakFresh ? statsSyncManager.continuityDays : 0
    }

    private var loginContinuityDisplayDays: Int {
        max(apiStreakForDisplay, localStreakForDisplay)
    }

    private var loginContinuityDisplayDate: String {
        if apiStreakForDisplay >= localStreakForDisplay,
           let apiDate = statsSyncManager.continuityLastActiveDate,
           !apiDate.isEmpty {
            return apiDate
        }
        return formatLocalDate(loginBonusLastClaimDate) ?? "未記録"
    }

    private var mergedLoginDateKeys: Set<String> {
        claimHistoryDateKeys.union(inferredStreakDateKeys)
    }

    private var claimHistoryDateKeys: Set<String> {
        Set(
            loginBonusClaimHistoryRaw
                .split(separator: ",")
                .map { String($0) }
                .filter { $0.isEmpty == false }
        )
    }

    private var inferredStreakDateKeys: Set<String> {
        guard loginContinuityDisplayDays > 0 else { return [] }
        guard let last = parseApiDate(loginContinuityDisplayDate) else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: last)

        var keys: Set<String> = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"

        for offset in 0..<loginContinuityDisplayDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            keys.insert(formatter.string(from: date))
        }
        return keys
    }

    private var displaySteps: Int {
        useApiFallback ? apiSteps : healthManager.steps
    }

    private var displayCalories: Int {
        useApiFallback ? apiCalories : healthManager.activeCalories
    }

    private var displayDistanceKm: Double {
        useApiFallback ? apiDistanceKm : healthManager.walkingRunningDistanceKm
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.teal.opacity(0.18),
                        Color.blue.opacity(0.10),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if let notice = statsNoticeMessage {
                            NoticeBanner(text: notice)
                                .padding(.horizontal, 20)
                        }
                        heroAvatarSpotlight
                        topSummaryCard
                        growthFocusSection
                        weeklyMomentumSection
                        quickLinksSection

                        Spacer(minLength: 12)
                    }
                    .padding(.bottom, 20)
                }

                if showLoginBonus, let result = loginBonusResult {
                    LoginBonusOverlay(result: result) {
                        showLoginBonus = false
                    }
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .sheet(isPresented: $showLoginCalendar) {
                LoginCalendarSheet(
                    currentStreak: loginContinuityDisplayDays,
                    lastLoginDate: loginContinuityDisplayDate,
                    loggedDateKeys: mergedLoginDateKeys
                )
            }
            .task {
                await healthManager.requestAuthorization()
                healthManager.startObserving()
                locationManager.refreshIfEnabled()
                await statsSyncManager.syncIfNeeded(reason: "home", isLoggedIn: session.isLoggedIn)
                await statsSyncManager.refreshContinuity(isLoggedIn: session.isLoggedIn)
                await refreshDisplayStats()
                await loadWeeklySteps()
            }
            .refreshable {
                await healthManager.fetchTodayData()
                await statsSyncManager.syncIfNeeded(reason: "home_refresh", forceFetch: false, isLoggedIn: session.isLoggedIn)
                await statsSyncManager.refreshContinuity(isLoggedIn: session.isLoggedIn)
                await refreshDisplayStats()
                await loadWeeklySteps()
            }
            .onAppear {
                Task {
                    if let result = await LoginBonusManager.shared.checkAndGrant() {
                        await MainActor.run {
                            loginBonusResult = result
                            showLoginBonus = true
                        }
                    }
                }
                let all = GameStore.shared.loadEncounters()
                processedTravelerIds = Set(all.map { $0.traveler.id })
                if myTraveler == nil {
                    myTraveler = GameStore.shared.loadTravelers().first
                }
                encounterManager.start()
                if let traveler = myTraveler {
                    encounterManager.sendTraveler(traveler)
                }
            }
            .onDisappear {
                encounterManager.stop()
            }
            .onChange(of: encounterManager.nearbyTravelers) { _, newValue in
                for traveler in newValue where !processedTravelerIds.contains(traveler.id) {
                    addEncounter(traveler)
                }
            }
        }
    }

    private var topSummaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Steps
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.pink.opacity(0.8), Color(red: 0.86, green: 0.12, blue: 0.31)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)

                            Image(systemName: "figure.walk")
                                .font(.body)
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("歩数")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(displaySteps.formatted(.number))
                                    .font(.title2.bold())
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                Text("歩")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    ProgressBar(progress: Double(displaySteps) / Double(stepTarget), accentColor: .pink)
                        .frame(height: 6)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                )

                // Calories
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange.opacity(0.7), Color.orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)

                            Image(systemName: "flame.fill")
                                .font(.body)
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                        Text("アクティブ消費")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(displayCalories.formatted(.number))
                                    .font(.title2.bold())
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                Text("kcal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    ProgressBar(progress: Double(displayCalories) / Double(calorieTarget), accentColor: .orange)
                        .frame(height: 6)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                )
            }

            // Distance
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.7), Color.green],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)

                        Image(systemName: "location.fill")
                            .font(.body)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("移動距離")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", displayDistanceKm))
                                .font(.title2.bold())
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text("km")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                ProgressBar(progress: displayDistanceKm / distanceTargetKm, accentColor: .green)
                    .frame(height: 6)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
            )
        }
        .padding(.horizontal)
    }

    private var profileOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("身長 \(Int(heightCm)) cm")
            Text("体重 \(Int(weightKg)) kg")
            Text(String(format: "BMI %.1f", bmiValue))
            if let categoryText = bodyFatCategoryText {
                Text(categoryText)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var bmiValue: Double {
        BodyFatClassifier.bmiTrefethen(weightKg: weightKg, heightCm: heightCm)
    }

    private var bodyFatCategoryText: String? {
        guard let genderValue = BodyFatClassifier.parseGender(gender),
              let age = BodyFatClassifier.age(from: birthdayRaw),
              let percent = BodyFatClassifier.estimatedBodyFatPercent(
                gender: genderValue,
                age: age,
                weightKg: weightKg,
                heightCm: heightCm
              ) else {
            return nil
        }
        let category = BodyFatClassifier.category(gender: genderValue, age: age, percent: percent)
        return String(format: "体脂肪率(推定) %.1f%%  %@", percent, category)
    }
}

private extension HomeView {
    func addEncounter(_ traveler: Traveler) {
        var encounters = GameStore.shared.loadEncounters()
        let new = Encounter(traveler: traveler, source: .mpc)
        encounters.insert(new, at: 0)
        GameStore.shared.saveEncounters(encounters)

        var travelers = GameStore.shared.loadTravelers()
        if travelers.contains(where: { $0.id == traveler.id }) == false {
            travelers.append(traveler)
            GameStore.shared.saveTravelers(travelers)
        }
        processedTravelerIds.insert(traveler.id)
    }
}

private struct LoginBonusOverlay: View {
    let result: LoginBonusResult
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("ログインボーナス")
                    .font(.title3.bold())

                Text("連続ログイン \(result.streak) 日目")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Text("コイン +\(result.coins)")
                    .font(.title2.bold())
                    .foregroundColor(.orange)

                Button {
                    onClose()
                } label: {
                    Text("OK")
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan)
                        .clipShape(Capsule())
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 10)
        }
    }
}

private extension HomeView {
    func refreshDisplayStats() async {
        let shouldFallback = !healthManager.isAuthorized || healthManager.errorMessage != nil
        if !shouldFallback {
            useApiFallback = false
            statsNoticeMessage = nil
            return
        }

        guard session.isLoggedIn else {
            useApiFallback = false
            statsNoticeMessage = nil
            return
        }

        do {
            let response = try await statsSyncManager.fetchTodayStatsFromAPI(isLoggedIn: true)
            apiSteps = response.steps
            apiCalories = response.calories
            apiDistanceKm = response.distanceKm
            useApiFallback = true
            statsNoticeMessage = "HealthKitの取得に失敗したため、APIの値を表示しています。"
        } catch {
            useApiFallback = false
            statsNoticeMessage = nil
        }
    }

    func parseLocalDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "ja_JP")
        input.timeZone = TimeZone.current
        input.dateFormat = "yyyy-MM-dd"
        return input.date(from: raw)
    }

    func parseApiDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let input = DateFormatter()
        input.locale = Locale(identifier: "ja_JP")
        input.timeZone = TimeZone.current
        input.dateFormat = "yyyy/MM/dd"
        return input.date(from: raw)
    }

    func formatLocalDate(_ raw: String) -> String? {
        guard let date = parseLocalDate(raw) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "ja_JP")
        output.timeZone = TimeZone.current
        output.dateFormat = "yyyy/MM/dd"
        return output.string(from: date)
    }

    private var growthFocusSection: some View {
        let progress = growthProgress
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日の成長")
                    .font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.bold())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            ProgressBar(progress: progress, accentColor: .teal, showPercentage: true)
                .frame(height: 16)

            HStack(spacing: 8) {
                Image(systemName: focusIcon)
                    .foregroundColor(.teal)
                Text(focusText)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(focusHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
    }

    private var heroAvatarSpotlight: some View {
        let progress = growthProgress
        return ZStack {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 12)

                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 10)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)

                AvatarView(cameraDistanceMultiplier: 0.95)
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)

                VStack {
                    HStack {
                        InfoPill(text: "成長 \(Int(progress * 100))%")
                        Spacer()
                        Button {
                            showLoginCalendar = true
                        } label: {
                            InfoPill(text: "連続ログイン \(loginContinuityDisplayDays)日")
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    HStack {
                        InfoPill(text: focusText)
                        Spacer()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
        .overlay(alignment: .bottomTrailing) {
            profileOverlay
                .frame(maxWidth: 160, alignment: .trailing)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
    }

    private var weeklyMomentumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("週間モメンタム")
                    .font(.headline)
                Spacer()
                Text("目標 \(stepTarget)歩")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if weeklySteps.isEmpty {
                Text("データ取得中…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weeklySteps.indices, id: \.self) { index in
                        let steps = weeklySteps[index]
                        let ratio = min(1.0, Double(steps) / Double(max(1, stepTarget)))
                        VStack {
                            Capsule()
                                .fill(ratio >= 1.0 ? Color.teal : Color.gray.opacity(0.4))
                                .frame(width: 12, height: max(12, 64 * ratio))
                            Text(shortWeekday(offset: weeklySteps.count - 1 - index))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 20)
    }

    private var quickLinksSection: some View {
        HStack(spacing: 10) {
            NavigationLink {
                TargetView()
            } label: {
                HomeQuickLink(title: "成長", subtitle: "目標へ", icon: "leaf.fill", tint: .green)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            NavigationLink {
                RewardView()
            } label: {
                HomeQuickLink(title: "ご褒美", subtitle: "解放 \(stampsStore.balance)", icon: "crown.fill", tint: .orange)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            NavigationLink {
                EncounterGameSelectView()
            } label: {
                HomeQuickLink(title: "すれ違い", subtitle: "探索へ", icon: "person.2.fill", tint: .teal)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }

    private var growthProgress: Double {
        let step = stepTarget > 0 ? Double(displaySteps) / Double(stepTarget) : 0
        let cal = calorieTarget > 0 ? Double(displayCalories) / Double(calorieTarget) : 0
        let dist = distanceTargetKm > 0 ? displayDistanceKm / distanceTargetKm : 0
        return min(1.0, (step * 0.5) + (cal * 0.3) + (dist * 0.2))
    }

    private var focusMetric: FocusMetric {
        let step = stepTarget > 0 ? Double(displaySteps) / Double(stepTarget) : 0
        let cal = calorieTarget > 0 ? Double(displayCalories) / Double(calorieTarget) : 0
        let dist = distanceTargetKm > 0 ? displayDistanceKm / distanceTargetKm : 0
        let metrics: [(FocusMetric, Double)] = [(.steps, step), (.calories, cal), (.distance, dist)]
        return metrics.min(by: { $0.1 < $1.1 })?.0 ?? .steps
    }

    private var focusText: String {
        switch focusMetric {
        case .steps:
            return "あと少し歩こう"
        case .calories:
            return "軽く動いて消費を伸ばす"
        case .distance:
            return "遠回りで距離を稼ぐ"
        }
    }

    private var focusHint: String {
        switch focusMetric {
        case .steps:
            let remaining = max(0, stepTarget - displaySteps)
            return "残り \(remaining) 歩"
        case .calories:
            let remaining = max(0, calorieTarget - displayCalories)
            return "残り \(remaining) kcal"
        case .distance:
            let remaining = max(0, distanceTargetKm - displayDistanceKm)
            return String(format: "残り %.1f km", remaining)
        }
    }

    private var focusIcon: String {
        switch focusMetric {
        case .steps:
            return "figure.walk"
        case .calories:
            return "flame.fill"
        case .distance:
            return "location.fill"
        }
    }

    private func loadWeeklySteps() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var steps: [Int] = []
        for offset in (0..<7).reversed() {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let value = await healthManager.stepsBetween(start: start, end: end)
            steps.append(value)
        }
        weeklySteps = steps

        var streak = 0
        for value in steps.reversed() {
            if value >= stepTarget {
                streak += 1
            } else {
                break
            }
        }
        streakDays = streak
    }

    private func shortWeekday(offset: Int) -> String {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

private enum FocusMetric {
    case steps
    case calories
    case distance
}

private struct HomeQuickLink: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .font(.title3.bold())
            Text(title)
                .font(.subheadline.bold())
                .foregroundColor(.black)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.black.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemGray5), Color(.systemGray4), Color(.systemGray3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
                .shadow(color: Color.white.opacity(0.8), radius: 8, x: -4, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(2)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 24)
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .blendMode(.screen)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.right.circle.fill")
                .font(.caption)
                .foregroundColor(tint)
                .padding(8)
        }
    }
}

private struct InfoPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.primary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.systemBackground).opacity(0.9))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

private struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

private struct LoginCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentStreak: Int
    let lastLoginDate: String
    let loggedDateKeys: Set<String>
    @State private var displayMonth: Date
    @State private var selectedDetent: PresentationDetent = .medium

    private let rewards = [50, 60, 70, 80, 90, 100, 150]
    private let calendar = Calendar.current

    init(currentStreak: Int, lastLoginDate: String, loggedDateKeys: Set<String>) {
        self.currentStreak = currentStreak
        self.lastLoginDate = lastLoginDate
        self.loggedDateKeys = loggedDateKeys
        if let last = Self.parseDay(lastLoginDate) {
            _displayMonth = State(initialValue: Self.startOfMonth(last))
        } else {
            _displayMonth = State(initialValue: Self.startOfMonth(Date()))
        }
    }

    private var streakClamped: Int {
        max(0, min(currentStreak, rewards.count))
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayMonth)
    }

    private var weekdaySymbols: [String] {
        ["日", "月", "火", "水", "木", "金", "土"]
    }

    private var loggedDays: Set<Date> {
        Set(loggedDateKeys.compactMap { Self.parseDay($0) }.map { calendar.startOfDay(for: $0) })
    }

    private var monthCells: [Date?] {
        let start = Self.startOfMonth(displayMonth)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: start) // 1:Sunday

        var cells: [Date?] = Array(repeating: nil, count: max(0, firstWeekday - 1))
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var isExpanded: Bool {
        selectedDetent == .large
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.teal.opacity(0.2), Color.blue.opacity(0.15), Color(.systemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                // Keep the sheet title away from the very top edge when presented.
                Color.clear
                    .frame(height: 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ログインカレンダー")
                            .font(.title3.bold())
                        Text("最終ログイン \(lastLoginDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.bold())
                            .foregroundColor(.secondary)
                            .padding(10)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)

                HStack {
                    Text("上にスワイプで月別ログイン履歴")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(rewards.indices, id: \.self) { index in
                        let day = index + 1
                        let isClaimed = index < streakClamped
                        VStack(spacing: 8) {
                            Text("\(day)日目")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)

                                VStack(spacing: 6) {
                                    Image(systemName: isClaimed ? "checkmark.seal.fill" : "seal")
                                        .font(.title2)
                                        .foregroundColor(isClaimed ? .red : .gray)
                                    Text("+\(rewards[index])")
                                        .font(.caption.bold())
                                        .foregroundColor(.primary)
                                    Text("コイン")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 10)
                            }
                            .frame(height: 92)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Text("連続ログイン: \(currentStreak)日")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                if isExpanded {
                    VStack(spacing: 10) {
                        HStack {
                            Button {
                                if let previous = calendar.date(byAdding: .month, value: -1, to: displayMonth) {
                                    displayMonth = Self.startOfMonth(previous)
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Spacer()
                            Text(monthTitle)
                                .font(.headline)
                            Spacer()

                            Button {
                                if let next = calendar.date(byAdding: .month, value: 1, to: displayMonth) {
                                    displayMonth = Self.startOfMonth(next)
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        let calendarColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                        LazyVGrid(columns: calendarColumns, spacing: 8) {
                            ForEach(weekdaySymbols, id: \.self) { symbol in
                                Text(symbol)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                            }

                            ForEach(Array(monthCells.enumerated()), id: \.offset) { entry in
                                if let date = entry.element {
                                    let day = calendar.component(.day, from: date)
                                    let start = calendar.startOfDay(for: date)
                                    let isLogged = loggedDays.contains(start)
                                    let isToday = calendar.isDateInToday(start)

                                    ZStack {
                                        Circle()
                                            .fill(isLogged ? Color.teal.opacity(0.22) : Color.clear)
                                            .frame(width: 34, height: 34)
                                        if isLogged {
                                            Circle()
                                                .stroke(Color.teal, lineWidth: 1)
                                                .frame(width: 34, height: 34)
                                        } else if isToday {
                                            Circle()
                                                .stroke(Color.gray.opacity(0.45), lineWidth: 1)
                                                .frame(width: 34, height: 34)
                                        }
                                        Text("\(day)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                } else {
                                    Color.clear
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.teal.opacity(0.22))
                                .overlay(Circle().stroke(Color.teal, lineWidth: 1))
                                .frame(width: 14, height: 14)
                            Text("ログイン日")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground).opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func parseDay(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current

        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) { return date }

        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.date(from: value)
    }
}
#if DEBUG
@available(iOS 17, *)
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(AuthSession())
            .environmentObject(LocationManager())
    }
}
#endif
