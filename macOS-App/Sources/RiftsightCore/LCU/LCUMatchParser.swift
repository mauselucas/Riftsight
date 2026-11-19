import Foundation

/// Converts the loosely-typed LCU match JSON (match history, timelines, end-of-game block) into `MatchRecord`.
public enum LCUMatchParser {
    static func int(_ any: Any?) -> Int {
        switch any {
        case let value as Int: value
        case let value as Double: Int(value)
        case let value as NSNumber: value.intValue
        case let value as String: Int(value) ?? 0
        default: 0
        }
    }

    static func int64(_ any: Any?) -> Int64 {
        switch any {
        case let value as Int64: value
        case let value as Int: Int64(value)
        case let value as NSNumber: value.int64Value
        case let value as String: Int64(value) ?? 0
        default: 0
        }
    }

    static func bool(_ any: Any?) -> Bool {
        switch any {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        case let value as String: ["win", "true", "1"].contains(value.lowercased())
        default: false
        }
    }

    // MARK: Match history

    public static func matches(fromHistory object: Any, localPuuid: String? = nil) -> [MatchRecord] {
        guard let root = object as? [String: Any],
              let games = (root["games"] as? [String: Any])?["games"] as? [[String: Any]] else { return [] }
        return games.compactMap { match(fromGame: $0, localPuuid: localPuuid) }.sorted { $0.creation > $1.creation }
    }

