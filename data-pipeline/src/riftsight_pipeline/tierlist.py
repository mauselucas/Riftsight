"""tierlist.json – brackets (EMERALD_PLUS / DIAMOND_PLUS / MASTER_PLUS) × platforms (ALL + each) × modes
(ranked, aram, arena, duo).

ranked score = clamp(50 + 10·(0.65 z(WR_EB) + 0.20 z(ln(PR+1e-4)) + 0.15 z(ln(BR+1e-4)))), WR_EB with m=100 towards 0.5.
"""
from __future__ import annotations

import math
from collections import defaultdict
from typing import Any

from .config import RANK_BRACKETS, Settings
from .stats import assign_tier, blend, composite_scores, logit, rnd, sigmoid, smoothed

EARLY, LATE = 1500, 1920


def _bucket(duration: int) -> str:
    return "early" if duration < EARLY else ("mid" if duration < LATE else "late")


class _Group:
    def __init__(self) -> None:
        self.ranked_matches = 0
        self.ranked: dict[tuple[int, str], list[int]] = defaultdict(lambda: [0, 0])
        self.curve: dict[tuple[int, str, str], list[int]] = defaultdict(lambda: [0, 0])
        self.champ_games: dict[int, int] = defaultdict(int)
        self.bans: dict[int, int] = defaultdict(int)
        self.duo: dict[tuple[int, int], list[int]] = defaultdict(lambda: [0, 0])
        self.aram_matches = 0
        self.aram: dict[int, list[int]] = defaultdict(lambda: [0, 0])
        self.aram_curve: dict[tuple[int, str], list[int]] = defaultdict(lambda: [0, 0])
        self.arena_matches = 0
        self.arena: dict[int, list[int]] = defaultdict(lambda: [0, 0, 0, 0])  # games, firsts, top4, placement sum


