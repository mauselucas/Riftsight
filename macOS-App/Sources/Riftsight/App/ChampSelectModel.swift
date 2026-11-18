import RiftsightCore
import SwiftUI

/// One seat in the draft (independent of LCU vs. demo source).
struct DraftMember: Identifiable, Hashable {
    var cellId: Int
    var championId: Int
    var assignedRole: Role?
    var spell1: Int
    var spell2: Int
    var name: String
    var isLocal = false
    var isAlly: Bool
    var isHovering = false
    var id: Int { cellId }
    var hasSmite: Bool { spell1 == 11 || spell2 == 11 }
}

struct DraftState: Hashable {
    var allies: [DraftMember]
    var enemies: [DraftMember]
    var allyBans: [Int]
    var enemyBans: [Int]
    var isBlueSide: Bool
    var localPickActionId: Int?
    var phase: String
    var secondsLeft: Double?

    init(allies: [DraftMember], enemies: [DraftMember], allyBans: [Int], enemyBans: [Int], isBlueSide: Bool,
         localPickActionId: Int?, phase: String, secondsLeft: Double?) {
        self.allies = allies
        self.enemies = enemies
        self.allyBans = allyBans
        self.enemyBans = enemyBans
        self.isBlueSide = isBlueSide
        self.localPickActionId = localPickActionId
        self.phase = phase
        self.secondsLeft = secondsLeft
    }

    init(session: ChampSelectSession, championNames: (Int) -> String) {
        func member(_ m: ChampSelectSession.Member, ally: Bool) -> DraftMember {
            DraftMember(cellId: m.cellId, championId: m.displayChampionId, assignedRole: m.role,
                        spell1: m.spell1Id ?? 0, spell2: m.spell2Id ?? 0,
                        name: m.gameName.map { $0.isEmpty ? championNames(m.displayChampionId) : $0 } ?? championNames(m.displayChampionId),
                        isLocal: m.cellId == session.localPlayerCellId, isAlly: ally,
                        isHovering: m.championId == 0 && (m.championPickIntent ?? 0) > 0)
        }
        allies = session.myTeam.map { member($0, ally: true) }
        enemies = session.theirTeam.map { member($0, ally: false) }
        let bans = session.completedBanIds
        allyBans = bans.mine
        enemyBans = bans.theirs
        isBlueSide = session.isLocalBlueSide
        localPickActionId = session.localPickAction?.id
        phase = session.timer?.phase ?? ""
        secondsLeft = session.timer?.adjustedTimeLeftInPhase.map { $0 / 1000 }
    }
}

/// Everything the Champ Select screen shows, derived from the draft + static data.
@MainActor
@Observable
final class ChampSelectModel {
    var demoDraft: DraftState?
    /// Manual lane overrides for enemies (`isRoleLockedByUser`), keyed by cellId.
    var lockedRoles: [Int: Role] = [:]
    var runeMode: RuneMode = .lane
    var selectedArchetype: String?
    var showCounterDrawer = false
    var actionMessage: String?

    private unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var draft: DraftState? {
        if let session = app.lcu.champSelect ?? app.lcu.lastChampSelect {
            return DraftState(session: session, championNames: app.gameData.championName)
        }
        return app.showsDemo ? demoDraft : nil
    }

    var isLive: Bool { app.lcu.champSelect != nil }

    // MARK: Lanes

    /// Enemy roles from the Hungarian assignment (smite → jungle), honouring manual locks.
    var enemyRoles: [Int: Role] {
        guard let draft else { return [:] }
        let picked = draft.enemies.enumerated().filter { $0.element.championId > 0 }
        let assigner = LaneAssigner(rates: app.gameData.roleRates)
        let enemies = picked.map { LaneAssigner.Enemy(slot: $0.offset, championId: $0.element.championId, hasSmite: $0.element.hasSmite) }
        var locked: [Int: Role] = [:]
        for (offset, member) in picked {
            if let role = lockedRoles[member.cellId] { locked[offset] = role }
        }
        let result = assigner.assign(enemies, locked: locked)
        var roles: [Int: Role] = [:]
        for (offset, member) in draft.enemies.enumerated() {
            if let role = result[offset] { roles[member.cellId] = role }
        }
        return roles
    }

    func role(of member: DraftMember) -> Role? {
        member.isAlly ? member.assignedRole : enemyRoles[member.cellId]
    }

    var orderedEnemies: [DraftMember] {
        guard let draft else { return [] }
        let roles = enemyRoles
        return draft.enemies.sorted {
            (roles[$0.cellId].flatMap { Role.allCases.firstIndex(of: $0) } ?? 9) < (roles[$1.cellId].flatMap { Role.allCases.firstIndex(of: $0) } ?? 9)
        }
    }

    var orderedAllies: [DraftMember] {
        guard let draft else { return [] }
        return draft.allies.sorted {
            ($0.assignedRole.flatMap { Role.allCases.firstIndex(of: $0) } ?? 9) < ($1.assignedRole.flatMap { Role.allCases.firstIndex(of: $0) } ?? 9)
        }
    }

