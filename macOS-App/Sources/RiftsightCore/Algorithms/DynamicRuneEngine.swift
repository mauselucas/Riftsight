import Foundation

public enum RuneMode: String, CaseIterable, Sendable, Identifiable {
    case lane, team
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lane: "1v1 Lane"
        case .team: "5v5 Team-Comp"
        }
    }
}

public struct RuneBadge: Sendable, Hashable, Identifiable {
    public let title: String
    public let detail: String
    public var id: String { title }
}

public struct RuneRecommendation: Sendable, Hashable {
    public var page: RunePageStat
    public var badges: [RuneBadge]
    public var source: String
}

/// Summary of an opposing champion for rune decisions.
public struct OpponentTraits: Sendable, Hashable {
    public var name: String
    public var damageType: String
    public var isRanged: Bool
    public var hardCC: Bool
    public var isTank: Bool
    public var isHealer: Bool
    public var classTags: Set<String>

    public init(name: String, damageType: String, isRanged: Bool, hardCC: Bool, isTank: Bool, isHealer: Bool, classTags: Set<String>) {
        self.name = name
        self.damageType = damageType
        self.isRanged = isRanged
        self.hardCC = hardCC
        self.isTank = isTank
        self.isHealer = isHealer
        self.classTags = classTags
    }
}

/// Adapts the popular rune page to the lane opponent (mode A) or the whole enemy comp (mode B).
public enum DynamicRuneEngine {
    // Rune ids (perkstyles.json, patch 16.x)
    static let cutDown = 8017, coupDeGrace = 8014, lastStand = 8299
    static let secondWind = 8444, bonePlating = 8473, conditioning = 8429, demolish = 8446, fontOfLife = 8463
    static let unflinching = 8242, overgrowth = 8451, revitalize = 8453
    static let shardHealth = 5011, shardTenacity = 5013, shardHealthScaling = 5001
    static let shardAdaptive = 5008, shardMoveSpeed = 5010

    public static func recommend(base: RunePageStat, matchupPage: RunePageStat?, mode: RuneMode, me: OpponentTraits?,
                                 laneOpponent: OpponentTraits?, enemyTeam: [OpponentTraits],
                                 styles: [Int: PerkStyle]) -> RuneRecommendation {
        var page = base
        var badges: [RuneBadge] = []
        var source = "Beliebteste Seite"

        switch mode {
        case .lane:
            if let matchupPage, let opponent = laneOpponent {
                page = matchupPage
                source = "Matchup-Seite vs. \(opponent.name)"
            }
            guard let opponent = laneOpponent else { break }
            let iAmMelee = !(me?.isRanged ?? true)
            if opponent.isRanged && iAmMelee,
               replace(&page, candidates: [conditioning, demolish, fontOfLife, secondWind, bonePlating], with: secondWind, styles: styles) {
                badges.append(RuneBadge(title: "Ranged-Gegner → Zweiter Atem",
                                        detail: "\(opponent.name) pokt dich auf Distanz – Zweiter Atem gleicht den Lane-Schaden aus."))
            } else if opponent.classTags.contains("assassin") || (opponent.damageType == "kPhysical" && !opponent.isRanged),
                      replace(&page, candidates: [secondWind, conditioning, demolish, fontOfLife], with: bonePlating, styles: styles) {
                badges.append(RuneBadge(title: "Burst-Gegner → Knochenpanzer",
                                        detail: "\(opponent.name) lebt von kurzen Trades – Knochenpanzer halbiert die Combo-Folgetreffer."))
            }
            if opponent.hardCC {
                if setShard(&page, row: 2, to: shardTenacity) {
                    badges.append(RuneBadge(title: "Hard-CC in Lane → Zähigkeits-Shard",
                                            detail: "\(opponent.name) hat verlässliches Hard-CC."))
                }
            }

        case .team:
            let cc = enemyTeam.filter(\.hardCC).count
            let tanks = enemyTeam.filter(\.isTank).count
            let magic = enemyTeam.filter { $0.damageType == "kMagic" }.count
            let physical = enemyTeam.filter { $0.damageType == "kPhysical" }.count
            let healers = enemyTeam.filter(\.isHealer).count

            if cc >= 3 {
                if setShard(&page, row: 2, to: shardTenacity) {
                    badges.append(RuneBadge(title: "\(cc)× Hard-CC → Zähigkeit",
                                            detail: "Gegner-Comp hat \(cc) Champions mit verlässlichem CC. Defensiv-Shard auf Zähigkeit & Verlangsamungsresistenz."))
                }
                if replace(&page, candidates: [overgrowth, revitalize], with: unflinching, styles: styles) {
                    badges.append(RuneBadge(title: "CC-lastig → Unerschütterlich", detail: "Mehr Zähigkeit nach Beschwörerzaubern."))
                }
            }
            if tanks >= 2, replace(&page, candidates: [coupDeGrace, lastStand], with: cutDown, styles: styles) {
                badges.append(RuneBadge(title: "\(tanks) Tanks → Niedermäher",
                                        detail: "Bonusschaden gegen Ziele mit mehr maximalem Leben."))
            }
            if physical >= 4 || magic >= 4 {
                let type = physical >= 4 ? "AD" : "AP"
                if setShard(&page, row: 1, to: shardHealthScaling) {
                    badges.append(RuneBadge(title: "\(max(physical, magic))× \(type) → Stat-Shards angepasst",
                                            detail: "Einseitiger Schaden: Flex-Shard auf skalierendes Leben, Itemize gezielt \(type == "AD" ? "Rüstung" : "Magieresistenz")."))
                }
            }
            if healers >= 2 {
                badges.append(RuneBadge(title: "\(healers) Heiler → Anti-Heal einplanen",
                                        detail: "Keine Rune nötig – früh ein Anti-Heal-Bauteil kaufen (siehe Items)."))
            }
        }
        return RuneRecommendation(page: page, badges: badges, source: source)
    }

    /// Replaces one of `candidates` inside the page by `perk`, only if `perk` lives in the same rune slot.
    @discardableResult
    static func replace(_ page: inout RunePageStat, candidates: [Int], with perk: Int, styles: [Int: PerkStyle]) -> Bool {
        guard !page.perkIds.contains(perk) else { return false }
        let allSlots = styles.values.flatMap(\.slots)
        for (index, current) in page.perkIds.enumerated().prefix(6) where candidates.contains(current) {
            if allSlots.contains(where: { $0.perks.contains(current) && $0.perks.contains(perk) }) {
                page.perkIds[index] = perk
                return true
            }
        }
        return false
    }

    /// Stat shards occupy indices 6–8 (offense, flex, defense).
    @discardableResult
    static func setShard(_ page: inout RunePageStat, row: Int, to shard: Int) -> Bool {
        let index = 6 + row
        guard page.perkIds.indices.contains(index), page.perkIds[index] != shard else { return false }
        page.perkIds[index] = shard
        return true
    }
}
