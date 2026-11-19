import RiftsightCore
import SwiftUI

/// Post-game analysis: header, KPIs, German summary, scoreboard with MVP/ACE and score rings.
struct PostGameView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var tab: Tab = .scoreboard

    enum Tab: String, CaseIterable, Hashable {
        case scoreboard, analysis, details
        var title: String {
            switch self {
            case .scoreboard: "Scoreboard"
            case .analysis: "Analyse"
            case .details: "Details"
            }
        }
        var symbol: String {
            switch self {
            case .scoreboard: "list.number"
            case .analysis: "waveform.path.ecg"
            case .details: "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        Group {
            if let match = app.postGameMatch, let me = match.local {
                let scores = PostGameAnalyzer.scores(for: match)
                Page(spacing: 14) {
                    PostGameHeader(match: match, me: me, score: scores[me.participantId])
                    SummaryCard(match: match, me: me)
                    HStack(spacing: 22) {
                        ForEach(Tab.allCases, id: \.self) { item in
                            Button { tab = item } label: {
                                Label(item.title, systemImage: item.symbol)
                                    .font(.system(size: 14, weight: tab == item ? .semibold : .medium))
                                    .foregroundStyle(tab == item ? Theme.text : Theme.textSecondary)
                                    .padding(.vertical, 8)
                                    .overlay(alignment: .bottom) {
                                        if tab == item { Rectangle().fill(Theme.accent).frame(height: 2).offset(y: 2) }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        MatchPicker()
                    }
                    switch tab {
                    case .scoreboard:
                        VStack(spacing: 0) {
                            ForEach(teamOrder(match, me: me), id: \.self) { teamId in
                                TeamSection(match: match, teamId: teamId, scores: scores, localId: me.participantId)
                            }
                        }
                        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
                    case .analysis:
                        AnalysisTab(match: match, me: me)
                    case .details:
                        DetailsTab(match: match)
                    }
                }
            } else {
                Page {
                    PageHeader("Nach dem Spiel", icon: "flag.checkered")
                    EmptyStateView(icon: "flag.checkered", title: "Noch kein Spiel", message: "Nach deinem nächsten Spiel erscheint hier die Auswertung.")
                }
            }
        }
        .task { if app.postGameMatch == nil { await app.loadPostGame() } }
    }

    private func teamOrder(_ match: MatchRecord, me: ParticipantRecord) -> [Int] {
        me.teamId == 100 ? [100, 200] : [200, 100]
    }
}

private struct MatchPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            ForEach(MatchLine.lines(app.matches).prefix(15)) { line in
                Button {
                    Task { await app.loadPostGame(line.match) }
                } label: {
                    Text("\(line.me.win ? "Sieg" : "Niederlage") · \(app.gameData.championName(line.me.championId)) · \(line.me.kills)/\(line.me.deaths)/\(line.me.assists) · \(line.match.creation.relativeGerman)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
                Text("Anderes Spiel").font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Theme.field, in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

// MARK: - Header

private struct PostGameHeader: View {
    @Environment(AppModel.self) private var app
    let match: MatchRecord
    let me: ParticipantRecord
    let score: PlayerScore?

    var body: some View {
        let teamKills = match.players(team: me.teamId).reduce(0) { $0 + $1.kills }
        let teamDamage = match.players(team: me.teamId).reduce(0) { $0 + $1.damageToChampions }
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    ChampionIcon(id: me.championId, size: 52, radius: 8)
                    Text("\(me.champLevel)").font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.85), in: .rect(cornerRadius: 3))
                        .offset(x: 3, y: 3)
                }
                VStack(spacing: 3) {
                    SpellIcon(id: me.spell1Id, size: 22)
                    SpellIcon(id: me.spell2Id, size: 22)
                }
                ZStack(alignment: .bottomTrailing) {
                    PerkIcon(id: me.keystoneId, size: 34)
                    StyleIcon(id: me.subStyleId, size: 15).offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(me.gameName).font(.system(size: 16, weight: .semibold))
                            + Text("#\(me.tagLine)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        if let rank = rankLabel(me) {
                            Text(rank).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x9DB0FF))
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(Theme.accent.opacity(0.18), in: .rect(cornerRadius: 4))
                        }
                    }
                    HStack(spacing: 14) {
                        Text(app.gameData.championName(me.championId))
                        Text(Queue(rawValue: match.queueId)?.displayName ?? match.gameMode)
                        Text(formatClock(Double(match.durationSeconds)))
                        Text(match.creation.relativeGerman)
                    }
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let score {
                    ScoreRing(score: score.score, size: 64, lineWidth: 4)
                }
                VStack(alignment: .trailing, spacing: 6) {
                    Text(me.win ? "Sieg" : "Niederlage")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(me.win ? Color(hex: 0x8FA6FF) : Theme.loss)
                    if let lp = match.lpChange {
                        Text("\(lp >= 0 ? "+" : "−")\(abs(lp)) LP").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(lp >= 0 ? Color(hex: 0x8FA6FF) : Theme.loss)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((lp >= 0 ? Theme.accent : Theme.loss).opacity(0.18), in: .rect(cornerRadius: 5))
                    }
                }
            }
            .padding(16)
            Divider().overlay(Theme.border)
            HStack(spacing: 0) {
                kpi("\(me.kills) / \(me.deaths) / \(me.assists)", String(format: "%.2f KDA", locale: .riftsight, me.kda))
                kpi((Double(me.kills + me.assists) / Double(max(1, teamKills))).percentString(digits: 0), "Kill-Beteiligung")
                kpi(String(format: "%.1f", locale: .riftsight, Double(me.cs) / match.durationMinutes), "CS/Min · \(me.cs) gesamt")
                kpi(me.damageToChampions.compactString, "Schaden · \((Double(me.damageToChampions) / Double(max(1, teamDamage))).percentString(digits: 0)) vom Team")
                kpi("\(me.visionScore)", "Vision-Score", last: true)
            }
        }
        .background(
            LinearGradient(colors: [(me.win ? Color(hex: 0x1D2547) : Color(hex: 0x3A1A22)), Theme.card], startPoint: .topTrailing, endPoint: .bottomLeading),
            in: .rect(cornerRadius: Theme.cornerRadius)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(me.win ? Theme.accent : Theme.loss).frame(height: 2).padding(.horizontal, 8)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
    }

    private func kpi(_ value: String, _ caption: String, last: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .semibold).monospacedDigit())
                Text(caption).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            if !last { Rectangle().fill(Theme.border).frame(width: 1, height: 34) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
    }
}

