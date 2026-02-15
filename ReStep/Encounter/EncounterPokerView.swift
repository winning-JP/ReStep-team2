import SwiftUI

struct EncounterPokerView: View {
    struct Card: Identifiable, Equatable {
        let id = UUID()
        let rank: Int
        let suit: Suit
    }

    enum Suit: String, CaseIterable {
        case spade = "♠︎"
        case heart = "♥︎"
        case diamond = "♦︎"
        case club = "♣︎"

        var color: Color {
            switch self {
            case .heart, .diamond: return .red
            case .spade, .club: return .primary
            }
        }
    }

    enum Phase {
        case ready
        case dealt
        case finished
    }

    @State private var deck: [Card] = []
    @State private var hand: [Card] = []
    @State private var held: [Bool] = Array(repeating: false, count: 5)
    @State private var phase: Phase = .ready
    @State private var resultText: String = "ディールしてね"
    private let wallet = WalletAPIClient.shared
    @StateObject private var coinTracker = CoinUsageTracker.shared
    @State private var credits: Int = 0
    @State private var bet: Int = 1
    @State private var lastResult: (name: String, multiplier: Int) = ("", 0)
    @State private var showWinGlow = false
    @State private var dealing = false
    @State private var faceUp: [Bool] = Array(repeating: false, count: 5)
    @State private var isLoadingBalance = false
    @State private var isSpending = false
    @State private var jackpot: Int = 0
    @State private var pendingWin: Int = 0
    @State private var isDoubleUpActive = false
    @State private var doubleUpDeck: [Card] = []
    @State private var doubleUpCard: Card?
    @State private var doubleUpWinnings: Int = 0
    @State private var doubleUpRound: Int = 0
    private let doubleUpMaxRounds = 10
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            tableBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header

