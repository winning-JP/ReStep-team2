import SwiftUI

enum ProfileField {
    case nickname
}

enum ProfilePicker: Identifiable {
    case birthday
    case height
    case weight
    case stepTarget
    case calorieTarget
    case distanceTarget
    case weeklySteps
    case bodyFat
    case weeklyExercise

    var id: String {
        switch self {
        case .birthday: return "birthday"
        case .height: return "height"
        case .weight: return "weight"
        case .stepTarget: return "stepTarget"
        case .calorieTarget: return "calorieTarget"
        case .distanceTarget: return "distanceTarget"
        case .weeklySteps: return "weeklySteps"
        case .bodyFat: return "bodyFat"
        case .weeklyExercise: return "weeklyExercise"
        }
    }
}

struct ProfileView: View {
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

    @State private var showSavedAlert = false
    @State private var activePicker: ProfilePicker?
    @State private var tempHeightInt: Int = 170
    @State private var tempHeightDecimal: Int = 0
    @State private var tempWeightInt: Int = 60
    @State private var tempWeightDecimal: Int = 0
    @State private var tempWeeklySteps: Int = 200
    @State private var tempBodyFat: Int = 35
    @State private var tempWeeklyExercise: Int = 1
    @State private var tempBirthdayDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var tempStepTarget: Int = 5000
    @State private var tempCalorieTarget: Int = 300
    @State private var tempDistanceTargetInt: Int = 3
    @State private var tempDistanceTargetDecimal: Int = 0
    @FocusState private var focusedField: ProfileField?
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardAlert = false
    @State private var initialSnapshot = ProfileSnapshot()

    private let saveColor = Color(red: 0.45, green: 0.80, blue: 0.92)
    @Environment(\.colorScheme) private var colorScheme

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

