import Foundation

/// Everything the draft engine needs to know about one champion.
public struct ChampionTraits: Sendable, Hashable {
    public var championId: Int
    public var winrate: Double
    public var powerCurve: PowerCurve
    public var damageType: String
    public var damage: Int
    public var durability: Int
    public var crowdControl: Int
    public var classTags: Set<String>

    public init(championId: Int, winrate: Double = 0.5, powerCurve: PowerCurve? = nil, damageType: String = "kMixed",
                damage: Int = 2, durability: Int = 2, crowdControl: Int = 1, classTags: Set<String> = []) {
        self.championId = championId
        self.winrate = winrate
        self.damageType = damageType
        self.damage = damage
        self.durability = durability
        self.crowdControl = crowdControl
        self.classTags = classTags
        self.powerCurve = powerCurve ?? Self.defaultCurve(for: classTags)
    }

    /// A neutral stand-in used to measure a single pick's contribution.
    public static func average(championId: Int = 0) -> ChampionTraits {
        ChampionTraits(championId: championId, winrate: 0.5, powerCurve: PowerCurve(early: 0.5, mid: 0.5, late: 0.5))
    }

    public static func defaultCurve(for tags: Set<String>) -> PowerCurve {
        if tags.contains("marksman") { return PowerCurve(early: 0.47, mid: 0.50, late: 0.54) }
        if tags.contains("assassin") { return PowerCurve(early: 0.53, mid: 0.51, late: 0.47) }
        if tags.contains("fighter") { return PowerCurve(early: 0.52, mid: 0.51, late: 0.48) }
        if tags.contains("tank") { return PowerCurve(early: 0.49, mid: 0.51, late: 0.51) }
        if tags.contains("mage") { return PowerCurve(early: 0.49, mid: 0.51, late: 0.52) }
        return PowerCurve(early: 0.50, mid: 0.50, late: 0.50)
    }

    public var isTank: Bool { classTags.contains("tank") || durability >= 3 }
    public var magicWeight: Double {
        switch damageType {
        case "kMagic": 1
        case "kMixed": 0.5
        default: 0
        }
    }
}

public struct DraftSlot: Sendable, Hashable {
    public var traits: ChampionTraits
    public var role: Role?

    public init(traits: ChampionTraits, role: Role?) {
        self.traits = traits
        self.role = role
    }
}

/// Six-axis radar (0…1): Early, Mid, Late, Damage Dealt, Damage Taken, Synergy.
public struct RadarValues: Sendable, Hashable {
    public var early: Double
    public var mid: Double
    public var late: Double
    public var damageDealt: Double
    public var damageTaken: Double
    public var synergy: Double

    public var axes: [Double] { [early, mid, late, damageDealt, damageTaken, synergy] }
    public static let axisLabels = ["EARLY", "MID", "LATE", "DAMAGE DEALT", "DAMAGE TAKEN", "SYNERGY"]
    public static let zero = RadarValues(early: 0, mid: 0, late: 0, damageDealt: 0, damageTaken: 0, synergy: 0)
}

public struct DraftAnalysis: Sendable, Hashable {
    public var blueWinProbability: Double
    public var blueRadar: RadarValues
    public var redRadar: RadarValues
    /// championId → contribution of that pick in win-probability points (e.g. +1.82).
    public var pickDeltas: [Int: Double]
    public var notes: [String]
}

public struct PickSuggestion: Sendable, Hashable, Identifiable {
    public var championId: Int
    public var delta: Double
    public var counterPart: Double
    public var synergyPart: Double
    public var masteryPoints: Int
    public var id: Int { championId }
}

/// Live draft scoring: team win probability, radar and per-pick deltas.
public struct DraftWinProbabilityEngine: Sendable {
    /// (champion, enemy, role) → lane win-rate delta for `champion` (positive = good).
    public typealias MatchupLookup = @Sendable (Int, Int, Role) -> Double?
    let matchup: MatchupLookup

    public init(matchup: @escaping MatchupLookup) {
        self.matchup = matchup
    }

    public func analyze(blue: [DraftSlot], red: [DraftSlot]) -> DraftAnalysis {
        let p = probability(blue: blue, red: red)
        var deltas: [Int: Double] = [:]
        for (index, slot) in blue.enumerated() where slot.traits.championId > 0 {
            var replaced = blue
            replaced[index].traits = .average()
            deltas[slot.traits.championId] = (p - probability(blue: replaced, red: red)) * 100
        }
        for (index, slot) in red.enumerated() where slot.traits.championId > 0 {
            var replaced = red
            replaced[index].traits = .average()
            deltas[slot.traits.championId] = ((1 - p) - (1 - probability(blue: blue, red: replaced))) * 100
        }
        return DraftAnalysis(blueWinProbability: p, blueRadar: radar(blue), redRadar: radar(red),
                             pickDeltas: deltas, notes: notes(blue: blue, red: red))
    }

