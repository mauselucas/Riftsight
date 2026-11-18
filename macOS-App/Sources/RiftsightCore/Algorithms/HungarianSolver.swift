import Foundation

/// Kuhn–Munkres (Hungarian) algorithm for square minimum-cost assignment, O(n³).
public enum HungarianSolver {
    /// Returns `assignment[row] = column` minimising the total cost.
    public static func solve(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        guard n > 0 else { return [] }
        precondition(cost.allSatisfy { $0.count == n }, "HungarianSolver needs a square matrix")

        let inf = Double.greatestFiniteMagnitude / 4
        // 1-indexed potentials (classic e-maxx formulation).
        var u = [Double](repeating: 0, count: n + 1)
        var v = [Double](repeating: 0, count: n + 1)
        var p = [Int](repeating: 0, count: n + 1)   // p[column] = row
        var way = [Int](repeating: 0, count: n + 1)

        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = [Double](repeating: inf, count: n + 1)
            var used = [Bool](repeating: false, count: n + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = inf
                var j1 = 0
                for j in 1...n where !used[j] {
                    let cur = min(cost[i0 - 1][j - 1], inf) - u[i0] - v[j]
                    if cur < minv[j] {
                        minv[j] = cur
                        way[j] = j0
                    }
                    if minv[j] < delta {
                        delta = minv[j]
                        j1 = j
                    }
                }
                for j in 0...n {
                    if used[j] {
                        u[p[j]] += delta
                        v[j] -= delta
                    } else {
                        minv[j] -= delta
                    }
                }
                j0 = j1
            } while p[j0] != 0
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }

        var assignment = [Int](repeating: -1, count: n)
        for j in 1...n where p[j] > 0 { assignment[p[j] - 1] = j - 1 }
        return assignment
    }

    public static func totalCost(_ cost: [[Double]], _ assignment: [Int]) -> Double {
        zip(cost.indices, assignment).reduce(0) { $0 + cost[$1.0][$1.1] }
    }
}

/// Enemy lane detection: Smite ⇒ Jungle, otherwise optimal 1:1 role assignment on −log(P(champion, role)).
public struct LaneAssigner: Sendable {
    public struct Enemy: Sendable, Hashable {
        public let slot: Int
        public let championId: Int
        public let hasSmite: Bool

        public init(slot: Int, championId: Int, hasSmite: Bool) {
            self.slot = slot
            self.championId = championId
            self.hasSmite = hasSmite
        }
    }

    /// championId → role → play rate (any scale; normalised per champion).
    let rates: [Int: [Role: Double]]

    public init(rates: [Int: [Role: Double]]) {
        self.rates = rates
    }

    func probability(_ championId: Int, _ role: Role) -> Double {
        guard championId > 0, let roleRates = rates[championId] else { return 0.2 }
        let total = roleRates.values.reduce(0, +)
        guard total > 0 else { return 0.2 }
        return (roleRates[role] ?? 0) / total
    }

    /// Returns slot → role for up to five enemies. `locked` roles (manual overrides) are kept as-is.
    public func assign(_ enemies: [Enemy], locked: [Int: Role] = [:]) -> [Int: Role] {
        let roles = Role.allCases
        var result = locked
        let freeEnemies = enemies.filter { locked[$0.slot] == nil }
        let freeRoles = roles.filter { !locked.values.contains($0) }
        guard !freeEnemies.isEmpty, !freeRoles.isEmpty else { return result }

        let smiteCount = freeEnemies.filter(\.hasSmite).count
        let size = max(freeEnemies.count, freeRoles.count)
        let big = 1e6
        var cost = [[Double]](repeating: [Double](repeating: big, count: size), count: size)
        for (r, enemy) in freeEnemies.enumerated() {
            for (c, role) in freeRoles.enumerated() {
                if enemy.hasSmite && smiteCount == 1 {
                    cost[r][c] = role == .jungle ? 0 : big
                } else if smiteCount == 1 && role == .jungle && freeRoles.contains(.jungle) {
                    cost[r][c] = big
                } else {
                    cost[r][c] = -log(max(probability(enemy.championId, role), 1e-4))
                }
            }
        }
        // Padding rows/columns cost 0 so they absorb whatever is left.
        for r in freeEnemies.count..<size { for c in 0..<size { cost[r][c] = 0 } }
        for c in freeRoles.count..<size { for r in 0..<size { cost[r][c] = 0 } }

        let assignment = HungarianSolver.solve(cost)
        for (r, enemy) in freeEnemies.enumerated() {
            let c = assignment[r]
            if c >= 0 && c < freeRoles.count { result[enemy.slot] = freeRoles[c] }
        }
        return result
    }
}
