import Foundation

struct Traveler: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var job: String
    var rarity: Rarity
    var level: Int
    var stats: Stats
    var skill: String
    var joinedAt: Date

    init(
        name: String,
        job: String,
        rarity: Rarity,
        level: Int = 1,
        stats: Stats,
        skill: String,
        joinedAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.job = job
        self.rarity = rarity
        self.level = level
        self.stats = stats
        self.skill = skill
        self.joinedAt = joinedAt
    }

    init(
        id: UUID,
        name: String,
        job: String,
        rarity: Rarity,
        level: Int = 1,
        stats: Stats,
        skill: String,
        joinedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.job = job
        self.rarity = rarity
        self.level = level
        self.stats = stats
        self.skill = skill
        self.joinedAt = joinedAt
    }
}

struct Stats: Codable, Hashable {
    var hp: Int
    var atk: Int
    var def: Int
    var agi: Int
}

enum Rarity: Int, Codable, CaseIterable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var label: String {
        switch self {
        case .one: return "淡い"
        case .two: return "澄んだ"
        case .three: return "深い"
        case .four: return "輝く"
        case .five: return "神秘"
        }
    }
}
