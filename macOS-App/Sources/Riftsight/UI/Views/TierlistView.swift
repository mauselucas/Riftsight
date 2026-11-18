import RiftsightCore
import SwiftUI

enum TierMode: String, CaseIterable, Hashable {
    case ranked, aram, arena, duo
    var title: String {
        switch self {
        case .ranked: "Ranked"
        case .aram: "ARAM"
        case .arena: "Arena"
        case .duo: "Duo"
        }
    }
}

enum TierSort: Hashable { case rank, tier, winrate, pickrate, games, placement }

struct TierlistView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var mode: TierMode = .ranked
    @ViewState private var role: Role?
    @ViewState private var rank = "EMERALD_PLUS"
    @ViewState private var platform = "ALL"
    @ViewState private var offMeta = false
    @ViewState private var query = ""
    @ViewState private var sort: TierSort = .rank
    @ViewState private var ascending = true

    var body: some View {
        let entries = filtered()
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Tierlist", icon: "chart.bar.fill",
                       subtitle: "Champion-Rankings der täglichen Pipeline\nnach Rolle, Rang, Region und Modus.") {
                BoxedTabs(options: TierMode.allCases.map { ($0, $0.title) }, selection: $mode)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)

            HStack(spacing: 10) {
                if mode == .ranked || mode == .duo {
                    RoleFilter(selection: $role)
                }
                DropdownChip(options: rankOptions, selection: $rank, icon: "shield.lefthalf.filled")
                DropdownChip(options: platformOptions, selection: $platform, icon: "globe")
                DropdownChip(options: [(app.staticData.dataPatch ?? app.gameData.patch, app.staticData.dataPatch ?? app.gameData.patch)],
                             selection: .constant(app.staticData.dataPatch ?? app.gameData.patch))
                if mode == .ranked {
                    Toggle(isOn: $offMeta) {
                        Text("OFF-META").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Zeigt auch Champion-Rollen mit weniger als 10 % Lane-Anteil")
                }
                if app.staticData.usingSampleData { SampleDataBadge() }
                Spacer()
                SearchField(text: $query, placeholder: "Champion suchen", width: 230)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)

            TierTable(entries: entries, mode: mode, sort: $sort, ascending: $ascending)
                .padding(.horizontal, 26)
        }
    }

    private var rankOptions: [(String, String)] {
        let labels = ["EMERALD_PLUS": "SMARAGD+", "DIAMOND_PLUS": "DIAMANT+", "MASTER_PLUS": "MEISTER+"]
        let ranks = app.staticData.availableRanks.isEmpty ? ["EMERALD_PLUS"] : app.staticData.availableRanks
        return ranks.map { ($0, labels[$0] ?? $0) }
    }

    private var platformOptions: [(String, String)] {
        let platforms = app.staticData.availablePlatforms.isEmpty ? ["ALL"] : app.staticData.availablePlatforms
        return platforms.sorted { $0 == "ALL" ? true : ($1 == "ALL" ? false : $0 < $1) }
            .map { ($0, $0 == "ALL" ? "ALLE REGIONEN" : (Platform(lenient: $0)?.shortLabel ?? $0)) }
    }

    private func filtered() -> [TierEntry] {
        var entries = app.staticData.tierEntries(mode: mode.rawValue, rank: rank, platform: platform)
        if let role, mode == .ranked || mode == .duo { entries = entries.filter { $0.role == role.rawValue } }
        if mode == .ranked && !offMeta { entries = entries.filter { ($0.laneShare ?? 1) >= 0.1 } }
        if !query.isEmpty {
            let q = query.lowercased()
            entries = entries.filter {
                app.gameData.championName($0.championId).lowercased().contains(q)
                    || ($0.partnerChampionId.map { app.gameData.championName($0).lowercased().contains(q) } ?? false)
            }
        }
        let sorted: [TierEntry]
        switch sort {
        case .rank, .tier: sorted = entries.sorted { ($0.score ?? 0, $1.rank) > ($1.score ?? 0, $0.rank) }
        case .winrate: sorted = entries.sorted { $0.winrate > $1.winrate }
        case .pickrate: sorted = entries.sorted { $0.pickrate > $1.pickrate }
        case .games: sorted = entries.sorted { $0.games > $1.games }
        case .placement: sorted = entries.sorted { ($0.avgPlacement ?? 9) < ($1.avgPlacement ?? 9) }
        }
        // `sorted` is always best-first; the header arrow flips it.
        return ascending ? sorted : sorted.reversed()
    }
}

