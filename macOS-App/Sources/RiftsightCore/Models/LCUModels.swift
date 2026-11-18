import Foundation

// MARK: - Summoner & ranked

public struct LCUSummoner: Codable, Sendable, Hashable {
    public let puuid: String
    public let summonerId: Int64?
    public let gameName: String?
    public let tagLine: String?
    public let displayName: String?
    public let profileIconId: Int
    public let summonerLevel: Int

    public var riotName: String { gameName ?? displayName ?? "Beschwörer" }
    public var riotTag: String { tagLine ?? "" }
}

public struct LCURankedStats: Codable, Sendable, Hashable {
    public let queueMap: [String: LCURankedQueue]?
    public let queues: [LCURankedQueue]?

    public var soloDuo: LCURankedQueue? { queueMap?["RANKED_SOLO_5x5"] ?? queues?.first { $0.queueType == "RANKED_SOLO_5x5" } }
    public var flex: LCURankedQueue? { queueMap?["RANKED_FLEX_SR"] ?? queues?.first { $0.queueType == "RANKED_FLEX_SR" } }
}

public struct LCURankedQueue: Codable, Sendable, Hashable {
    public let queueType: String?
    public let tier: String?
    public let division: String?
    public let leaguePoints: Int?
    public let wins: Int?
    public let losses: Int?

    public var rankTier: RankTier { RankTier(lenient: tier) }
    public var games: Int { (wins ?? 0) + (losses ?? 0) }
    public var winrate: Double { games == 0 ? 0 : Double(wins ?? 0) / Double(games) }

    public var shortLabel: String {
        let tier = rankTier
        if tier == .unranked { return "Ungewertet" }
        if tier.isApex { return "\(tier.shortCode)" }
        return "\(tier.shortCode)\(romanToInt(division ?? ""))"
    }

    func romanToInt(_ roman: String) -> String {
        switch roman { case "I": "1"; case "II": "2"; case "III": "3"; case "IV": "4"; default: "" }
    }
}

public enum GameflowPhase: String, Codable, Sendable {
    case none = "None"
    case lobby = "Lobby"
    case matchmaking = "Matchmaking"
    case checkedIntoTournament = "CheckedIntoTournament"
    case readyCheck = "ReadyCheck"
    case champSelect = "ChampSelect"
    case gameStart = "GameStart"
    case failedToLaunch = "FailedToLaunch"
    case inProgress = "InProgress"
    case reconnect = "Reconnect"
    case waitingForStats = "WaitingForStats"
    case preEndOfGame = "PreEndOfGame"
    case endOfGame = "EndOfGame"
    case terminatedInError = "TerminatedInError"

    public init(lenient raw: String) { self = GameflowPhase(rawValue: raw) ?? .none }

    public var isInGame: Bool { self == .gameStart || self == .inProgress || self == .reconnect }

    public var displayName: String {
        switch self {
        case .none: "Bereit"
        case .lobby: "Lobby"
        case .matchmaking: "Suche läuft"
        case .readyCheck: "Match gefunden"
        case .champSelect: "Champ Select"
        case .gameStart, .inProgress, .reconnect: "Im Spiel"
        case .waitingForStats, .preEndOfGame, .endOfGame: "Spielende"
        default: rawValue
        }
    }
}

// MARK: - Champ select

public struct ChampSelectSession: Codable, Sendable, Hashable {
    public struct Member: Codable, Sendable, Hashable {
        public let cellId: Int
        public let championId: Int
        public let championPickIntent: Int?
        public let assignedPosition: String?
        public let spell1Id: Int?
        public let spell2Id: Int?
        public let puuid: String?
        public let gameName: String?
        public let tagLine: String?
        public let team: Int?

        public var displayChampionId: Int { championId != 0 ? championId : (championPickIntent ?? 0) }
        public var role: Role? { assignedPosition.flatMap { Role(flexible: $0) } }
        public var hasSmite: Bool { spell1Id == 11 || spell2Id == 11 }
    }

    public struct Action: Codable, Sendable, Hashable {
        public let id: Int
        public let actorCellId: Int
        public let championId: Int
        public let completed: Bool
        public let isInProgress: Bool?
        public let isAllyAction: Bool?
        public let type: String
    }

