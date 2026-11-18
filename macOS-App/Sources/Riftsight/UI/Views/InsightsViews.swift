import RiftsightCore
import SwiftUI

// MARK: - Data Lens (deep analysis of your own games)

struct DataLensView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var queue: QueueFilter = .all
    @ViewState private var role: Role?

    var body: some View {
        let lines = MatchLine.lines(app.matches).filter { queue.matches($0.match.queueId) && (role == nil || $0.me.role == role) }
        Page(spacing: 16) {
            PageHeader("Data Lens", icon: "doc.text.magnifyingglass", subtitle: "Tiefenanalyse deiner letzten Spiele – Trends, Rollen, Champions und Spieldauer.") {
                if app.showsDemo { Pill(text: "Demo-Spiele", color: Theme.gold, icon: "person.crop.circle.badge.questionmark") }
            }
            HStack(spacing: 10) {
                SegmentedPills(options: QueueFilter.allCases.map { ($0, $0.title) }, selection: $queue, compact: true)
                RoleFilter(selection: $role)
                Spacer()
                Text("\(lines.count) Spiele").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            if lines.count < 3 {
                EmptyStateView(icon: "chart.bar.doc.horizontal", title: "Zu wenige Spiele",
                               message: "Für diese Auswahl gibt es noch nicht genug Spiele für eine Analyse.")
            } else {
                let series = headlineSeries(lines)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(series) { StatTile(series: $0) }
                }
                HStack(alignment: .top, spacing: 16) {
                    InsightList(lines: lines, series: series)
                    DurationBuckets(lines: lines).frame(width: 340)
                }
                HStack(alignment: .top, spacing: 16) {
                    ChampionBreakdown(lines: lines)
                    RoleBreakdown(lines: lines).frame(width: 340)
                }
            }
        }
    }
}

private struct InsightList: View {
    @Environment(AppModel.self) private var app
    let lines: [MatchLine]
    let series: [StatSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Erkenntnisse", icon: "lightbulb")
            ForEach(insights, id: \.text) { insight in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: insight.positive ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                        .foregroundStyle(insight.positive ? Theme.win : Theme.loss)
                    Text(insight.text).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private var insights: [(text: String, positive: Bool)] {
        var result: [(String, Bool)] = []
        // Strongest movements of the last five games against the whole sample.
        let moved = series.filter { $0.average > 0 }
            .map { ($0, $0.delta / $0.average * ($0.higherIsBetter ? 1 : -1)) }
            .sorted { abs($0.1) > abs($1.1) }
        for (stat, change) in moved.prefix(3) where abs(change) >= 0.05 {
            let direction = change > 0 ? "besser" : "schlechter"
            result.append(("\(stat.title) in den letzten 5 Spielen \(Int((abs(change) * 100).rounded())) % \(direction) als dein Schnitt (\(stat.format(stat.current)) statt \(stat.format(stat.average))).", change > 0))
        }
        let byChampion = Dictionary(grouping: lines, by: \.me.championId).filter { $0.value.count >= 3 }
        if let best = byChampion.max(by: { winrate($0.value) < winrate($1.value) }) {
            result.append(("Stärkster Champion: \(app.gameData.championName(best.key)) mit \(winrate(best.value).percentString(digits: 0)) Siegrate in \(best.value.count) Spielen.", true))
        }
        if let worst = byChampion.min(by: { winrate($0.value) < winrate($1.value) }), winrate(worst.value) < 0.45 {
            result.append(("\(app.gameData.championName(worst.key)) läuft gerade nicht: \(winrate(worst.value).percentString(digits: 0)) in \(worst.value.count) Spielen.", false))
        }
        let deaths = lines.map { Double($0.me.deaths) }.average
        if deaths >= 6 {
            result.append(("Ø \(String(format: "%.1f", locale: .riftsight, deaths)) Tode pro Spiel – weniger riskante Plays bringen hier am meisten.", false))
        }
        let long = lines.filter { $0.minutes > 32 }
        if long.count >= 3 {
            let rate = winrate(long)
            result.append(("Lange Spiele (> 32 Min.): \(rate.percentString(digits: 0)) Siegrate – \(rate >= 0.5 ? "du skalierst gut." : "versuche, Spiele früher zu beenden.")", rate >= 0.5))
        }
        return result
    }

    private func winrate(_ lines: [MatchLine]) -> Double {
        Double(lines.filter(\.me.win).count) / Double(max(1, lines.count))
    }
}

private struct DurationBuckets: View {
    let lines: [MatchLine]

    var body: some View {
        let buckets: [(String, [MatchLine])] = [
            ("< 25 Min.", lines.filter { $0.minutes < 25 }),
            ("25–32 Min.", lines.filter { $0.minutes >= 25 && $0.minutes <= 32 }),
            ("> 32 Min.", lines.filter { $0.minutes > 32 }),
        ]
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Siegrate nach Spieldauer", icon: "clock")
            ForEach(buckets, id: \.0) { title, games in
                let rate = Double(games.filter(\.me.win).count) / Double(max(1, games.count))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(title).font(.system(size: 12.5, weight: .medium))
                        Text("\(games.count) Spiele").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text(games.isEmpty ? "–" : rate.percentString(digits: 0)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(games.isEmpty ? Theme.textTertiary : Theme.winrateColor(rate))
                    }
                    ProgressBar(value: games.isEmpty ? 0 : rate, color: Theme.winrateColor(rate), height: 6)
                }
            }
        }
        .cardStyle(padding: 16)
    }
}

