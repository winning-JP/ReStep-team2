import SwiftUI

@main
struct ReStepApp: App {
    @StateObject private var stampsStore = StampsStore.shared
    @StateObject private var locationManager = LocationManager()
    @StateObject private var notificationManager = NotificationManager()
    @StateObject private var chocozapStampManager: ChocozapStampManager
    @StateObject private var session = AuthSession()
    @StateObject private var statsSyncManager = StatsSyncManager.shared
    private let encounterRuntime = BluetoothEncounterRuntimeController.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingSplash = true
    @AppStorage("restep.encounter.enabled") private var encounterEnabled: Bool = false
    @AppStorage("restep.encounter.shareNickname") private var encounterShareNickname: Bool = true
    @AppStorage("restep.encounter.batterySaver") private var encounterBatterySaver: Bool = false
    @AppStorage("restep.profile.nickname") private var encounterNickname: String = ""
    @AppStorage("restep.encounter.notifications") private var encounterNotifications: Bool = true

    init() {
        let locationManager = LocationManager()
        let notificationManager = NotificationManager()
        _locationManager = StateObject(wrappedValue: locationManager)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _chocozapStampManager = StateObject(wrappedValue: ChocozapStampManager(stampsStore: StampsStore.shared, locationManager: locationManager, notificationManager: notificationManager))
        BluetoothEncounterRuntimeController.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isShowingSplash {
                    SplashScreenView(onFinish: {})
                } else {
                    AuthGateView()
                }
            }
            .environmentObject(stampsStore)
            .environmentObject(locationManager)
            .environmentObject(notificationManager)
            .environmentObject(chocozapStampManager)
            .environmentObject(session)
            .environmentObject(statsSyncManager)
            .onReceive(NotificationCenter.default.publisher(for: EncounterStampTracker.didAwardStampsNotification)) { notification in
                let count = notification.userInfo?["count"] as? Int ?? 1
                stampsStore.addBonusStamp(count: count)
            }
            .onReceive(NotificationCenter.default.publisher(for: EncounterRecorder.didDetectEncounterNotification)) { notification in
                guard encounterNotifications, notificationManager.isEnabled else { return }
                let name = notification.userInfo?["name"] as? String ?? "旅人"
                notificationManager.notifyEncounter(name: name)
            }
            .onChange(of: session.didRestore) { _, didRestore in
                guard didRestore else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    isShowingSplash = false
                }
                statsSyncManager.startPeriodic()
                Task {
                    await statsSyncManager.seedContinuityFromLocalIfNeeded(isLoggedIn: session.isLoggedIn)
                    await statsSyncManager.recordContinuityIfNeeded(isLoggedIn: session.isLoggedIn)
                    await statsSyncManager.refreshContinuity(isLoggedIn: session.isLoggedIn)
                    await statsSyncManager.syncIfNeeded(reason: "restore", isLoggedIn: session.isLoggedIn)
                }
                if session.isLoggedIn {
                    stampsStore.refreshBalance()
                }
                encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
            }
            .onChange(of: session.isLoggedIn) { _, isLoggedIn in
                if isLoggedIn {
                    stampsStore.refreshBalance()
                    Task {
                        await statsSyncManager.seedContinuityFromLocalIfNeeded(isLoggedIn: true)
                        await statsSyncManager.recordContinuityIfNeeded(isLoggedIn: true)
                        await statsSyncManager.refreshContinuity(isLoggedIn: true)
                    }
                } else {
                    encounterRuntime.stop()
                }
                encounterRuntime.refresh(isLoggedIn: isLoggedIn)
            }
            .onChange(of: encounterEnabled) { _, _ in
                encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
            }
            .onChange(of: encounterShareNickname) { _, _ in
                encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
            }
            .onChange(of: encounterBatterySaver) { _, _ in
                encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
            }
            .onChange(of: encounterNickname) { _, _ in
                encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task {
                        await statsSyncManager.seedContinuityFromLocalIfNeeded(isLoggedIn: session.isLoggedIn)
                        await statsSyncManager.recordContinuityIfNeeded(isLoggedIn: session.isLoggedIn)
                        await statsSyncManager.syncIfNeeded(reason: "active", isLoggedIn: session.isLoggedIn)
                    }
                    if session.isLoggedIn {
                        stampsStore.refreshBalance()
                    }
                    encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
                case .background, .inactive:
                    Task { await statsSyncManager.syncIfNeeded(reason: "background", isLoggedIn: session.isLoggedIn) }
                    encounterRuntime.refresh(isLoggedIn: session.isLoggedIn)
                @unknown default:
                    break
                }
            }
        }
    }
}
