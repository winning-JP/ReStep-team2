import SwiftUI

struct PuzzleCollectionView: View {
    let collectedPieces: [Int]
    @State private var showCompleteAlert = false
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let treasure = TreasureAPIClient.shared
    private let totalPieces = 9
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var isComplete: Bool { collectedPieces.count >= totalPieces }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 進捗
                VStack(spacing: 8) {
                    Text("パズル収集")
                        .font(.headline)

                    Text("\(collectedPieces.count) / \(totalPieces)")
                        .font(.system(size: 28, weight: .bold))

                    ProgressView(value: Double(collectedPieces.count), total: Double(totalPieces))
                        .tint(.purple)
                        .padding(.horizontal, 40)
                }

                // パズルグリッド
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<totalPieces, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(collectedPieces.contains(index) ? Color.purple.opacity(0.3) : Color.gray.opacity(0.1))
                                .aspectRatio(1, contentMode: .fit)

                            if collectedPieces.contains(index) {
                                Image(systemName: "puzzlepiece.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.purple)
                            } else {
                                Image(systemName: "questionmark")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.gray.opacity(0.4))
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)

                if isComplete {
                    VStack(spacing: 12) {
                        Text("パズル完成!")
                            .font(.title2.bold())
                            .foregroundStyle(.purple)

                        Button {
                            Task { await completePuzzle() }
                        } label: {
                            HStack {
                                Image(systemName: "gift.fill")
                                Text("報酬を受け取る (コイン500)")
                            }
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .disabled(isCompleting)
                    }
                } else {
                    Text("宝箱を開けてピースを集めよう!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("パズル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("報酬獲得!", isPresented: $showCompleteAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("コイン500枚を獲得しました! 新しいパズルが始まります。")
            }
        }
    }

    private func completePuzzle() async {
        isCompleting = true
        errorMessage = nil
        do {
            _ = try await treasure.completePuzzle(puzzleId: 1)
            showCompleteAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isCompleting = false
    }
}
