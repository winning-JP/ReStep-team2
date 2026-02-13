import Foundation
import Combine

@MainActor
final class TravelerListViewModel: ObservableObject {
    @Published private(set) var travelers: [Traveler] = []

    private let store = GameStore.shared

    init() {
        travelers = store.loadTravelers()
        if travelers.isEmpty {
            travelers = [
                Traveler(name: "ミオ", job: "旅の料理人", rarity: .two, stats: Stats(hp: 28, atk: 6, def: 4, agi: 5), skill: "体力回復"),
                Traveler(name: "レン", job: "星見の案内人", rarity: .three, stats: Stats(hp: 24, atk: 7, def: 3, agi: 7), skill: "探索補助"),
                Traveler(name: "ユイ", job: "森の薬師", rarity: .two, stats: Stats(hp: 26, atk: 5, def: 5, agi: 6), skill: "小回復"),
                Traveler(name: "ジン", job: "鍛冶職人", rarity: .two, stats: Stats(hp: 30, atk: 7, def: 6, agi: 4), skill: "装備強化")
            ]
            store.saveTravelers(travelers)
        }
    }

    func addRandomTraveler() {
        let pool: [Traveler] = [
            Traveler(name: "カナ", job: "風読み", rarity: .three, stats: Stats(hp: 22, atk: 6, def: 4, agi: 8), skill: "道標"),
            Traveler(name: "ハル", job: "迷宮記録者", rarity: .four, stats: Stats(hp: 24, atk: 8, def: 5, agi: 7), skill: "発見率UP"),
            Traveler(name: "ソラ", job: "灯り守り", rarity: .three, stats: Stats(hp: 25, atk: 6, def: 5, agi: 6), skill: "視界確保")
        ]
        if let newTraveler = pool.randomElement() {
            travelers.insert(newTraveler, at: 0)
            store.saveTravelers(travelers)
        }
    }
}