    public struct Bans: Codable, Sendable, Hashable {
        public let myTeamBans: [Int]?
        public let theirTeamBans: [Int]?
    }

    public struct Timer: Codable, Sendable, Hashable {
        public let phase: String?
        public let adjustedTimeLeftInPhase: Double?
    }

    public let gameId: Int64?
    public let localPlayerCellId: Int
    public let myTeam: [Member]
    public let theirTeam: [Member]
    public let actions: [[Action]]
    public let bans: Bans?
    public let timer: Timer?

    public var localPlayer: Member? { myTeam.first { $0.cellId == localPlayerCellId } }

    /// The pick action of the local player that is still open, if any (for 1-click hover/lock).
    public var localPickAction: Action? {
        actions.joined().first { $0.actorCellId == localPlayerCellId && $0.type == "pick" && !$0.completed }
    }

    public var completedBanIds: (mine: [Int], theirs: [Int]) {
        let all = actions.joined().filter { $0.type == "ban" && $0.completed && $0.championId > 0 }
        let myCells = Set(myTeam.map(\.cellId))
        let mine = all.filter { myCells.contains($0.actorCellId) }.map(\.championId)
        let theirs = all.filter { !myCells.contains($0.actorCellId) }.map(\.championId)
        if mine.isEmpty && theirs.isEmpty {
            return (bans?.myTeamBans ?? [], bans?.theirTeamBans ?? [])
        }
        return (mine, theirs)
    }

    /// Blue side owns cell ids 0–4.
    public var isLocalBlueSide: Bool { (myTeam.map(\.cellId).min() ?? 0) < 5 }
}

// MARK: - Perks

public struct LCUPerkPage: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let isEditable: Bool?
    public let isDeletable: Bool?
    public let current: Bool?
    public let primaryStyleId: Int?
    public let subStyleId: Int?
    public let selectedPerkIds: [Int]?
}

public struct LCUPerkInventory: Codable, Sendable {
    public let ownedPageCount: Int?
}

// MARK: - Mastery

public struct LCUChampionMastery: Codable, Sendable, Hashable {
    public let championId: Int
    public let championLevel: Int
    public let championPoints: Int
    public let lastPlayTime: Int64?
}

// MARK: - Inventory (skins)

public struct LCUInventoryItem: Codable, Sendable, Hashable {
    public let itemId: Int
    public let inventoryType: String?
    public let purchaseDate: String?
    public let ownershipType: String?

    /// LCU dates look like `20240512T183012.000Z`.
    public var purchased: Date? {
        guard let purchaseDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: purchaseDate)
    }
}

// MARK: - Gameflow session (loading screen)

public struct GameflowSession: Codable, Sendable {
    public struct GameData: Codable, Sendable {
        public let gameId: Int64?
        public let queue: QueueInfo?
        public let teamOne: [TeamPlayer]?
        public let teamTwo: [TeamPlayer]?
    }

    public struct QueueInfo: Codable, Sendable {
        public let id: Int?
        public let gameMode: String?
    }

    public struct TeamPlayer: Codable, Sendable, Hashable {
        public let puuid: String?
        public let championId: Int?
        public let selectedPosition: String?
        public let summonerId: Int64?
        public let gameName: String?
        public let tagLine: String?
        public let summonerName: String?
    }

    public let phase: String?
    public let gameData: GameData?
}

// MARK: - Canonical match record (built from LCU match history or end-of-game block)

public struct MatchRecord: Codable, Sendable, Hashable, Identifiable {
    public var gameId: Int64
    public var queueId: Int
    public var gameMode: String
    public var creation: Date
    public var durationSeconds: Int
    public var teams: [TeamRecord]
    public var participants: [ParticipantRecord]
    public var localPuuid: String?
    public var lpChange: Int?

    public var id: Int64 { gameId }
    public var local: ParticipantRecord? { participants.first { $0.puuid == localPuuid } ?? participants.first }
    public var durationMinutes: Double { max(1, Double(durationSeconds) / 60) }

