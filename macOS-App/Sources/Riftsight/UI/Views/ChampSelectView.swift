import RiftsightCore
import SwiftUI

/// Champ Select assistant: draft win probability, lane assignment, runes, items, counters and matchup guide.
struct ChampSelectView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.champSelect!
        if model.draft == nil {
            Page {
                PageHeader("Champ Select", icon: "sparkles")
                EmptyStateView(icon: "sparkles", title: "Kein Champ Select aktiv",
                               message: "Sobald du im Client in die Championauswahl kommst, erscheint hier der Draft-Assistent.")
            }
        } else {
            VStack(spacing: 0) {
                DraftHeader(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                Divider().overlay(Theme.border)
                HStack(spacing: 0) {
                    BuildSidebar(model: model)
                        .frame(width: 300)
                    Divider().overlay(Theme.border)
                    RunesColumn(model: model)
                        .frame(maxWidth: .infinity)
                    Divider().overlay(Theme.border)
                    ItemsColumn(model: model)
                        .frame(width: 262)
                }
            }
            .overlay(alignment: .trailing) {
                if model.showCounterDrawer {
                    CounterDrawer(model: model)
                        .transition(.move(edge: .trailing))
                }
            }
            .overlay(alignment: .bottom) {
                if let message = model.actionMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.cardRaised, in: .capsule)
                        .overlay(Capsule().strokeBorder(Theme.border))
                        .padding(.bottom, 16)
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(3.5))
                            model.actionMessage = nil
                        }
                }
            }
            .animation(.snappy(duration: 0.22), value: model.showCounterDrawer)
            .task(id: prefetchKey(model)) { await model.prefetchDetails() }
        }
    }

    private func prefetchKey(_ model: ChampSelectModel) -> String {
        guard let draft = model.draft else { return "" }
        let ids = (draft.allies + draft.enemies).map { "\($0.cellId):\($0.championId)" }
        let locks = model.lockedRoles.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }
        return (ids + locks).joined(separator: ",")
    }
}

// MARK: - Draft header (bans, win probability, cards, radar)

private struct DraftHeader: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel

    var body: some View {
        let draft = model.draft!
        let allyProb = model.allyWinProbability
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                bans(draft.allyBans)
                VStack(spacing: 6) {
                    HStack {
                        Text(allyProb.percentString(digits: 0)).font(.system(size: 19, weight: .bold).monospacedDigit()).foregroundStyle(Theme.blueSideBar)
                        Spacer()
                        Text("SIEGWAHRSCHEINLICHKEIT (DRAFT)").font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text((1 - allyProb).percentString(digits: 0)).font(.system(size: 19, weight: .bold).monospacedDigit()).foregroundStyle(Theme.redSideBar)
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Theme.blueSideBar.frame(width: proxy.size.width * allyProb)
                            Theme.redSideBar
                        }
                        .clipShape(.capsule)
                    }
                    .frame(height: 7)
                }
                .frame(maxWidth: .infinity)
                .help(model.analysis?.notes.joined(separator: "\n") ?? "")
                bans(draft.enemyBans)
            }

            HStack(alignment: .top, spacing: 7) {
                ForEach(model.orderedAllies) { member in
                    DraftCard(model: model, member: member)
                }
                RadarChart(values: radarAlly, compare: radarEnemy, labels: RadarValues.axisLabels,
                           color: Theme.blueSideBar, compareColor: Theme.redSideBar, showLabels: true)
                    .frame(width: 150, height: 150)
                    .padding(.horizontal, 2)
                    .help("Blau: dein Team · Rot: Gegner")
                ForEach(model.orderedEnemies) { member in
                    DraftCard(model: model, member: member)
                }
            }
        }
    }

    private var radarAlly: [Double] {
        guard let analysis = model.analysis, let draft = model.draft else { return RadarValues.zero.axes }
        return (draft.isBlueSide ? analysis.blueRadar : analysis.redRadar).axes
    }

    private var radarEnemy: [Double] {
        guard let analysis = model.analysis, let draft = model.draft else { return RadarValues.zero.axes }
        return (draft.isBlueSide ? analysis.redRadar : analysis.blueRadar).axes
    }

    private func bans(_ ids: [Int]) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                let id = index < ids.count ? ids[index] : 0
                ZStack {
                    if id > 0 {
                        ChampionIcon(id: id, size: 34, radius: 6, grayscale: true).opacity(0.75)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.card).frame(width: 34, height: 34)
                    }
                    Rectangle().fill(Theme.textSecondary.opacity(0.7)).frame(width: 44, height: 1.5).rotationEffect(.degrees(-45))
                }
                .frame(width: 34, height: 34)
                .clipped()
                .help(id > 0 ? "Gebannt: \(app.gameData.championName(id))" : "Kein Bann")
            }
        }
    }
}

