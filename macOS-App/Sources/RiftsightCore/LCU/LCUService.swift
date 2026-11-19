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
    public var onGameflowSession: ((GameflowSession) -> Void)?
    public var onEndOfGame: ((MatchRecord) -> Void)?
    public var onConnected: (() -> Void)?

    public let accounts: LinkedAccountsStore
    private let monitor = LockfileMonitor()
    private var listenTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastChampSelectEventAt: Date = .distantPast
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
        pollTask?.cancel()
        pollTask = nil
        guard let creds else {
            state = .disconnected
            client = nil
            phase = .none
            champSelect = nil
            gameflowSession = nil
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
        onConnected?()
        startFallbackPoller(client: client)

        var firstConnect = true
        while !Task.isCancelled {
            if !firstConnect {
                await syncActiveState(client: client)
            }
            firstConnect = false
            do {
                let paths = ["/lol-gameflow/v1/gameflow-phase", "/lol-gameflow/v1/session",
                             "/lol-champ-select/v1/session", "/lol-end-of-game/v1/eog-stats-block",
                             "/lol-ranked/v1/current-ranked-stats", "/lol-summoner/v1/current-summoner"]
                for try await event in LCUWebSocketClient.events(credentials: client.credentials, paths: paths) {
                    await handle(event, client: client)
                }
            } catch {
                if !Task.isCancelled {
                    DebugLog.shared.add("lcu", "WebSocket getrennt: \(error.localizedDescription)", error: true)
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Lightweight REST safety net so Champ Select and gameflow transitions never freeze if WAMP drops events.
    private func startFallbackPoller(client: LCURestClient) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay: Duration = self.phase == .champSelect ? .milliseconds(1200) : .seconds(2.5)
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
                if let currentPhase = try? await client.gameflowPhase() {
                    self.setPhase(currentPhase)
                }
                if self.phase == .champSelect, Date().timeIntervalSince(self.lastChampSelectEventAt) >= 1.2 {
                    if let session = try? await client.champSelectSession() {
                        self.champSelect = session
                        self.lastChampSelect = session
                    }
                } else if self.phase.isInGame {
                    let hasTeams = !(self.gameflowSession?.gameData?.teamOne?.isEmpty ?? true)
                    if !hasTeams, let session = try? await client.gameflowSession() {
                        self.applyGameflowSession(session)
                    }
                }
            }
        }
    }

    private func syncActiveState(client: LCURestClient) async {
        if let currentPhase = try? await client.gameflowPhase() {
            setPhase(currentPhase)
        }
        if phase == .champSelect, let session = try? await client.champSelectSession() {
            champSelect = session
            lastChampSelect = session
        }
        if phase.isInGame, let session = try? await client.gameflowSession() {
            applyGameflowSession(session)
        }
    }

    public func refreshAll(client: LCURestClient? = nil) async {
        guard let client = client ?? self.client else { return }
        let localPuuid = summoner?.puuid
        async let rankedTask = try? client.currentRankedStats()
        async let regionTask = try? client.region()
        async let phaseTask = try? client.gameflowPhase()
        async let masteryTask = try? client.masteries()
        async let historyTask = try? client.matchHistory(count: 20, localPuuid: localPuuid)
        ranked = await rankedTask
        region = await regionTask ?? region
        let fetchedPhase = await phaseTask ?? .none
        if fetchedPhase == .champSelect {
            champSelect = try? await client.champSelectSession()
            lastChampSelect = champSelect ?? lastChampSelect
        }
        if fetchedPhase.isInGame {
            if let session = try? await client.gameflowSession() {
                applyGameflowSession(session)
            }
        }
        setPhase(fetchedPhase)
        if let list = await masteryTask {
            masteries = Dictionary(list.map { ($0.championId, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if let history = await historyTask { recentMatches = history }
        if let summoner { accounts.upsert(summoner: summoner, ranked: ranked, region: region) }
        DebugLog.shared.add("lcu", "Verbunden als \(summoner?.riotName ?? "?") (\(region)), Phase \(phase.rawValue)")
    }

    private func handle(_ event: LCUEvent, client: LCURestClient) async {
        switch event.uri {
        case "/lol-gameflow/v1/gameflow-phase":
            if let raw = event.decode(String.self) { setPhase(GameflowPhase(lenient: raw)) }
        case "/lol-gameflow/v1/session":
            if event.eventType == "Delete" {
                gameflowSession = nil
            } else if let session = event.decode(GameflowSession.self) {
                applyGameflowSession(session)
            }
        case "/lol-champ-select/v1/session":
            lastChampSelectEventAt = .now
            if event.eventType == "Delete" {
                champSelect = nil
            } else if let session = event.decode(ChampSelectSession.self) {
                champSelect = session
                lastChampSelect = session
            } else if let data = event.data {
                do {
                    _ = try JSONDecoder().decode(ChampSelectSession.self, from: data)
                } catch {
                    DebugLog.shared.add("lcu", "Champ-Select-Decode fehlgeschlagen: \(error.localizedDescription)", error: true)
                }
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

    private func applyGameflowSession(_ session: GameflowSession) {
        gameflowSession = session
        let teamOne = session.gameData?.teamOne ?? []
        let teamTwo = session.gameData?.teamTwo ?? []
        if !teamOne.isEmpty || !teamTwo.isEmpty {
            onGameflowSession?(session)
        }
    }

    private func fetchGameflowSessionWithRetry(client: LCURestClient) {
        Task { [weak self] in
            for attempt in 0..<6 {
                guard let self, self.phase.isInGame else { return }
                if let session = try? await client.gameflowSession() {
                    self.applyGameflowSession(session)
                    let count = (session.gameData?.teamOne?.count ?? 0) + (session.gameData?.teamTwo?.count ?? 0)
                    if count > 0 { return }
                }
                if attempt < 5 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }

    private func setPhase(_ newPhase: GameflowPhase) {
        guard newPhase != phase else { return }
        let old = phase
        phase = newPhase
        DebugLog.shared.add("lcu", "Phase: \(old.rawValue) → \(newPhase.rawValue)")
        if newPhase == .champSelect {
            gameflowSession = nil
            if let solo = ranked?.soloDuo {
                ladderBeforeGame = ladderPoints(tier: solo.rankTier, division: solo.division, lp: solo.leaguePoints ?? 0)
            }
            if let client {
                Task { [weak self] in
                    if let session = try? await client.champSelectSession() {
                        self?.champSelect = session
                        self?.lastChampSelect = session
                    }
                }
            }
        }
        if newPhase != .champSelect {
            champSelect = nil
        }
        if newPhase.isInGame, let client {
            fetchGameflowSessionWithRetry(client: client)
        }
        if newPhase == .endOfGame, lastEndOfGame == nil || old != .endOfGame, let client {
            Task {
                if let record = try? await client.endOfGameBlock() { await self.finishGame(record, client: client) }
            }
        }
        if (newPhase == .none || newPhase == .lobby) && old == .endOfGame, let client {
            let localPuuid = summoner?.puuid
            Task { if let history = try? await client.matchHistory(count: 20, localPuuid: localPuuid) { self.recentMatches = history } }
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
        return try? await client.game(gameId, localPuuid: summoner?.puuid)
    }

    public func timeline(_ gameId: Int64) async -> [Int: ParticipantTimeline] {
        guard let client else { return [:] }
        return (try? await client.timeline(gameId)) ?? [:]
    }
}
