import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }

            ChallengeView()
                .tabItem {
                    Label("チャレンジ", systemImage: "flame.fill")
                }

            TargetView()
                .tabItem {
                    Label("目標", systemImage: "target")
                }

            EncounterGameSelectView()
                .tabItem {
                    Label("すれ違い", systemImage: "person.2.circle")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
        }
    }
}

// =========================
// Preview
// =========================
@available(iOS 17, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthSession())
            .environmentObject(LocationManager())
            .environmentObject(NotificationManager())
            .environmentObject(StampsStore.shared)
    }
}
