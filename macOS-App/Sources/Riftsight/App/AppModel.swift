import AppKit
import RiftsightCore
import SwiftUI

/// Root state: owns every service, wires LCU / Live Client events to overlays and the recorder,
/// and decides when demo content is shown.
@MainActor
@Observable
final class AppModel {
    let gameData = CommunityDragonService()
    let staticData = StaticDataService()
    let accounts = LinkedAccountsStore()
    let lcu: LCUService
    let live = LiveGamePoller()
    let scout = LoadingScreenScout()
    let library = RecordingLibrary()
    let recorder: ScreenCaptureRecorder
    let guides = MatchupGuideCache()
    let router = Router()
    let settings = AppSettings()
    @ObservationIgnored private(set) var champSelect: ChampSelectModel!
    @ObservationIgnored private(set) var overlay: LiveOverlayModel!
    @ObservationIgnored private(set) var overlayWindows: OverlayWindowManager!

    var showCommandPalette = false
    var isBooting = true
    var skinInventory: SkinInventory?
    var postGameMatch: MatchRecord?
    var postGameTimeline: ParticipantTimeline?
    var toast: String?

    init() {
        lcu = LCUService(accounts: accounts)
        recorder = ScreenCaptureRecorder(library: library)
        champSelect = ChampSelectModel(app: self)
        overlay = LiveOverlayModel(app: self)
        overlayWindows = OverlayWindowManager(app: self)
    }

    // MARK: Demo handling

    /// Demo content is shown whenever no client is connected (or the user forces it).
    var showsDemo: Bool { settings.forceDemo || demoOverride || !lcu.isConnected }
    /// Snapshot mode: demo content without persisting the preference.
    var demoOverride = false

    @ObservationIgnored private lazy var demoMatches: [MatchRecord] = DemoData.matches()

    var profileName: String { lcu.summoner?.riotName ?? (showsDemo ? DemoData.profile.name : "Nicht verbunden") }
    var profileTag: String { lcu.summoner?.riotTag ?? (showsDemo ? DemoData.profile.tag : "") }
    var profileLevel: Int { lcu.summoner?.summonerLevel ?? DemoData.profile.level }
    var profileIconId: Int { lcu.summoner?.profileIconId ?? DemoData.profile.iconId }
    var region: String { lcu.isConnected ? lcu.region : DemoData.profile.region }

    var soloQueue: (tier: RankTier, division: String?, lp: Int, wins: Int, losses: Int) {
        if let solo = lcu.ranked?.soloDuo, lcu.isConnected {
            return (solo.rankTier, solo.division, solo.leaguePoints ?? 0, solo.wins ?? 0, solo.losses ?? 0)
        }
        let p = DemoData.profile
        return (p.tier, p.division, p.lp, p.wins, p.losses)
    }

    var matches: [MatchRecord] {
        if !showsDemo { return lcu.recentMatches }
        return demoMatches
    }

    var linkedAccounts: [LinkedAccount] {
        accounts.accounts.isEmpty || showsDemo ? DemoData.accounts : accounts.accounts
    }

    func lpHistory(_ puuid: String) -> [LPPoint] {
        let stored = accounts.lpHistory[puuid] ?? []
        return stored.count >= 2 ? stored : DemoData.lpHistory(for: puuid)
    }

    func mastery(for championId: Int) -> Int {
        if let points = lcu.masteries[championId]?.championPoints { return points }
        guard showsDemo else { return 0 }
        var rng = DemoData.RNG(seed: UInt64(championId))
        return rng.chance(0.4) ? rng.int(8_000...420_000) : 0
    }

    // MARK: Lifecycle

    func start() {
        Task {
            await gameData.load()
            AssetContext.ddragonVersion = gameData.version
            await staticData.load()
            isBooting = false
            champSelect.demoDraft = DemoData.draft
            await champSelect.prefetchDetails()
        }
        library.reload()
        wireEvents()
        lcu.start()
        live.start()
        overlayWindows.start()
    }

    /// Loads data only (no LCU / Live Client / overlays) – used by snapshot mode.
    func startForSnapshot() async {
        await gameData.load()
        AssetContext.ddragonVersion = gameData.version
        await staticData.load()
        isBooting = false
        champSelect.demoDraft = DemoData.draft
        await champSelect.prefetchDetails()
    }

