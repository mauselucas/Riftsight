import RiftsightCore
import SwiftUI

/// Live solo-queue games of pros (from the pipeline's pro_spectate.json), launched via the client's own spectator.
struct SpectateView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var query = ""
    @ViewState private var region = "ALL"
    @ViewState private var team = "ALL"
    @ViewState private var sort = "relevant"

    var body: some View {
        let games = filtered()
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Page(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Zuschauen").font(.system(size: 22, weight: .bold))
                    Text("\(games.count) Live-Spiele").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    if app.staticData.usingSampleData { SampleDataBadge() }
                    Spacer()
                    Text("Live-SoloQ-Spiele von Pros und bekannten Streamern – über den Zuschauermodus des Clients.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 10) {
                    SearchField(text: $query, placeholder: "Spieler oder Champion suchen", width: 250)
                    DropdownChip(label: "Region", options: regionOptions, selection: $region)
                    DropdownChip(options: teamOptions, selection: $team)
                    Spacer()
                    DropdownChip(label: "Sortierung", options: [("relevant", "Relevanz"), ("time", "Spielzeit"), ("lp", "Ø LP")], selection: $sort)
                }
                Text("Zuschauen funktioniert nur für Spiele in deiner Client-Region (\(app.region)) und erst ca. 3 Minuten nach Spielstart. Riftsight startet nur den Zuschauermodus des Clients.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                if games.isEmpty {
                    EmptyStateView(icon: "display", title: "Keine Live-Spiele", message: "Gerade spielt niemand aus der Pro-Liste – später erneut versuchen.")
                }
                ForEach(games) { game in
                    SpectateRow(game: game, now: context.date)
                }
            }
        }
    }

    private var allGames: [ProGame] { app.staticData.proSpectate?.games ?? [] }

    private var regionOptions: [(String, String)] {
        [("ALL", "Alle")] + Set(allGames.map(\.platformId)).sorted().map { ($0, Platform(lenient: $0)?.shortLabel ?? $0) }
    }

    private var teamOptions: [(String, String)] {
        let teams = Set(allGames.flatMap { $0.participants.compactMap(\.proTeam) }).sorted()
        return [("ALL", "Jedes Team")] + teams.map { ($0, $0) }
    }

    private func filtered() -> [ProGame] {
        var games = allGames
        if region != "ALL" { games = games.filter { $0.platformId == region } }
        if team != "ALL" { games = games.filter { $0.participants.contains { $0.proTeam == team } } }
        if !query.isEmpty {
            let q = query.lowercased()
            games = games.filter { game in
                game.participants.contains {
                    $0.displayName.lowercased().contains(q) || app.gameData.championName($0.championId).lowercased().contains(q)
                }
            }
        }
        switch sort {
        case "time": games.sort { $0.gameStartTime < $1.gameStartTime }
        case "lp": games.sort { $0.averageLp > $1.averageLp }
        default:
            // Watchable (own-region) games first, then by how many known players are in them.
            let home = Platform(lenient: app.region)?.rawValue ?? app.region
            games.sort { ($0.platformId == home ? 1 : 0, $0.knownPlayers, $0.averageLp) > ($1.platformId == home ? 1 : 0, $1.knownPlayers, $1.averageLp) }
        }
        return games
    }
}

private struct SpectateRow: View {
    @Environment(AppModel.self) private var app
    let game: ProGame
    let now: Date

    var body: some View {
        let tier = RankTier(lenient: game.averageTier)
        let elapsed = max(0, now.timeIntervalSince(game.startDate))
        let platform = Platform(lenient: game.platformId)?.shortLabel ?? game.platformId
        let sameRegion = platform == app.region || (Platform(lenient: app.region)?.shortLabel == platform)
        let ready = elapsed >= 180
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(Theme.loss).frame(width: 7, height: 7)
                    Text(formatClock(elapsed)).font(.system(size: 16, weight: .semibold).monospacedDigit())
                    Text(platform).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                }
                HStack(spacing: 8) {
                    RankEmblem(tier: tier, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DURCHSCHNITT").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                        Text(tier.displayName.uppercased()).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(game.averageLp.groupedString) LP").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x6FC3FF))
                    }
                }
            }
            .frame(width: 170, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(game.blue) { SpectateTile(participant: $0) }
            }
            Text("vs").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 30)
            HStack(spacing: 4) {
                ForEach(game.red) { SpectateTile(participant: $0) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(game.knownPlayers) bekannte Spieler").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                if sameRegion {
                    Button {
                        Task { await watch() }
                    } label: {
                        Label(ready ? "Zuschauen" : "ab 3:00", systemImage: "eye")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(ready ? Theme.accent : Theme.field, in: .rect(cornerRadius: 6))
                            .foregroundStyle(ready ? .white : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!ready)
                    .help(ready ? "Startet den Zuschauermodus im League-Client" : "Riot gibt Spiele erst ca. 180 s nach Start frei")
                } else {
                    Text("Andere Region\n(nur Info)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.trailing)
                        .help("Der Client kann nur Spiele der eigenen Region zuschauen")
                }
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                .fill(Theme.rankColor(tier)).frame(width: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }

    private func watch() async {
        guard app.lcu.isConnected else {
            let name = game.participants.first(where: \.isKnown)?.displayName ?? "dem Spiel"
            app.toast = "Demo: Der Client würde jetzt \(name) zuschauen."
            return
        }
        guard let target = game.participants.first(where: { $0.isKnown && $0.puuid != nil }) ?? game.participants.first(where: { $0.puuid != nil }),
              let puuid = target.puuid else {
            app.toast = "Für dieses Spiel fehlt eine PUUID – Zuschauen nicht möglich."
            return
        }
        do {
            try await app.lcu.launchSpectate(puuid: puuid, gameId: game.gameId)
            app.toast = "Zuschauermodus wird gestartet …"
        } catch {
            app.toast = "Zuschauen fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct SpectateTile: View {
    @Environment(AppModel.self) private var app
    let participant: ProParticipant

    var body: some View {
        ZStack(alignment: .bottom) {
            SplashArt(championId: participant.championId, style: .loading, alignment: .top)
                .saturation(participant.isKnown ? 1 : 0)
                .opacity(participant.isKnown ? 1 : 0.4)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 3) {
                if participant.isKnown, let team = participant.proTeam {
                    Text(String(team.prefix(3)).uppercased()).font(.system(size: 8.5, weight: .heavy))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 3))
                }
                Text(participant.displayName).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(participant.isKnown ? .white : Theme.textTertiary)
            }
            .padding(.bottom, 5)
            .padding(.horizontal, 3)
        }
        .overlay(alignment: .topLeading) {
            RoleIcon(role: participant.role.flatMap { Role(flexible: $0) }, size: 11, color: .white)
                .padding(3).background(.black.opacity(0.55), in: .rect(cornerRadius: 3)).padding(4)
        }
        .frame(width: 66, height: 112)
        .clipShape(.rect(cornerRadius: 5))
        .help("\(participant.displayName) – \(app.gameData.championName(participant.championId))\(participant.tier.map { " · \($0) \(participant.lp ?? 0) LP" } ?? "")")
    }
}
