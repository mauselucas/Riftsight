import Foundation

/// The five Summoner's Rift positions, spelled like Match-V5 `teamPosition`.
public enum Role: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case top = "TOP"
    case jungle = "JUNGLE"
    case middle = "MIDDLE"
    case bottom = "BOTTOM"
    case utility = "UTILITY"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: "Top"
        case .jungle: "Jungle"
        case .middle: "Mid"
        case .bottom: "Bot"
        case .utility: "Support"
        }
    }

    /// Accepts the various spellings used by LCU (`assignedPosition`), Live Client (`position`) and Meraki.
    public init?(flexible raw: String) {
        switch raw.lowercased() {
        case "top": self = .top
        case "jungle": self = .jungle
        case "middle", "mid": self = .middle
        case "bottom", "bot", "adc": self = .bottom
        case "utility", "support", "sup": self = .utility
        default: return nil
        }
    }
}

public enum Tier: String, Codable, CaseIterable, Sendable, Comparable {
    case sPlus = "S+"
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.order > rhs.order }
}

public enum RankTier: String, Codable, CaseIterable, Sendable, Comparable {
    case unranked = "UNRANKED"
    case iron = "IRON", bronze = "BRONZE", silver = "SILVER", gold = "GOLD", platinum = "PLATINUM"
    case emerald = "EMERALD", diamond = "DIAMOND", master = "MASTER", grandmaster = "GRANDMASTER"
    case challenger = "CHALLENGER"

    public init(lenient raw: String?) {
        self = raw.flatMap { RankTier(rawValue: $0.uppercased()) } ?? .unranked
    }

    public var displayName: String {
        switch self {
        case .unranked: "Ungewertet"
        case .iron: "Eisen"
        case .bronze: "Bronze"
        case .silver: "Silber"
        case .gold: "Gold"
        case .platinum: "Platin"
        case .emerald: "Smaragd"
        case .diamond: "Diamant"
        case .master: "Meister"
        case .grandmaster: "Großmeister"
        case .challenger: "Herausforderer"
        }
    }

    public var shortCode: String {
        switch self {
        case .unranked: "–"
        case .iron: "I"
        case .bronze: "B"
        case .silver: "S"
        case .gold: "G"
        case .platinum: "P"
        case .emerald: "E"
        case .diamond: "D"
        case .master: "M"
        case .grandmaster: "GM"
        case .challenger: "C"
        }
    }

    public var isApex: Bool { self >= .master }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: RankTier, rhs: RankTier) -> Bool { lhs.order < rhs.order }
}

public enum Platform: String, Codable, CaseIterable, Sendable {
    case euw1 = "EUW1", eun1 = "EUN1", na1 = "NA1", kr = "KR", br1 = "BR1", jp1 = "JP1"
    case la1 = "LA1", la2 = "LA2", oc1 = "OC1", tr1 = "TR1", ru = "RU", sg2 = "SG2", tw2 = "TW2", vn2 = "VN2"

    public var shortLabel: String {
        switch self {
        case .euw1: "EUW"
        case .eun1: "EUNE"
        case .na1: "NA"
        case .kr: "KR"
        case .br1: "BR"
        case .jp1: "JP"
        case .la1: "LAN"
        case .la2: "LAS"
        case .oc1: "OCE"
        case .tr1: "TR"
        case .ru: "RU"
        case .sg2: "SG"
        case .tw2: "TW"
        case .vn2: "VN"
        }
    }

    public init?(lenient raw: String) {
        let upper = raw.uppercased()
        if let exact = Platform(rawValue: upper) { self = exact; return }
        guard let match = Platform.allCases.first(where: { $0.shortLabel == upper }) else { return nil }
        self = match
    }
}

/// Queue ids we care about.
public enum Queue: Int, Sendable {
    case rankedSolo = 420
    case rankedFlex = 440
    case normalDraft = 400
    case swiftplay = 480
    case aram = 450
    case aramMayhem = 2400
    case arena = 1700

    public var displayName: String {
        switch self {
        case .rankedSolo: "Ranked Solo"
        case .rankedFlex: "Ranked Flex"
        case .normalDraft: "Normal"
        case .swiftplay: "Swiftplay"
        case .aram: "ARAM"
        case .aramMayhem: "ARAM Mayhem"
        case .arena: "Arena"
        }
    }

    public static func displayName(for id: Int) -> String {
        Queue(rawValue: id)?.displayName ?? (id == 1710 ? "Arena" : "Andere")
    }
}

/// Game mode buckets that matter for overlay positions and data.
public enum GameModeBucket: String, Codable, CaseIterable, Sendable {
    case summonersRift = "CLASSIC"
    case aram = "ARAM"
    case arena = "CHERRY"

    public init(liveGameMode: String) {
        switch liveGameMode.uppercased() {
        case "ARAM", "KIWI": self = .aram
        case "CHERRY": self = .arena
        default: self = .summonersRift
        }
    }

    public var displayName: String {
        switch self {
        case .summonersRift: "Kluft der Beschwörer"
        case .aram: "ARAM"
        case .arena: "Arena"
        }
    }
}

public extension Locale {
    /// All user-facing numbers are German: `16.444`, `53,4%`.
    static let riftsight = Locale(identifier: "de_DE")
}

public extension Double {
    /// `0.526` → `"52,6%"`
    func percentString(digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", locale: .riftsight, self * 100)
    }

    /// `0.008` → `"+0,8%"`
    func signedPercentString(digits: Int = 1) -> String {
        String(format: "%+.\(digits)f%%", locale: .riftsight, self * 100)
    }
}

public extension Int {
    /// `412884` → `"412.884"`
    var groupedString: String {
        formatted(.number.grouping(.automatic).locale(.riftsight))
    }

    /// `24100` → `"24,1K"`
    var compactString: String {
        if abs(self) >= 1000 { return String(format: "%.1fK", locale: .riftsight, Double(self) / 1000) }
        return String(self)
    }
}

/// Formats seconds as `m:ss`.
public func formatClock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
