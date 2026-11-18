"""counterpicks.json – lane matchups with Bradley-Terry expectation and Empirical-Bayes smoothing.

For target B and counter A in the same role:
    μ0 = σ(logit(WR_A) − logit(WR_B)),  WR^ = (W + m·μ0) / (N + m),  delta = WR^ − μ0
Entries are from the counter's perspective (positive delta = A beats B more than expected).
"""
from __future__ import annotations

from collections import defaultdict
from typing import Any

from .config import ROLES, Settings
from .features import lane_metrics
from .stats import blend, logit, rnd, sigmoid, smoothed


class CounterAccumulator:
    def __init__(self) -> None:
        self.base: dict[tuple[int, str], list[int]] = defaultdict(lambda: [0, 0])
        self.champ_games: dict[int, int] = defaultdict(int)
        # (target B, role, counter A) → [games, winsA, tl_games, gd15_sum, cs15_sum, lane_kills]
        self.pairs: dict[tuple[int, str, int], list[float]] = defaultdict(lambda: [0, 0, 0, 0.0, 0.0, 0])

    def add(self, match: dict[str, Any]) -> None:
        lanes: dict[str, dict[int, dict[str, Any]]] = defaultdict(dict)
        duplicate: set[tuple[str, int]] = set()
        for p in match["p"]:
            if p["role"]:
                s = self.base[(p["champ"], p["role"])]
                s[0] += 1
                s[1] += int(p["win"])
                self.champ_games[p["champ"]] += 1
                if p["team"] in lanes[p["role"]]:
                    duplicate.add((p["role"], p["team"]))
                lanes[p["role"]][p["team"]] = p
        tl = match.get("tl")
        for role in ROLES:
            pair = lanes.get(role, {})
            if 100 not in pair or 200 not in pair or (role, 100) in duplicate or (role, 200) in duplicate:
                continue
            for a, b in ((pair[100], pair[200]), (pair[200], pair[100])):
                s = self.pairs[(b["champ"], role, a["champ"])]
                s[0] += 1
                s[1] += int(a["win"])
                if tl:
                    metrics = lane_metrics(tl, a["pid"], b["pid"])
                    if metrics:
                        s[2] += 1
                        s[3] += metrics[0]
                        s[4] += metrics[1]
                        s[5] += metrics[2]

    def base_winrates(self) -> dict[tuple[int, str], float]:
        return {k: smoothed(w, n, 0.5, 100) for k, (n, w) in self.base.items()}

    def lane_shares(self) -> dict[tuple[int, str], float]:
        return {(cid, role): n / max(self.champ_games[cid], 1) for (cid, role), (n, _w) in self.base.items()}

    def finish(self, settings: Settings, prev: dict[str, float]) -> tuple[dict[str, dict[str, Any]], dict[str, float]]:
        base_wr = self.base_winrates()
        shares = self.lane_shares()
        by_target: dict[tuple[int, str], list[tuple[int, list[float]]]] = defaultdict(list)
        for (b, role, a), stats in self.pairs.items():
            by_target[(b, role)].append((a, stats))

        champions: dict[str, dict[str, Any]] = {}
        summary: dict[str, float] = {}
        for (b, role), entries in by_target.items():
            games_b, _wins_b = self.base[(b, role)]
            if games_b < settings.counter_base_min_games or shares.get((b, role), 0) < settings.min_lane_share:
                continue
            wr_b = base_wr[(b, role)]
            counters = []
            for a, (n, w, tl_n, gd, cs, lk) in entries:
                if n < settings.counter_min_games or (a, role) not in base_wr:
                    continue
                mu0 = sigmoid(logit(base_wr[(a, role)]) - logit(wr_b))
                wr = smoothed(w, n, mu0, settings.counter_prior)
                prev_key = f"{b}|{role}|{a}"
                wr = blend(wr, int(n), prev.get(prev_key), settings.blend_target_matchup)
                summary[prev_key] = rnd(wr)
                counters.append({
                    "championId": a, "games": int(n), "winrate": rnd(wr), "delta": rnd(wr - mu0),
                    "goldDiff15": rnd(gd / tl_n, 1) if tl_n else None,
                    "csDiff15": rnd(cs / tl_n, 1) if tl_n else None,
                    "laneKillRate": rnd(lk / tl_n, 3) if tl_n else None,
                })
            if not counters:
                continue
            counters.sort(key=lambda e: -e["delta"])
            k = settings.counters_per_side
            if len(counters) > 2 * k:
                counters = counters[:k] + counters[-k:]
            champions.setdefault(str(b), {})[role] = {"games": games_b, "winrate": rnd(wr_b), "counters": counters}
        return champions, summary
