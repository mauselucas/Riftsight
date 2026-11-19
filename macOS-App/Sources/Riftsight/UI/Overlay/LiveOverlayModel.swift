import RiftsightCore
import SwiftUI

enum OverlayWidget: String, CaseIterable, Identifiable {
    case goldBar, winProbability, nextItem, skillUp, trinket, cooldowns, matchupGuide, csBenchmark, itemSpikes, augments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goldBar: "Gold-Differenz"
        case .winProbability: "Siegwahrscheinlichkeit"
        case .nextItem: "Nächstes Item"
        case .skillUp: "Skill-Up-Erinnerung"
        case .trinket: "Trinket-Tausch"
        case .cooldowns: "Gegner-Cooldowns"
        case .matchupGuide: "Matchup-Guide"
        case .csBenchmark: "CS-Benchmark"
        case .itemSpikes: "Item-Spike-Warnung"
        case .augments: "Augment-Berater"
        }
    }

    var detail: String {
        switch self {
        case .goldBar: "Item-Gold beider Teams, Differenz und Objective-Timer am oberen Bildschirmrand."
        case .winProbability: "Live-Siegchance aus Gold, Objectives und Draft."
        case .nextItem: "Welches Item du als Nächstes kaufen solltest – inklusive günstigster Komponente."
        case .skillUp: "Erinnert dich, einen Skillpunkt zu verteilen, nach der besten Skill-Reihenfolge."
        case .trinket: "Hinweis auf den Trinket-Wechsel (z. B. Orakel-Linse ab Stufe 9)."
        case .cooldowns: "Klicke auf Flash/Ult eines Gegners, um den Cooldown (≈) zu starten."
        case .matchupGuide: "Die 4 wichtigsten Punkte gegen deinen Lane-Gegner (bei gedrückter Tab-Taste)."
        case .csBenchmark: "Dein CS im Vergleich zum theoretischen Maximum (bei gedrückter Tab-Taste)."
        case .itemSpikes: "Warnt, wenn ein Gegner ein starkes Item fertigstellt."
        case .augments: "Bewertet die angebotenen Augments in ARAM: Mayhem und Arena."
        }
    }

    var symbol: String {
        switch self {
        case .goldBar: "dollarsign.circle"
        case .winProbability: "percent"
        case .nextItem: "bag"
        case .skillUp: "chevron.up.2"
        case .trinket: "eye"
        case .cooldowns: "timer"
        case .matchupGuide: "text.book.closed"
        case .csBenchmark: "chart.line.uptrend.xyaxis"
        case .itemSpikes: "exclamationmark.triangle"
        case .augments: "sparkles.rectangle.stack"
        }
    }

    /// Riot's developer policies (see docs/gemini-ergebnisse-datenpipeline.md §3.2) reportedly forbid live
    /// enemy cooldown timers, in-game win probability and real-time alerts about enemy item purchases.
    /// These widgets exist (the spec asks for them) but stay off until the user opts in.
    var isPolicySensitive: Bool { self == .winProbability || self == .cooldowns || self == .itemSpikes }

    var policyNote: String? {
        guard isPolicySensitive else { return nil }
        return "Laut Recherche untersagen Riots Entwicklerrichtlinien diese Live-Funktion. Vor einer Veröffentlichung prüfen – standardmäßig aus."
    }

    var defaultOn: Bool { self != .csBenchmark && !isPolicySensitive }

    var defaultVisibility: OverlayVisibility {
        switch self {
        case .matchupGuide, .csBenchmark: .onTab
        default: .always
        }
    }

    /// The gold bar is large by nature; start it smaller.
    var defaultScale: Double { self == .goldBar ? 0.8 : 1.0 }

    var defaultSize: CGSize {
        switch self {
        case .goldBar: CGSize(width: 360, height: 70)
        case .winProbability: CGSize(width: 250, height: 104)
        case .nextItem: CGSize(width: 300, height: 104)
        case .skillUp: CGSize(width: 250, height: 58)
        case .trinket: CGSize(width: 370, height: 58)
        case .cooldowns: CGSize(width: 230, height: 230)
        case .matchupGuide: CGSize(width: 340, height: 250)
        case .csBenchmark: CGSize(width: 230, height: 80)
        case .itemSpikes: CGSize(width: 300, height: 66)
        case .augments: CGSize(width: 640, height: 120)
        }
    }

    /// Default position as a fraction of the screen (origin top-left).
    var defaultAnchor: CGPoint {
        switch self {
        case .goldBar: CGPoint(x: 0.5, y: 0.02)
        case .winProbability: CGPoint(x: 0.01, y: 0.32)
        case .nextItem: CGPoint(x: 0.78, y: 0.3)
        case .skillUp: CGPoint(x: 0.01, y: 0.72)
        case .trinket: CGPoint(x: 0.78, y: 0.62)
        case .cooldowns: CGPoint(x: 0.86, y: 0.06)
        case .matchupGuide: CGPoint(x: 0.01, y: 0.06)
        case .csBenchmark: CGPoint(x: 0.01, y: 0.5)
        case .itemSpikes: CGPoint(x: 0.5, y: 0.14)
        case .augments: CGPoint(x: 0.5, y: 0.78)
        }
    }
}

