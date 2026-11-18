import Foundation

/// Item value of inventories (the Live Client API only exposes current gold for the local player).
public struct GoldCalculator: Sendable {
    let prices: [Int: Int]

    public init(items: [Int: Item]) {
        prices = items.mapValues(\.priceTotal)
    }

    public func inventoryValue(_ player: LivePlayer) -> Int {
        player.items.reduce(0) { sum, item in
            sum + (prices[item.itemID] ?? item.price ?? 0) * max(1, item.count ?? 1)
        }
    }

    public func teamValue(_ players: [LivePlayer]) -> Int {
        players.reduce(0) { $0 + inventoryValue($1) }
    }

    /// Direct lane opponent: same position, otherwise the enemy with the same index.
    public func laneOpponent(of player: LivePlayer, in enemies: [LivePlayer]) -> LivePlayer? {
        if let role = player.role, let match = enemies.first(where: { $0.role == role }) { return match }
        return nil
    }
}

/// What the enemy team brings, derived from champions + items. Drives situational item highlighting.
public struct ThreatProfile: Sendable, Hashable {
    public var healingSources: [String] = []
    public var shieldSources: [String] = []
    public var tanks: Int = 0
    public var magicShare: Double = 0.5
    public var hardCC: Int = 0
    public var fedCritCarries: [String] = []
    public var fedMages: [String] = []
    public var fedAssassins: [String] = []

    public var heavyHealing: Bool { healingSources.count >= 2 }
    public var heavyShields: Bool { shieldSources.count >= 2 }
    public var heavyAP: Bool { magicShare >= 0.6 }
    public var heavyAD: Bool { magicShare <= 0.35 }

    public init() {}
}

/// Champion/item knowledge tables used for threat detection.
public enum ChampionKnowledge {
    public static let healers: Set<String> = [
        "Soraka", "Aatrox", "Vladimir", "Sylas", "DrMundo", "Warwick", "Yuumi", "Nami", "Swain", "Fiddlesticks",
        "Briar", "Illaoi", "Olaf", "Sona", "Seraphine", "Renata", "Maokai", "Kayn", "Darius", "Volibear",
        "Zac", "Trundle", "Nasus", "Udyr", "Senna", "Milio", "Gwen", "Samira", "Belveth", "Viego", "Aurora",
    ]

    public static let shielders: Set<String> = [
        "Lulu", "Janna", "Karma", "Sett", "Shen", "Seraphine", "Orianna", "Ivern", "Lux", "Rakan", "Taric",
        "Braum", "Sona", "Milio", "Renata", "Yasuo", "Yone", "Riven", "Camille", "Mordekaiser", "Rell", "Skarner",
    ]

    /// Abilities that reliably stun/root/knock up/charm/suppress.
    public static let hardCC: Set<String> = [
        "Leona", "Nautilus", "Thresh", "Blitzcrank", "Morgana", "Lux", "Amumu", "Sejuani", "Malphite", "Ornn",
        "Rell", "Alistar", "Rakan", "Annie", "Ashe", "Lissandra", "Veigar", "Zyra", "Maokai", "Jarvan IV",
        "JarvanIV", "Vi", "Warwick", "Skarner", "Zac", "Rammus", "Cassiopeia", "Ahri", "Seraphine", "Sona",
        "Galio", "Twisted Fate", "TwistedFate", "Neeko", "Taric", "Braum", "Poppy", "Pantheon", "Sett",
        "Renekton", "Wukong", "MonkeyKing", "Kennen", "Shen", "Ryze", "Syndra", "Xerath", "Varus", "Jhin",
        "Lillia", "Fiddlesticks", "Hecarim", "Nocturne", "Leblanc", "Swain", "Diana", "Chogath", "Gragas",
    ]

    public static let critItems: Set<Int> = [3031, 6675, 6676, 6672, 3032, 3094, 3046, 3036, 3072, 3095, 2015, 3508, 6671]
    public static let healingItems: Set<Int> = [3153, 3074, 3065, 6610, 4633, 3072, 6673, 3161, 6692]
    public static let shieldItems: Set<Int> = [6673, 3053, 6692, 3161, 4005, 3190, 2065]
}

