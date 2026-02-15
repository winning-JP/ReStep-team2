import SwiftUI

struct GoldStampView: View {
    @StateObject private var coinTracker = CoinUsageTracker.shared
    @State private var goldStampBalance: Int = 0
    @State private var goldStampTotalEarned: Int = 0
    @State private var coinBalance: Int = 0
    @State private var showExchangeConfirm = false
    @State private var showUseSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let wallet = WalletAPIClient.shared
    private let exchangeCost = 5000

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ゴールドスタンプ残高
                VStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)

                    Text("\(goldStampBalance)")
                        .font(.system(size: 36, weight: .bold))
                    Text("ゴールドスタンプ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )

                // コインからゴールドスタンプに交換
                VStack(spacing: 12) {
                    Text("ゴールドスタンプ交換")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("コイン \(exchangeCost)枚")
                                .font(.subheadline)
                            Text("→ ゴールドスタンプ 1枚")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            showExchangeConfirm = true
                        } label: {
                            Text("交換")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(coinBalance >= exchangeCost ? Color.yellow : Color.gray.opacity(0.3))
                                .foregroundStyle(coinBalance >= exchangeCost ? .black : .secondary)
                                .clipShape(Capsule())
                        }
                        .disabled(coinBalance < exchangeCost || isLoading)
                    }

                    Text("所持コイン: \(coinBalance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("本日のコイン使用: \(coinTracker.dailyUsed)/\(coinTracker.dailyLimit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 4)
                )

                // ゴールドスタンプ使用
                VStack(spacing: 12) {
                    Text("ゴールドスタンプを使う")
                        .font(.headline)

                    Button {
                        showUseSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "gift.fill")
                            Text("使用する")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(goldStampBalance > 0 ? Color.orange : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(goldStampBalance <= 0)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 4)
                )

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("ゴールドスタンプ")
        .onAppear { Task { await loadData() } }
        .alert("ゴールドスタンプ交換", isPresented: $showExchangeConfirm) {
            Button("交換する") { Task { await exchange() } }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("\(exchangeCost)コインを消費してゴールドスタンプ1枚と交換しますか？")
        }
        .sheet(isPresented: $showUseSheet) {
            GoldStampRewardView(
                goldStampBalance: $goldStampBalance,
                onUsed: { Task { await loadData() } }
            )
        }
    }

    private func loadData() async {
        do {
            async let gsResponse = wallet.fetchGoldStampBalance()
            async let coinResponse = wallet.fetchBalance()
            let (gs, coin) = try await (gsResponse, coinResponse)
            goldStampBalance = gs.balance
            goldStampTotalEarned = gs.totalEarned
            coinBalance = coin.balance
            await coinTracker.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exchange() async {
        isLoading = true
        errorMessage = nil
        do {
            let requestId = "gs_exchange_\(UUID().uuidString)"
            let response = try await wallet.exchangeGoldStamp(clientRequestId: requestId)
            goldStampBalance = response.goldStampBalance
            goldStampTotalEarned = response.goldStampTotalEarned
            coinBalance = response.coinBalance
            await coinTracker.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct GoldStampRewardView: View {
    @Binding var goldStampBalance: Int
    let onUsed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private let wallet = WalletAPIClient.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("ゴールドスタンプ: \(goldStampBalance)枚")
                    .font(.headline)

                // 選択肢1: コイン上限拡張
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)

                    Text("コイン使用上限を拡張")
                        .font(.headline)

                    Text("1スタンプ = +10コイン/日")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Stepper("使用数: \(amount)", value: $amount, in: 1...goldStampBalance)
                        .padding(.horizontal)

                    Text("上限 +\(amount * 10)コイン/日")
                        .font(.caption)
                        .foregroundStyle(.blue)

                    Button {
                        Task { await useForCoinLimit() }
                    } label: {
                        Text("上限拡張する")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(isLoading)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3))
                )

                // 選択肢2: リアル景品（仮）
                VStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)

                    Text("リアル景品と交換")
                        .font(.headline)

                    Text("準備中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3))
                )
                .opacity(0.5)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("スタンプ使用")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("拡張完了", isPresented: $showSuccess) {
                Button("OK") {
                    onUsed()
                    dismiss()
                }
            } message: {
                Text("コイン使用上限が拡張されました")
            }
        }
    }

    private func useForCoinLimit() async {
        isLoading = true
        errorMessage = nil
        do {
            let requestId = "gs_use_\(UUID().uuidString)"
            let response = try await wallet.useGoldStamp(amount: amount, useType: "coin_limit_expand", clientRequestId: requestId)
            goldStampBalance = response.goldStampBalance
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