enum OverlayVisibility: String, CaseIterable, Identifiable {
    case always, onTab, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .always: "Immer"
        case .onTab: "Nur bei Tab"
        case .off: "Aus"
        }
    }
}

/// Live in-game state for the overlays, derived from the Live Client API (read-only).
@MainActor
@Observable
final class LiveOverlayModel {
    private(set) var data: LiveAllGameData?
    private(set) var tracker = ObjectiveEventTracker()
    private var spikeDetector = ItemSpikeDetector(items: [:])
    private(set) var cooldowns: [String: CooldownTimer] = [:]
    private(set) var detectedAugments: [DetectedAugment] = []
    private(set) var isScanningAugments = false
    private(set) var detailsRevision = 0
    var augmentMessage: String?
    var tabHeld = false

    private unowned let app: AppModel
    private let isPreview: Bool
    private var prefetchedMatchKey: String?

    init(app: AppModel, preview: Bool = false) {
        self.app = app
        isPreview = preview
        if preview, let demo = DemoData.liveGame() {
            update(demo)
            ingest(demo.events?.Events ?? [], data: demo)
            let enemy = demo.enemies.first { $0.championAlias == "Syndra" }
            if let enemy {
                cooldowns["\(enemy.id)-ultimate"] = CooldownTimer(playerId: enemy.id, kind: .ultimate, startedAt: demo.gameData.gameTime - 40, duration: 90)
            }
            if let caitlyn = demo.enemies.first(where: { $0.championAlias == "Caitlyn" }) {
                cooldowns["\(caitlyn.id)-spell1"] = CooldownTimer(playerId: caitlyn.id, kind: .spell1, startedAt: demo.gameData.gameTime - 120, duration: 300)
            }
        }
    }

    var isInGame: Bool { data != nil }
    var gameTime: Double { data?.gameData.gameTime ?? 0 }
    var me: LivePlayer? { data?.localPlayer }
    var localTeam: String { data?.localTeam ?? "ORDER" }

    func update(_ data: LiveAllGameData) {
        if self.data == nil || data.gameData.gameTime < (self.data?.gameData.gameTime ?? 0) - 5 {
            tracker = ObjectiveEventTracker()
            spikeDetector = ItemSpikeDetector(items: app.gameData.items)
            cooldowns = [:]
            prefetchedMatchKey = nil
        }
        self.data = data
        _ = spikeDetector.update(players: data.enemies, gameTime: data.gameData.gameTime)

        if !isPreview {
            let key = ([data.localPlayer?.championAlias ?? ""] + data.enemies.map(\.championAlias)).joined(separator: "|")
            if !key.isEmpty && key != prefetchedMatchKey {
                prefetchedMatchKey = key
                Task { await prefetchEnemyDetails() }
            }
        }
    }

    func ingest(_ events: [LiveEvent], data: LiveAllGameData) {
        tracker.ingest(events, players: data.allPlayers)
    }

    func reset() {
        data = nil
        tracker = ObjectiveEventTracker()
        cooldowns = [:]
        detectedAugments = []
        prefetchedMatchKey = nil
    }

    // MARK: Gold & win probability

    private var gold: GoldCalculator { GoldCalculator(items: app.gameData.items) }

    var orderGold: Int { gold.teamValue(data?.allPlayers.filter { $0.team == "ORDER" } ?? []) }
    var chaosGold: Int { gold.teamValue(data?.allPlayers.filter { $0.team == "CHAOS" } ?? []) }
    var allyGold: Int { localTeam == "ORDER" ? orderGold : chaosGold }
    var enemyGold: Int { localTeam == "ORDER" ? chaosGold : orderGold }

