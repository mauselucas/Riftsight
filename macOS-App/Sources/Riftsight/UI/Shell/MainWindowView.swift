import RiftsightCore
import SwiftUI

/// Window chrome in the reference layout: fixed sidebar, top bar with history + search, rounded content panel.
struct MainWindowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 214)
            VStack(spacing: 0) {
                TopBar()
                    .frame(height: 50)
                RouteView(route: app.router.current)
                    .id(app.router.reloadToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x141821), Color(hex: 0x10131A)], startPoint: .top, endPoint: .bottom),
                        in: .rect(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    )
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0)
                            .strokeBorder(Theme.border.opacity(0.9), lineWidth: 1)
                    )
                    .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0))
            }
        }
        .background(WindowBackground())
        .ignoresSafeArea()
        .overlay {
            if app.showCommandPalette {
                CommandPalette()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .animation(.snappy(duration: 0.18), value: app.showCommandPalette)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
    }
}

struct WindowBackground: View {
    var body: some View {
        ZStack {
            Theme.window
            RadialGradient(colors: [Color(hex: 0x1A2240).opacity(0.55), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(hex: 0x16203A).opacity(0.35), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}

/// Switches the content panel by route.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .dashboard: DashboardView()
        case .account(let puuid): AccountView(puuid: puuid)
        case .tierlist: TierlistView()
        case .champion(let id, let role): ChampionDetailView(championId: id, initialRole: role)
        case .leaderboards: LeaderboardsView()
        case .recordings: RecordingsView()
        case .overlays: OverlaySettingsView()
        case .spectate: SpectateView()
        case .collection: CollectionView()
        case .dataLens: DataLensView()
        case .matchups: MatchupsView()
        case .champSelect: ChampSelectView()
        case .loadingScreen: LoadingScreenView()
        case .postGame: PostGameView()
        case .settings: SettingsView()
        case .debug: DebugLogView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Logo()
                .padding(.top, 34)
                .padding(.leading, 20)
                .padding(.bottom, 26)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    group("RIFTSIGHT CORE")
                    item(.dashboard)
                    accountItem
                    item(.tierlist)
                    item(.leaderboards)

                    group("RIFTSIGHT APP")
                    item(.recordings)
                    item(.overlays)
                    item(.spectate)
                    item(.collection)

                    group("RIFTSIGHT INSIGHTS")
                    item(.dataLens)
                    item(.matchups)

                    group("IM SPIEL")
                    item(.champSelect, badge: app.lcu.phase == .champSelect ? "LIVE" : nil)
                    item(.loadingScreen, badge: app.lcu.phase.isInGame ? "LIVE" : nil)
                    item(.postGame)
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            ProfileCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
    }

    private func group(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    private func isSelected(_ route: Route) -> Bool {
        switch (route, app.router.current) {
        case (.tierlist, .champion): true
        default: route == app.router.current
        }
    }

    private func item(_ route: Route, badge: String? = nil) -> some View {
        SidebarRow(title: route.title, symbol: route.symbol, selected: isSelected(route), badge: badge) {
            app.router.go(route)
        }
    }

    private var accountItem: some View {
        let account = app.linkedAccounts.first
        let route = Route.account(account?.puuid ?? "")
        let selected = { if case .account = app.router.current { return true } else { return false } }()
        return Button { app.router.go(route) } label: {
            HStack(spacing: 8) {
                ProfileIcon(id: app.profileIconId, size: 18)
                    .clipShape(.rect(cornerRadius: 4))
                Text(app.profileName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text("#\(app.profileTag)").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
            .padding(.leading, 46)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var badge: String?
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14.5, weight: selected ? .semibold : .medium))
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.loss, in: .rect(cornerRadius: 4))
                }
            }
            .foregroundStyle(selected ? Theme.text : (hovering ? Theme.text.opacity(0.9) : Theme.textSecondary))
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                if selected {
                    LinearGradient(colors: [Theme.accent.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.text).frame(width: 3, height: 22)
                        }
                } else if hovering {
                    Theme.hover.opacity(0.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Logo: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LogoMark(size: 34)
            VStack(alignment: .trailing, spacing: -2) {
                Text("Riftsight").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.text)
                Text("APP V.1.0.0").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// Simple vector mark: a stylised "eye of the rift" (diamond lens).
struct LogoMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26)
                .fill(LinearGradient(colors: [Color(hex: 0x8A97FF), Color(hex: 0x4F5BE8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "diamond.fill")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(.white)
            Circle().fill(Color(hex: 0x4F5BE8)).frame(width: size * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.35), radius: 8)
    }
}

struct ProfileCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let solo = app.soloQueue
        Button { app.router.go(.account(app.linkedAccounts.first?.puuid ?? "")) } label: {
            HStack(spacing: 12) {
                ZStack {
                    ProfileIcon(id: app.profileIconId, size: 62)
                        .clipShape(.rect(cornerRadius: 10))
                    VStack {
                        Text(app.region).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Theme.accent, in: .rect(cornerRadius: 4))
                            .offset(y: -6)
                        Spacer()
                        Text("\(app.profileLevel)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Color.black.opacity(0.85), in: .rect(cornerRadius: 4))
                            .offset(y: 6)
                    }
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.profileName).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("#\(app.profileTag)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 4) {
                        RankEmblem(tier: solo.tier, size: 18)
                        Text(solo.tier.displayName.uppercased())
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Theme.rankColor(solo.tier))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(app.lcu.isConnected ? Theme.win : Theme.textTertiary)
                .frame(width: 7, height: 7)
                .help(app.lcu.isConnected ? "Mit dem League-Client verbunden" : "Kein League-Client gefunden – Demo-Daten")
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                navButton("chevron.left", enabled: app.router.canGoBack, help: "Zurück (⌘[)") { app.router.back() }
                navButton("chevron.right", enabled: app.router.canGoForward, help: "Vor (⌘])") { app.router.forward() }
                navButton("arrow.clockwise", enabled: true, help: "Neu laden (⌘R)") {
                    app.router.reload()
                    Task { await app.staticData.load() }
                }
            }
            .background(Theme.field.opacity(0.8), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))

            Button { app.showCommandPalette = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12.5, weight: .medium))
                    Text("Spieler, Champion, Team oder Pro suchen …").font(.system(size: 13))
                    Spacer()
                    HStack(spacing: 3) {
                        KeyCap("⌘")
                        KeyCap("K")
                    }
                }
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .frame(width: 540, height: 32)
                .background(Theme.field.opacity(0.8), in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)

            HStack(spacing: 4) {
                StatusIndicator()
                IconButton(systemName: "ladybug", help: "Protokoll") { app.router.go(.debug) }
                IconButton(systemName: "gearshape", help: "Einstellungen") { app.router.go(.settings) }
            }
            .padding(.trailing, 14)
        }
        .padding(.leading, 0)
    }

    private func navButton(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Theme.textSecondary : Theme.textTertiary.opacity(0.5))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 2)
            .background(Theme.cardRaised, in: .rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

/// Client / game connection indicator (top-right).
struct StatusIndicator: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let connected = app.lcu.isConnected
        let inGame = app.overlay.isInGame
        let label = inGame ? "Im Spiel" : (connected ? app.lcu.phase.displayName : "Offline")
        HStack(spacing: 5) {
            Circle().fill(inGame ? Theme.gold : (connected ? Theme.win : Theme.textTertiary)).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            if app.recorder.isRecording {
                Image(systemName: "record.circle").foregroundStyle(Theme.loss).font(.system(size: 11, weight: .bold))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Theme.field.opacity(0.8), in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.border))
        .help(connected ? "League-Client verbunden (\(app.region))" : "League-Client nicht gefunden – es werden Demo-Daten angezeigt")
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let toast = app.toast {
            Text(toast)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.cardRaised, in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.border))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { app.toast = nil }
                }
        }
    }
}

/// Generic page scaffold used by all content views.
struct Page<Content: View>: View {
    var spacing: CGFloat = 18
    var scrolls = true
    @ViewBuilder var content: Content

    var body: some View {
        if scrolls {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) { content }
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        } else {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