/// "✱ top jungle mid bot support" icon segmented control.
struct RoleFilter: View {
    @Binding var selection: Role?

    var body: some View {
        HStack(spacing: 2) {
            button(nil)
            ForEach(Role.allCases) { button($0) }
        }
        .padding(2)
        .background(Theme.field, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
    }

    private func button(_ role: Role?) -> some View {
        let selected = selection == role
        return Button { selection = role } label: {
            Group {
                if let role {
                    RoleIcon(role: role, size: 15, color: selected ? .white : Theme.textSecondary)
                } else {
                    Image(systemName: "asterisk").font(.system(size: 12, weight: .bold)).foregroundStyle(selected ? .white : Theme.textSecondary)
                }
            }
            .frame(width: 30, height: 26)
            .background(selected ? Theme.accent : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(role?.displayName ?? "Alle Rollen")
    }
}

private struct TierTable: View {
    @Environment(AppModel.self) private var app
    let entries: [TierEntry]
    let mode: TierMode
    @Binding var sort: TierSort
    @Binding var ascending: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header("RANG", .rank, width: 70)
                Text("CHAMPION").frame(maxWidth: .infinity, alignment: .leading)
                if mode == .ranked { Text("LANE").frame(width: 110) }
                if mode == .duo { Text("PARTNER").frame(width: 200, alignment: .leading) }
                header("TIER", .tier, width: 110)
                header(mode == .arena ? "1. PLATZ" : "WINRATE", .winrate, width: 130)
                if mode == .arena {
                    header("Ø PLATZ", .placement, width: 110)
                    Text("TOP 4").frame(width: 100)
                }
                header("PICKRATE", .pickrate, width: 120)
                header("SPIELE", .games, width: 120)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(height: 34)
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        TierRow(entry: entry, mode: mode, position: index + 1)
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)
        }
        .background(Theme.card.opacity(0.55), in: .rect(topLeadingRadius: 12, topTrailingRadius: 12))
    }