    var blueWinProbability: Double {
        let prior: Double = {
            guard let analysis = app.champSelect.analysis else { return 0.5 }
            return analysis.blueWinProbability
        }()
        return LiveWinProbability.blue(goldDiff: orderGold - chaosGold, gameTime: gameTime,
                                       blue: tracker.objectives(for: "ORDER"), red: tracker.objectives(for: "CHAOS"),
                                       draftPrior: isPreview ? 0.53 : prior)
    }

    var timers: [ObjectiveTimer] { tracker.timers(at: gameTime) }

    // MARK: Build guidance

    var myChampionId: Int { me.flatMap { app.gameData.championId(alias: $0.championAlias) } ?? 0 }
    var myRole: Role { me?.role ?? .middle }

    var laneOpponent: LivePlayer? {
        guard let me, let data else { return nil }
        return gold.laneOpponent(of: me, in: data.enemies, allies: data.allies)
    }

    var activeMatchupGuide: MatchupGuide? {
        _ = detailsRevision
        guard myChampionId > 0,
              let opponent = laneOpponent,
              let enemyId = app.gameData.championId(alias: opponent.championAlias) else { return nil }
        return app.guides.guide(my: myChampionId, enemy: enemyId, role: myRole, patch: app.gameData.patch)
            ?? app.champSelect.guide(my: myChampionId, enemy: enemyId, role: myRole)
            ?? (app.champSelect.matchupGuide.flatMap { $0.enemyChampionId == enemyId ? $0 : nil })
    }

    var build: BuildBlock? {
        guard myChampionId > 0 else { return nil }
        let enemy = laneOpponent.flatMap { app.gameData.championId(alias: $0.championAlias) }
        if let mode = augmentModeKey, let block = app.staticData.augmentStats(mode: mode)?.builds?[String(myChampionId)] {
            return block
        }
        return app.staticData.build(championId: myChampionId, role: myRole, vs: enemy)
    }

    /// Core items in the order Champ Select showed them (selected build style first).
    var recommendedCore: [Int] {
        guard let build else { return [] }
        let selected = app.champSelect.myChampionId == myChampionId ? app.champSelect.selectedArchetype : nil
        let archetype = build.archetypes?.first { $0.name == selected } ?? build.archetypes?.first
        return archetype?.itemIds ?? build.coreBuild?.itemIds ?? []
    }

    var nextPurchase: NextPurchase? {
        guard let me, let data = data?.activePlayer else { return nil }
        // Too few games behind this build → no recommendation rather than a random one.
        guard isPreview || app.staticData.isReliable(build) else { return nil }
        let owned = me.itemIds
        let targets = recommendedCore + (build?.completedItems?.map(\.itemId) ?? [])
        guard let target = targets.first(where: { !owned.contains($0) }) else { return nil }
        return SituationalItemEngine.nextPurchase(target: target, owned: owned, gold: Int(data.currentGold), items: app.gameData.items)
    }

    /// The ability to level next, if a skill point is unspent.
    var skillUp: String? {
        guard let active = data?.activePlayer, let abilities = active.abilities else { return nil }
        let spent = abilities.totalPoints
        guard spent < active.level else { return nil }
        if let sequence = build?.skillOrder?.sequence, spent < sequence.count {
            let key = sequence[spent]
            if key == "R" && ![6, 11, 16].contains(where: { active.level >= $0 && abilities.level("R") < [6, 11, 16].firstIndex(of: $0)! + 1 }) {
                return build?.skillOrder?.maxOrder.first
            }
            return key
        }
        if [6, 11, 16].contains(active.level), abilities.level("R") < CooldownCalculator.ultimateRank(level: active.level) { return "R" }
        return build?.skillOrder?.maxOrder.first { abilities.level($0) < 5 } ?? "Q"
    }

    var trinketSwap: (from: Int, to: Int)? {
        guard let me, me.level >= 9 || (myRole == .utility && me.level >= 4), me.itemIds.contains(3340) else { return nil }
        let target = myRole == .bottom || myRole == .middle ? 3363 : 3364
        return (3340, target)
    }

    var cs: (current: Int, benchmark: Int, share: Double) {
        let current = me?.scores.creepScore ?? 0
        let bench = CSBenchmark.minionsAvailable(at: gameTime)
        return (current, bench, CSBenchmark.share(cs: current, gameTime: gameTime))
    }

    var activeSpikes: [ItemSpikeDetector.Spike] {
        if isPreview, let caitlyn = data?.enemies.first(where: { $0.championAlias == "Caitlyn" }) {
            return [ItemSpikeDetector.Spike(playerId: caitlyn.id, itemId: 3031, gameTime: gameTime)] // Infinity Edge
        }
        return spikeDetector.spikes.filter { gameTime - $0.gameTime < 25 }.suffix(2)
    }

