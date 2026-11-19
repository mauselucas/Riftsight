"""aram_augments.json – ARAM: Mayhem and Arena (CHERRY). Arena "win" = placement ≤ 4, EB m=40."""
from __future__ import annotations

import math
from collections import defaultdict
from typing import Any

from .builds import Block
from .config import Settings
from .features import is_legendary
from .stats import assign_tier, composite_scores, rnd, smoothed

MODE_KEYS = {"mayhem": "ARAM_MAYHEM", "arena": "CHERRY"}


class AugmentAccumulator:
    def __init__(self, items: dict[int, dict], rarity: dict[int, str]):
        self.items = items
        self.rarity = rarity
        self.participants: dict[str, int] = defaultdict(int)
        self.aug: dict[tuple[str, int], list] = defaultdict(lambda: [0, 0, 0])        # games, wins, placement sum
        self.champ_aug: dict[tuple[str, int, int], list] = defaultdict(lambda: [0, 0, 0])
        self.builds: dict[tuple[str, int], Block] = defaultdict(Block)

    def add(self, match: dict[str, Any]) -> None:
        mode = match["mode"]
        if mode not in MODE_KEYS:
            return
        for p in match["p"]:
            placement = p.get("placement") or 0
            win = int(placement <= 4) if mode == "arena" and placement else int(p["win"])
            self.participants[mode] += 1
            for a in p["augments"]:
                for s in (self.aug[(mode, a)], self.champ_aug[(mode, p["champ"], a)]):
                    s[0] += 1
                    s[1] += win
                    s[2] += placement
            legendaries = [i for i in p["items"][:6] if is_legendary(i, self.items)]
            self.builds[(mode, p["champ"])].add({**p, "win": bool(win)}, None, legendaries, "ALL", self.items, True, inventory_core=True)

    def _stat(self, mode: str, aug_id: int, g: int, w: int, psum: int, prior: float) -> dict[str, Any]:
        stat = {"id": aug_id, "rarity": self.rarity.get(aug_id, "silver"), "winrate": rnd(smoothed(w, g, prior, 40)),
                "pickrate": rnd(g / max(self.participants[mode], 1)), "games": g}
        if mode == "arena" and psum:
            stat["avgPlacement"] = rnd((psum + 40 * 4.5) / (g + 40), 2)
            stat["top4Rate"] = stat["winrate"]
        return stat

    def finish(self, s: Settings) -> dict[str, Any]:
        modes: dict[str, Any] = {}
        for mode, key in MODE_KEYS.items():
            rows = [(a, *v) for (m, a), v in self.aug.items() if m == mode and v[0] >= s.augment_min_games]
            if not rows:
                continue
            prior = sum(r[2] for r in rows) / max(sum(r[1] for r in rows), 1)
            stats = [self._stat(mode, a, g, w, ps, prior) for a, g, w, ps in rows]
            scores = composite_scores([(0.8, [x["winrate"] for x in stats]), (0.2, [math.log(x["pickrate"] + 1e-4) for x in stats])])
            for x, sc in zip(stats, scores):
                x["tier"] = assign_tier(sc)
            per_champ: dict[str, list] = defaultdict(list)
            for (m, cid, a), (g, w, ps) in self.champ_aug.items():
                if m == mode and g >= s.champion_augment_min_games:
                    x = self._stat(mode, a, g, w, ps, prior)
                    x["tier"] = assign_tier(50 + 10 * (x["winrate"] - prior) / 0.03)
                    per_champ[str(cid)].append(x)
            builds = {}
            for (m, cid), block in self.builds.items():
                if m == mode and block.games >= s.build_min_games:
                    out = block.output(s, full=True)
                    builds[str(cid)] = {k: out[k] for k in ("games", "winrate", "coreBuild", "boots", "completedItems") if k in out}
            modes[key] = {
                "augments": sorted(stats, key=lambda x: -x["winrate"]),
                "championAugments": {c: sorted(v, key=lambda x: -x["winrate"])[:6] for c, v in per_champ.items()},
                "builds": builds,
            }
        return modes