    private func wireEvents() {
        lcu.onPhaseChange = { [weak self] old, new in self?.phaseChanged(from: old, to: new) }
        lcu.onEndOfGame = { [weak self] match in
            guard let self else { return }
            postGameMatch = match
            if settings.autoNavigate { router.go(.postGame) }
        }
        live.onUpdate = { [weak self] data in self?.overlay.update(data) }
        live.onNewEvents = { [weak self] events, data in self?.handleLiveEvents(events, data: data) }
        live.onGameEnded = { [weak self] in self?.gameEnded() }
    }

    private func phaseChanged(from old: GameflowPhase, to new: GameflowPhase) {
        DebugLog.shared.add("lcu", "Phase: \(old.displayName) → \(new.displayName)")
        switch new {
        case .champSelect:
            champSelect.lockedRoles = [:]
            if settings.autoNavigate { router.go(.champSelect) }
            Task { await champSelect.prefetchDetails() }
        case .gameStart, .inProgress:
            if let session = lcu.gameflowSession, let client = lcu.client {
                var names: [Int: String] = [:]
                for (id, champ) in gameData.champions { names[id] = champ.name }
                scout.scout(session: session, client: client, championNames: names)
                if settings.autoNavigate, old == .champSelect || old == .none { router.go(.loadingScreen) }
            }
        case .endOfGame, .preEndOfGame:
            if settings.autoNavigate { router.go(.postGame) }
        default:
            break
        }
    }

    private func handleLiveEvents(_ events: [LiveEvent], data: LiveAllGameData) {
        overlay.ingest(events, data: data)
        if events.contains(where: { $0.EventName == "GameStart" }) || (!recorder.isRecording && settings.recordGames && data.gameData.gameTime < 120) {
            if settings.recordGames && !recorder.isRecording {
                Task { await recorder.start(gameTime: data.gameData.gameTime) }
            }
        }
        guard recorder.isRecording, let me = data.localPlayer else { return }
        for event in events {
            let mine = event.KillerName.map(me.matches(name:)) ?? false
            switch event.EventName {
            case "ChampionKill" where mine:
                recorder.addMarker(.kill, gameTime: event.EventTime, label: "Kill: \(event.VictimName ?? "")")
            case "ChampionKill" where event.VictimName.map(me.matches(name:)) ?? false:
                recorder.addMarker(.death, gameTime: event.EventTime, label: "Tod")
            case "Multikill" where mine && (event.KillStreak ?? 0) >= 3:
                recorder.addMarker(.multikill, gameTime: event.EventTime, label: "Multikill ×\(event.KillStreak ?? 3)")
                autoClip(title: (event.KillStreak ?? 3) >= 5 ? "Pentakill" : (event.KillStreak == 4 ? "Quadrakill" : "Triplekill"), data: data)
            case "BaronKill", "DragonKill":
                let kind: TimelineMarker.Kind = event.EventName == "BaronKill" ? .baron : .dragon
                recorder.addMarker(event.wasStolen ? .steal : kind, gameTime: event.EventTime,
                                   label: event.wasStolen ? "Objective gestohlen" : (kind == .baron ? "Baron" : "Drache"))
                if event.wasStolen && mine { autoClip(title: "Objective gestohlen", data: data) }
            case "Ace" where event.AcingTeam == data.localTeam:
                recorder.addMarker(.ace, gameTime: event.EventTime, label: "Ace")
            default:
                break
            }
        }
    }

    private func autoClip(title: String, data: LiveAllGameData) {
        guard settings.autoClips, let me = data.localPlayer else { return }
        let meta = ClipMetadata(kind: .clip, title: title, championId: gameData.championId(alias: me.championAlias),
                                kills: me.scores.kills, deaths: me.scores.deaths, assists: me.scores.assists,
                                queueName: data.modeBucket.displayName)
        Task { await recorder.saveClip(lastSeconds: 30, delay: 6, metadata: meta) }
    }

