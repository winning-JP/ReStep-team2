import Foundation

final class GameStore {
    static let shared = GameStore()

    private let dir: URL
    private let travelersURL: URL
    private let partyURL: URL
    private let encountersURL: URL
    private let runsURL: URL
    private let inventoryURL: URL

    private init() {
        dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        travelersURL = dir.appendingPathComponent("travelers.json")
        partyURL = dir.appendingPathComponent("party.json")
        encountersURL = dir.appendingPathComponent("encounters.json")
        runsURL = dir.appendingPathComponent("dungeon_runs.json")
        inventoryURL = dir.appendingPathComponent("inventory.json")
    }

    func loadTravelers() -> [Traveler] {
        load([Traveler].self, from: travelersURL) ?? []
    }

    func saveTravelers(_ travelers: [Traveler]) {
        save(travelers, to: travelersURL)
    }

    func loadParty() -> Party {
        load(Party.self, from: partyURL) ?? Party()
    }

    func saveParty(_ party: Party) {
        save(party, to: partyURL)
    }

    func loadEncounters() -> [Encounter] {
        load([Encounter].self, from: encountersURL) ?? []
    }

    func saveEncounters(_ encounters: [Encounter]) {
        save(encounters, to: encountersURL)
    }

    func loadDungeonRuns() -> [DungeonRun] {
        load([DungeonRun].self, from: runsURL) ?? []
    }

    func saveDungeonRuns(_ runs: [DungeonRun]) {
        save(runs, to: runsURL)
    }

    func loadInventory() -> Inventory {
        load(Inventory.self, from: inventoryURL) ?? Inventory()
    }

    func saveInventory(_ inventory: Inventory) {
        save(inventory, to: inventoryURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: travelersURL)
        try? FileManager.default.removeItem(at: partyURL)
        try? FileManager.default.removeItem(at: encountersURL)
        try? FileManager.default.removeItem(at: runsURL)
        try? FileManager.default.removeItem(at: inventoryURL)
    }
}
