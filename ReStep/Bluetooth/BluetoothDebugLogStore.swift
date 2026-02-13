import Foundation
import Observation

struct BluetoothDebugLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

struct BluetoothDebugPayloadEntry: Identifiable {
    let id = UUID()
    let date: Date
    let userId: String
    let nickname: String
    let raw: String
}

@MainActor
@Observable
final class BluetoothDebugLogStore {
    static let shared = BluetoothDebugLogStore()

    private(set) var entries: [BluetoothDebugLogEntry] = []
    private(set) var payloads: [BluetoothDebugPayloadEntry] = []

    func add(_ message: String) {
        entries.insert(BluetoothDebugLogEntry(date: Date(), message: message), at: 0)
        if entries.count > 200 {
            entries.removeLast(entries.count - 200)
        }
    }

    func addPayload(userId: String, nickname: String, raw: String) {
        payloads.insert(
            BluetoothDebugPayloadEntry(date: Date(), userId: userId, nickname: nickname, raw: raw),
            at: 0
        )
        if payloads.count > 100 {
            payloads.removeLast(payloads.count - 100)
        }
    }

    func addRawPayload(_ raw: String) {
        addPayload(userId: "unknown", nickname: "unknown", raw: raw)
    }

    func clear() {
        entries.removeAll()
        payloads.removeAll()
    }
}

@MainActor
@Observable
final class BluetoothDebugStatusStore {
    static let shared = BluetoothDebugStatusStore()

    private(set) var isScanning: Bool = false
    private(set) var isAdvertising: Bool = false
    private(set) var lastDiscoveredAt: Date?
    private(set) var lastEncounterAt: Date?

    func setScanning(_ value: Bool) {
        isScanning = value
    }

    func setAdvertising(_ value: Bool) {
        isAdvertising = value
    }

    func markDiscovered() {
        lastDiscoveredAt = Date()
    }

    func markEncountered() {
        lastEncounterAt = Date()
    }
}
