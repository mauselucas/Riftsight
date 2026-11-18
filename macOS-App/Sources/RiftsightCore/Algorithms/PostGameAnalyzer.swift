import Foundation

public struct PlayerScore: Sendable, Hashable {
    public let participantId: Int
    public let score: Int
    public let placement: Int
    public let badge: String
    public let killParticipation: Double
    public let damageShare: Double

    public var isMVP: Bool { badge == "MVP" }
    public var isACE: Bool { badge == "ACE" }
}

/// Performance scores (0–100), placements 1st–10th with MVP/ACE and the German 3-line summary.
public enum PostGameAnalyzer {
    public static func scores(for match: MatchRecord) -> [Int: PlayerScore] {
        let players = match.participants
        guard !players.isEmpty else { return [:] }
        let minutes = match.durationMinutes

        func teamKills(_ teamId: Int) -> Int { match.players(team: teamId).reduce(0) { $0 + $1.kills } }
        func teamDamage(_ teamId: Int) -> Int { match.players(team: teamId).reduce(0) { $0 + $1.damageToChampions } }
        func teamGold(_ teamId: Int) -> Int { match.players(team: teamId).reduce(0) { $0 + $1.gold } }

        struct Raw { let id: Int; let team: Int; let win: Bool; let value: Double; let kp: Double; let share: Double }
        var raws: [Raw] = []
        let maxVision = Double(players.map(\.visionScore).max() ?? 1)
        let maxObjective = Double(players.map(\.objectiveDamage).max() ?? 1)
        for p in players {
            let kp = Double(p.kills + p.assists) / Double(max(1, teamKills(p.teamId)))
            let share = Double(p.damageToChampions) / Double(max(1, teamDamage(p.teamId)))
            let goldShare = Double(p.gold) / Double(max(1, teamGold(p.teamId)))
            let kda = min(10, p.kda) / 10
            let csPerMin = Double(p.cs) / minutes
            let farm = p.role == .utility ? 0.6 : min(1, csPerMin / 9)
            let vision = maxVision > 0 ? Double(p.visionScore) / maxVision : 0
            let objective = maxObjective > 0 ? Double(p.objectiveDamage) / maxObjective : 0
            let supportBonus = p.role == .utility ? 0.1 * vision : 0
            let value = 0.26 * min(1, kp / 0.75) + 0.2 * min(1, share / 0.35) + 0.18 * kda + 0.1 * min(1, goldShare / 0.25)
                + 0.08 * vision + 0.08 * farm + 0.05 * objective + (p.win ? 0.05 : 0) + supportBonus
            raws.append(Raw(id: p.participantId, team: p.teamId, win: p.win, value: value, kp: kp, share: share))
        }

        let ordered = raws.sorted { $0.value > $1.value }
        let mvp = ordered.first { $0.win }?.id
        let ace = ordered.first { !$0.win }?.id
        var result: [Int: PlayerScore] = [:]
        for (index, raw) in ordered.enumerated() {
            let placement = index + 1
            let badge = raw.id == mvp ? "MVP" : raw.id == ace ? "ACE" : ordinal(placement)
            let score = Int((min(1.05, raw.value) * 95).rounded())
            result[raw.id] = PlayerScore(participantId: raw.id, score: max(5, min(100, score)), placement: placement,
                                         badge: badge, killParticipation: raw.kp, damageShare: raw.share)
        }
        return result
    }

    /// German ordinal for placements ("1.", "2.", …).
    public static func ordinal(_ n: Int) -> String { "\(n)." }

