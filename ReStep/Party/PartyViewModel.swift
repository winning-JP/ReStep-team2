import Foundation
import Combine

@MainActor
final class PartyViewModel: ObservableObject {
    @Published private(set) var travelers: [Traveler] = []
    @Published private(set) var party: Party = Party()

    private let store = GameStore.shared

    init() {
        travelers = store.loadTravelers()
        party = store.loadParty()
        if party.memberIds.isEmpty {
            let defaultIds = travelers.prefix(4).map { $0.id }
            party.setMembers(defaultIds)
            store.saveParty(party)
        }
    }

    func toggleMember(_ traveler: Traveler) {
        var ids = party.memberIds
        if let index = ids.firstIndex(of: traveler.id) {
            ids.remove(at: index)
        } else if ids.count < 4 {
            ids.append(traveler.id)
        }
        party.setMembers(ids)
        store.saveParty(party)
    }

    func isSelected(_ traveler: Traveler) -> Bool {
        party.memberIds.contains(traveler.id)
    }
}
