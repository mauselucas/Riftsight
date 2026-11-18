import Foundation

/// Central LCU connection: detects the client, mirrors the relevant state and pushes WebSocket updates.
@MainActor
@Observable
public final class LCUService {
    public enum ConnectionState: Sendable { case disconnected, connecting, connected }

    public private(set) var state: ConnectionState = .disconnected
    public private(set) var client: LCURestClient?
    public private(set) var summoner: LCUSummoner?
    public private(set) var ranked: LCURankedStats?
    public private(set) var region = "EUW"
    public private(set) var phase: GameflowPhase = .none
    public private(set) var champSelect: ChampSelectSession?
    /// Stays on screen after champ select ends (so the draft can be reviewed).
    public private(set) var lastChampSelect: ChampSelectSession?
    public private(set) var gameflowSession: GameflowSession?
    public private(set) var masteries: [Int: LCUChampionMastery] = [:]
    public private(set) var recentMatches: [MatchRecord] = []
    public private(set) var lastEndOfGame: MatchRecord?

    public var onPhaseChange: ((GameflowPhase, GameflowPhase) -> Void)?
    public var onEndOfGame: ((MatchRecord) -> Void)?

    public let accounts: LinkedAccountsStore
    private let monitor = LockfileMonitor()
    private var listenTask: Task<Void, Never>?
    private var ladderBeforeGame: Int?

    public init(accounts: LinkedAccountsStore) {
        self.accounts = accounts
    }

    public var isConnected: Bool { state == .connected }

    public func start() {
        monitor.onChange = { [weak self] creds in self?.credentialsChanged(creds) }
        monitor.start()
    }

    private func credentialsChanged(_ creds: LCUCredentials?) {
        listenTask?.cancel()
        listenTask = nil
        guard let creds else {
            state = .disconnected
            client = nil
            phase = .none
            champSelect = nil
            return
        }
        let client = LCURestClient(credentials: creds)
        self.client = client
        state = .connecting
        listenTask = Task { [weak self] in await self?.run(client: client) }
    }

