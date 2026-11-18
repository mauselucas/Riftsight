import RiftsightCore
import SwiftUI

struct CollectionView: View {
    @Environment(AppModel.self) private var app
    @ViewState private var query = ""
    @ViewState private var ownership = "all"
    @ViewState private var champion = 0
    @ViewState private var skinLine = 0
    @ViewState private var rarities: Set<SkinRarity> = []
    @ViewState private var legacyFilter = "all"
    @ViewState private var grouping = "year"
    @ViewState private var sorting = "date"
    @ViewState private var cardSize = "auto"

    var body: some View {
        let inventory = app.skinInventory ?? SkinInventory()
        let allSkins = app.gameData.skins.values.filter { !$0.isBase }
        let owned = allSkins.filter { inventory.owned[$0.id] != nil }
        let shown = filter(allSkins, inventory: inventory)
        let spent = owned.reduce(0) { $0 + (inventory.prices[$1.id] ?? $1.rarityTier.estimatedRP) }
        HStack(alignment: .top, spacing: 26) {
            ScrollView {
                filters(allSkins: allSkins, inventory: inventory)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
            .frame(width: 236)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary(owned: owned.count, total: allSkins.count, spent: spent)
                    HStack(spacing: 10) {
                        Text("\(shown.count) Skins").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        if app.showsDemo { Pill(text: "Demo-Inventar", color: Theme.gold, icon: "person.crop.circle.badge.questionmark") }
                        Spacer()
                        DropdownChip(label: "Gruppe", options: [("year", "Erwerbsjahr"), ("champion", "Champion"), ("rarity", "Seltenheit"), ("none", "Keine")], selection: $grouping)
                        DropdownChip(label: "Sortierung", options: [("date", "Erwerbsdatum"), ("name", "Name"), ("rarity", "Seltenheit")], selection: $sorting)
                        DropdownChip(label: "Größe", options: [("auto", "Auto"), ("small", "Klein"), ("large", "Groß")], selection: $cardSize)
                    }
                    ForEach(groups(shown, inventory: inventory), id: \.title) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.title).font(.system(size: 16, weight: .semibold))
                            let ownedInGroup = group.skins.filter { inventory.owned[$0.id] != nil }.count
                            Text("\(ownedInGroup) / \(group.skins.count)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth, maximum: minimumWidth + 60), spacing: 12)], spacing: 12) {
                            ForEach(group.skins) { skin in
                                SkinCard(skin: skin, owned: inventory.owned[skin.id], price: inventory.prices[skin.id])
                            }
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .overlay(alignment: .topLeading) { EmptyView() }
        .task { await app.loadCollection() }
    }

    private var minimumWidth: CGFloat {
        switch cardSize {
        case "small": 120
        case "large": 200
        default: 150
        }
    }

    // MARK: Filters

    @ViewBuilder
    private func filters(allSkins: [Skin], inventory: SkinInventory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sammlung").font(.system(size: 30, weight: .bold))
                Text("Jeder Skin auf deinem Konto – und die noch fehlenden.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 8)
            Label("Filter", systemImage: "line.3.horizontal.decrease").font(.system(size: 14, weight: .semibold))
            SearchField(text: $query, placeholder: "Skin suchen")
            SegmentedPills(options: [("all", "Alle"), ("owned", "Im Besitz"), ("missing", "Fehlend")], selection: $ownership, compact: true)
            Text("CHAMPION").sectionLabelStyle()
            DropdownChip(options: [(0, "Jeder Champion")] + app.gameData.sortedChampions.map { ($0.id, $0.name) }, selection: $champion)
            Text("SKIN-LINIE").sectionLabelStyle()
            let lines = topSkinLines(allSkins)
            DropdownChip(options: [(0, "Jede Linie")] + lines.map { ($0.id, $0.name) }, selection: $skinLine)
            ForEach(lines.prefix(4)) { line in
                let skins = allSkins.filter { $0.skinLines?.contains { $0.id == line.id } ?? false }
                filterRow(title: line.name, count: "\(skins.filter { inventory.owned[$0.id] != nil }.count)/\(skins.count)", checked: skinLine == line.id) {
                    skinLine = skinLine == line.id ? 0 : line.id
                }
            }
            Text("SELTENHEIT").sectionLabelStyle()
            ForEach(SkinRarity.allCases, id: \.self) { rarity in
                let skins = allSkins.filter { $0.rarityTier == rarity }
                filterRow(title: rarity.displayName, count: "\(skins.filter { inventory.owned[$0.id] != nil }.count)/\(skins.count)",
                          checked: rarities.contains(rarity), color: Theme.rarityColor(rarity)) {
                    if rarities.contains(rarity) { rarities.remove(rarity) } else { rarities.insert(rarity) }
                }
                .opacity(skins.isEmpty ? 0.4 : 1)
            }
            Text("VERFÜGBARKEIT").sectionLabelStyle()
            let legacy = allSkins.filter { $0.isLegacy == true }
            filterRow(title: "Erhältlich", count: "\(allSkins.count - legacy.count)", checked: legacyFilter == "available") {
                legacyFilter = legacyFilter == "available" ? "all" : "available"
            }
            filterRow(title: "Legacy", count: "\(legacy.count)", checked: legacyFilter == "legacy") {
                legacyFilter = legacyFilter == "legacy" ? "all" : "legacy"
            }
        }
    }

    private func filterRow(title: String, count: String, checked: Bool, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Checkbox(isOn: checked)
                if let color { Image(systemName: "diamond.fill").font(.system(size: 9)).foregroundStyle(color) }
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer()
                Text(count).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func topSkinLines(_ skins: [Skin]) -> [SkinLine] {
        var counts: [Int: Int] = [:]
        for skin in skins { for line in skin.skinLines ?? [] { counts[line.id, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(40).compactMap { app.gameData.skinLines[$0.key] }
    }

    private func summary(owned: Int, total: Int, spent: Int) -> some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(owned)").font(.system(size: 24, weight: .semibold))
                    Text("/ \(total)").font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                }
                ProgressBar(value: Double(owned) / Double(max(1, total)), color: Color(hex: 0x8FA0FF), height: 5)
                Text("Skins im Besitz · \((Double(owned) / Double(max(1, total))).percentString(digits: 0)) komplett")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(spent.groupedString).font(.system(size: 26, weight: .semibold))
                    Text("RP").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                Text("Wert deiner Skins (Shop-Preise)").font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(20)
        .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
    }

    // MARK: Filtering + grouping

    private func filter(_ skins: [Skin], inventory: SkinInventory) -> [Skin] {
        skins.filter { skin in
            let isOwned = inventory.owned[skin.id] != nil
            if ownership == "owned" && !isOwned { return false }
            if ownership == "missing" && isOwned { return false }
            if champion != 0 && skin.championId != champion { return false }
            if skinLine != 0 && !(skin.skinLines?.contains { $0.id == skinLine } ?? false) { return false }
            if !rarities.isEmpty && !rarities.contains(skin.rarityTier) { return false }
            if legacyFilter == "legacy" && skin.isLegacy != true { return false }
            if legacyFilter == "available" && skin.isLegacy == true { return false }
            if !query.isEmpty && !skin.name.localizedCaseInsensitiveContains(query) { return false }
            return true
        }
    }

    private func groups(_ skins: [Skin], inventory: SkinInventory) -> [(title: String, skins: [Skin])] {
        let sorted = skins.sorted { a, b in
            switch sorting {
            case "name": return a.name < b.name
            case "rarity": return SkinRarity.allCases.firstIndex(of: a.rarityTier)! > SkinRarity.allCases.firstIndex(of: b.rarityTier)!
            default:
                let da = inventory.owned[a.id]?.purchased ?? .distantPast
                let db = inventory.owned[b.id]?.purchased ?? .distantPast
                return da == db ? a.name < b.name : da > db
            }
        }
        // Keep big result sets responsive.
        let capped = Array(sorted.prefix(600))
        switch grouping {
        case "champion":
            let grouped = Dictionary(grouping: capped, by: \.championId)
            return grouped.keys.sorted { app.gameData.championName($0) < app.gameData.championName($1) }
                .map { (app.gameData.championName($0), grouped[$0] ?? []) }
        case "rarity":
            let grouped = Dictionary(grouping: capped, by: \.rarityTier)
            return SkinRarity.allCases.reversed().compactMap { rarity in grouped[rarity].map { (rarity.displayName, $0) } }
        case "none":
            return capped.isEmpty ? [] : [("Alle Skins", capped)]
        default:
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: capped) { skin -> Int in
                inventory.owned[skin.id]?.purchased.map { calendar.component(.year, from: $0) } ?? 0
            }
            return grouped.keys.sorted(by: >).map { year in
                (year == 0 ? "Noch nicht im Besitz" : "Erworben \(year)", grouped[year] ?? [])
            }
        }
    }
}

private struct SkinCard: View {
    @Environment(AppModel.self) private var app
    let skin: Skin
    let owned: OwnedSkin?
    let price: Int?
    @ViewState private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(CDN.gameData(skin.loadScreenPath ?? skin.tilePath), alignment: .top)
                .saturation(owned == nil ? 0 : 1)
                .opacity(owned == nil ? 0.45 : 1)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(skin.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(9)
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "diamond.fill").font(.system(size: 8))
                .foregroundStyle(Theme.rarityColor(skin.rarityTier))
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.55), in: .circle)
                .padding(7)
                .help(skin.rarityTier.displayName)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hovering ? Theme.rarityColor(skin.rarityTier).opacity(0.8) : .white.opacity(0.06), lineWidth: hovering ? 1.5 : 1))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.snappy(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    private var subtitle: String {
        if let owned {
            if let date = owned.purchased { return date.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE"))) }
            return "Im Besitz"
        }
        if skin.isLegacy == true { return "Legacy" }
        return "\((price ?? skin.rarityTier.estimatedRP).groupedString) RP"
    }
}