func rankLabel(_ player: ParticipantRecord) -> String? {
    guard let tier = player.rankTier.map({ RankTier(lenient: $0) }), tier != .unranked else { return nil }
    if tier.isApex { return tier.shortCode }
    return tier.shortCode + romanToArabic(player.rankDivision)
}

private func romanToArabic(_ roman: String?) -> String {
    switch roman {
    case "I": "1"
    case "II": "2"
    case "III": "3"
    case "IV": "4"
    default: roman ?? ""
    }
}

/// Rune tree (style) icon.
struct StyleIcon: View {
    @Environment(AppModel.self) private var app
    let id: Int
    var size: CGFloat = 16

    var body: some View {
        RemoteImage(CDN.gameData(app.gameData.perkStyles[id]?.iconPath), contentMode: .fit, placeholder: .clear)
            .frame(width: size, height: size)
            .background(.black.opacity(0.6), in: .circle)
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    @Environment(AppModel.self) private var app
    let match: MatchRecord
    let me: ParticipantRecord

    var body: some View {
        let lines = PostGameAnalyzer.summary(match: match, player: me, timeline: app.postGameTimeline,
                                             enemyThreats: threats, playerIsMagic: app.gameData.cachedDetail(me.championId)?.isMagicDamage ?? false)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "text.bubble.fill").font(.system(size: 16)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34).background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text("Kurzfazit").font(.system(size: 13, weight: .semibold))
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary)
                        Text(line).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
        .task {
            for player in match.participants { _ = await app.gameData.detail(player.championId) }
        }
    }

    private var threats: ThreatProfile {
        var profile = ThreatProfile()
        let enemies = match.participants.filter { $0.teamId != me.teamId }
        var magic = 0.0
        for enemy in enemies {
            let alias = app.gameData.alias(enemy.championId)
            let name = app.gameData.championName(enemy.championId)
            if ChampionKnowledge.healers.contains(alias) { profile.healingSources.append(name) }
            if ChampionKnowledge.shielders.contains(alias) { profile.shieldSources.append(name) }
            if app.gameData.classTags(enemy.championId).contains("tank") { profile.tanks += 1 }
            if app.gameData.cachedDetail(enemy.championId)?.isMagicDamage == true { magic += 1 }
        }
        profile.magicShare = enemies.isEmpty ? 0.5 : magic / Double(enemies.count)
        return profile
    }
}

