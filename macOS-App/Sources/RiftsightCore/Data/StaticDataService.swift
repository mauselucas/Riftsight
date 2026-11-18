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
        counterpicks = await c
        matchupRunes = await m
        itemStats = await i
        tierlist = await t
        augments = await a
        proSpectate = await p
        leaderboard = await l
        lastLoaded = .now
        DebugLog.shared.add("data", "Pipeline-Daten geladen (\(usingSampleData ? "Beispieldaten" : "live"), Patch \(dataPatch ?? "?"))")
    }

    private func file<T: Decodable & Sendable>(_ type: T.Type, _ name: String) async -> T? {
        if let base = baseURL {
            do {
                return try await fetcher.decode(type, from: base.appendingPathComponent(name),
                                                cacheKey: "pipeline/\(name)", policy: .networkFirst)
            } catch {
                DebugLog.shared.add("data", "\(name) vom Server fehlgeschlagen: \(error.localizedDescription)", error: true)
            }
        }
        guard let dir = AppPaths.sampleData, let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else {
            return nil
        }
        do {
            return try await JSONFetcher.decodeOffMain(type, data: data)
        } catch {
            DebugLog.shared.add("data", "Beispieldatei \(name) ungültig: \(error)", error: true)
            return nil
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

    public func build(championId: Int, role: Role, vs enemy: Int? = nil) -> BuildBlock? {
        matchupRunes?.builds(championId: championId, role: role)?.build(vs: enemy)
    }

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
