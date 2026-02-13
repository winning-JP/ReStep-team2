import SwiftUI

struct StampCardView: View {
    @EnvironmentObject private var stampsStore: StampsStore
    @EnvironmentObject private var session: AuthSession
    let total: Int = 10
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<total, id: \.self) { index in
                        StampCardSlot(isFilled: index < displayStamps)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.thinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

                controls

                Spacer(minLength: 0)
            }
            .padding(.vertical)
            .navigationTitle("スタンプ")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if session.isLoggedIn {
                    stampsStore.refreshBalance()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("スタンプカード")
                .font(.title2.bold())

            ProgressView(value: Double(displayStamps), total: Double(total))
                .tint(.blue)

            Text("\(displayStamps) / \(total) 個")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { _ = await stampsStore.spend(1, reason: "manual_adjust") }
            } label: {
                Label("減らす", systemImage: "minus.circle")
            }
            .buttonStyle(.bordered)

            Button {
                stampsStore.addBonusStamp(count: 1, reason: "manual_adjust")
            } label: {
                Label("貯める", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .disabled(!session.isLoggedIn)
    }

    private var displayStamps: Int {
        min(stampsStore.balance, total)
    }
}

private struct StampCardSlot: View {
    let isFilled: Bool
    @State private var pop: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isFilled ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isFilled ? Color.blue.opacity(0.35) : Color.secondary.opacity(0.18),
                            style: StrokeStyle(lineWidth: 1, dash: isFilled ? [] : [6, 4])
                        )
                )

            if isFilled {
                Image(systemName: "seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                    .scaleEffect(pop ? 1.15 : 1.0)
                    .onAppear {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                            pop = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                pop = false
                            }
                        }
                    }
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(isFilled ? "スタンプ獲得済み" : "未獲得")
    }
}
