import Foundation
import CoreBluetooth
import Observation

@MainActor
@Observable
final class BluetoothDiagnosticsManager: NSObject {
    private(set) var authorization: CBManagerAuthorization = CBManager.authorization
    private(set) var centralState: CBManagerState = .unknown
    private(set) var peripheralState: CBManagerState = .unknown
    private(set) var lastUpdated: Date?
    private(set) var isRunning: Bool = false

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var timeoutTask: Task<Void, Never>?

    func start() {
        isRunning = true
        authorization = CBManager.authorization
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: .main,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
        )
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.isRunning = false
        }
        touchUpdated()
    }

    var authorizationStatusText: String {
        switch authorization {
        case .notDetermined:
            return "未確認"
        case .restricted:
            return "制限あり"
        case .denied:
            return "拒否"
        case .allowedAlways:
            return "許可"
        @unknown default:
            return "不明"
        }
    }

    var centralStateText: String {
        switch centralState {
        case .unknown:
            return "不明"
        case .resetting:
            return "リセット中"
        case .unsupported:
            return "非対応"
        case .unauthorized:
            return "未許可"
        case .poweredOff:
            return "OFF"
        case .poweredOn:
            return "ON"
        @unknown default:
            return "不明"
        }
    }

    var peripheralStateText: String {
        switch peripheralState {
        case .unknown:
            return "不明"
        case .resetting:
            return "リセット中"
        case .unsupported:
            return "非対応"
        case .unauthorized:
            return "未許可"
        case .poweredOff:
            return "OFF"
        case .poweredOn:
            return "ON"
        @unknown default:
            return "不明"
        }
    }

    private func touchUpdated() {
        lastUpdated = Date()
    }
}

extension BluetoothDiagnosticsManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        authorization = CBManager.authorization
        centralState = central.state
        touchUpdated()
        isRunning = false
    }
}

extension BluetoothDiagnosticsManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        authorization = CBManager.authorization
        peripheralState = peripheral.state
        touchUpdated()
        isRunning = false
    }
}