class TierlistAccumulator:
    def __init__(self, platforms: tuple[str, ...]):
        self.platforms = platforms
        self.groups: dict[tuple[str, str], _Group] = defaultdict(_Group)

    def _targets(self, match: dict[str, Any]) -> list[_Group]:
        brackets = [b for b, buckets in RANK_BRACKETS.items() if match["bucket"] in buckets]
        return [self.groups[(b, p)] for b in brackets for p in ("ALL", match["platform"])]

    def add(self, match: dict[str, Any]) -> None:
        mode = match["mode"]
        if mode not in ("ranked", "aram", "arena"):
            return
        targets = self._targets(match)
        bucket = _bucket(match["duration"])
        participants = match["p"]
        if mode == "ranked":
            bot = {p["team"]: p for p in participants if p["role"] == "BOTTOM"}
            sup = {p["team"]: p for p in participants if p["role"] == "UTILITY"}
            for g in targets:
                g.ranked_matches += 1
                for cid in set(match["bans"]):
                    g.bans[cid] += 1
                for p in participants:
                    if not p["role"]:
                        continue
                    win = int(p["win"])
                    s = g.ranked[(p["champ"], p["role"])]
                    s[0] += 1
                    s[1] += win
                    c = g.curve[(p["champ"], p["role"], bucket)]
                    c[0] += 1
                    c[1] += win
                    g.champ_games[p["champ"]] += 1
                for team, b in bot.items():
                    if team in sup:
                        d = g.duo[(b["champ"], sup[team]["champ"])]
                        d[0] += 1
                        d[1] += int(b["win"])
        elif mode == "aram":
            for g in targets:
                g.aram_matches += 1
                for p in participants:
                    s = g.aram[p["champ"]]
                    s[0] += 1
                    s[1] += int(p["win"])
                    c = g.aram_curve[(p["champ"], bucket)]
                    c[0] += 1
                    c[1] += int(p["win"])
        else:
            for g in targets:
                g.arena_matches += 1
                for p in participants:
                    placement = p.get("placement") or (1 if p["win"] else 8)
                    s = g.arena[p["champ"]]
                    s[0] += 1
                    s[1] += int(placement == 1)
                    s[2] += int(placement <= 4)
                    s[3] += placement

    # ------------------------------------------------------------------------------------

    def finish(self, settings: Settings, prev: dict[str, float]) -> tuple[list[dict[str, Any]], dict[str, float]]:
        """Returns (brackets, summary) – the summary feeds next patch's winrateDelta/blending."""
        brackets: list[dict[str, Any]] = []
        summary: dict[str, float] = {}
        for rank in RANK_BRACKETS:
            for platform in ("ALL", *self.platforms):
                g = self.groups.get((rank, platform))
                if g is None:
                    continue
                key = f"{rank}|{platform}"
                modes = {
                    "ranked": self._ranked(g, settings, prev, key, summary),
                    "aram": self._aram(g, settings, prev, key, summary),
                    "arena": self._arena(g, settings),
                    "duo": self._duo(g, settings),
                }
                brackets.append({"rank": rank, "platform": platform, "modes": modes})
        return brackets, summary

    @staticmethod
    def _rank(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        rows.sort(key=lambda r: -r["score"])
        for i, row in enumerate(rows, start=1):
            row["rank"] = i
        return rows

    def _ranked(self, g: _Group, s: Settings, prev: dict[str, float], key: str, summary: dict[str, float]) -> list[dict[str, Any]]:
        total = max(g.ranked_matches, 1)
        valid = []
        for (cid, role), (games, wins) in g.ranked.items():
            share = games / max(g.champ_games[cid], 1)
            if games < s.tier_min_games or share < s.min_lane_share:
                continue
            wr = smoothed(wins, games, 0.5, 100)
            prev_wr = prev.get(f"{key}|ranked|{cid}|{role}")
            wr = blend(wr, games, prev_wr, s.blend_target_tier)
            summary[f"{key}|ranked|{cid}|{role}"] = rnd(wr)
            valid.append((cid, role, games, wins, share, wr, prev_wr))
        if not valid:
            return []
        scores = composite_scores([
            (0.65, [v[5] for v in valid]),
            (0.20, [math.log(v[2] / total + 1e-4) for v in valid]),
            (0.15, [math.log(g.bans.get(v[0], 0) / total + 1e-4) for v in valid]),
        ])
        rows = []
        for (cid, role, games, wins, share, wr, prev_wr), score in zip(valid, scores):
            curve = {b: rnd(smoothed(g.curve[(cid, role, b)][1], g.curve[(cid, role, b)][0], wr, 50), 3)
                     for b in ("early", "mid", "late")}
            rows.append({
                "championId": cid, "role": role, "laneShare": rnd(share, 3), "score": rnd(score, 1),
                "tier": assign_tier(score), "winrate": rnd(wr), "winrateDelta": rnd(wr - prev_wr) if prev_wr is not None else None,
                "pickrate": rnd(games / total), "banrate": rnd(g.bans.get(cid, 0) / total), "games": games,
                "powerCurve": curve if games >= 3 * s.tier_min_games else None,
            })
        return self._rank(rows)

    def _aram(self, g: _Group, s: Settings, prev: dict[str, float], key: str, summary: dict[str, float]) -> list[dict[str, Any]]:
        total = max(g.aram_matches, 1)
        valid = []
        for cid, (games, wins) in g.aram.items():
            if games < s.tier_min_games:
                continue
            wr = smoothed(wins, games, 0.5, 100)
            prev_wr = prev.get(f"{key}|aram|{cid}")
            wr = blend(wr, games, prev_wr, s.blend_target_tier)
            summary[f"{key}|aram|{cid}"] = rnd(wr)
            valid.append((cid, games, wr, prev_wr))
        if not valid:
            return []
        scores = composite_scores([(0.85, [v[2] for v in valid]), (0.15, [math.log(v[1] / total + 1e-4) for v in valid])])
        rows = []
        for (cid, games, wr, prev_wr), score in zip(valid, scores):
            curve = {b: rnd(smoothed(g.aram_curve[(cid, b)][1], g.aram_curve[(cid, b)][0], wr, 50), 3) for b in ("early", "mid", "late")}
            rows.append({"championId": cid, "role": "ALL", "laneShare": 1.0, "score": rnd(score, 1), "tier": assign_tier(score),
                         "winrate": rnd(wr), "winrateDelta": rnd(wr - prev_wr) if prev_wr is not None else None,
                         "pickrate": rnd(games / total), "games": games, "powerCurve": curve})
        return self._rank(rows)

    def _arena(self, g: _Group, s: Settings) -> list[dict[str, Any]]:
        total = max(g.arena_matches, 1)
        valid = [(cid, *v) for cid, v in g.arena.items() if v[0] >= s.tier_min_games]
        if not valid:
            return []
        mean_top4 = sum(v[3] for v in valid) / max(sum(v[1] for v in valid), 1)
        mean_first = sum(v[2] for v in valid) / max(sum(v[1] for v in valid), 1)
        top4 = [smoothed(v[3], v[1], mean_top4, 40) for v in valid]
        first = [smoothed(v[2], v[1], mean_first, 40) for v in valid]
        placement = [(v[4] + 40 * 4.5) / (v[1] + 40) for v in valid]
        scores = composite_scores([(0.5, top4), (0.3, [-p for p in placement]), (0.2, first)])
        rows = []
        for i, (cid, games, _firsts, _top4, _psum) in enumerate(valid):
            rows.append({"championId": cid, "role": "ALL", "laneShare": 1.0, "score": rnd(scores[i], 1),
                         "tier": assign_tier(scores[i]), "winrate": rnd(first[i]), "pickrate": rnd(games / total),
                         "games": games, "avgPlacement": rnd(placement[i], 2), "top4Rate": rnd(top4[i], 3)})
        return self._rank(rows)

    def _duo(self, g: _Group, s: Settings) -> list[dict[str, Any]]:
        total = max(g.ranked_matches, 1)
        base = {k: smoothed(w, n, 0.5, 100) for k, (n, w) in g.ranked.items()}
        valid = []
        for (bot, sup), (games, wins) in g.duo.items():
            if games < s.duo_min_games or (bot, "BOTTOM") not in base or (sup, "UTILITY") not in base:
                continue
            mu = sigmoid(logit(base[(bot, "BOTTOM")]) + logit(base[(sup, "UTILITY")]))
            wr = smoothed(wins, games, mu, s.duo_prior)
            valid.append((bot, sup, games, wr, wr - mu))
        if not valid:
            return []
        scores = composite_scores([(0.6, [v[3] for v in valid]), (0.25, [v[4] for v in valid]),
                                   (0.15, [math.log(v[2] / total + 1e-4) for v in valid])])
        rows = [{"championId": bot, "role": "BOTTOM", "partnerChampionId": sup, "partnerRole": "UTILITY",
                 "score": rnd(score, 1), "tier": assign_tier(score), "winrate": rnd(wr), "pickrate": rnd(games / total),
                 "games": games}
                for (bot, sup, games, wr, _syn), score in zip(valid, scores)]
        return self._rank(rows)[:150]
