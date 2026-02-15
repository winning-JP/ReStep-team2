import SwiftUI

struct TreasureBoxView: View {
    @State private var isOpening = false
    @State private var showResult = false
    @State private var rewardType: String = ""
    @State private var rewardValue: Int = 0
    @State private var rewardMessage: String = ""
    @State private var rewardIcon: String = ""
    @State private var collectedPieces: [Int] = []
    @State private var isComplete = false
    @State private var boxScale: CGFloat = 1.0
    @State private var boxRotation: Double = 0
    @State private var errorMessage: String?
    @State private var showPuzzle = false

    private let treasure = TreasureAPIClient.shared

    var body: some View {
        VStack(spacing: 24) {
            // パズル進捗
            Button {
                showPuzzle = true
            } label: {
                HStack {
                    Image(systemName: "puzzlepiece.fill")
                    Text("パズル: \(collectedPieces.count)/9")
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .clipShape(Capsule())
            }

            Spacer()

            // 宝箱
            VStack(spacing: 16) {
                Text(showResult ? rewardIcon : "📦")
                    .font(.system(size: 80))
                    .scaleEffect(boxScale)
                    .rotationEffect(.degrees(boxRotation))

                if showResult {
                    VStack(spacing: 8) {
                        Text(rewardMessage)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)

                        if rewardType == "puzzle_piece" {
                            Text("パズルピースを獲得!")
                                .font(.subheadline)
                                .foregroundStyle(.purple)
                        }
                    }
                    .transition(.opacity.combined(with: .scale))
                } else {
                    Text("タップして宝箱を開けよう")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 開けるボタン
            Button {
                Task { await openBox() }
            } label: {
                Text(showResult ? "もう一度開ける" : "宝箱を開ける")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isOpening ? Color.gray : Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isOpening)
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("宝箱さがし")
        .onAppear { Task { await loadPuzzleStatus() } }
        .sheet(isPresented: $showPuzzle) {
            PuzzleCollectionView(collectedPieces: collectedPieces)
        }
    }

    private func openBox() async {
        showResult = false
        isOpening = true
        errorMessage = nil

        // アニメーション: 揺れる
        withAnimation(.easeInOut(duration: 0.1).repeatCount(6, autoreverses: true)) {
            boxRotation = 10
        }

        try? await Task.sleep(nanoseconds: 600_000_000)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            boxScale = 1.3
            boxRotation = 0
        }

        do {
            let response = try await treasure.openBox(puzzleId: 1)
            rewardType = response.rewardType
            rewardValue = response.rewardValue

            switch response.rewardType {
            case "puzzle_piece":
                rewardIcon = "🧩"
                rewardMessage = "パズルピースを手に入れた!"
                if let pieces = response.collectedPieces {
                    collectedPieces = pieces
                }
                if response.isComplete == true {
                    isComplete = true
                    rewardMessage = "パズル完成! おめでとう!"
                }
            case "coin_penalty":
                rewardIcon = "💸"
                let penalty = response.actualPenalty ?? response.rewardValue
                rewardMessage = "残念賞... コイン -\(penalty)"
            case "experience":
                rewardIcon = "✨"
                rewardMessage = "経験値 +\(response.rewardValue)"
            case "reserved":
                rewardIcon = "🎁"
                rewardMessage = "??? (準備中)"
            default:
                rewardIcon = "❓"
                rewardMessage = "不明な景品"
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                boxScale = 1.0
                showResult = true
            }
        } catch {
            errorMessage = error.localizedDescription
            withAnimation { boxScale = 1.0 }
        }

        isOpening = false
    }

    private func loadPuzzleStatus() async {
        do {
            let status = try await treasure.fetchPuzzleStatus(puzzleId: 1)
            collectedPieces = status.pieces.map(\.pieceIndex)
            isComplete = status.isComplete
        } catch {
            DebugLog.log("TreasureBox.loadPuzzle error: \(error.localizedDescription)")
        }
    }
}
