import RiftsightCore
import SwiftUI

/// Loading-screen scout: both teams with rank, recent form, champion pool and pre-game behaviour badges.
struct LoadingScreenView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var guideReady = 0

    var body: some View {
        let players = shownPlayers
        let myTeam = players.first { $0.puuid == localPuuid }?.teamId ?? 100
        let teams = Dictionary(grouping: players, by: \.teamId)
        Page(spacing: 16) {
            PageHeader("Ladebildschirm", icon: "person.3.fill",
                       subtitle: "Ränge, Form und Champion-Pool aller Spieler – sobald das Spiel lädt.") {
                if usesDemo { Pill(text: "Demo-Lobby", color: Theme.gold, icon: "person.crop.circle.badge.questionmark") }
            }
            if players.isEmpty {
                EmptyStateView(icon: "hourglass", title: "Kein Spiel lädt gerade",
                               message: "Sobald dein nächstes Spiel startet, erscheinen hier beide Teams automatisch.")
            } else if teams.count > 2 {
                // Arena: flat view of every duo.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                    ForEach(players) { ScoutCard(player: $0, accent: $0.teamId == myTeam ? Theme.blueSideBar : Theme.textTertiary) }
                }
            } else {
                if guideReady >= 0, let me = players.first(where: { $0.puuid == localPuuid }), me.championId > 0 {
                    let enemies = players.filter { $0.teamId != myTeam }
                    ItemGuideCard(me: me, laneEnemy: enemies.first { me.role != nil && $0.role == me.role }, enemies: enemies)
                }
                if guideReady >= 0, let guide = laneGuide(players: players, myTeam: myTeam) {
                    LaneGuideCard(guide: guide)
                }
                HStack(alignment: .top, spacing: 16) {
                    TeamColumn(title: "Dein Team", color: Theme.blueSideBar, players: sorted(teams[myTeam] ?? []))
                    TeamColumn(title: "Gegner", color: Theme.redSideBar,
                               players: sorted(players.filter { $0.teamId != myTeam }))
                }
            }
        }
        .task(id: players.map(\.championId)) {
            guard let me = players.first(where: { $0.puuid == localPuuid }), me.championId > 0 else { return }
            _ = await app.gameData.detail(me.championId)
            let enemy = players.first { $0.teamId != myTeam && me.role != nil && $0.role == me.role }
                ?? players.first { $0.teamId != myTeam && $0.championId > 0 }
            if let enemy, enemy.championId > 0 {
                _ = await app.gameData.detail(enemy.championId)
                if let guide = app.champSelect.guide(my: me.championId, enemy: enemy.championId, role: me.role ?? .middle) {
                    app.guides.store(guide)
                }
            }
            guideReady += 1
        }
    }

    private var usesDemo: Bool { app.scout.players.isEmpty }
    private var shownPlayers: [ScoutPlayer] { usesDemo ? (app.showsDemo ? DemoData.scoutPlayers : []) : app.scout.players }
    private var localPuuid: String { app.lcu.summoner?.puuid ?? DemoData.localPuuid }

    private func sorted(_ players: [ScoutPlayer]) -> [ScoutPlayer] {
        players.sorted { (Role.allCases.firstIndex(of: $0.role ?? .utility) ?? 9) < (Role.allCases.firstIndex(of: $1.role ?? .utility) ?? 9) }
    }

    private func laneGuide(players: [ScoutPlayer], myTeam: Int) -> MatchupGuide? {
        guard let me = players.first(where: { $0.puuid == localPuuid }), let role = me.role,
              let enemy = players.first(where: { $0.teamId != myTeam && $0.role == role }) else { return nil }
        return app.champSelect.guide(my: me.championId, enemy: enemy.championId, role: role)
    }
}

private struct TeamColumn: View {
    let title: String
    let color: Color
    let players: [ScoutPlayer]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 16)
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                let ranked = players.compactMap(\.solo).filter { $0.rankTier != .unranked }
                if !ranked.isEmpty {
                    let average = ranked.map { ladderPoints(tier: $0.rankTier, division: $0.division, lp: $0.leaguePoints ?? 0) }.reduce(0, +) / ranked.count
                    Text("Ø \(averageLabel(average))").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(players) { ScoutCard(player: $0, accent: color) }
        }
        .frame(maxWidth: .infinity)
    }

    private func averageLabel(_ points: Int) -> String {
        if points >= 2800 { return "Meister+ · \(points - 2800) LP" }
        let tiers: [RankTier] = [.iron, .bronze, .silver, .gold, .platinum, .emerald, .diamond]
        let tier = tiers[min(tiers.count - 1, points / 400)]
        let division = ["IV", "III", "II", "I"][min(3, (points % 400) / 100)]
        return "\(tier.displayName) \(division)"
    }
}

