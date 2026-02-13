import SwiftUI

struct EncounterBattleListView: View {
    @State private var encounters: [Encounter] = []
    @State private var playedIds: Set<UUID> = []

    var body: some View {
        VStack(spacing: 16) {
            if encounters.isEmpty {
                Text("すれ違いがありません")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(encounters) { encounter in
                            NavigationLink {
                                EncounterBattleView(encounter: encounter, onPlayed: markPlayed)
                            } label: {
                                battleRow(encounter, isPlayed: playedIds.contains(encounter.traveler.id))
                            }
                            .disabled(playedIds.contains(encounter.traveler.id))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("すれ違いバトル")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            encounters = GameStore.shared.loadEncounters().sorted { $0.date > $1.date }
            playedIds = EncounterBattleStore.loadPlayed()
        }
    }

    private func battleRow(_ encounter: Encounter, isPlayed: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(encounter.traveler.name.prefix(1)))
                        .font(.headline)
                        .foregroundColor(.purple)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(encounter.traveler.name)
                    .font(.headline)
                Text(encounter.traveler.job)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(isPlayed ? "プレイ済み" : "プレイ")
                .font(.caption.weight(.semibold))
                .foregroundColor(isPlayed ? .secondary : .white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isPlayed ? Color(.systemGray6) : Color.purple)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .opacity(isPlayed ? 0.6 : 1.0)
    }

    private func markPlayed(_ encounterId: UUID) {
        playedIds.insert(encounterId)
        EncounterBattleStore.savePlayed(playedIds)
    }
}

struct EncounterBattleView: View {
    let encounter: Encounter
    let onPlayed: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var resultText: String = "準備完了"
    @State private var isFinished = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("\(encounter.traveler.name) と対決！")
                .font(.title2.bold())

            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .frame(height: 200)
                .overlay(
                    VStack(spacing: 8) {
                        Text("すれ違いバトル")
                            .font(.headline)
                        Text(isFinished ? "勝利！" : "バトル開始")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.purple)
                    }
                )

            Text(resultText)
                .font(.body.weight(.semibold))
                .foregroundColor(.secondary)

            Button {
                let outcomes = ["勝利！報酬 +1", "引き分け", "勝利！経験値 +20"]
                resultText = outcomes.randomElement() ?? "勝利！"
                isFinished = true
                onPlayed(encounter.traveler.id)
            } label: {
                Text(isFinished ? "完了" : "バトルする")
                    .font(.body.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .disabled(isFinished)

            if isFinished {
                Button {
                    dismiss()
                } label: {
                    Text("戻る")
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.8))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("バトル")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

enum EncounterBattleStore {
    private static let key = "restep.encounterBattle.playedIds"

    static func loadPlayed() -> Set<UUID> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    static func savePlayed(_ ids: Set<UUID>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterBattleListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterBattleListView()
        }
    }
}
#endif