public enum InventoryAnalyzer {
    /// - Parameters:
    ///   - damageType: championAlias → `kMagic | kPhysical | kMixed` (CommunityDragon tacticalInfo).
    ///   - tankAliases: champions whose class tags contain `tank`.
    public static func threatProfile(enemies: [LivePlayer], damageType: [String: String], tankAliases: Set<String>,
                                     items: [Int: Item]) -> ThreatProfile {
        var profile = ThreatProfile()
        var magicWeight = 0.0
        var totalWeight = 0.0
        for enemy in enemies {
            let alias = enemy.championAlias
            if ChampionKnowledge.healers.contains(alias) { profile.healingSources.append(enemy.championName) }
            if let heal = enemy.itemIds.first(where: ChampionKnowledge.healingItems.contains) {
                profile.healingSources.append("\(enemy.championName) (\(items[heal]?.name ?? "Item"))")
            }
            if ChampionKnowledge.shielders.contains(alias) { profile.shieldSources.append(enemy.championName) }
            if enemy.itemIds.contains(where: ChampionKnowledge.shieldItems.contains) {
                profile.shieldSources.append("\(enemy.championName) (Item)")
            }
            if tankAliases.contains(alias) { profile.tanks += 1 }
            if ChampionKnowledge.hardCC.contains(alias) || ChampionKnowledge.hardCC.contains(enemy.championName) {
                profile.hardCC += 1
            }

            let weight = 1.0 + Double(enemy.scores.kills) * 0.15
            totalWeight += weight
            switch damageType[alias] {
            case "kMagic": magicWeight += weight
            case "kMixed": magicWeight += weight * 0.5
            default: break
            }

            let fed = enemy.scores.kills >= 5 && Double(enemy.scores.kills + enemy.scores.assists) / Double(max(1, enemy.scores.deaths)) >= 3
            if fed {
                let crit = enemy.itemIds.filter(ChampionKnowledge.critItems.contains).count
                if crit >= 1 { profile.fedCritCarries.append(enemy.championName) }
                else if damageType[alias] == "kMagic" { profile.fedMages.append(enemy.championName) }
                else { profile.fedAssassins.append(enemy.championName) }
            }
        }
        profile.magicShare = totalWeight > 0 ? magicWeight / totalWeight : 0.5
        return profile
    }
}

/// Detects freshly completed legendary items per enemy (pulse badge "Item-Spike").
public struct ItemSpikeDetector: Sendable {
    public struct Spike: Sendable, Hashable, Identifiable {
        public let playerId: String
        public let itemId: Int
        public let gameTime: Double
        public var id: String { "\(playerId)-\(itemId)" }

        public init(playerId: String, itemId: Int, gameTime: Double) {
            self.playerId = playerId
            self.itemId = itemId
            self.gameTime = gameTime
        }
    }

    private var known: [String: Set<Int>] = [:]
    public private(set) var spikes: [Spike] = []
    let legendary: Set<Int>

    public init(items: [Int: Item]) {
        legendary = Set(items.values.filter(\.isLegendary).map(\.id))
    }

    /// Returns spikes that are new in this snapshot. The first sighting of a player only seeds the state.
    public mutating func update(players: [LivePlayer], gameTime: Double) -> [Spike] {
        var fresh: [Spike] = []
        for player in players {
            let current = Set(player.itemIds.filter(legendary.contains))
            if let previous = known[player.id] {
                for item in current.subtracting(previous) {
                    fresh.append(Spike(playerId: player.id, itemId: item, gameTime: gameTime))
                }
            }
            known[player.id] = current
        }
        spikes.append(contentsOf: fresh)
        spikes.removeAll { gameTime - $0.gameTime > 25 }
        return fresh
    }

    public func activeSpike(for playerId: String) -> Spike? { spikes.last { $0.playerId == playerId } }
}
