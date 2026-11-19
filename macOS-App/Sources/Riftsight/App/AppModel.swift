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
        recorder.replaySeconds = settings.replaySeconds
        recorder.recordFullGames = settings.recordGames
        library.storageQuotaGB = settings.storageQuotaGB
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
        if !showsDemo { return stored }
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
        lcu.onGameflowSession = { [weak self] session in self?.handleGameflowSession(session) }
        lcu.onConnected = { [weak self] in
            guard let self else { return }
            Task { await self.loadCollection() }
        }
        lcu.onEndOfGame = { [weak self] match in
            guard let self else { return }
            postGameMatch = match
            if settings.autoNavigate { router.go(.postGame) }
        }
        live.onUpdate = { [weak self] data in self?.handleLiveUpdate(data) }
        live.onNewEvents = { [weak self] events, data in self?.handleLiveEvents(events, data: data) }
        live.onGameEnded = { [weak self] in self?.gameEnded() }
    }

    private func handleGameflowSession(_ session: GameflowSession) {
        guard let client = lcu.client else { return }
        var names: [Int: String] = [:]
        for (id, champ) in gameData.champions { names[id] = champ.name }
        scout.scout(session: session, client: client, championNames: names)
    }

    private func handleLiveUpdate(_ data: LiveAllGameData) {
        overlay.update(data)
        recorder.replaySeconds = settings.replaySeconds
        recorder.recordFullGames = settings.recordGames
        let wantsCapture = settings.recordGames || settings.autoClips
        if wantsCapture && !recorder.isRecording && ScreenCaptureRecorder.hasPermission {
            Task { await recorder.start(gameTime: data.gameData.gameTime) }
        }
    }

    private func phaseChanged(from old: GameflowPhase, to new: GameflowPhase) {
        DebugLog.shared.add("lcu", "Phase: \(old.displayName) → \(new.displayName)")
        switch new {
        case .champSelect:
            scout.reset()
            champSelect.lockedRoles = [:]
            if settings.autoNavigate { router.go(.champSelect) }
            Task { await champSelect.prefetchDetails() }
        case .gameStart, .inProgress, .reconnect:
            if let session = lcu.gameflowSession {
                handleGameflowSession(session)
            }
            if settings.autoNavigate, old == .champSelect || old == .none {
                router.go(.loadingScreen)
            }
        case .endOfGame, .preEndOfGame:
            if settings.autoNavigate { router.go(.postGame) }
        default:
            break
        }
    }

    private func handleLiveEvents(_ events: [LiveEvent], data: LiveAllGameData) {
        overlay.ingest(events, data: data)
        let wantsCapture = settings.recordGames || settings.autoClips
        if wantsCapture && !recorder.isRecording && ScreenCaptureRecorder.hasPermission {
            recorder.replaySeconds = settings.replaySeconds
            recorder.recordFullGames = settings.recordGames
            Task { await recorder.start(gameTime: data.gameData.gameTime) }
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
        let localPuuid = chosen.localPuuid ?? lcu.summoner?.puuid
        if chosen.participants.count < 10, lcu.isConnected, let full = await lcu.fullGame(chosen.gameId) {
            let lp = chosen.lpChange
            chosen = full
            chosen.lpChange = lp
        }
        if chosen.localPuuid == nil { chosen.localPuuid = localPuuid }
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
    var replaySeconds: Double { didSet { defaults.set(replaySeconds, forKey: "replaySeconds") } }
    var storageQuotaGB: Double { didSet { defaults.set(storageQuotaGB, forKey: "storageQuotaGB") } }
    var overlaysEnabled: Bool { didSet { defaults.set(overlaysEnabled, forKey: "overlaysEnabled") } }
    var enabledWidgets: Set<String> { didSet { defaults.set(Array(enabledWidgets), forKey: "enabledWidgets") } }
    /// Widgets that only appear while Tab is held.
    var tabOnlyWidgets: Set<String> { didSet { defaults.set(Array(tabOnlyWidgets), forKey: "tabOnlyWidgets") } }
    /// Per-widget scale factor (0.6 … 1.6).
    var widgetScales: [String: Double] { didSet { defaults.set(widgetScales, forKey: "widgetScales") } }
    var pipelineURL: String {
        didSet { defaults.set(pipelineURL, forKey: StaticDataService.baseURLDefaultsKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "autoNavigate": true, "recordGames": false, "autoClips": true,
            "replaySeconds": 90.0, "storageQuotaGB": 20.0, "overlaysEnabled": true,
        ])
        forceDemo = defaults.bool(forKey: "forceDemo")
        autoNavigate = defaults.bool(forKey: "autoNavigate")
        recordGames = defaults.bool(forKey: "recordGames")
        autoClips = defaults.bool(forKey: "autoClips")
        replaySeconds = defaults.double(forKey: "replaySeconds")
        storageQuotaGB = defaults.double(forKey: "storageQuotaGB")
        overlaysEnabled = defaults.bool(forKey: "overlaysEnabled")
        enabledWidgets = Set(defaults.stringArray(forKey: "enabledWidgets") ?? OverlayWidget.allCases.filter(\.defaultOn).map(\.rawValue))
        tabOnlyWidgets = Set(defaults.stringArray(forKey: "tabOnlyWidgets")
            ?? OverlayWidget.allCases.filter { $0.defaultVisibility == .onTab }.map(\.rawValue))
        widgetScales = (defaults.dictionary(forKey: "widgetScales") as? [String: Double]) ?? [:]
        pipelineURL = defaults.string(forKey: StaticDataService.baseURLDefaultsKey) ?? ""
    }

    func isEnabled(_ widget: OverlayWidget) -> Bool { enabledWidgets.contains(widget.rawValue) }

    func toggle(_ widget: OverlayWidget) {
        if enabledWidgets.contains(widget.rawValue) { enabledWidgets.remove(widget.rawValue) } else { enabledWidgets.insert(widget.rawValue) }
    }

    func visibility(_ widget: OverlayWidget) -> OverlayVisibility {
        guard isEnabled(widget) else { return .off }
        return tabOnlyWidgets.contains(widget.rawValue) ? .onTab : .always
    }

    func setVisibility(_ visibility: OverlayVisibility, for widget: OverlayWidget) {
        switch visibility {
        case .off: enabledWidgets.remove(widget.rawValue)
        case .always: enabledWidgets.insert(widget.rawValue); tabOnlyWidgets.remove(widget.rawValue)
        case .onTab: enabledWidgets.insert(widget.rawValue); tabOnlyWidgets.insert(widget.rawValue)
        }
    }

    func scale(_ widget: OverlayWidget) -> Double { widgetScales[widget.rawValue] ?? widget.defaultScale }

    func setScale(_ scale: Double, for widget: OverlayWidget) {
        widgetScales[widget.rawValue] = min(1.6, max(0.6, (scale * 20).rounded() / 20))
    }

    func resetOverlayLayout() {
        tabOnlyWidgets = Set(OverlayWidget.allCases.filter { $0.defaultVisibility == .onTab }.map(\.rawValue))
        widgetScales = [:]
    }
}
