import SwiftUI

struct EncounterListView: View {
    @State private var encounters: [Encounter] = []
    @State private var stampProgress = EncounterStampProgress(count: 0, awardedCount: 0, thresholds: [])

    var body: some View {
        Group {
            if encounters.isEmpty {
                VStack(spacing: 12) {
                    EncounterStampProgressCard(progress: stampProgress)
                    Text("まだすれ違いがありません")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        EncounterStampProgressCard(progress: stampProgress)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color(.systemGroupedBackground))
                    }

                    Section {
                        ForEach(encounters) { encounter in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.orange.opacity(0.18))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String(encounter.traveler.name.prefix(1)))
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(encounter.traveler.name)
                                        .font(.headline)
                                    Text(encounter.traveler.job)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(encounter.displayDateTime)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(encounter.source.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("すれ違い履歴")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadEncounters()
            loadStampProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: EncounterRecorder.didUpdateNotification)) { _ in
            loadEncounters()
            loadStampProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: EncounterStampTracker.didAwardStampsNotification)) { _ in
            loadStampProgress()
        }
    }

    private func loadEncounters() {
        encounters = GameStore.shared.loadEncounters().sorted { $0.date > $1.date }
    }

    private func loadStampProgress() {
        stampProgress = EncounterStampTracker.shared.todayProgress()
    }
}

private struct EncounterStampProgressCard: View {
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

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日のすれ違い")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(progress.count)回")
                        .font(.title2.bold())
                }
                Spacer()
                Text("獲得 \(progress.awardedCount)")
                    .font(.caption.bold())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            }

            Text(nextText)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(progress.thresholds, id: \.self) { threshold in
                    let reached = progress.count >= threshold
                    Text("\(threshold)")
                        .font(.caption2.bold())
                        .foregroundColor(reached ? .white : .secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(reached ? Color.orange : Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterListView()
        }
    }
}
#endif
