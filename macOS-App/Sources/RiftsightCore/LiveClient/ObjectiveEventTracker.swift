import Foundation

/// Spawn rules for Summoner's Rift epic monsters. Kept in one table so a patch change is a one-line edit.
public enum ObjectiveTimings {
    public static let dragonFirstSpawn: Double = 5 * 60
    public static let dragonRespawn: Double = 5 * 60
    public static let elderRespawn: Double = 6 * 60
    public static let grubsSpawn: Double = 8 * 60
    public static let heraldSpawn: Double = 15 * 60
    public static let baronFirstSpawn: Double = 20 * 60
    public static let baronRespawn: Double = 6 * 60
    public static let baronBuffDuration: Double = 3 * 60
}

public enum ObjectiveKind: String, Sendable, CaseIterable {
    case dragon, grubs, herald, baron

    public var displayName: String {
        switch self {
        case .dragon: "Drache"
        case .grubs: "Larven"
        case .herald: "Herold"
        case .baron: "Baron"
        }
    }

    public var symbol: String {
        switch self {
        case .dragon: "flame.fill"
        case .grubs: "ant.fill"
        case .herald: "eye.fill"
        case .baron: "crown.fill"
        }
    }
}

public struct ObjectiveTimer: Sendable, Hashable, Identifiable {
    public let kind: ObjectiveKind
    /// Game time at which the objective is (or was) up.
    public let spawnsAt: Double?
    public let detail: String?
    public var id: ObjectiveKind { kind }

    public func remaining(at gameTime: Double) -> Double? {
        guard let spawnsAt else { return nil }
        return max(0, spawnsAt - gameTime)
    }
}

/// Team scoreboard derived from Live Client events.
public struct TeamObjectives: Sendable, Hashable {
    public var dragons = 0
    public var barons = 0
    public var heralds = 0
    public var grubs = 0
    public var towers = 0
    public var inhibitors = 0
    public var kills = 0
    public var hasElder = false
    public var baronBuffUntil: Double = 0

    public init() {}
}

/// Turns the Live Client event list into objective timers and per-team objective counts.
public struct ObjectiveEventTracker: Sendable {
    public private(set) var order = TeamObjectives()
    public private(set) var chaos = TeamObjectives()
    private var lastDragonKill: Double?
    private var lastBaronKill: Double?
    private var elderUnlocked = false
    private var grubsDone = false
    private var heraldDone = false
    private var processed = Set<Int>()

    public init() {}

    public mutating func ingest(_ events: [LiveEvent], players: [LivePlayer]) {
        let teamOf = Dictionary(players.flatMap { p in [(p.riotId ?? "", p.team), (p.summonerName ?? "", p.team), (p.riotIdGameName ?? "", p.team)] }
            .filter { !$0.0.isEmpty }, uniquingKeysWith: { a, _ in a })
        func team(of name: String?) -> String? {
            guard let name else { return nil }
            if let team = teamOf[name] { return team }
            if name.contains("T100") || name.hasPrefix("Minion_T100") { return "ORDER" }
            if name.contains("T200") || name.hasPrefix("Minion_T200") { return "CHAOS" }
            return nil
        }
        for event in events where !processed.contains(event.EventID) {
            processed.insert(event.EventID)
            let killerTeam = team(of: event.KillerName)
            switch event.EventName {
            case "ChampionKill":
                mutate(killerTeam) { $0.kills += 1 }
            case "DragonKill":
                lastDragonKill = event.EventTime
                if event.DragonType == "Elder" { mutate(killerTeam) { $0.hasElder = true } }
                else { mutate(killerTeam) { $0.dragons += 1 } }
                if order.dragons >= 4 || chaos.dragons >= 4 { elderUnlocked = true }
            case "BaronKill":
                lastBaronKill = event.EventTime
                mutate(killerTeam) {
                    $0.barons += 1
                    $0.baronBuffUntil = event.EventTime + ObjectiveTimings.baronBuffDuration
                }
            case "HeraldKill":
                heraldDone = true
                mutate(killerTeam) { $0.heralds += 1 }
            case "HordeKill":
                mutate(killerTeam) { $0.grubs += 1 }
                if order.grubs + chaos.grubs >= 3 { grubsDone = true }
            case "TurretKilled":
                // Turret_T1_* belongs to ORDER → destroyed by CHAOS.
                let owner = event.TurretKilled ?? ""
                if owner.contains("_T1_") { chaos.towers += 1 } else if owner.contains("_T2_") { order.towers += 1 }
            case "InhibKilled":
                let owner = event.InhibKilled ?? ""
                if owner.contains("_T1_") { chaos.inhibitors += 1 } else if owner.contains("_T2_") { order.inhibitors += 1 }
            default:
                break
            }
        }
    }

    private mutating func mutate(_ team: String?, _ change: (inout TeamObjectives) -> Void) {
        switch team {
        case "ORDER": change(&order)
        case "CHAOS": change(&chaos)
        default: break
        }
    }

    public func objectives(for team: String) -> TeamObjectives { team == "CHAOS" ? chaos : order }

    public func timers(at gameTime: Double) -> [ObjectiveTimer] {
        var result: [ObjectiveTimer] = []
        let dragonAt = lastDragonKill.map { $0 + (elderUnlocked ? ObjectiveTimings.elderRespawn : ObjectiveTimings.dragonRespawn) }
            ?? ObjectiveTimings.dragonFirstSpawn
        result.append(ObjectiveTimer(kind: .dragon, spawnsAt: dragonAt, detail: elderUnlocked ? "Elder" : nil))
        if !grubsDone && gameTime < ObjectiveTimings.heraldSpawn {
            result.append(ObjectiveTimer(kind: .grubs, spawnsAt: ObjectiveTimings.grubsSpawn, detail: nil))
        } else if !heraldDone && gameTime < ObjectiveTimings.baronFirstSpawn {
            result.append(ObjectiveTimer(kind: .herald, spawnsAt: ObjectiveTimings.heraldSpawn, detail: nil))
        }
        let baronAt = lastBaronKill.map { $0 + ObjectiveTimings.baronRespawn } ?? ObjectiveTimings.baronFirstSpawn
        result.append(ObjectiveTimer(kind: .baron, spawnsAt: baronAt, detail: nil))
        return result
    }
}

/// Minion spawn math for the CS benchmark (Summoner's Rift lanes).
public enum CSBenchmark {
    /// Waves spawn every 30 s from 0:30; cannon every 3rd wave until 15:00, every 2nd until 25:00, then every wave.
    /// Minions reach the lane roughly 25 s after spawning.
    public static func minionsAvailable(at gameTime: Double, travel: Double = 25) -> Int {
        let effective = gameTime - travel
        guard effective >= 30 else { return 0 }
        let waves = Int((effective - 30) / 30) + 1
        var total = 0
        for wave in 1...waves {
            let spawnTime = 30 + Double(wave - 1) * 30
            let hasCannon: Bool = if spawnTime < 15 * 60 { wave % 3 == 0 }
                else if spawnTime < 25 * 60 { wave % 2 == 0 }
                else { true }
            total += 6 + (hasCannon ? 1 : 0)
        }
        return total
    }

    public static func share(cs: Int, gameTime: Double) -> Double {
        let available = minionsAvailable(at: gameTime)
        return available == 0 ? 0 : min(1.2, Double(cs) / Double(available))
    }
}