    private func header(_ title: String, _ key: TierSort, width: CGFloat) -> some View {
        Button {
            if sort == key { ascending.toggle() } else { sort = key; ascending = true }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if sort == key {
                    Image(systemName: ascending ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.system(size: 7))
                }
            }
            .frame(width: width)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct TierRow: View {
    @Environment(AppModel.self) private var app
    let entry: TierEntry
    let mode: TierMode
    let position: Int
    @ViewState private var hovering = false

    var body: some View {
        Button {
            app.router.go(.champion(entry.championId, entry.roleValue))
        } label: {
            HStack(spacing: 0) {
                Text("\(position)").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 70)
                HStack(spacing: 12) {
                    ChampionBanner(championId: entry.championId)
                    Text(app.gameData.championName(entry.championId)).font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if mode == .ranked {
                    VStack(spacing: 2) {
                        RoleIcon(role: entry.roleValue, size: 15)
                        Text((entry.laneShare ?? 1).percentString()).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(width: 110)
                }
                if mode == .duo, let partner = entry.partnerChampionId {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
                        ChampionBanner(championId: partner, width: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.gameData.championName(partner)).font(.system(size: 13, weight: .semibold))
                            Text(Role(rawValue: entry.partnerRole ?? "")?.displayName ?? "").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                }
                Text(entry.tier.rawValue)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.tierColor(entry.tier))
                    .frame(width: 110)
                    .help(entry.score.map { String(format: "Tier-Score %.1f / 100", locale: .riftsight, $0) } ?? "")
                VStack(spacing: 1) {
                    Text(entry.winrate.percentString()).font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(entry.winrate < 0.495 && mode != .arena ? Theme.textSecondary : Theme.text)
                    if let delta = entry.winrateDelta {
                        Text(delta.signedPercentString()).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.deltaColor(delta))
                    }
                }
                .frame(width: 130)
                if mode == .arena {
                    Text(entry.avgPlacement.map { String(format: "%.2f", locale: .riftsight, $0) } ?? "–").font(.system(size: 14, weight: .semibold).monospacedDigit()).frame(width: 110)
                    Text(entry.top4Rate.map { $0.percentString(digits: 0) } ?? "–").font(.system(size: 13.5).monospacedDigit()).frame(width: 100)
                }
                Text(entry.pickrate.percentString()).font(.system(size: 14, weight: .medium).monospacedDigit()).frame(width: 120)
                Text(entry.games.groupedString).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 120)
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(hovering ? Theme.hover : (position.isMultiple(of: 2) ? Color.white.opacity(0.012) : .clear))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Wide champion crop like the reference tier list thumbnails.
struct ChampionBanner: View {
    let championId: Int
    var width: CGFloat = 60
    var height: CGFloat = 34

    var body: some View {
        SplashArt(championId: championId, style: .centered, alignment: .center)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 5))
    }
}

// MARK: - Champion detail (offline champion browser)

struct ChampionDetailView: View {
    @Environment(AppModel.self) private var app
    let championId: Int
    let initialRole: Role?
    @ViewState private var role: Role?
    @ViewState private var vsChampion: Int?

    var body: some View {
        let roles = availableRoles
        let current = role ?? initialRole ?? roles.first ?? .middle
        let entry = app.staticData.tierEntry(championId: championId, role: current)
        let build = app.staticData.build(championId: championId, role: current, vs: vsChampion)
        let detail = app.gameData.cachedDetail(championId)
        Page(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                SplashArt(championId: championId, style: .splash, alignment: .top)
                    .frame(height: 230)
                    .overlay(LinearGradient(colors: [.clear, Theme.canvas], startPoint: .center, endPoint: .bottom))
                    .overlay(LinearGradient(colors: [Theme.canvas.opacity(0.9), .clear], startPoint: .leading, endPoint: .center))
                HStack(alignment: .bottom, spacing: 16) {
                    ChampionIcon(id: championId, size: 78, radius: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.gameData.championName(championId)).font(.system(size: 34, weight: .bold))
                        Text(detail?.title?.capitalized ?? "").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 6) {
                            ForEach(roles) { option in
                                Button { role = option } label: {
                                    HStack(spacing: 5) {
                                        RoleIcon(role: option, size: 12, color: option == current ? .white : Theme.textSecondary)
                                        Text(option.displayName).font(.system(size: 12, weight: .semibold))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(option == current ? Theme.accent : Theme.field, in: .rect(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                    if let entry {
                        HStack(spacing: 22) {
                            VStack(spacing: 0) {
                                Text(entry.tier.rawValue).font(.system(size: 34, weight: .heavy)).foregroundStyle(Theme.tierColor(entry.tier))
                                Text("Tier").font(Typo.caption).foregroundStyle(Theme.textSecondary)
                            }
                            LabeledValue(label: "Winrate", value: entry.winrate.percentString(), valueColor: Theme.winrateColor(entry.winrate))
                            LabeledValue(label: "Pickrate", value: entry.pickrate.percentString())
                            LabeledValue(label: "Banrate", value: entry.banrate.map { $0.percentString() } ?? "–")
                            LabeledValue(label: "Spiele", value: entry.games.groupedString)
                        }
                    }
                }
                .padding(20)
            }
            .clipShape(.rect(cornerRadius: Theme.cornerRadius))

            HStack(spacing: 10) {
                Text("Build gegen").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                DropdownChip(options: opponentOptions(current),
                             selection: Binding(get: { vsChampion ?? 0 }, set: { vsChampion = $0 == 0 ? nil : $0 }),
                             icon: "figure.fencing")
                if app.staticData.usingSampleData { SampleDataBadge() }
                Spacer()
                if let build { Text("\(build.games.groupedString) Spiele · \(build.winrate.percentString()) Winrate").font(Typo.caption).foregroundStyle(Theme.textSecondary) }
            }

            if let build {
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader("Runen", icon: "circle.hexagongrid")
                            if let runes = build.runes { RuneMatrix(page: runes).frame(maxWidth: .infinity) }
                            if let order = build.skillOrder { SkillOrderView(championId: championId, order: order) }
                        }
                    }
                    VStack(spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader("Items", icon: "bag")
                                BuildItemsList(build: build)
                            }
                        }
                        if let curve = entry?.powerCurve {
                            Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader("Power-Kurve", icon: "chart.line.uptrend.xyaxis")
                                    PowerCurveView(curve: curve)
                                }
                            }
                        }
                    }
                    .frame(width: 360)
                }
            }

            CountersSection(championId: championId, role: current)
        }
        .task { _ = await app.gameData.detail(championId) }
    }

    private func opponentOptions(_ role: Role) -> [(Int, String)] {
        let counters = app.staticData.counters(of: championId, role: role).prefix(25)
        let named: [(Int, String)] = counters.map { entry in (entry.championId, app.gameData.championName(entry.championId)) }
        return [(0, "Alle Gegner")] + named.sorted { $0.1 < $1.1 }
    }

    private var availableRoles: [Role] {
        let fromBuilds = app.staticData.matchupRunes?.roles(championId: championId) ?? []
        if !fromBuilds.isEmpty { return fromBuilds }
        return app.staticData.tierEntries().filter { $0.championId == championId }.compactMap(\.roleValue)
    }
}