private struct ScoutCard: View {
    @Environment(AppModel.self) private var app
    let player: ScoutPlayer
    let accent: Color
    @ViewState private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    SplashArt(championId: player.championId, style: .centered)
                    LinearGradient(colors: [.clear, Theme.card], startPoint: .leading, endPoint: .trailing)
                    RoleIcon(role: player.role, size: 12, color: .white)
                        .padding(4).background(.black.opacity(0.55), in: .rect(cornerRadius: 4)).padding(6)
                }
                .frame(width: 118, height: 92)
                .clipped()
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(player.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("#\(player.tag)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    Text(app.gameData.championName(player.championId)).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    if player.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        BadgeRow(badges: player.badges)
                    }
                }
                .padding(.leading, 6)
                Spacer(minLength: 8)
                RankBlock(solo: player.solo)
                FormBlock(player: player)
                    .frame(width: 96)
                Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 92)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Champion-Pool anzeigen")
            }
            if expanded {
                ChampionPoolStrip(pool: player.championPool)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }
}

private struct RankBlock: View {
    let solo: LCURankedQueue?

    var body: some View {
        let tier = solo?.rankTier ?? .unranked
        HStack(spacing: 6) {
            RankEmblem(tier: tier, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(label(tier)).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                if let solo, tier != .unranked {
                    Text("\(solo.leaguePoints ?? 0) LP").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x8FD3FF))
                    Text("\(solo.wins ?? 0)S \(solo.losses ?? 0)N · \(solo.winrate.percentString(digits: 0))")
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: 128, alignment: .leading)
    }

    private func label(_ tier: RankTier) -> String {
        if tier == .unranked { return "Ungewertet" }
        return tier.isApex ? tier.displayName : "\(tier.displayName) \(solo?.division ?? "")"
    }
}

private struct FormBlock: View {
    let player: ScoutPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LETZTE \(player.recentGames)").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            if player.recentGames > 0 {
                Text(player.recentWinrate.percentString(digits: 0))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.winrateColor(player.recentWinrate))
                Text("\(player.recentWins)S \(player.recentGames - player.recentWins)N").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            } else {
                Text("–").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

struct BadgeRow: View {
    let badges: [PlayerBadge]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(badges.prefix(3)) { badge in
                Text(badge.title)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(color(badge.tone))
                    .background(color(badge.tone).opacity(0.14), in: .rect(cornerRadius: 4))
                    .help(badge.detail)
            }
        }
    }

    private func color(_ tone: PlayerBadge.Tone) -> Color {
        switch tone {
        case .positive: Theme.win
        case .negative: Theme.loss
        case .warning: Theme.gold
        case .neutral: Theme.textSecondary
        }
    }
}

private struct ChampionPoolStrip: View {
    @Environment(AppModel.self) private var app
    let pool: [(championId: Int, games: Int, wins: Int)]

