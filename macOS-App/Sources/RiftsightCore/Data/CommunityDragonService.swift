import Foundation

/// Static game data (champions, items, runes, spells, skins, augments) from CommunityDragon `de_de`
/// and Data Dragon, cached on disk once per patch.
@MainActor
@Observable
public final class CommunityDragonService {
    static let cdragonBase = "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/de_de/v1"

    public private(set) var version = "16.23.1"
    public private(set) var champions: [Int: ChampionSummary] = [:]
    public private(set) var items: [Int: Item] = [:]
    public private(set) var perks: [Int: Perk] = [:]
    public private(set) var perkStyles: [Int: PerkStyle] = [:]
    public private(set) var summonerSpells: [Int: SummonerSpell] = [:]
    public private(set) var ddChampions: [Int: DDragonChampion] = [:]
    public private(set) var skins: [Int: Skin] = [:]
    public private(set) var skinLines: [Int: SkinLine] = [:]
    public private(set) var augments: [Int: ArenaAugment] = [:]
    public private(set) var roleRates: [Int: [Role: Double]] = [:]
    public private(set) var isLoaded = false
    public private(set) var loadError: String?

    private var details: [Int: ChampionDetail] = [:]
    private var aliasIndex: [String: Int] = [:]
    private let fetcher: JSONFetcher

    public init(fetcher: JSONFetcher = JSONFetcher()) {
        self.fetcher = fetcher
    }

    /// `16.23.1` → `16.23`
    public var patch: String { version.split(separator: ".").prefix(2).joined(separator: ".") }

