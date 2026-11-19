import RiftsightCore
import SwiftUI

/// Hosts one widget inside its panel (or inline in the overlay preview).
struct OverlayWidgetHost: View {
    let widget: OverlayWidget
    let model: LiveOverlayModel
    let manager: OverlayWindowManager?
    let app: AppModel

    var body: some View {
        let scale = app.settings.scale(widget)
        ScaledContent(scale: scale) {
            OverlayWidgetView(widget: widget, model: model, interact: manager?.interactMode ?? false) {
                manager?.disable(widget)
            }
            .fixedSize()
        }
        .environment(app)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    if !dragging { dragging = true; manager?.beginDrag(widget) }
                    manager?.drag(widget)
                }
                .onEnded { _ in
                    dragging = false
                    manager?.endDrag(widget)
                }
        )
    }

    @ViewState private var dragging = false
}

/// Renders its content scaled while reporting the scaled size to the layout (so the panel resizes too).
struct ScaledContent<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: Content

    var body: some View {
        ScaleLayout(scale: scale) {
            content.scaleEffect(scale, anchor: .topLeading)
        }
    }
}

private struct ScaleLayout: Layout {
    let scale: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}

struct OverlayWidgetView: View {
    let widget: OverlayWidget
    let model: LiveOverlayModel
    var interact = false
    var onClose: (() -> Void)?

    var body: some View {
        content
            .overlay {
                if interact {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .overlay(alignment: .topLeading) {
                if interact {
                    Text(widget.title).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.accent, in: .rect(cornerRadius: 4))
                        .offset(x: 8, y: -8)
                }
            }
            .padding(10)
    }

    @ViewBuilder private var content: some View {
        switch widget {
        case .goldBar: GoldBarWidget(model: model)
        case .winProbability: WinProbabilityWidget(model: model, onClose: onClose)
        case .nextItem: NextItemWidget(model: model, onClose: onClose)
        case .skillUp: SkillUpWidget(model: model, onClose: onClose)
        case .trinket: TrinketWidget(model: model, onClose: onClose)
        case .cooldowns: CooldownWidget(model: model)
        case .matchupGuide: MatchupGuideWidget(model: model)
        case .csBenchmark: CSBenchmarkWidget(model: model)
        case .itemSpikes: ItemSpikeWidget(model: model)
        case .augments: AugmentWidget(model: model)
        }
    }
}

// MARK: - Glass container

struct GlassPanel<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: 0x1B2130, alpha: 0.9), Color(hex: 0x121620, alpha: 0.88)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }
}

private struct CloseX: View {
    var action: (() -> Void)?
    var body: some View {
        if let action {
            Button(action: action) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Widget ausblenden")
        }
    }
}

// MARK: - Widgets

struct GoldBarWidget: View {
    let model: LiveOverlayModel

    var body: some View {
        let ally = model.allyGold, enemy = model.enemyGold
        let diff = ally - enemy
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                Text(compact(ally)).foregroundStyle(Color(hex: 0x8FB2FF))
                HStack(spacing: 5) {
                    Text((diff >= 0 ? "+" : "−") + compact(abs(diff))).foregroundStyle(.white)
                    Circle().fill(Theme.gold).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color(hex: 0xB07D1E), lineWidth: 1.5))
                }
                Text(compact(enemy)).foregroundStyle(Color(hex: 0xFF8A8A))
            }
            .font(.system(size: 22, weight: .heavy).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color(hex: 0x0E1220, alpha: 0.92), in: .rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(LinearGradient(colors: [Color(hex: 0xC9A24A), Color(hex: 0x7A5B1F)], startPoint: .top, endPoint: .bottom), lineWidth: 2))

            HStack(spacing: 10) {
                ForEach(model.timers.prefix(4)) { timer in
                    let left = timer.remaining(at: model.gameTime)
                    HStack(spacing: 4) {
                        Image(systemName: timer.kind.symbol).font(.system(size: 10, weight: .bold))
                        Text(left.map { $0 <= 0 ? "jetzt" : formatClock($0) } ?? "–").font(.system(size: 11, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(left.map { $0 < 60 } ?? false ? Theme.gold : .white.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(hex: 0x0E1220, alpha: 0.85), in: .capsule)
                    .help(timer.detail ?? timer.kind.displayName)
                }
            }
            .fixedSize()
        }
        .fixedSize()
    }

    private func compact(_ value: Int) -> String { String(format: "%.1fK", locale: .riftsight, Double(value) / 1000) }
}

struct WinProbabilityWidget: View {
    let model: LiveOverlayModel
    var onClose: (() -> Void)?

