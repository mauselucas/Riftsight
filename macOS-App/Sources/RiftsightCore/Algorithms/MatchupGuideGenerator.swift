import Foundation

/// Builds the German 4-point matchup guide (Trading, Gefahrenzone, Wave-Management, Power-Spikes)
/// from CommunityDragon cooldowns, Data Dragon base stats and the pipeline builds.
public enum MatchupGuideGenerator {
    public struct Input: Sendable {
        public var me: ChampionDetail
        public var enemy: ChampionDetail
        public var myStats: DDragonChampion?
        public var enemyStats: DDragonChampion?
        public var role: Role?
        public var patch: String
        public var laneDelta: Double?
        public var myCurve: PowerCurve?
        public var enemyCurve: PowerCurve?
        public var myCoreItem: String?
        public var enemyCoreItem: String?

        public init(me: ChampionDetail, enemy: ChampionDetail, myStats: DDragonChampion?, enemyStats: DDragonChampion?,
                    role: Role?, patch: String, laneDelta: Double?, myCurve: PowerCurve?, enemyCurve: PowerCurve?,
                    myCoreItem: String?, enemyCoreItem: String?) {
            self.me = me
            self.enemy = enemy
            self.myStats = myStats
            self.enemyStats = enemyStats
            self.role = role
            self.patch = patch
            self.laneDelta = laneDelta
            self.myCurve = myCurve
            self.enemyCurve = enemyCurve
            self.myCoreItem = myCoreItem
            self.enemyCoreItem = enemyCoreItem
        }
    }

    static func cd(_ spell: ChampionDetail.Spell?, rank: Int = 1) -> String {
        guard let value = spell?.cooldown(rank: rank) else { return "?" }
        return value == value.rounded() ? "\(Int(value)) s" : String(format: "%.1f s", locale: .riftsight, value)
    }

    /// The enemy's most punishing basic ability: the one with the longest rank-1 cooldown.
    static func keySpell(_ detail: ChampionDetail) -> ChampionDetail.Spell? {
        detail.spells.filter { $0.key != "R" }.max { ($0.cooldown(rank: 1) ?? 0) < ($1.cooldown(rank: 1) ?? 0) }
    }

    /// My best short-cooldown trading tool.
    static func tradeSpell(_ detail: ChampionDetail) -> ChampionDetail.Spell? {
        detail.spells.filter { $0.key != "R" }.min { ($0.cooldown(rank: 1) ?? 99) < ($1.cooldown(rank: 1) ?? 99) }
    }

