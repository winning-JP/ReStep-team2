import SwiftUI

struct EncounterRaidView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var progress = EncounterStampProgress(count: 0, awardedCount: 0, thresholds: [])
    @State private var encounterCount: Int = 0
    @State private var glow = false
    @State private var showChest = false
    @AppStorage("restep.raid.bonus") private var selectedBonus: String = "attack"

    private var bossName: String { "レイドスライム" }
    private var bossHpMax: Int { 100 }
    private var bossHpRemaining: Int {
        let damage = min(bossHpMax, encounterCount * 5)
        return max(0, bossHpMax - damage)
    }

    private var remainingForClear: Int {
        let required = Int(ceil(Double(bossHpMax) / 5.0))
        return max(0, required - encounterCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    bossCard

                    bonusChoiceCard

                    raidProgressCard

                    rewardCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("すれ違いレイド")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .onAppear {
                loadState()
            }
            .overlay {
                if showChest {
                    TreasureOverlay {
                        showChest = false
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日のレイド")
                .font(.title2.bold())
            Text("すれ違い1回＝ボスHP-5")
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bossCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bossName)
                        .font(.headline)
                    Text("HP \(bossHpRemaining)/\(bossHpMax)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image("enemy_slime")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
            }

            ProgressBar(progress: Double(bossHpMax - bossHpRemaining) / Double(bossHpMax), accentColor: .orange)
                .frame(height: 10)
                .shadow(color: Color.orange.opacity(glow ? 0.7 : 0.2), radius: glow ? 10 : 4, x: 0, y: 0)

            Text("討伐まであと\(remainingForClear)回")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private var bonusChoiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("次のすれ違い効果を選ぶ")
                .font(.headline)

            HStack(spacing: 8) {
                bonusChip(id: "attack", title: "攻撃+")
                bonusChip(id: "guard", title: "守り+")
                bonusChip(id: "loot", title: "ドロップ+")
            }

            Text(nextEffectText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private var raidProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("すれ違いゲージ")
                    .font(.headline)
                Spacer()
                Text("\(encounterCount)回")
                    .font(.caption.bold())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            Text(remainingForClear > 0 ? "討伐まであと\(remainingForClear)回" : "討伐完了！")
                .font(.subheadline.weight(.semibold))

            RaidStampProgressCard(progress: progress)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var rewardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("報酬")
                .font(.headline)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "tshirt.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("限定衣装を解放")
                        .font(.subheadline.weight(.semibold))
                    Text("あと\(remainingForClear)回でゲット")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if remainingForClear == 0 {
                Button {
                    showChest = true
                } label: {
                    Text("宝箱を開ける")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private func loadState() {
        let all = GameStore.shared.loadEncounters()
        encounterCount = all.count
        progress = EncounterStampTracker.shared.todayProgress()
    }

    private func bonusChip(id: String, title: String) -> some View {
        Button {
            selectedBonus = id
            triggerGlow()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(selectedBonus == id ? .white : .primary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(selectedBonus == id ? Color.orange : Color(.systemGray5))
                .clipShape(Capsule())
        }
    }

    private var nextEffectText: String {
        switch selectedBonus {
        case "guard":
            return "次のすれ違いで被ダメ軽減"
        case "loot":
            return "次のすれ違いで報酬率アップ"
        default:
            return "次のすれ違いでボスHPが大きく減る"
        }
    }

    private func triggerGlow() {
        withAnimation(.easeOut(duration: 0.2)) {
            glow = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                glow = false
            }
        }
    }
}

private struct TreasureOverlay: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Text("宝箱を開けた！")
                    .font(.headline)
                    .foregroundColor(.white)
                Button("OK") {
                    onClose()
                }
                .font(.caption.bold())
                .foregroundColor(.black)
                .padding(.vertical, 6)
                .padding(.horizontal, 16)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .padding(20)
            .background(Color.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct RaidStampProgressCard: View {
    let progress: EncounterStampProgress

    var body: some View {
        let nextText: String = {
            if let remaining = progress.remainingToNext, let next = progress.nextThreshold {
                return "次のスタンプまであと\(remaining)回（\(next)回目）"
            }
            if progress.thresholds.isEmpty {
                return "スタンプ条件を準備中"
            }
            return "本日のスタンプ上限達成"
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日のすれ違い")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("獲得 \(progress.awardedCount)")
                    .font(.caption.bold())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            }

            Text(nextText)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(progress.thresholds, id: \.self) { threshold in
                    let reached = progress.count >= threshold
                    Text("\(threshold)")
                        .font(.caption2.bold())
                        .foregroundColor(reached ? .white : .secondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(reached ? Color.orange : Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterRaidView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterRaidView()
        }
    }
}
#endif
