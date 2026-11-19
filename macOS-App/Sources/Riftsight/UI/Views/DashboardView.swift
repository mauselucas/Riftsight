import RiftsightCore
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var filter: QueueFilter = .all

    var body: some View {
        let lines = MatchLine.lines(app.matches.filter { filter.matches($0.queueId) })
        Page(spacing: 16) {
            PageHeader("Dashboard", icon: "house.fill") {
                HStack(spacing: 18) {
                    Text("Deine Spiele, Clips und Live-Daten auf einen Blick –\nalles lokal aus dem League-Client.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    if app.showsDemo { Pill(text: "Demo-Modus", color: Theme.gold, icon: "circle.fill") }
                    SegmentedPills(options: QueueFilter.allCases.map { ($0, $0.title) }, selection: $filter, compact: true)
                    VStack(spacing: 0) {
                        Text("Letzte \(lines.count)").font(.system(size: 11.5, weight: .medium))
                        Text("Spiele").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                    VStack(spacing: 0) {
                        Text("Saison").font(.system(size: 11.5, weight: .medium))
                        Text(String(app.gameData.patch.split(separator: ".").first ?? "16")).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    ProfileHero(lines: lines)
                        .frame(height: 300)
                    HStack(spacing: 16) {
                        ProSpectateCard()
                        RecordingsCard()
                    }
                    .frame(height: 210)
                    HStack(spacing: 16) {
                        OverlayPreviewCard()
                        CollectionCard()
                        DataLensCard(lines: lines)
                            .frame(width: 170)
                    }
                    .frame(height: 210)
                }
                VStack(spacing: 10) {
                    RankCard()
                    ForEach(lines.prefix(6)) { line in
                        MatchRow(line: line, compact: true)
                    }
                    ChampionPerformanceCard(lines: lines)
                }
                .frame(width: 318)
            }
        }
    }
}

// MARK: - Hero

private struct ProfileHero: View {
    @Environment(AppModel.self) private var app
    let lines: [MatchLine]

    var body: some View {
        let favorite = Dictionary(grouping: lines, by: \.me.championId).max { $0.value.count < $1.value.count }?.key ?? 103
        ZStack {
            SplashArt(championId: favorite, skinNum: 0, style: .splash, alignment: .top)
                .overlay(LinearGradient(colors: [Theme.card.opacity(0.92), Theme.card.opacity(0.55), Theme.card.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(colors: [.clear, Theme.card.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        ProfileIcon(id: app.profileIconId, size: 86).clipShape(.rect(cornerRadius: 10))
                        VStack {
                            Text(app.region).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent, in: .rect(cornerRadius: 4)).offset(y: -7)
                            Spacer()
                            Text("\(app.profileLevel)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.85), in: .rect(cornerRadius: 4)).offset(y: 7)
                        }
                    }
                    .frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: -4) {
                        HStack(spacing: 8) {
                            Text(app.profileName).font(.system(size: 38, weight: .bold))
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 18)).foregroundStyle(Theme.gold)
                        }
                        Text("#\(app.profileTag)").font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 4) {
                            ForEach(["sparkles", "chart.xyaxis.line", "scope"], id: \.self) { symbol in
                                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                                    .frame(width: 26, height: 24)
                                    .background(symbol == "chart.xyaxis.line" ? Theme.accent : Theme.field.opacity(0.8), in: .rect(cornerRadius: 6))
                            }
                        }
                        Text("Letzte 5 vs. dein Schnitt").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
                let series = headlineSeries(lines)
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { ForEach(series.prefix(4)) { StatTile(series: $0) } }
                    GridRow { ForEach(series.dropFirst(4)) { StatTile(series: $0) } }
                }
            }
            .padding(18)
        }
        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
    }
}

// MARK: - Right column

private struct RankCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let solo = app.soloQueue
        let games = solo.wins + solo.losses
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(hex: 0x1B2A3A), Color(hex: 0x172030)], startPoint: .leading, endPoint: .trailing)
            RankEmblem(tier: solo.tier, size: 120)
                .opacity(0.35)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Solo/Duo").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Text((solo.tier.displayName + (solo.tier.isApex ? "" : " \(solo.division ?? "")")).uppercased())
                    .font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(solo.lp) LP").font(.system(size: 20, weight: .regular)).foregroundStyle(Color(hex: 0x8FD3FF))
                    Text("\(solo.wins)S – \(solo.losses)N (\(games == 0 ? "–" : (Double(solo.wins) / Double(games)).percentString(digits: 0)))")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(16)
        }
        .frame(height: 96)
        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
    }
}

private struct ChampionPerformanceCard: View {
    @Environment(AppModel.self) private var app
    let lines: [MatchLine]