    public func team(_ teamId: Int) -> TeamRecord? { teams.first { $0.teamId == teamId } }
    public func players(team teamId: Int) -> [ParticipantRecord] { participants.filter { $0.teamId == teamId } }

    public init(gameId: Int64, queueId: Int, gameMode: String, creation: Date, durationSeconds: Int,
                teams: [TeamRecord], participants: [ParticipantRecord], localPuuid: String?, lpChange: Int? = nil) {
        self.gameId = gameId
        self.queueId = queueId
        self.gameMode = gameMode
        self.creation = creation
        self.durationSeconds = durationSeconds
        self.teams = teams
        self.participants = participants
        self.localPuuid = localPuuid
        self.lpChange = lpChange
    }
}

public struct TeamRecord: Codable, Sendable, Hashable {
    public var teamId: Int
    public var win: Bool
    public var baronKills: Int
    public var dragonKills: Int
    public var towerKills: Int
    public var inhibitorKills: Int
    public var heraldKills: Int
    public var hordeKills: Int
    public var bans: [Int]

    public init(teamId: Int, win: Bool, baronKills: Int = 0, dragonKills: Int = 0, towerKills: Int = 0,
                inhibitorKills: Int = 0, heraldKills: Int = 0, hordeKills: Int = 0, bans: [Int] = []) {
        self.teamId = teamId
        self.win = win
        self.baronKills = baronKills
        self.dragonKills = dragonKills
        self.towerKills = towerKills
        self.inhibitorKills = inhibitorKills
        self.heraldKills = heraldKills
        self.hordeKills = hordeKills
        self.bans = bans
    }
}

public struct ParticipantRecord: Codable, Sendable, Hashable, Identifiable {
    public var participantId: Int
    public var teamId: Int
    public var puuid: String?
    public var gameName: String
    public var tagLine: String
    public var championId: Int
    public var role: Role?
    public var champLevel: Int
    public var spell1Id: Int
    public var spell2Id: Int
    public var keystoneId: Int
    public var subStyleId: Int
    public var items: [Int]
    public var kills: Int
    public var deaths: Int
    public var assists: Int
    public var cs: Int
    public var gold: Int
    public var damageToChampions: Int
    public var damageTaken: Int
    public var visionScore: Int
    public var objectiveDamage: Int
    public var rankTier: String?
    public var rankDivision: String?
    public var win: Bool

    public var id: Int { participantId }
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }

    public init(participantId: Int, teamId: Int, puuid: String?, gameName: String, tagLine: String, championId: Int,
                role: Role?, champLevel: Int, spell1Id: Int, spell2Id: Int, keystoneId: Int, subStyleId: Int,
                items: [Int], kills: Int, deaths: Int, assists: Int, cs: Int, gold: Int, damageToChampions: Int,
                damageTaken: Int, visionScore: Int, objectiveDamage: Int, rankTier: String? = nil,
                rankDivision: String? = nil, win: Bool) {
        self.participantId = participantId
        self.teamId = teamId
        self.puuid = puuid
        self.gameName = gameName
        self.tagLine = tagLine
        self.championId = championId
        self.role = role
        self.champLevel = champLevel
        self.spell1Id = spell1Id
        self.spell2Id = spell2Id
        self.keystoneId = keystoneId
        self.subStyleId = subStyleId
        self.items = items
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.cs = cs
        self.gold = gold
        self.damageToChampions = damageToChampions
        self.damageTaken = damageTaken
        self.visionScore = visionScore
        self.objectiveDamage = objectiveDamage
        self.rankTier = rankTier
        self.rankDivision = rankDivision
        self.win = win
    }
}

/// Per-minute frames for a single participant (from `/lol-match-history/v1/game-timelines/{gameId}`).
public struct ParticipantTimeline: Codable, Sendable, Hashable {
    public var csAtMinute: [Int: Int]
    public var deathTimes: [Double]
    public var takedownTimes: [Double]

    public init(csAtMinute: [Int: Int] = [:], deathTimes: [Double] = [], takedownTimes: [Double] = []) {
        self.csAtMinute = csAtMinute
        self.deathTimes = deathTimes
        self.takedownTimes = takedownTimes
    }
}
