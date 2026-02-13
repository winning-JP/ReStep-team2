import Foundation

struct Party: Codable, Hashable {
    var memberIds: [UUID] = []

    mutating func setMembers(_ ids: [UUID]) {
        memberIds = Array(ids.prefix(4))
    }
}
