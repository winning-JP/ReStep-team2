import SwiftUI

struct EncounterSettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @AppStorage("restep.encounter.enabled") private var encounterEnabled: Bool = false
    @AppStorage("restep.encounter.shareNickname") private var shareNickname: Bool = true
    @AppStorage("restep.encounter.notifications") private var encounterNotifications: Bool = true
    @AppStorage("restep.encounter.batterySaver") private var batterySaver: Bool = false
    @AppStorage("restep.encounter.historyDays") private var historyDays: Int = 7
    @AppStorage("restep.encounter.debugRunning") private var debugRunning: Bool = false
    @AppStorage("restep.encounter.debugNickname") private var debugNickname: String = ""
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var diagnostics = BluetoothDiagnosticsManager()
    @State private var debugController = BluetoothEncounterDebugController.shared

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("すれ違い通信")) {
                    Toggle("すれ違い通信", isOn: $encounterEnabled)
                    Toggle("ニックネーム共有", isOn: $shareNickname)
                }

                Section(header: Text("通知")) {
                    Toggle("すれ違い通知", isOn: $encounterNotifications)
                        .disabled(!notificationManager.isEnabled)
                }

                Section(header: Text("バッテリー")) {
                    Toggle("節電モード", isOn: $batterySaver)
                    Text("節電モードは探索間隔を広げます。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("履歴")) {
                    Picker("保存期間", selection: $historyDays) {
                        Text("1日").tag(1)
                        Text("3日").tag(3)
                        Text("7日").tag(7)
                        Text("14日").tag(14)
                        Text("30日").tag(30)
                    }
                }

                Section(header: Text("診断")) {
                    Button("Bluetooth診断を実行") {
                        diagnostics.start()
                    }

                    if diagnostics.isRunning {
                        Text("診断中…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    diagnosisRow("権限", value: diagnostics.authorizationStatusText)
                    diagnosisRow("Bluetooth電源", value: diagnostics.centralStateText)
                    diagnosisRow("周辺機器", value: diagnostics.peripheralStateText)

#if targetEnvironment(simulator)
                    Text("シミュレーターではBluetoothは利用できません。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
#endif

                    if let updatedAt = diagnostics.lastUpdated {
                        Text("最終更新: \(updatedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("デバッグ")) {
                    Toggle("デバッグ用すれ違い起動", isOn: $debugRunning)
                        .onChange(of: debugRunning) { _, newValue in
                            if newValue {
                                debugController.start(overrideNickname: debugNickname)
                            } else {
                                debugController.stop()
                                BluetoothEncounterRuntimeController.shared.refresh(isLoggedIn: true)
                            }
                        }
                    Text("このスイッチは設定画面から強制的にBluetoothスキャン/広告を行います。")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    TextField("デバッグ用ニックネーム(任意)", text: $debugNickname)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: debugNickname) { _, newValue in
                            guard debugRunning else { return }
                            debugController.restart(overrideNickname: newValue)
                        }

                    BluetoothDebugView()
                }
            }
            .navigationTitle("すれ違い設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
        }
        .onChange(of: notificationManager.isEnabled) { _, newValue in
            if !newValue {
                encounterNotifications = false
            }
        }
        .onChange(of: encounterEnabled) { _, _ in
            BluetoothEncounterRuntimeController.shared.refresh(isLoggedIn: session.isLoggedIn)
        }
        .onChange(of: shareNickname) { _, _ in
            BluetoothEncounterRuntimeController.shared.refresh(isLoggedIn: session.isLoggedIn)
        }
        .onChange(of: batterySaver) { _, _ in
            BluetoothEncounterRuntimeController.shared.refresh(isLoggedIn: session.isLoggedIn)
        }
        .onAppear {
            if debugRunning {
                debugController.start(overrideNickname: debugNickname)
            } else {
                BluetoothEncounterRuntimeController.shared.refresh(isLoggedIn: session.isLoggedIn)
            }
        }
    }

    private func diagnosisRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        EncounterSettingsView()
    }
}
#endif
