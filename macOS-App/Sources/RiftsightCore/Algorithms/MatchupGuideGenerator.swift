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

        // 1) Trading & win condition
        var trading = "Trade, sobald \(enemy.name) \(enemyKey?.key ?? "?") (\(enemyKey?.name ?? "Key-Spell"), \(cd(enemyKey)) auf Rang 1) verbraucht hat – "
        trading += "dein \(myTrade?.key ?? "Q") (\(myTrade?.name ?? "Spell")) ist nach \(cd(myTrade)) wieder bereit."
        if let mine = input.myStats?.stats.attackrange, let theirs = input.enemyStats?.stats.attackrange {
            let diff = Int(mine - theirs)
            if diff >= 100 { trading += " Du hast \(diff) mehr Reichweite: Poke mit Autos, wenn er Minions lasthittet." }
            else if diff <= -100 { trading += " Er hat \(-diff) mehr Reichweite – nur in kurzen All-ins traden." }
        }
        if let delta = input.laneDelta {
            trading += delta >= 0.015 ? " Statistisch gewinnst du die Lane (\(delta.signedPercentString()))."
                : delta <= -0.015 ? " Statistisch verlierst du die Lane (\(delta.signedPercentString())) – spiel auf Skalierung."
                : " Ausgeglichenes Matchup."
        }

        // 2) Danger zone
        var danger = "Respektiere \(enemyKey?.name ?? "seinen Key-Spell") (\(enemyKey?.key ?? "?")): "
        danger += "\(cd(enemyKey)) Abklingzeit früh, \(cd(enemyKey, rank: 5)) maximiert."
        if let ult = enemyUlt {
            danger += " Ult \(ult.name): \(cd(ult)) / \(cd(ult, rank: 2)) / \(cd(ult, rank: 3)) – ab Level 6 Kill-Gefahr unter ~60 % Leben."
        }

        // 3) Wave management
        let iAmMelee = !(me.isRanged)
        let enemyRanged = enemy.isRanged
        let early = (input.myCurve?.early ?? 0.5) - (input.enemyCurve?.early ?? 0.5) + (input.laneDelta ?? 0)
        let wave: String
        if input.role == .jungle {
            wave = early >= 0 ? "Invade/Contest früh: Du bist in den ersten Clears stärker – spiegeln und Scuttle sichern."
                : "Gegenüberliegend farmen, Lanes mit Prio unterstützen und \(enemy.name) per Ward tracken."
        } else if input.role == .utility {
            wave = early >= 0 ? "Level-2-Spike erzwingen: Erste Welle schnell pushen und auf Engage gehen."
                : "Welle neutral halten, Bushes kontrollieren und \(enemy.name)s Engage-Cooldowns abwarten."
        } else if iAmMelee && enemyRanged {
            wave = "Freeze nah an deinem Turm: \(enemy.name) muss sich für Poke weit nach vorn stellen – dann bestrafen."
        } else if early > 0.01 {
            wave = "Fast-Push & Roam: Wellen schnell clearen, Plates holen und Mid/Jungle-Prio für Drachen nutzen."
        } else {
            wave = "Slow-Push vor Level 6 und Reset mit Welle im Turm – kein Freeze-Kampf gegen frühe Stärke."
        }

        // 4) Power spikes
        var spikes = "Deine Spikes: Level 2/3 (\(me.spells.prefix(3).map(\.key).joined(separator: "/"))), Level 6 (R)"
        if let item = input.myCoreItem { spikes += " und erstes Item \(item)" }
        spikes += ". \(enemy.name)"
        if let item = input.enemyCoreItem { spikes += " spiket mit \(item)" } else { spikes += " spiket mit Level 6" }
        if let curve = input.enemyCurve, curve.late > curve.early + 0.02 { spikes += " und skaliert stärker ins Late Game – beende früh." }
        else { spikes += "." }

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
                                .init(title: "Trading & Win-Condition", text: trading),
                                .init(title: "Gefahrenzone / Key-Spell", text: danger),
                                .init(title: "Wave-Management", text: wave),
                                .init(title: "Power-Spikes", text: spikes),
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