    func player(_ id: String) -> LivePlayer? { data?.allPlayers.first { $0.id == id } }

    // MARK: Enemy cooldowns (manual, click to start – values are estimates ≈)

    func cooldownDuration(for player: LivePlayer, kind: CooldownTimer.Kind) -> Double? {
        switch kind {
        case .spell1, .spell2:
            let ref = kind == .spell1 ? player.summonerSpells?.summonerSpellOne : player.summonerSpells?.summonerSpellTwo
            guard let id = ref?.spellId, let base = app.gameData.spell(id)?.cooldown else { return nil }
            return CooldownCalculator.summonerCooldown(base: base, items: player.itemIds, itemDB: app.gameData.items)
        case .ultimate:
            guard let championId = app.gameData.championId(alias: player.championAlias),
                  let detail = app.gameData.cachedDetail(championId) else { return nil }
            return CooldownCalculator.ultimateCooldown(detail: detail, level: player.level, items: player.itemIds, itemDB: app.gameData.items)
        }
    }

    func toggleCooldown(_ player: LivePlayer, kind: CooldownTimer.Kind) {
        let key = "\(player.id)-\(kind.rawValue)"
        if let running = cooldowns[key], running.remaining(at: gameTime) > 0 {
            cooldowns[key] = nil
            return
        }
        guard let duration = cooldownDuration(for: player, kind: kind) else { return }
        cooldowns[key] = CooldownTimer(playerId: player.id, kind: kind, startedAt: gameTime, duration: duration)
    }

    func remaining(_ player: LivePlayer, _ kind: CooldownTimer.Kind) -> Double? {
        guard let timer = cooldowns["\(player.id)-\(kind.rawValue)"] else { return nil }
        let left = timer.remaining(at: gameTime)
        return left > 0 ? left : nil
    }

    func prefetchEnemyDetails() async {
        if myChampionId > 0 {
            _ = await app.gameData.detail(myChampionId)
        }
        for enemy in data?.enemies ?? [] {
            if let id = app.gameData.championId(alias: enemy.championAlias) { _ = await app.gameData.detail(id) }
        }
        if myChampionId > 0,
           let opponent = laneOpponent,
           let enemyId = app.gameData.championId(alias: opponent.championAlias),
           let guide = app.champSelect.guide(my: myChampionId, enemy: enemyId, role: myRole) {
            app.guides.store(guide)
        }
        detailsRevision += 1
    }

    // MARK: Augments

    var augmentModeKey: String? {
        switch data?.modeBucket {
        case .aram: "ARAM_MAYHEM"
        case .arena: "CHERRY"
        default: nil
        }
    }

    func augmentStat(_ id: Int) -> AugmentStat? {
        guard let mode = augmentModeKey ?? (isPreview ? "ARAM_MAYHEM" : nil),
              let stats = app.staticData.augmentStats(mode: mode) else { return nil }
        if let champion = stats.championAugments[String(myChampionId)]?.first(where: { $0.id == id }) { return champion }
        return stats.augments.first { $0.id == id }
    }

    /// Previewed augment choices (first three entries of the sample stats).
    var previewAugments: [DetectedAugment] {
        guard let stats = app.staticData.augmentStats(mode: "ARAM_MAYHEM") else { return [] }
        return stats.augments.sorted { $0.winrate > $1.winrate }.prefix(3).compactMap { stat in
            guard let augment = app.gameData.augments[stat.id] else { return nil }
            return DetectedAugment(augmentId: stat.id, name: augment.name, frame: .zero)
        }
    }

    var shownAugments: [DetectedAugment] { isPreview ? previewAugments : detectedAugments }

    func scanAugments() async {
        guard !isScanningAugments else { return }
        guard ScreenCaptureRecorder.hasPermission else {
            augmentMessage = "Für das Erkennen der Augments braucht Riftsight die Bildschirmaufnahme-Berechtigung."
            ScreenCaptureRecorder.requestPermission()
            return
        }
        isScanningAugments = true
        defer { isScanningAugments = false }
        let names = app.gameData.augments.mapValues(\.name)
        do {
            detectedAugments = try await AugmentDetector.detect(names: names)
            augmentMessage = detectedAugments.isEmpty ? "Keine Augments erkannt – ist die Auswahl gerade offen?" : nil
        } catch {
            augmentMessage = error.localizedDescription
        }
    }
}
