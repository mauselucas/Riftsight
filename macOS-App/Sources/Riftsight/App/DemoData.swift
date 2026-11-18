import Foundation
import RiftsightCore

/// Deterministic demo content so every screen renders without a running League client.
/// All player names are fictional.
enum DemoData {
    struct RNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func double(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + Double(next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
        }
        mutating func pick<T>(_ array: [T]) -> T { array[int(0...(array.count - 1))] }
        mutating func chance(_ p: Double) -> Bool { double(0...1) < p }
    }

    static let localPuuid = "demo-local"
    static let localName = "Nachtfalke"
    static let localTag = "EUW"

    struct Profile {
        var name: String
        var tag: String
        var level: Int
        var iconId: Int
        var region: String
        var tier: RankTier
        var division: String?
        var lp: Int
        var wins: Int
        var losses: Int
    }

    static let profile = Profile(name: localName, tag: localTag, level: 612, iconId: 4568, region: "EUW",
                                 tier: .challenger, division: nil, lp: 1284, wins: 214, losses: 171)

    static let rolePools: [Role: [Int]] = [
        .top: [266, 897, 92, 126, 150, 122, 86, 24, 875, 516],
        .jungle: [64, 234, 59, 28, 254, 141, 876, 121],
        .middle: [103, 134, 268, 61, 112, 238, 84, 157, 4, 518],
        .bottom: [222, 145, 51, 81, 67, 21, 236, 202, 360, 523],
        .utility: [412, 111, 117, 497, 89, 37, 40, 526, 201, 53],
    ]

    static let roleItems: [Role: [Int]] = [
        .top: [3078, 3047, 3071, 6333, 3053, 3065],
        .jungle: [6610, 3111, 3071, 6333, 3053, 3026],
        .middle: [6655, 3020, 4645, 3089, 3135, 3157],
        .bottom: [3031, 3006, 3087, 3036, 3072, 3026],
        .utility: [3190, 3111, 3109, 3050, 4401, 3065],
    ]

    static let roleSpells: [Role: (Int, Int)] = [
        .top: (4, 12), .jungle: (11, 4), .middle: (4, 14), .bottom: (4, 7), .utility: (4, 14),
    ]

    static let keystones: [Role: (Int, Int)] = [
        .top: (8010, 8400), .jungle: (8010, 8100), .middle: (8229, 8300), .bottom: (8008, 8300), .utility: (8439, 8300),
    ]

    static let fictionalNames = ["Kiesel", "Morgenwind", "Ferrolux", "Tintenfisch", "Zinnober", "Halogen", "Polarlicht",
                                 "Quarzkopf", "Lotusblatt", "Sternsucher", "Frostbiss", "Kobaltfuchs", "Nebelkrähe",
                                 "Echolot", "Sirius", "Glutkern", "Vektor", "Wolkenbruch", "Schattenriss", "Funkenflug",
                                 "Mooswacht", "Orbitläufer", "Asche", "Pixelherz", "Klingensang", "Zephir", "Runenbote"]

    // MARK: Matches