    /// Three short German lines: CS@10, early deaths (< 14 min), missing situational items.
    public static func summary(match: MatchRecord, player: ParticipantRecord, timeline: ParticipantTimeline?,
                               enemyThreats: ThreatProfile, playerIsMagic: Bool) -> [String] {
        var lines: [String] = []

        // 1) CS @ 10
        if player.role == .utility {
            let perMin = Double(player.visionScore) / match.durationMinutes
            lines.append(perMin >= 2
                ? String(format: "Vision stark: %.1f Vision Score pro Minute.", locale: .riftsight, perMin)
                : String(format: "Vision ausbaufähig: %.1f/Min. – mehr Kontrollwards und Trinket-Swap.", locale: .riftsight, perMin))
        } else if let cs10 = timeline?.csAtMinute[10] {
            let target = player.role == .jungle ? 60 : 75
            let verdict = cs10 >= target ? "stark" : cs10 >= target - 15 ? "solide" : "zu niedrig"
            lines.append("CS@10: \(cs10) (\(verdict), Ziel ≥ \(target)).")
        } else {
            let perMin = Double(player.cs) / match.durationMinutes
            lines.append(String(format: "CS/Min.: %.1f %@", locale: .riftsight, perMin, perMin >= 7 ? "– gutes Farming." : "– Farming verbessern (Ziel ≥ 7)."))
        }

        // 2) Early deaths
        if let deaths = timeline?.deathTimes.filter({ $0 < 14 * 60 }) {
            lines.append(deaths.isEmpty
                ? "Keine Tode vor Minute 14 – sauberes Early Game."
                : "\(deaths.count) \(deaths.count == 1 ? "Tod" : "Tode") vor Minute 14 – Lane-Phase sicherer spielen.")
        } else {
            lines.append(player.deaths <= 4 ? "Nur \(player.deaths) Tode im ganzen Spiel." : "\(player.deaths) Tode – vor allem frühe Tode vermeiden.")
        }

        // 3) Situational items
        let owned = Set(player.items)
        var missing: [String] = []
        let antiHeal: Set<Int> = [3123, 3033, 6609, 3916, 3165, 3076, 3075]
        if enemyThreats.heavyHealing && owned.isDisjoint(with: antiHeal) {
            missing.append("Anti-Heal (\(enemyThreats.healingSources.prefix(2).joined(separator: ", ")))")
        }
        let shred: Set<Int> = [3036, 3071, 6694, 3033, 3135, 3137, 6653]
        if enemyThreats.tanks >= 2 && owned.isDisjoint(with: shred) && player.role != .utility {
            missing.append(playerIsMagic ? "Magiedurchdringung gegen \(enemyThreats.tanks) Tanks" : "Rüstungsdurchdringung gegen \(enemyThreats.tanks) Tanks")
        }
        lines.append(missing.isEmpty
            ? "Itemization passte zur Gegner-Comp."
            : "Gefehlt hat: " + missing.joined(separator: " · ") + ".")
        return lines
    }
}

/// Pre-game behaviour badges from a player's recent match history (loading screen scout).
public struct PlayerBadge: Sendable, Hashable, Identifiable {
    public enum Tone: Sendable { case positive, negative, neutral, warning }
    public let title: String
    public let detail: String
    public let tone: Tone
    public var id: String { title }

    public init(title: String, detail: String, tone: Tone) {
        self.title = title
        self.detail = detail
        self.tone = tone
    }
}

public enum BehaviorBadges {
    public static func badges(history: [MatchRecord], puuid: String?, currentChampionId: Int, role: Role?,
                              earlyTakedownsPerGame: Double? = nil, championName: (Int) -> String) -> [PlayerBadge] {
        let own = history.compactMap { match -> ParticipantRecord? in
            match.participants.first { $0.puuid == puuid } ?? match.local
        }
        guard !own.isEmpty else { return [] }
        var badges: [PlayerBadge] = []

        let counts = Dictionary(grouping: own, by: \.championId).mapValues(\.count)
        if let (top, games) = counts.max(by: { $0.value < $1.value }), own.count >= 8,
           Double(games) / Double(own.count) >= 0.7 {
            badges.append(PlayerBadge(title: "OTP", detail: "\(games) von \(own.count) Spielen auf \(championName(top))", tone: .neutral))
        }
        if currentChampionId > 0 && own.count >= 8 && counts[currentChampionId] == nil {
            badges.append(PlayerBadge(title: "First Time", detail: "\(championName(currentChampionId)) nicht in den letzten \(own.count) Spielen", tone: .positive))
        }
        if let onChamp = counts[currentChampionId], onChamp >= 5 {
            let wins = own.filter { $0.championId == currentChampionId && $0.win }.count
            if Double(wins) / Double(onChamp) >= 0.65 {
                badges.append(PlayerBadge(title: "Main", detail: "\(wins)/\(onChamp) Siege auf \(championName(currentChampionId))", tone: .negative))
            }
        }
        if role == .jungle, let early = earlyTakedownsPerGame, early >= 0.6 {
            badges.append(PlayerBadge(title: "Früher Ganker", detail: String(format: "Ø %.1f Takedowns vor Minute 4", locale: .riftsight, early), tone: .negative))
        }
        let streak = own.prefix { !$0.win }.count
        if streak >= 3 {
            badges.append(PlayerBadge(title: "Loss-Streak", detail: "\(streak) Niederlagen in Folge", tone: .positive))
        }
        let winStreak = own.prefix { $0.win }.count
        if winStreak >= 4 {
            badges.append(PlayerBadge(title: "Win-Streak", detail: "\(winStreak) Siege in Folge", tone: .negative))
        }
        return badges
    }
}