    private func run(client: LCURestClient) async {
        // The client needs a few seconds after launch before the summoner endpoint answers.
        for attempt in 0..<20 {
            if Task.isCancelled { return }
            if let summoner = try? await client.currentSummoner() {
                self.summoner = summoner
                break
            }
            try? await Task.sleep(for: .seconds(attempt < 5 ? 1 : 3))
        }
        guard summoner != nil else { state = .disconnected; return }
        state = .connected
        await refreshAll(client: client)

        while !Task.isCancelled {
            do {
                let paths = ["/lol-gameflow/v1/gameflow-phase", "/lol-champ-select/v1/session",
                             "/lol-end-of-game/v1/eog-stats-block", "/lol-ranked/v1/current-ranked-stats",
                             "/lol-summoner/v1/current-summoner"]
                for try await event in LCUWebSocketClient.events(credentials: client.credentials, paths: paths) {
                    await handle(event, client: client)
                }
            } catch {
                DebugLog.shared.add("lcu", "WebSocket getrennt: \(error.localizedDescription)", error: true)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    public func refreshAll(client: LCURestClient? = nil) async {
        guard let client = client ?? self.client else { return }
        async let rankedTask = try? client.currentRankedStats()
        async let regionTask = try? client.region()
        async let phaseTask = try? client.gameflowPhase()
        async let masteryTask = try? client.masteries()
        async let historyTask = try? client.matchHistory(count: 20)
        ranked = await rankedTask
        region = await regionTask ?? region
        setPhase(await phaseTask ?? .none)
        if let list = await masteryTask {
            masteries = Dictionary(list.map { ($0.championId, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if let history = await historyTask { recentMatches = history }
        if phase == .champSelect { champSelect = try? await client.champSelectSession(); lastChampSelect = champSelect ?? lastChampSelect }
        if phase.isInGame { gameflowSession = try? await client.gameflowSession() }
        if let summoner { accounts.upsert(summoner: summoner, ranked: ranked, region: region) }
        DebugLog.shared.add("lcu", "Verbunden als \(summoner?.riotName ?? "?") (\(region)), Phase \(phase.rawValue)")
    }

    private func handle(_ event: LCUEvent, client: LCURestClient) async {
        switch event.uri {
        case "/lol-gameflow/v1/gameflow-phase":
            if let raw = event.decode(String.self) { setPhase(GameflowPhase(lenient: raw)) }
        case "/lol-champ-select/v1/session":
            if event.eventType == "Delete" {
                champSelect = nil
            } else if let session = event.decode(ChampSelectSession.self) {
                champSelect = session
                lastChampSelect = session
            }
        case "/lol-end-of-game/v1/eog-stats-block":
            if let data = event.data, let object = try? JSONSerialization.jsonObject(with: data),
               let record = LCUMatchParser.match(fromEndOfGame: object) {
                await finishGame(record, client: client)
            }
        case "/lol-ranked/v1/current-ranked-stats":
            if let stats = event.decode(LCURankedStats.self) { ranked = stats }
        case "/lol-summoner/v1/current-summoner":
            if let s = event.decode(LCUSummoner.self) { summoner = s }
        default:
            break
        }
    }

    private func setPhase(_ newPhase: GameflowPhase) {
        guard newPhase != phase else { return }
        let old = phase
        phase = newPhase
        DebugLog.shared.add("lcu", "Phase: \(old.rawValue) → \(newPhase.rawValue)")
        if newPhase == .champSelect, let solo = ranked?.soloDuo {
            ladderBeforeGame = ladderPoints(tier: solo.rankTier, division: solo.division, lp: solo.leaguePoints ?? 0)
        }
        if newPhase.isInGame, let client {
            Task { self.gameflowSession = try? await client.gameflowSession() }
        }
        if newPhase == .endOfGame, lastEndOfGame == nil || old != .endOfGame, let client {
            Task {
                if let record = try? await client.endOfGameBlock() { await self.finishGame(record, client: client) }
            }
        }
        if (newPhase == .none || newPhase == .lobby) && old == .endOfGame, let client {
            Task { if let history = try? await client.matchHistory(count: 20) { self.recentMatches = history } }
        }
        onPhaseChange?(old, newPhase)
    }

    private func finishGame(_ record: MatchRecord, client: LCURestClient) async {
        guard lastEndOfGame?.gameId != record.gameId else { return }
        var record = record
        if let stats = try? await client.currentRankedStats(), let solo = stats.soloDuo {
            ranked = stats
            let after = ladderPoints(tier: solo.rankTier, division: solo.division, lp: solo.leaguePoints ?? 0)
            if let before = ladderBeforeGame, record.queueId == Queue.rankedSolo.rawValue || record.queueId == 0 {
                record.lpChange = after - before
            }
            if let summoner { accounts.upsert(summoner: summoner, ranked: stats, region: region) }
        }
        lastEndOfGame = record
        onEndOfGame?(record)
    }

    // MARK: Actions

    public func hover(championId: Int) async throws {
        guard let client else { throw LCUError.notConnected }
        guard let action = champSelect?.localPickAction else { return }
        try await client.hover(championId: championId, actionId: action.id)
    }

    public func applyRunes(_ page: RunePageStat, title: String) async throws {
        guard let client else { throw LCUError.notConnected }
        try await RunePageService.apply(page, title: title, client: client)
    }

    public func applySummonerSpells(_ ids: [Int]) async throws {
        guard let client else { throw LCUError.notConnected }
        guard ids.count == 2 else { return }
        try await client.setSummonerSpells(ids[0], ids[1])
    }

    public func launchSpectate(puuid: String, gameId: Int64? = nil) async throws {
        guard let client else { throw LCUError.notConnected }
        try await client.launchSpectate(puuid: puuid, gameId: gameId)
    }

    public func loadSkinInventory() async throws -> SkinInventory {
        guard let client else { throw LCUError.notConnected }
        return try await SkinInventoryService.load(client: client)
    }

    public func fullGame(_ gameId: Int64) async -> MatchRecord? {
        guard let client else { return nil }
        return try? await client.game(gameId)
    }

    public func timeline(_ gameId: Int64) async -> [Int: ParticipantTimeline] {
        guard let client else { return [:] }
        return (try? await client.timeline(gameId)) ?? [:]
    }
}
