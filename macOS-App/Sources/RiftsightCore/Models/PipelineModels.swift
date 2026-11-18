import Foundation

// Codable mirror of the pipeline JSON contract in docs/gemini-recherche-datenpipeline.md (§2).

public struct DataMeta: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let patch: String
    public let generatedAt: String?
    public let sample: Bool
    public let platforms: [String]?
    public let rankFloor: String?
    public let matchesAnalyzed: Int?

    public init(schemaVersion: Int = 1, patch: String, generatedAt: String? = nil, sample: Bool,
                platforms: [String]? = nil, rankFloor: String? = nil, matchesAnalyzed: Int? = nil) {
        self.schemaVersion = schemaVersion
        self.patch = patch
        self.generatedAt = generatedAt
        self.sample = sample
        self.platforms = platforms
        self.rankFloor = rankFloor
        self.matchesAnalyzed = matchesAnalyzed
    }
}

// MARK: counterpicks.json

public struct CounterpicksFile: Codable, Sendable {
    public let meta: DataMeta
    public let champions: [String: [String: ChampionCounterBlock]]

    public func block(championId: Int, role: Role) -> ChampionCounterBlock? {
        champions[String(championId)]?[role.rawValue]
    }
}

public struct ChampionCounterBlock: Codable, Sendable, Hashable {
    public let games: Int
    public let winrate: Double
    public let counters: [CounterEntry]
}

public struct CounterEntry: Codable, Sendable, Hashable, Identifiable {
    public let championId: Int
    public let games: Int
    public let winrate: Double
    public let delta: Double
    public let goldDiff15: Double?
    public let csDiff15: Double?
    public let laneKillRate: Double?
    public var id: Int { championId }
}

// MARK: matchup_runes.json

public struct MatchupRunesFile: Codable, Sendable {
    public let meta: DataMeta
    public let builds: [String: [String: RoleBuilds]]

    public func builds(championId: Int, role: Role) -> RoleBuilds? {
        builds[String(championId)]?[role.rawValue]
    }