    var me: DraftMember? { draft?.allies.first { $0.isLocal } }
    var myRole: Role { me?.assignedRole ?? .middle }
    var myChampionId: Int { me?.championId ?? 0 }

    var laneOpponent: DraftMember? {
        let roles = enemyRoles
        return draft?.enemies.first { roles[$0.cellId] == myRole && $0.championId > 0 }
    }

    // MARK: Draft analysis

    func traits(_ championId: Int, role: Role?) -> ChampionTraits {
        guard championId > 0 else { return .average() }
        let entry = app.staticData.tierEntry(championId: championId, role: role)
        let tags = app.gameData.classTags(championId)
        let detail = app.gameData.cachedDetail(championId)
        let dd = app.gameData.ddChampions[championId]
        let damageType = detail?.tacticalInfo?.damageType
            ?? (dd.map { $0.info.magic > $0.info.attack ? "kMagic" : "kPhysical" } ?? "kMixed")
        return ChampionTraits(championId: championId, winrate: entry?.winrate ?? 0.5,
                              powerCurve: entry?.powerCurve ?? ChampionTraits.defaultCurve(for: tags),
                              damageType: damageType,
                              damage: detail?.playstyleInfo?.damage ?? (dd.map { max($0.info.attack, $0.info.magic) / 3 } ?? 2),
                              durability: detail?.playstyleInfo?.durability ?? (dd.map { $0.info.defense / 3 } ?? 2),
                              crowdControl: detail?.playstyleInfo?.crowdControl ?? 1,
                              classTags: tags)
    }

    var engine: DraftWinProbabilityEngine {
        let counters = app.staticData.counterpicks
        return DraftWinProbabilityEngine { mine, theirs, role in
            if let entry = counters?.block(championId: theirs, role: role)?.counters.first(where: { $0.championId == mine }) {
                return entry.delta
            }
            if let entry = counters?.block(championId: mine, role: role)?.counters.first(where: { $0.championId == theirs }) {
                return -entry.delta
            }
            return nil
        }
    }

    var allySlots: [DraftSlot] { orderedAllies.map { DraftSlot(traits: traits($0.championId, role: $0.assignedRole), role: $0.assignedRole) } }
    var enemySlots: [DraftSlot] {
        let roles = enemyRoles
        return orderedEnemies.map { DraftSlot(traits: traits($0.championId, role: roles[$0.cellId]), role: roles[$0.cellId]) }
    }

    var analysis: DraftAnalysis? {
        guard let draft else { return nil }
        let allies = allySlots, enemies = enemySlots
        let blue = draft.isBlueSide ? allies : enemies
        let red = draft.isBlueSide ? enemies : allies
        return engine.analyze(blue: blue, red: red)
    }

    /// Ally-perspective win probability.
    var allyWinProbability: Double {
        guard let analysis, let draft else { return 0.5 }
        return draft.isBlueSide ? analysis.blueWinProbability : 1 - analysis.blueWinProbability
    }

    func pickDelta(_ championId: Int) -> Double? { analysis?.pickDeltas[championId] }

    // MARK: Build, runes, items

    var build: BuildBlock? {
        guard myChampionId > 0 else { return nil }
        return app.staticData.build(championId: myChampionId, role: myRole, vs: laneOpponent?.championId)
    }

    var baseBuild: BuildBlock? {
        guard myChampionId > 0 else { return nil }
        return app.staticData.build(championId: myChampionId, role: myRole)
    }

    func opponentTraits(_ championId: Int) -> OpponentTraits? {
        guard championId > 0 else { return nil }
        let alias = app.gameData.alias(championId)
        let t = traits(championId, role: nil)
        let ranged = app.gameData.ddChampions[championId].map { $0.stats.attackrange >= 325 }
            ?? app.gameData.cachedDetail(championId)?.isRanged ?? false
        return OpponentTraits(name: app.gameData.championName(championId), damageType: t.damageType, isRanged: ranged,
                              hardCC: ChampionKnowledge.hardCC.contains(alias), isTank: t.isTank,
                              isHealer: ChampionKnowledge.healers.contains(alias), classTags: t.classTags)
    }

    var runeRecommendation: RuneRecommendation? {
        guard let base = baseBuild?.runes else { return nil }
        let matchupPage = laneOpponent.flatMap { opp in
            app.staticData.matchupRunes?.builds(championId: myChampionId, role: myRole)?.vs?[String(opp.championId)]?.runes
        }
        return DynamicRuneEngine.recommend(base: base, matchupPage: matchupPage, mode: runeMode,
                                           me: opponentTraits(myChampionId),
                                           laneOpponent: laneOpponent.flatMap { opponentTraits($0.championId) },
                                           enemyTeam: (draft?.enemies ?? []).compactMap { opponentTraits($0.championId) },
                                           styles: app.gameData.perkStyles)
    }