    var body: some View {
        if pool.isEmpty {
            Text("Keine Match-Historie verfügbar.").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        } else {
            HStack(spacing: 10) {
                ForEach(pool.prefix(6), id: \.championId) { entry in
                    let winrate = Double(entry.wins) / Double(max(1, entry.games))
                    HStack(spacing: 6) {
                        ChampionIcon(id: entry.championId, size: 26, radius: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(entry.games) Spiele").font(.system(size: 10.5, weight: .medium))
                            Text(winrate.percentString(digits: 0)).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.winrateColor(winrate))
                        }
                    }
                    .help(app.gameData.championName(entry.championId))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LaneGuideCard: View {
    @Environment(AppModel.self) private var app
    let guide: MatchupGuide
    @ViewState private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    ChampionIcon(id: guide.myChampionId, size: 22, radius: 11)
                    Text("vs").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    ChampionIcon(id: guide.enemyChampionId, size: 22, radius: 11)
                    Text("Lane-Guide gegen \(app.gameData.championName(guide.enemyChampionId))")
                        .font(.system(size: 13.5, weight: .semibold))
                    Pill(text: guide.difficulty, color: Theme.gold)
                    Spacer()
                    if !expanded {
                        Text("Ingame mit Tab").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    ForEach(guide.points) { point in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
                            Text(point.text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .cardStyle(padding: 14)
    }
}

/// Recommended build plus "what to buy when" options for the loading screen.
private struct ItemGuideCard: View {
    @Environment(AppModel.self) private var app
    let me: ScoutPlayer
    let laneEnemy: ScoutPlayer?
    let enemies: [ScoutPlayer]

    var body: some View {
        let role = me.role ?? .middle
        let model: ChampSelectModel = app.champSelect
        let build = app.staticData.build(championId: me.championId, role: role, vs: laneEnemy?.championId)
        let chosen = model.myChampionId == me.championId ? model.selectedArchetype : nil
        let archetype = build?.archetypes?.first { $0.name == chosen } ?? build?.archetypes?.first
        let core = archetype?.itemIds ?? build?.coreBuild?.itemIds ?? []
        let boots = (build?.boots ?? []).first.map { [$0.itemId] } ?? []
        let threats = model.threats(enemyIds: enemies.map(\.championId))
        let groups = model.itemGroups(championId: me.championId, role: role, build: build, threats: threats)
            .filter { $0.kind != .coreSpike }
            .sorted { $0.isHighlighted && !$1.isHighlighted }
        let ahead = (build?.completedItems ?? [])
            .filter { !core.contains($0.itemId) && !boots.contains($0.itemId) && !(app.gameData.item($0.itemId)?.categories.contains("Boots") ?? false) }
            .sorted { $0.winrate > $1.winrate }
            .prefix(3).map(\.itemId)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ChampionIcon(id: me.championId, size: 26, radius: 13)
                Text("Item-Guide · \(app.gameData.championName(me.championId))").font(.system(size: 14, weight: .semibold))
                if let archetype { Pill(text: archetype.name, color: Color(hex: 0x9DB0FF)) }
                Spacer()
                if let laneEnemy, laneEnemy.championId > 0 {
                    Text("vs \(app.gameData.championName(laneEnemy.championId))").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            if build == nil {
                Text("Für diesen Champion gibt es noch keine Build-Daten.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            } else {
                if !app.staticData.isReliable(build) {
                    Label("Erst \(build?.games ?? 0) Spiele in den Daten – Empfehlung noch unsicher", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(Theme.gold)
                }
                HStack(alignment: .top, spacing: 22) {
                    step("Start", ids: build?.startingItems?.itemIds ?? [])
                    step("Kern-Build", ids: core, arrows: true)
                    if !boots.isEmpty { step("Stiefel", ids: boots) }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Je nach Spielverlauf").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                        if !ahead.isEmpty {
                            option(symbol: "arrow.up.right", title: "Du liegst vorne", detail: "Mehr Schaden – Vorsprung ausbauen.",
                                   ids: ahead, highlighted: false)
                        }
                        ForEach(groups) { group in
                            option(symbol: group.kind.symbol, title: condition(group.kind),
                                   detail: group.trigger ?? hint(group.kind),
                                   ids: group.items.prefix(3).map(\.itemId), highlighted: group.isHighlighted)
                        }
                    }
                }
            }
        }
        .cardStyle(padding: 16)
    }

    private func step(_ title: String, ids: [Int], arrows: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 5) {
                ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                    if arrows && index > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                    ItemIcon(id: id, size: 34).help(app.gameData.itemName(id))
                }
                if ids.isEmpty { Text("–").foregroundStyle(Theme.textTertiary) }
            }
        }
    }

    private func option(symbol: String, title: String, detail: String, ids: [Int], highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if highlighted { Text("JETZT WICHTIG").font(.system(size: 8.5, weight: .heavy)) }
            }
            .foregroundStyle(highlighted ? Theme.gold : Theme.text)
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                ForEach(ids, id: \.self) { ItemIcon(id: $0, size: 28).help(app.gameData.itemName($0)) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? Theme.gold.opacity(0.07) : Theme.cardRaised, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(highlighted ? Theme.gold.opacity(0.4) : Theme.border))
    }

    private func condition(_ kind: ItemGroupKind) -> String {
        switch kind {
        case .coreSpike: "Standard"
        case .antiHeal: "Gegner heilen viel"
        case .defensive: "Du stirbst zu schnell"
        case .tankShred: "Gegner sind zu tanky"
        }
    }

    private func hint(_ kind: ItemGroupKind) -> String {
        switch kind {
        case .coreSpike: ""
        case .antiHeal: "Ab 2 Heil- oder Schildquellen – früh das billige Bauteil."
        case .defensive: "Wenn du hinten liegst oder in einer Combo fällst."
        case .tankShred: "Ab 2 Tanks oder wenn sie Rüstung/MR stapeln."
        }
    }
}