struct BuildItemsList: View {
    @Environment(AppModel.self) private var app
    let build: BuildBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let spells = build.summonerSpells {
                row("Beschwörer") { ForEach(spells.ids, id: \.self) { SpellIcon(id: $0, size: 30) } }
            }
            if let start = build.startingItems {
                row("Start") { ForEach(Array(start.itemIds.enumerated()), id: \.offset) { ItemIcon(id: $0.element, size: 30).help(app.gameData.itemName($0.element)) } }
            }
            if let core = build.coreBuild {
                row("Core") {
                    ForEach(Array(core.itemIds.enumerated()), id: \.offset) { index, id in
                        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textTertiary) }
                        ItemIcon(id: id, size: 30).help(app.gameData.itemName(id))
                    }
                }
            }
            if let boots = build.boots, !boots.isEmpty {
                rates("Stiefel", boots)
            }
            if let completed = build.completedItems, !completed.isEmpty { rates("Fertige Items", completed) }
            if let situational = build.situational, !situational.isEmpty { rates("Situativ", situational) }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 5) { content() }
        }
    }

    private func rates(_ title: String, _ items: [ItemRate]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 7) {
                ForEach(items.prefix(6)) { rate in
                    VStack(spacing: 2) {
                        ItemIcon(id: rate.itemId, size: 30)
                        Text(rate.pickrate.percentString(digits: 0)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    .help("\(app.gameData.itemName(rate.itemId)) – \(rate.winrate.percentString()) Winrate")
                }
            }
        }
    }
}

struct PowerCurveView: View {
    let curve: PowerCurve

    var body: some View {
        let values = [curve.early, curve.mid, curve.late]
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(Array(zip(["Früh (<25)", "Mitte (25–32)", "Spät (>32)"], values)), id: \.0) { label, value in
                VStack(spacing: 5) {
                    Text(value.percentString()).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.winrateColor(value))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Theme.winrateColor(value), Theme.winrateColor(value).opacity(0.35)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(8, CGFloat((value - 0.40) / 0.2) * 90))
                    Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140, alignment: .bottom)
    }
}

private struct CountersSection: View {
    @Environment(AppModel.self) private var app
    let championId: Int
    let role: Role

    var body: some View {
        let counters = app.staticData.counters(of: championId, role: role)
        // counters(of: X) lists champions that do well against X → those are X's worst matchups.
        let worst = counters.filter { $0.delta > 0 }.sorted { $0.delta > $1.delta }.prefix(8)
        let best = counters.filter { $0.delta < 0 }.sorted { $0.delta < $1.delta }.prefix(8)
        HStack(alignment: .top, spacing: 16) {
            column("Beste Matchups", entries: Array(best), invert: true)
            column("Schwerste Matchups", entries: Array(worst), invert: false)
        }
    }

    private func column(_ title: String, entries: [CounterEntry], invert: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title, icon: invert ? "hand.thumbsup" : "exclamationmark.triangle")
                if entries.isEmpty {
                    Text("Keine Daten.").font(Typo.caption).foregroundStyle(Theme.textTertiary)
                }
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        ChampionIcon(id: entry.championId, size: 28, radius: 14)
                        Text(app.gameData.championName(entry.championId)).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("\(entry.games.groupedString) Spiele").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                        // Show from this champion's perspective.
                        DeltaPill(value: -entry.delta, format: .percent)
                    }
                    .contentShape(.rect)
                    .onTapGesture { app.router.go(.champion(entry.championId, role)) }
                }
            }
        }
    }
}
