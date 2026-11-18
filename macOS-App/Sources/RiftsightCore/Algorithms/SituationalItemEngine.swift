import Foundation

public enum ItemGroupKind: String, CaseIterable, Sendable, Identifiable {
    case coreSpike, antiHeal, defensive, tankShred
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .coreSpike: "Core-Spike"
        case .antiHeal: "Anti-Heal / Anti-Shield"
        case .defensive: "Defensiv / Survival"
        case .tankShred: "Tank-Shred / Penetration"
        }
    }

    public var symbol: String {
        switch self {
        case .coreSpike: "bolt.fill"
        case .antiHeal: "cross.vial.fill"
        case .defensive: "shield.lefthalf.filled"
        case .tankShred: "scissors"
        }
    }
}

/// German tooltip: (1) when to build, (2) why it's strong, (3) buy timing.
public struct ItemReasoning: Sendable, Hashable {
    public let whenToBuild: String
    public let whyStrong: String
    public let timing: String
}

public struct ItemSuggestion: Sendable, Hashable, Identifiable {
    public let itemId: Int
    public let reasoning: ItemReasoning
    public let pickrate: Double?
    public let winrate: Double?
    public var id: Int { itemId }
}

public struct ItemGroup: Sendable, Hashable, Identifiable {
    public let kind: ItemGroupKind
    public let items: [ItemSuggestion]
    public let isHighlighted: Bool
    public let trigger: String?
    public let groupReasoning: ItemReasoning
    public var id: ItemGroupKind { kind }
}

public struct NextPurchase: Sendable, Hashable {
    public let targetItemId: Int
    /// Best component (or the item itself) affordable right now.
    public let buyNowItemId: Int?
    /// Gold still missing to finish the target item.
    public let missingGold: Int
    public let tag: String
}

public enum SituationalItemEngine {
    public enum DamageProfile: Sendable { case physical, magic, tank }

    static let pools: [ItemGroupKind: [DamageProfile: [Int]]] = [
        .antiHeal: [.physical: [3123, 3033, 6609, 6695], .magic: [3916, 3165], .tank: [3076, 3075]],
        .defensive: [.physical: [3026, 6333, 3156, 3139, 3814, 3140], .magic: [3157, 3102, 3140],
                     .tank: [3143, 3110, 4401, 2504, 3065]],
        .tankShred: [.physical: [3036, 3071, 6694, 3033], .magic: [3135, 3137, 6653, 2503], .tank: [3071, 6653]],
    ]

