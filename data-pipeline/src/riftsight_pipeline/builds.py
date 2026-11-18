"""matchup_runes.json + item_stats.json (one pass over ranked matches)."""
from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any

from .config import ROLES, Settings
from .features import enemy_context, is_legendary, is_upgraded_boots
from .stats import rnd, smoothed, wilson_lower

CONTEXTS = ("vsHeavyHealing", "vsShields", "vsHeavyAP", "vsHeavyAD", "vsTanks", "vsFedCrit")


def _inc(d: dict, key: Any, win: int) -> None:
    s = d.get(key)
    if s is None:
        d[key] = [1, win]
    else:
        s[0] += 1
        s[1] += win


def _best(stats: dict, total: int, min_share: float) -> tuple[Any, int, int] | None:
    if not stats:
        return None
    cands = [(k, g, w) for k, (g, w) in stats.items() if g >= min_share * total]
    if not cands:
        k, (g, w) = max(stats.items(), key=lambda kv: kv[1][0])
        return k, g, w
    return max(cands, key=lambda c: wilson_lower(c[2], c[1]))


def archetype(item_ids: list[int], items: dict[int, dict], role: str | None) -> str:
    def n(cat: str) -> int:
        return sum(1 for i in item_ids if cat in ((items.get(i) or {}).get("categories") or []))
    tanky = sum(1 for i in item_ids if (c := set((items.get(i) or {}).get("categories") or []))
                and c & {"Health", "Armor", "SpellBlock"} and not c & {"Damage", "SpellDamage", "CriticalStrike"})
    if n("CriticalStrike") >= 2:
        return "Krit"
    if n("SpellDamage") >= 2:
        if role == "UTILITY" and n("ManaRegen") >= 2:
            return "Heilung & Schilde"
        if n("Health") >= 2:
            return "Kampfmagier"
        return "Burst" if n("MagicPenetration") >= 1 else "Dauerschaden"
    if n("OnHit") + n("AttackSpeed") >= 3:
        return "On-Hit & Angriffstempo"
    if n("Damage") >= 2 and n("Health") >= 2:
        return "Bruiser"
    if n("ArmorPenetration") >= 2:
        return "Letalität"
    if tanky >= 2:
        if n("Damage") >= 1:
            return "Tank-Bruiser"
        if role == "UTILITY":
            return "Engage"
        return "Anti-AD" if n("Armor") >= 2 and n("SpellBlock") == 0 else "Tank"
    return "Bruiser" if n("Health") >= 1 else "Dauerschaden"


def complete_sequence(seq: list[str], max_order: list[str]) -> list[str]:
    seq = list(seq[:18])
    counts = Counter(seq)
    while len(seq) < 18:
        level = len(seq) + 1
        if level in (6, 11, 16) and counts["R"] < 3:
            skill = "R"
        else:
            skill = next((s for s in max_order if counts[s] < 5), "R")
        seq.append(skill)
        counts[skill] += 1
    return seq