// MARK: - Scoreboard

private struct TeamSection: View {
    @Environment(AppModel.self) private var app
    let match: MatchRecord
    let teamId: Int
    let scores: [Int: PlayerScore]
    let localId: Int

    var body: some View {
        let players = match.players(team: teamId).sorted { roleIndex($0) < roleIndex($1) }
        let team = match.team(teamId)
        let win = team?.win ?? players.first?.win ?? false
        let maxDamage = match.participants.map(\.damageToChampions).max() ?? 1
        let avgDamage = Double(players.reduce(0) { $0 + $1.damageToChampions }) / Double(max(1, players.count))
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text(win ? "Sieg" : "Niederlage").font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(win ? Color(hex: 0x8FA6FF) : Theme.loss)
                    Text(teamId == 100 ? "Blaue Seite" : "Rote Seite").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 210, alignment: .leading)
                if let team {
                    HStack(spacing: 12) {
                        objective("building.columns.fill", team.towerKills, "Türme")
                        objective("shield.fill", team.inhibitorKills, "Inhibitoren")
                        objective("flame.fill", team.dragonKills, "Drachen")
                        objective("crown.fill", team.baronKills, "Baron")
                        objective("eye.fill", team.heraldKills, "Herold")
                        objective("ant.fill", team.hordeKills, "Leerenlarven")
                    }
                    .foregroundStyle(win ? Color(hex: 0x8FA6FF) : Theme.loss)
                }
                Spacer()
                if let bans = team?.bans, !bans.isEmpty {
                    Text("Bans").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 3) {
                        ForEach(Array(bans.prefix(5).enumerated()), id: \.offset) { _, id in
                            ChampionIcon(id: id, size: 22, radius: 4, grayscale: true).opacity(0.7)
                        }
                    }
                }
                let k = players.reduce(0) { $0 + $1.kills }, d = players.reduce(0) { $0 + $1.deaths }, a = players.reduce(0) { $0 + $1.assists }
                KDAText(kills: k, deaths: d, assists: a, size: 12)
                Text("\(players.reduce(0) { $0 + $1.gold }.compactString) Gold").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(win ? Color(hex: 0x1A2140) : Color(hex: 0x2E1A20))

            ForEach(players) { player in
                ScoreboardRow(match: match, player: player, score: scores[player.participantId], isLocal: player.participantId == localId,
                              maxDamage: maxDamage, teamAverageDamage: avgDamage)
                Divider().overlay(Theme.border.opacity(0.6))
            }
        }
    }

    private func roleIndex(_ p: ParticipantRecord) -> Int { p.role.flatMap { Role.allCases.firstIndex(of: $0) } ?? 9 }

    private func objective(_ symbol: String, _ count: Int, _ help: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 11))
            Text("\(count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
        }
        .help(help)
    }
}

private struct ScoreboardRow: View {
    @Environment(AppModel.self) private var app
    let match: MatchRecord
    let player: ParticipantRecord
    let score: PlayerScore?
    let isLocal: Bool
    let maxDamage: Int
    let teamAverageDamage: Double

