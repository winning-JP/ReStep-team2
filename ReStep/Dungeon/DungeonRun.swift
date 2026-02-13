import Foundation

struct DungeonRun: Identifiable, Codable, Hashable {
    let id: UUID
    var floor: Int
    var seed: Int
    var startedAt: Date

    init(floor: Int = 1, seed: Int, startedAt: Date = Date()) {
        self.id = UUID()
        self.floor = floor
        self.seed = seed
        self.startedAt = startedAt
    }
}