    public func probability(blue: [DraftSlot], red: [DraftSlot]) -> Double {
        let picked = { (team: [DraftSlot]) in team.filter { $0.traits.championId > 0 } }
        let b = picked(blue), r = picked(red)
        guard !b.isEmpty || !r.isEmpty else { return 0.5 }

        let base = { (team: [DraftSlot]) -> Double in
            team.isEmpty ? 0 : team.map { $0.traits.winrate - 0.5 }.reduce(0, +)
        }
        var lane = 0.0
        for role in Role.allCases {
            guard let mine = b.first(where: { $0.role == role }), let theirs = r.first(where: { $0.role == role }) else { continue }
            lane += matchup(mine.traits.championId, theirs.traits.championId, role) ?? 0
        }
        let synergyDiff = synergy(b) - synergy(r)
        let logit = 2.5 * (base(b) - base(r)) + 3.0 * lane + 0.55 * synergyDiff
        return min(0.75, max(0.25, 1 / (1 + exp(-logit))))
    }

    /// 0…1: damage-type balance, frontline and crowd control.
    public func synergy(_ team: [DraftSlot]) -> Double {
        let picked = team.filter { $0.traits.championId > 0 }
        guard !picked.isEmpty else { return 0 }
        let magic = picked.map(\.traits.magicWeight).reduce(0, +) / Double(picked.count)
        let balance = 1 - min(1, abs(magic - 0.5) * 2)
        let frontline = min(1, Double(picked.filter(\.traits.isTank).count) / 1.5)
        let cc = min(1, Double(picked.map(\.traits.crowdControl).reduce(0, +)) / 9)
        let completeness = Double(picked.count) / 5
        return (0.4 * balance + 0.3 * frontline + 0.3 * cc) * (0.6 + 0.4 * completeness)
    }

    public func radar(_ team: [DraftSlot]) -> RadarValues {
        let picked = team.filter { $0.traits.championId > 0 }
        guard !picked.isEmpty else { return .zero }
        func norm(_ value: Double) -> Double { min(1, max(0.05, (value - 0.44) / 0.12)) }
        let count = Double(picked.count)
        return RadarValues(
            early: norm(picked.map(\.traits.powerCurve.early).reduce(0, +) / count),
            mid: norm(picked.map(\.traits.powerCurve.mid).reduce(0, +) / count),
            late: norm(picked.map(\.traits.powerCurve.late).reduce(0, +) / count),
            damageDealt: min(1, picked.map { Double($0.traits.damage) }.reduce(0, +) / 15),
            damageTaken: min(1, picked.map { Double($0.traits.durability) }.reduce(0, +) / 15),
            synergy: synergy(team)
        )
    }

    func notes(blue: [DraftSlot], red: [DraftSlot]) -> [String] {
        var notes: [String] = []
        for (name, team) in [("Blau", blue), ("Rot", red)] {
            let picked = team.filter { $0.traits.championId > 0 }
            guard picked.count >= 3 else { continue }
            let magic = picked.map(\.traits.magicWeight).reduce(0, +) / Double(picked.count)
            if magic < 0.2 { notes.append("\(name): fast nur AD-Schaden – Rüstung wird für Gegner effizient.") }
            if magic > 0.8 { notes.append("\(name): fast nur AP-Schaden – Magieresistenz wird für Gegner effizient.") }
            if !picked.contains(where: \.traits.isTank) && picked.count >= 4 { notes.append("\(name): keine Frontline.") }
        }
        return notes
    }

    /// Ranks candidate picks for the local player's role by their effect on win probability.
    public func suggestions(candidates: [ChampionTraits], role: Role, myTeam: [DraftSlot], myIndex: Int,
                            enemyTeam: [DraftSlot], myTeamIsBlue: Bool, mastery: [Int: Int], limit: Int = 5) -> [PickSuggestion] {
        let taken = Set((myTeam + enemyTeam).map(\.traits.championId))
        let laneEnemy = enemyTeam.first { $0.role == role && $0.traits.championId > 0 }
        var baselineTeam = myTeam
        guard baselineTeam.indices.contains(myIndex) else { return [] }
        baselineTeam[myIndex] = DraftSlot(traits: .average(), role: role)
        let baseline = winProbability(team: baselineTeam, enemy: enemyTeam, blue: myTeamIsBlue)
        let baseSynergy = synergy(baselineTeam)

        let ranked = candidates.filter { !taken.contains($0.championId) }.map { candidate -> PickSuggestion in
            var team = myTeam
            team[myIndex] = DraftSlot(traits: candidate, role: role)
            let p = winProbability(team: team, enemy: enemyTeam, blue: myTeamIsBlue)
            let counter = laneEnemy.flatMap { matchup(candidate.championId, $0.traits.championId, role) } ?? 0
            return PickSuggestion(championId: candidate.championId, delta: (p - baseline) * 100,
                                  counterPart: counter * 100, synergyPart: (synergy(team) - baseSynergy) * 10,
                                  masteryPoints: mastery[candidate.championId] ?? 0)
        }
        return Array(ranked.sorted { $0.delta > $1.delta }.prefix(limit))
    }

    func winProbability(team: [DraftSlot], enemy: [DraftSlot], blue: Bool) -> Double {
        blue ? probability(blue: team, red: enemy) : 1 - probability(blue: enemy, red: team)
    }
}