    static func matches(count: Int = 20) -> [MatchRecord] {
        var rng = RNG(seed: 42)
        let myPool = [103, 103, 103, 134, 134, 268, 61, 112]
        var result: [MatchRecord] = []
        var clock = Date().addingTimeInterval(-55 * 60)
        for index in 0..<count {
            let queue = index % 6 == 5 ? 400 : (index % 9 == 8 ? 450 : 420)
            let duration = rng.int(1380...2280)
            let myTeam = rng.chance(0.5) ? 100 : 200
            let win = rng.chance(index < 6 ? 0.67 : 0.55)
            var participants: [ParticipantRecord] = []
            var pid = 1
            var used = Set<Int>()
            for team in [100, 200] {
                let teamWin = (team == myTeam) == win
                for role in Role.allCases {
                    let isMe = team == myTeam && role == .middle
                    var champion = isMe ? rng.pick(myPool) : rng.pick(rolePools[role]!)
                    while used.contains(champion) { champion = rng.pick(rolePools[role]!) }
                    used.insert(champion)
                    let minutes = Double(duration) / 60
                    let carry = role == .middle || role == .bottom
                    let kills = rng.int(teamWin ? 3...12 : 1...8)
                    let deaths = rng.int(teamWin ? 1...6 : 3...9)
                    let assists = rng.int(role == .utility ? 8...22 : 3...14)
                    let csPerMin = role == .utility ? rng.double(0.8...1.6) : (role == .jungle ? rng.double(5.2...6.8) : rng.double(6.4...9.2))
                    let items = Array(roleItems[role]!.prefix(minutes > 32 ? 6 : (minutes > 26 ? 5 : 4)))
                        + [role == .utility || role == .jungle ? 3364 : 3340]
                    let spells = roleSpells[role]!
                    let keystone = keystones[role]!
                    participants.append(ParticipantRecord(
                        participantId: pid, teamId: team, puuid: isMe ? localPuuid : "p\(index)-\(pid)",
                        gameName: isMe ? localName : rng.pick(fictionalNames), tagLine: isMe ? localTag : "EUW",
                        championId: champion, role: queue == 450 ? nil : role, champLevel: min(18, Int(minutes / 2) + rng.int(0...3)),
                        spell1Id: spells.0, spell2Id: spells.1, keystoneId: keystone.0, subStyleId: keystone.1,
                        items: items, kills: kills, deaths: deaths, assists: assists, cs: Int(csPerMin * minutes),
                        gold: Int(minutes * (carry ? 430 : 360)) + kills * 300,
                        damageToChampions: Int(minutes * (carry ? rng.double(850...1250) : rng.double(400...900))),
                        damageTaken: Int(minutes * rng.double(600...1300)), visionScore: role == .utility ? rng.int(55...95) : rng.int(14...40),
                        objectiveDamage: rng.int(1500...14000), rankTier: rng.pick(["CHALLENGER", "GRANDMASTER", "MASTER"]),
                        rankDivision: nil, win: teamWin))
                    pid += 1
                }
            }
            let teams = [100, 200].map { team -> TeamRecord in
                let teamWin = (team == myTeam) == win
                return TeamRecord(teamId: team, win: teamWin, baronKills: teamWin ? rng.int(1...2) : rng.int(0...1),
                                  dragonKills: teamWin ? rng.int(2...4) : rng.int(0...2), towerKills: teamWin ? rng.int(7...10) : rng.int(1...5),
                                  inhibitorKills: teamWin ? rng.int(1...2) : 0, heraldKills: rng.int(0...1), hordeKills: rng.int(0...3),
                                  bans: (0..<5).map { _ in rng.pick(rolePools[rng.pick(Role.allCases)]!) })
            }
            let lp = queue == 420 ? (win ? rng.int(18...24) : -rng.int(15...20)) : nil
            result.append(MatchRecord(gameId: 7_200_000_000 + Int64(index), queueId: queue, gameMode: queue == 450 ? "ARAM" : "CLASSIC",
                                      creation: clock, durationSeconds: duration, teams: teams, participants: participants,
                                      localPuuid: localPuuid, lpChange: lp))
            clock = clock.addingTimeInterval(-Double(rng.int(2400...20_000)))
        }
        return result
    }

    static func timeline(for match: MatchRecord) -> ParticipantTimeline {
        var rng = RNG(seed: UInt64(match.gameId))
        var cs: [Int: Int] = [:]
        var total = 0
        for minute in 1...max(1, match.durationSeconds / 60) {
            total += minute < 2 ? 0 : rng.int(5...9)
            cs[minute] = total
        }
        return ParticipantTimeline(csAtMinute: cs, deathTimes: [480, 760, 1300], takedownTimes: [300, 620, 900, 1150])
    }

    // MARK: Champ select

    static var draft: DraftState {
        let allies = [
            DraftMember(cellId: 0, championId: 150, assignedRole: .top, spell1: 4, spell2: 12, name: "Kiesel", isAlly: true),
            DraftMember(cellId: 1, championId: 254, assignedRole: .jungle, spell1: 11, spell2: 4, name: "Morgenwind", isAlly: true),
            DraftMember(cellId: 2, championId: 103, assignedRole: .middle, spell1: 4, spell2: 14, name: "Ferrolux", isAlly: true),
            DraftMember(cellId: 3, championId: 222, assignedRole: .bottom, spell1: 4, spell2: 7, name: localName, isLocal: true, isAlly: true),
            DraftMember(cellId: 4, championId: 201, assignedRole: .utility, spell1: 4, spell2: 14, name: "Zinnober", isAlly: true),
        ]
        // Enemy order as the client reports it (pick order, not lanes) – Riftsight sorts it out.
        let enemies = [
            DraftMember(cellId: 5, championId: 134, assignedRole: nil, spell1: 4, spell2: 12, name: "Syndra", isAlly: false),
            DraftMember(cellId: 6, championId: 266, assignedRole: nil, spell1: 12, spell2: 4, name: "Aatrox", isAlly: false),
            DraftMember(cellId: 7, championId: 497, assignedRole: nil, spell1: 4, spell2: 14, name: "Rakan", isAlly: false),
            DraftMember(cellId: 8, championId: 64, assignedRole: nil, spell1: 4, spell2: 11, name: "Lee Sin", isAlly: false),
            DraftMember(cellId: 9, championId: 51, assignedRole: nil, spell1: 4, spell2: 21, name: "Caitlyn", isAlly: false),
        ]
        return DraftState(allies: allies, enemies: enemies, allyBans: [157, 238, 145, 875, 360],
                          enemyBans: [84, 236, 412, 141, 523], isBlueSide: true, localPickActionId: nil,
                          phase: "FINALIZATION", secondsLeft: 24)
    }