    public static func groups(profile: DamageProfile, build: BuildBlock?, threats: ThreatProfile,
                              items: [Int: Item]) -> [ItemGroup] {
        let rates = Dictionary(((build?.situational ?? []) + (build?.completedItems ?? [])).map { ($0.itemId, $0) },
                               uniquingKeysWith: { a, _ in a })
        func suggestions(_ ids: [Int]) -> [ItemSuggestion] {
            ids.filter { items.isEmpty || items[$0] != nil }.map {
                ItemSuggestion(itemId: $0, reasoning: reasoning(for: $0, items: items),
                               pickrate: rates[$0]?.pickrate, winrate: rates[$0]?.winrate)
            }
        }

        var result: [ItemGroup] = []
        let core = build?.coreBuild?.itemIds ?? []
        if !core.isEmpty {
            result.append(ItemGroup(kind: .coreSpike, items: suggestions(core), isHighlighted: false, trigger: nil,
                                    groupReasoning: ItemReasoning(
                                        whenToBuild: "Immer – das ist der Standard-Build für den ersten Power-Spike.",
                                        whyStrong: "Höchste Winrate-Kombination der ersten drei fertigen Items.",
                                        timing: "Erstes Item fertig bauen, bevor du auf Situatives wechselst.")))
        }

        let healTrigger: String? = threats.heavyHealing || threats.heavyShields
            ? "Heilung/Schilde bei: " + (threats.healingSources + threats.shieldSources).prefix(3).joined(separator: ", ")
            : nil
        result.append(ItemGroup(kind: .antiHeal, items: suggestions(pools[.antiHeal]?[profile] ?? []),
                                isHighlighted: healTrigger != nil, trigger: healTrigger,
                                groupReasoning: ItemReasoning(
                                    whenToBuild: "Sobald der Gegner zwei oder mehr starke Heil- oder Schildquellen hat.",
                                    whyStrong: "Grievous Wounds reduziert Heilung um 40 % – Kämpfe gegen Sustain werden gewinnbar.",
                                    timing: "Billiges 800-Gold-Bauteil früh kaufen, Ausbau erst als 2.–3. Item.")))

        var defensiveTrigger: String?
        if !threats.fedCritCarries.isEmpty { defensiveTrigger = "Gefütterter Crit-Carry: \(threats.fedCritCarries.joined(separator: ", "))" }
        else if !threats.fedMages.isEmpty || !threats.fedAssassins.isEmpty {
            defensiveTrigger = "Gefüttert: \((threats.fedMages + threats.fedAssassins).joined(separator: ", "))"
        } else if threats.heavyAP { defensiveTrigger = "Gegner macht überwiegend Magieschaden" }
        else if threats.hardCC >= 3 { defensiveTrigger = "\(threats.hardCC)× Hard-CC im Gegnerteam" }
        result.append(ItemGroup(kind: .defensive, items: suggestions(defensivePicks(profile: profile, threats: threats)),
                                isHighlighted: defensiveTrigger != nil, trigger: defensiveTrigger,
                                groupReasoning: ItemReasoning(
                                    whenToBuild: "Wenn ein Gegner dich in einer Combo töten kann oder du im Teamfight zuerst fällst.",
                                    whyStrong: "Ein Survival-Item kauft dir die Sekunden, in denen dein Schaden zählt.",
                                    timing: "Als 2.–3. Item; gegen frühen Burst zuerst das Bauteil (z. B. Stopwatch / Null-Magic-Mantle).")))

        let shredTrigger: String? = threats.tanks >= 2 ? "\(threats.tanks) Tanks im Gegnerteam" : nil
        result.append(ItemGroup(kind: .tankShred, items: suggestions(pools[.tankShred]?[profile] ?? []),
                                isHighlighted: shredTrigger != nil, trigger: shredTrigger,
                                groupReasoning: ItemReasoning(
                                    whenToBuild: "Gegen zwei oder mehr Frontliner oder sobald Gegner Resistenzen stacken.",
                                    whyStrong: "Prozentuale Penetration skaliert mit den Resistenzen des Ziels.",
                                    timing: "Ab dem 3. Item, wenn die Gegner ~100+ Rüstung/MR haben.")))
        return result
    }

    static func defensivePicks(profile: DamageProfile, threats: ThreatProfile) -> [Int] {
        switch profile {
        case .tank:
            if !threats.fedCritCarries.isEmpty || threats.heavyAD { return [3143, 3110, 3047, 3075] }
            if threats.heavyAP { return [4401, 2504, 3111, 3065] }
            return pools[.defensive]?[.tank] ?? []
        case .physical:
            if threats.heavyAP { return [3156, 3139, 3111] }
            if threats.hardCC >= 3 { return [3139, 3111, 3026] }
            return pools[.defensive]?[.physical] ?? []
        case .magic:
            if threats.heavyAP { return [3102, 3157, 3111] }
            return pools[.defensive]?[.magic] ?? []
        }
    }

    // MARK: Next purchase

    public static func nextPurchase(target: Int, owned: [Int], gold: Int, items: [Int: Item]) -> NextPurchase? {
        guard let item = items[target] else { return nil }
        var pool = owned
        var candidates: [(id: Int, cost: Int)] = []

        /// Gold still needed to own `id`, consuming owned components from `pool`.
        func remaining(_ id: Int) -> Int {
            if let index = pool.firstIndex(of: id) {
                pool.remove(at: index)
                return 0
            }
            guard let node = items[id] else { return 0 }
            let cost = node.price + node.from.reduce(0) { $0 + remaining($1) }
            candidates.append((id, cost))
            return cost
        }

        let total = remaining(target)
        guard total > 0 else { return nil }
        let affordable = candidates.filter { $0.cost <= gold }.max { $0.cost < $1.cost }
        return NextPurchase(targetItemId: target, buyNowItemId: affordable?.id, missingGold: max(0, total - gold),
                            tag: spikeTag(item))
    }

