import RiftsightCore
import SwiftUI

/// ⌘K: jump to pages, champions, linked accounts and pros.
struct CommandPalette: View {
    @Environment(AppModel.self) private var app
    @ViewState private var query = ""
    @ViewState private var highlighted = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        let id: String
        let section: String
        let title: String
        let subtitle: String?
        let icon: Icon
        let action: () -> Void

        enum Icon { case symbol(String), champion(Int), profile(Int) }
    }

    var body: some View {
        let items = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    TextField("Spieler, Champion, Team oder Seite suchen …", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($focused)
                        .onSubmit { run(items) }
                    KeyCap("esc")
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Divider().overlay(Theme.border)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || items[index - 1].section != item.section {
                                    Text(item.section).sectionLabelStyle().padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                                }
                                row(item, selected: index == highlighted)
                                    .id(index)
                                    .onTapGesture { item.action(); close() }
                            }
                            if items.isEmpty {
                                Text("Keine Treffer für „\(query)“").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                                    .frame(maxWidth: .infinity).padding(24)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: highlighted) { _, value in proxy.scrollTo(value) }
                }
                HStack(spacing: 12) {
                    hint("↑↓", "Auswählen")
                    hint("↩", "Öffnen")
                    hint("esc", "Schließen")
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.field)
            }
            .frame(width: 640)
            .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(0, items.count - 1)); return .handled }
        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Group {
                switch item.icon {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28).background(Theme.field, in: .rect(cornerRadius: 7))
                case .champion(let id): ChampionIcon(id: id, size: 28, radius: 7)
                case .profile(let id): ProfileIcon(id: id, size: 28)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5, weight: .medium))
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            if selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(Theme.textTertiary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Theme.accentSoft : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(key)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
    }

    private var results: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pages: [Route] = [.dashboard, .tierlist, .leaderboards, .recordings, .overlays, .spectate, .collection,
                              .dataLens, .matchups, .champSelect, .loadingScreen, .postGame, .settings, .debug]
        var items: [Item] = pages.filter { q.isEmpty || $0.title.lowercased().contains(q) }.map { route in
            Item(id: "page-\(route.slug)", section: "Seiten", title: route.title, subtitle: nil, icon: .symbol(route.symbol)) { app.router.go(route) }
        }
        guard !q.isEmpty else { return Array(items.prefix(8)) }

        items += app.gameData.searchChampions(q).prefix(6).map { champion in
            let tier = app.staticData.tierEntry(championId: champion.id, role: nil)
            return Item(id: "champ-\(champion.id)", section: "Champions", title: champion.name,
                        subtitle: tier.map { "Tier \($0.tier.rawValue) · \($0.winrate.percentString()) Siegrate" } ?? "Builds, Runen & Counter",
                        icon: .champion(champion.id)) { app.router.go(.champion(champion.id, nil)) }
        }
        items += app.linkedAccounts.filter { "\($0.gameName)#\($0.tagLine)".lowercased().contains(q) }.map { account in
            Item(id: "acc-\(account.puuid)", section: "Deine Konten", title: "\(account.gameName)#\(account.tagLine)",
                 subtitle: "\(account.rankTier.displayName) · \(account.region)", icon: .profile(account.profileIconId)) { app.router.go(.account(account.puuid)) }
        }
        let pros = (app.staticData.proSpectate?.games ?? []).flatMap { game in game.participants.filter(\.isKnown).map { (game, $0) } }
        items += pros.filter { $0.1.displayName.lowercased().contains(q) || ($0.1.proTeam?.lowercased().contains(q) ?? false) }
            .prefix(5).map { game, pro in
                Item(id: "pro-\(game.gameId)-\(pro.id)", section: "Pros live", title: pro.displayName,
                     subtitle: "\(pro.proTeam ?? "Pro") · spielt \(app.gameData.championName(pro.championId)) · \(Platform(lenient: game.platformId)?.shortLabel ?? game.platformId)",
                     icon: .champion(pro.championId)) { app.router.go(.spectate) }
            }
        let ladder = (app.staticData.leaderboard?.platforms ?? [:]).flatMap { platform, entries in entries.map { (platform, $0) } }
        items += ladder.filter { $0.1.riotId.lowercased().contains(q) }.prefix(4).map { platform, entry in
            Item(id: "ladder-\(platform)-\(entry.id)", section: "Ranglisten", title: entry.riotId,
                 subtitle: "#\(entry.rank) \(Platform(lenient: platform)?.shortLabel ?? platform) · \(entry.lp.groupedString) LP",
                 icon: .symbol("trophy")) { app.router.go(.leaderboards) }
        }
        return items
    }

    private func run(_ items: [Item]) {
        guard items.indices.contains(highlighted) else { return }
        items[highlighted].action()
        close()
    }

    private func close() {
        query = ""
        app.showCommandPalette = false
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = app.settings
        let solo = app.soloQueue
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LogoMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Riftsight").font(.system(size: 14, weight: .bold))
                    HStack(spacing: 5) {
                        Circle().fill(app.lcu.isConnected ? Theme.win : Theme.textTertiary).frame(width: 6, height: 6)
                        Text(statusText).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                ProfileIcon(id: app.profileIconId, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(app.profileName)#\(app.profileTag)").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        RankEmblem(tier: solo.tier, size: 16)
                        Text(solo.tier.isApex ? "\(solo.tier.displayName) · \(solo.lp) LP" : "\(solo.tier.displayName) \(solo.division ?? "") · \(solo.lp) LP")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(Theme.card, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Overlays", isOn: $settings.overlaysEnabled)
                Toggle("Spiele aufnehmen", isOn: $settings.recordGames)
            }
            .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
            Divider()
            menuButton("Riftsight öffnen", icon: "macwindow") {
                openWindow(id: "main")
                NSApp.activate()
            }
            menuButton("Instant Replay speichern", icon: "gobackward", disabled: !app.overlay.isInGame) { app.instantReplay() }
            menuButton("Einstellungen …", icon: "gearshape") {
                openWindow(id: "main")
                NSApp.activate()
                app.router.go(.settings)
            }
            Divider()
            menuButton("Beenden", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 290)
        .background(Theme.canvas)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private var statusText: String {
        guard app.lcu.isConnected else { return "Client nicht verbunden" }
        if app.overlay.isInGame { return "Im Spiel" }
        return app.lcu.phase == .none ? "Verbunden" : app.lcu.phase.displayName
    }

    private func menuButton(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12.5)).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}