    var body: some View {
        let teamKills = match.players(team: player.teamId).reduce(0) { $0 + $1.kills }
        let kp = Double(player.kills + player.assists) / Double(max(1, teamKills))
        let color = player.win ? Theme.accent : Theme.loss
        HStack(spacing: 12) {
            Group {
                if let score, score.isMVP || score.isACE {
                    Text(score.badge).font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(score.isMVP ? Theme.gold : Color(hex: 0xC6CBFF))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((score.isMVP ? Theme.gold : Theme.accent).opacity(0.16), in: .rect(cornerRadius: 5))
                } else {
                    Text(score?.badge ?? "–").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 46)

            ZStack(alignment: .bottomTrailing) {
                ChampionIcon(id: player.championId, size: 38, radius: 7)
                Text("\(player.champLevel)").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 3).background(.black.opacity(0.85), in: .rect(cornerRadius: 3)).offset(x: 3, y: 3)
            }
            VStack(spacing: 2) {
                SpellIcon(id: player.spell1Id, size: 17)
                SpellIcon(id: player.spell2Id, size: 17)
            }
            VStack(spacing: 2) {
                PerkIcon(id: player.keystoneId, size: 18)
                StyleIcon(id: player.subStyleId, size: 14)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(player.gameName).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text("#\(player.tagLine)").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    if isLocal {
                        Text("DU").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Color(hex: 0x9DB0FF))
                            .padding(.horizontal, 4).padding(.vertical, 1.5).background(Theme.accent.opacity(0.2), in: .rect(cornerRadius: 3))
                    }
                }
                HStack(spacing: 5) {
                    if let rank = rankLabel(player) {
                        Text(rank).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.rankColor(RankTier(lenient: player.rankTier)))
                    }
                    Text(app.gameData.championName(player.championId)).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 190, alignment: .leading)
            Spacer(minLength: 8)

            let items = player.items + Array(repeating: 0, count: max(0, 7 - player.items.count))
            VStack(spacing: 2) {
                HStack(spacing: 2) { ForEach(0..<4, id: \.self) { slot(items[$0]) } }
                HStack(spacing: 2) { ForEach(4..<7, id: \.self) { slot(items[$0]) }; Color.clear.frame(width: 20, height: 20) }
            }

            VStack(alignment: .leading, spacing: 2) {
                KDAText(kills: player.kills, deaths: player.deaths, assists: player.assists, size: 13.5)
                Text(String(format: "%.2f KDA · %@ KP", locale: .riftsight, player.kda, kp.percentString(digits: 0)))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 118, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if player.role == .utility {
                    Text("\(player.visionScore)").font(.system(size: 13.5, weight: .semibold))
                    Text("Vision").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                } else {
                    Text(String(format: "%.1f", locale: .riftsight, Double(player.cs) / match.durationMinutes)).font(.system(size: 13.5, weight: .semibold))
                    Text("\(player.cs) CS").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                (Text(player.damageToChampions.compactString).font(.system(size: 13.5, weight: .semibold))
                    + Text(" Schaden").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.border)
                        Capsule().fill(color).frame(width: proxy.size.width * CGFloat(player.damageToChampions) / CGFloat(max(1, maxDamage)))
                        Rectangle().fill(Theme.text.opacity(0.7)).frame(width: 1.5, height: 9)
                            .offset(x: proxy.size.width * CGFloat(teamAverageDamage) / CGFloat(max(1, maxDamage)))
                            .help("Team-Schnitt")
                    }
                }
                .frame(height: 5)
            }
            .frame(width: 140)

            if let score {
                ScoreRing(score: score.score, size: 34, lineWidth: 2.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(isLocal ? Theme.accent.opacity(0.08) : Theme.card)
        .overlay(alignment: .leading) { if isLocal { Rectangle().fill(Theme.accent).frame(width: 2) } }
    }

    private func slot(_ id: Int) -> some View {
        Group {
            if id > 0 {
                ItemIcon(id: id, size: 20).help(app.gameData.itemName(id))
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Theme.field).frame(width: 20, height: 20)
            }
        }
    }
}