    var body: some View {
        let blue = model.blueWinProbability
        GlassPanel(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Siegchance").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    CloseX(action: onClose)
                }
                HStack(spacing: 0) {
                    side(value: blue, label: "BLAU", color: Color(hex: 0x7C9BFF))
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 40)
                    side(value: 1 - blue, label: "ROT", color: Color(hex: 0xFF7B7B))
                }
            }
            .frame(width: 210)
        }
    }

    private func side(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((value * 100).rounded()))").font(.system(size: 30, weight: .heavy).monospacedDigit())
                Text("%").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(color)
            Text(label).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(color.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

struct NextItemWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel
    var onClose: (() -> Void)?

    var body: some View {
        if let next = model.nextPurchase {
            GlassPanel(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Nächstes Item").font(.system(size: 14, weight: .medium)).foregroundStyle(Color(hex: 0x9DB0FF))
                        Spacer()
                        CloseX(action: onClose)
                    }
                    HStack(spacing: 12) {
                        ItemIcon(id: next.targetItemId, size: 44)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0x9DB0FF).opacity(0.7), lineWidth: 1.5))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(app.gameData.itemName(next.targetItemId)).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(next.tag).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 4))
                                if let buy = next.buyNowItemId, buy != next.targetItemId {
                                    HStack(spacing: 3) {
                                        Text("Jetzt:").foregroundStyle(.white.opacity(0.55))
                                        ItemIcon(id: buy, size: 16)
                                    }
                                    .font(.system(size: 10.5))
                                } else if next.missingGold > 0 {
                                    Text("noch \(next.missingGold) G").font(.system(size: 10.5)).foregroundStyle(Theme.gold)
                                }
                            }
                        }
                    }
                }
                .frame(width: 260, alignment: .leading)
            }
        }
    }
}

struct SkillUpWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel
    var onClose: (() -> Void)?

    var body: some View {
        let _ = model.detailsRevision
        if let key = model.skillUp, let me = model.me {
            let championId = model.myChampionId
            let detail = app.gameData.cachedDetail(championId)
            let rank = model.data?.activePlayer?.abilities?.level(key) ?? 0
            let maxRank = key == "R" ? 3 : 5
            GlassPanel(padding: 10) {
                HStack(spacing: 12) {
                    ChampionIcon(id: championId, size: 36, radius: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                    ZStack(alignment: .bottomTrailing) {
                        RemoteImage(CDN.gameData(detail?.spell(key)?.abilityIconPath))
                            .frame(width: 34, height: 34)
                            .clipShape(.rect(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x9DB0FF), lineWidth: 1.5))
                        Text(key).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 15, height: 15).background(.black, in: .rect(cornerRadius: 3))
                            .offset(x: 4, y: 4)
                    }
                    HStack(spacing: 5) {
                        ForEach(0..<min(maxRank, 5), id: \.self) { index in
                            Circle()
                                .fill(index < rank ? Color(hex: 0x9DB0FF) : .clear)
                                .overlay(Circle().strokeBorder(Color(hex: 0x9DB0FF), lineWidth: 1.3))
                                .frame(width: 10, height: 10)
                        }
                    }
                    Image(systemName: "chevron.up.2").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
                    Spacer(minLength: 4)
                    CloseX(action: onClose)
                }
                .frame(width: 230)
                .help("Skillpunkt frei – \(me.championName): \(key) leveln")
            }
        }
    }
}

struct TrinketWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel
    var onClose: (() -> Void)?

    var body: some View {
        if let swap = model.trinketSwap {
            GlassPanel(padding: 10) {
                HStack(spacing: 10) {
                    ItemIcon(id: swap.from, size: 32)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
                    ItemIcon(id: swap.to, size: 32)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(hex: 0x9DB0FF), lineWidth: 1.5))
                    Text("\(app.gameData.itemName(swap.to)) kaufen").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    CloseX(action: onClose)
                }
                .frame(width: 340)
            }
        }
    }
}

