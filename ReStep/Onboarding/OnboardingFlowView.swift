import SwiftUI
import CoreLocation
import CoreBluetooth
import UIKit
import HealthKit

enum OnboardingMode {
    case normal
    case debug
}

private enum OnboardingStep {
    case intro
    case permissions
    case profileBasics
    case goals
}

struct OnboardingFlowView: View {
    let mode: OnboardingMode
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @ObservedObject private var healthManager = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("restep.onboarding.completed") private var didCompleteOnboarding: Bool = false
    @AppStorage("restep.onboarding.userId") private var onboardedUserId: String = ""
    @State private var step: OnboardingStep = .intro
    @State private var didLoadDefaults = false
    @State private var isSaving = false

    @State private var nickname: String = ""
    @State private var birthdayDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var birthdayIsSet: Bool = false
    @State private var gender: String = "未設定"
    @State private var heightInt: Int = 170
    @State private var heightDecimal: Int = 0
    @State private var weightInt: Int = 60
    @State private var weightDecimal: Int = 0

    @State private var stepTarget: Int = 5000
    @State private var calorieTarget: Int = 300
    @State private var distanceTargetInt: Int = 3
    @State private var distanceTargetDecimal: Int = 0
    @State private var weeklySteps: Int = 200
    @State private var bodyFat: Int = 35
    @State private var weeklyExercise: Int = 1

    private let nicknameKey = "restep.profile.nickname"
    private let birthdayKey = "restep.profile.birthday"
    private let genderKey = "restep.profile.gender"
    private let heightKey = "restep.profile.height"
    private let weightKey = "restep.profile.weight"
    private let stepTargetKey = "restep.goal.steps"
    private let calorieTargetKey = "restep.goal.calories"
    private let distanceTargetKey = "restep.goal.distanceKm"
    private let weeklyStepsKey = "restep.profile.weeklySteps"
    private let bodyFatKey = "restep.profile.bodyFat"
    private let weeklyExerciseKey = "restep.profile.weeklyExercise"

    init(mode: OnboardingMode = .normal) {
        self.mode = mode
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            switch step {
            case .intro:
                OnboardingIntroView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        step = .permissions
                    }
                }