// MARK: - Analysis + details

private struct AnalysisTab: View {
    @Environment(AppModel.self) private var app
    let match: MatchRecord
    let me: ParticipantRecord

    var body: some View {
        let timeline = app.postGameTimeline
        let minutes = Int(match.durationMinutes)
        let cs = (0...minutes).map { Double(timeline?.csAtMinute[$0] ?? 0) }
        let benchmark = (0...minutes).map { Double(max(0, $0 - 1)) * (me.role == .jungle ? 6.2 : 8.0) }
        HStack(alignment: .top, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("CS-Verlauf vs. Benchmark", icon: "chart.line.uptrend.xyaxis")
                    ZStack {
                        Sparkline(values: benchmark, color: Theme.textTertiary, lineWidth: 1.2)
                        Sparkline(values: cs, color: Theme.accent, lineWidth: 2, fill: true)
                    }
                    .frame(height: 170)
                    HStack(spacing: 14) {
                        Label("Du", systemImage: "circle.fill").foregroundStyle(Theme.accent)
                        Label("Benchmark (Challenger-Tempo)", systemImage: "circle.fill").foregroundStyle(Theme.textTertiary)
                    }
                    .font(.system(size: 11))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Tode & Takedowns", icon: "timeline.selection")
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        let safeDuration = Double(max(1, match.durationSeconds))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.border).frame(height: 4)
                            ForEach(Array((timeline?.takedownTimes ?? []).enumerated()), id: \.offset) { _, time in
                                Circle().fill(Theme.win).frame(width: 9, height: 9)
                                    .offset(x: width * CGFloat(min(1, max(0, time / safeDuration))) - 4.5, y: -10)
                            }
                            ForEach(Array((timeline?.deathTimes ?? []).enumerated()), id: \.offset) { _, time in
                                Circle().fill(Theme.loss).frame(width: 9, height: 9)
                                    .offset(x: width * CGFloat(min(1, max(0, time / safeDuration))) - 4.5, y: 10)
                            }
                            Rectangle().fill(Theme.gold.opacity(0.6)).frame(width: 1, height: 34)
                                .offset(x: width * CGFloat(min(1, Double(14 * 60) / safeDuration)))
                        }
                    }
                    .frame(height: 50)
                    HStack {
                        Text("0:00")
                        Spacer()
                        Text("Min. 14").foregroundStyle(Theme.gold)
                        Spacer()
                        Text(formatClock(Double(match.durationSeconds)))
                    }
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 14) {
                        Label("Takedown", systemImage: "circle.fill").foregroundStyle(Theme.win)
                        Label("Tod", systemImage: "circle.fill").foregroundStyle(Theme.loss)
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }
}

private struct DetailsTab: View {
    @Environment(AppModel.self) private var app
    let match: MatchRecord

    var body: some View {
        let players = match.participants
        let columns: [(String, (ParticipantRecord) -> Int)] = [
            ("Schaden", \.damageToChampions), ("Erlitten", \.damageTaken), ("Gold", \.gold),
            ("CS", \.cs), ("Vision", \.visionScore), ("Objektiv-Schaden", \.objectiveDamage),
        ]
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Spieler").frame(width: 220, alignment: .leading)
                    ForEach(columns, id: \.0) { Text($0.0).frame(maxWidth: .infinity, alignment: .trailing) }
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 16).frame(height: 36)
                ForEach(players) { player in
                    Divider().overlay(Theme.border)
                    HStack {
                        HStack(spacing: 8) {
                            Rectangle().fill(player.teamId == 100 ? Theme.blueSideBar : Theme.redSideBar).frame(width: 3, height: 22)
                            ChampionIcon(id: player.championId, size: 24, radius: 5)
                            Text(player.gameName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        }
                        .frame(width: 220, alignment: .leading)
                        ForEach(columns, id: \.0) { column in
                            let value = column.1(player)
                            let best = players.map(column.1).max() ?? 0
                            Text(value.groupedString).font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(value == best ? Theme.gold : Theme.text)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 38)
                }
            }
        }
    }
}