private struct DraftCard: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel
    let member: DraftMember
    @ViewState private var hovering = false

    var body: some View {
        let role = model.role(of: member)
        let entry = app.staticData.tierEntry(championId: member.championId, role: role)
        let delta = model.pickDelta(member.championId)
        VStack(spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                if member.championId > 0 {
                    SplashArt(championId: member.championId, style: .loading, alignment: .top)
                } else {
                    Theme.card
                    Image(systemName: "questionmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: -2) {
                    if let entry, member.championId > 0 {
                        Text(entry.tier.rawValue).font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.tierColor(entry.tier))
                        Text("tier").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(7)
                if member.isLocal {
                    Text("DU").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.accent, in: .rect(cornerRadius: 4))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(height: 148)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(member.isLocal ? Theme.accent : (member.isAlly ? Theme.blueSideBar.opacity(0.25) : Theme.redSideBar.opacity(0.25)), lineWidth: member.isLocal ? 2 : 1))
            .scaleEffect(hovering ? 1.015 : 1)
            .onHover { hovering = $0 }
            .help(cardHelp(entry: entry))

            HStack(spacing: 6) {
                if member.isAlly {
                    RoleIcon(role: role, size: 13)
                } else {
                    laneMenu(role: role)
                }
                if let delta, member.championId > 0 {
                    Text(String(format: "%+.2f", locale: .riftsight, delta))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(delta >= 0 ? Theme.blueSideBar : Theme.redSideBar)
                        .help("Einfluss dieses Picks auf die Draft-Siegchance (Prozentpunkte)")
                }
            }
            .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func laneMenu(role: Role?) -> some View {
        Menu {
            ForEach(Role.allCases) { option in
                Button {
                    model.lockedRoles[member.cellId] = option
                } label: {
                    if option == role { Label(option.displayName, systemImage: "checkmark") } else { Text(option.displayName) }
                }
            }
            if model.lockedRoles[member.cellId] != nil {
                Divider()
                Button("Automatisch zuordnen") { model.lockedRoles[member.cellId] = nil }
            }
        } label: {
            HStack(spacing: 3) {
                RoleIcon(role: role, size: 13, color: model.lockedRoles[member.cellId] != nil ? Theme.gold : Theme.textSecondary)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Lane manuell festlegen (überschreibt die automatische Zuordnung)")
    }

    private func cardHelp(entry: TierEntry?) -> String {
        guard member.championId > 0 else { return member.name }
        var text = "\(app.gameData.championName(member.championId)) – \(member.name)"
        if let entry {
            text += "\nWinrate \(entry.winrate.percentString()) · Pickrate \(entry.pickrate.percentString())"
        }
        return text
    }
}

// MARK: - Left column: builds + counters

private struct BuildSidebar: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel

    var body: some View {
        let build = model.build
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ChampionIcon(id: model.myChampionId, size: 36, radius: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.gameData.championName(model.myChampionId)).font(.system(size: 14, weight: .bold))
                        HStack(spacing: 4) {
                            RoleIcon(role: model.myRole, size: 11)
                            Text(model.myRole.displayName).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            if let opponent = model.laneOpponent {
                                Text("vs").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                                ChampionIcon(id: opponent.championId, size: 14, radius: 7)
                            }
                        }
                    }
                    Spacer()
                    if app.staticData.usingSampleData { SampleDataBadge() }
                }
                .padding(14)

                label("BUILDS")
                if let archetypes = build?.archetypes, !archetypes.isEmpty {
                    ForEach(archetypes) { archetype in
                        archetypeRow(archetype, selected: (model.selectedArchetype ?? archetypes.first?.name) == archetype.name)
                    }
                } else {
                    Text("Keine Build-Daten für diese Kombination.").font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(14)
                }

                label("KONTER-PICKS")
                    .overlay(alignment: .trailing) {
                        Button("Alle") { model.showCounterDrawer = true }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                            .padding(.trailing, 14)
                    }
                let counters = model.counterSuggestions.prefix(5)
                if counters.isEmpty {
                    Text(model.laneOpponent == nil ? "Noch kein Lane-Gegner gepickt." : "Keine Konter-Daten.")
                        .font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.horizontal, 14).padding(.bottom, 10)
                }
                ForEach(Array(counters), id: \.entry.championId) { suggestion in
                    CounterRow(model: model, entry: suggestion.entry, mastery: suggestion.mastery)
                }

                if let guide = model.matchupGuide {
                    label("MATCHUP-GUIDE")
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Schwierigkeit").font(Typo.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(guide.difficulty).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gold)
                        }
                        ForEach(guide.points) { point in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(point.title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
                                Text(point.text).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func label(_ text: String) -> some View {
        Text(text).sectionLabelStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func archetypeRow(_ archetype: ArchetypeStat, selected: Bool) -> some View {
        Button { model.selectedArchetype = archetype.name } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(archetype.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text("\(archetype.games.groupedString) Spiele").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(archetype.itemIds.prefix(3), id: \.self) { ItemIcon(id: $0, size: 22) }
                }
                Text(archetype.winrate.percentString(digits: 0))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.winrateColor(archetype.winrate))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Theme.winrateColor(archetype.winrate).opacity(0.12), in: .rect(cornerRadius: 4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? Theme.accent.opacity(0.12) : .clear)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.accent).frame(width: 2) } }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct CounterRow: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel
    let entry: CounterEntry
    let mastery: Int

    var body: some View {
        HStack(spacing: 10) {
            ChampionIcon(id: entry.championId, size: 30, radius: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.gameData.championName(entry.championId)).font(.system(size: 13, weight: .semibold))
                Text(mastery > 0 ? "\(mastery.compactString) Meisterschaft" : "\(entry.games.groupedString) Spiele")
                    .font(.system(size: 10.5)).foregroundStyle(mastery > 0 ? Theme.gold : Theme.textTertiary)
            }
            Spacer()
            DeltaPill(value: entry.delta, format: .percent)
            Button {
                Task { await model.hover(entry.championId) }
            } label: {
                Image(systemName: "hand.point.up.left").font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Theme.field, in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .help("Im Client hovern (nur auf Klick)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Center: runes

private struct RunesColumn: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel

    var body: some View {
        @Bindable var model = model
        let recommendation = model.runeRecommendation
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Runen").font(.system(size: 15, weight: .bold))
                    Button { Task { await model.importRunes() } } label: {
                        Label("Import", systemImage: "square.and.arrow.down").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Legt genau eine eigene Seite „\(RunePageService.pagePrefix) …“ an bzw. ersetzt nur diese.")
                    Spacer()
                    SegmentedPills(options: RuneMode.allCases.map { ($0, $0.displayName) }, selection: $model.runeMode, compact: true)
                }
                if let recommendation {
                    if !recommendation.badges.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(recommendation.badges) { badge in
                                Pill(text: badge.title, color: Theme.gold, icon: "wand.and.stars")
                                    .help(badge.detail)
                            }
                        }
                    }
                    RuneMatrix(page: recommendation.page)
                        .frame(maxWidth: .infinity)
                    Text(recommendation.source).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                } else {
                    EmptyStateView(icon: "circle.hexagonpath", title: "Keine Runen", message: "Für diesen Champion liegen keine Runendaten vor.")
                }

                if let order = model.build?.skillOrder {
                    SkillOrderView(championId: model.myChampionId, order: order)
                }
            }
            .padding(18)
        }
        .scrollIndicators(.never)
    }
}

