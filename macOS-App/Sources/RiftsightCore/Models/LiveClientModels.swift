import Foundation

// Live Client Data API: https://127.0.0.1:2999/liveclientdata/allgamedata

public struct LiveAllGameData: Codable, Sendable {
    public let activePlayer: LiveActivePlayer?
    public let allPlayers: [LivePlayer]
    public let events: LiveEvents?
    public let gameData: LiveGameData

    public var localPlayer: LivePlayer? {
        guard let active = activePlayer else { return nil }
        return allPlayers.first { $0.matches(name: active.displayName) }
    }

    public var localTeam: String { localPlayer?.team ?? "ORDER" }
    public var allies: [LivePlayer] { allPlayers.filter { $0.team == localTeam } }
    public var enemies: [LivePlayer] { allPlayers.filter { $0.team != localTeam } }
    public var modeBucket: GameModeBucket { GameModeBucket(liveGameMode: gameData.gameMode) }
}

public struct LiveActivePlayer: Codable, Sendable {
    public struct Abilities: Codable, Sendable {
        public let Q: Ability?
        public let W: Ability?
        public let E: Ability?
        public let R: Ability?

        public func level(_ key: String) -> Int {
            switch key {
            case "Q": Q?.abilityLevel ?? 0
            case "W": W?.abilityLevel ?? 0
            case "E": E?.abilityLevel ?? 0
            default: R?.abilityLevel ?? 0
            }
        }

        public var totalPoints: Int { ["Q", "W", "E", "R"].reduce(0) { $0 + level($1) } }
    }

    public struct Ability: Codable, Sendable {
        public let abilityLevel: Int?
        public let displayName: String?
        public let id: String?
    }

    public struct ChampionStats: Codable, Sendable {
        public let abilityHaste: Double?
        public let currentHealth: Double?
        public let maxHealth: Double?
        public let attackRange: Double?
    }

    public let abilities: Abilities?
    public let championStats: ChampionStats?
    public let currentGold: Double
    public let level: Int
    public let riotId: String?
    public let riotIdGameName: String?
    public let summonerName: String?

    public var displayName: String { riotId ?? summonerName ?? riotIdGameName ?? "" }
}

public struct LivePlayer: Codable, Sendable, Hashable, Identifiable {
    public struct Item: Codable, Sendable, Hashable {
        public let itemID: Int
        public let displayName: String?
        public let count: Int?
        public let price: Int?
        public let slot: Int?
        public let consumable: Bool?
    }

    public struct Scores: Codable, Sendable, Hashable {
        public let assists: Int
        public let creepScore: Int
        public let deaths: Int
        public let kills: Int
        public let wardScore: Double?
    }

    public struct SpellRef: Codable, Sendable, Hashable {
        public let displayName: String?
        public let rawDisplayName: String?

        /// `GeneratedTip_SummonerSpell_SummonerFlash_DisplayName` → `SummonerFlash`
        public var key: String {
            let raw = rawDisplayName ?? ""
            let parts = raw.components(separatedBy: "_")
            return parts.first { $0.hasPrefix("Summoner") && $0 != "SummonerSpell" } ?? raw
        }

        public var spellId: Int? { SummonerSpellKeys.id(forKey: key) }
    }

    public struct Spells: Codable, Sendable, Hashable {
        public let summonerSpellOne: SpellRef?
        public let summonerSpellTwo: SpellRef?
    }

    public let championName: String
    public let rawChampionName: String?
    public let isBot: Bool?
    public let isDead: Bool
    public let items: [Item]
    public let level: Int
    public let position: String?
    public let riotId: String?
    public let riotIdGameName: String?
    public let summonerName: String?
    public let respawnTimer: Double?
    public let scores: Scores
    public let summonerSpells: Spells?
    public let team: String
    public let skinID: Int?

    public var id: String { riotId ?? summonerName ?? championName }
    public var displayName: String { riotIdGameName ?? riotId?.components(separatedBy: "#").first ?? summonerName ?? championName }

    /// `game_character_displayname_Ahri` → `Ahri` (matches CommunityDragon `alias`).
    public var championAlias: String {
        guard let raw = rawChampionName, let last = raw.components(separatedBy: "_").last, !last.isEmpty else {
            return championName.replacingOccurrences(of: " ", with: "")
        }
        return last
    }

    public var role: Role? { position.flatMap { Role(flexible: $0) } }
    public var itemIds: [Int] { items.map(\.itemID) }

    public func matches(name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return riotId == name || summonerName == name || riotIdGameName == name
            || riotId?.components(separatedBy: "#").first == name.components(separatedBy: "#").first
    }
}

public struct LiveEvents: Codable, Sendable {
    public let Events: [LiveEvent]
}

public struct LiveEvent: Codable, Sendable, Hashable, Identifiable {
    public let EventID: Int
    public let EventName: String
    public let EventTime: Double
    public let KillerName: String?
    public let VictimName: String?
    public let Assisters: [String]?
    public let DragonType: String?
    public let Stolen: String?
    public let KillStreak: Int?
    public let Acer: String?
    public let AcingTeam: String?
    public let TurretKilled: String?
    public let InhibKilled: String?

    public init(EventID: Int, EventName: String, EventTime: Double, KillerName: String? = nil, VictimName: String? = nil,
                Assisters: [String]? = nil, DragonType: String? = nil, Stolen: String? = nil, KillStreak: Int? = nil,
                Acer: String? = nil, AcingTeam: String? = nil, TurretKilled: String? = nil, InhibKilled: String? = nil) {
        self.EventID = EventID
        self.EventName = EventName
        self.EventTime = EventTime
        self.KillerName = KillerName
        self.VictimName = VictimName
        self.Assisters = Assisters
        self.DragonType = DragonType
        self.Stolen = Stolen
        self.KillStreak = KillStreak
        self.Acer = Acer
        self.AcingTeam = AcingTeam
        self.TurretKilled = TurretKilled
        self.InhibKilled = InhibKilled
    }

    public var id: Int { EventID }
    public var wasStolen: Bool { Stolen?.lowercased() == "true" }
}

public struct LiveGameData: Codable, Sendable, Hashable {
    public let gameMode: String
    public let gameTime: Double
    public let mapName: String?
    public let mapNumber: Int?
    public let mapTerrain: String?
}

/// Maps Live Client `rawDisplayName` keys to summoner spell ids.
public enum SummonerSpellKeys {
    static let table: [String: Int] = [
        "SummonerBoost": 1, "SummonerExhaust": 3, "SummonerFlash": 4, "SummonerHaste": 6,
        "SummonerHeal": 7, "SummonerSmite": 11, "SummonerTeleport": 12, "SummonerMana": 13,
        "SummonerDot": 14, "SummonerBarrier": 21, "SummonerSnowball": 32, "SummonerSnowURFSnowball_Mark": 32,
        "SummonerCherryFlash": 2202, "SummonerCherryHold": 2201,
    ]

    public static func id(forKey key: String) -> Int? {
        if let id = table[key] { return id }
        if key.hasPrefix("SummonerSmite") { return 11 }
        if key.hasPrefix("SummonerTeleport") { return 12 }
        if key.hasPrefix("SummonerFlash") { return 4 }
        return nil
    }
}
