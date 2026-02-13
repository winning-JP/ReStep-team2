import Foundation

struct Encounter: Identifiable, Codable, Hashable {
    let id: UUID
    var traveler: Traveler
    var date: Date
    var source: EncounterSource

    init(traveler: Traveler, date: Date = Date(), source: EncounterSource) {
        self.id = UUID()
        self.traveler = traveler
        self.date = date
        self.source = source
    }
}

enum EncounterSource: String, Codable {
    case mpc = "MPC"
    case bluetooth = "BT"
    case qr = "QR"
    case other = "OTHER"
}

extension Encounter {
    var displayDateTime: String {
        Self.displayDateFormatter.string(from: date)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()
}