    // MARK: Loading screen

    static var scoutPlayers: [ScoutPlayer] {
        func solo(_ tier: String, _ division: String?, _ lp: Int, _ wins: Int, _ losses: Int) -> LCURankedQueue? {
            let json = """
            {"queueType":"RANKED_SOLO_5x5","tier":"\(tier)","division":\(division.map { "\"\($0)\"" } ?? "null"),"leaguePoints":\(lp),"wins":\(wins),"losses":\(losses)}
            """
            return try? JSONDecoder().decode(LCURankedQueue.self, from: Data(json.utf8))
        }
        let badge = { (title: String, detail: String, tone: PlayerBadge.Tone) in PlayerBadge(title: title, detail: detail, tone: tone) }
        return [
            ScoutPlayer(puuid: "a1", name: "Kiesel", tag: "EUW", championId: 150, role: .top, teamId: 100,
                        solo: solo("GRANDMASTER", "I", 512, 188, 160), recentGames: 20, recentWins: 12,
                        championPool: [(150, 9, 6), (266, 5, 3), (875, 3, 1)], badges: [badge("Main", "Gnar: 9 der letzten 20 Spiele", .positive)], isLoading: false),
            ScoutPlayer(puuid: "a2", name: "Morgenwind", tag: "EUW", championId: 254, role: .jungle, teamId: 100,
                        solo: solo("MASTER", "I", 241, 95, 90), recentGames: 20, recentWins: 8,
                        championPool: [(254, 6, 2), (64, 5, 3)], badges: [badge("Loss-Streak", "4 Niederlagen in Folge", .negative)], isLoading: false),
            ScoutPlayer(puuid: "a3", name: "Ferrolux", tag: "EUW", championId: 103, role: .middle, teamId: 100,
                        solo: solo("CHALLENGER", "I", 1102, 240, 190), recentGames: 20, recentWins: 13,
                        championPool: [(103, 15, 10), (134, 3, 2)], badges: [badge("OTP", "Ahri: 15 der letzten 20 Spiele", .positive)], isLoading: false),
            ScoutPlayer(puuid: localPuuid, name: localName, tag: localTag, championId: 222, role: .bottom, teamId: 100,
                        solo: solo("CHALLENGER", "I", 1284, 214, 171), recentGames: 20, recentWins: 12,
                        championPool: [(222, 7, 5), (145, 6, 3)], badges: [], isLoading: false),
            ScoutPlayer(puuid: "a5", name: "Zinnober", tag: "EUW", championId: 201, role: .utility, teamId: 100,
                        solo: solo("GRANDMASTER", "I", 488, 150, 141), recentGames: 20, recentWins: 11,
                        championPool: [(201, 4, 3), (412, 6, 3)], badges: [], isLoading: false),
            ScoutPlayer(puuid: "b1", name: "Halogen", tag: "EUW", championId: 266, role: .top, teamId: 200,
                        solo: solo("CHALLENGER", "I", 980, 301, 262), recentGames: 20, recentWins: 11,
                        championPool: [(266, 12, 7), (24, 4, 2)], badges: [badge("Main", "Aatrox: 12 der letzten 20 Spiele", .positive)], isLoading: false),
            ScoutPlayer(puuid: "b2", name: "Polarlicht", tag: "EUW", championId: 64, role: .jungle, teamId: 200,
                        solo: solo("GRANDMASTER", "I", 610, 122, 104), recentGames: 20, recentWins: 12,
                        championPool: [(64, 8, 5), (234, 6, 4)],
                        badges: [badge("Früher Ganker", "Ø 2,4 Takedowns vor Minute 6", .warning)], isLoading: false),
            ScoutPlayer(puuid: "b3", name: "Quarzkopf", tag: "EUW", championId: 134, role: .middle, teamId: 200,
                        solo: solo("MASTER", "I", 199, 80, 74), recentGames: 20, recentWins: 9,
                        championPool: [(61, 7, 4), (4, 6, 2)], badges: [badge("First Time", "Erstes Spiel auf Syndra seit 20 Spielen", .warning)], isLoading: false),
            ScoutPlayer(puuid: "b4", name: "Lotusblatt", tag: "EUW", championId: 51, role: .bottom, teamId: 200,
                        solo: solo("CHALLENGER", "I", 1040, 260, 220), recentGames: 20, recentWins: 14,
                        championPool: [(51, 9, 7), (202, 5, 3)], badges: [badge("Win-Streak", "5 Siege in Folge", .positive)], isLoading: false),
            ScoutPlayer(puuid: "b5", name: "Sternsucher", tag: "EUW", championId: 497, role: .utility, teamId: 200,
                        solo: solo("GRANDMASTER", "I", 455, 170, 166), recentGames: 20, recentWins: 10,
                        championPool: [(497, 10, 6), (89, 4, 2)], badges: [], isLoading: false),
        ]
    }

