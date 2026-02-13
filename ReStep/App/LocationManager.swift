import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            applyEnabledState()
        }
    }

    private let manager = CLLocationManager()
    private var isApplyingState = false
    private static let enabledKey = "restep.location.enabled"

    override init() {
        authorizationStatus = manager.authorizationStatus
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        applyEnabledState()
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        isEnabled = true
    }

    func stopUpdating() {
        isEnabled = false
    }

    func refreshIfEnabled() {
        guard isEnabled else { return }
        applyEnabledState()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            if isEnabled {
                manager.startUpdatingLocation()
            }
        } else {
            manager.stopUpdatingLocation()
            lastLocation = nil
            if isEnabled, authorizationStatus != .notDetermined {
                isEnabled = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    private func applyEnabledState() {
        guard !isApplyingState else { return }
        isApplyingState = true
        defer { isApplyingState = false }

        guard isEnabled else {
            manager.stopUpdatingLocation()
            lastLocation = nil
            return
        }

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            lastLocation = nil
        }
    }
}