    var threats: ThreatProfile {
        var profile = ThreatProfile()
        let enemies = (draft?.enemies ?? []).filter { $0.championId > 0 }
        var magic = 0.0
        for enemy in enemies {
            let alias = app.gameData.alias(enemy.championId)
            let t = traits(enemy.championId, role: nil)
            let name = app.gameData.championName(enemy.championId)
            if ChampionKnowledge.healers.contains(alias) { profile.healingSources.append(name) }
            if ChampionKnowledge.shielders.contains(alias) { profile.shieldSources.append(name) }
            if ChampionKnowledge.hardCC.contains(alias) { profile.hardCC += 1 }
            if t.isTank { profile.tanks += 1 }
            magic += t.magicWeight
        }
        profile.magicShare = enemies.isEmpty ? 0.5 : magic / Double(enemies.count)
        return profile
    }

    var itemGroups: [ItemGroup] {
        guard myChampionId > 0 else { return [] }
        let t = traits(myChampionId, role: myRole)
        let profile: SituationalItemEngine.DamageProfile = t.isTank ? .tank : (t.magicWeight > 0.5 ? .magic : .physical)
        return SituationalItemEngine.groups(profile: profile, build: build, threats: threats, items: app.gameData.items)
    }

    /// Counter picks for my role against the lane opponent, with my mastery.
    var counterSuggestions: [(entry: CounterEntry, mastery: Int)] {
        guard let opponent = laneOpponent else { return [] }
        let pool = app.staticData.counters(of: opponent.championId, role: myRole)
        let taken = Set((draft?.allies ?? []).map(\.championId) + (draft?.enemies ?? []).map(\.championId)
                        + (draft?.allyBans ?? []) + (draft?.enemyBans ?? []))
        let candidates: [(entry: CounterEntry, mastery: Int)] = pool
            .filter { !taken.contains($0.championId) && $0.delta > 0 }
            .map { (entry: $0, mastery: app.mastery(for: $0.championId)) }
        // Strong counter first, but reward champions the player actually plays.
        func score(_ candidate: (entry: CounterEntry, mastery: Int)) -> Double {
            candidate.entry.delta + min(0.02, Double(candidate.mastery) / 5_000_000)
        }
        return Array(candidates.sorted { score($0) > score($1) }.prefix(12))
    }

    var matchupGuide: MatchupGuide? {
        guard let opponent = laneOpponent, myChampionId > 0 else { return nil }
        return guide(my: myChampionId, enemy: opponent.championId, role: myRole)
    }

    /// German 4-point lane guide for any pairing (cached; needs both champion details loaded).
    func guide(my myId: Int, enemy enemyId: Int, role: Role) -> MatchupGuide? {
        let patch = app.gameData.patch
        if let cached = app.guides.guide(my: myId, enemy: enemyId, role: role, patch: patch) {
            return cached
        }
        guard let me = app.gameData.cachedDetail(myId),
              let enemy = app.gameData.cachedDetail(enemyId) else { return nil }
        let myBuild = app.staticData.build(championId: myId, role: role)
        let enemyBuild = app.staticData.build(championId: enemyId, role: role)
        let input = MatchupGuideGenerator.Input(
            me: me, enemy: enemy, myStats: app.gameData.ddChampions[myId],
            enemyStats: app.gameData.ddChampions[enemyId], role: role, patch: patch,
            laneDelta: app.staticData.matchupDelta(championId: myId, vs: enemyId, role: role),
            myCurve: traits(myId, role: role).powerCurve,
            enemyCurve: traits(enemyId, role: role).powerCurve,
            myCoreItem: myBuild?.coreBuild?.itemIds.first.map(app.gameData.itemName),
            enemyCoreItem: enemyBuild?.coreBuild?.itemIds.first.map(app.gameData.itemName))
        return MatchupGuideGenerator.generate(input)
    }

    /// Fetches per-champion details (spells, playstyle) for everybody in the draft.
    func prefetchDetails() async {
        guard let draft else { return }
        for id in (draft.allies + draft.enemies).map(\.championId) where id > 0 {
            _ = await app.gameData.detail(id)
        }
        if let guide = matchupGuide { app.guides.store(guide) }
    }

    // MARK: Actions (LCU writes only on explicit user clicks)

    func hover(_ championId: Int) async {
        guard isLive else {
            actionMessage = "Demo: \(app.gameData.championName(championId)) würde jetzt gehovert."
            return
        }
        do {
            try await app.lcu.hover(championId: championId)
            actionMessage = "\(app.gameData.championName(championId)) gehovert."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    func importRunes() async {
        guard let recommendation = runeRecommendation else { return }
        guard isLive else {
            actionMessage = "Demo: Runenseite würde als „\(RunePageService.pagePrefix) \(app.gameData.championName(myChampionId))“ importiert."
            return
        }
        do {
            try await app.lcu.applyRunes(recommendation.page, title: app.gameData.championName(myChampionId))
            actionMessage = "Runen importiert."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    func importSpells() async {
        guard let ids = build?.summonerSpells?.ids, ids.count == 2 else { return }
        guard isLive else {
            actionMessage = "Demo: Beschwörerzauber würden gesetzt."
            return
        }
        do {
            try await app.lcu.applySummonerSpells(ids)
            actionMessage = "Beschwörerzauber gesetzt."
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}
