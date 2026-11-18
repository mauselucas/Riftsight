import Foundation

public struct ScoutPlayer: Sendable, Hashable, Identifiable {
    public var puuid: String
    public var name: String
    public var tag: String
    public var championId: Int
    public var role: Role?
    public var teamId: Int
    public var solo: LCURankedQueue?
    public var recentGames: Int
    public var recentWins: Int
    public var championPool: [(championId: Int, games: Int, wins: Int)]
    public var badges: [PlayerBadge]
    public var isLoading: Bool

    public var id: String { puuid.isEmpty ? "\(teamId)-\(championId)" : puuid }
    public var recentWinrate: Double { recentGames == 0 ? 0 : Double(recentWins) / Double(recentGames) }

    public static func == (lhs: ScoutPlayer, rhs: ScoutPlayer) -> Bool {
        lhs.id == rhs.id && lhs.isLoading == rhs.isLoading && lhs.badges == rhs.badges && lhs.championId == rhs.championId
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(puuid: String, name: String, tag: String, championId: Int, role: Role?, teamId: Int,
                solo: LCURankedQueue? = nil, recentGames: Int = 0, recentWins: Int = 0,
                championPool: [(championId: Int, games: Int, wins: Int)] = [], badges: [PlayerBadge] = [], isLoading: Bool = true) {
        self.puuid = puuid
        self.name = name
        self.tag = tag
        self.championId = championId
        self.role = role
        self.teamId = teamId
        self.solo = solo
        self.recentGames = recentGames
        self.recentWins = recentWins
        self.championPool = championPool
        self.badges = badges
        self.isLoading = isLoading
    }
}

/// Loading-screen scout: rank, recent winrate, champion pool and behaviour badges for all ten players.
@MainActor
@Observable
public final class LoadingScreenScout {
    public private(set) var players: [ScoutPlayer] = []
    public private(set) var gameId: Int64?
    private var task: Task<Void, Never>?

    public init() {}

    public func scout(session: GameflowSession, client: LCURestClient, championNames: [Int: String]) {
        guard let data = session.gameData, data.gameId != gameId else { return }
        gameId = data.gameId
        task?.cancel()
        let teamOne = (data.teamOne ?? []).map { ($0, 100) }
        let teamTwo = (data.teamTwo ?? []).map { ($0, 200) }
        players = (teamOne + teamTwo).map { player, team in
            ScoutPlayer(puuid: player.puuid ?? "", name: player.gameName ?? player.summonerName ?? "Spieler",
                        tag: player.tagLine ?? "", championId: player.championId ?? 0,
                        role: player.selectedPosition.flatMap { Role(flexible: $0) }, teamId: team)
        }
        task = Task {
            await withTaskGroup(of: (Int, ScoutPlayer).self) { group in
                for (index, player) in players.enumerated() where !player.puuid.isEmpty {
                    group.addTask {
                        (index, await Self.enrich(player, client: client, championNames: championNames))
                    }
                }
                for await (index, enriched) in group where players.indices.contains(index) {
                    players[index] = enriched
                }
            }
        }
    }

    public func reset() {
        task?.cancel()
        players = []
        gameId = nil
    }

    /// Demo/preview data.
    public func show(_ demo: [ScoutPlayer]) { players = demo }

    nonisolated static func enrich(_ player: ScoutPlayer, client: LCURestClient, championNames: [Int: String]) async -> ScoutPlayer {
        var result = player
        async let ranked = try? client.rankedStats(puuid: player.puuid)
        async let history = try? client.matchHistory(puuid: player.puuid, count: 20)
        result.solo = await ranked?.soloDuo
        let games = await history ?? []
        let own = games.compactMap { $0.participants.first { $0.puuid == player.puuid } ?? $0.local }
        result.recentGames = own.count
        result.recentWins = own.filter(\.win).count
        let grouped = Dictionary(grouping: own, by: \.championId)
        result.championPool = grouped.map { ($0.key, $0.value.count, $0.value.filter(\.win).count) }
            .sorted { $0.1 > $1.1 }
            .prefix(5).map { (championId: $0.0, games: $0.1, wins: $0.2) }

        var earlyTakedowns: Double?
        if player.role == .jungle {
            let jungleGames = games.filter { ($0.local?.role ?? .jungle) == .jungle }.prefix(3)
            var total = 0, counted = 0
            for game in jungleGames {
                guard let timelines = try? await client.timeline(game.gameId),
                      let pid = game.local?.participantId, let line = timelines[pid] else { continue }
                total += line.takedownTimes.filter { $0 < 240 }.count
                counted += 1
            }
            if counted > 0 { earlyTakedowns = Double(total) / Double(counted) }
        }
        result.badges = BehaviorBadges.badges(history: games, puuid: player.puuid, currentChampionId: player.championId,
                                              role: player.role, earlyTakedownsPerGame: earlyTakedowns,
                                              championName: { championNames[$0] ?? "#\($0)" })
        result.isLoading = false
        return result
    }
}
