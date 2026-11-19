import Foundation

// MARK: - CommunityDragon (de_de)

public struct ChampionSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let alias: String
    public let squarePortraitPath: String?
    public let roles: [String]?

    /// Excludes placeholders (-1) and mode variants such as the 60xxx "Jade_" copies.
    public var isPlayable: Bool { id > 0 && id < 10_000 }
    public var classTags: Set<String> { Set(roles ?? []) }
}

public struct ChampionDetail: Codable, Sendable, Hashable {
    public struct TacticalInfo: Codable, Sendable, Hashable {
        public let damageType: String?
        public let attackType: String?
        public let difficulty: Int?
    }

    public struct PlaystyleInfo: Codable, Sendable, Hashable {
        public let damage: Int
        public let durability: Int
        public let crowdControl: Int
        public let mobility: Int
        public let utility: Int
    }

    public struct Passive: Codable, Sendable, Hashable {
        public let name: String
        public let abilityIconPath: String?
        public let description: String?
    }

    public struct Spell: Codable, Sendable, Hashable {
        public let spellKey: String
        public let name: String
        public let abilityIconPath: String?
        public let description: String?
        public let cooldownCoefficients: [Double]?
        public let maxLevel: Int?

        public var key: String { spellKey.uppercased() }

        /// Cooldown at a given 1-based rank, clamped to the available data.
        public func cooldown(rank: Int) -> Double? {
            guard let values = cooldownCoefficients, !values.isEmpty else { return nil }
            let upper = max(1, min(maxLevel ?? values.count, values.count))
            return values[min(max(rank, 1), upper) - 1]
        }
    }

    public let id: Int
    public let name: String
    public let alias: String
    public let title: String?
    public let tacticalInfo: TacticalInfo?
    public let playstyleInfo: PlaystyleInfo?
    public let roles: [String]?
    public let passive: Passive?
    public let spells: [Spell]

    public func spell(_ key: String) -> Spell? { spells.first { $0.key == key.uppercased() } }

    public var isMagicDamage: Bool { tacticalInfo?.damageType == "kMagic" }
    public var isPhysicalDamage: Bool { tacticalInfo?.damageType == "kPhysical" }
    public var isRanged: Bool { tacticalInfo?.attackType == "ranged" }
}

public struct Item: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String?
    public let active: Bool?
    public let inStore: Bool?
    public let from: [Int]
    public let to: [Int]
    public let categories: [String]
    public let price: Int
    public let priceTotal: Int
    public let iconPath: String?
    public let requiredChampion: String?
    public let displayInItemSets: Bool?

    /// Legendary heuristic: finished (no upgrades), real recipe, ≥ 2200 gold, purchasable for everyone.
    public var isLegendary: Bool {
        to.isEmpty && !from.isEmpty && priceTotal >= 2200 && (requiredChampion ?? "").isEmpty
            && !categories.contains("Boots") && !categories.contains("Consumable")
    }

    public var isBoots: Bool { categories.contains("Boots") }

    /// Ability haste parsed from the description stats block (CDragon has no numeric stat table).
    public var abilityHaste: Int {
        Self.stat(named: ["Fähigkeitstempo", "Ability Haste"], in: description)
    }

    public var summonerSpellHaste: Int {
        Self.stat(named: ["Beschwörerzaubertempo", "Summoner Spell Haste"], in: description)
    }

    static func stat(named names: [String], in description: String?) -> Int {
        guard let description else { return 0 }
        let cleaned = description.replacingOccurrences(of: "&nbsp;", with: " ")
        for name in names {
            let pattern = #"<attention>\s*(\d+)\s*</attention>\s*"# + NSRegularExpression.escapedPattern(for: name)
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               let range = Range(match.range(at: 1), in: cleaned),
               let value = Int(cleaned[range]) {
                return value
            }
        }
        return 0
    }

    /// Plain-text description with the HTML-ish tags removed.
    public var plainDescription: String {
        guard let description else { return "" }
        return description
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Perk: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let iconPath: String?
    public let shortDesc: String?
    public let longDesc: String?
}

public struct PerkStylesFile: Codable, Sendable {
    public let styles: [PerkStyle]
}

public struct PerkStyle: Codable, Sendable, Hashable, Identifiable {
    public struct Slot: Codable, Sendable, Hashable {
        public let type: String
        public let perks: [Int]
    }