    /// Short German tag pill, e.g. "Burst & MS-Spike".
    public static func spikeTag(_ item: Item) -> String {
        let c = Set(item.categories)
        var parts: [String] = []
        if c.contains("ArmorPenetration") && !c.contains("CriticalStrike") { parts.append("Burst") }
        if c.contains("CriticalStrike") { parts.append("Crit") }
        if c.contains("SpellDamage") && !c.contains("Health") { parts.append("AP") }
        if c.contains("MagicPenetration") { parts.append("Pen") }
        if c.contains("OnHit") || c.contains("AttackSpeed") { parts.append("On-Hit") }
        if c.contains("Health") && (c.contains("Armor") || c.contains("SpellBlock")) { parts.append("Tank") }
        if c.contains("LifeSteal") || c.contains("SpellVamp") { parts.append("Sustain") }
        if c.contains("NonbootsMovement") { parts.append("MS") }
        if parts.isEmpty { parts.append("Power") }
        return parts.prefix(2).joined(separator: " & ") + "-Spike"
    }

    // MARK: German tooltips

    public static func reasoning(for itemId: Int, items: [Int: Item]) -> ItemReasoning {
        if let known = tooltips[itemId] { return known }
        let name = items[itemId]?.name ?? "Dieses Item"
        return ItemReasoning(whenToBuild: "\(name) passt in die meisten Spiele dieses Champions.",
                             whyStrong: "Hohe Pick- und Winrate in der Datenbasis.",
                             timing: "Nach dem Core-Spike, wenn kein situatives Item dringender ist.")
    }

