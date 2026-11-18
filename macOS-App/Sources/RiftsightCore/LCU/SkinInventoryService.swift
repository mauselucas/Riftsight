import Foundation

public struct OwnedSkin: Sendable, Hashable {
    public let skinId: Int
    public let purchased: Date?

    public init(skinId: Int, purchased: Date?) {
        self.skinId = skinId
        self.purchased = purchased
    }
}

public struct SkinInventory: Sendable {
    public var owned: [Int: OwnedSkin]
    /// skinId → RP price from the client catalog (when available).
    public var prices: [Int: Int]

    public init(owned: [Int: OwnedSkin] = [:], prices: [Int: Int] = [:]) {
        self.owned = owned
        self.prices = prices
    }
}

/// Reads the account's skins (`/lol-inventory/v2/inventory/CHAMPION_SKIN`) and catalog prices.
public enum SkinInventoryService {
    public static func load(client: LCURestClient) async throws -> SkinInventory {
        var inventory = SkinInventory()
        let items = try await client.get("/lol-inventory/v2/inventory/CHAMPION_SKIN", as: [LCUInventoryItem].self)
        for item in items where item.ownershipType != "RENTED" {
            inventory.owned[item.itemId] = OwnedSkin(skinId: item.itemId, purchased: item.purchased)
        }
        if let catalog = try? await client.getObject("/lol-catalog/v1/items/CHAMPION_SKIN") as? [[String: Any]] {
            for entry in catalog {
                let id = LCUMatchParser.int(entry["itemId"])
                let prices = entry["prices"] as? [[String: Any]] ?? []
                if let rp = prices.first(where: { ($0["currency"] as? String) == "RP" }) {
                    inventory.prices[id] = LCUMatchParser.int(rp["cost"])
                }
            }
        }
        return inventory
    }
}

/// Manages exactly one Riftsight-owned rune page. Never deletes or overwrites the user's own pages.
public enum RunePageService {
    public static let pagePrefix = "Riftsight"

    public static func apply(_ page: RunePageStat, title: String, client: LCURestClient) async throws {
        let pages = try await client.get("/lol-perks/v1/pages", as: [LCUPerkPage].self)
        let ownPage = pages.first { $0.name.hasPrefix(pagePrefix) && ($0.isEditable ?? true) }

        struct Body: Encodable, Sendable {
            let name: String
            let primaryStyleId: Int
            let subStyleId: Int
            let selectedPerkIds: [Int]
            let current: Bool
        }
        let body = Body(name: "\(pagePrefix): \(title)".prefix(25).description,
                        primaryStyleId: page.primaryStyleId,
                        subStyleId: page.subStyleId,
                        selectedPerkIds: page.perkIds,
                        current: true)

        if let ownPage {
            try await client.send("PUT", "/lol-perks/v1/pages/\(ownPage.id)", json: body)
            _ = try? await client.request("PUT", "/lol-perks/v1/currentpage", body: JSONEncoder().encode(ownPage.id))
            return
        }
        do {
            try await client.send("POST", "/lol-perks/v1/pages", json: body)
        } catch LCUError.http(let status, _) where status == 400 || status == 409 {
            throw LCUError.noFreeRunePage
        }
    }
}