    func instantReplay() {
        guard recorder.isRecording else {
            toast = "Instant Replay: Es läuft keine Aufnahme."
            return
        }
        let me = live.data?.localPlayer
        let meta = ClipMetadata(kind: .clip, title: "Instant Replay",
                                championId: me.flatMap { gameData.championId(alias: $0.championAlias) },
                                kills: me?.scores.kills, deaths: me?.scores.deaths, assists: me?.scores.assists,
                                queueName: live.data?.modeBucket.displayName)
        toast = "Instant Replay wird gespeichert …"
        Task { await recorder.saveClip(lastSeconds: recorder.replaySeconds, metadata: meta) }
    }

    private func gameEnded() {
        overlay.reset()
        guard recorder.isRecording else { return }
        let me = live.data?.localPlayer
        let meta = ClipMetadata(kind: .fullGame,
                                title: "Ganzes Spiel – \(me?.championName ?? "League")",
                                championId: me.flatMap { gameData.championId(alias: $0.championAlias) },
                                kills: me?.scores.kills, deaths: me?.scores.deaths, assists: me?.scores.assists,
                                queueName: live.data?.modeBucket.displayName)
        Task { await recorder.stop(fullGameMetadata: meta) }
    }

    // MARK: Post-game & collection

    /// The match the post-game screen shows: end-of-game block, selected match, or latest match.
    func loadPostGame(_ match: MatchRecord? = nil) async {
        let candidate = match ?? lcu.lastEndOfGame ?? matches.first
        guard var chosen = candidate else { return }
        if chosen.participants.count < 10, lcu.isConnected, let full = await lcu.fullGame(chosen.gameId) {
            let lp = chosen.lpChange
            chosen = full
            chosen.lpChange = lp
        }
        postGameMatch = chosen
        if showsDemo {
            postGameTimeline = DemoData.timeline(for: chosen)
        } else if let local = chosen.local {
            postGameTimeline = await lcu.timeline(chosen.gameId)[local.participantId]
        }
    }

    func loadCollection() async {
        await gameData.loadSkinsIfNeeded()
        if !showsDemo {
            do {
                skinInventory = try await lcu.loadSkinInventory()
                return
            } catch {
                DebugLog.shared.add("lcu", "Skin-Inventar: \(error.localizedDescription)", error: true)
            }
        }
        skinInventory = DemoData.ownedSkins(gameData.skins)
    }
}

/// User preferences (UserDefaults-backed).
@MainActor
@Observable
final class AppSettings {
    private var defaults: UserDefaults { .standard }

    var forceDemo: Bool { didSet { defaults.set(forceDemo, forKey: "forceDemo") } }
    var autoNavigate: Bool { didSet { defaults.set(autoNavigate, forKey: "autoNavigate") } }
    var recordGames: Bool { didSet { defaults.set(recordGames, forKey: "recordGames") } }
    var autoClips: Bool { didSet { defaults.set(autoClips, forKey: "autoClips") } }
    var overlaysEnabled: Bool { didSet { defaults.set(overlaysEnabled, forKey: "overlaysEnabled") } }
    var enabledWidgets: Set<String> { didSet { defaults.set(Array(enabledWidgets), forKey: "enabledWidgets") } }
    var pipelineURL: String {
        didSet { defaults.set(pipelineURL, forKey: StaticDataService.baseURLDefaultsKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["autoNavigate": true, "recordGames": false, "autoClips": true, "overlaysEnabled": true])
        forceDemo = defaults.bool(forKey: "forceDemo")
        autoNavigate = defaults.bool(forKey: "autoNavigate")
        recordGames = defaults.bool(forKey: "recordGames")
        autoClips = defaults.bool(forKey: "autoClips")
        overlaysEnabled = defaults.bool(forKey: "overlaysEnabled")
        enabledWidgets = Set(defaults.stringArray(forKey: "enabledWidgets") ?? OverlayWidget.allCases.filter(\.defaultOn).map(\.rawValue))
        pipelineURL = defaults.string(forKey: StaticDataService.baseURLDefaultsKey) ?? ""
    }

    func isEnabled(_ widget: OverlayWidget) -> Bool { enabledWidgets.contains(widget.rawValue) }

    func toggle(_ widget: OverlayWidget) {
        if enabledWidgets.contains(widget.rawValue) { enabledWidgets.remove(widget.rawValue) } else { enabledWidgets.insert(widget.rawValue) }
    }
}