    static let tooltips: [Int: ItemReasoning] = [
        3123: .init(whenToBuild: "Gegen Heiler/Lifesteal schon in der Lane.", whyStrong: "Billigste Quelle für Grievous Wounds.", timing: "Früh als Bauteil kaufen, Ausbau später."),
        3033: .init(whenToBuild: "ADC/Crit gegen Heilung und Tanks.", whyStrong: "Anti-Heal plus Rüstungsdurchdringung in einem Slot.", timing: "Als 2.–3. Item; Ruf des Henkers vorher."),
        6609: .init(whenToBuild: "Bruiser/AD-Caster gegen Sustain.", whyStrong: "Anti-Heal mit Leben und Fähigkeitstempo.", timing: "Ruf des Henkers früh, Ausbau als 2. Item."),
        6695: .init(whenToBuild: "Gegen Schild-Supports (Lulu, Janna, Karma) und Shieldbow.", whyStrong: "Reduziert Schilde des Gegners massiv.", timing: "Sobald 2+ Schildquellen sichtbar sind."),
        3916: .init(whenToBuild: "AP gegen Heiler.", whyStrong: "800 Gold für Grievous Wounds.", timing: "Sofort beim ersten Recall gegen Heal-Lanes."),
        3165: .init(whenToBuild: "Magier gegen anhaltende Heilung.", whyStrong: "Anti-Heal, Leben und Fähigkeitstempo.", timing: "Kugel früh, Ausbau als 2.–3. Item."),
        3076: .init(whenToBuild: "Tank gegen Auto-Attack-Heiler.", whyStrong: "Reflektiert Schaden und verwundet Angreifer.", timing: "Früh gegen Lifesteal-Bruiser."),
        3075: .init(whenToBuild: "Tank gegen AD-Heiler (Aatrox, Warwick, Lifesteal-ADC).", whyStrong: "Rüstung + Anti-Heal ohne Schaden zu investieren.", timing: "Dornenweste früh, Ausbau als 2. Tank-Item."),
        3157: .init(whenToBuild: "Gegen AD-Assassinen und Dive.", whyStrong: "Stase kontert ganze Combos und Ults.", timing: "Seekers Armguard früh gegen AD-Lane."),
        3026: .init(whenToBuild: "Carry, der im Teamfight fokussiert wird.", whyStrong: "Zweites Leben zwingt den Gegner, dich zweimal zu töten.", timing: "Als 4.–5. Item oder früher, wenn du der Wincon bist."),
        6333: .init(whenToBuild: "AD-Bruiser gegen Burst.", whyStrong: "Wandelt Burst in Schaden über Zeit um.", timing: "2.–3. Item gegen AD-Assassinen."),
        3143: .init(whenToBuild: "Gegen gefütterte Crit-Carries.", whyStrong: "Reduziert kritischen Schaden und verlangsamt.", timing: "Sobald ein Crit-ADC 2 Items hat."),
        3110: .init(whenToBuild: "Gegen Attack-Speed-Carries.", whyStrong: "Senkt das Angriffstempo aller Gegner in der Nähe.", timing: "Gegen ADC/On-Hit ab Midgame."),
        3047: .init(whenToBuild: "Gegen 3+ Auto-Attacker.", whyStrong: "Reduziert jeden normalen Angriff.", timing: "Als erste Stiefel gegen AD-Comps."),
        3102: .init(whenToBuild: "Gegen Engage/Pick-Comps mit AP.", whyStrong: "Zauberschild blockt den ersten CC/Burst.", timing: "Verbotenes Idol bzw. Bauteil früh gegen AP-Assassinen."),
        3156: .init(whenToBuild: "AD gegen AP-Burst.", whyStrong: "Magieschild bei niedrigem Leben.", timing: "Hexdrinker früh gegen AP-Lane."),
        3139: .init(whenToBuild: "Carry gegen Hard-CC (Suppress, Stun).", whyStrong: "Aktive Reinigung entfernt jedes CC.", timing: "Quecksilberschärpe früh, Ausbau spät."),
        4401: .init(whenToBuild: "Tank gegen AP-Dauerschaden.", whyStrong: "Stackende MR und Lauftempo.", timing: "Als 2. Tank-Item gegen 3+ AP."),
        2504: .init(whenToBuild: "Tank/Bruiser gegen Poke-Magier.", whyStrong: "Großer Magieschild, der sich regeneriert.", timing: "Gegen AP-Poke ab Midgame."),
        3111: .init(whenToBuild: "Gegen viel CC oder AP.", whyStrong: "Zähigkeit + Magieresistenz.", timing: "Als erste Stiefel gegen CC-Comps."),
        3140: .init(whenToBuild: "Gegen Suppressions/Exhaust-Ziele.", whyStrong: "Reinigung als Aktiv.", timing: "Situativ, sobald ein Gegner-CC dich zuverlässig tötet."),
        3036: .init(whenToBuild: "ADC gegen Tanks.", whyStrong: "Bonus-Rüstungsdurchdringung gegen Ziele mit viel Leben.", timing: "3. Item, wenn 2+ Tanks im Spiel sind."),
        3071: .init(whenToBuild: "Bruiser gegen Rüstungsstacker.", whyStrong: "Reduziert Rüstung für das ganze Team.", timing: "Früh als 1.–2. Item."),
        6694: .init(whenToBuild: "AD-Caster gegen Rüstung.", whyStrong: "Rüstungsdurchdringung plus Slow.", timing: "Ab dem 3. Item."),
        3135: .init(whenToBuild: "Magier gegen MR-Stacker.", whyStrong: "40 % Magiedurchdringung.", timing: "Ab dem 3. Item oder sobald Tanks 80+ MR haben."),
        3137: .init(whenToBuild: "Magier gegen gemischte Teams.", whyStrong: "Magiedurchdringung + Heilfeld nach Takedowns.", timing: "Als 2.–3. Item."),
        6653: .init(whenToBuild: "Magier/Tank gegen Frontlines.", whyStrong: "%-Leben-Brennschaden.", timing: "Früh gegen 2+ Tanks."),
        2503: .init(whenToBuild: "Magier mit DoT-Schaden.", whyStrong: "Verstärkt brennende Fähigkeiten.", timing: "Als 1.–2. Item."),
    ]
}