    public let id: Int
    public let name: String
    public let iconPath: String?
    public let slots: [Slot]

    public var keystoneSlot: Slot? { slots.first { $0.type == "kKeyStone" } }
    public var regularSlots: [Slot] { slots.filter { $0.type == "kMixedRegularSplashable" } }
    public var statSlots: [Slot] { slots.filter { $0.type == "kStatMod" } }
}

public struct SummonerSpell: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String?
    public let cooldown: Double?
    public let iconPath: String?
    public let gameModes: [String]?
}

public struct Skin: Codable, Sendable, Hashable, Identifiable {
    public struct LineRef: Codable, Sendable, Hashable { public let id: Int }

    public let id: Int
    public let name: String
    public let isBase: Bool
    public let rarity: String?
    public let isLegacy: Bool?
    public let splashPath: String?
    public let uncenteredSplashPath: String?
    public let tilePath: String?
    public let loadScreenPath: String?
    public let skinLines: [LineRef]?

    public var championId: Int { id / 1000 }
    public var rarityTier: SkinRarity { SkinRarity(cdragon: rarity, isBase: isBase) }
}

public enum SkinRarity: String, CaseIterable, Sendable, Codable {
    case standard, rare, epic, legendary, mythic, ultimate, exalted, transcendent

    public init(cdragon: String?, isBase: Bool = false) {
        switch cdragon {
        case "kRare": self = .rare
        case "kEpic": self = .epic
        case "kLegendary": self = .legendary
        case "kMythic": self = .mythic
        case "kUltimate": self = .ultimate
        case "kExalted": self = .exalted
        case "kTranscendent": self = .transcendent
        default: self = .standard
        }
    }

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .rare: "Selten"
        case .epic: "Episch"
        case .legendary: "Legendär"
        case .mythic: "Mythisch"
        case .ultimate: "Ultimativ"
        case .exalted: "Erhaben"
        case .transcendent: "Transzendent"
        }
    }

    /// Typical store price in RP, used when the client catalog has no price.
    public var estimatedRP: Int {
        switch self {
        case .standard: 975
        case .rare: 975
        case .epic: 1350
        case .legendary: 1820
        case .mythic: 2000
        case .ultimate: 3250
        case .exalted: 3000
        case .transcendent: 5000
        }
    }
}

public struct SkinLine: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
}

// MARK: - Data Dragon

public struct DDragonChampionFile: Codable, Sendable {
    public let data: [String: DDragonChampion]
}

public struct DDragonChampion: Codable, Sendable, Hashable {
    public struct Info: Codable, Sendable, Hashable {
        public let attack: Int
        public let defense: Int
        public let magic: Int
        public let difficulty: Int
    }

    public struct Stats: Codable, Sendable, Hashable {
        public let hp: Double
        public let hpperlevel: Double
        public let armor: Double
        public let spellblock: Double
        public let attackrange: Double
        public let attackdamage: Double
        public let attackspeed: Double
        public let movespeed: Double
    }

    public let id: String
    public let key: String
    public let name: String
    public let tags: [String]
    public let info: Info
    public let stats: Stats

    public var championId: Int { Int(key) ?? 0 }
}

// MARK: - Meraki

public struct MerakiRatesFile: Codable, Sendable {
    public struct RoleRate: Codable, Sendable { public let playRate: Double }
    public let data: [String: [String: RoleRate]]
    public let patch: String?

    /// championId → role → play rate (0…100 scale as delivered by Meraki).
    public var byChampion: [Int: [Role: Double]] {
        var result: [Int: [Role: Double]] = [:]
        for (key, roles) in data {
            guard let id = Int(key) else { continue }
            var map: [Role: Double] = [:]
            for (roleKey, rate) in roles { if let role = Role(flexible: roleKey) { map[role] = rate.playRate } }
            result[id] = map
        }
        return result
    }
}

// MARK: - Arena / Mayhem augments (CommunityDragon cdragon/arena)

public struct ArenaAugmentFile: Codable, Sendable {
    public let augments: [ArenaAugment]
}

public struct ArenaAugment: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let apiName: String?
    public let name: String
    public let rarity: Int
    public let iconLarge: String?
    public let iconSmall: String?

    public var rarityName: String {
        switch rarity {
        case 0: "silver"
        case 1: "gold"
        default: "prismatic"
        }
    }
}
