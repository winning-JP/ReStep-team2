import Foundation
import CoreBluetooth
import Combine

struct EncounterUserPayload: Codable, Hashable {
    let id: String
    let nickname: String
}

@MainActor
final class BluetoothEncounterManager: NSObject, ObservableObject {
    static let shared = BluetoothEncounterManager()

    @Published private(set) var nearbyUsers: [EncounterUserPayload] = []
    @Published private(set) var isBluetoothPoweredOn: Bool = false

    private let serviceUUID = CBUUID(string: "9B2D2E77-2D0E-4B0E-9D2B-1A66C6B6F42A")
    private let userCharacteristicUUID = CBUUID(string: "C3A5D1B1-6F0C-4F4D-9D5F-1CC8B0D2C9F4")
    // Compatibility UUIDs observed on older/beta encounter builds.
    private let legacyServiceUUIDs: Set<CBUUID> = [
        CBUUID(string: "D0611E78-BBB4-4591-A5F8-487910AE4366"),
        CBUUID(string: "9FA480E0-4967-4542-9390-D343DC5D04AE")
    ]
    private let legacyCharacteristicUUIDs: Set<CBUUID> = [
        CBUUID(string: "9FA480E0-4967-4542-9390-D343DC5D04AE"),
        CBUUID(string: "D0611E78-BBB4-4591-A5F8-487910AE4366")
    ]
    private let centralRestoreIdentifier = "restep.bluetooth.central"
    private let peripheralRestoreIdentifier = "restep.bluetooth.peripheral"

    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var userCharacteristic: CBMutableCharacteristic?
    private var discoveredPeripherals: [UUID: PeripheralEntry] = [:]
    private var knownUserIds: Set<String> = []
    private var serviceDiscoveryRetried: Set<UUID> = []
    private var pendingCharacteristicReads: [UUID: Int] = [:]
    private var pendingServiceCharacteristicDiscovery: [UUID: Int] = [:]
    private var pendingNotifyOnlyCharacteristics: [UUID: [CBCharacteristic]] = [:]
    private var pendingValueTimeouts: [UUID: DispatchWorkItem] = [:]
    private var pendingValueRetryCount: [UUID: Int] = [:]
    private var payloadData: Data = Data()
    private var batterySaverEnabled: Bool = false
    private var scanTimer: Timer?
    private var cleanupTimer: Timer?
    private var recentPeripheralIds: [UUID: Date] = [:]
    private var disconnectingPeripherals: Set<UUID> = []
    private var pendingNotify: Bool = false
    private var shouldAdvertiseWhenReady: Bool = false
    private var isServiceAdded: Bool = false
    private var isActive: Bool = false

    private let connectionRetryBase: TimeInterval = 6
    private let connectionRetryMax: TimeInterval = 30
    private let peripheralCooldown: TimeInterval = 180
    private let entryExpiration: TimeInterval = 300
    private let cleanupInterval: TimeInterval = 30
    private let dutyScanDuration: TimeInterval = 6
    private let dutyPauseDuration: TimeInterval = 20
    private let debugLog = BluetoothDebugLogStore.shared
    private let debugStatus = BluetoothDebugStatusStore.shared

    private struct PeripheralEntry {
        var peripheral: CBPeripheral
        var lastSeen: Date
        var lastAttempt: Date?
        var failureCount: Int
        var nextAllowedAttempt: Date
    }