            case .permissions:
                OnboardingPermissionsView(
                    locationManager: locationManager,
                    notificationManager: notificationManager,
                    healthManager: healthManager,
                    onNext: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step = .profileBasics
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step = .profileBasics
                        }
                    }
                )

            case .profileBasics:
                OnboardingProfileBasicsView(
                    nickname: $nickname,
                    birthdayDate: $birthdayDate,
                    birthdayIsSet: $birthdayIsSet,
                    gender: $gender,
                    heightInt: $heightInt,
                    heightDecimal: $heightDecimal,
                    weightInt: $weightInt,
                    weightDecimal: $weightDecimal,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step = .intro
                        }
                    },
                    onNext: {
                        saveBasicsAndContinue()
                    },
                    onSkip: {
                        completeOnboarding()
                    }
                )

            case .goals:
                OnboardingGoalsView(
                    stepTarget: $stepTarget,
                    calorieTarget: $calorieTarget,
                    distanceTargetInt: $distanceTargetInt,
                    distanceTargetDecimal: $distanceTargetDecimal,
                    weeklySteps: $weeklySteps,
                    bodyFat: $bodyFat,
                    weeklyExercise: $weeklyExercise,
                    isSaving: isSaving,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            step = .profileBasics
                        }
                    },
                    onSkip: {
                        completeOnboarding()
                    },
                    onSave: {
                        saveAndComplete()
                    }
                )
            }
        }
        .onAppear {
            loadDefaultsIfNeeded()
        }
    }

    private func loadDefaultsIfNeeded() {
        guard didLoadDefaults == false else { return }
        didLoadDefaults = true

        let defaults = UserDefaults.standard
        nickname = defaults.string(forKey: nicknameKey) ?? ""

        let savedBirthday = defaults.string(forKey: birthdayKey) ?? ""
        if let parsed = parseBirthday(savedBirthday) {
            birthdayDate = parsed
            birthdayIsSet = true
        } else {
            birthdayIsSet = false
        }

        gender = defaults.string(forKey: genderKey) ?? "未設定"

        let savedHeight = defaults.double(forKey: heightKey)
        if savedHeight > 0 {
            let rounded = (savedHeight * 10).rounded()
            heightInt = Int(rounded) / 10
            heightDecimal = Int(rounded) % 10
        }

        let savedWeight = defaults.double(forKey: weightKey)
        if savedWeight > 0 {
            let rounded = (savedWeight * 10).rounded()
            weightInt = Int(rounded) / 10
            weightDecimal = Int(rounded) % 10
        }

        let savedStepTarget = defaults.integer(forKey: stepTargetKey)
        if savedStepTarget > 0 { stepTarget = savedStepTarget }
        let savedCalorieTarget = defaults.integer(forKey: calorieTargetKey)
        if savedCalorieTarget > 0 { calorieTarget = savedCalorieTarget }
        let savedDistanceTarget = defaults.double(forKey: distanceTargetKey)
        if savedDistanceTarget > 0 {
            let rounded = (savedDistanceTarget * 10).rounded()
            distanceTargetInt = Int(rounded) / 10
            distanceTargetDecimal = Int(rounded) % 10
        }

        let savedWeeklySteps = defaults.integer(forKey: weeklyStepsKey)
        if savedWeeklySteps > 0 { weeklySteps = savedWeeklySteps }
        let savedBodyFat = defaults.integer(forKey: bodyFatKey)
        if savedBodyFat > 0 { bodyFat = savedBodyFat }
        let savedWeeklyExercise = defaults.integer(forKey: weeklyExerciseKey)
        if savedWeeklyExercise > 0 { weeklyExercise = savedWeeklyExercise }
    }

    private func saveAndComplete() {
        guard isSaving == false else { return }
        isSaving = true

        let defaults = UserDefaults.standard
        defaults.set(stepTarget, forKey: stepTargetKey)
        defaults.set(calorieTarget, forKey: calorieTargetKey)
        let distanceValue = Double(distanceTargetInt) + (Double(distanceTargetDecimal) / 10.0)
        defaults.set(distanceValue, forKey: distanceTargetKey)
        defaults.set(weeklySteps, forKey: weeklyStepsKey)
        defaults.set(bodyFat, forKey: bodyFatKey)
        defaults.set(weeklyExercise, forKey: weeklyExerciseKey)

        Task {
            let payload = UserProfileDetails(
                nickname: nil,
                birthday: nil,
                gender: nil,
                heightCm: nil,
                weightKg: nil,
                weeklySteps: weeklySteps,
                bodyFat: bodyFat,
                weeklyExercise: weeklyExercise,
                goalSteps: stepTarget,
                goalCalories: calorieTarget,
                goalDistanceKm: distanceValue,
                updatedAt: nil
            )
            _ = try? await UserAPIClient.shared.updateUserProfile(payload)

            await MainActor.run {
                isSaving = false
            }
        }

        completeOnboarding()
    }

    private func parseBirthday(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.date(from: trimmed)
    }

    private func saveBasicsAndContinue() {
        persistBasicsToDefaults()
        Task { await sendBasicsToServer() }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = .goals
        }
    }

    private func persistBasicsToDefaults() {
        let defaults = UserDefaults.standard
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNickname.isEmpty {
            defaults.removeObject(forKey: nicknameKey)
        } else {
            defaults.set(trimmedNickname, forKey: nicknameKey)
        }

        if birthdayIsSet {
            defaults.set(formatBirthday(birthdayDate), forKey: birthdayKey)
        } else {
            defaults.removeObject(forKey: birthdayKey)
        }

        defaults.set(gender, forKey: genderKey)

        let heightValue = Double(heightInt) + (Double(heightDecimal) / 10.0)
        let weightValue = Double(weightInt) + (Double(weightDecimal) / 10.0)
        defaults.set(heightValue, forKey: heightKey)
        defaults.set(weightValue, forKey: weightKey)
    }

    private func sendBasicsToServer() async {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let heightValue = Double(heightInt) + (Double(heightDecimal) / 10.0)
        let weightValue = Double(weightInt) + (Double(weightDecimal) / 10.0)
        let payload = UserProfileDetails(
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            birthday: birthdayIsSet ? formatBirthday(birthdayDate) : nil,
            gender: gender == "未設定" ? nil : gender,
            heightCm: heightValue,
            weightKg: weightValue,
            weeklySteps: nil,
            bodyFat: nil,
            weeklyExercise: nil,
            goalSteps: nil,
            goalCalories: nil,
            goalDistanceKm: nil,
            updatedAt: nil
        )
        _ = try? await UserAPIClient.shared.updateUserProfile(payload)

        var fieldsToClear: [String] = []
        if trimmedNickname.isEmpty { fieldsToClear.append("nickname") }
        if birthdayIsSet == false { fieldsToClear.append("birthday") }
        if gender == "未設定" { fieldsToClear.append("gender") }
        if fieldsToClear.isEmpty == false {
            _ = try? await UserAPIClient.shared.clearUserProfileFields(fieldsToClear)
        }
    }

    private func completeOnboarding() {
        switch mode {
        case .normal:
            if let loginId = session.user?.loginId, loginId.isEmpty == false {
                onboardedUserId = loginId
            }
            didCompleteOnboarding = true
        case .debug:
            dismiss()
        }
    }
}

