import SwiftUI

struct TravelerDetailView: View {
    @State private var traveler: Traveler
    @State private var inventory: Inventory = GameStore.shared.loadInventory()

    init(traveler: Traveler) {
        _traveler = State(initialValue: traveler)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(traveler.name)
                .font(.title2.bold())
            Text(traveler.job)
                .font(.body)
                .foregroundColor(.secondary)
            Text("気配：\(traveler.rarity.label)")
                .font(.subheadline)
            Text("固有スキル：\(traveler.skill)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 6) {
                Text("成長させる")
                    .font(.headline)
                Button {
                    guard inventory.materials >= 1 else { return }
                    inventory.materials -= 1
                    traveler.level += 1
                    traveler.stats.hp += 2
                    traveler.stats.atk += 1
                    traveler.stats.def += 1
                    traveler.stats.agi += 1
                    persist()
                } label: {
                    Text("静かに鍛える")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.cyan)
                        .clipShape(Capsule())
                }
                .disabled(inventory.materials < 1)
                Text("必要素材がある時に成長します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding()
        .navigationTitle("旅人詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            inventory = GameStore.shared.loadInventory()
        }
    }

    private func persist() {
        GameStore.shared.saveInventory(inventory)
        var travelers = GameStore.shared.loadTravelers()
        if let index = travelers.firstIndex(where: { $0.id == traveler.id }) {
            travelers[index] = traveler
            GameStore.shared.saveTravelers(travelers)
        }
    }
}

#if DEBUG
@available(iOS 17, *)
struct TravelerDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TravelerDetailView(traveler: Traveler(name: "ミオ", job: "旅の料理人", rarity: .two, stats: Stats(hp: 28, atk: 6, def: 4, agi: 5), skill: "体力回復"))
        }
    }
}
#endif
