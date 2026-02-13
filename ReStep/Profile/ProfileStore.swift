import Foundation

enum ProfileStore {
    private static let nicknameKey = "restep.profile.nickname"
    private static let birthdayKey = "restep.profile.birthday"
    private static let genderKey = "restep.profile.gender"
    private static let heightKey = "restep.profile.height"
    private static let weightKey = "restep.profile.weight"
    private static let weeklyStepsKey = "restep.profile.weeklySteps"
    private static let bodyFatKey = "restep.profile.bodyFat"
    private static let weeklyExerciseKey = "restep.profile.weeklyExercise"
    private static let stepTargetKey = "restep.goal.steps"
    private static let calorieTargetKey = "restep.goal.calories"
    private static let distanceTargetKey = "restep.goal.distanceKm"

    static func applyFromServer(_ profile: UserProfileDetails) {
        let defaults = UserDefaults.standard
        if let nickname = profile.nickname { defaults.set(nickname, forKey: nicknameKey) }
        if let birthday = profile.birthday { defaults.set(birthday, forKey: birthdayKey) }
        if let gender = profile.gender { defaults.set(gender, forKey: genderKey) }
        if let height = profile.heightCm { defaults.set(height, forKey: heightKey) }
        if let weight = profile.weightKg { defaults.set(weight, forKey: weightKey) }
        if let weeklySteps = profile.weeklySteps { defaults.set(weeklySteps, forKey: weeklyStepsKey) }
        if let bodyFat = profile.bodyFat { defaults.set(bodyFat, forKey: bodyFatKey) }
        if let weeklyExercise = profile.weeklyExercise { defaults.set(weeklyExercise, forKey: weeklyExerciseKey) }
        if let steps = profile.goalSteps { defaults.set(steps, forKey: stepTargetKey) }
        if let calories = profile.goalCalories { defaults.set(calories, forKey: calorieTargetKey) }
        if let distance = profile.goalDistanceKm { defaults.set(distance, forKey: distanceTargetKey) }
    }

    static func buildForServer() -> UserProfileDetails {
        let defaults = UserDefaults.standard
        let nickname = defaults.string(forKey: nicknameKey)
        let rawBirthday = defaults.string(forKey: birthdayKey)
        let birthday = (rawBirthday?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? rawBirthday : nil
        let rawGender = defaults.string(forKey: genderKey)
        let gender = (rawGender == "未設定") ? nil : rawGender
        let height = defaults.object(forKey: heightKey) as? Double
        let weight = defaults.object(forKey: weightKey) as? Double
        let weeklySteps = defaults.object(forKey: weeklyStepsKey) as? Int
        let bodyFat = defaults.object(forKey: bodyFatKey) as? Int
        let weeklyExercise = defaults.object(forKey: weeklyExerciseKey) as? Int
        let goalSteps = defaults.object(forKey: stepTargetKey) as? Int
        let goalCalories = defaults.object(forKey: calorieTargetKey) as? Int
        let goalDistanceKm = defaults.object(forKey: distanceTargetKey) as? Double

        return UserProfileDetails(
            nickname: nickname,
            birthday: birthday,
            gender: gender,
            heightCm: height,
            weightKg: weight,
            weeklySteps: weeklySteps,
            bodyFat: bodyFat,
            weeklyExercise: weeklyExercise,
            goalSteps: goalSteps,
            goalCalories: goalCalories,
            goalDistanceKm: goalDistanceKm,
            updatedAt: nil
        )
    }

    static func clearAll() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: nicknameKey)
        defaults.removeObject(forKey: birthdayKey)
        defaults.removeObject(forKey: genderKey)
        defaults.removeObject(forKey: heightKey)
        defaults.removeObject(forKey: weightKey)
        defaults.removeObject(forKey: weeklyStepsKey)
        defaults.removeObject(forKey: bodyFatKey)
        defaults.removeObject(forKey: weeklyExerciseKey)
        defaults.removeObject(forKey: stepTargetKey)
        defaults.removeObject(forKey: calorieTargetKey)
        defaults.removeObject(forKey: distanceTargetKey)
    }
}