private struct OnboardingPermissionsView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var healthManager: HealthKitManager
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showSkipAlert = false
    @State private var bluetoothDiagnostics = BluetoothDiagnosticsManager()

#if DEBUG
    private func debugLog(_ label: String) {
        print("[Permissions] \(label)")
    }
#endif

    private var isLocationAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private var isNotificationAuthorized: Bool {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "許可済み"
        case .denied, .restricted:
            return "許可されていません"
        case .notDetermined:
            return "未許可"
        @unknown default:
            return "未確認"
        }
    }

    private var notificationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "許可済み"
        case .denied:
            return "許可されていません"
        case .notDetermined:
            return "未許可"
        @unknown default:
            return "未確認"
        }
    }

    private var healthStatusText: String {
        guard healthManager.isHealthKitAvailable else { return "非対応" }
        switch healthManager.requestStatus {
        case .unnecessary:
            return "設定済み"
        case .shouldRequest:
            return "未許可"
        case .unknown:
            return "未確認"
        @unknown default:
            return "未確認"
        }
    }

    private var healthActionTitle: String {
        guard healthManager.isHealthKitAvailable else { return "非対応" }
        switch healthManager.requestStatus {
        case .unnecessary:
            return "許可済み"
        case .shouldRequest:
            return "許可する"
        case .unknown:
            return "許可を確認"
        @unknown default:
            return "許可を確認"
        }
    }

    private var isHealthActionEnabled: Bool {
        guard healthManager.isHealthKitAvailable else { return false }
        switch healthManager.requestStatus {
        case .unnecessary:
            return false
        case .shouldRequest, .unknown:
            return true
        @unknown default:
            return true
        }
    }

    private var bluetoothStatusText: String {
        switch bluetoothDiagnostics.authorization {
        case .allowedAlways:
            return "許可済み"
        case .denied:
            return "許可されていません"
        case .restricted:
            return "制限あり"
        case .notDetermined:
            return "未許可"
        @unknown default:
            return "未確認"
        }
    }

    private var isBluetoothAuthorized: Bool {
        bluetoothDiagnostics.authorization == .allowedAlways
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("必要な権限を許可")
                    .font(.title2.bold())
                Text("歩数や位置情報、通知を使って体験を向上させます。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)

            ScrollView {
                VStack(spacing: 12) {
                    PermissionCard(
                        icon: "location.fill",
                        title: "位置情報",
                        message: "近くのchocoZAP検索やスタンプ付与に使用します。",
                        statusText: locationStatusText,
                        actionTitle: isLocationAuthorized ? "許可済み" : "許可する",
                        isActionEnabled: isLocationAuthorized == false
                    ) {
                        locationManager.isEnabled = true
                        locationManager.requestPermission()
                    }

                    PermissionCard(
                        icon: "bell.fill",
                        title: "通知",
                        message: "スタンプ付与やすれ違い通知を受け取れます。",
                        statusText: notificationStatusText,
                        actionTitle: isNotificationAuthorized ? "許可済み" : "許可する",
                        isActionEnabled: isNotificationAuthorized == false
                    ) {
                        notificationManager.isEnabled = true
                    }

                    PermissionCard(
                        icon: "heart.fill",
                        title: "ヘルスケア",
                        message: "歩数・消費カロリーなどの取得に使用します。",
                        statusText: healthStatusText,
                        actionTitle: healthActionTitle,
                        isActionEnabled: isHealthActionEnabled
                    ) {
                        Task { await healthManager.requestAuthorization() }
                    }

                    PermissionCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Bluetooth",
                        message: "すれ違い機能で近くのユーザーを検出するために使用します。",
                        statusText: bluetoothStatusText,
                        actionTitle: isBluetoothAuthorized ? "許可済み" : "許可する",
                        isActionEnabled: isBluetoothAuthorized == false
                    ) {
                        bluetoothDiagnostics.start()
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color(red: 0.55, green: 0.90, blue: 0.95), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                )
                .padding(.horizontal, 26)
                .padding(.top, 20)
            }

            VStack(spacing: 10) {
                Button(action: onNext) {
                    Text("次へ")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.45, green: 0.80, blue: 0.92))
                        .clipShape(Capsule())
                }

                Button {
                    showSkipAlert = true
                } label: {
                    Text("あとで設定する")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onAppear {
            Task { await notificationManager.refreshAuthorizationStatus() }
            healthManager.refreshAuthorizationStatus()
#if DEBUG
            debugLog("onAppear location=\(locationManager.authorizationStatus) notification=\(notificationManager.authorizationStatus) health=\(healthManager.authorizationState) requestStatus=\(healthManager.requestStatus) bluetooth=\(bluetoothDiagnostics.authorization)")
#endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await notificationManager.refreshAuthorizationStatus() }
            healthManager.refreshAuthorizationStatus()
#if DEBUG
            debugLog("foreground location=\(locationManager.authorizationStatus) notification=\(notificationManager.authorizationStatus) health=\(healthManager.authorizationState) requestStatus=\(healthManager.requestStatus) bluetooth=\(bluetoothDiagnostics.authorization)")
#endif
        }
#if DEBUG
        .onChange(of: locationManager.authorizationStatus) { _, newValue in
            debugLog("location changed -> \(newValue)")
        }
        .onChange(of: notificationManager.authorizationStatus) { _, newValue in
            debugLog("notification changed -> \(newValue)")
        }
        .onChange(of: healthManager.authorizationState) { _, newValue in
            debugLog("health changed -> \(newValue)")
        }
        .onChange(of: bluetoothDiagnostics.authorization) { _, newValue in
            debugLog("bluetooth changed -> \(newValue)")
        }
#endif
        .alert("あとで設定する", isPresented: $showSkipAlert) {
            Button("OK") {
                onSkip()
            }
        } message: {
            Text("必要に応じて、iOSの設定またはアプリ内設定から変更できます。")
        }
    }
}

