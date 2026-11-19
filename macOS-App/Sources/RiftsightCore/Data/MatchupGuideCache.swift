import Foundation

/// A compact German 4-point lane guide for `myChampion` vs `enemyChampion`.
public struct MatchupGuide: Codable, Sendable, Hashable {
    public struct Point: Codable, Sendable, Hashable, Identifiable {
        public let title: String
        public let text: String
        public var id: String { title }

        public init(title: String, text: String) {
            self.title = title
            self.text = text
        }
    }

    public let myChampionId: Int
    public let enemyChampionId: Int
    public let role: Role?
    public let patch: String
    public let difficulty: String
    public let points: [Point]

    public init(myChampionId: Int, enemyChampionId: Int, role: Role?, patch: String, difficulty: String, points: [Point]) {
        self.myChampionId = myChampionId
        self.enemyChampionId = enemyChampionId
        self.role = role
        self.patch = patch
        self.difficulty = difficulty
        self.points = points
    }

    public var cacheKey: String { Self.key(my: myChampionId, enemy: enemyChampionId, role: role, patch: patch) }

    public static func key(my: Int, enemy: Int, role: Role?, patch: String) -> String {
        "\(patch)-\(my)-\(enemy)-\(role?.rawValue ?? "ANY")"
    }
}

/// JSON-file backed cache so known matchups load in 0 ms.
@MainActor
@Observable
public final class MatchupGuideCache {
    private var guides: [String: MatchupGuide] = [:]
    private let file: URL
    private var dirty = false

    public init(file: URL = AppPaths.directory("Guides").appendingPathComponent("matchup-guides-v2.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([String: MatchupGuide].self, from: data) {
            guides = stored
        }
    }

    public func guide(my: Int, enemy: Int, role: Role?, patch: String) -> MatchupGuide? {
        guides[MatchupGuide.key(my: my, enemy: enemy, role: role, patch: patch)]
            ?? guides[MatchupGuide.key(my: my, enemy: enemy, role: nil, patch: patch)]
    }

    public func store(_ guide: MatchupGuide) {
        if guides[guide.cacheKey] == guide { return }
        guides[guide.cacheKey] = guide
        dirty = true
        flush()
    }

    public func flush() {
        guard dirty, let data = try? JSONEncoder().encode(guides) else { return }
        try? data.write(to: file, options: .atomic)
        dirty = false
    }

    public var count: Int { guides.count }
}
