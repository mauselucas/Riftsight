import Foundation

public struct LCUCredentials: Sendable, Hashable {
    public let pid: Int?
    public let port: Int
    public let password: String
    public let scheme: String

    public init(pid: Int?, port: Int, password: String, scheme: String = "https") {
        self.pid = pid
        self.port = port
        self.password = password
        self.scheme = scheme
    }

    public var baseURL: URL { URL(string: "\(scheme)://127.0.0.1:\(port)")! }
    public var webSocketURL: URL { URL(string: "wss://127.0.0.1:\(port)/")! }
    public var authorization: String { "Basic " + Data("riot:\(password)".utf8).base64EncodedString() }
}

/// Accepts the self-signed Riot certificate **only** for loopback hosts (LCU and port 2999).
public final class LocalhostTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        Self.handle(challenge)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        Self.handle(challenge)
    }

    static func handle(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["127.0.0.1", "localhost"].contains(space.host),
              let trust = space.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

public enum LocalSession {
    public static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: LocalhostTrustDelegate(), delegateQueue: nil)
    }()
}

public enum LCUError: Error, LocalizedError, Sendable {
    case notConnected
    case http(status: Int, body: String)
    case invalidResponse
    case noFreeRunePage

    public var errorDescription: String? {
        switch self {
        case .notConnected: "League-Client ist nicht verbunden."
        case let .http(status, body): "LCU antwortete mit \(status): \(body.prefix(160))"
        case .invalidResponse: "Unerwartete Antwort vom League-Client."
        case .noFreeRunePage: "Kein freier Runenseiten-Slot. Riftsight löscht keine eigenen Seiten. Bitte eine Seite freigeben."
        }
    }
}

/// Thin REST wrapper for the League Client Update API (`https://127.0.0.1:<port>`, Basic Auth `riot:<password>`).
public struct LCURestClient: Sendable {
    public let credentials: LCUCredentials
    let session: URLSession

    public init(credentials: LCUCredentials, session: URLSession = LocalSession.shared) {
        self.credentials = credentials
        self.session = session
    }

    @discardableResult
    public func request(_ method: String = "GET", _ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: credentials.baseURL) else { throw LCUError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LCUError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LCUError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    public func get<T: Decodable & Sendable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let data = try await request("GET", path)
        return try await JSONFetcher.decodeOffMain(type, data: data)
    }

    /// JSON object from the response, for endpoints with loose/varying shapes.
    public func getObject(_ path: String) async throws -> Any {
        let data = try await request("GET", path)
        return try JSONSerialization.jsonObject(with: data)
    }

    public func send<Body: Encodable & Sendable>(_ method: String, _ path: String, json: Body) async throws {
        try await request(method, path, body: JSONEncoder().encode(json))
    }

    // MARK: Endpoints

    public func currentSummoner() async throws -> LCUSummoner {
        try await get("/lol-summoner/v1/current-summoner")
    }

    public func currentRankedStats() async throws -> LCURankedStats {
        try await get("/lol-ranked/v1/current-ranked-stats")
    }

    public func rankedStats(puuid: String) async throws -> LCURankedStats {
        try await get("/lol-ranked/v1/ranked-stats/\(puuid)")
    }

    public func gameflowPhase() async throws -> GameflowPhase {
        let raw = try await get("/lol-gameflow/v1/gameflow-phase", as: String.self)
        return GameflowPhase(lenient: raw)
    }

    public func gameflowSession() async throws -> GameflowSession {
        try await get("/lol-gameflow/v1/session")
    }

    public func champSelectSession() async throws -> ChampSelectSession {
        try await get("/lol-champ-select/v1/session")
    }

    public func masteries() async throws -> [LCUChampionMastery] {
        try await get("/lol-champion-mastery/v1/local-player/champion-masteries")
    }

    public func region() async throws -> String {
        let object = try await getObject("/riotclient/region-locale") as? [String: Any]
        return (object?["region"] as? String) ?? "EUW"
    }

    /// 1-click hover: sets the champion on the local player's open pick action (does not lock in).
    public func hover(championId: Int, actionId: Int) async throws {
        struct Body: Encodable, Sendable { let championId: Int }
        try await send("PATCH", "/lol-champ-select/v1/session/actions/\(actionId)", json: Body(championId: championId))
    }

    public func setSummonerSpells(_ first: Int, _ second: Int) async throws {
        struct Body: Encodable, Sendable { let spell1Id: Int; let spell2Id: Int }
        try await send("PATCH", "/lol-champ-select/v1/session/my-selection", json: Body(spell1Id: first, spell2Id: second))
    }

    // MARK: Match history

    public func matchHistory(puuid: String? = nil, count: Int = 20) async throws -> [MatchRecord] {
        let who = puuid ?? "current-summoner"
        let path = puuid == nil
            ? "/lol-match-history/v1/products/lol/current-summoner/matches?begIndex=0&endIndex=\(count - 1)"
            : "/lol-match-history/v1/products/lol/\(who)/matches?begIndex=0&endIndex=\(count - 1)"
        let object = try await getObject(path)
        return LCUMatchParser.matches(fromHistory: object)
    }

    public func game(_ gameId: Int64) async throws -> MatchRecord? {
        let object = try await getObject("/lol-match-history/v1/games/\(gameId)")
        guard let dict = object as? [String: Any] else { return nil }
        return LCUMatchParser.match(fromGame: dict, localPuuid: nil)
    }

    public func timeline(_ gameId: Int64) async throws -> [Int: ParticipantTimeline] {
        let object = try await getObject("/lol-match-history/v1/game-timelines/\(gameId)")
        return LCUMatchParser.timelines(from: object)
    }

    public func endOfGameBlock() async throws -> MatchRecord? {
        let object = try await getObject("/lol-end-of-game/v1/eog-stats-block")
        return LCUMatchParser.match(fromEndOfGame: object)
    }

    // MARK: Spectate

    /// Launches the spectator client for the game a player (by PUUID) is currently in.
    /// Starts spectating via the client. Only works for games on the client's own platform,
    /// and Riot releases the stream ~3 minutes after the game started.
    public func launchSpectate(puuid: String, gameId: Int64? = nil, queueType: String = "RANKED_SOLO_5x5") async throws {
        struct Body: Encodable, Sendable {
            let allowObserveMode = "ALL"
            let dropInSpectateGameId: String
            let gameQueueType: String
            let puuid: String
        }
        try await send("POST", "/lol-spectator/v1/spectate/launch",
                       json: Body(dropInSpectateGameId: gameId.map(String.init) ?? "", gameQueueType: queueType, puuid: puuid))
    }
}