/// Full rune trees with the selected perks highlighted (reference look).
struct RuneMatrix: View {
    @Environment(AppModel.self) private var app
    let page: RunePageStat

    var body: some View {
        let selected = Set(page.perkIds)
        HStack(alignment: .top, spacing: 44) {
            if let primary = app.gameData.perkStyles[page.primaryStyleId] {
                VStack(spacing: 14) {
                    styleHeader(primary, others: page.primaryStyleId)
                    if let keystones = primary.keystoneSlot {
                        HStack(spacing: 14) {
                            ForEach(keystones.perks, id: \.self) { id in perk(id, selected: selected.contains(id), size: 50) }
                        }
                    }
                    ForEach(Array(primary.regularSlots.enumerated()), id: \.offset) { _, slot in
                        HStack(spacing: 18) {
                            ForEach(slot.perks, id: \.self) { id in perk(id, selected: selected.contains(id), size: 36) }
                        }
                    }
                }
            }
            if let secondary = app.gameData.perkStyles[page.subStyleId] {
                VStack(spacing: 14) {
                    styleHeader(secondary, others: page.subStyleId)
                    ForEach(Array(secondary.regularSlots.enumerated()), id: \.offset) { _, slot in
                        HStack(spacing: 16) {
                            ForEach(slot.perks, id: \.self) { id in perk(id, selected: selected.contains(id), size: 32) }
                        }
                    }
                    if let shardStyle = app.gameData.perkStyles.values.first(where: { !$0.statSlots.isEmpty }) {
                        let shards = Array(page.statShards)
                        VStack(spacing: 8) {
                            ForEach(Array(shardStyle.statSlots.enumerated()), id: \.offset) { index, slot in
                                HStack(spacing: 18) {
                                    ForEach(slot.perks, id: \.self) { id in
                                        perk(id, selected: index < shards.count && shards[index] == id, size: 22)
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func styleHeader(_ style: PerkStyle, others: Int) -> some View {
        HStack(spacing: 8) {
            RemoteImage(CDN.gameData(style.iconPath), contentMode: .fit, placeholder: .clear).frame(width: 22, height: 22)
            Text(style.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func perk(_ id: Int, selected: Bool, size: CGFloat) -> some View {
        PerkIcon(id: id, size: size)
            .saturation(selected ? 1 : 0)
            .opacity(selected ? 1 : 0.32)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Theme.gold.opacity(0.85) : .clear, lineWidth: 1.5))
            .help(app.gameData.perk(id).map { "\($0.name)\n\(($0.shortDesc ?? "").strippingTags)" } ?? "")
    }
}

struct SkillOrderView: View {
    @Environment(AppModel.self) private var app
    let championId: Int
    let order: SkillOrderStat

    var body: some View {
        let detail = app.gameData.cachedDetail(championId)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Skill-Reihenfolge").font(.system(size: 14, weight: .bold))
                if let games = order.games { Text("\(games.groupedString) Spiele").font(Typo.caption).foregroundStyle(Theme.textTertiary) }
                if let wr = order.winrate { Text(wr.percentString()).font(Typo.caption).foregroundStyle(Theme.winrateColor(wr)) }
            }
            HStack(spacing: 8) {
                ForEach(Array(order.maxOrder.enumerated()), id: \.offset) { index, key in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textTertiary) }
                    HStack(spacing: 6) {
                        RemoteImage(CDN.gameData(detail?.spell(key)?.abilityIconPath))
                            .frame(width: 28, height: 28).clipShape(.rect(cornerRadius: 5))
                        Text(key).font(.system(size: 13, weight: .bold))
                    }
                    .help(detail?.spell(key)?.name ?? key)
                }
            }
            if let sequence = order.sequence, !sequence.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(sequence.prefix(18).enumerated()), id: \.offset) { index, key in
                        VStack(spacing: 2) {
                            Text("\(index + 1)").font(.system(size: 8.5)).foregroundStyle(Theme.textTertiary)
                            Text(key).font(.system(size: 10.5, weight: .bold))
                                .frame(width: 20, height: 20)
                                .background(key == "R" ? Theme.gold.opacity(0.25) : Theme.field, in: .rect(cornerRadius: 4))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Right column: summoners + items

private struct ItemsColumn: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel

    var body: some View {
        let build = model.build
        let archetype = build?.archetypes?.first { $0.name == model.selectedArchetype } ?? build?.archetypes?.first
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header("Beschwörer") { Task { await model.importSpells() } }
                HStack(spacing: 6) {
                    ForEach(build?.summonerSpells?.ids ?? [], id: \.self) { id in
                        SpellIcon(id: id, size: 34).help(app.gameData.spell(id)?.name ?? "")
                    }
                    if let wr = build?.summonerSpells?.winrate {
                        Text(wr.percentString()).font(Typo.caption).foregroundStyle(Theme.textTertiary).padding(.leading, 4)
                    }
                }

                header("Items", action: nil)
                if build != nil && !app.staticData.isReliable(build) {
                    Label("Erst \(build?.games ?? 0) Spiele in den Daten – Empfehlung noch unsicher", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                itemRow("Start-Items", ids: build?.startingItems?.itemIds ?? [])
                itemRow("Core-Build-Reihenfolge", ids: archetype?.itemIds ?? build?.coreBuild?.itemIds ?? [], arrows: true)
                rateRow("Fertige Items", rates: build?.completedItems ?? [])
                rateRow("Situativ", rates: build?.situational ?? [])

                ForEach(model.itemGroups) { group in
                    ItemGroupView(group: group)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.never)
    }

    private func header(_ title: String, action: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .bold))
            if let action {
                Button(action: action) {
                    Label("Import", systemImage: "square.and.arrow.down").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func itemRow(_ title: String, ids: [Int], arrows: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 5) {
                ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                    if arrows && index > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                    ItemIcon(id: id, size: 32).help(app.gameData.itemName(id))
                }
            }
        }
    }

    private func rateRow(_ title: String, rates: [ItemRate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 7) {
                ForEach(rates.prefix(5)) { rate in
                    VStack(spacing: 3) {
                        ItemIcon(id: rate.itemId, size: 32)
                        Text(rate.pickrate.percentString(digits: 0)).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    .help("\(app.gameData.itemName(rate.itemId)) – Winrate \(rate.winrate.percentString())")
                }
            }
        }
    }
}

/// Situational item group with the three-part German reasoning as tooltip / popover.
struct ItemGroupView: View {
    @Environment(AppModel.self) private var app
    let group: ItemGroup
    @ViewState private var popover: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: group.kind.symbol).font(.system(size: 10.5, weight: .bold))
                Text(group.kind.title).font(.system(size: 11.5, weight: .semibold))
                Spacer()
                if group.isHighlighted {
                    Text("EMPFOHLEN").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Theme.gold)
                }
            }
            .foregroundStyle(group.isHighlighted ? Theme.gold : Theme.textSecondary)
            if let trigger = group.trigger {
                Text(trigger).font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(group.items.prefix(5)) { suggestion in
                    Button { popover = suggestion.itemId } label: {
                        ItemIcon(id: suggestion.itemId, size: 30)
                    }
                    .buttonStyle(.plain)
                    .help(tooltip(suggestion))
                    .popover(isPresented: Binding(get: { popover == suggestion.itemId }, set: { if !$0 { popover = nil } }), arrowEdge: .leading) {
                        ItemReasoningCard(itemId: suggestion.itemId, reasoning: suggestion.reasoning)
                            .environment(app)
                    }
                }
            }
        }
        .padding(10)
        .background(group.isHighlighted ? Theme.gold.opacity(0.07) : Theme.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(group.isHighlighted ? Theme.gold.opacity(0.4) : Theme.border))
    }

    private func tooltip(_ suggestion: ItemSuggestion) -> String {
        """
        \(app.gameData.itemName(suggestion.itemId))
        Wann bauen: \(suggestion.reasoning.whenToBuild)
        Warum stark: \(suggestion.reasoning.whyStrong)
        Kauf-Timing: \(suggestion.reasoning.timing)
        """
    }
}

struct ItemReasoningCard: View {
    @Environment(AppModel.self) private var app
    let itemId: Int
    let reasoning: ItemReasoning

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ItemIcon(id: itemId, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.gameData.itemName(itemId)).font(.system(size: 14, weight: .bold))
                    if let item = app.gameData.item(itemId) {
                        Text("\(item.priceTotal) Gold").font(Typo.caption).foregroundStyle(Theme.gold)
                    }
                }
            }
            reason("Wann bauen", reasoning.whenToBuild, "clock")
            reason("Warum stark", reasoning.whyStrong, "bolt")
            reason("Kauf-Timing", reasoning.timing, "cart")
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.cardRaised)
    }