    public static func match(fromGame game: [String: Any], localPuuid: String?) -> MatchRecord? {
        let gameId = int64(game["gameId"])
        guard gameId > 0 else { return nil }
        let identities = (game["participantIdentities"] as? [[String: Any]]) ?? []
        var players: [Int: [String: Any]] = [:]
        for identity in identities {
            players[int(identity["participantId"])] = identity["player"] as? [String: Any] ?? [:]
        }

        let participants: [ParticipantRecord] = ((game["participants"] as? [[String: Any]]) ?? []).map { p in
            let pid = int(p["participantId"])
            let stats = p["stats"] as? [String: Any] ?? [:]
            let player = players[pid] ?? [:]
            let timeline = p["timeline"] as? [String: Any] ?? [:]
            let items = (0...6).map { int(stats["item\($0)"]) }
            return ParticipantRecord(
                participantId: pid,
                teamId: int(p["teamId"]),
                puuid: player["puuid"] as? String,
                gameName: (player["gameName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (player["summonerName"] as? String ?? "Spieler"),
                tagLine: player["tagLine"] as? String ?? "",
                championId: int(p["championId"]),
                role: role(lane: timeline["lane"] as? String, role: timeline["role"] as? String),
                champLevel: int(stats["champLevel"]),
                spell1Id: int(p["spell1Id"]),
                spell2Id: int(p["spell2Id"]),
                keystoneId: int(stats["perk0"]),
                subStyleId: int(stats["perkSubStyle"]),
                items: items,
                kills: int(stats["kills"]),
                deaths: int(stats["deaths"]),
                assists: int(stats["assists"]),
                cs: int(stats["totalMinionsKilled"]) + int(stats["neutralMinionsKilled"]),
                gold: int(stats["goldEarned"]),
                damageToChampions: int(stats["totalDamageDealtToChampions"]),
                damageTaken: int(stats["totalDamageTaken"]),
                visionScore: int(stats["visionScore"]),
                objectiveDamage: int(stats["damageDealtToObjectives"]),
                win: bool(stats["win"])
            )
        }

        let teams: [TeamRecord] = ((game["teams"] as? [[String: Any]]) ?? []).map { t in
            TeamRecord(
                teamId: int(t["teamId"]),
                win: bool(t["win"]),
                baronKills: int(t["baronKills"]),
                dragonKills: int(t["dragonKills"]),
                towerKills: int(t["towerKills"]),
                inhibitorKills: int(t["inhibitorKills"]),
                heraldKills: int(t["riftHeraldKills"]),
                hordeKills: int(t["hordeKills"]),
                bans: ((t["bans"] as? [[String: Any]]) ?? []).map { int($0["championId"]) }
            )
        }

        return MatchRecord(
            gameId: gameId,
            queueId: int(game["queueId"]),
            gameMode: game["gameMode"] as? String ?? "CLASSIC",
            creation: Date(timeIntervalSince1970: TimeInterval(int64(game["gameCreation"])) / 1000),
            durationSeconds: int(game["gameDuration"]),
            teams: teams,
            participants: participants,
            localPuuid: localPuuid ?? (participants.count == 1 ? participants.first?.puuid : nil)
        )
    }

    static func role(lane: String?, role: String?) -> Role? {
        switch (lane?.uppercased(), role?.uppercased()) {
        case ("TOP", _): .top
        case ("JUNGLE", _): .jungle
        case ("MIDDLE", _), ("MID", _): .middle
        case ("BOTTOM", "SUPPORT"), ("BOT", "SUPPORT"), (_, "SUPPORT"): .utility
        case ("BOTTOM", _), ("BOT", _): .bottom
        default: nil
        }
    }

    // MARK: Timeline

    public static func timelines(from object: Any) -> [Int: ParticipantTimeline] {
        guard let root = object as? [String: Any], let frames = root["frames"] as? [[String: Any]] else { return [:] }
        var result: [Int: ParticipantTimeline] = [:]
        for (minute, frame) in frames.enumerated() {
            if let pf = frame["participantFrames"] as? [String: Any] {
                for (key, value) in pf {
                    guard let id = Int(key), let f = value as? [String: Any] else { continue }
                    result[id, default: ParticipantTimeline()].csAtMinute[minute] =
                        int(f["minionsKilled"]) + int(f["jungleMinionsKilled"])
                }
            }
            for event in (frame["events"] as? [[String: Any]]) ?? [] where (event["type"] as? String) == "CHAMPION_KILL" {
                let time = Double(int64(event["timestamp"])) / 1000
                let victim = int(event["victimId"])
                result[victim, default: ParticipantTimeline()].deathTimes.append(time)
                var takers = [int(event["killerId"])]
                takers += ((event["assistingParticipantIds"] as? [Any]) ?? []).map { int($0) }
                for taker in takers where taker > 0 {
                    result[taker, default: ParticipantTimeline()].takedownTimes.append(time)
                }
            }
        }
        return result
    }

    // MARK: End of game

    public static func match(fromEndOfGame object: Any) -> MatchRecord? {
        guard let root = object as? [String: Any] else { return nil }
        let gameId = int64(root["gameId"])
        guard gameId > 0 else { return nil }
        let localPuuid = (root["localPlayer"] as? [String: Any])?["puuid"] as? String
        var participants: [ParticipantRecord] = []
        var teams: [TeamRecord] = []
        var pid = 1
        for team in (root["teams"] as? [[String: Any]]) ?? [] {
            let teamId = int(team["teamId"])
            let win = bool(team["isWinningTeam"])
            let teamStats = team["stats"] as? [String: Any] ?? [:]
            teams.append(TeamRecord(teamId: teamId, win: win,
                                    baronKills: int(teamStats["BARON_KILLS"]),
                                    dragonKills: int(teamStats["DRAGON_KILLS"]),
                                    towerKills: int(teamStats["TURRETS_KILLED"]),
                                    inhibitorKills: int(teamStats["BARRACKS_KILLED"]),
                                    heraldKills: int(teamStats["RIFT_HERALD_KILLS"]),
                                    hordeKills: int(teamStats["HORDE_KILLS"])))
            for player in (team["players"] as? [[String: Any]]) ?? [] {
                let s = player["stats"] as? [String: Any] ?? [:]
                let items = (player["items"] as? [Any] ?? []).map { int($0) }
                participants.append(ParticipantRecord(
                    participantId: pid,
                    teamId: teamId,
                    puuid: player["puuid"] as? String,
                    gameName: (player["riotIdGameName"] as? String) ?? (player["summonerName"] as? String) ?? "Spieler",
                    tagLine: player["riotIdTagLine"] as? String ?? "",
                    championId: int(player["championId"]),
                    role: Role(flexible: (player["detectedTeamPosition"] as? String) ?? (player["selectedPosition"] as? String) ?? ""),
                    champLevel: int(s["LEVEL"]),
                    spell1Id: int(player["spell1Id"]),
                    spell2Id: int(player["spell2Id"]),
                    keystoneId: int(s["PERK0"]),
                    subStyleId: int(s["PERK_SUB_STYLE"]),
                    items: items,
                    kills: int(s["CHAMPIONS_KILLED"]),
                    deaths: int(s["NUM_DEATHS"]),
                    assists: int(s["ASSISTS"]),
                    cs: int(s["MINIONS_KILLED"]) + int(s["NEUTRAL_MINIONS_KILLED"]),
                    gold: int(s["GOLD_EARNED"]),
                    damageToChampions: int(s["TOTAL_DAMAGE_DEALT_TO_CHAMPIONS"]),
                    damageTaken: int(s["TOTAL_DAMAGE_TAKEN"]),
                    visionScore: int(s["VISION_SCORE"]),
                    objectiveDamage: int(s["TOTAL_DAMAGE_DEALT_TO_OBJECTIVES"]),
                    win: win))
                pid += 1
            }
        }
        return MatchRecord(gameId: gameId,
                           queueId: int(root["queueId"]),
                           gameMode: root["gameMode"] as? String ?? "CLASSIC",
                           creation: .now,
                           durationSeconds: int(root["gameLength"]),
                           teams: teams,
                           participants: participants,
                           localPuuid: localPuuid)
    }
}