class Block:
    __slots__ = ("games", "wins", "tl", "runes", "shards", "spells", "skills", "seqs", "starters", "core", "arche", "boots", "completed")

    def __init__(self) -> None:
        self.games = self.wins = self.tl = 0
        self.runes: dict = {}
        self.shards: Counter = Counter()
        self.spells: dict = {}
        self.skills: dict = {}
        self.seqs: Counter = Counter()
        self.starters: dict = {}
        self.core: dict = {}
        self.arche: dict = defaultdict(dict)
        self.boots: dict = {}
        self.completed: dict = {}

    def add(self, p: dict, tlp: dict | None, legendaries: list[int], role: str, items: dict, full: bool) -> None:
        win = int(p["win"])
        self.games += 1
        self.wins += win
        if p["primary"] and p["secondary"] and len(p["perks"]) == 6 and all(p["perks"]):
            _inc(self.runes, (p["primary"], p["secondary"], tuple(p["perks"])), win)
            if all(p["shards"]):
                self.shards[tuple(p["shards"])] += 1
        _inc(self.spells, tuple(p["spells"]), win)
        for iid in p["items"][:6]:
            if is_upgraded_boots(iid, items):
                _inc(self.boots, iid, win)
                break
        if tlp:
            self.tl += 1
            if tlp.get("maxOrder"):
                mo = tuple(tlp["maxOrder"])
                _inc(self.skills, mo, win)
                if tlp.get("skills"):
                    self.seqs[(mo, tuple(tlp["skills"][:15]))] += 1
            if tlp.get("starters"):
                _inc(self.starters, tuple(sorted(set(tlp["starters"]))), win)
            ordered = [int(i) for i, _m in tlp.get("legendaries") or []]
        else:
            ordered = legendaries
        core = tuple(ordered[:3])
        if len(core) == 3:
            _inc(self.core, core, win)
        if full:
            if len(core) >= 2:
                _inc(self.arche[archetype(list(core), items, role)], core, win)
            for iid in set(legendaries):
                _inc(self.completed, iid, win)

    def output(self, s: Settings, *, full: bool, vs: bool = False) -> dict[str, Any]:
        out: dict[str, Any] = {"games": self.games, "winrate": rnd(smoothed(self.wins, self.games, 0.5, 20))}
        if r := _best(self.runes, self.games, s.rune_min_pickrate):
            (primary, sub, perks), g, w = r
            shards = list(self.shards.most_common(1)[0][0]) if self.shards else [5008, 5008, 5011]
            out["runes"] = {"primaryStyleId": primary, "subStyleId": sub, "perkIds": list(perks) + shards, "games": g, "winrate": rnd(w / g)}
        if self.spells:
            pairs: dict[frozenset, list] = defaultdict(lambda: [0, 0])
            for k, (g, w) in self.spells.items():
                pairs[frozenset(k)][0] += g
                pairs[frozenset(k)][1] += w
            top, (g, w) = max(pairs.items(), key=lambda kv: kv[1][0])
            ordered = max((k for k in self.spells if frozenset(k) == top), key=lambda k: self.spells[k][0])
            out["summonerSpells"] = {"ids": list(ordered), "games": g, "winrate": rnd(w / g)}
        if r := _best(self.starters, self.tl, 0.10):
            out["startingItems"] = {"itemIds": list(r[0]), "games": r[1], "winrate": rnd(r[2] / r[1])}
        if self.boots:
            out["boots"] = [{"itemId": k, "pickrate": rnd(g / self.games, 3), "winrate": rnd(w / g)}
                            for k, (g, w) in sorted(self.boots.items(), key=lambda kv: -kv[1][0])[:3]]
        if (not vs or self.tl >= s.vs_skill_min_timelines) and (r := _best(self.skills, self.tl, 0.10)):
            mo, g, w = r
            seqs = [(seq, c) for (m, seq), c in self.seqs.items() if m == mo]
            seq = max(seqs, key=lambda x: x[1])[0] if seqs else []
            out["skillOrder"] = {"maxOrder": list(mo), "sequence": complete_sequence(list(seq), list(mo)), "games": g, "winrate": rnd(w / g)}
        if (not vs or self.games >= s.vs_core_min_games) and (r := _best(self.core, sum(g for g, _ in self.core.values()), 0.10)):
            out["coreBuild"] = {"itemIds": list(r[0]), "games": r[1], "winrate": rnd(r[2] / r[1])}
        if full:
            total = sum(g for d in self.arche.values() for g, _ in d.values()) or 1
            arche = []
            for name, combos in self.arche.items():
                g = sum(c[0] for c in combos.values())
                if g / total < s.archetype_min_pickrate:
                    continue
                w = sum(c[1] for c in combos.values())
                best = max(combos.items(), key=lambda kv: kv[1][0])[0]
                arche.append({"name": name, "itemIds": list(best), "games": g, "winrate": rnd(w / g)})
            out["archetypes"] = sorted(arche, key=lambda a: -a["games"])[:3] or None
            rates = [{"itemId": k, "pickrate": rnd(g / self.games, 3), "winrate": rnd(smoothed(w, g, 0.5, 20))}
                     for k, (g, w) in self.completed.items()]
            out["completedItems"] = sorted(rates, key=lambda r: -r["pickrate"])[:8]
            core = set(out.get("coreBuild", {}).get("itemIds", []))
            sit = [r for r in rates if 0.02 <= r["pickrate"] <= 0.35 and r["itemId"] not in core]
            out["situational"] = sorted(sit, key=lambda r: -r["winrate"])[:6]
        return {k: v for k, v in out.items() if v is not None}


