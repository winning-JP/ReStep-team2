import Foundation
import Combine

@MainActor
final class DungeonViewModel: ObservableObject {
    @Published private(set) var log: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var resultText: String = ""
    @Published private(set) var lastActionText: String = "探索の気配が漂う"
    @Published private(set) var allyHp: Int = 0
    @Published private(set) var allyMaxHp: Int = 1
    @Published private(set) var enemyHp: Int = 0
    @Published private(set) var enemyMaxHp: Int = 1
    @Published private(set) var shouldExit: Bool = false
    @Published private(set) var isInBattle: Bool = false
    @Published private(set) var remainingAttacks: Int = 0
    @Published private(set) var currentAttackerName: String = "旅人"

    private let store = GameStore.shared
    private let turnDelay: UInt64 = 250_000_000
    private let battleStateKey = "restep.dungeon.battleState"
    private var currentAllies: [CombatUnit] = []
    private var currentEnemies: [CombatUnit] = []
    private var attackerNames: [String] = []
    private var currentAttackerIndex: Int = 0
    private var usedAttacks: Int = 0
    private var encounterLimit: Int = 0
    private var defendOn: Bool = false

    func startRun() {
        guard !isRunning else { return }
        isRunning = true
        log.removeAll()
        resultText = ""
        shouldExit = false
        allyHp = 0
        allyMaxHp = 1
        enemyHp = 0
        enemyMaxHp = 1
        startTurnBattle()
    }

    private func startTurnBattle() {
        let party = store.loadParty()
        let travelers = store.loadTravelers().filter { party.memberIds.contains($0.id) }
        guard !travelers.isEmpty else {
            log.append("パーティが空です")
            isRunning = false
            return
        }

        let encounterCount = store.loadEncounters().count
        let buffLevel = min(encounterCount / 5, 10)
        if buffLevel > 0 {
            log.append("すれ違いの力が高まっている（Lv.\(buffLevel)）")
        }

        encounterLimit = encounterCount
        usedAttacks = 0
        remainingAttacks = max(0, encounterLimit - usedAttacks)
        log.append("迷宮へ足を踏み入れた")

        if let saved = loadBattleState() {
            usedAttacks = saved.usedAttacks
            encounterLimit = encounterCount
            remainingAttacks = max(0, encounterLimit - usedAttacks)
            log.append("前回の続きから再開")
            attackerNames = saved.attackerNames
            currentAttackerIndex = min(saved.currentAttackerIndex, max(0, attackerNames.count - 1))
            currentAllies = saved.allies.map { CombatUnit(snapshot: $0) }
            currentEnemies = saved.enemies.map { CombatUnit(snapshot: $0) }
            updateDisplayedUnits(allies: currentAllies, enemies: currentEnemies)
            updateAttackerName()
            isInBattle = true
            return
        }

        let encounterTravelers = store.loadEncounters().map { $0.traveler }
        let sourceTravelers = encounterTravelers.isEmpty ? travelers : encounterTravelers

        attackerNames = sourceTravelers.map { $0.name }
        currentAttackerIndex = 0
        currentAllies = sourceTravelers.map {
            let bonusHp = buffLevel * 2
            let bonusAtk = buffLevel
            let bonusDef = max(0, buffLevel / 2)
            return CombatUnit(
                hp: $0.stats.hp + bonusHp,
                atk: $0.stats.atk + bonusAtk,
                def: $0.stats.def + bonusDef,
                agi: $0.stats.agi
            )
        }
        currentEnemies = [CombatUnit(hp: 20, atk: 6, def: 3, agi: 4)]
        log.append("敵が現れた")
        updateDisplayedUnits(allies: currentAllies, enemies: currentEnemies)
        updateAttackerName()
        isInBattle = true
    }

    enum PlayerAction {
        case attack
        case skill
        case defend
    }

    func performAction(_ action: PlayerAction) {
        guard isInBattle else { return }

        if encounterLimit == 0 {
            resultText = "攻撃回数がありません。もっとたくさんの人とすれ違おう！"
            shouldExit = true
            saveBattleState(floor: 1, isBoss: false, allies: currentAllies, enemies: currentEnemies, usedAttacks: usedAttacks)
            return
        }

        if action != .defend && usedAttacks >= encounterLimit {
            resultText = "攻撃回数が0になりました。もっとたくさんの人とすれ違おう！"
            shouldExit = true
            saveBattleState(floor: 1, isBoss: false, allies: currentAllies, enemies: currentEnemies, usedAttacks: usedAttacks)
            return
        }

        switch action {
        case .attack:
            playerAttack(multiplier: 1.0, label: "攻撃！")
        case .skill:
            playerAttack(multiplier: 1.5, label: "スキル！")
        case .defend:
            defendOn = true
            log.append("防御の構え")
            lastActionText = "旅人は身を固めた"
        }

        if currentEnemies.allSatisfy({ $0.hp <= 0 }) {
            resultText = "勝利！"
            isInBattle = false
            isRunning = false
            clearBattleState()
            return
        }

        enemyTurn()
        advanceAttacker()
    }