    func start(with payload: EncounterUserPayload) {
        guard Self.isBluetoothAuthorized else { return }
        if isActive {
            payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
            knownUserIds.insert(payload.id)
            notifyPayloadUpdate()
            debugLog.add("start() 更新")
            return
        }
        isActive = true
        payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
        knownUserIds.insert(payload.id)
        notifyPayloadUpdate()
        debugLog.add("start() 呼び出し")

        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [
                    CBCentralManagerOptionShowPowerAlertKey: true,
                    CBCentralManagerOptionRestoreIdentifierKey: centralRestoreIdentifier
                ]
            )
            debugLog.add("CBCentralManager 初期化")
        } else {
            centralManager?.delegate = self
            if centralManager?.state == .poweredOn {
                startScanningIfNeeded()
            }
        }

        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(
                delegate: self,
                queue: .main,
                options: [
                    CBPeripheralManagerOptionShowPowerAlertKey: true,
                    CBPeripheralManagerOptionRestoreIdentifierKey: peripheralRestoreIdentifier
                ]
            )
            debugLog.add("CBPeripheralManager 初期化")
        } else {
            peripheralManager?.delegate = self
            if peripheralManager?.state == .poweredOn {
                startAdvertising()
            }
        }
    }

    func stop() {
        isActive = false
        stopScanTimer()
        stopCleanupTimer()
        centralManager?.stopScan()
        debugLog.add("stop() 呼び出し")
        debugStatus.setScanning(false)
        for entry in discoveredPeripherals.values {
            if entry.peripheral.state != .disconnected {
                disconnect(entry.peripheral)
            }
        }
        discoveredPeripherals.removeAll()
        disconnectingPeripherals.removeAll()
        serviceDiscoveryRetried.removeAll()
        for work in pendingValueTimeouts.values {
            work.cancel()
        }
        pendingCharacteristicReads.removeAll()
        pendingServiceCharacteristicDiscovery.removeAll()
        pendingNotifyOnlyCharacteristics.removeAll()
        pendingValueTimeouts.removeAll()
        pendingValueRetryCount.removeAll()
        peripheralManager?.stopAdvertising()
        debugStatus.setAdvertising(false)
        shouldAdvertiseWhenReady = false
        pendingNotify = false
        knownUserIds.removeAll()
    }

    static var isBluetoothAuthorized: Bool {
        switch CBManager.authorization {
        case .allowedAlways, .notDetermined:
            return true
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    static var isBluetoothDenied: Bool {
        switch CBManager.authorization {
        case .restricted, .denied:
            return true
        case .allowedAlways, .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    func setBatterySaverEnabled(_ enabled: Bool) {
        batterySaverEnabled = enabled
        startScanningIfNeeded()
    }

    private func startAdvertising() {
        guard isActive else { return }
        debugLog.add("広告開始リクエスト")
        if userCharacteristic == nil {
            let characteristic = CBMutableCharacteristic(
                type: userCharacteristicUUID,
                properties: [.read, .notify],
                value: nil,
                permissions: [.readable]
            )
            userCharacteristic = characteristic
            let service = CBMutableService(type: serviceUUID, primary: true)
            service.characteristics = [characteristic]
            peripheralManager?.removeAllServices()
            peripheralManager?.add(service)
            isServiceAdded = false
            debugLog.add("サービス追加リクエスト")
        }
        guard isServiceAdded else {
            shouldAdvertiseWhenReady = true
            return
        }
        guard peripheralManager?.isAdvertising == false else { return }
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "ReStep"
        ])
        debugLog.add("広告開始")
        debugStatus.setAdvertising(true)
    }

    private func startScanningIfNeeded() {
        guard isActive else { return }
        guard centralManager?.state == .poweredOn else { return }
        stopScanTimer()
        centralManager?.stopScan()
        debugLog.add("スキャン開始")
        debugStatus.setScanning(true)
        startCleanupTimer()
        if batterySaverEnabled {
            scheduleDutyCycleScan()
        } else {
            centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
        }
    }

    private func scheduleDutyCycleScan() {
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        debugLog.add("節電スキャン開始")
        debugStatus.setScanning(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + dutyScanDuration) {
            Task { @MainActor in
                self.centralManager?.stopScan()
                self.debugLog.add("節電スキャン停止")
                self.debugStatus.setScanning(false)
            }
        }
        scanTimer = Timer.scheduledTimer(withTimeInterval: dutyScanDuration + dutyPauseDuration, repeats: true) { _ in
            Task { @MainActor in
                self.centralManager?.scanForPeripherals(withServices: [self.serviceUUID], options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ])
                self.debugLog.add("節電スキャン再開")
                self.debugStatus.setScanning(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + self.dutyScanDuration) {
                    Task { @MainActor in
                        self.centralManager?.stopScan()
                        self.debugLog.add("節電スキャン停止")
                        self.debugStatus.setScanning(false)
                    }
                }
            }
        }
    }

    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    private func startCleanupTimer() {
        guard cleanupTimer == nil else { return }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { _ in
            Task { @MainActor in
                self.purgeStalePeripherals()
            }
        }
    }

    private func stopCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    private func purgeStalePeripherals() {
        let now = Date()
        discoveredPeripherals = discoveredPeripherals.filter { now.timeIntervalSince($0.value.lastSeen) < entryExpiration }
        recentPeripheralIds = recentPeripheralIds.filter { $0.value > now }
    }

    private func shortId(_ value: String) -> String {
        String(value.prefix(6))
    }

    private func isKnownEncounterService(_ uuid: CBUUID) -> Bool {
        uuid == serviceUUID || legacyServiceUUIDs.contains(uuid)
    }

    private func isKnownEncounterCharacteristic(_ uuid: CBUUID) -> Bool {
        uuid == userCharacteristicUUID || legacyCharacteristicUUIDs.contains(uuid)
    }

    private func isLikelyStandardBluetoothUUID(_ uuid: CBUUID) -> Bool {
        // CoreBluetooth usually returns adopted SIG UUIDs as short hex (e.g. 180A, 2A29).
        let value = uuid.uuidString
        return value.count <= 8
    }

    private func characteristicFlags(_ properties: CBCharacteristicProperties) -> String {
        var flags: [String] = []
        if properties.contains(.read) { flags.append("R") }
        if properties.contains(.write) { flags.append("W") }
        if properties.contains(.writeWithoutResponse) { flags.append("WNR") }
        if properties.contains(.notify) { flags.append("N") }
        if properties.contains(.indicate) { flags.append("I") }
        return flags.isEmpty ? "-" : flags.joined(separator: "/")
    }

    private func hasPendingNotifyCharacteristic(id: UUID, uuid: CBUUID) -> Bool {
        (pendingNotifyOnlyCharacteristics[id] ?? []).contains(where: { $0.uuid == uuid })
    }

    private func removePendingNotifyCharacteristic(id: UUID, uuid: CBUUID) {
        guard var list = pendingNotifyOnlyCharacteristics[id] else { return }
        list.removeAll(where: { $0.uuid == uuid })
        pendingNotifyOnlyCharacteristics[id] = list
    }

    private func clearPendingValueState(for id: UUID) {
        pendingCharacteristicReads.removeValue(forKey: id)
        pendingServiceCharacteristicDiscovery.removeValue(forKey: id)
        pendingNotifyOnlyCharacteristics.removeValue(forKey: id)
        pendingValueTimeouts[id]?.cancel()
        pendingValueTimeouts.removeValue(forKey: id)
        pendingValueRetryCount.removeValue(forKey: id)
    }

    private func schedulePendingValueTimeout(for peripheral: CBPeripheral) {
        let id = peripheral.identifier
        pendingValueTimeouts[id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            Task { @MainActor in
                guard let self, let peripheral else { return }
                guard self.isActive else { return }
                let pending = self.pendingCharacteristicReads[id] ?? 0
                let servicesPending = self.pendingServiceCharacteristicDiscovery[id] ?? 0
                guard pending > 0, servicesPending == 0 else { return }
                let retry = self.pendingValueRetryCount[id] ?? 0
                if retry < 1 {
                    let notifyTargets = self.pendingNotifyOnlyCharacteristics[id] ?? []
                    var didWriteRetry = false
                    for characteristic in notifyTargets {
                        if characteristic.properties.contains(.writeWithoutResponse) {
                            peripheral.writeValue(self.payloadData, for: characteristic, type: .withoutResponse)
                            self.debugLog.add("値待機再write: \(characteristic.uuid.uuidString.prefix(8)) type=withoutResponse")
                            didWriteRetry = true
                        } else if characteristic.properties.contains(.write) {
                            peripheral.writeValue(self.payloadData, for: characteristic, type: .withResponse)
                            self.debugLog.add("値待機再write: \(characteristic.uuid.uuidString.prefix(8)) type=withResponse")
                            didWriteRetry = true
                        }
                    }
                    if didWriteRetry {
                        self.pendingValueRetryCount[id] = retry + 1
                        self.schedulePendingValueTimeout(for: peripheral)
                        return
                    }
                }
                self.debugLog.add("値待機タイムアウト: remaining=\(pending)")
                self.clearPendingValueState(for: id)
                self.noteFailure(for: peripheral)
                self.disconnect(peripheral)
            }
        }
        pendingValueTimeouts[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func finalizeFailureIfNoPending(for peripheral: CBPeripheral, fallbackMessage: String = "デコード失敗") {
        let id = peripheral.identifier
        let pending = pendingCharacteristicReads[id] ?? 0
        let servicesPending = pendingServiceCharacteristicDiscovery[id] ?? 0
        if pending > 0 || servicesPending > 0 {
            if pending > 0 && servicesPending == 0 {
                schedulePendingValueTimeout(for: peripheral)
            }
            return
        }
        clearPendingValueState(for: id)
        debugLog.add(fallbackMessage)
        noteFailure(for: peripheral)
        disconnect(peripheral)
    }

    private func handlePayload(_ payload: EncounterUserPayload) {
        guard knownUserIds.contains(payload.id) == false else { return }
        knownUserIds.insert(payload.id)

        Task { @MainActor in
            let resolved = await resolveEncounterPayload(payload)
            nearbyUsers.insert(resolved, at: 0)
            debugLog.add("ペイロード受信: user=\(shortId(resolved.id)) name=\(resolved.nickname)")
            debugStatus.markEncountered()
            _ = EncounterRecorder.shared.record(payload: resolved)
        }
    }

    private func isLookupEligibleUserId(_ id: String) -> Bool {
        // bluetooth_user_id is expected to be alphanumeric + hyphen, up to 64 chars.
        guard id.isEmpty == false, id.count <= 64 else { return false }
        return id.range(of: "^[A-Za-z0-9\\-]+$", options: .regularExpression) != nil
    }

    private func resolveEncounterPayload(_ payload: EncounterUserPayload) async -> EncounterUserPayload {
        guard isLookupEligibleUserId(payload.id) else {
            debugLog.add("API照会スキップ: user=\(shortId(payload.id)) reason=invalid_id")
            return payload
        }

        do {
            let response = try await UserAPIClient.shared.lookupEncounterProfile(bluetoothUserId: payload.id)
            let fallback = payload.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedNameRaw = response.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultName = fallback.isEmpty ? "名無しの旅人" : fallback
            let resolvedName: String
            if !response.found {
                resolvedName = defaultName
            } else {
                resolvedName = resolvedNameRaw.isEmpty ? defaultName : resolvedNameRaw
            }
            let visibility = response.encounterVisibility ?? (response.shareNickname ? "public" : "private")
            debugLog.add("API照会: user=\(shortId(payload.id)) found=\(response.found) visibility=\(visibility) display=\(resolvedName)")
            return EncounterUserPayload(id: payload.id, nickname: resolvedName)
        } catch let apiError as APIError {
            debugLog.add("API照会失敗: user=\(shortId(payload.id)) reason=\(apiError.userMessage())")
            return payload
        } catch {
            debugLog.add("API照会失敗: user=\(shortId(payload.id)) reason=\(error.localizedDescription)")
            return payload
        }
    }

    private func loadOrCreateUserId() -> String {
        let key = "restep.bluetooth.userId"
        if let existing = UserDefaults.standard.string(forKey: key), existing.isEmpty == false {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    func makePayload(nickname: String) -> EncounterUserPayload {
        let safeNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = loadOrCreateUserId()
        return EncounterUserPayload(
            id: id,
            nickname: safeNick.isEmpty ? "名無しの旅人" : safeNick
        )
    }

    private func updatePeripheralEntry(for peripheral: CBPeripheral, seenAt: Date) {
        let id = peripheral.identifier
        var entry = discoveredPeripherals[id] ?? PeripheralEntry(
            peripheral: peripheral,
            lastSeen: seenAt,
            lastAttempt: nil,
            failureCount: 0,
            nextAllowedAttempt: seenAt
        )
        entry.peripheral = peripheral
        entry.lastSeen = seenAt
        discoveredPeripherals[id] = entry
    }

    private func shouldIgnorePeripheral(_ id: UUID, now: Date) -> Bool {
        if let until = recentPeripheralIds[id], until > now {
            return true
        }
        return false
    }

    private func attemptConnectionIfNeeded(for id: UUID) {
        guard let centralManager else { return }
        guard var entry = discoveredPeripherals[id] else { return }
        let now = Date()
        guard now >= entry.nextAllowedAttempt else { return }
        guard entry.peripheral.state == .disconnected else { return }
        entry.lastAttempt = now
        entry.nextAllowedAttempt = now.addingTimeInterval(connectionRetryBase)
        discoveredPeripherals[id] = entry
        centralManager.connect(entry.peripheral, options: nil)
        debugLog.add("接続開始(peripheral): \(shortId(id.uuidString))")
    }

    private func noteFailure(for peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard var entry = discoveredPeripherals[id] else { return }
        entry.failureCount += 1
        let delay = min(connectionRetryMax, connectionRetryBase * Double(entry.failureCount))
        entry.nextAllowedAttempt = Date().addingTimeInterval(delay)
        discoveredPeripherals[id] = entry
        debugLog.add("失敗(peripheral): \(shortId(id.uuidString)) (count \(entry.failureCount))")
    }

    private func markSuccess(for peripheral: CBPeripheral) {
        let id = peripheral.identifier
        recentPeripheralIds[id] = Date().addingTimeInterval(peripheralCooldown)
        discoveredPeripherals.removeValue(forKey: id)
        serviceDiscoveryRetried.remove(id)
        clearPendingValueState(for: id)
        debugLog.add("成功(peripheral): \(shortId(id.uuidString))")
    }

    private func disconnect(_ peripheral: CBPeripheral) {
        guard let centralManager else { return }
        guard peripheral.state != .disconnected else { return }
        disconnectingPeripherals.insert(peripheral.identifier)
        centralManager.cancelPeripheralConnection(peripheral)
        debugLog.add("切断(peripheral): \(shortId(peripheral.identifier.uuidString))")
    }

    private func notifyPayloadUpdate() {
        guard let peripheralManager, let userCharacteristic else { return }
        let didSend = peripheralManager.updateValue(payloadData, for: userCharacteristic, onSubscribedCentrals: nil)
        pendingNotify = !didSend
        debugLog.add("通知送信: \(didSend ? "OK" : "待機")")
    }
}

extension BluetoothEncounterManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        debugLog.add("Central 状態復元")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                peripheral.delegate = self
                updatePeripheralEntry(for: peripheral, seenAt: Date())
                if peripheral.state == .connected {
                    peripheral.discoverServices([serviceUUID])
                }
            }
        }
        if isActive {
            startScanningIfNeeded()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothPoweredOn = (central.state == .poweredOn)
        debugLog.add("Central 状態: \(central.state.rawValue)")
        guard central.state == .poweredOn else {
            debugStatus.setScanning(false)
            return
        }
        startScanningIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard isActive else { return }
        let now = Date()
        let id = peripheral.identifier
        guard shouldIgnorePeripheral(id, now: now) == false else { return }
        updatePeripheralEntry(for: peripheral, seenAt: now)
        peripheral.delegate = self
        debugLog.add("検出(peripheral): \(shortId(id.uuidString)) RSSI \(RSSI)")
        debugStatus.markDiscovered()
        attemptConnectionIfNeeded(for: id)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isActive else {
            disconnect(peripheral)
            return
        }
        debugLog.add("接続(peripheral): \(shortId(peripheral.identifier.uuidString))")
        // Discover all once to avoid missing a just-registered service due timing.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isActive else { return }
        debugLog.add("接続失敗(peripheral): \(shortId(peripheral.identifier.uuidString))")
        noteFailure(for: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard isActive else { return }
        let id = peripheral.identifier
        serviceDiscoveryRetried.remove(id)
        clearPendingValueState(for: id)
        if disconnectingPeripherals.remove(id) != nil {
            debugLog.add("切断完了(peripheral): \(shortId(id.uuidString))")
            return
        }
        debugLog.add("予期せぬ切断(peripheral): \(shortId(id.uuidString))")
        noteFailure(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard isActive else {
            disconnect(peripheral)
            return
        }
        guard error == nil else {
            debugLog.add("サービス発見失敗")
            noteFailure(for: peripheral)
            disconnect(peripheral)
            return
        }
        debugLog.add("サービス発見")
        let id = peripheral.identifier
        guard let services = peripheral.services else {
            debugLog.add("対象サービスなし: <nil>")
            noteFailure(for: peripheral)
            disconnect(peripheral)
            return
        }
        if services.isEmpty {
            if serviceDiscoveryRetried.insert(id).inserted {
                debugLog.add("サービス0件: 再探索")
                peripheral.discoverServices(nil)
                return
            }
            debugLog.add("対象サービスなし: <empty>")
            noteFailure(for: peripheral)
            disconnect(peripheral)
            return
        }
        serviceDiscoveryRetried.remove(id)
        let knownServices = services.filter { isKnownEncounterService($0.uuid) }
        let selectedServices: [CBService]
        if !knownServices.isEmpty {
            selectedServices = knownServices
        } else {
            let customServices = services.filter { !isLikelyStandardBluetoothUUID($0.uuid) }
            if !customServices.isEmpty {
                let available = services.map { $0.uuid.uuidString }.joined(separator: ",")
                debugLog.add("対象サービスなし: \(available) -> カスタムサービス特性フォールバック")
                selectedServices = customServices
            } else {
                let available = services.map { $0.uuid.uuidString }.joined(separator: ",")
                debugLog.add("対象サービスなし: \(available)")
                noteFailure(for: peripheral)
                disconnect(peripheral)
                return
            }
        }

        pendingServiceCharacteristicDiscovery[id] = selectedServices.count
        pendingCharacteristicReads[id] = 0
        pendingNotifyOnlyCharacteristics[id] = []
        pendingValueTimeouts[id]?.cancel()
        pendingValueTimeouts.removeValue(forKey: id)
        pendingValueRetryCount[id] = 0
        for service in selectedServices {
            // Discover all characteristics on selected services so older clients with
            // different characteristic UUIDs can still be read via fallback.
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isActive else {
            disconnect(peripheral)
            return
        }
        debugLog.add("特性発見")
        let id = peripheral.identifier
        if let error {
            debugLog.add("特性発見失敗: \(error.localizedDescription)")
            let servicesPending = max(0, (pendingServiceCharacteristicDiscovery[id] ?? 1) - 1)
            pendingServiceCharacteristicDiscovery[id] = servicesPending
            finalizeFailureIfNoPending(for: peripheral, fallbackMessage: "特性発見失敗")
            return
        }
        guard let characteristics = service.characteristics else {
            let servicesPending = max(0, (pendingServiceCharacteristicDiscovery[id] ?? 1) - 1)
            pendingServiceCharacteristicDiscovery[id] = servicesPending
            finalizeFailureIfNoPending(for: peripheral)
            return
        }
        let readable = characteristics.filter { $0.properties.contains(.read) }
        let notifyOnly = characteristics.filter { !$0.properties.contains(.read) && ($0.properties.contains(.notify) || $0.properties.contains(.indicate)) }
        let preferredReadable = readable.filter { isKnownEncounterCharacteristic($0.uuid) }
        let fallbackReadable = readable.filter { !isKnownEncounterCharacteristic($0.uuid) }
        let preferredNotifyOnly = notifyOnly.filter { isKnownEncounterCharacteristic($0.uuid) }
        let fallbackNotifyOnly = notifyOnly.filter { !isKnownEncounterCharacteristic($0.uuid) }
        let orderedReadable = preferredReadable + fallbackReadable
        let orderedNotifyOnly = preferredNotifyOnly + fallbackNotifyOnly

        pendingServiceCharacteristicDiscovery[id] = max(0, (pendingServiceCharacteristicDiscovery[id] ?? 1) - 1)
        let targetSummary = (orderedReadable + orderedNotifyOnly).map { "\($0.uuid.uuidString.prefix(8))[\(characteristicFlags($0.properties))]" }.joined(separator: ",")
        debugLog.add("特性候補: \(targetSummary.isEmpty ? "<none>" : targetSummary)")

        for target in orderedReadable {
            pendingCharacteristicReads[id, default: 0] += 1
            peripheral.readValue(for: target)
        }
        if !orderedNotifyOnly.isEmpty {
            var notifyList = pendingNotifyOnlyCharacteristics[id] ?? []
            for target in orderedNotifyOnly {
                pendingCharacteristicReads[id, default: 0] += 1
                notifyList.append(target)
                peripheral.setNotifyValue(true, for: target)
            }
            pendingNotifyOnlyCharacteristics[id] = notifyList
        }

        if orderedReadable.isEmpty && orderedNotifyOnly.isEmpty {
            debugLog.add("受信可能特性なし")
            finalizeFailureIfNoPending(for: peripheral)
            return
        }

        if (pendingServiceCharacteristicDiscovery[id] ?? 0) == 0 && (pendingCharacteristicReads[id] ?? 0) > 0 {
            schedulePendingValueTimeout(for: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard isActive else { return }
        let id = peripheral.identifier
        guard hasPendingNotifyCharacteristic(id: id, uuid: characteristic.uuid) else { return }
        if let error {
            debugLog.add("通知購読失敗: \(characteristic.uuid.uuidString.prefix(8)) \(error.localizedDescription)")
            var remaining = pendingCharacteristicReads[id] ?? 1
            remaining = max(0, remaining - 1)
            pendingCharacteristicReads[id] = remaining
            removePendingNotifyCharacteristic(id: id, uuid: characteristic.uuid)
            finalizeFailureIfNoPending(for: peripheral)
            return
        }
        if characteristic.isNotifying {
            debugLog.add("通知購読開始: \(characteristic.uuid.uuidString.prefix(8))")
            if characteristic.properties.contains(.writeWithoutResponse) {
                peripheral.writeValue(payloadData, for: characteristic, type: .withoutResponse)
                debugLog.add("通知特性へwrite試行: \(characteristic.uuid.uuidString.prefix(8)) type=withoutResponse")
            } else if characteristic.properties.contains(.write) {
                peripheral.writeValue(payloadData, for: characteristic, type: .withResponse)
                debugLog.add("通知特性へwrite試行: \(characteristic.uuid.uuidString.prefix(8)) type=withResponse")
            }
            schedulePendingValueTimeout(for: peripheral)
        } else {
            debugLog.add("通知停止: \(characteristic.uuid.uuidString.prefix(8))")
            var remaining = pendingCharacteristicReads[id] ?? 1
            remaining = max(0, remaining - 1)
            pendingCharacteristicReads[id] = remaining
            removePendingNotifyCharacteristic(id: id, uuid: characteristic.uuid)
            finalizeFailureIfNoPending(for: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isActive else { return }
        if let error {
            debugLog.add("write失敗: \(characteristic.uuid.uuidString.prefix(8)) \(error.localizedDescription)")
            return
        }
        debugLog.add("write成功: \(characteristic.uuid.uuidString.prefix(8))")
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isActive else {
            disconnect(peripheral)
            return
        }
        if let error {
            debugLog.add("値取得失敗: \(characteristic.uuid.uuidString.prefix(8)) \(error.localizedDescription)")
            var remaining = pendingCharacteristicReads[peripheral.identifier] ?? 1
            remaining = max(0, remaining - 1)
            pendingCharacteristicReads[peripheral.identifier] = remaining
            removePendingNotifyCharacteristic(id: peripheral.identifier, uuid: characteristic.uuid)
            finalizeFailureIfNoPending(for: peripheral)
            return
        }
        guard let data = characteristic.value else { return }
        if let payload = try? JSONDecoder().decode(EncounterUserPayload.self, from: data) {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            debugLog.addPayload(userId: payload.id, nickname: payload.nickname, raw: raw)
            debugLog.add("ユーザーID受信: user=\(shortId(payload.id))")
            clearPendingValueState(for: peripheral.identifier)
            handlePayload(payload)
            markSuccess(for: peripheral)
            disconnect(peripheral)
        } else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            debugLog.addRawPayload(raw)
            var remaining = pendingCharacteristicReads[peripheral.identifier] ?? 1
            remaining = max(0, remaining - 1)
            pendingCharacteristicReads[peripheral.identifier] = remaining
            removePendingNotifyCharacteristic(id: peripheral.identifier, uuid: characteristic.uuid)
            if remaining > 0 {
                debugLog.add("デコード失敗(継続): characteristic=\(characteristic.uuid.uuidString.prefix(8)) remaining=\(remaining)")
                finalizeFailureIfNoPending(for: peripheral)
                return
            }
            let servicesPending = pendingServiceCharacteristicDiscovery[peripheral.identifier] ?? 0
            if servicesPending > 0 {
                debugLog.add("デコード失敗待機: services_pending=\(servicesPending)")
                return
            }
            finalizeFailureIfNoPending(for: peripheral)
        }
    }
}

extension BluetoothEncounterManager: CBPeripheralManagerDelegate {
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        debugLog.add("Peripheral 状態復元")
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBService],
           services.contains(where: { $0.uuid == serviceUUID }) {
            isServiceAdded = true
        }
        if isActive {
            startAdvertising()
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        isBluetoothPoweredOn = (peripheral.state == .poweredOn)
        debugLog.add("Peripheral 状態: \(peripheral.state.rawValue)")
        guard peripheral.state == .poweredOn else {
            debugStatus.setAdvertising(false)
            return
        }
        startAdvertising()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard service.uuid == serviceUUID else { return }
        guard error == nil else { return }
        isServiceAdded = true
        debugLog.add("サービス追加完了")
        if shouldAdvertiseWhenReady {
            shouldAdvertiseWhenReady = false
            startAdvertising()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == userCharacteristicUUID else { return }
        guard isActive else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }
        debugLog.add("Read 要求")
        let data = payloadData
        if request.offset > data.count {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        let maxLength = request.central.maximumUpdateValueLength
        let chunkLength = maxLength > 0 ? maxLength : data.count
        let end = min(data.count, request.offset + chunkLength)
        request.value = data.subdata(in: request.offset..<end)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard pendingNotify else { return }
        guard isActive else {
            pendingNotify = false
            return
        }
        pendingNotify = false
        notifyPayloadUpdate()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == userCharacteristicUUID else { return }
        guard isActive else { return }
        debugLog.add("Subscribe 受信")
        notifyPayloadUpdate()
    }
}
