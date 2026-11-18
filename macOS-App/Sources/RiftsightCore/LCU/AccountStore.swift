import Foundation

/// A linked League account (multi-account support), persisted locally.
public struct LinkedAccount: Codable, Sendable, Hashable, Identifiable {
    public var puuid: String
    public var gameName: String
    public var tagLine: String
    public var region: String
    public var profileIconId: Int
    public var level: Int
    public var soloTier: String?
    public var soloDivision: String?
    public var soloLP: Int?
    public var wins: Int?
    public var losses: Int?
    public var lastSeen: Date

    public var id: String { puuid }
    public var rankTier: RankTier { RankTier(lenient: soloTier) }

    public init(puuid: String, gameName: String, tagLine: String, region: String, profileIconId: Int, level: Int,
                soloTier: String? = nil, soloDivision: String? = nil, soloLP: Int? = nil, wins: Int? = nil,
                losses: Int? = nil, lastSeen: Date = .now) {
        self.puuid = puuid
        self.gameName = gameName
        self.tagLine = tagLine
        self.region = region
        self.profileIconId = profileIconId
        self.level = level
        self.soloTier = soloTier
        self.soloDivision = soloDivision
        self.soloLP = soloLP
        self.wins = wins
        self.losses = losses
        self.lastSeen = lastSeen
    }
}

public struct LPPoint: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var ladderPoints: Int
    public var lp: Int
    public var tier: String
    public var division: String?
    public var id: Date { date }

    public init(date: Date, ladderPoints: Int, lp: Int, tier: String, division: String?) {
        self.date = date
        self.ladderPoints = ladderPoints
        self.lp = lp
        self.tier = tier
        self.division = division
    }
}

/// Maps a rank to a single ladder value for graphs and LP deltas (apex tiers share one ladder above Diamond I).
public func ladderPoints(tier: RankTier, division: String?, lp: Int) -> Int {
    let base: Int
    switch tier {
    case .unranked: return 0
    case .iron: base = 0
    case .bronze: base = 400
    case .silver: base = 800
    case .gold: base = 1200
    case .platinum: base = 1600
    case .emerald: base = 2000
    case .diamond: base = 2400
    case .master, .grandmaster, .challenger: return 2800 + lp
    }
    let divisionOffset = ["IV": 0, "III": 100, "II": 200, "I": 300][division ?? "IV"] ?? 0
    return base + divisionOffset + lp
}

@MainActor
@Observable
public final class LinkedAccountsStore {
    public private(set) var accounts: [LinkedAccount] = []
    public private(set) var lpHistory: [String: [LPPoint]] = [:]
    private let accountsFile = AppPaths.support.appendingPathComponent("accounts.json")
    private let lpFile = AppPaths.support.appendingPathComponent("lp-history.json")

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: accountsFile), let stored = try? decoder.decode([LinkedAccount].self, from: data) {
            accounts = stored
        }
        if let data = try? Data(contentsOf: lpFile), let stored = try? decoder.decode([String: [LPPoint]].self, from: data) {
            lpHistory = stored
        }
    }

    public func upsert(summoner: LCUSummoner, ranked: LCURankedStats?, region: String) {
        let solo = ranked?.soloDuo
        let account = LinkedAccount(puuid: summoner.puuid, gameName: summoner.riotName, tagLine: summoner.riotTag,
                                    region: region, profileIconId: summoner.profileIconId, level: summoner.summonerLevel,
                                    soloTier: solo?.tier, soloDivision: solo?.division, soloLP: solo?.leaguePoints,
                                    wins: solo?.wins, losses: solo?.losses, lastSeen: .now)
        if let index = accounts.firstIndex(where: { $0.puuid == summoner.puuid }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        if let solo, solo.rankTier != .unranked {
            recordLP(puuid: summoner.puuid, queue: solo)
        }
        save()
    }

    public func remove(_ puuid: String) {
        accounts.removeAll { $0.puuid == puuid }
        save()
    }

    func recordLP(puuid: String, queue: LCURankedQueue) {
        let point = LPPoint(date: .now,
                            ladderPoints: ladderPoints(tier: queue.rankTier, division: queue.division, lp: queue.leaguePoints ?? 0),
                            lp: queue.leaguePoints ?? 0, tier: queue.tier ?? "", division: queue.division)
        var history = lpHistory[puuid] ?? []
        if history.last?.ladderPoints != point.ladderPoints { history.append(point) }
        lpHistory[puuid] = Array(history.suffix(400))
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(accounts) { try? data.write(to: accountsFile, options: .atomic) }
        if let data = try? encoder.encode(lpHistory) { try? data.write(to: lpFile, options: .atomic) }
    }
}