    private func updateDisplayedUnits(allies: [CombatUnit], enemies: [CombatUnit]) {
        if let ally = allies.first(where: { $0.hp > 0 }) ?? allies.first {
            allyHp = max(0, ally.hp)
            allyMaxHp = max(1, ally.maxHp)
        }

        if let enemy = enemies.first(where: { $0.hp > 0 }) ?? enemies.first {
            enemyHp = max(0, enemy.hp)
            enemyMaxHp = max(1, enemy.maxHp)
        } else {
            enemyHp = 0
        }
    }

    private func playerAttack(multiplier: Double, label: String) {
        guard let attackerIndex = nextAliveAttackerIndex(from: currentAttackerIndex) else { return }
        currentAttackerIndex = attackerIndex
        guard let targetIndex = currentEnemies.indices.first(where: { currentEnemies[$0].hp > 0 }) else { return }
        let attacker = currentAllies[attackerIndex]
        let base = max(1, attacker.atk - currentEnemies[targetIndex].def / 2)
        let damage = max(1, Int(Double(base) * multiplier))
        currentEnemies[targetIndex].hp -= damage
        usedAttacks += 1
        remainingAttacks = max(0, encounterLimit - usedAttacks)
        let name = attackerNames.indices.contains(attackerIndex) ? attackerNames[attackerIndex] : "旅人"
        log.append("\(name)の\(label) \(damage) ダメージ")
        lastActionText = "\(name)の\(label)"
        updateDisplayedUnits(allies: currentAllies, enemies: currentEnemies)
    }

    private func enemyTurn() {
        guard let enemy = currentEnemies.first(where: { $0.hp > 0 }) else { return }
        guard let targetIndex = nextAliveAttackerIndex(from: currentAttackerIndex) else { return }
        var damage = max(1, enemy.atk - currentAllies[targetIndex].def / 2)
        if defendOn {
            damage = max(1, damage / 2)
        }
        currentAllies[targetIndex].hp -= damage
        defendOn = false
        let name = attackerNames.indices.contains(targetIndex) ? attackerNames[targetIndex] : "旅人"
        log.append("敵の攻撃 \(damage) ダメージ（\(name)）")
        lastActionText = "敵が攻撃した"
        updateDisplayedUnits(allies: currentAllies, enemies: currentEnemies)

        if currentAllies.allSatisfy({ $0.hp <= 0 }) {
            resultText = "敗北..."
            isInBattle = false
            isRunning = false
            clearBattleState()
        }
    }

    private func saveBattleState(floor: Int, isBoss: Bool, allies: [CombatUnit], enemies: [CombatUnit], usedAttacks: Int) {
        let state = PersistedBattleState(
            floor: floor,
            isBoss: isBoss,
            allies: allies.map { $0.snapshot },
            enemies: enemies.map { $0.snapshot },
            usedAttacks: usedAttacks,
            attackerNames: attackerNames,
            currentAttackerIndex: currentAttackerIndex
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: battleStateKey)
        }
    }

    private func loadBattleState() -> PersistedBattleState? {
        guard let data = UserDefaults.standard.data(forKey: battleStateKey) else { return nil }
        return try? JSONDecoder().decode(PersistedBattleState.self, from: data)
    }

    private func clearBattleState() {
        UserDefaults.standard.removeObject(forKey: battleStateKey)
    }

    private func nextAliveAttackerIndex(from start: Int) -> Int? {
        guard !currentAllies.isEmpty else { return nil }
        for offset in 0..<currentAllies.count {
            let idx = (start + offset) % currentAllies.count
            if currentAllies[idx].hp > 0 {
                return idx
            }
        }
        return nil
    }

    private func advanceAttacker() {
        guard let nextIndex = nextAliveAttackerIndex(from: currentAttackerIndex + 1) else { return }
        currentAttackerIndex = nextIndex
        updateAttackerName()
    }

    private func updateAttackerName() {
        if attackerNames.indices.contains(currentAttackerIndex) {
            currentAttackerName = attackerNames[currentAttackerIndex]
        } else {
            currentAttackerName = "旅人"
        }
    }
}

private final class CombatUnit {
    var hp: Int
    let maxHp: Int
    let atk: Int
    let def: Int
    let agi: Int

    init(hp: Int, atk: Int, def: Int, agi: Int) {
        self.hp = hp
        self.maxHp = hp
        self.atk = atk
        self.def = def
        self.agi = agi
    }

    var snapshot: BattleUnitSnapshot {
        BattleUnitSnapshot(hp: hp, maxHp: maxHp, atk: atk, def: def, agi: agi)
    }

    convenience init(snapshot: BattleUnitSnapshot) {
        self.init(hp: snapshot.hp, atk: snapshot.atk, def: snapshot.def, agi: snapshot.agi)
    }
}

private struct BattleUnitSnapshot: Codable {
    let hp: Int
    let maxHp: Int
    let atk: Int
    let def: Int
    let agi: Int
}

private struct PersistedBattleState: Codable {
    let floor: Int
    let isBoss: Bool
    let allies: [BattleUnitSnapshot]
    let enemies: [BattleUnitSnapshot]
    let usedAttacks: Int
    let attackerNames: [String]
    let currentAttackerIndex: Int
}
