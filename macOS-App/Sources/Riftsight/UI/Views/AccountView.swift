import RiftsightCore
import SwiftUI

/// One linked account: rank, LP history and (for the logged-in account) recent games.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    let puuid: String
    @ViewState private var confirmRemove = false

    var body: some View {
        let account = app.linkedAccounts.first { $0.puuid == puuid }
        let history = app.lpHistory(puuid)
        Page(spacing: 16) {
            if let account {
                header(account)
                HStack(alignment: .top, spacing: 16) {
                    rankCard(account)
                        .frame(width: 300)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("LP-Verlauf", icon: "chart.xyaxis.line") {
                            if let first = history.first, let last = history.last {
                                let diff = last.ladderPoints - first.ladderPoints
                                Text("\(diff >= 0 ? "+" : "−")\(abs(diff)) LP seit \(first.date.formatted(.dateTime.day().month(.abbreviated).locale(.riftsight)))")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(diff >= 0 ? Theme.win : Theme.loss)
                            }
                        }
                        LPHistoryChart(points: history)
                            .frame(height: 190)
                    }
                    .cardStyle(padding: 16)
                }
                if isCurrent {
                    recentGames
                } else {
                    Card {
                        Label("Match-Historie gibt es nur für das gerade im Client eingeloggte Konto. Melde dich mit \(account.gameName) an, damit Rang und Spiele aktualisiert werden.",
                              systemImage: "info.circle")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                EmptyStateView(icon: "person.crop.circle.badge.questionmark", title: "Konto nicht gefunden",
                               message: "Dieses Konto ist nicht mehr verknüpft.")
            }
        }
        .confirmationDialog("Konto entfernen?", isPresented: $confirmRemove) {
            Button("Entfernen", role: .destructive) {
                app.accounts.remove(puuid)
                app.router.go(.dashboard)
            }
        } message: {
            Text("Das Konto und sein lokal gespeicherter LP-Verlauf werden aus Riftsight entfernt. Dein Riot-Konto bleibt unberührt.")
        }
    }

    private var isCurrent: Bool { puuid == (app.lcu.summoner?.puuid ?? DemoData.localPuuid) }

    private func header(_ account: LinkedAccount) -> some View {
        HStack(spacing: 16) {
            ProfileIcon(id: account.profileIconId, size: 72)
                .overlay(alignment: .bottom) {
                    Text("\(account.level)").font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Theme.window, in: .capsule).offset(y: 8)
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(account.gameName).font(.system(size: 26, weight: .bold))
                    Text("#\(account.tagLine)").font(.system(size: 16)).foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 8) {
                    Pill(text: account.region, color: Theme.textSecondary)
                    if isCurrent { Pill(text: "Aktiv im Client", color: Theme.win, icon: "checkmark.circle.fill") }
                    Text("Zuletzt gesehen \(account.lastSeen.relativeGerman)").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            if !isCurrent && !app.showsDemo {
                GhostButton(title: "Konto entfernen", icon: "trash") { confirmRemove = true }
            }
        }
    }

    private func rankCard(_ account: LinkedAccount) -> some View {
        let games = (account.wins ?? 0) + (account.losses ?? 0)
        let winrate = games == 0 ? 0 : Double(account.wins ?? 0) / Double(games)
        return VStack(alignment: .leading, spacing: 12) {
            Text("SOLO/DUO").sectionLabelStyle()
            HStack(spacing: 12) {
                RankEmblem(tier: account.rankTier, size: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.rankTier == .unranked ? "Ungewertet"
                         : (account.rankTier.displayName + (account.rankTier.isApex ? "" : " \(account.soloDivision ?? "")")).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                    if account.rankTier != .unranked {
                        Text("\(account.soloLP ?? 0) LP").font(.system(size: 18)).foregroundStyle(Color(hex: 0x8FD3FF))
                    }
                }
            }
            if games > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(account.wins ?? 0) Siege · \(account.losses ?? 0) Niederlagen").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(winrate.percentString(digits: 1)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.winrateColor(winrate))
                    }
                    ProgressBar(value: winrate, color: Theme.win, track: Theme.loss.opacity(0.55), height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private var recentGames: some View {
        let lines = MatchLine.lines(app.matches)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Letzte Spiele", icon: "list.bullet.rectangle") {
                Button("Data Lens öffnen") { app.router.go(.dataLens) }.buttonStyle(.link).font(.system(size: 12))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(headlineSeries(lines).prefix(4)) { StatTile(series: $0) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 6) {
                ForEach(lines.prefix(10)) { MatchRow(line: $0) }
            }
        }
    }
}

/// LP history as an area chart with tier/division gridlines.
struct LPHistoryChart: View {
    let points: [LPPoint]

    var body: some View {
        GeometryReader { proxy in
            let values = points.map { Double($0.ladderPoints) }
            if values.count < 2 {
                Text("Noch zu wenig Daten – der Verlauf füllt sich mit jedem gewerteten Spiel.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let low = (values.min() ?? 0) - 25
                let high = (values.max() ?? 1) + 25
                let size = CGSize(width: proxy.size.width - 64, height: proxy.size.height - 18)
                let mapped = values.enumerated().map { index, value in
                    CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                            y: size.height * (1 - CGFloat((value - low) / max(1, high - low))))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(gridLines(low: low, high: high), id: \.value) { line in
                        let y = size.height * (1 - CGFloat((Double(line.value) - low) / max(1, high - low)))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: line.major ? [] : [3, 4]))
                        Text(line.label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.textTertiary)
                            .position(x: size.width + 34, y: y)
                    }
                    Path { path in
                        path.move(to: CGPoint(x: mapped[0].x, y: size.height))
                        mapped.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: mapped[mapped.count - 1].x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: mapped[0])
                        mapped.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    Circle().fill(Theme.accent).frame(width: 7, height: 7).position(mapped[mapped.count - 1])
                    HStack {
                        Text(points[0].date.formatted(.dateTime.day().month(.abbreviated).locale(.riftsight)))
                        Spacer()
                        Text("Heute")
                    }
                    .font(.system(size: 9.5)).foregroundStyle(Theme.textTertiary)
                    .frame(width: size.width)
                    .offset(y: size.height + 5)
                }
            }
        }
    }

    private struct GridLine { let value: Int; let label: String; let major: Bool }

    private func gridLines(low: Double, high: Double) -> [GridLine] {
        let tiers: [RankTier] = [.iron, .bronze, .silver, .gold, .platinum, .emerald, .diamond]
        var lines: [GridLine] = []
        if high - low > 600 {
            for (index, tier) in tiers.enumerated() {
                let value = index * 400
                if Double(value) > low && Double(value) < high { lines.append(GridLine(value: value, label: tier.displayName, major: true)) }
            }
        } else {
            for value in stride(from: 0, through: 2800, by: 100) where Double(value) > low && Double(value) < high {
                let tier = tiers[min(tiers.count - 1, value / 400)]
                let division = ["IV", "III", "II", "I"][(value % 400) / 100]
                lines.append(GridLine(value: value, label: "\(tier.displayName) \(division)", major: value % 400 == 0))
            }
        }
        // Apex: one line per 200 LP above Master.
        for value in stride(from: 2800, through: Int(high), by: 200) where Double(value) > low {
            lines.append(GridLine(value: value, label: value == 2800 ? "Meister" : "\(value - 2800) LP", major: value == 2800))
        }
        return lines
    }
}