    /// Roles for which a build exists, most data first.
    public func roles(championId: Int) -> [Role] {
        guard let roles = builds[String(championId)] else { return [] }
        return roles.compactMap { key, value in Role(rawValue: key).map { ($0, value.defaultBuild.games) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}

public struct RoleBuilds: Codable, Sendable, Hashable {
    public let defaultBuild: BuildBlock
    public let vs: [String: BuildBlock]?

    enum CodingKeys: String, CodingKey {
        case defaultBuild = "default"
        case vs
    }

    public func build(vs enemy: Int?) -> BuildBlock {
        guard let enemy, let specific = vs?[String(enemy)] else { return defaultBuild }
        return defaultBuild.merged(with: specific)
    }
}

public struct BuildBlock: Codable, Sendable, Hashable {
    public var games: Int
    public var winrate: Double
    public var runes: RunePageStat?
    public var summonerSpells: SpellPairStat?
    public var skillOrder: SkillOrderStat?
    public var startingItems: ItemSetStat?
    public var coreBuild: ItemSetStat?
    public var archetypes: [ArchetypeStat]?
    public var boots: [ItemRate]?
    public var completedItems: [ItemRate]?
    public var situational: [ItemRate]?

    /// Matchup-specific blocks may be partial; fall back to the default per field.
    public func merged(with specific: BuildBlock) -> BuildBlock {
        var result = self
        result.games = specific.games
        result.winrate = specific.winrate
        result.runes = specific.runes ?? runes
        result.summonerSpells = specific.summonerSpells ?? summonerSpells
        result.skillOrder = specific.skillOrder ?? skillOrder
        result.startingItems = specific.startingItems ?? startingItems
        result.coreBuild = specific.coreBuild ?? coreBuild
        result.archetypes = specific.archetypes ?? archetypes
        result.boots = specific.boots ?? boots
        result.completedItems = specific.completedItems ?? completedItems
        result.situational = specific.situational ?? situational
        return result
    }
}

public struct RunePageStat: Codable, Sendable, Hashable {
    public var primaryStyleId: Int
    public var subStyleId: Int
    public var perkIds: [Int]
    public var games: Int?
    public var winrate: Double?

    public init(primaryStyleId: Int, subStyleId: Int, perkIds: [Int], games: Int? = nil, winrate: Double? = nil) {
        self.primaryStyleId = primaryStyleId
        self.subStyleId = subStyleId
        self.perkIds = perkIds
        self.games = games
        self.winrate = winrate
    }

    public var keystoneId: Int? { perkIds.first }
    public var primaryPerks: ArraySlice<Int> { perkIds.prefix(4) }
    public var secondaryPerks: ArraySlice<Int> { perkIds.dropFirst(4).prefix(2) }
    public var statShards: ArraySlice<Int> { perkIds.dropFirst(6).prefix(3) }
}

public struct SpellPairStat: Codable, Sendable, Hashable {
    public let ids: [Int]
    public let games: Int?
    public let winrate: Double?
}

public struct SkillOrderStat: Codable, Sendable, Hashable {
    public let maxOrder: [String]
    public let sequence: [String]?
    public let games: Int?
    public let winrate: Double?
}

public struct ItemSetStat: Codable, Sendable, Hashable {
    public let itemIds: [Int]
    public let games: Int?
    public let winrate: Double?
}

public struct ArchetypeStat: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let itemIds: [Int]
    public let games: Int
    public let winrate: Double
    public var id: String { name }
}

public struct ItemRate: Codable, Sendable, Hashable, Identifiable {
    public let itemId: Int
    public let pickrate: Double
    public let winrate: Double
    public var id: Int { itemId }
}

// MARK: item_stats.json

public struct ItemStatsFile: Codable, Sendable {
    public let meta: DataMeta
    public let items: [String: ItemStat]
}

public struct ItemStat: Codable, Sendable, Hashable {
    public let games: Int
    public let pickrate: Double
    public let winrate: Double
    public let avgCompletionMinute: Double?
    public let contextDeltas: [String: Double]?
}

// MARK: tierlist.json

public struct TierlistFile: Codable, Sendable {
    public let meta: DataMeta
    public let brackets: [TierBracket]
}

public struct TierBracket: Codable, Sendable, Hashable {
    public let rank: String
    public let platform: String
    public let modes: [String: [TierEntry]]
}

public struct PowerCurve: Codable, Sendable, Hashable {
    public let early: Double
    public let mid: Double
    public let late: Double
}

public struct TierEntry: Codable, Sendable, Hashable, Identifiable {
    public let championId: Int
    public let role: String
    public let laneShare: Double?
    public let rank: Int
    public let tier: Tier
    public let score: Double?
    public let winrate: Double
    public let winrateDelta: Double?
    public let pickrate: Double
    public let banrate: Double?
    public let games: Int
    public let powerCurve: PowerCurve?
    public let avgPlacement: Double?
    public let top4Rate: Double?
    public let partnerChampionId: Int?
    public let partnerRole: String?

    public var id: String { "\(championId)-\(role)-\(partnerChampionId ?? 0)" }
    public var roleValue: Role? { Role(rawValue: role) }
}

extension TierEntry {
    enum CodingKeys: String, CodingKey {
        case championId, role, laneShare, rank, tier, score, winrate, winrateDelta, pickrate, banrate, games
        case powerCurve, avgPlacement, top4Rate, partnerChampionId, partnerRole
    }

    /// Lenient decoding: duo rows may omit `rank` / `pickrate`, ARAM/Arena rows use role "ALL".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        championId = try c.decode(Int.self, forKey: .championId)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "ALL"
        laneShare = try c.decodeIfPresent(Double.self, forKey: .laneShare)
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        tier = try c.decode(Tier.self, forKey: .tier)
        score = try c.decodeIfPresent(Double.self, forKey: .score)
        winrate = try c.decode(Double.self, forKey: .winrate)
        winrateDelta = try c.decodeIfPresent(Double.self, forKey: .winrateDelta)
        pickrate = try c.decodeIfPresent(Double.self, forKey: .pickrate) ?? 0
        banrate = try c.decodeIfPresent(Double.self, forKey: .banrate)
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        powerCurve = try c.decodeIfPresent(PowerCurve.self, forKey: .powerCurve)
        avgPlacement = try c.decodeIfPresent(Double.self, forKey: .avgPlacement)
        top4Rate = try c.decodeIfPresent(Double.self, forKey: .top4Rate)
        partnerChampionId = try c.decodeIfPresent(Int.self, forKey: .partnerChampionId)
        partnerRole = try c.decodeIfPresent(String.self, forKey: .partnerRole)
    }
}

// MARK: aram_augments.json

public struct AugmentsFile: Codable, Sendable {
    public let meta: DataMeta
    public let modes: [String: AugmentModeStats]
}

public struct AugmentModeStats: Codable, Sendable, Hashable {
    public let augments: [AugmentStat]
    public let championAugments: [String: [AugmentStat]]
    public let builds: [String: BuildBlock]?
}

public struct AugmentStat: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let rarity: String?
    public let tier: Tier
    public let winrate: Double
    public let pickrate: Double?
    public let games: Int
    /// Arena (CHERRY) only: average placement 1–8 and top-4 rate (schema extension from the research brief).
    public let avgPlacement: Double?
    public let top4Rate: Double?
}

// MARK: pro_spectate.json

public struct ProSpectateFile: Codable, Sendable {
    public let meta: DataMeta
    public let games: [ProGame]
}

public struct ProGame: Codable, Sendable, Hashable, Identifiable {
    public let gameId: Int64
    public let platformId: String
    public let gameStartTime: Int64
    public let queueId: Int
    public let averageTier: String
    public let averageLp: Int
    public let knownPlayers: Int
    public let participants: [ProParticipant]

    public var id: Int64 { gameId }
    public var blue: [ProParticipant] { participants.filter { $0.teamId == 100 } }
    public var red: [ProParticipant] { participants.filter { $0.teamId == 200 } }
    public var startDate: Date { Date(timeIntervalSince1970: TimeInterval(gameStartTime) / 1000) }
}

public struct ProParticipant: Codable, Sendable, Hashable, Identifiable {
    public let teamId: Int
    public let championId: Int
    public let role: String?
    public let puuid: String?
    public let riotId: String?
    public let proName: String?
    public let proTeam: String?
    public let tier: String?
    public let lp: Int?
    public let isKnown: Bool

    public var id: String { "\(teamId)-\(championId)-\(riotId ?? "")" }
    public var displayName: String { proName ?? riotId?.components(separatedBy: "#").first ?? "Unbekannt" }
}

// MARK: leaderboard.json

public struct LeaderboardFile: Codable, Sendable {
    public let meta: DataMeta
    public let platforms: [String: [LeaderboardEntry]]
}

public struct LeaderboardEntry: Codable, Sendable, Hashable, Identifiable {
    public let rank: Int
    public let puuid: String?
    public let riotId: String
    public let tier: String
    public let lp: Int
    public let wins: Int
    public let losses: Int
    public let topChampionIds: [Int]

    public var id: String { "\(rank)-\(riotId)" }
    public var winrate: Double { wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses) }
}
