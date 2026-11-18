import Foundation
import Testing
@testable import RiftsightCore

@Suite("Hungarian & lane assignment")
struct LaneAssignmentTests {
    @Test func `hungarian finds the optimal assignment`() {
        let cost: [[Double]] = [
            [4, 1, 3],
            [2, 0, 5],
            [3, 2, 2],
        ]
        let assignment = HungarianSolver.solve(cost)
        #expect(HungarianSolver.totalCost(cost, assignment) == 5)
        #expect(Set(assignment) == [0, 1, 2])
    }

    @Test func `hungarian handles 5x5 with a forced column`() {
        var cost = [[Double]](repeating: [1, 2, 3, 4, 5], count: 5)
        cost[3] = [100, 100, 0, 100, 100]
        let assignment = HungarianSolver.solve(cost)
        #expect(assignment[3] == 2)
        #expect(Set(assignment).count == 5)
    }

    @Test func `smite locks the jungle role`() {
        // Champion 1 is usually TOP, but carries Smite.
        let rates: [Int: [Role: Double]] = [
            1: [.top: 90, .jungle: 5],
            2: [.jungle: 80, .top: 20],
            3: [.middle: 95],
            4: [.bottom: 95],
            5: [.utility: 95],
        ]
        let assigner = LaneAssigner(rates: rates)
        let enemies = [
            LaneAssigner.Enemy(slot: 0, championId: 1, hasSmite: true),
            LaneAssigner.Enemy(slot: 1, championId: 2, hasSmite: false),
            LaneAssigner.Enemy(slot: 2, championId: 3, hasSmite: false),
            LaneAssigner.Enemy(slot: 3, championId: 4, hasSmite: false),
            LaneAssigner.Enemy(slot: 4, championId: 5, hasSmite: false),
        ]
        let result = assigner.assign(enemies)
        #expect(result[0] == .jungle)
        #expect(result[1] == .top)
        #expect(result[2] == .middle)
    }

    @Test func `manual overrides survive reassignment`() {
        let assigner = LaneAssigner(rates: [1: [.top: 100], 2: [.middle: 100]])
        let enemies = [LaneAssigner.Enemy(slot: 0, championId: 1, hasSmite: false),
                       LaneAssigner.Enemy(slot: 1, championId: 2, hasSmite: false)]
        let result = assigner.assign(enemies, locked: [0: .middle])
        #expect(result[0] == .middle)
        #expect(result[1] != .middle)
    }
}

@Suite("Cooldowns & items")
struct CooldownTests {
    @Test(arguments: [(0.0, 300.0), (10.0, 272.727), (18.0, 254.237)])
    func `haste formula`(haste: Double, expected: Double) {
        #expect(abs(CooldownCalculator.apply(haste: haste, to: 300) - expected) < 0.01)
    }

    @Test func `ultimate rank follows 6 11 16`() {
        #expect(CooldownCalculator.ultimateRank(level: 5) == 0)
        #expect(CooldownCalculator.ultimateRank(level: 6) == 1)
        #expect(CooldownCalculator.ultimateRank(level: 11) == 2)
        #expect(CooldownCalculator.ultimateRank(level: 18) == 3)
    }

    @Test func `ability haste parses from german item text`() {
        let text = "<mainText><stats><attention> 20</attention>&nbsp;Fähigkeitstempo</stats></mainText>"
        #expect(Item.stat(named: ["Fähigkeitstempo"], in: text) == 20)
    }

    @Test func `next purchase picks the most expensive affordable component`() {
        let items: [Int: Item] = [
            1: makeItem(1, price: 400, total: 400),
            2: makeItem(2, price: 300, total: 1100, from: [1]),
            3: makeItem(3, price: 900, total: 2900, from: [2, 2]),
        ]
        let next = SituationalItemEngine.nextPurchase(target: 3, owned: [2], gold: 1200, items: items)
        #expect(next?.buyNowItemId == 2)
        #expect(next?.missingGold == 1600 - 1200)  // 900 recipe + 700 for the second component
    }