                HStack(spacing: 10) {
                    ForEach(0..<hand.count, id: \.self) { index in
                        PokerCardView(card: hand[index], isHeld: held[index], isFaceUp: faceUp[index])
                            .overlay(alignment: .top) {
                                if held[index] {
                                    Text("HOLD")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.cyan.opacity(0.9))
                                        .clipShape(Capsule())
                                        .offset(y: -10)
                                }
                            }
                            .opacity(dealing ? 0.6 : 1.0)
                            .scaleEffect(dealing ? 0.98 : 1.0)
                            .animation(.easeOut(duration: 0.2), value: dealing)
                            .onTapGesture {
                                guard phase == .dealt else { return }
                                held[index].toggle()
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)

                if lastResult.multiplier > 0 {
                    Text("\(lastResult.name)  x\(lastResult.multiplier)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                        .shadow(color: .yellow.opacity(0.5), radius: 8)
                        .transition(.opacity.combined(with: .scale))
                }

                Text(resultText)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                if pendingWin > 0 && !isDoubleUpActive {
                    HStack(spacing: 12) {
                        Button("受け取る") { collectWinnings() }
                            .buttonStyle(.borderedProminent)
                        Button("ダブルアップ") { startDoubleUp() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                }

                if isDoubleUpActive {
                    doubleUpSection
                }

                HStack(spacing: 12) {
                    LedDisplay(title: "CREDITS", value: "\(credits)")
                    LedDisplay(title: "BET", value: "\(bet)")
                }
                .padding(.horizontal, 14)

                LedDisplay(title: "JACKPOT", value: "\(jackpot)")
                    .padding(.horizontal, 14)

                HStack(spacing: 10) {
                    Button("BET -") { bet = max(1, bet - 1) }
                        .buttonStyle(.bordered)
                        .disabled(phase == .dealt || dealing || isSpending || isLoadingBalance)
                    Button("BET +") { bet = min(5, bet + 1) }
                        .buttonStyle(.bordered)
                        .disabled(phase == .dealt || dealing || isSpending || isLoadingBalance)
                }

                Button {
                    handleMainAction()
                } label: {
                    Text(mainButtonTitle)
                        .font(.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .disabled(dealing || isSpending || isLoadingBalance)

                instructionsCard

                payTable

                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)

            if showWinGlow {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.yellow.opacity(0.18))
                    .padding(16)
                    .transition(.opacity)
            }
        }
//        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            Task { await bootstrapWallet() }
            loadJackpot()
            resetGame()
        }
    }

    private var mainButtonTitle: String {
        switch phase {
        case .ready: return "ディール"
        case .dealt: return "ドロー"
        case .finished: return "もう一度"
        }
    }

    private func handleMainAction() {
        switch phase {
        case .ready:
            startDeal()
        case .dealt:
            drawCards()
        case .finished:
            resetGame()
        }
    }

    private func resetGame() {
        deck = makeDeck().shuffled()
        hand = Array(deck.prefix(5))
        deck.removeFirst(min(5, deck.count))
        held = Array(repeating: false, count: 5)
        faceUp = Array(repeating: false, count: 5)
        resultText = "ディールしてね"
        lastResult = ("", 0)
        phase = .ready
        pendingWin = 0
        endDoubleUp(resetMessage: false)
    }

    private func startDeal() {
        guard !isSpending else { return }
        guard pendingWin == 0 else {
            resultText = "受け取るかダブルアップしてね"
            return
        }
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
        let requestId = "poker-" + UUID().uuidString

        Task {
            do {
                let response = try await wallet.useCoinsDaily(amount: bet, reason: "poker", clientRequestId: requestId)
                await MainActor.run {
                    credits = response.balance
                    coinTracker.recordUsage(bet)
                    incrementJackpot(by: bet)
                    isSpending = false
                    beginDeal()
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

    private func beginDeal() {
        dealing = true
        deck = makeDeck().shuffled()
        hand = Array(deck.prefix(5))
        deck.removeFirst(min(5, deck.count))
        held = Array(repeating: false, count: 5)
        faceUp = Array(repeating: false, count: 5)
        resultText = "ホールドしてドロー"
        lastResult = ("", 0)
        phase = .dealt
        for i in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i)) {
                withAnimation(.easeOut(duration: 0.2)) {
                    faceUp[i] = true
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            dealing = false
        }
    }

    private func drawCards() {
        dealing = true
        for i in 0..<hand.count {
            if held[i] == false, let next = deck.first {
                faceUp[i] = false
                hand[i] = next
                deck.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i)) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        faceUp[i] = true
                    }
                }
            }
        }
        let result = evaluate(hand)
        lastResult = result
        if result.multiplier > 0 {
            let win = bet * result.multiplier
            var totalWin = win
            if result.name == "ロイヤルストレートフラッシュ" {
                let jackpotPayout = payoutJackpot()
                totalWin += jackpotPayout
                if jackpotPayout > 0 {
                    resultText = "\(result.name) +\(win) JP+\(jackpotPayout)"
                } else {
                    resultText = "\(result.name) +\(win)"
                }
            } else {
                resultText = "\(result.name) +\(win)"
            }
            pendingWin = totalWin
            flashWin()
        } else {
            resultText = "ノーペア"
        }
        phase = .finished
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dealing = false
        }
    }

    private func makeDeck() -> [Card] {
        var cards: [Card] = []
        for suit in Suit.allCases {
            for rank in 2...14 {
                cards.append(Card(rank: rank, suit: suit))
            }
        }
        return cards
    }

    private func evaluate(_ cards: [Card]) -> (name: String, multiplier: Int) {
        let ranks = cards.map(\.rank).sorted()
        let suits = cards.map(\.suit)
        let isFlush = Set(suits).count == 1
        let isStraight = isSequential(ranks)
        let counts = Dictionary(grouping: ranks, by: { $0 }).mapValues { $0.count }
        let sortedCounts = counts.values.sorted(by: >)

        if isStraight && isFlush && ranks.max() == 14 { return ("ロイヤルストレートフラッシュ", 25) }
        if isStraight && isFlush { return ("ストレートフラッシュ", 20) }
        if sortedCounts == [4,1] { return ("フォーカード", 12) }
        if sortedCounts == [3,2] { return ("フルハウス", 8) }
        if isFlush { return ("フラッシュ", 6) }
        if isStraight { return ("ストレート", 5) }
        if sortedCounts == [3,1,1] { return ("スリーカード", 4) }
        if sortedCounts == [2,2,1] { return ("ツーペア", 3) }
        if sortedCounts == [2,1,1,1] { return ("ワンペア", 2) }
        return ("ノーペア", 0)
    }

    private func isSequential(_ ranks: [Int]) -> Bool {
        guard ranks.count == 5 else { return false }
        let unique = Array(Set(ranks)).sorted()
        if unique.count != 5 { return false }
        let minVal = unique.first ?? 0
        if unique == [2,3,4,5,14] { return true } // A-2-3-4-5
        return unique.enumerated().allSatisfy { index, value in value == minVal + index }
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

    private func loadJackpot() {
        var inventory = GameStore.shared.loadInventory()
        if inventory.pokerJackpot == 0 {
            inventory.pokerJackpot = 1000
            GameStore.shared.saveInventory(inventory)
        }
        jackpot = inventory.pokerJackpot
    }

    private func incrementJackpot(by amount: Int) {
        guard amount > 0 else { return }
        var inventory = GameStore.shared.loadInventory()
        inventory.pokerJackpot += amount
        jackpot = inventory.pokerJackpot
        GameStore.shared.saveInventory(inventory)
    }

    private func payoutJackpot() -> Int {
        var inventory = GameStore.shared.loadInventory()
        let payout = inventory.pokerJackpot
        inventory.pokerJackpot = 0
        jackpot = 0
        GameStore.shared.saveInventory(inventory)
        return payout
    }

    private func collectWinnings() {
        guard pendingWin > 0 else { return }
        let payout = pendingWin
        pendingWin = 0
        awardWin(payout)
        endDoubleUp(resetMessage: false)
    }

    private func startDoubleUp() {
        guard pendingWin > 0 else { return }
        isDoubleUpActive = true
        doubleUpWinnings = pendingWin
        doubleUpRound = 0
        setupDoubleUpDeckIfNeeded()
        doubleUpCard = drawDoubleUpCard()
        if let base = doubleUpCard {
            DebugLog.log("double_up.start -> base=\(rankLabel(base.rank))(\(base.rank))")
        } else {
            DebugLog.log("double_up.start -> base=nil")
        }
        logNextDoubleUpCard("start")
        resultText = "ダブルアップ: HIGH or LOW"
    }

    private func endDoubleUp(resetMessage: Bool) {
        isDoubleUpActive = false
        doubleUpWinnings = 0
        doubleUpRound = 0
        doubleUpCard = nil
        if resetMessage {
            resultText = "ディールしてね"
        }
    }

    private func setupDoubleUpDeckIfNeeded() {
        if doubleUpDeck.isEmpty {
            doubleUpDeck = makeDeck().shuffled()
        }
    }

    private func drawDoubleUpCard() -> Card? {
        setupDoubleUpDeckIfNeeded()
        guard !doubleUpDeck.isEmpty else { return nil }
        return doubleUpDeck.removeFirst()
    }

    private func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        case 14: return "A"
        default: return "\(rank)"
        }
    }

    private func logNextDoubleUpCard(_ context: String) {
        let next = doubleUpDeck.first
        if let next {
            DebugLog.log("double_up.next[\(context)] -> \(rankLabel(next.rank))(\(next.rank))")
        } else {
            DebugLog.log("double_up.next[\(context)] -> nil")
        }
    }

    private func handleDoubleUpGuess(isHigh: Bool) {
        guard isDoubleUpActive, let base = doubleUpCard else { return }
        guard doubleUpRound < doubleUpMaxRounds else { return }
        guard let next = drawDoubleUpCard() else { return }
        if next.rank == base.rank {
            doubleUpCard = next
            DebugLog.log("double_up.draw -> base=\(rankLabel(base.rank))(\(base.rank)) next=\(rankLabel(next.rank))(\(next.rank)) guess=\(isHigh ? "HIGH" : "LOW") result=DRAW")
            logNextDoubleUpCard("draw")
            resultText = "引き分け: 続行"
            return
        }
        let win = isHigh ? (next.rank > base.rank) : (next.rank < base.rank)
        doubleUpCard = next
        DebugLog.log("double_up.draw -> base=\(rankLabel(base.rank))(\(base.rank)) next=\(rankLabel(next.rank))(\(next.rank)) guess=\(isHigh ? "HIGH" : "LOW") result=\(win ? "WIN" : "LOSE")")
        if win {
            doubleUpRound += 1
            doubleUpWinnings *= 2
            resultText = "成功! x\(doubleUpWinnings)"
            if doubleUpRound >= doubleUpMaxRounds {
                resultText = "上限到達: 受け取ってください"
            }
            logNextDoubleUpCard("win")
        } else {
            if doubleUpWinnings > 0 {
                incrementJackpot(by: doubleUpWinnings)
            }
            pendingWin = 0
            doubleUpWinnings = 0
            resultText = "失敗..."
            endDoubleUp(resetMessage: false)
        }
    }

    private var header: some View {
        HStack {
            Text("POKER")
                .font(.title2.bold())
                .foregroundColor(.white)
            Spacer()
            Text("5-Card Draw")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
    }

    private var tableBackground: some View {
        let colors = colorScheme == .dark
        ? [Color(red: 0.03, green: 0.3, blue: 0.18), Color(red: 0.02, green: 0.18, blue: 0.1)]
        : [Color(red: 0.12, green: 0.55, blue: 0.35), Color(red: 0.06, green: 0.34, blue: 0.2)]

        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 260
            )
        )
    }

    private var payTable: some View {
        DisclosureGroup("ペイテーブル") {
            VStack(alignment: .leading, spacing: 6) {
                payRow("ロイヤルストレートフラッシュ", 25)
                payRow("ストレートフラッシュ", 20)
                payRow("フォーカード", 12)
                payRow("フルハウス", 8)
                payRow("フラッシュ", 6)
                payRow("ストレート", 5)
                payRow("スリーカード", 4)
                payRow("ツーペア", 3)
                payRow("ワンペア", 2)
                HStack {
                    Text("ロイヤル時ジャックポット")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("+\(jackpot)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.top, 6)
        }
        .font(.footnote.weight(.semibold))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .foregroundColor(.primary)
        .padding(.horizontal, 18)
    }

    private func payRow(_ name: String, _ multiplier: Int) -> some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            Text("x\(multiplier)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.yellow)
        }
    }

    private func awardWin(_ amount: Int) {
        guard amount > 0 else { return }
        let requestId = "poker_win_" + UUID().uuidString
        Task {
            do {
                let response = try await wallet.earnCoins(amount: amount, reason: "poker_win", clientRequestId: requestId)
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

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("遊び方")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.primary)
            Text("1. ディールで5枚配られる")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("2. 残すカードをタップしてHOLD")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("3. ドローで引き直し")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("4. 役ができたら配当")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 18)
    }

    private func flashWin() {
        showWinGlow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showWinGlow = false
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private var doubleUpSection: some View {
        VStack(spacing: 10) {
            if let card = doubleUpCard {
                PokerCardView(card: card, isHeld: false, isFaceUp: true)
            }
            Text("ROUND \(doubleUpRound)/\(doubleUpMaxRounds)  WIN \(doubleUpWinnings)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
            HStack(spacing: 12) {
                Button("LOW") { handleDoubleUpGuess(isHigh: false) }
                    .buttonStyle(.bordered)
                    .disabled(doubleUpRound >= doubleUpMaxRounds)
                Button("HIGH") { handleDoubleUpGuess(isHigh: true) }
                    .buttonStyle(.bordered)
                    .disabled(doubleUpRound >= doubleUpMaxRounds)
                Button("受け取る") { collectDoubleUpWinnings() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 18)
    }

    private func collectDoubleUpWinnings() {
        guard isDoubleUpActive, doubleUpWinnings > 0 else { return }
        let payout = doubleUpWinnings
        pendingWin = 0
        doubleUpWinnings = 0
        awardWin(payout)
        endDoubleUp(resetMessage: false)
    }
}

private struct PokerCardView: View {
    let card: EncounterPokerView.Card
    let isHeld: Bool
    let isFaceUp: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            cardBack
                .opacity(isFaceUp ? 0.0 : 1.0)
                .rotation3DEffect(.degrees(isFaceUp ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            cardFront
                .opacity(isFaceUp ? 1.0 : 0.0)
                .rotation3DEffect(.degrees(isFaceUp ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .animation(.easeOut(duration: 0.2), value: isFaceUp)
    }

    private func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        case 14: return "A"
        default: return "\(rank)"
        }
    }

    private var cardFront: some View {
        VStack(spacing: 6) {
            Text(rankLabel(card.rank))
                .font(.headline.bold())
            Text(card.suit.rawValue)
                .font(.title3)
        }
        .foregroundColor(card.suit.color)
        .frame(width: 64, height: 90)
        .background(cardFaceFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHeld ? Color.cyan : cardFaceStroke, lineWidth: isHeld ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private var cardFaceFill: Color {
        colorScheme == .dark
        ? Color(red: 0.12, green: 0.12, blue: 0.15)
        : Color.white
    }

    private var cardFaceStroke: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.25)
        : Color.black.opacity(0.2)
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.2, blue: 0.6), Color(red: 0.05, green: 0.1, blue: 0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .overlay(
                Text("RESTEP")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white.opacity(0.8))
            )
            .frame(width: 64, height: 90)
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

private struct LedDisplay: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? Color(red: 0.36, green: 0.98, blue: 0.62) : Color(red: 0.1, green: 0.5, blue: 0.3))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#if DEBUG
@available(iOS 17, *)
struct EncounterPokerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EncounterPokerView()
        }
    }
}
#endif