class BuildAccumulator:
    def __init__(self, items: dict[int, dict]):
        self.items = items
        self.blocks: dict[tuple[int, str], Block] = defaultdict(Block)
        self.vs: dict[tuple[int, str, int], Block] = defaultdict(Block)
        self.champ_games: Counter = Counter()
        # item_stats
        self.participants = 0
        self.item: dict[int, list] = {}
        self.minutes: dict[int, list[float]] = defaultdict(lambda: [0.0, 0])
        self.ctx_tot: dict = {}
        self.ctx_item: dict = {}

    def add(self, match: dict[str, Any]) -> None:
        items = self.items
        tl = match.get("tl")
        lanes: dict[tuple[str, int], int] = {}
        for p in match["p"]:
            if p["role"]:
                lanes[(p["role"], p["team"])] = p["champ"]
        ctx = {}
        for team in (100, 200):
            enemies = [e for e in match["p"] if e["team"] != team]
            flags = enemy_context(enemies, items)
            ctx[team] = sum(1 << i for i, name in enumerate(CONTEXTS) if flags[name])
        for p in match["p"]:
            legendaries = [i for i in p["items"][:6] if is_legendary(i, items)]
            win = int(p["win"])
            self.participants += 1
            mask = ctx[p["team"]]
            _inc(self.ctx_tot, (p["champ"], mask), win)
            for iid in set(legendaries):
                _inc(self.item, iid, win)
                _inc(self.ctx_item, (iid, p["champ"], mask), win)
            tlp = (tl or {}).get("p", {}).get(str(p["pid"])) if tl else None
            if tlp:
                for iid, minute in tlp.get("legendaries") or []:
                    m = self.minutes[int(iid)]
                    m[0] += minute
                    m[1] += 1
            role = p["role"]
            if not role:
                continue
            self.champ_games[p["champ"]] += 1
            self.blocks[(p["champ"], role)].add(p, tlp, legendaries, role, items, True)
            enemy = lanes.get((role, 300 - p["team"]))
            if enemy:
                self.vs[(p["champ"], role, enemy)].add(p, tlp, legendaries, role, items, False)

    def finish_builds(self, s: Settings) -> dict[str, dict[str, Any]]:
        vs_by: dict[tuple[int, str], list[tuple[int, Block]]] = defaultdict(list)
        for (cid, role, enemy), block in self.vs.items():
            if block.games >= s.vs_min_games:
                vs_by[(cid, role)].append((enemy, block))
        out: dict[str, dict[str, Any]] = {}
        for (cid, role), block in self.blocks.items():
            if block.games < s.build_min_games or block.games / max(self.champ_games[cid], 1) < s.min_lane_share:
                continue
            vs = sorted(vs_by.get((cid, role), []), key=lambda e: -e[1].games)[:15]
            out.setdefault(str(cid), {})[role] = {
                "default": block.output(s, full=True),
                "vs": {str(e): b.output(s, full=False, vs=True) for e, b in vs},
            }
        return out

    def finish_items(self, s: Settings) -> dict[str, Any]:
        result: dict[str, Any] = {}
        tot_by: dict[int, dict[int, list]] = defaultdict(dict)
        for (c, m), v in self.ctx_tot.items():
            tot_by[c][m] = v
        item_by: dict[int, dict[int, dict[int, list]]] = defaultdict(lambda: defaultdict(dict))
        for (i, c, m), v in self.ctx_item.items():
            item_by[i][c][m] = v

        def split(cells: dict[int, list], bit: int) -> dict[int, list[int]]:
            out = {1: [0, 0], 0: [0, 0]}
            for m, (g, w) in cells.items():
                o = out[m >> bit & 1]
                o[0] += g
                o[1] += w
            return out

        for iid, (games, wins) in self.item.items():
            if games < s.tier_min_games:
                continue
            deltas = {}
            for bit, name in enumerate(CONTEXTS):
                total, weight = 0.0, 0
                n_on = n_off = 0
                for champ, masks in item_by[iid].items():
                    has_s, tot_s = split(masks, bit), split(tot_by[champ], bit)
                    cells = {f: (has_s[f], [tot_s[f][0] - has_s[f][0], tot_s[f][1] - has_s[f][1]]) for f in (1, 0)}
                    (h1, n1), (h0, n0) = cells[1], cells[0]
                    if min(h1[0], n1[0], h0[0], n0[0]) < 5:
                        continue
                    did = (h1[1] / h1[0] - n1[1] / n1[0]) - (h0[1] / h0[0] - n0[1] / n0[0])
                    w_k = h1[0] + h0[0]
                    total += w_k * did
                    weight += w_k
                    n_on += h1[0]
                    n_off += h0[0]
                if weight and n_on >= s.item_context_min and n_off >= s.item_context_min:
                    deltas[name] = rnd(total / weight)
            minutes = self.minutes.get(iid)
            result[str(iid)] = {
                "games": games, "pickrate": rnd(games / max(self.participants, 1)), "winrate": rnd(wins / games),
                "avgCompletionMinute": rnd(minutes[0] / minutes[1], 1) if minutes and minutes[1] else None,
                "contextDeltas": deltas or None,
            }
        return result
