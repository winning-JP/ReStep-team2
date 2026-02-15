import SwiftUI
import UIKit

struct EncounterSlotView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let symbols = ["🍒", "⭐️", "🔔", "🍋", "💎", "7️⃣", "🍀"]
    private let symbolWeights = [20, 16, 14, 18, 8, 4, 10]
    private let wallet = WalletAPIClient.shared
    @StateObject private var coinTracker = CoinUsageTracker.shared
    @State private var reels: [Int] = [0, 1, 2]
    @State private var reelSpinning: [Bool] = [false, false, false]
    @State private var resultText: String = "レバーを引いてね"
    @State private var isSpinning = false
    @State private var spinTask: Task<Void, Never>?
    @State private var reelTasks: [Task<Void, Never>?] = [nil, nil, nil]
    @State private var reelDelayMs: [Int] = [50, 50, 50]
    @State private var reelStopRequested: [Bool] = [false, false, false]
    @State private var reelStopTicks: [Int] = [0, 0, 0]
    @State private var credits: Int = 0
    @State private var bet: Int = 1
    @State private var winMultiplier: Int = 0
    @State private var showWinFlash = false
    @State private var lightsOn = false
    @State private var isLoadingBalance = false
    @State private var isSpending = false

    var body: some View {
        ZStack {
            slotBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                marquee

                Text("SLOT")
                    .font(.system(size: 30, weight: .heavy, design: .serif))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)

                HStack(spacing: 12) {
                    slotPanel

                    LeverView(isSpinning: isSpinning)
                        .onTapGesture {
                            spin()
                        }
                }
                .padding(.horizontal, 10)

                HStack(spacing: 10) {
                    ForEach(reels.indices, id: \.self) { index in
                        Button {
                            requestStopReel(index: index)
                        } label: {
                            Text("STOP")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(controlBackground)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(controlStroke, lineWidth: 1)
                                )
                        }
                        .disabled(!isSpinning || reelSpinning[index] == false)
                    }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    LedDisplay(title: "CREDITS", value: "\(credits)")
                    LedDisplay(title: "BET", value: "\(bet)")
                }
                .padding(.horizontal, 18)

                HStack(spacing: 10) {
                    Button {
                        bet = max(1, bet - 1)
                    } label: {
                        Text("BET -")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(controlBackground)
                            .clipShape(Capsule())
                    }
                    .disabled(isSpinning || isSpending || isLoadingBalance)

                    Button {
                        bet = min(5, bet + 1)
                    } label: {
                        Text("BET +")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(controlBackground)
                            .clipShape(Capsule())
                    }
                    .disabled(isSpinning || isSpending || isLoadingBalance)

                    Button {
                        spin()
                    } label: {
                        Text(isSpinning ? "スピン中..." : "スピン")
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color.red, Color(red: 0.6, green: 0.0, blue: 0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                .stroke(controlStroke, lineWidth: 1)
                            )
                    }
                    .disabled(isSpinning || isSpending || isLoadingBalance)
                }
                .padding(.horizontal, 18)

                Text(resultText)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                payTable

                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)

            if showWinFlash {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.yellow.opacity(0.25))
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .navigationTitle("スロット")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            Task { await bootstrapWallet() }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                lightsOn.toggle()
            }
        }
    }

    private var slotBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.02, blue: 0.12),
                Color(red: 0.2, green: 0.05, blue: 0.15),
                Color(red: 0.05, green: 0.01, blue: 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.15), Color.clear],
                center: .top,
                startRadius: 10,
                endRadius: 260
            )
        )
    }

    private var marquee: some View {
        HStack(spacing: 8) {
            ForEach(0..<14, id: \.self) { index in
                Circle()
                    .fill(index % 2 == 0 ? (lightsOn ? Color.yellow : Color.orange) : (lightsOn ? Color.orange : Color.yellow))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.yellow.opacity(0.8), radius: 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(marqueeBackground)
        .clipShape(Capsule())
    }

    private var slotPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.08, blue: 0.2), Color(red: 0.1, green: 0.04, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 6)

            HStack(spacing: 12) {
                ForEach(reels.indices, id: \.self) { index in
                    SlotReelView(
                        symbols: symbols,
                        centerIndex: reels[index],
                        isSpinning: reelSpinning[index],
                        blurAmount: blurAmount(for: index)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.6), lineWidth: 2)
        )
    }

    private var payTable: some View {
        DisclosureGroup("ペイテーブル") {
            VStack(alignment: .leading, spacing: 6) {
                PayRow(symbol: "7️⃣", multiplier: 10)
                PayRow(symbol: "💎", multiplier: 7)
                PayRow(symbol: "🔔", multiplier: 5)
                PayRow(symbol: "🍀", multiplier: 4)
                PayRow(symbol: "⭐️", multiplier: 3)
                PayRow(symbol: "🍒", multiplier: 2)
                PayRow(symbol: "🍋", multiplier: 1)
                Text("2つ揃い: x1")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }
        .font(.footnote.weight(.semibold))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .foregroundColor(.primary)
        .padding(.horizontal, 18)
    }

    private var controlBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.12)
        : Color.black.opacity(0.6)
    }

    private var controlStroke: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.25)
        : Color.white.opacity(0.3)
    }

    private var marqueeBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.08)
        : Color.black.opacity(0.35)
    }

    private func spin() {
        guard !isSpinning, !isSpending else { return }
        guard !isLoadingBalance else {
            resultText = "コイン取得中..."
            return
        }
        guard credits >= bet else {
            resultText = "コインが足りません"
            return
        }
        guard coinTracker.canUse(bet) else {
            resultText = "本日のコイン使用上限(\(coinTracker.dailyLimit))に達しました"
            return
        }

        isSpending = true
        resultText = "コイン消費中..."
        let requestId = "slot-" + UUID().uuidString

        Task {
            do {
                let response = try await wallet.useCoinsDaily(amount: bet, reason: "slot", clientRequestId: requestId)
                await MainActor.run {
                    credits = response.balance
                    coinTracker.recordUsage(bet)
                    isSpending = false
                    startSpin()
                }
            } catch let apiErr as APIError {
                await MainActor.run {
                    isSpending = false
                    resultText = apiErr.userMessage()
                }
            } catch {
                await MainActor.run {
                    isSpending = false
                    resultText = error.localizedDescription
                }
            }
        }
    }

    private func startSpin() {
        isSpinning = true
        resultText = "回転中..."
        winMultiplier = 0
        spinTask?.cancel()
        for i in reelTasks.indices {
            reelTasks[i]?.cancel()
            reelTasks[i] = nil
            reelDelayMs[i] = 45
            reelStopRequested[i] = false
            reelStopTicks[i] = 0
        }

        spinTask = Task { @MainActor in
            reelSpinning = [true, true, true]
        }

        for i in reels.indices {
            startReel(index: i)
        }

        // Manual stop only. No auto-stop.
    }

    private func startReel(index: Int) {
        reelTasks[index]?.cancel()
        reelTasks[index] = Task { @MainActor in
            while !Task.isCancelled {
                reels[index] = weightedIndex()
                let delay = max(25, min(reelDelayMs[index], 220))
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

                if reelStopRequested[index] {
                    reelDelayMs[index] = min(reelDelayMs[index] + 12, 200)
                    if reelDelayMs[index] >= 160 {
                        reelStopTicks[index] += 1
                    }
                    if reelStopTicks[index] >= 6 {
                        finalizeStop(index: index)
                        return
                    }
                }
            }
        }
    }

    private func requestStopReel(index: Int) {
        guard reelSpinning[index] else { return }
        reelStopRequested[index] = true
        reelStopTicks[index] = 0
        reelDelayMs[index] = max(reelDelayMs[index], 80)
    }

    private func finalizeStop(index: Int) {
        reels[index] = weightedIndex()
        reelSpinning[index] = false
        reelStopRequested[index] = false
        reelStopTicks[index] = 0
        reelTasks[index]?.cancel()
        reelTasks[index] = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        finalizeIfAllStopped()
    }

    private func finalizeIfAllStopped() {
        if reelSpinning.contains(true) { return }
        let unique = Set(reels)
        if unique.count == 1 {
            winMultiplier = threeOfKindMultiplier(for: reels[0])
            resultText = "大当たり！ x\(winMultiplier)"
            let win = bet * winMultiplier
            awardWin(win)
            flashWin()
        } else if unique.count == 2 {
            winMultiplier = 1
            let win = bet * winMultiplier
            resultText = "当たり！ +\(win)"
            awardWin(win)
            flashWin()
        } else {
            resultText = "はずれ"
        }
        isSpinning = false
    }

    private func weightedIndex() -> Int {
        let total = symbolWeights.reduce(0, +)
        let r = Int.random(in: 0..<max(1, total))
        var acc = 0
        for (i, w) in symbolWeights.enumerated() {
            acc += w
            if r < acc { return i }
        }
        return 0
    }

    private func threeOfKindMultiplier(for index: Int) -> Int {
        switch symbols[index] {
        case "7️⃣": return 10
        case "💎": return 7
        case "🔔": return 5
        case "🍀": return 4
        case "⭐️": return 3
        case "🍒": return 2
        default: return 1
        }
    }

    private func flashWin() {
        showWinFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showWinFlash = false
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func blurAmount(for index: Int) -> Double {
        let delay = reelDelayMs[index]
        if !reelSpinning[index] { return 0 }
        if delay <= 40 { return 3.5 }
        if delay <= 70 { return 2.5 }
        if delay <= 110 { return 1.6 }
        return 0.8
    }

    private func awardWin(_ amount: Int) {
        guard amount > 0 else { return }
        let requestId = "slot_win_" + UUID().uuidString
        Task {
            do {
                let response = try await wallet.earnCoins(amount: amount, reason: "slot_win", clientRequestId: requestId)
                await MainActor.run {
                    credits = response.balance
                }
            } catch let apiErr as APIError {
                await MainActor.run {
                    resultText = apiErr.userMessage()
                }
            } catch {
                await MainActor.run {
                    resultText = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func bootstrapWallet() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        do {
            let localCoins = GameStore.shared.loadInventory().coins
            let response = try await wallet.registerWallet(initialBalance: localCoins)
            credits = response.balance
            if response.registered, localCoins > 0 {
                var inventory = GameStore.shared.loadInventory()
                inventory.coins = 0
                GameStore.shared.saveInventory(inventory)
            }
        } catch let apiErr as APIError {
            resultText = apiErr.userMessage()
        } catch {
            resultText = error.localizedDescription
        }
    }
}

private struct SlotReelView: View {
    let symbols: [String]
    let centerIndex: Int
    let isSpinning: Bool
    let blurAmount: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [reelBaseFill, reelEdgeFill],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(reelStroke, lineWidth: 1)
                )
                .overlay(
                    LinearGradient(
                        colors: [reelHighlight, Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                )

            VStack(spacing: 4) {
                Text(symbols[prevIndex])
                    .font(.system(size: 30, weight: .bold))
                    .opacity(0.45)
                Text(symbols[safeIndex])
                    .font(.system(size: 54, weight: .bold))
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .opacity(isSpinning ? 0.85 : 1.0)
                Text(symbols[nextIndex])
                    .font(.system(size: 30, weight: .bold))
                    .opacity(0.45)
            }
            .blur(radius: isSpinning ? blurAmount : 0.0)
            .scaleEffect(isSpinning ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isSpinning)
        }
        .frame(width: 80, height: 96)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.clear, Color.white.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 8)
    }

    private var safeIndex: Int {
        if symbols.isEmpty { return 0 }
        return min(max(0, centerIndex), symbols.count - 1)
    }

    private var prevIndex: Int {
        if symbols.isEmpty { return 0 }
        return (safeIndex - 1 + symbols.count) % symbols.count
    }

    private var nextIndex: Int {
        if symbols.isEmpty { return 0 }
        return (safeIndex + 1) % symbols.count
    }

    private var reelBaseFill: Color {
        colorScheme == .dark
        ? Color(red: 0.12, green: 0.12, blue: 0.16)
        : Color.white
    }

    private var reelEdgeFill: Color {
        colorScheme == .dark
        ? Color(red: 0.16, green: 0.16, blue: 0.2)
        : Color(red: 0.9, green: 0.9, blue: 0.95)
    }

    private var reelStroke: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.15)
        : Color.black.opacity(0.2)
    }

    private var reelHighlight: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.12)
        : Color.white.opacity(0.6)
    }
}

private struct LedDisplay: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.36, green: 0.98, blue: 0.62))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PayRow: View {
    let symbol: String
    let multiplier: Int

    var body: some View {
        HStack {
            Text(symbol)
            Text("x\(multiplier)")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundColor(.primary)
    }
}

private struct LeverView: View {
    let isSpinning: Bool
    @State private var pull = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.8))
                .frame(width: 10, height: 80)
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(pull || isSpinning ? 25 : 0), anchor: .top)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isSpinning)
        }
        .padding(10)
        .background(leverBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            pull = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pull = false
            }
        }
    }

    private var leverBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.12)
        : Color.black.opacity(0.5)
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterSlotView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterSlotView()
        }
    }
}
#endif