    public static func generate(_ input: Input) -> MatchupGuide {
        let me = input.me, enemy = input.enemy
        let enemyKey = keySpell(enemy)
        let myTrade = tradeSpell(me)
        let enemyUlt = enemy.spell("R")
        let keyLabel = "\(enemyKey?.key ?? "?") (\(enemyKey?.name ?? "Key-Spell"))"

        // 1) Trading – one clear rule plus range advantage.
        var trading = "Greif an, wenn sein \(keyLabel) weg ist – \(cd(enemyKey)) Cooldown."
        if let mine = input.myStats?.stats.attackrange, let theirs = input.enemyStats?.stats.attackrange {
            let diff = Int(mine - theirs)
            if diff >= 100 { trading += " Du hast mehr Reichweite: poke ihn beim Farmen." }
            else if diff <= -100 { trading += " Er hat mehr Reichweite: nur kurze All-ins." }
            else if let myTrade { trading += " Dein \(myTrade.key) ist nach \(cd(myTrade)) wieder da." }
        } else if let myTrade {
            trading += " Dein \(myTrade.key) ist nach \(cd(myTrade)) wieder da."
        }

        // 2) Danger – what to respect.
        var danger = "Weich seinem \(keyLabel) aus."
        if let ult = enemyUlt {
            danger += " Ab Level 6 (\(ult.name)): unter 60 % Leben nicht nach vorn."
        }

        // 3) Wave – one instruction.
        let iAmMelee = !(me.isRanged)
        let early = (input.myCurve?.early ?? 0.5) - (input.enemyCurve?.early ?? 0.5) + (input.laneDelta ?? 0)
        let wave: String
        if input.role == .jungle {
            wave = early >= 0 ? "Du bist früh stärker: Scuttle holen und seinen Jungle invaden."
                : "Er ist früh stärker: auf der anderen Seite farmen und Lanes mit Prio helfen."
        } else if input.role == .utility {
            wave = early >= 0 ? "Erste Welle schnell pushen und auf Level 2 angreifen."
                : "Welle ruhig halten, Büsche kontrollieren, seinen Engage abwarten."
        } else if iAmMelee && enemy.isRanged {
            wave = "Welle nah an deinem Turm halten – er muss für Poke nach vorn kommen."
        } else if early > 0.01 {
            wave = "Schnell pushen, Plates holen und roamen."
        } else {
            wave = "Vor Level 6 langsam pushen und mit der Welle im Turm zurückgehen."
        }

        // 4) Power spikes – who is strong when.
        var spikes = "Du: Level 6" + (input.myCoreItem.map { " + \($0)" } ?? "") + "."
        spikes += " Er: " + (input.enemyCoreItem ?? "Level 6") + "."
        if let curve = input.enemyCurve, curve.late > curve.early + 0.02 { spikes += " Er skaliert besser – spiel aufs frühe Spiel." }
        else if let delta = input.laneDelta, delta <= -0.015 { spikes += " Lane ist schwer – sicher farmen, später gewinnen." }

        let difficulty: String
        switch input.laneDelta ?? 0 {
        case ..<(-0.025): difficulty = "Schwer"
        case ..<(-0.008): difficulty = "Eher schwer"
        case ..<0.008: difficulty = "Ausgeglichen"
        case ..<0.025: difficulty = "Eher leicht"
        default: difficulty = "Leicht"
        }

        return MatchupGuide(myChampionId: me.id, enemyChampionId: enemy.id, role: input.role, patch: input.patch,
                            difficulty: difficulty, points: [
                                .init(title: "Traden", text: trading),
                                .init(title: "Aufpassen", text: danger),
                                .init(title: "Welle", text: wave),
                                .init(title: "Stark wann", text: spikes),
                            ])
    }
}

/// Live in-game win probability (model estimate) from gold, objectives and draft prior.
public enum LiveWinProbability {
    public static func blue(goldDiff: Int, gameTime: Double, blue: TeamObjectives, red: TeamObjectives,
                            draftPrior: Double = 0.5) -> Double {
        let minutes = max(1, gameTime / 60)
        let goldTerm = Double(goldDiff) / (1000 + 120 * minutes) * 0.9
        let towerTerm = Double(blue.towers - red.towers) * 0.12 + Double(blue.inhibitors - red.inhibitors) * 0.35
        let dragonTerm = Double(blue.dragons - red.dragons) * 0.12
            + (blue.dragons >= 4 ? 0.5 : 0) - (red.dragons >= 4 ? 0.5 : 0)
        let elderTerm = (blue.hasElder ? 0.6 : 0) - (red.hasElder ? 0.6 : 0)
        let baronTerm = (blue.baronBuffUntil > gameTime ? 0.55 : 0) - (red.baronBuffUntil > gameTime ? 0.55 : 0)
        let grubTerm = Double(blue.grubs - red.grubs) * 0.04
        let killTerm = Double(blue.kills - red.kills) * 0.02
        let prior = log(draftPrior / (1 - draftPrior)) * max(0.2, 1 - minutes / 25)
        let logit = goldTerm + towerTerm + dragonTerm + elderTerm + baronTerm + grubTerm + killTerm + prior
        return min(0.97, max(0.03, 1 / (1 + exp(-logit))))
    }
}