    // MARK: Accounts

    static var accounts: [LinkedAccount] {
        [
            LinkedAccount(puuid: localPuuid, gameName: localName, tagLine: localTag, region: "EUW", profileIconId: 4568,
                          level: 612, soloTier: "CHALLENGER", soloDivision: "I", soloLP: 1284, wins: 214, losses: 171),
            LinkedAccount(puuid: "demo-smurf", gameName: "Nachtfalke2", tagLine: "EUW", region: "EUW", profileIconId: 5367,
                          level: 204, soloTier: "GRANDMASTER", soloDivision: "I", soloLP: 640, wins: 120, losses: 98,
                          lastSeen: .now.addingTimeInterval(-3 * 86_400)),
        ]
    }

    static func lpHistory(for puuid: String) -> [LPPoint] {
        var rng = RNG(seed: puuid == localPuuid ? 9 : 10)
        var lp = puuid == localPuuid ? 980 : 520
        return (0..<40).map { index in
            lp += rng.chance(0.56) ? rng.int(17...24) : -rng.int(14...20)
            let date = Date().addingTimeInterval(-Double(40 - index) * 18_000)
            return LPPoint(date: date, ladderPoints: 2800 + lp, lp: lp, tier: puuid == localPuuid ? "CHALLENGER" : "GRANDMASTER", division: "I")
        }
    }

    // MARK: Clips

    struct Clip: Identifiable, Hashable {
        var id: String { title + "\(date.timeIntervalSince1970)" }
        var title: String
        var championId: Int
        var skinNum: Int
        var kills: Int
        var deaths: Int
        var assists: Int
        var queue: String
        var date: Date
        var duration: Double
        var isFullGame = false
        var favorite = false
    }

    static var clips: [Clip] {
        let now = Date()
        return [
            Clip(title: "Pentakill mit Ahri", championId: 103, skinNum: 27, kills: 12, deaths: 3, assists: 16, queue: "Ranked Solo", date: now.addingTimeInterval(-12 * 60), duration: 34, favorite: true),
            Clip(title: "Triple vor dem Baron", championId: 103, skinNum: 27, kills: 12, deaths: 3, assists: 16, queue: "Ranked Solo", date: now.addingTimeInterval(-41 * 60), duration: 28),
            Clip(title: "Flash-Charm", championId: 103, skinNum: 27, kills: 12, deaths: 3, assists: 16, queue: "Ranked Solo", date: now.addingTimeInterval(-62 * 60), duration: 18),
            Clip(title: "Elder gestohlen", championId: 64, skinNum: 11, kills: 5, deaths: 4, assists: 17, queue: "Ranked Solo", date: now.addingTimeInterval(-3 * 3600), duration: 22),
            Clip(title: "Insec auf Mid", championId: 64, skinNum: 11, kills: 5, deaths: 4, assists: 17, queue: "Ranked Solo", date: now.addingTimeInterval(-4 * 3600), duration: 15),
            Clip(title: "Herald-Flip", championId: 64, skinNum: 11, kills: 5, deaths: 4, assists: 17, queue: "Ranked Solo", date: now.addingTimeInterval(-4.2 * 3600), duration: 27),
            Clip(title: "Quadra am Drachen", championId: 134, skinNum: 1, kills: 11, deaths: 5, assists: 5, queue: "ARAM", date: now.addingTimeInterval(-5 * 3600), duration: 31),
            Clip(title: "Backdoor-Versuch", championId: 134, skinNum: 1, kills: 11, deaths: 5, assists: 5, queue: "ARAM", date: now.addingTimeInterval(-6 * 3600), duration: 44),
            Clip(title: "1v3-Outplay", championId: 268, skinNum: 2, kills: 6, deaths: 6, assists: 6, queue: "Ranked Flex", date: now.addingTimeInterval(-26 * 3600), duration: 26),
            Clip(title: "Shurima-Shuffle", championId: 268, skinNum: 2, kills: 6, deaths: 6, assists: 6, queue: "Ranked Flex", date: now.addingTimeInterval(-27 * 3600), duration: 12),
            Clip(title: "Baron gestohlen", championId: 268, skinNum: 2, kills: 6, deaths: 6, assists: 6, queue: "Ranked Flex", date: now.addingTimeInterval(-28 * 3600), duration: 19),
            Clip(title: "Ganzes Spiel – Ahri", championId: 103, skinNum: 27, kills: 12, deaths: 3, assists: 16, queue: "Ranked Solo", date: now.addingTimeInterval(-10 * 60), duration: 28 * 60 + 1, isFullGame: true),
        ]
    }