private struct OnboardingIntroView: View {
    let onNext: () -> Void

    private let features: [OnboardingFeature] = [
        OnboardingFeature(
            icon: "figure.walk",
            title: "歩数・消費・距離を可視化",
            message: "毎日の活動量をまとめてチェックできます。"
        ),
        OnboardingFeature(
            icon: "sparkles",
            title: "アバターとスタンプで継続",
            message: "続けるほど育つ体験で習慣化を後押し。"
        ),
        OnboardingFeature(
            icon: "person.2.circle",
            title: "すれ違いで出会い",
            message: "近くのユーザーと楽しくモチベーション共有。"
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.93, blue: 0.98),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("ReStepへようこそ")
                        .font(.largeTitle.bold())
                        .foregroundColor(.primary)
                    Text("毎日の一歩を、見える成果に。")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(features) { feature in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(width: 44, height: 44)
                                Image(systemName: feature.icon)
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.15, green: 0.45, blue: 0.65))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(feature.message)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
                        )
                    }
                }

                Spacer(minLength: 12)

                Button(action: onNext) {
                    Text("次へ")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.45, green: 0.80, blue: 0.92))
                        .clipShape(Capsule())
                        .shadow(radius: 2, y: 2)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 40)
        }
    }
}

private struct OnboardingProfileBasicsView: View {
    @Binding var nickname: String
    @Binding var birthdayDate: Date
    @Binding var birthdayIsSet: Bool
    @Binding var gender: String
    @Binding var heightInt: Int
    @Binding var heightDecimal: Int
    @Binding var weightInt: Int
    @Binding var weightDecimal: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var activePicker: BasicsPicker?
    @State private var showSkipAlert = false
    @State private var tempHeightInt: Int = 170
    @State private var tempHeightDecimal: Int = 0
    @State private var tempWeightInt: Int = 60
    @State private var tempWeightDecimal: Int = 0
    @State private var tempBirthdayDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()

