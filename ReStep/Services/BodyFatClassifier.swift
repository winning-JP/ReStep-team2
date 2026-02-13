import Foundation

struct BodyFatClassifier {
    enum Gender {
        case male
        case female
    }

    static func parseGender(_ raw: String) -> Gender? {
        switch raw {
        case "男性":
            return .male
        case "女性":
            return .female
        case "未設定":
            return nil
        default:
            return nil
        }
    }

    static func age(from birthdayRaw: String) -> Int? {
        let trimmed = birthdayRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        guard let date = formatter.date(from: trimmed) else { return nil }
        let now = Date()
        guard date <= now else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: now).year
    }

    static func category(gender: Gender, age: Int, percent: Double) -> String {
        let thresholds = thresholdsFor(gender: gender, age: age)
        if percent <= thresholds.thinMax { return "痩せ" }
        if percent <= thresholds.normalMinusMax { return "標準（－）" }
        if percent <= thresholds.normalPlusMax { return "標準（＋）" }
        if percent <= thresholds.mildObesityMax { return "軽度肥満" }
        return "肥満"
    }

    static func bmiTrefethen(weightKg: Double, heightCm: Double) -> Double {
        let heightMeters = max(0.1, heightCm / 100.0)
        return 1.3 * weightKg / pow(heightMeters, 2.5)
    }

    static func estimatedBodyFatPercent(gender: Gender, age: Int, weightKg: Double, heightCm: Double) -> Double? {
        guard age >= 18, weightKg > 0 else { return nil }
        // 18歳以上の日本人に対する体脂肪率の推定式
        let base = 3.02 + (0.461 * weightKg) - (0.089 * heightCm) + (0.038 * Double(age)) - 0.238
        let genderAdjust: Double
        switch gender {
        case .male:
            genderAdjust = -6.85
        case .female:
            genderAdjust = 0.0
        }
        return (base + genderAdjust) / weightKg * 100.0
    }

    private static func thresholdsFor(gender: Gender, age: Int) -> (thinMax: Double, normalMinusMax: Double, normalPlusMax: Double, mildObesityMax: Double) {
        switch gender {
        case .male:
            if age <= 14 { return (6, 15, 24, 27) }
            if age <= 17 { return (8, 15, 24, 28) }
            if age <= 39 { return (11, 16, 24, 28) }
            if age <= 59 { return (12, 17, 25, 28) }
            return (14, 19, 25, 30)
        case .female:
            if age <= 13 { return (15, 25, 33, 38) }
            if age <= 17 { return (18, 27, 35, 40) }
            if age <= 39 { return (21, 28, 34, 40) }
            if age <= 59 { return (22, 29, 35, 41) }
            return (23, 30, 36, 42)
        }
    }
}