    // MARK: Collection

    /// Pretends roughly 44 % of all skins are owned, with acquisition dates spread over five years.
    static func ownedSkins(_ skins: [Int: Skin]) -> SkinInventory {
        var rng = RNG(seed: 7)
        var owned: [Int: OwnedSkin] = [:]
        var prices: [Int: Int] = [:]
        for skin in skins.values.sorted(by: { $0.id < $1.id }) where !skin.isBase {
            prices[skin.id] = skin.rarityTier.estimatedRP
            let favoured = [103, 134, 268, 222, 64].contains(skin.championId)
            if rng.chance(favoured ? 0.9 : 0.4) {
                let date = Date().addingTimeInterval(-rng.double(0...(5 * 365 * 86_400)))
                owned[skin.id] = OwnedSkin(skinId: skin.id, purchased: date)
            }
        }
        return SkinInventory(owned: owned, prices: prices)
    }

    // MARK: Live game

    static func liveGame(gameTime: Double = 1265) -> LiveAllGameData? {
        struct P {
            let champ: String, alias: String, role: String, team: String, name: String
            let k: Int, d: Int, a: Int, cs: Int, level: Int, items: [Int], spells: (String, String)
        }
        let players: [P] = [
            P(champ: "Gnar", alias: "Gnar", role: "TOP", team: "ORDER", name: "Kiesel", k: 2, d: 2, a: 3, cs: 171, level: 12, items: [3078, 3047, 1037, 3340], spells: ("SummonerFlash", "SummonerTeleport")),
            P(champ: "Vi", alias: "Vi", role: "JUNGLE", team: "ORDER", name: "Morgenwind", k: 4, d: 3, a: 6, cs: 128, level: 11, items: [6610, 3111, 1028, 3364], spells: ("SummonerSmite", "SummonerFlash")),
            P(champ: "Ahri", alias: "Ahri", role: "MIDDLE", team: "ORDER", name: "Ferrolux", k: 6, d: 1, a: 4, cs: 182, level: 13, items: [6655, 3020, 4645, 3340], spells: ("SummonerFlash", "SummonerDot")),
            P(champ: "Jinx", alias: "Jinx", role: "BOTTOM", team: "ORDER", name: localName, k: 5, d: 2, a: 5, cs: 196, level: 12, items: [3031, 3006, 1018, 1037, 3340], spells: ("SummonerFlash", "SummonerHeal")),
            P(champ: "Braum", alias: "Braum", role: "UTILITY", team: "ORDER", name: "Zinnober", k: 0, d: 3, a: 12, cs: 31, level: 10, items: [3190, 3111, 3364], spells: ("SummonerFlash", "SummonerDot")),
            P(champ: "Aatrox", alias: "Aatrox", role: "TOP", team: "CHAOS", name: "Halogen", k: 3, d: 3, a: 2, cs: 165, level: 12, items: [6610, 3047, 3133, 3340], spells: ("SummonerTeleport", "SummonerFlash")),
            P(champ: "Lee Sin", alias: "LeeSin", role: "JUNGLE", team: "CHAOS", name: "Polarlicht", k: 2, d: 4, a: 4, cs: 119, level: 10, items: [3071, 3111, 3364], spells: ("SummonerFlash", "SummonerSmite")),
            P(champ: "Syndra", alias: "Syndra", role: "MIDDLE", team: "CHAOS", name: "Quarzkopf", k: 2, d: 4, a: 2, cs: 175, level: 12, items: [6655, 3020, 3916, 3340], spells: ("SummonerFlash", "SummonerTeleport")),
            P(champ: "Caitlyn", alias: "Caitlyn", role: "BOTTOM", team: "CHAOS", name: "Lotusblatt", k: 3, d: 3, a: 1, cs: 188, level: 11, items: [3031, 3006, 3133, 3363], spells: ("SummonerFlash", "SummonerBarrier")),
            P(champ: "Rakan", alias: "Rakan", role: "UTILITY", team: "CHAOS", name: "Sternsucher", k: 0, d: 3, a: 6, cs: 28, level: 9, items: [3190, 3158, 3364], spells: ("SummonerFlash", "SummonerExhaust")),
        ]
        let allPlayers: [[String: Any]] = players.map { p in
            [
                "championName": p.champ, "rawChampionName": "game_character_displayname_\(p.alias)", "isBot": false,
                "isDead": false, "level": p.level, "position": p.role, "riotId": "\(p.name)#EUW", "riotIdGameName": p.name,
                "summonerName": p.name, "respawnTimer": 0, "team": p.team, "skinID": 0,
                "items": p.items.enumerated().map { ["itemID": $0.element, "slot": $0.offset, "count": 1, "price": 0, "displayName": "", "consumable": false] },
                "scores": ["kills": p.k, "deaths": p.d, "assists": p.a, "creepScore": p.cs, "wardScore": 18.0],
                "summonerSpells": [
                    "summonerSpellOne": ["displayName": "", "rawDisplayName": "GeneratedTip_SummonerSpell_\(p.spells.0)_DisplayName"],
                    "summonerSpellTwo": ["displayName": "", "rawDisplayName": "GeneratedTip_SummonerSpell_\(p.spells.1)_DisplayName"],
                ],
            ]
        }
        let events: [[String: Any]] = [
            ["EventID": 0, "EventName": "GameStart", "EventTime": 0.05],
            ["EventID": 1, "EventName": "ChampionKill", "EventTime": 312, "KillerName": "Ferrolux", "VictimName": "Quarzkopf", "Assisters": ["Morgenwind"]],
            ["EventID": 2, "EventName": "FirstBlood", "EventTime": 312, "Recipient": "Ferrolux"],
            ["EventID": 3, "EventName": "DragonKill", "EventTime": 545, "KillerName": "Morgenwind", "DragonType": "Fire", "Stolen": "False"],
            ["EventID": 4, "EventName": "HordeKill", "EventTime": 610, "KillerName": "Polarlicht", "Stolen": "False"],
            ["EventID": 5, "EventName": "TurretKilled", "EventTime": 840, "KillerName": localName, "TurretKilled": "Turret_T2_R_03_A"],
            ["EventID": 6, "EventName": "DragonKill", "EventTime": 1020, "KillerName": "Morgenwind", "DragonType": "Earth", "Stolen": "False"],
            ["EventID": 7, "EventName": "ChampionKill", "EventTime": 1180, "KillerName": localName, "VictimName": "Lotusblatt", "Assisters": ["Zinnober"]],
        ]
        let root: [String: Any] = [
            "activePlayer": [
                "abilities": ["Q": ["abilityLevel": 5], "W": ["abilityLevel": 2], "E": ["abilityLevel": 2], "R": ["abilityLevel": 2]],
                "championStats": ["abilityHaste": 0, "currentHealth": 1420, "maxHealth": 1720, "attackRange": 525],
                "currentGold": 1460.0, "level": 12, "riotId": "\(localName)#EUW", "riotIdGameName": localName, "summonerName": localName,
            ],
            "allPlayers": allPlayers,
            "events": ["Events": events],
            "gameData": ["gameMode": "CLASSIC", "gameTime": gameTime, "mapName": "Map11", "mapNumber": 11, "mapTerrain": "Infernal"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        do {
            return try JSONDecoder().decode(LiveAllGameData.self, from: data)
        } catch {
            DebugLog.shared.add("demo", "Demo-Livedaten ungültig: \(error)", error: true)
            return nil
        }
    }
}
