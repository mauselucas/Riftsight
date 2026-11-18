import Foundation

/// Cooldown math for the (manually started) enemy summoner-spell and ultimate timers.
public enum CooldownCalculator {
    /// LoL formula: cooldown × 100 / (100 + haste).
    public static func apply(haste: Double, to base: Double) -> Double {
        base * 100 / (100 + max(0, haste))
    }

    static let summonerHasteItems: [Int: Double] = [3158: 10]
    static let ultimateHasteItems: [Int: Double] = [3118: 20]

    public static func summonerCooldown(base: Double, items: [Int], itemDB: [Int: Item], cosmicInsight: Bool = false) -> Double {
        var haste = cosmicInsight ? 18.0 : 0
        for id in items {
            if let parsed = itemDB[id]?.summonerSpellHaste, parsed > 0 { haste += Double(parsed) }
            else { haste += summonerHasteItems[id] ?? 0 }
        }
        return apply(haste: haste, to: base)
    }

    /// Standard ultimate ranks: 6 / 11 / 16.
    public static func ultimateRank(level: Int) -> Int {
        level >= 16 ? 3 : level >= 11 ? 2 : level >= 6 ? 1 : 0
    }

    public static func abilityHaste(items: [Int], itemDB: [Int: Item]) -> Double {
        Double(items.reduce(0) { $0 + (itemDB[$1]?.abilityHaste ?? 0) })
    }

    /// Estimated ultimate cooldown (≈) from level and item haste. `nil` before level 6.
    public static func ultimateCooldown(detail: ChampionDetail, level: Int, items: [Int], itemDB: [Int: Item]) -> Double? {
        let rank = ultimateRank(level: level)
        guard rank > 0, let base = detail.spell("R")?.cooldown(rank: rank) else { return nil }
        let haste = abilityHaste(items: items, itemDB: itemDB) + items.reduce(0) { $0 + (ultimateHasteItems[$1] ?? 0) }
        return apply(haste: haste, to: base)
    }
}

/// A running countdown started by a click on an enemy spell/ult icon.
public struct CooldownTimer: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case spell1, spell2, ultimate }
    public let playerId: String
    public let kind: Kind
    public let startedAt: Double
    public let duration: Double

    public init(playerId: String, kind: Kind, startedAt: Double, duration: Double) {
        self.playerId = playerId
        self.kind = kind
        self.startedAt = startedAt
        self.duration = duration
    }

    public var id: String { "\(playerId)-\(kind.rawValue)" }
    public func remaining(at gameTime: Double) -> Double { max(0, startedAt + duration - gameTime) }
}