    func makeItem(_ id: Int, price: Int, total: Int, from: [Int] = []) -> Item {
        Item(id: id, name: "Item \(id)", description: nil, active: false, inStore: true, from: from, to: [],
             categories: [], price: price, priceTotal: total, iconPath: nil, requiredChampion: nil, displayInItemSets: true)
    }
}

@Suite("Parsing")
struct ParsingTests {
    @Test func `lockfile parsing`() throws {
        let creds = try #require(LockfileLocator.parse(lockfile: "LeagueClient:1234:53210:s3cr3t:https"))
        #expect(creds.port == 53210)
        #expect(creds.password == "s3cr3t")
        #expect(creds.pid == 1234)
    }

    @Test func `process argument parsing`() throws {
        let args = "/Applications/League of Legends.app/.../LeagueClientUx --app-pid=99 --app-port=61234 --remoting-auth-token=abcDEF --other"
        let creds = try #require(LockfileLocator.parse(processArguments: args))
        #expect(creds.port == 61234)
        #expect(creds.password == "abcDEF")
    }

    @Test func `websocket topic naming`() {
        #expect(LCUWebSocketClient.topic(for: "/lol-champ-select/v1/session") == "OnJsonApiEvent_lol-champ-select_v1_session")
    }

    @Test func `wamp event parsing`() throws {
        let text = #"[8,"OnJsonApiEvent_lol-gameflow_v1_gameflow-phase",{"data":"ChampSelect","eventType":"Update","uri":"/lol-gameflow/v1/gameflow-phase"}]"#
        let event = try #require(LCUWebSocketClient.parse(text))
        #expect(event.uri == "/lol-gameflow/v1/gameflow-phase")
        #expect(event.decode(String.self) == "ChampSelect")
    }

    @Test func `live client spell keys`() {
        let ref = LivePlayer.SpellRef(displayName: "Blitz", rawDisplayName: "GeneratedTip_SummonerSpell_SummonerFlash_DisplayName")
        #expect(ref.spellId == 4)
    }

    @Test func `cs benchmark grows with time`() {
        #expect(CSBenchmark.minionsAvailable(at: 30) == 0)
        #expect(CSBenchmark.minionsAvailable(at: 10 * 60) > 100)
    }
}

@Suite("Post game")
struct PostGameTests {
    @Test func `mvp is on the winning team and ace on the losing team`() {
        var participants: [ParticipantRecord] = []
        for i in 1...10 {
            participants.append(ParticipantRecord(
                participantId: i, teamId: i <= 5 ? 100 : 200, puuid: "p\(i)", gameName: "P\(i)", tagLine: "EUW",
                championId: i, role: Role.allCases[(i - 1) % 5], champLevel: 15, spell1Id: 4, spell2Id: 14, keystoneId: 8005,
                subStyleId: 8000, items: [], kills: i, deaths: 3, assists: 5, cs: 180, gold: 10000 + i * 100,
                damageToChampions: 15000 + i * 1000, damageTaken: 20000, visionScore: 20, objectiveDamage: 3000, win: i <= 5))
        }
        let match = MatchRecord(gameId: 1, queueId: 420, gameMode: "CLASSIC", creation: .now, durationSeconds: 1800,
                                teams: [TeamRecord(teamId: 100, win: true), TeamRecord(teamId: 200, win: false)],
                                participants: participants, localPuuid: "p1")
        let scores = PostGameAnalyzer.scores(for: match)
        let mvp = scores.values.first { $0.isMVP }
        let ace = scores.values.first { $0.isACE }
        #expect(mvp.map { $0.participantId <= 5 } == true)
        #expect(ace.map { $0.participantId > 5 } == true)
        #expect(Set(scores.values.map(\.placement)) == Set(1...10))
    }
}