    private var heightDisplay: String { "\(heightInt).\(heightDecimal)" }
    private var weightDisplay: String { "\(weightInt).\(weightDecimal)" }
    private var birthdayDisplay: String { formatBirthday(birthdayDate) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                }
                .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: 0)

                        VStack(spacing: 18) {
                            VStack(spacing: 8) {
                                Text("プロフィール設定")
                                    .font(.title2.bold())
                                Text("身長・体重は消費カロリーやアバターに反映されます。")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 10)

                            VStack(spacing: 12) {
                                ProfileIconTextField(
                                    systemImage: "person",
                                    placeholder: "ニックネーム(任意)",
                                    text: $nickname
                                )

                                ProfileSelectRow(
                                    systemImage: "calendar",
                                    title: "生年月日(任意)",
                                    value: birthdayIsSet ? birthdayDisplay : "未設定"
                                ) {
                                    activePicker = .birthday
                                }

                                ProfileIconRow(systemImage: "person.2") {
                                    Picker("性別", selection: $gender) {
                                        Text("未設定").tag("未設定")
                                        Text("男性").tag("男性")
                                        Text("女性").tag("女性")
//                                        Text("その他").tag("その他")
                                    }
                                    .pickerStyle(.segmented)
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                ProfileSelectRow(
                                    systemImage: "ruler",
                                    title: "身長",
                                    value: "\(heightDisplay) cm"
                                ) {
                                    activePicker = .height
                                }

                                ProfileSelectRow(
                                    systemImage: "scalemass",
                                    title: "体重",
                                    value: "\(weightDisplay) kg"
                                ) {
                                    activePicker = .weight
                                }
                            }

                            Text("内容はあとで変更できます")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                        }
                        .padding(22)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(Color(red: 0.55, green: 0.90, blue: 0.95), lineWidth: 2)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                        )
                        .padding(.horizontal, 26)
                        .padding(.top, 12)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }

            VStack(spacing: 10) {
                Button(action: onNext) {
                    Text("次へ")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.45, green: 0.80, blue: 0.92))
                        .clipShape(Capsule())
                }

                Button {
                    showSkipAlert = true
                } label: {
                    Text("あとで設定する")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onChange(of: activePicker) { _, newValue in
            guard newValue != nil else { return }
            tempBirthdayDate = birthdayDate
            tempHeightInt = heightInt
            tempHeightDecimal = heightDecimal
            tempWeightInt = weightInt
            tempWeightDecimal = weightDecimal
        }
        .overlay {
            if let picker = activePicker {
                pickerSheet(for: picker)
            }
        }
        .alert("あとで設定する", isPresented: $showSkipAlert) {
            Button("OK") {
                onSkip()
            }
        } message: {
            Text("設定 > プロフィール からいつでも変更できます。")
        }
    }

    @ViewBuilder
    private func pickerSheet(for picker: BasicsPicker) -> some View {
        switch picker {
        case .birthday:
            PickerModal(
                title: "生年月日",
                onCancel: { activePicker = nil },
                onDone: {
                    birthdayDate = tempBirthdayDate
                    birthdayIsSet = true
                    activePicker = nil
                }
            ) {
                DatePicker(
                    "生年月日",
                    selection: $tempBirthdayDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .datePickerStyle(.wheel)
                .labelsHidden()

                Button {
                    birthdayIsSet = false
                    activePicker = nil
                } label: {
                    Text("生年月日を削除")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                }
            }

        case .height:
            PickerModal(
                title: "身長",
                onCancel: { activePicker = nil },
                onDone: {
                    heightInt = tempHeightInt
                    heightDecimal = tempHeightDecimal
                    activePicker = nil
                }
            ) {
                HStack(spacing: 0) {
                    Picker("身長", selection: $tempHeightInt) {
                        ForEach(120...220, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Text(".")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)

                    Picker("小数", selection: $tempHeightDecimal) {
                        ForEach(0...9, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Text("cm")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.leading, 6)
                }
            }

        case .weight:
            PickerModal(
                title: "体重",
                onCancel: { activePicker = nil },
                onDone: {
                    weightInt = tempWeightInt
                    weightDecimal = tempWeightDecimal
                    activePicker = nil
                }
            ) {
                HStack(spacing: 0) {
                    Picker("体重", selection: $tempWeightInt) {
                        ForEach(20...200, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Text(".")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)

                    Picker("小数", selection: $tempWeightDecimal) {
                        ForEach(0...9, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Text("kg")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.leading, 6)
                }
            }
        }
    }
}

private struct OnboardingGoalsView: View {
    @Binding var stepTarget: Int
    @Binding var calorieTarget: Int
    @Binding var distanceTargetInt: Int
    @Binding var distanceTargetDecimal: Int
    @Binding var weeklySteps: Int
    @Binding var bodyFat: Int
    @Binding var weeklyExercise: Int
    let isSaving: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onSave: () -> Void

    @State private var activePicker: GoalsPicker?
    @State private var showSkipAlert = false
    @State private var tempStepTarget: Int = 5000
    @State private var tempCalorieTarget: Int = 300
    @State private var tempDistanceTargetInt: Int = 3
    @State private var tempDistanceTargetDecimal: Int = 0
    @State private var tempWeeklySteps: Int = 200
    @State private var tempBodyFat: Int = 35
    @State private var tempWeeklyExercise: Int = 1

    private var distanceTargetDisplay: String { "\(distanceTargetInt).\(distanceTargetDecimal)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                }
                .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: 0)

                        VStack(spacing: 18) {
                            VStack(spacing: 8) {
                                Text("目標設定")
                                    .font(.title2.bold())
                                Text("無理のない目標から始めましょう。")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 10)

                            VStack(spacing: 12) {
                                ProfileSelectRow(
                                    systemImage: "figure.walk",
                                    title: "歩数目標",
                                    value: "\(stepTarget) 歩"
                                ) {
                                    activePicker = .stepTarget
                                }

                                ProfileSelectRow(
                                    systemImage: "flame.fill",
                                    title: "消費カロリー目標",
                                    value: "\(calorieTarget) kcal"
                                ) {
                                    activePicker = .calorieTarget
                                }

                                ProfileSelectRow(
                                    systemImage: "location.fill",
                                    title: "移動距離目標",
                                    value: "\(distanceTargetDisplay) km"
                                ) {
                                    activePicker = .distanceTarget
                                }

                                ProfileSelectRow(
                                    systemImage: "figure.walk",
                                    title: "一週間の平均歩数",
                                    value: "\(weeklySteps) 歩"
                                ) {
                                    activePicker = .weeklySteps
                                }

                                ProfileSelectRow(
                                    systemImage: "percent",
                                    title: "目標体脂肪率",
                                    value: "\(bodyFat) %"
                                ) {
                                    activePicker = .bodyFat
                                }

                                ProfileSelectRow(
                                    systemImage: "calendar.badge.clock",
                                    title: "一週間の運動回数",
                                    value: "\(weeklyExercise) 回"
                                ) {
                                    activePicker = .weeklyExercise
                                }
                            }
                        }
                        .padding(22)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(Color(red: 0.55, green: 0.90, blue: 0.95), lineWidth: 2)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                        )
                        .padding(.horizontal, 26)
                        .padding(.top, 12)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }

            VStack(spacing: 10) {
                Button(action: onSave) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("保存してはじめる")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.45, green: 0.80, blue: 0.92))
                    .clipShape(Capsule())
                }
                .disabled(isSaving)

                Button {
                    showSkipAlert = true
                } label: {
                    Text("あとで設定する")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .onChange(of: activePicker) { _, newValue in
            guard newValue != nil else { return }
            tempStepTarget = stepTarget
            tempCalorieTarget = calorieTarget
            tempDistanceTargetInt = distanceTargetInt
            tempDistanceTargetDecimal = distanceTargetDecimal
            tempWeeklySteps = weeklySteps
            tempBodyFat = bodyFat
            tempWeeklyExercise = weeklyExercise
        }
        .overlay {
            if let picker = activePicker {
                pickerSheet(for: picker)
            }
        }
        .alert("あとで設定する", isPresented: $showSkipAlert) {
            Button("OK") {
                onSkip()
            }
        } message: {
            Text("設定 > プロフィール からいつでも変更できます。")
        }
    }

    @ViewBuilder
    private func pickerSheet(for picker: GoalsPicker) -> some View {
        switch picker {
        case .stepTarget:
            PickerModal(
                title: "歩数目標",
                onCancel: { activePicker = nil },
                onDone: {
                    stepTarget = tempStepTarget
                    activePicker = nil
                }
            ) {
                Picker("歩数目標", selection: $tempStepTarget) {
                    let values = Array(stride(from: 1000, through: 50000, by: 500))
                    ForEach(values, id: \.self) { value in
                        Text("\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }

        case .calorieTarget:
            PickerModal(
                title: "消費カロリー目標",
                onCancel: { activePicker = nil },
                onDone: {
                    calorieTarget = tempCalorieTarget
                    activePicker = nil
                }
            ) {
                Picker("消費カロリー目標", selection: $tempCalorieTarget) {
                    let values = Array(stride(from: 100, through: 2000, by: 50))
                    ForEach(values, id: \.self) { value in
                        Text("\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }

        case .distanceTarget:
            PickerModal(
                title: "移動距離目標",
                onCancel: { activePicker = nil },
                onDone: {
                    distanceTargetInt = tempDistanceTargetInt
                    distanceTargetDecimal = tempDistanceTargetDecimal
                    activePicker = nil
                }
            ) {
                HStack(spacing: 0) {
                    Picker("距離", selection: $tempDistanceTargetInt) {
                        ForEach(0...50, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Text(".")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)

                    Picker("小数", selection: $tempDistanceTargetDecimal) {
                        ForEach(0...9, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Text("km")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.leading, 6)
                }
            }

        case .weeklySteps:
            PickerModal(
                title: "一週間の平均歩数",
                onCancel: { activePicker = nil },
                onDone: {
                    weeklySteps = tempWeeklySteps
                    activePicker = nil
                }
            ) {
                Picker("歩数", selection: $tempWeeklySteps) {
                    let values = Array(stride(from: 100, through: 30000, by: 100))
                    ForEach(values, id: \.self) { value in
                        Text("\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }

        case .bodyFat:
            PickerModal(
                title: "目標体脂肪率",
                onCancel: { activePicker = nil },
                onDone: {
                    bodyFat = tempBodyFat
                    activePicker = nil
                }
            ) {
                Picker("体脂肪率", selection: $tempBodyFat) {
                    ForEach(5...50, id: \.self) { value in
                        Text("\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }

        case .weeklyExercise:
            PickerModal(
                title: "一週間の運動回数",
                onCancel: { activePicker = nil },
                onDone: {
                    weeklyExercise = tempWeeklyExercise
                    activePicker = nil
                }
            ) {
                Picker("回数", selection: $tempWeeklyExercise) {
                    ForEach(0...14, id: \.self) { value in
                        Text("\(value)")
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }
        }
    }
}

private struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
}

private enum BasicsPicker: Identifiable {
    case birthday
    case height
    case weight

    var id: String {
        switch self {
        case .birthday: return "birthday"
        case .height: return "height"
        case .weight: return "weight"
        }
    }
}

private enum GoalsPicker: Identifiable {
    case stepTarget
    case calorieTarget
    case distanceTarget
    case weeklySteps
    case bodyFat
    case weeklyExercise

    var id: String {
        switch self {
        case .stepTarget: return "stepTarget"
        case .calorieTarget: return "calorieTarget"
        case .distanceTarget: return "distanceTarget"
        case .weeklySteps: return "weeklySteps"
        case .bodyFat: return "bodyFat"
        case .weeklyExercise: return "weeklyExercise"
        }
    }
}

private func formatBirthday(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    formatter.locale = Locale(identifier: "ja_JP")
    return formatter.string(from: date)
}

private struct PickerModal<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    let onDone: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)

                content
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)

                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("キャンセル")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }

                    Button(action: onDone) {
                        Text("OK")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.45, green: 0.80, blue: 0.92))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color(.systemGray3), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.25), radius: 16, x: 0, y: 8)
        }
    }
}

private struct ProfileIconRow<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(.gray)
                .frame(width: 22)
            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        )
    }
}

private struct ProfileIconTextField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        ProfileIconRow(systemImage: systemImage) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
    }
}

private struct GenderOption: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .clipShape(Capsule())
    }
}

private struct ProfileSelectRow: View {
    let systemImage: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileIconRow(systemImage: systemImage) {
                HStack {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(value)
                            .font(.body)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.bold))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let message: String
    let statusText: String
    let actionTitle: String
    let isActionEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(Color(red: 0.15, green: 0.45, blue: 0.65))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statusText == "許可済み" ? .green : .secondary)
                }

                Spacer()
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: action) {
                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isActionEnabled ? Color(red: 0.45, green: 0.80, blue: 0.92) : Color(.systemGray3))
                    .clipShape(Capsule())
            }
            .disabled(isActionEnabled == false)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}