    var body: some View {
        let grouped = Dictionary(grouping: lines, by: \.me.championId)
            .sorted { $0.value.count > $1.value.count }
            .prefix(3)
        let roles = Dictionary(grouping: lines.filter { $0.me.role != nil }, by: { $0.me.role! })
        VStack(spacing: 12) {
            Label("Champion-Performance", systemImage: "wand.and.stars").font(.system(size: 13.5, weight: .semibold))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(grouped.enumerated()), id: \.element.key) { index, group in
                    let wins = group.value.filter(\.me.win).count
                    let k = group.value.map { Double($0.me.kills) }.average
                    let d = group.value.map { Double($0.me.deaths) }.average
                    let a = group.value.map { Double($0.me.assists) }.average
                    VStack(spacing: 3) {
                        ChampionIcon(id: group.key, size: index == 0 ? 44 : 38, radius: 8)
                        Text(app.gameData.championName(group.key)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Text("\(wins)S – \(group.value.count - wins)N").font(.system(size: 12, weight: .semibold))
                        Text(String(format: "%.1f / %.1f / %.1f", locale: .riftsight, k, d, a)).font(.system(size: 9.5)).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: index == 0 ? -10 : 0)
                }
            }
            HStack(spacing: 0) {
                ForEach(Role.allCases) { role in
                    let games = roles[role] ?? []
                    let wr = games.isEmpty ? nil : Double(games.filter(\.me.win).count) / Double(games.count)
                    VStack(spacing: 3) {
                        RoleIcon(role: role, size: 18, color: games.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                        Text(wr.map { $0.percentString(digits: 0) } ?? "–").font(.system(size: 12, weight: .medium))
                        Text("\(games.count) Sp.").font(.system(size: 9.5)).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
    }
}

// MARK: - Middle cards

struct ProSpectateCard: View {
    @Environment(AppModel.self) private var app
    @ViewState private var index = 0

    var body: some View {
        let games = app.staticData.proSpectate?.games ?? []
        LinkCard {
            if games.isEmpty {
                EmptyStateView(icon: "display", title: "Keine Pro-Spiele", message: "Die Pipeline liefert gerade keine Live-Spiele.")
            } else {
                let game = games[index % games.count]
                let known = game.participants.filter(\.isKnown)
                let first = known.first ?? game.participants[0]
                let second = known.dropFirst().first ?? game.participants[min(5, game.participants.count - 1)]
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        SplashArt(championId: first.championId, style: .splash, alignment: .center)
                        SplashArt(championId: second.championId, style: .splash, alignment: .center)
                    }
                    .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.loss).frame(width: 7, height: 7)
                            Text(formatClock(Date().timeIntervalSince(game.startDate))).font(.system(size: 16, weight: .semibold).monospacedDigit())
                            Text(Platform(lenient: game.platformId)?.shortLabel ?? game.platformId).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        HStack(alignment: .bottom) {
                            player(first)
                            Spacer()
                            VStack(spacing: 8) {
                                Text("vs").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                Button { app.router.go(.spectate) } label: {
                                    Label("Zuschauen", systemImage: "eye").font(.system(size: 12, weight: .semibold)).fixedSize()
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Theme.accent, in: .rect(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            player(second).multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(14)
                }
                .overlay(alignment: .leading) { arrow("arrow.left") { index = (index + games.count - 1) % games.count } }
                .overlay(alignment: .trailing) { arrow("arrow.right") { index = (index + 1) % games.count } }
            }
        }
    }

    private func player(_ participant: ProParticipant) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(participant.displayName).font(.system(size: 15, weight: .bold)).lineLimit(1)
            Text(participant.proTeam ?? app.gameData.championName(participant.championId)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).padding(8)
        }
        .buttonStyle(.plain)
    }
}

private struct RecordingsCard: View {
    @Environment(AppModel.self) private var app

    private var clips: [ClipCardModel] {
        if !app.library.items.isEmpty {
            return app.library.items.map { item in
                let m = item.metadata
                return ClipCardModel(id: item.url.path, title: m.title, championId: m.championId, skinNum: 0,
                                     kills: m.kills, deaths: m.deaths, assists: m.assists, queue: m.queueName ?? "",
                                     date: m.createdAt, duration: m.duration, isFullGame: m.kind == .fullGame,
                                     favorite: m.favorite, fileURL: item.url, thumbnail: item.thumbnail, markers: m.markers)
            }
        }
        return DemoData.clips.map {
            ClipCardModel(id: $0.id, title: $0.title, championId: $0.championId, skinNum: $0.skinNum,
                          kills: $0.kills, deaths: $0.deaths, assists: $0.assists, queue: $0.queue,
                          date: $0.date, duration: $0.duration, isFullGame: $0.isFullGame,
                          favorite: $0.favorite, fileURL: nil, thumbnail: nil, markers: [])
        }
    }

    var body: some View {
        let allClips = clips
        let full = allClips.first { $0.isFullGame } ?? allClips.first
        LinkCard {
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let thumb = full?.thumbnail {
                            RemoteImage(thumb)
                        } else {
                            SplashArt(championId: full?.championId ?? 103, skinNum: full?.skinNum ?? 0, style: .centered)
                        }
                    }
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(full?.isFullGame == true ? "GANZES SPIEL" : "CLIP").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x8FB2FF))
                                .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.accent.opacity(0.25), in: .rect(cornerRadius: 4))
                            Spacer()
                            Text(formatClock(full?.duration ?? 0)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 3).background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            ChampionIcon(id: full?.championId ?? 103, size: 26, radius: 13)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(full?.title ?? "Ganzes Spiel").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text("\(full?.queue ?? "") · \(full?.date.relativeGerman ?? "")").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if let full, let k = full.kills, let d = full.deaths, let a = full.assists {
                            HStack(spacing: 6) {
                                KDAText(kills: k, deaths: d, assists: a, size: 13)
                                Text(String(format: "%.1f KDA", locale: .riftsight, Double(k + a) / Double(max(1, d))))
                                    .font(.system(size: 10.5)).foregroundStyle(Color(hex: 0x9DB0FF))
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(width: 190)
                .clipped()
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(allClips.filter { !$0.isFullGame }.prefix(4)) { clip in
                        HStack(spacing: 8) {
                            ZStack(alignment: .bottomLeading) {
                                Group {
                                    if let thumb = clip.thumbnail {
                                        RemoteImage(thumb)
                                    } else {
                                        SplashArt(championId: clip.championId ?? 103, skinNum: clip.skinNum, style: .centered)
                                    }
                                }
                                .frame(width: 50, height: 30).clipShape(.rect(cornerRadius: 4))
                                Text(formatClock(clip.duration)).font(.system(size: 8.5, weight: .bold).monospacedDigit())
                                    .padding(.horizontal, 3).background(.black.opacity(0.7), in: .rect(cornerRadius: 2))
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(clip.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(clip.date.relativeGerman).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button { app.router.go(.recordings) } label: {
                        HStack(spacing: 4) { Text("Alle ansehen"); Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Bottom cards

private struct OverlayPreviewCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        LinkCard(title: "Overlays", action: { app.router.go(.overlays) }) {
            ZStack(alignment: .top) {
                SplashArt(championId: 222, style: .splash, alignment: .center).opacity(0.35).blur(radius: 1.5)
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        timerChip("flame.fill", "1:41")
                        timerChip("crown.fill", "0:27")
                        timerChip("bolt.fill", "8:14")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            LogoMark(size: 12)
                            Text("RIFTSIGHT").font(.system(size: 9, weight: .heavy))
                        }
                        ForEach([("CSM", "7.1 / 6.2"), ("GPM", "452 / 392"), ("KDA", "7.2 / 2.8"), ("KP%", "37 / 35")], id: \.0) { row in
                            HStack {
                                Text(row.0).font(.system(size: 9, weight: .bold)).frame(width: 30, alignment: .leading)
                                Text(row.1).font(.system(size: 9).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                Sparkline(values: [3, 5, 4, 6, 5, 7, 6], color: Theme.accent, lineWidth: 1).frame(width: 34, height: 9)
                            }
                        }
                    }
                    .padding(8)
                    .background(Theme.overlayGlass, in: .rect(cornerRadius: 6))
                }
                .padding(.top, 18)
            }
        }
    }

    private func timerChip(_ symbol: String, _ time: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18).background(.black.opacity(0.6), in: .circle).overlay(Circle().strokeBorder(.white.opacity(0.4)))
            Text(time).font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }
}

private struct CollectionCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let allNonBase = app.gameData.skins.values.filter { !$0.isBase }
        let owned = app.skinInventory?.owned.count ?? (app.showsDemo ? 212 : 0)
        let total = max(allNonBase.count, app.showsDemo ? 482 : 1)
        LinkCard {
            ZStack(alignment: .bottomLeading) {
                SplashArt(championId: 103, skinNum: 27, style: .splash, alignment: .top)
                    .overlay(LinearGradient(colors: [.clear, Theme.card.opacity(0.95)], startPoint: .center, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 8) {
                    Button { app.router.go(.collection) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "diamond.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0x9DB0FF))
                            Text("Sammlung").font(.system(size: 15, weight: .semibold))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    HStack {
                        Text("Skins im Besitz").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(owned)").font(.system(size: 15, weight: .semibold)) + Text(" / \(total)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    ProgressBar(value: Double(owned) / Double(max(1, total)), color: Color(hex: 0x8FA0FF))
                }
                .padding(16)
            }
        }
        .task(id: app.lcu.isConnected) { await app.loadCollection() }
    }
}

private struct DataLensCard: View {
    @Environment(AppModel.self) private var app
    let lines: [MatchLine]

    var body: some View {
        let deaths = lines.reversed().map { Double($0.me.deaths) }
        let survivability = Int((100 - min(60, deaths.average * 8)).rounded())
        LinkCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Data Lens", systemImage: "shield.checkered").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                Spacer()
                Sparkline(values: Array(deaths.suffix(14)).map { -$0 }, color: Theme.text.opacity(0.85), lineWidth: 1.3)
                    .frame(height: 50)
                Text("Überlebensfähigkeit").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                Text("Tode in Teamfights").font(.system(size: 12.5, weight: .medium))
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(survivability)").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.gold)
                    Text("/100").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .contentShape(.rect)
            .onTapGesture { app.router.go(.dataLens) }
        }
    }
}