    private var weightDisplay: String { "\(weightInt).\(weightDecimal)" }
    private var heightDisplay: String { "\(heightInt).\(heightDecimal)" }
    private var distanceTargetDisplay: String { "\(distanceTargetInt).\(distanceTargetDecimal)" }
    private var birthdayDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: birthdayDate)
    }
    private var hasBirthday: Bool {
        birthdayIsSet
    }
    private var heightMeters: Double {
        (Double(heightInt) + Double(heightDecimal) / 10.0) / 100.0
    }
    private var weightValue: Double { Double(weightInt) + Double(weightDecimal) / 10.0 }
    private var distanceTargetValue: Double {
        Double(distanceTargetInt) + Double(distanceTargetDecimal) / 10.0
    }
    private var bmiValue: Double {
        BodyFatClassifier.bmiTrefethen(weightKg: weightValue, heightCm: Double(heightInt) + Double(heightDecimal) / 10.0)
    }
    private var bodyFatCategoryText: String? {
        guard let genderValue = BodyFatClassifier.parseGender(gender),
              let age = BodyFatClassifier.age(from: UserDefaults.standard.string(forKey: birthdayKey) ?? ""),
              let percent = BodyFatClassifier.estimatedBodyFatPercent(
                gender: genderValue,
                age: age,
                weightKg: weightValue,
                heightCm: Double(heightInt) + Double(heightDecimal) / 10.0
              ) else {
            return nil
        }
        let category = BodyFatClassifier.category(gender: genderValue, age: age, percent: percent)
        return String(format: "体脂肪率(推定) %.1f%%  %@", percent, category)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack {
                    VStack(spacing: 18) {
                        Text("プロフィール変更")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.top, 6)

                        VStack(spacing: 12) {
                            ProfileIconTextField(
                                systemImage: "person",
                                placeholder: "ニックネーム(任意)",
                                text: $nickname
                            )
                            .focused($focusedField, equals: .nickname)

                            ProfileSelectRow(
                                systemImage: "calendar",
                                title: "生年月日(任意)",
                                value: hasBirthday ? birthdayDisplay : "未設定"
                            ) {
                                activePicker = .birthday
                            }

                            ProfileIconRow(systemImage: "person.2") {
                                Picker("性別", selection: $gender) {
                                    Text("未設定").tag("未設定")
                                    Text("男性").tag("男性")
                                    Text("女性").tag("女性")
//                                    Text("その他").tag("その他")
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

                        Divider()

                        Text("目標設定")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)

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

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "BMI  %.1f", bmiValue))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            if let text = bodyFatCategoryText {
                                Text(text)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                            } else {
                                Text("年齢・性別・体脂肪率を設定すると判定できます")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            saveProfile()
                        } label: {
                            Text("変更を保存")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(saveColor)
                                .clipShape(Capsule())
                                .shadow(radius: 2, y: 2)
                        }
                        .padding(.top, 4)

                        Text("内容はあとで変更できます")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 4)
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 28)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28)
                                    .stroke(Color(red: 0.55, green: 0.90, blue: 0.95).opacity(colorScheme == .dark ? 0.5 : 1.0), lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 12, x: 0, y: 6)
                    )
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                }
            }

            if let picker = activePicker {
                pickerSheet(for: picker)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if hasUnsavedChanges {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .alert("保存しました", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        }
        .alert("変更を保存しますか？", isPresented: $showDiscardAlert) {
            Button("保存して戻る") {
                saveProfile()
                dismiss()
            }
            Button("保存しない") {
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
        .onAppear {
            let savedNickname = UserDefaults.standard.string(forKey: nicknameKey) ?? ""
            nickname = savedNickname
            let savedBirthday = UserDefaults.standard.string(forKey: birthdayKey) ?? ""
            if let parsed = parseBirthday(savedBirthday) {
                birthdayDate = parsed
                birthdayIsSet = true
            } else {
                birthdayIsSet = false
            }
            let savedGender = UserDefaults.standard.string(forKey: genderKey) ?? "未設定"
            gender = savedGender

            let savedHeight = UserDefaults.standard.double(forKey: heightKey)
            if savedHeight > 0 {
                let rounded = (savedHeight * 10).rounded()
                heightInt = Int(rounded) / 10
                heightDecimal = Int(rounded) % 10
            }

            let savedWeight = UserDefaults.standard.double(forKey: weightKey)
            if savedWeight > 0 {
                let rounded = (savedWeight * 10).rounded()
                weightInt = Int(rounded) / 10
                weightDecimal = Int(rounded) % 10
            }

            let savedStepTarget = UserDefaults.standard.integer(forKey: stepTargetKey)
            if savedStepTarget > 0 { stepTarget = savedStepTarget }
            let savedCalorieTarget = UserDefaults.standard.integer(forKey: calorieTargetKey)
            if savedCalorieTarget > 0 { calorieTarget = savedCalorieTarget }
            let savedDistanceTarget = UserDefaults.standard.double(forKey: distanceTargetKey)
            if savedDistanceTarget > 0 {
                let rounded = (savedDistanceTarget * 10).rounded()
                distanceTargetInt = Int(rounded) / 10
                distanceTargetDecimal = Int(rounded) % 10
            }

            let savedWeeklySteps = UserDefaults.standard.integer(forKey: weeklyStepsKey)
            if savedWeeklySteps > 0 { weeklySteps = savedWeeklySteps }
            let savedBodyFat = UserDefaults.standard.integer(forKey: bodyFatKey)
            if savedBodyFat > 0 { bodyFat = savedBodyFat }
            let savedWeeklyExercise = UserDefaults.standard.integer(forKey: weeklyExerciseKey)
            if savedWeeklyExercise > 0 { weeklyExercise = savedWeeklyExercise }
            Task { await refreshFromServer() }
            initialSnapshot = currentSnapshot()
        }
        .onChange(of: activePicker) { _, newValue in
            guard newValue != nil else { return }
            tempBirthdayDate = birthdayDate
            tempHeightInt = heightInt
            tempHeightDecimal = heightDecimal
            tempWeightInt = weightInt
            tempWeightDecimal = weightDecimal
            tempStepTarget = stepTarget
            tempCalorieTarget = calorieTarget
            tempDistanceTargetInt = distanceTargetInt
            tempDistanceTargetDecimal = distanceTargetDecimal
            tempWeeklySteps = weeklySteps
            tempBodyFat = bodyFat
            tempWeeklyExercise = weeklyExercise
        }
    }

    @ViewBuilder
    private func pickerSheet(for picker: ProfilePicker) -> some View {
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
                    UserDefaults.standard.removeObject(forKey: birthdayKey)
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

    private func parseBirthday(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.date(from: trimmed)
    }

    private func ageYears(from birthday: Date) -> Int? {
        let now = Date()
        guard birthday <= now else { return nil }
        let components = Calendar.current.dateComponents([.year], from: birthday, to: now)
        return components.year
    }

    private func refreshFromServer() async {
        do {
            let response = try await UserAPIClient.shared.fetchUserProfile()
            ProfileStore.applyFromServer(response.profile)
            applyProfileDetails(response.profile)
            initialSnapshot = currentSnapshot()
        } catch {
            // ignore; keep local values
        }
    }

    private func applyProfileDetails(_ profile: UserProfileDetails) {
        if let nickname = profile.nickname { self.nickname = nickname }
        if let birthday = profile.birthday, let parsed = parseBirthday(birthday) {
            birthdayDate = parsed
            birthdayIsSet = true
        }
        if profile.birthday == nil {
            birthdayIsSet = false
        }
        if let gender = profile.gender { self.gender = gender }
        if let height = profile.heightCm {
            let rounded = (height * 10).rounded()
            heightInt = Int(rounded) / 10
            heightDecimal = Int(rounded) % 10
        }
        if let weight = profile.weightKg {
            let rounded = (weight * 10).rounded()
            weightInt = Int(rounded) / 10
            weightDecimal = Int(rounded) % 10
        }
        if let weeklySteps = profile.weeklySteps { self.weeklySteps = weeklySteps }
        if let bodyFat = profile.bodyFat { self.bodyFat = bodyFat }
        if let weeklyExercise = profile.weeklyExercise { self.weeklyExercise = weeklyExercise }
        if let steps = profile.goalSteps { self.stepTarget = steps }
        if let calories = profile.goalCalories { self.calorieTarget = calories }
        if let distance = profile.goalDistanceKm {
            let rounded = (distance * 10).rounded()
            distanceTargetInt = Int(rounded) / 10
            distanceTargetDecimal = Int(rounded) % 10
        }
    }

    private func saveProfile() {
        UserDefaults.standard.set(nickname, forKey: nicknameKey)
        if birthdayIsSet {
            UserDefaults.standard.set(birthdayDisplay, forKey: birthdayKey)
        } else {
            UserDefaults.standard.removeObject(forKey: birthdayKey)
        }
        UserDefaults.standard.set(gender, forKey: genderKey)
        let heightValue = Double(heightInt) + (Double(heightDecimal) / 10.0)
        UserDefaults.standard.set(heightValue, forKey: heightKey)
        UserDefaults.standard.set(weightValue, forKey: weightKey)
        UserDefaults.standard.set(stepTarget, forKey: stepTargetKey)
        UserDefaults.standard.set(calorieTarget, forKey: calorieTargetKey)
        UserDefaults.standard.set(distanceTargetValue, forKey: distanceTargetKey)
        UserDefaults.standard.set(weeklySteps, forKey: weeklyStepsKey)
        UserDefaults.standard.set(bodyFat, forKey: bodyFatKey)
        UserDefaults.standard.set(weeklyExercise, forKey: weeklyExerciseKey)
        focusedField = nil
        showSavedAlert = true
        Task {
            let payload = ProfileStore.buildForServer()
            _ = try? await UserAPIClient.shared.updateUserProfile(payload)
            var fieldsToClear: [String] = []
            if birthdayIsSet == false { fieldsToClear.append("birthday") }
            if gender == "未設定" { fieldsToClear.append("gender") }
            if fieldsToClear.isEmpty == false {
                _ = try? await UserAPIClient.shared.clearUserProfileFields(fieldsToClear)
            }
        }
        initialSnapshot = currentSnapshot()
    }

    private func currentSnapshot() -> ProfileSnapshot {
        ProfileSnapshot(
            nickname: nickname,
            birthdayDate: birthdayDate,
            birthdayIsSet: birthdayIsSet,
            gender: gender,
            heightInt: heightInt,
            heightDecimal: heightDecimal,
            weightInt: weightInt,
            weightDecimal: weightDecimal,
            stepTarget: stepTarget,
            calorieTarget: calorieTarget,
            distanceTargetInt: distanceTargetInt,
            distanceTargetDecimal: distanceTargetDecimal,
            weeklySteps: weeklySteps,
            bodyFat: bodyFat,
            weeklyExercise: weeklyExercise
        )
    }

    private var hasUnsavedChanges: Bool {
        currentSnapshot() != initialSnapshot
    }
}

private struct ProfileSnapshot: Equatable {
    var nickname: String = ""
    var birthdayDate: Date = Date()
    var birthdayIsSet: Bool = false
    var gender: String = "未設定"
    var heightInt: Int = 170
    var heightDecimal: Int = 0
    var weightInt: Int = 60
    var weightDecimal: Int = 0
    var stepTarget: Int = 5000
    var calorieTarget: Int = 300
    var distanceTargetInt: Int = 3
    var distanceTargetDecimal: Int = 0
    var weeklySteps: Int = 200
    var bodyFat: Int = 35
    var weeklyExercise: Int = 1
}

#if DEBUG
@available(iOS 17, *)
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProfileView()
        }
    }
}
#endif

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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
