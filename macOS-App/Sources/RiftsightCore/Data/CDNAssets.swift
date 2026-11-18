import Foundation

/// URL builders for CommunityDragon and Data Dragon assets.
public enum CDN {
    static let cdragonGameData = "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global"
    static let cdragonStatic = "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default"
    static let ddragon = "https://ddragon.leagueoflegends.com/cdn"

    /// `/lol-game-data/assets/v1/perk-images/...` → absolute CommunityDragon URL (lowercased, `default` locale).
    public static func gameData(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let prefix = "/lol-game-data/assets/"
        guard path.hasPrefix(prefix) else { return URL(string: path) }
        let rest = String(path.dropFirst(prefix.count)).lowercased()
        return URL(string: "\(cdragonGameData)/default/\(rest)")
    }

    public static func championIcon(_ id: Int) -> URL? {
        URL(string: "\(cdragonGameData)/default/v1/champion-icons/\(id).png")
    }

    /// Wide splash art (DDragon), `skinNum` = skinId % 1000.
    public static func splash(alias: String, skinNum: Int = 0) -> URL? {
        URL(string: "\(ddragon)/img/champion/splash/\(alias)_\(skinNum).jpg")
    }

    /// Centered crop of the splash (good for wide banners).
    public static func centeredSplash(alias: String, skinNum: Int = 0) -> URL? {
        URL(string: "\(ddragon)/img/champion/centered/\(alias)_\(skinNum).jpg")
    }

    /// Vertical loading-screen art (308×560) – used for champ select and spectate cards.
    public static func loadingArt(alias: String, skinNum: Int = 0) -> URL? {
        URL(string: "\(ddragon)/img/champion/loading/\(alias)_\(skinNum).jpg")
    }

    public static func itemIcon(_ id: Int, version: String) -> URL? {
        URL(string: "\(ddragon)/\(version)/img/item/\(id).png")
    }

    public static func profileIcon(_ id: Int) -> URL? {
        URL(string: "\(cdragonGameData)/default/v1/profile-icons/\(id).jpg")
    }

    public static func rankEmblem(_ tier: RankTier) -> URL? {
        let name = tier == .unranked ? "iron" : tier.rawValue.lowercased()
        return URL(string: "\(cdragonStatic)/images/ranked-emblem/emblem-\(name).png")
    }

    public static func rankCrest(_ tier: RankTier) -> URL? {
        let name = tier == .unranked ? "unranked" : tier.rawValue.lowercased()
        return URL(string: "\(cdragonStatic)/images/ranked-mini-crests/\(name).png")
    }

    public static func roleIcon(_ role: Role) -> URL? {
        URL(string: "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-clash/global/default/assets/images/position-selector/positions/icon-position-\(role.rawValue.lowercased()).png")
    }

    /// Arena / Mayhem augment icons (`assets/ux/cherry/augments/icons/...`).
    public static func augmentIcon(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://raw.communitydragon.org/latest/game/\(path.lowercased())")
    }
}
