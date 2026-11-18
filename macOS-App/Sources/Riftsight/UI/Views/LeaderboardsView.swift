import RiftsightCore
import SwiftUI

/// Apex ladder per region (from the pipeline's leaderboard.json).
struct LeaderboardsView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var platform = ""
    @ViewState private var query = ""
    @ViewState private var tierFilter = "ALL"

    var body: some View {
        let platforms = app.staticData.leaderboard?.platforms.keys.sorted() ?? []
        let selected = platform.isEmpty ? (platforms.first { Platform(lenient: $0)?.shortLabel == app.region } ?? platforms.first ?? "") : platform
        let entries = filtered(app.staticData.leaderboard?.platforms[selected] ?? [])
        Page(spacing: 14) {
            PageHeader("Ranglisten", icon: "trophy.fill", subtitle: "Die besten Spieler jeder Region – täglich aus der Pipeline.") {
                if app.staticData.usingSampleData { SampleDataBadge() }
            }
            HStack(spacing: 10) {
                SegmentedPills(options: platforms.map { ($0, Platform(lenient: $0)?.shortLabel ?? $0) },
                               selection: Binding(get: { selected }, set: { platform = $0 }))
                DropdownChip(label: "Tier", options: [("ALL", "Alle"), ("CHALLENGER", "Herausforderer"), ("GRANDMASTER", "Großmeister"), ("MASTER", "Meister")],
                             selection: $tierFilter)
                Spacer()
                SearchField(text: $query, placeholder: "Riot ID suchen", width: 220)
            }
            if entries.isEmpty {
                EmptyStateView(icon: "trophy", title: "Keine Einträge", message: "Für diese Auswahl gibt es keine Ranglisten-Daten.")
            } else {
                VStack(spacing: 0) {
                    LeaderboardHeaderRow()
                    ForEach(entries) { entry in
                        LeaderboardRow(entry: entry)
                        Divider().overlay(Theme.border.opacity(0.6))
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
            }
        }
    }

    private func filtered(_ entries: [LeaderboardEntry]) -> [LeaderboardEntry] {
        entries.filter { entry in
            (tierFilter == "ALL" || entry.tier == tierFilter)
                && (query.isEmpty || entry.riotId.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.rank < $1.rank }
    }
}

private struct LeaderboardHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("#").frame(width: 44)
            Text("SPIELER").frame(maxWidth: .infinity, alignment: .leading)
            Text("RANG").frame(width: 190, alignment: .leading)
            Text("SIEGE / NIEDERL.").frame(width: 200, alignment: .leading)
            Text("TOP-CHAMPIONS").frame(width: 130, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry

    var body: some View {
        let tier = RankTier(lenient: entry.tier)
        let parts = entry.riotId.components(separatedBy: "#")
        HStack(spacing: 12) {
            Text("\(entry.rank)").font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(entry.rank <= 3 ? Theme.gold : Theme.textSecondary)
                .frame(width: 44)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.first ?? entry.riotId).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                if parts.count > 1 { Text("#\(parts[1])").font(.system(size: 11)).foregroundStyle(Theme.textTertiary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                RankEmblem(tier: tier, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tier.displayName).font(.system(size: 11.5, weight: .semibold))
                    Text("\(entry.lp.groupedString) LP").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0x8FD3FF))
                }
            }
            .frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(entry.wins)S \(entry.losses)N").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(entry.winrate.percentString(digits: 1)).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.winrateColor(entry.winrate))
                }
                ProgressBar(value: entry.winrate, color: Theme.win, track: Theme.loss.opacity(0.5), height: 4)
            }
            .frame(width: 200)
            HStack(spacing: 4) {
                ForEach(entry.topChampionIds.prefix(3), id: \.self) { ChampionIcon(id: $0, size: 28, radius: 6) }
            }
            .frame(width: 130, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}