    public var sortedChampions: [ChampionSummary] {
        champions.values.filter(\.isPlayable).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    public func load() async {
        do {
            let versions = try await fetcher.decode([String].self,
                                                    from: URL(string: "https://ddragon.leagueoflegends.com/api/versions.json")!,
                                                    cacheKey: "versions.json", policy: .networkFirst)
            if let latest = versions.first { version = latest }
        } catch {
            DebugLog.shared.add("data", "Patch-Version nicht erreichbar, nutze \(version)", error: true)
        }

        let v = version
        let base = Self.cdragonBase
        func url(_ path: String) -> URL { URL(string: "\(base)/\(path)")! }

        async let summary = fetcher.decode([ChampionSummary].self, from: url("champion-summary.json"), cacheKey: "\(v)/champion-summary.json")
        async let itemList = fetcher.decode([Item].self, from: url("items.json"), cacheKey: "\(v)/items.json")
        async let perkList = fetcher.decode([Perk].self, from: url("perks.json"), cacheKey: "\(v)/perks.json")
        async let styles = fetcher.decode(PerkStylesFile.self, from: url("perkstyles.json"), cacheKey: "\(v)/perkstyles.json")
        async let spells = fetcher.decode([SummonerSpell].self, from: url("summoner-spells.json"), cacheKey: "\(v)/summoner-spells.json")
        async let dd = fetcher.decode(DDragonChampionFile.self,
                                      from: URL(string: "https://ddragon.leagueoflegends.com/cdn/\(v)/data/de_DE/champion.json")!,
                                      cacheKey: "\(v)/dd-champion.json")
        async let meraki = fetcher.decode(MerakiRatesFile.self,
                                          from: URL(string: "https://cdn.merakianalytics.com/riot/lol/resources/latest/en-US/championrates.json")!,
                                          cacheKey: "\(v)/meraki-championrates.json")
        async let arena = fetcher.decode(ArenaAugmentFile.self,
                                         from: URL(string: "https://raw.communitydragon.org/latest/cdragon/arena/de_de.json")!,
                                         cacheKey: "\(v)/arena-augments.json")

        do {
            let list = try await summary
            champions = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            aliasIndex = Dictionary(list.map { ($0.alias.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
            items = Dictionary(try await itemList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            perks = Dictionary(try await perkList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            perkStyles = Dictionary(try await styles.styles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            summonerSpells = Dictionary(try await spells.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            isLoaded = true
            loadError = nil
        } catch {
            loadError = "Spieldaten konnten nicht geladen werden: \(error.localizedDescription)"
            DebugLog.shared.add("data", loadError ?? "", error: true)
        }
        if let ddFile = try? await dd {
            ddChampions = Dictionary(ddFile.data.values.map { ($0.championId, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if let rates = try? await meraki { roleRates = rates.byChampion }
        if let arenaFile = try? await arena {
            augments = Dictionary(arenaFile.augments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
        DebugLog.shared.add("data", "Patch \(version): \(champions.count) Champions, \(items.count) Items geladen")
    }

    /// Skins are 6+ MB – loaded only when the collection view needs them.
    public func loadSkinsIfNeeded() async {
        guard skins.isEmpty else { return }
        let v = version
        do {
            let file = try await fetcher.decode([String: Skin].self, from: URL(string: "\(Self.cdragonBase)/skins.json")!,
                                                cacheKey: "\(v)/skins.json")
            skins = Dictionary(file.values.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let lines = try await fetcher.decode([SkinLine].self, from: URL(string: "\(Self.cdragonBase)/skinlines.json")!,
                                                 cacheKey: "\(v)/skinlines.json")
            skinLines = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            DebugLog.shared.add("data", "Skins nicht ladbar: \(error.localizedDescription)", error: true)
        }
    }

    public func detail(_ championId: Int) async -> ChampionDetail? {
        if let cached = details[championId] { return cached }
        let v = version
        guard let detail = try? await fetcher.decode(ChampionDetail.self,
                                                     from: URL(string: "\(Self.cdragonBase)/champions/\(championId).json")!,
                                                     cacheKey: "\(v)/champions/\(championId).json") else { return nil }
        details[championId] = detail
        return detail
    }

    public func cachedDetail(_ championId: Int) -> ChampionDetail? { details[championId] }

    // MARK: Lookups

    public func champion(_ id: Int) -> ChampionSummary? { champions[id] }
    public func championName(_ id: Int) -> String { champions[id]?.name ?? (id == 0 ? "–" : "#\(id)") }
    public func alias(_ id: Int) -> String { champions[id]?.alias ?? ddChampions[id]?.id ?? "Aatrox" }

    public func championId(alias: String) -> Int? {
        aliasIndex[alias.lowercased()] ?? champions.values.first { $0.name.lowercased() == alias.lowercased() }?.id
    }

    public func item(_ id: Int) -> Item? { items[id] }
    public func itemName(_ id: Int) -> String { items[id]?.name ?? "Item \(id)" }
    public func perk(_ id: Int) -> Perk? { perks[id] }
    public func spell(_ id: Int) -> SummonerSpell? { summonerSpells[id] }

    public func classTags(_ championId: Int) -> Set<String> { champions[championId]?.classTags ?? [] }

    /// Searches champions by German name or alias, ignoring case, accents, spaces and apostrophes
    /// ("kaisa" → Kai'Sa, "fate" → Twisted Fate). Prefix matches come first.
    public func searchChampions(_ query: String) -> [ChampionSummary] {
        let q = Self.searchKey(query)
        guard !q.isEmpty else { return [] }
        var prefix: [ChampionSummary] = [], word: [ChampionSummary] = [], other: [ChampionSummary] = []
        for champion in sortedChampions {
            let name = Self.searchKey(champion.name)
            if name.hasPrefix(q) || Self.searchKey(champion.alias).hasPrefix(q) { prefix.append(champion) }
            else if champion.name.split(whereSeparator: { $0 == " " || $0 == "'" || $0 == "." })
                        .contains(where: { Self.searchKey(String($0)).hasPrefix(q) }) { word.append(champion) }
            else if name.contains(q) { other.append(champion) }
        }
        return prefix + word + other
    }

    nonisolated static func searchKey(_ text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber })
    }
}
