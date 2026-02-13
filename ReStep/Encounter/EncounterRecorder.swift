import Foundation

@MainActor
final class EncounterRecorder {
    static let shared = EncounterRecorder()
    static let didUpdateNotification = Notification.Name("restep.encounter.updated")
    static let didDetectEncounterNotification = Notification.Name("restep.encounter.detected")

    func record(payload: EncounterUserPayload) -> Bool {
        let traveler = traveler(from: payload)
        return record(traveler: traveler)
    }

    func record(traveler: Traveler) -> Bool {
        var encounters = GameStore.shared.loadEncounters()
        if let index = encounters.firstIndex(where: { $0.traveler.id == traveler.id }) {
            let now = Date()
            encounters[index].traveler = traveler
            encounters[index].date = now
            for i in encounters.indices where encounters[i].traveler.id == traveler.id {
                encounters[i].traveler = traveler
            }
            GameStore.shared.saveEncounters(encounters)

            var travelers = GameStore.shared.loadTravelers()
            if let travelerIndex = travelers.firstIndex(where: { $0.id == traveler.id }) {
                travelers[travelerIndex] = traveler
                GameStore.shared.saveTravelers(travelers)
            }
            NotificationCenter.default.post(
                name: Self.didDetectEncounterNotification,
                object: nil,
                userInfo: ["name": traveler.name]
            )
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
            EncounterStampTracker.shared.registerEncounter(travelerId: traveler.id, date: now)
            return false
        }

        let new = Encounter(traveler: traveler, source: .bluetooth)
        encounters.insert(new, at: 0)
        GameStore.shared.saveEncounters(encounters)

        var travelers = GameStore.shared.loadTravelers()
        if travelers.contains(where: { $0.id == traveler.id }) == false {
            travelers.append(traveler)
            GameStore.shared.saveTravelers(travelers)
        }
        NotificationCenter.default.post(
            name: Self.didDetectEncounterNotification,
            object: nil,
            userInfo: ["name": traveler.name]
        )
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
        EncounterStampTracker.shared.registerEncounter(travelerId: traveler.id, date: new.date)
        return true
    }

    func traveler(from payload: EncounterUserPayload) -> Traveler {
        let id = UUID(uuidString: payload.id) ?? UUID()
        let displayName = payload.nickname.isEmpty ? "名無しの旅人" : payload.nickname
        return Traveler(
            id: id,
            name: displayName,
            job: "ユーザー",
            rarity: .one,
            stats: Stats(hp: 20, atk: 4, def: 3, agi: 4),
            skill: "すれ違い"
        )
    }
}