    private func reason(_ title: String, _ text: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Counter drawer

private struct CounterDrawer: View {
    @Environment(AppModel.self) private var app
    let model: ChampSelectModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Konter-Picks").font(.system(size: 16, weight: .bold))
                    if let opponent = model.laneOpponent {
                        Text("gegen \(app.gameData.championName(opponent.championId)) · \(model.myRole.displayName)")
                            .font(Typo.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                IconButton(systemName: "xmark", help: "Schließen") { model.showCounterDrawer = false }
            }
            .padding(16)
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.counterSuggestions, id: \.entry.championId) { suggestion in
                        CounterRow(model: model, entry: suggestion.entry, mastery: suggestion.mastery)
                    }
                }
                .padding(.vertical, 8)
            }
            Text("Sortiert nach Winrate-Delta, Champions mit Meisterschaft leicht bevorzugt. Hover passiert nur auf Klick.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                .padding(14)
        }
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .background(Theme.cardRaised)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
        .shadow(color: .black.opacity(0.4), radius: 20, x: -6)
    }
}

// MARK: - Helpers

/// Simple wrapping layout for pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension String {
    /// Removes CommunityDragon markup like `<status>` and `@Value@`.
    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "@[^@]+@", with: "…", options: .regularExpression)
    }
}