struct CooldownWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel

    var body: some View {
        GlassPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Gegner-Cooldowns").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("≈ manuell").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(model.data?.enemies ?? []) { enemy in
                    HStack(spacing: 6) {
                        ChampionIcon(id: app.gameData.championId(alias: enemy.championAlias) ?? 0, size: 26, radius: 13)
                        cooldownButton(enemy, .spell1, spellId: enemy.summonerSpells?.summonerSpellOne?.spellId)
                        cooldownButton(enemy, .spell2, spellId: enemy.summonerSpells?.summonerSpellTwo?.spellId)
                        ultButton(enemy)
                    }
                }
            }
            .frame(width: 200, alignment: .leading)
        }
    }

    private func cooldownButton(_ enemy: LivePlayer, _ kind: CooldownTimer.Kind, spellId: Int?) -> some View {
        let left = model.remaining(enemy, kind)
        return Button { model.toggleCooldown(enemy, kind: kind) } label: {
            ZStack {
                SpellIcon(id: spellId ?? 0, size: 26).saturation(left == nil ? 1 : 0).opacity(left == nil ? 1 : 0.5)
                if let left {
                    Text("≈" + formatClock(left)).font(.system(size: 8.5, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Klicken, wenn der Zauber benutzt wurde (Schätzung inkl. Zaubertempo aus Items)")
    }

    private func ultButton(_ enemy: LivePlayer) -> some View {
        let left = model.remaining(enemy, .ultimate)
        return Button { model.toggleCooldown(enemy, kind: .ultimate) } label: {
            Text(left.map { "≈" + formatClock($0) } ?? "R")
                .font(.system(size: 10, weight: .heavy).monospacedDigit())
                .foregroundStyle(left == nil ? .white : Theme.gold)
                .frame(minWidth: 44, minHeight: 26)
                .background(.white.opacity(left == nil ? 0.08 : 0.04), in: .rect(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .disabled(enemy.level < 6)
        .opacity(enemy.level < 6 ? 0.4 : 1)
    }
}

struct MatchupGuideWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel

    var body: some View {
        let guide = model.activeMatchupGuide
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ChampionIcon(id: model.myChampionId, size: 20, radius: 10)
                    Text("vs").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    ChampionIcon(id: model.laneOpponent.flatMap { app.gameData.championId(alias: $0.championAlias) } ?? 0, size: 20, radius: 10)
                    Text("Matchup-Guide").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    if let guide { Text(guide.difficulty).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.gold) }
                }
                if let guide {
                    ForEach(guide.points) { point in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Color(hex: 0x9DB0FF))
                            Text(point.text).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Guide wird aus den Champion-Daten erstellt …").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 300, alignment: .leading)
        }
    }
}

struct CSBenchmarkWidget: View {
    let model: LiveOverlayModel

    var body: some View {
        let cs = model.cs
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CS").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    Text("\(cs.current)").font(.system(size: 20, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                    Text("/ \(cs.benchmark)").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(cs.share.percentString(digits: 0)).font(.system(size: 13, weight: .bold)).foregroundStyle(cs.share >= 0.8 ? Theme.win : (cs.share >= 0.65 ? Theme.gold : Theme.loss))
                }
                ProgressBar(value: cs.share, color: cs.share >= 0.8 ? Theme.win : Theme.gold, track: .white.opacity(0.12))
                Text(String(format: "%.1f CS/Min", locale: .riftsight, Double(cs.current) / max(1, model.gameTime / 60)))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 190)
        }
    }
}

struct ItemSpikeWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.activeSpikes) { spike in
                if let player = model.player(spike.playerId) {
                    GlassPanel(padding: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.gold)
                            ChampionIcon(id: app.gameData.championId(alias: player.championAlias) ?? 0, size: 28, radius: 14)
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                            ItemIcon(id: spike.itemId, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(player.championName) – Power-Spike").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                Text(app.gameData.itemName(spike.itemId)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .frame(width: 260, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct AugmentWidget: View {
    @Environment(AppModel.self) private var app
    let model: LiveOverlayModel

    var body: some View {
        GlassPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(Theme.gold)
                    Text("Augment-Berater").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button {
                        Task { await model.scanAugments() }
                    } label: {
                        Label(model.isScanningAugments ? "Erkenne …" : "Erkennen (⌃⌥A)", systemImage: "text.viewfinder")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0x9DB0FF))
                }
                let augments = model.shownAugments
                if augments.isEmpty {
                    Text(model.augmentMessage ?? "Öffne die Augment-Auswahl und drücke ⌃⌥A.")
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.65))
                } else {
                    let best = augments.max { (model.augmentStat($0.augmentId)?.winrate ?? 0) < (model.augmentStat($1.augmentId)?.winrate ?? 0) }
                    HStack(spacing: 8) {
                        ForEach(augments) { augment in
                            let stat = model.augmentStat(augment.augmentId)
                            let isBest = augment.augmentId == best?.augmentId
                            HStack(spacing: 8) {
                                RemoteImage(CDN.augmentIcon(app.gameData.augments[augment.augmentId]?.iconLarge), contentMode: .fit, placeholder: .clear)
                                    .frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(augment.name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                                    HStack(spacing: 5) {
                                        if let stat { TierBadge(tier: stat.tier, size: 11) }
                                        Text(stat.map { $0.winrate.percentString() } ?? "–").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                            }
                            .padding(7)
                            .frame(width: 190, alignment: .leading)
                            .background(isBest ? Theme.gold.opacity(0.14) : .white.opacity(0.05), in: .rect(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isBest ? Theme.gold.opacity(0.8) : .white.opacity(0.1)))
                        }
                    }
                }
            }
        }
    }
}
