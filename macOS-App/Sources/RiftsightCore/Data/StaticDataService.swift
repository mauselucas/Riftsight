import Foundation

/// Loads the pipeline JSONs (counterpicks, builds, tierlist, …) from the configured host, cached on disk,
/// and falls back to the bundled sample files (`meta.sample == true`).
@MainActor
@Observable
public final class StaticDataService {
    public static let baseURLDefaultsKey = "pipelineBaseURL"

    public private(set) var counterpicks: CounterpicksFile?
    public private(set) var matchupRunes: MatchupRunesFile?
    public private(set) var itemStats: ItemStatsFile?
    public private(set) var tierlist: TierlistFile?
    public private(set) var augments: AugmentsFile?
    public private(set) var proSpectate: ProSpectateFile?
    public private(set) var leaderboard: LeaderboardFile?
    public private(set) var lastLoaded: Date?
    /// True when the configured `baseURL` answered without falling back to local sample files.
    public private(set) var serverReachable = false
    /// True when at least one file failed from `baseURL` and fell back to local bundled sample data.
    public private(set) var lastLoadUsedFallback = false

    private let fetcher: JSONFetcher

    public init(fetcher: JSONFetcher = JSONFetcher()) {
        self.fetcher = fetcher
    }

    public var baseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey), !raw.isEmpty else { return nil }
        return URL(string: raw.hasSuffix("/") ? raw : raw + "/")
    }

    /// True as soon as any loaded file is sample data.
    public var usingSampleData: Bool {
        [counterpicks?.meta, matchupRunes?.meta, tierlist?.meta, augments?.meta, proSpectate?.meta]
            .compactMap { $0 }.contains { $0.sample }
    }

    public var dataPatch: String? { tierlist?.meta.patch ?? matchupRunes?.meta.patch }

    public func load() async {
        async let c = file(CounterpicksFile.self, "counterpicks.json")
        async let m = file(MatchupRunesFile.self, "matchup_runes.json")
        async let i = file(ItemStatsFile.self, "item_stats.json")
        async let t = file(TierlistFile.self, "tierlist.json")
        async let a = file(AugmentsFile.self, "aram_augments.json")
        async let p = file(ProSpectateFile.self, "pro_spectate.json")
        async let l = file(LeaderboardFile.self, "leaderboard.json")
        let (rc, rm, ri, rt, ra, rp, rl) = await (c, m, i, t, a, p, l)
        counterpicks = rc.value
        matchupRunes = rm.value
        itemStats = ri.value
        tierlist = rt.value
        augments = ra.value
        proSpectate = rp.value
        leaderboard = rl.value
        let results = [rc.fromServer, rm.fromServer, ri.fromServer, rt.fromServer, ra.fromServer, rp.fromServer, rl.fromServer]
        serverReachable = baseURL != nil && results.contains(true)
        lastLoadUsedFallback = baseURL != nil && results.contains(false)
        lastLoaded = .now
        let sourceLabel = serverReachable
            ? (usingSampleData ? "Server / Sample-Modus" : "live")
            : "Beispieldaten"
        DebugLog.shared.add("data", "Pipeline-Daten geladen (\(sourceLabel), Patch \(dataPatch ?? "?"))")
    }

    private func file<T: Decodable & Sendable>(_ type: T.Type, _ name: String) async -> (value: T?, fromServer: Bool) {
        if let base = baseURL {
            do {
                let decoded = try await fetcher.decode(type, from: base.appendingPathComponent(name),
                                                       cacheKey: "pipeline/\(name)", policy: .networkFirst)
                return (decoded, true)
            } catch {
                DebugLog.shared.add("data", "\(name) vom Server fehlgeschlagen: \(error.localizedDescription)", error: true)
            }
        }
        guard let dir = AppPaths.sampleData, let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else {
            return (nil, false)
        }
        do {
            return (try await JSONFetcher.decodeOffMain(type, data: data), false)
        } catch {
            DebugLog.shared.add("data", "Beispieldatei \(name) ungültig: \(error)", error: true)
            return (nil, false)
        }
    }

    // MARK: Convenience queries

    public func tierEntries(mode: String = "ranked", rank: String = "EMERALD_PLUS", platform: String = "ALL") -> [TierEntry] {
        guard let brackets = tierlist?.brackets else { return [] }
        let bracket = brackets.first { $0.rank == rank && $0.platform == platform } ?? brackets.first
        return bracket?.modes[mode] ?? []
    }

    public var availableRanks: [String] { Array(Set(tierlist?.brackets.map(\.rank) ?? [])).sorted() }
    public var availablePlatforms: [String] { Array(Set(tierlist?.brackets.map(\.platform) ?? [])).sorted() }

    public func tierEntry(championId: Int, role: Role?) -> TierEntry? {
        let entries = tierEntries().filter { $0.championId == championId }
        if let role, let exact = entries.first(where: { $0.role == role.rawValue }) { return exact }
        return entries.max { $0.games < $1.games }
    }

    /// Below this many games a build recommendation is too noisy to act on.
    public static let minReliableBuildGames = 40
    /// Matchup-specific blocks need at least this many games before they override the default build.
    public static let minMatchupBuildGames = 30

    public func build(championId: Int, role: Role, vs enemy: Int? = nil) -> BuildBlock? {
        guard let builds = matchupRunes?.builds(championId: championId, role: role) else { return nil }
        guard let enemy, let specific = builds.vs?[String(enemy)], specific.games >= Self.minMatchupBuildGames else {
            return builds.defaultBuild
        }
        return builds.defaultBuild.merged(with: specific)
    }

    /// True when the build rests on enough games to be shown as a recommendation.
    public func isReliable(_ build: BuildBlock?) -> Bool { (build?.games ?? 0) >= Self.minReliableBuildGames }

    public func counters(of championId: Int, role: Role) -> [CounterEntry] {
        counterpicks?.block(championId: championId, role: role)?.counters ?? []
    }

    /// Lane win-rate delta of `championId` against `enemyId` (positive = good for `championId`).
    public func matchupDelta(championId: Int, vs enemyId: Int, role: Role) -> Double? {
        if let entry = counters(of: enemyId, role: role).first(where: { $0.championId == championId }) {
            return entry.delta
        }
        if let entry = counters(of: championId, role: role).first(where: { $0.championId == enemyId }) {
            return -entry.delta
        }
        return nil
    }

    public func augmentStats(mode: String) -> AugmentModeStats? { augments?.modes[mode] }
}