private struct ChampionBreakdown: View {
    @Environment(AppModel.self) private var app
    let lines: [MatchLine]

    var body: some View {
        let groups = Dictionary(grouping: lines, by: \.me.championId).sorted { $0.value.count > $1.value.count }
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Champions", icon: "person.crop.square")
            HStack(spacing: 0) {
                Text("CHAMPION").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["SPIELE", "SIEGRATE", "KDA", "CS/MIN", "DMG/MIN", "SCORE"], id: \.self) { Text($0).frame(width: 74, alignment: .trailing) }
            }
            .font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textTertiary)
            ForEach(groups.prefix(8), id: \.key) { championId, games in
                let rate = Double(games.filter(\.me.win).count) / Double(games.count)
                HStack(spacing: 0) {
                    HStack(spacing: 9) {
                        ChampionIcon(id: championId, size: 28, radius: 6)
                        Text(app.gameData.championName(championId)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        Text("\(games.count)")
                        Text(rate.percentString(digits: 0)).foregroundStyle(Theme.winrateColor(rate))
                        Text(decimal(games.map(\.kda).average))
                        Text(decimal(games.map(\.csPerMin).average))
                        Text(Int(games.map(\.damagePerMin).average.rounded()).groupedString)
                        Text(decimal(games.map { Double($0.score?.score ?? 0) }.average, digits: 0))
                    }
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .frame(width: 74, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private func decimal(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", locale: .riftsight, value)
    }
}

private struct RoleBreakdown: View {
    let lines: [MatchLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Rollen", icon: "person.2")
            ForEach(Role.allCases) { role in
                let games = lines.filter { $0.me.role == role }
                if !games.isEmpty {
                    let rate = Double(games.filter(\.me.win).count) / Double(games.count)
                    HStack(spacing: 10) {
                        RoleIcon(role: role, size: 16, color: Theme.text)
                        Text(role.displayName).font(.system(size: 12.5, weight: .medium)).frame(width: 64, alignment: .leading)
                        ProgressBar(value: Double(games.count) / Double(max(1, lines.count)), color: Theme.accent, height: 5)
                        Text("\(games.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 28, alignment: .trailing)
                        Text(rate.percentString(digits: 0)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.winrateColor(rate))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .cardStyle(padding: 16)
    }
}

// MARK: - Matchups (lane matchup browser + German guide)

struct MatchupsView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var champion = 0
    @ViewState private var role: Role? = .middle
    @ViewState private var enemy = 0
    @ViewState private var guideReady = 0

    var body: some View {
        let me = champion == 0 ? defaultChampion : champion
        let lane = role ?? .middle
        let counters = app.staticData.counters(of: me, role: lane)
        let selectedEnemy = enemy == 0 ? (counters.first?.championId ?? 0) : enemy
        Page(spacing: 16) {
            PageHeader("Matchups", icon: "figure.fencing", subtitle: "Lane-Matchups aus der täglichen Pipeline – mit deutschem 4-Punkte-Guide.") {
                if app.staticData.usingSampleData { SampleDataBadge() }
            }
            HStack(spacing: 10) {
                DropdownChip(label: "Champion", options: app.gameData.sortedChampions.map { ($0.id, $0.name) },
                             selection: Binding(get: { me }, set: { champion = $0; enemy = 0 }))
                RoleFilter(selection: Binding(get: { role }, set: { role = $0 ?? .middle; enemy = 0 }))
                Spacer()
                if let block = app.staticData.counterpicks?.block(championId: me, role: lane) {
                    Text("\(block.games.groupedString) Spiele · \(block.winrate.percentString()) Siegrate")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            if counters.isEmpty {
                EmptyStateView(icon: "figure.fencing", title: "Keine Matchup-Daten",
                               message: "Für \(app.gameData.championName(me)) auf \(lane.displayName) gibt es in diesem Patch zu wenige Spiele.")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        MatchupList(title: "Schwer gegen", icon: "exclamationmark.shield", entries: Array(counters.filter { $0.delta > 0 }.prefix(8)),
                                    invert: true, selected: selectedEnemy) { enemy = $0 }
                        MatchupList(title: "Gut gegen", icon: "checkmark.shield", entries: Array(counters.filter { $0.delta < 0 }.reversed().prefix(8)),
                                    invert: true, selected: selectedEnemy) { enemy = $0 }
                    }
                    .frame(width: 330)
                    MatchupDetail(me: me, enemy: selectedEnemy, role: lane,
                                  entry: counters.first { $0.championId == selectedEnemy }, refresh: guideReady)
                }
            }
        }
        .task(id: "\(me)-\(selectedEnemyKey)") {
            _ = await app.gameData.detail(me)
            let target = enemy == 0 ? app.staticData.counters(of: me, role: role ?? .middle).first?.championId ?? 0 : enemy
            if target > 0 { _ = await app.gameData.detail(target) }
            guideReady += 1
        }
    }

    private var selectedEnemyKey: Int { enemy }

    private var defaultChampion: Int {
        if let played = app.matches.compactMap({ $0.local }).first(where: { $0.role == (role ?? .middle) })?.championId { return played }
        let lane = (role ?? .middle).rawValue
        return app.staticData.counterpicks?.champions.first { $0.value[lane] != nil }.flatMap { Int($0.key) } ?? 103
    }
}

private struct MatchupList: View {
    @Environment(AppModel.self) private var app
    let title: String
    let icon: String
    let entries: [CounterEntry]
    var invert = false
    let selected: Int
    let pick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title, icon: icon)
            if entries.isEmpty {
                Text("Keine deutlichen Matchups.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(entries) { entry in
                // `delta` is the counter's advantage; from your point of view it's the inverse.
                let mine = invert ? -entry.delta : entry.delta
                Button { pick(entry.championId) } label: {
                    HStack(spacing: 9) {
                        ChampionIcon(id: entry.championId, size: 28, radius: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(app.gameData.championName(entry.championId)).font(.system(size: 13, weight: .medium))
                            Text("\(entry.games.groupedString) Spiele").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Text(mine.signedPercentString()).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.deltaColor(mine))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(selected == entry.championId ? Theme.accentSoft : .clear, in: .rect(cornerRadius: 7))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle(padding: 14)
    }
}

private struct MatchupDetail: View {
    @Environment(AppModel.self) private var app
    let me: Int
    let enemy: Int
    let role: Role
    let entry: CounterEntry?
    let refresh: Int

    var body: some View {
        let mine = entry.map { -$0.delta }
        let guide = refresh >= 0 ? app.champSelect.guide(my: me, enemy: enemy, role: role) : nil
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                HStack(spacing: 0) {
                    SplashArt(championId: me, style: .centered).overlay(LinearGradient(colors: [.clear, Theme.card], startPoint: .center, endPoint: .trailing))
                    SplashArt(championId: enemy, style: .centered).overlay(LinearGradient(colors: [Theme.card, .clear], startPoint: .leading, endPoint: .center))
                }
                .opacity(0.55)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.gameData.championName(me)).font(.system(size: 22, weight: .bold))
                        Text(role.displayName).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(mine.map { $0.signedPercentString() } ?? "–").font(.system(size: 26, weight: .bold).monospacedDigit())
                            .foregroundStyle(mine.map { Theme.deltaColor($0) } ?? Theme.textSecondary)
                        Text("Lane-Siegrate vs. Erwartung").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(app.gameData.championName(enemy)).font(.system(size: 22, weight: .bold))
                        Text("Gegner").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 120)
            .clipShape(.rect(cornerRadius: 10))

            if let entry {
                HStack(spacing: 10) {
                    LabeledValue(label: "Spiele", value: entry.games.groupedString)
                    LabeledValue(label: "Siegrate", value: (1 - entry.winrate).percentString())
                    LabeledValue(label: "Gold @15", value: entry.goldDiff15.map { signed(-$0, digits: 0) } ?? "–")
                    LabeledValue(label: "CS @15", value: entry.csDiff15.map { signed(-$0, digits: 1) } ?? "–")
                    LabeledValue(label: "Gegner-Lane-Kill-Rate", value: entry.laneKillRate.map { $0.percentString(digits: 0) } ?? "–")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Matchup-Guide").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let guide { Pill(text: guide.difficulty, color: Theme.gold) }
                }
                if let guide {
                    ForEach(guide.points) { point in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.title).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
                            Text(point.text).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Guide wird aus den Champion-Daten erstellt …").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private func signed(_ value: Double, digits: Int) -> String {
        String(format: "%+.\(digits)f", locale: .riftsight, value)
    }
}
