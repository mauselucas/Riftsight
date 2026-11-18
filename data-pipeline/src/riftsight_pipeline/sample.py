#!/usr/bin/env python3
"""Generates *sample* pipeline files in the exact Riftsight schema.

Every file carries ``meta.sample = true`` and the app labels it "Beispieldaten".
Numbers are plausible but synthetic (deterministic RNG); champion/item/rune/augment
IDs are real and validated against the current CommunityDragon / Data Dragon patch,
so every icon and every rune page in the app resolves. Player names are fictional.

Usage:  python3 sample.py [--out ../macOS-App/Resources/SampleData] [--seed 7]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import random
import urllib.request
from pathlib import Path

DDRAGON = "https://ddragon.leagueoflegends.com"
CDRAGON = "https://raw.communitydragon.org/latest"
MERAKI = "https://cdn.merakianalytics.com/riot/lol/resources/latest/en-US/championrates.json"
ROLES = ["TOP", "JUNGLE", "MIDDLE", "BOTTOM", "UTILITY"]


def fetch(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "riftsight-sample-generator"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


# --------------------------------------------------------------------------------------
# Static knowledge used to make the synthetic numbers look like League
# --------------------------------------------------------------------------------------

ITEM_POOLS = {
    "marksman": [3031, 6672, 3032, 3087, 3036, 3033, 3072, 3046, 3094, 3085, 3153, 3124, 6676, 3508, 6675, 3078, 3026],
    "mage": [6655, 4645, 3089, 3135, 3157, 3102, 6653, 3116, 3100, 4646, 4628, 3165, 2503, 3003, 3118, 3137, 4633, 3040],
    "assassin": [3142, 3814, 6694, 6701, 6697, 6698, 6696, 6699, 6695, 3156, 6692, 3071, 3036, 6333, 3026, 6609],
    "fighter": [3078, 3071, 6610, 3053, 6333, 3181, 3161, 6692, 3074, 3748, 3156, 3065, 2501, 6631, 3073, 6609],
    "tank": [3068, 3084, 3075, 3110, 3143, 4401, 2504, 3065, 6665, 2502, 8020, 6664, 6662, 3083, 3742, 3109, 3190],
    "enchanter": [6617, 3107, 3222, 6616, 3504, 2065, 4005, 6621, 3190, 3109, 3011, 3916],
    "apfighter": [4633, 3152, 3115, 6653, 3157, 3116, 3089, 3137, 4645, 3102, 2503],
}
BOOTS = {
    "marksman": [3006, 3009, 3047], "mage": [3020, 3158, 3111], "assassin": [3158, 3047, 3111, 3009],
    "fighter": [3047, 3111, 3158], "tank": [3047, 3111, 3009], "enchanter": [3158, 3009, 3111],
    "apfighter": [3020, 3111, 3047],
}
STARTERS = {
    "marksman": [1055, 2003], "mage": [1056, 2003], "assassin": [1055, 2003], "fighter": [1054, 2003],
    "tank": [1054, 2003], "enchanter": [3865, 2003], "apfighter": [1056, 2003],
    "jungle": [1101, 2003], "support_tank": [3865, 2003],
}
ARCHETYPES = {
    "marksman": ["Krit", "On-Hit & Angriffstempo", "Letalität"],
    "mage": ["Burst", "Kampfmagier", "Dauerschaden"],
    "assassin": ["Letalität", "Bruiser", "Burst"],
    "fighter": ["Bruiser", "Tank-Bruiser", "Split-Push"],
    "tank": ["Tank", "Engage", "Anti-AD"],
    "enchanter": ["Heilung & Schilde", "Utility", "Poke"],
    "apfighter": ["Kampfmagier", "Burst", "Tank-Hybrid"],
}
SITUATIONAL = {
    "marksman": [3033, 3026, 3139, 6609, 3156, 3036],
    "mage": [3165, 3157, 3102, 3135, 3916, 3137],
    "assassin": [3814, 6609, 3026, 3156, 6333, 3033],
    "fighter": [3033, 6333, 3053, 3065, 3075, 3143],
    "tank": [3075, 3076, 3143, 4401, 2504, 3110],
    "enchanter": [3222, 3107, 3190, 3109, 4005, 3916],
    "apfighter": [3165, 3157, 3102, 3916, 4401, 3065],
}

# (primary style, keystone, preferred primary perks, secondary style, preferred secondary perks, shards)
RUNE_TEMPLATES = {
    "marksman": [(8000, 8008, [9111, 9104, 8014], 8300, [8304, 8345], [5005, 5008, 5011]),
                 (8000, 8005, [9111, 9104, 8299], 8100, [8139, 8135], [5005, 5008, 5011])],
    "mage": [(8200, 8229, [8226, 8210, 8237], 8300, [8304, 8345], [5008, 5008, 5011]),
             (8100, 8112, [8139, 8140, 8106], 8200, [8226, 8210], [5008, 5008, 5001])],
    "assassin": [(8100, 8112, [8143, 8140, 8135], 8000, [9111, 8014], [5008, 5008, 5001]),
                 (8100, 9923, [8143, 8140, 8135], 8200, [8234, 8236], [5005, 5008, 5001])],
    "fighter": [(8000, 8010, [9111, 9104, 8299], 8400, [8444, 8453], [5005, 5008, 5001]),
                (8400, 8437, [8446, 8429, 8451], 8000, [9111, 9104], [5008, 5008, 5001])],
    "tank": [(8400, 8437, [8446, 8429, 8451], 8000, [9111, 9105], [5008, 5010, 5001]),
             (8400, 8439, [8401, 8473, 8242], 8300, [8304, 8347], [5008, 5010, 5001])],
    "enchanter": [(8200, 8214, [8226, 8210, 8236], 8400, [8463, 8453], [5008, 5008, 5001]),
                  (8400, 8465, [8463, 8473, 8453], 8200, [8226, 8210], [5008, 5008, 5001])],
    "apfighter": [(8000, 8010, [9111, 9104, 8299], 8400, [8444, 8453], [5008, 5008, 5001]),
                  (8200, 8230, [8226, 8234, 8236], 8400, [8444, 8453], [5008, 5008, 5001])],
    "jungle": [(8000, 8010, [9111, 9104, 8014], 8100, [8126, 8135], [5005, 5008, 5001]),
               (8100, 8128, [8143, 8140, 8135], 8000, [9111, 9105], [5008, 5008, 5001])],
}

PLAYER_FIRST = ["Nebel", "Krähe", "Funke", "Sturm", "Echo", "Glut", "Frost", "Wolke", "Klinge", "Schatten", "Nova",
                "Kiesel", "Lichtung", "Polar", "Zephir", "Orbit", "Tinte", "Moos", "Ferro", "Sirius", "Kobalt",
                "Halo", "Rune", "Vektor", "Quarz", "Blitz", "Asche", "Zinn", "Lotus", "Pixel"]
PLAYER_SECOND = ["fänger", "wolf", "läufer", "herz", "jäger", "bote", "falke", "geist", "kern", "spur", "weber",
                 "flug", "wacht", "sang", "riss", "fall", "zahn", "blick", "", "", ""]
PRO_TEAMS = ["Nordlicht", "Basalt Gaming", "Kaltfront", "Tidewater", "Vanta Five", "Morgenrot", "Hydra Esports",
             "Silberpfeil", "Kumo Club", "Polaris"]


def fictional_name(rng: random.Random) -> str:
    name = rng.choice(PLAYER_FIRST) + rng.choice(PLAYER_SECOND)
    if rng.random() < 0.35:
        name += str(rng.randint(1, 99))
    return name


# --------------------------------------------------------------------------------------
# Game data helpers
# --------------------------------------------------------------------------------------

class GameData:
    def __init__(self) -> None:
        self.version = fetch(f"{DDRAGON}/api/versions.json")[0]
        self.patch = ".".join(self.version.split(".")[:2])
        dd = fetch(f"{DDRAGON}/cdn/{self.version}/data/en_US/champion.json")["data"]
        self.champions = {int(c["key"]): c for c in dd.values()}
        styles = fetch(f"{CDRAGON}/plugins/rcp-be-lol-game-data/global/default/v1/perkstyles.json")
        styles = styles["styles"] if isinstance(styles, dict) else styles
        self.styles = {s["id"]: s for s in styles}
        items = fetch(f"{CDRAGON}/plugins/rcp-be-lol-game-data/global/default/v1/items.json")
        self.items = {i["id"]: i for i in items}
        try:
            rates = fetch(MERAKI)["data"]
        except Exception:  # Meraki is optional
            rates = {}
        self.role_share: dict[int, dict[str, float]] = {}
        for cid in self.champions:
            raw = {r: float(rates.get(str(cid), {}).get(r, {}).get("playRate", 0) or 0) for r in ROLES}
            total = sum(raw.values())
            if total <= 0:
                raw = self.guess_roles(cid)
                total = sum(raw.values())
            self.role_share[cid] = {r: v / total for r, v in raw.items() if v > 0}
        try:
            arena = fetch(f"{CDRAGON}/cdragon/arena/en_us.json")
            self.augments = arena["augments"] if isinstance(arena, dict) else arena
        except Exception:
            self.augments = []

    def guess_roles(self, cid: int) -> dict[str, float]:
        tags = self.champions[cid]["tags"]
        if "Marksman" in tags:
            return {"BOTTOM": 1.0}
        if "Support" in tags:
            return {"UTILITY": 1.0}
        if "Mage" in tags:
            return {"MIDDLE": 1.0}
        if "Assassin" in tags:
            return {"MIDDLE": 0.6, "JUNGLE": 0.4}
        return {"TOP": 1.0}

    def main_roles(self, cid: int) -> list[tuple[str, float]]:
        shares = sorted(self.role_share[cid].items(), key=lambda kv: -kv[1])
        picked = [(r, s) for r, s in shares if s >= 0.12][:2]
        return picked or shares[:1]

    def archetype(self, cid: int, role: str) -> str:
        champ = self.champions[cid]
        tags = champ["tags"]
        info = champ["info"]
        ap = info["magic"] > info["attack"]
        if role == "UTILITY":
            return "tank" if "Tank" in tags or info["defense"] >= 6 else ("enchanter" if ap else "marksman")
        if "Marksman" in tags and role in ("BOTTOM", "MIDDLE", "TOP"):
            return "marksman"
        if "Tank" in tags and info["defense"] >= 7:
            return "tank"
        if "Mage" in tags:
            return "apfighter" if "Fighter" in tags else "mage"
        if "Assassin" in tags:
            return "mage" if ap else "assassin"
        if "Fighter" in tags:
            return "apfighter" if ap else "fighter"
        return "fighter"

    def item_ok(self, iid: int) -> bool:
        item = self.items.get(iid)
        return bool(item) and item.get("priceTotal", 0) > 0

    def valid_items(self, ids: list[int]) -> list[int]:
        return [i for i in ids if self.item_ok(i)]

    def rune_page(self, template, rng: random.Random) -> dict:
        primary_id, keystone, prefs, secondary_id, sec_prefs, shards = template
        primary = self.styles[primary_id]
        secondary = self.styles[secondary_id]

        def regular(style):
            return [s["perks"] for s in style["slots"] if s["type"] in ("kMixedRegularSplashable", "kRegular")]

        def stat_rows(style):
            return [s["perks"] for s in style["slots"] if s["type"] == "kStatMod"]

        keystones = next(s["perks"] for s in primary["slots"] if s["type"] == "kKeyStone")
        if keystone not in keystones:
            keystone = keystones[0]
        perks = [keystone]
        for row in regular(primary)[:3]:
            perks.append(next((p for p in prefs if p in row), rng.choice(row)))
        sec_rows = regular(secondary)[:3]
        chosen_rows: list[int] = []
        sec: list[int] = []
        for p in sec_prefs:
            for idx, row in enumerate(sec_rows):
                if p in row and idx not in chosen_rows:
                    sec.append(p)
                    chosen_rows.append(idx)
                    break
        for idx, row in enumerate(sec_rows):
            if len(sec) >= 2:
                break
            if idx not in chosen_rows:
                sec.append(row[0])
                chosen_rows.append(idx)
        perks += sec[:2]
        rows = stat_rows(primary) or stat_rows(secondary)
        for idx, row in enumerate(rows[:3]):
            want = shards[idx] if idx < len(shards) else row[0]
            perks.append(want if want in row else row[0])
        return {"primaryStyleId": primary_id, "subStyleId": secondary_id, "perkIds": perks}


# --------------------------------------------------------------------------------------
# Generators
# --------------------------------------------------------------------------------------

def meta(gd: GameData, matches: int, now: str) -> dict:
    return {"schemaVersion": 1, "patch": gd.patch, "generatedAt": now, "sample": True,
            "platforms": ["EUW1", "KR", "NA1"], "rankFloor": "EMERALD", "matchesAnalyzed": matches}


def skill_order(rng: random.Random, archetype: str) -> dict:
    orders = {
        "marksman": [["Q", "W", "E"], ["Q", "E", "W"], ["W", "Q", "E"]],
        "mage": [["Q", "W", "E"], ["Q", "E", "W"], ["E", "Q", "W"]],
        "assassin": [["Q", "E", "W"], ["Q", "W", "E"]],
        "fighter": [["Q", "E", "W"], ["Q", "W", "E"], ["E", "Q", "W"]],
        "tank": [["Q", "W", "E"], ["W", "Q", "E"], ["E", "W", "Q"]],
        "enchanter": [["E", "W", "Q"], ["Q", "E", "W"], ["W", "Q", "E"]],
        "apfighter": [["Q", "E", "W"], ["E", "Q", "W"]],
    }
    order = rng.choice(orders.get(archetype, orders["fighter"]))
    seq: list[str] = []
    levels = {"Q": 0, "W": 0, "E": 0}
    first = [order[0], order[1], order[2]]
    for lvl in range(1, 19):
        if lvl in (6, 11, 16):
            seq.append("R")
            continue
        if lvl <= 3:
            key = first[lvl - 1]
        else:
            key = next(k for k in order if levels[k] < 5)
        levels[key] += 1
        seq.append(key)
    return {"maxOrder": order, "sequence": seq}


def spells_for(role: str, archetype: str) -> list[int]:
    if role == "JUNGLE":
        return [11, 4]
    if role == "UTILITY":
        return [4, 14] if archetype != "enchanter" else [4, 3]
    if role == "BOTTOM":
        return [4, 7]
    if role == "TOP":
        return [4, 12]
    return [4, 14] if archetype in ("assassin", "mage") else [4, 12]


def build_block(gd: GameData, cid: int, role: str, rng: random.Random, strength: float, games: int) -> dict:
    archetype = gd.archetype(cid, role)
    pool = gd.valid_items(ITEM_POOLS[archetype])
    rng.shuffle(pool)
    core = pool[:3]
    boots = gd.valid_items(BOOTS[archetype])
    starters_key = "jungle" if role == "JUNGLE" else archetype
    starters = gd.valid_items(STARTERS.get(starters_key, STARTERS["fighter"]))
    templates = RUNE_TEMPLATES["jungle"] if role == "JUNGLE" and archetype not in ("tank", "mage") else RUNE_TEMPLATES[archetype]
    winrate = round(0.5 + strength + rng.gauss(0, 0.006), 4)
    page = gd.rune_page(templates[0], rng)
    page.update({"games": int(games * rng.uniform(0.45, 0.7)), "winrate": round(winrate + rng.uniform(-0.004, 0.006), 4)})
    archetypes = []
    remaining = games
    for name in ARCHETYPES[archetype]:
        share = rng.uniform(0.15, 0.6) if not archetypes else rng.uniform(0.05, 0.3)
        g = int(remaining * share)
        remaining -= g
        archetypes.append({"name": name, "itemIds": (pool[len(archetypes):] + pool)[:3], "games": max(g, 500),
                           "winrate": round(winrate + rng.uniform(-0.025, 0.02), 4)})
    archetypes.sort(key=lambda a: -a["games"])

    def rates(ids: list[int], top: float) -> list[dict]:
        out, pr = [], top
        for iid in ids:
            out.append({"itemId": iid, "pickrate": round(pr, 3), "winrate": round(winrate + rng.uniform(-0.03, 0.03), 4)})
            pr *= rng.uniform(0.55, 0.85)
        return out

    situational = gd.valid_items(SITUATIONAL[archetype])
    rng.shuffle(situational)
    return {
        "games": games,
        "winrate": winrate,
        "runes": page,
        "summonerSpells": {"ids": spells_for(role, archetype), "games": int(games * 0.8), "winrate": winrate},
        "skillOrder": skill_order(rng, archetype) | {"games": int(games * 0.6), "winrate": round(winrate + 0.003, 4)},
        "startingItems": {"itemIds": starters, "games": int(games * 0.7), "winrate": winrate},
        "coreBuild": {"itemIds": core, "games": int(games * 0.25), "winrate": round(winrate + 0.02, 4)},
        "archetypes": archetypes,
        "boots": rates(boots, rng.uniform(0.5, 0.8)),
        "completedItems": rates(pool[:6], rng.uniform(0.6, 0.8)),
        "situational": rates(situational[:5], rng.uniform(0.3, 0.45)),
    }


def matchup_override(gd: GameData, cid: int, enemy: int, role: str, base: dict, rng: random.Random, delta: float) -> dict:
    """Matchup-specific runes: e.g. Second Wind / Bone Plating against ranged or burst lanes."""
    archetype = gd.archetype(cid, role)
    enemy_champ = gd.champions[enemy]
    page = json.loads(json.dumps(base["runes"]))
    ranged = enemy_champ["stats"]["attackrange"] >= 325
    if archetype in ("fighter", "tank", "assassin", "apfighter") and role != "JUNGLE":
        template = list(RUNE_TEMPLATES[archetype][0])
        template[3] = 8400
        template[4] = [8444, 8453] if ranged else [8473, 8453]
        page = gd.rune_page(tuple(template), rng)
    elif archetype in ("mage", "marksman") and enemy_champ["info"]["attack"] > enemy_champ["info"]["magic"] and rng.random() < 0.5:
        alt = RUNE_TEMPLATES[archetype][1]
        page = gd.rune_page(alt, rng)
    games = int(rng.uniform(900, 9000))
    page.update({"games": int(games * 0.6), "winrate": round(0.5 + delta + rng.uniform(-0.01, 0.01), 4)})
    return {"games": games, "winrate": round(0.5 + delta, 4), "runes": page}


def generate(out: Path, seed: int) -> None:
    rng = random.Random(seed)
    gd = GameData()
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    now_iso = now.isoformat().replace("+00:00", "Z")
    print(f"Patch {gd.patch} · {len(gd.champions)} Champions · {len(gd.items)} Items · {len(gd.augments)} Augments")

    # Champion strength & popularity (stable per champion)
    strength = {cid: rng.gauss(0, 0.012) for cid in gd.champions}
    popularity = {cid: rng.lognormvariate(0, 0.7) for cid in gd.champions}
    entries = [(cid, role, share) for cid in gd.champions for role, share in gd.main_roles(cid)]
    by_role: dict[str, list[int]] = {r: [] for r in ROLES}
    for cid, role, _ in entries:
        by_role[role].append(cid)

    # ---------------- matchup_runes.json + counterpicks.json
    builds: dict[str, dict[str, dict]] = {}
    counters: dict[str, dict[str, dict]] = {}
    pair_wr: dict[tuple[int, int, str], float] = {}
    for role, cids in by_role.items():
        for i, a in enumerate(cids):
            for b in cids[i + 1:]:
                wr = 0.5 + (strength[a] - strength[b]) * 0.9 + rng.gauss(0, 0.022)
                wr = max(0.38, min(0.62, wr))
                pair_wr[(a, b, role)] = wr
                pair_wr[(b, a, role)] = 1 - wr

    for cid, role, share in entries:
        games = int(4000 + 160000 * popularity[cid] * share)
        block = build_block(gd, cid, role, rng, strength[cid], games)
        opponents = [o for o in by_role[role] if o != cid]
        opp_entries = []
        for o in opponents:
            wr_vs_me = pair_wr[(o, cid, role)]
            g = int(games * rng.uniform(0.01, 0.05) * popularity[o])
            if g < 150:
                continue
            delta = round(wr_vs_me - (0.5 + strength[o] - strength[cid]) * 0 - 0.5, 4)
            opp_entries.append({
                "championId": o, "games": g, "winrate": round(wr_vs_me, 4), "delta": delta,
                "goldDiff15": round(delta * 4200 + rng.gauss(0, 90), 1),
                "csDiff15": round(delta * 55 + rng.gauss(0, 2.5), 1),
                "laneKillRate": round(max(0.05, min(0.75, 0.3 + delta * 3 + rng.gauss(0, 0.05))), 3),
            })
        opp_entries.sort(key=lambda e: -e["delta"])
        counters.setdefault(str(cid), {})[role] = {"games": games, "winrate": block["winrate"], "counters": opp_entries[:40]}
        vs = {}
        frequent = sorted(opp_entries, key=lambda e: -e["games"])[:10]
        for e in frequent:
            vs[str(e["championId"])] = matchup_override(gd, cid, e["championId"], role, block, rng, -e["delta"])
        builds.setdefault(str(cid), {})[role] = {"default": block, "vs": vs}

    total_matches = 1_284_331
    write(out / "matchup_runes.json", {"meta": meta(gd, total_matches, now_iso), "builds": builds})
    write(out / "counterpicks.json", {"meta": meta(gd, total_matches, now_iso), "champions": counters})

    # ---------------- item_stats.json
    item_stats = {}
    for iid, item in gd.items.items():
        if item.get("priceTotal", 0) < 2000 or not item.get("inStore", True):
            continue
        item_stats[str(iid)] = {
            "games": int(rng.uniform(2000, 400000)), "pickrate": round(rng.uniform(0.005, 0.4), 4),
            "winrate": round(0.5 + rng.gauss(0, 0.02), 4), "avgCompletionMinute": round(rng.uniform(9, 28), 1),
            "contextDeltas": {k: round(rng.gauss(0, 0.015), 4) for k in ("vsHeavyHealing", "vsHeavyAP", "vsHeavyAD", "vsTanks", "vsShields")},
        }
    write(out / "item_stats.json", {"meta": meta(gd, total_matches, now_iso), "items": item_stats})

    # ---------------- tierlist.json
    def tier_of(score_rank: float) -> str:
        return "S+" if score_rank < 0.04 else "S" if score_rank < 0.14 else "A" if score_rank < 0.36 else \
            "B" if score_rank < 0.66 else "C" if score_rank < 0.88 else "D"

    def tier_from_score(score: float) -> str:
        # Thresholds from the research brief (§2.4).
        return "S+" if score >= 65 else "S" if score >= 57.5 else "A" if score >= 50 else \
            "B" if score >= 42.5 else "C" if score >= 35 else "D"

    def curve(cid: int) -> dict:
        tags = gd.champions[cid]["tags"]
        base = {"Assassin": (0.7, 0.75, 0.45), "Marksman": (0.4, 0.6, 0.85), "Mage": (0.5, 0.7, 0.7),
                "Tank": (0.5, 0.65, 0.7), "Fighter": (0.65, 0.7, 0.55), "Support": (0.6, 0.6, 0.6)}.get(tags[0], (0.55, 0.6, 0.6))
        return {k: round(min(1, max(0, v + rng.gauss(0, 0.06))), 2) for k, v in zip(("early", "mid", "late"), base)}

    def ranked_entries(rank_shift: float) -> list[dict]:
        rows = []
        for cid, role, share in entries:
            wr = 0.5 + strength[cid] + rank_shift * rng.gauss(0, 0.01)
            pr = min(0.25, 0.012 * popularity[cid] * share * 4)
            score = (wr - 0.5) * 900 + math.log1p(pr * 100) * 6 + rng.gauss(0, 1.5)
            rows.append({"championId": cid, "role": role, "laneShare": round(share, 3), "score": round(score, 2),
                         "winrate": round(wr, 4), "winrateDelta": round(rng.gauss(0, 0.007), 4),
                         "pickrate": round(pr, 4), "banrate": round(min(0.5, pr * rng.uniform(0.2, 2.5)), 4),
                         "games": int(250_000 * pr + 3000), "powerCurve": curve(cid)})
        return finish(rows)

    def finish(rows: list[dict]) -> list[dict]:
        # Composite z-score → 0–100 score like the real pipeline.
        raw = [r["score"] for r in rows]
        mean = sum(raw) / len(raw)
        std = max((sum((x - mean) ** 2 for x in raw) / len(raw)) ** 0.5, 1e-6)
        for r in rows:
            r["score"] = round(max(0.0, min(100.0, 50 + 10 * (r["score"] - mean) / std)), 1)
            r["tier"] = tier_from_score(r["score"])
        rows.sort(key=lambda r: -r["score"])
        for i, r in enumerate(rows):
            r["rank"] = i + 1
        return rows

    def aram_entries() -> list[dict]:
        rows = []
        for cid in gd.champions:
            wr = 0.5 + rng.gauss(0, 0.025)
            pr = rng.uniform(0.01, 0.06)
            rows.append({"championId": cid, "role": "ALL", "laneShare": 1.0, "score": round((wr - 0.5) * 900 + rng.gauss(0, 2), 2),
                         "winrate": round(wr, 4), "winrateDelta": round(rng.gauss(0, 0.008), 4), "pickrate": round(pr, 4),
                         "games": int(rng.uniform(20000, 180000)), "powerCurve": curve(cid)})
        return finish(rows)

    def arena_entries() -> list[dict]:
        rows = []
        for cid in gd.champions:
            placement = rng.uniform(3.6, 5.3)
            rows.append({"championId": cid, "role": "ALL", "laneShare": 1.0, "score": round((4.5 - placement) * 40, 2),
                         "winrate": round(max(0.05, 0.125 + (4.5 - placement) * 0.05), 4), "pickrate": round(rng.uniform(0.004, 0.03), 4),
                         "games": int(rng.uniform(5000, 60000)), "avgPlacement": round(placement, 2),
                         "top4Rate": round(min(0.8, 0.5 + (4.5 - placement) * 0.18), 3)})
        return finish(rows)

    def duo_entries() -> list[dict]:
        rows = []
        bots, sups = by_role["BOTTOM"], by_role["UTILITY"]
        for _ in range(80):
            a, b = rng.choice(bots), rng.choice(sups)
            wr = 0.5 + (strength[a] + strength[b]) * 0.8 + rng.gauss(0, 0.012)
            rows.append({"championId": a, "role": "BOTTOM", "partnerChampionId": b, "partnerRole": "UTILITY",
                         "score": round((wr - 0.5) * 900 + rng.gauss(0, 1), 2), "winrate": round(wr, 4),
                         "pickrate": round(rng.uniform(0.004, 0.03), 4), "games": int(rng.uniform(3000, 40000))})
        uniq = {(r["championId"], r["partnerChampionId"]): r for r in rows}
        return finish(list(uniq.values()))

    brackets = []
    for rank, shift in (("EMERALD_PLUS", 0.6), ("DIAMOND_PLUS", 1.0), ("MASTER_PLUS", 1.4)):
        for platform in ("ALL", "EUW1", "KR", "NA1"):
            brackets.append({"rank": rank, "platform": platform,
                             "modes": {"ranked": ranked_entries(shift), "aram": aram_entries(),
                                       "arena": arena_entries(), "duo": duo_entries()}})
    write(out / "tierlist.json", {"meta": meta(gd, total_matches, now_iso), "brackets": brackets})

    # ---------------- aram_augments.json
    rarity = {0: "silver", 1: "gold", 2: "prismatic"}
    augment_ids = [a for a in gd.augments if a.get("id") is not None]

    def augment_stat(a) -> dict:
        wr = 0.5 + rng.gauss(0, 0.03)
        return {"id": a["id"], "rarity": rarity.get(a.get("rarity"), "silver"), "tier": tier_of(rng.random()),
                "winrate": round(wr, 4), "pickrate": round(rng.uniform(0.01, 0.25), 4), "games": int(rng.uniform(3000, 90000))}

    def arena_stat(a) -> dict:
        stat = augment_stat(a)
        placement = round(rng.uniform(3.3, 5.4), 2)
        stat.update({"avgPlacement": placement, "top4Rate": round(min(0.85, 0.5 + (4.5 - placement) * 0.18), 3)})
        stat["winrate"] = stat["top4Rate"]
        return stat

    modes = {}
    for mode in ("ARAM_MAYHEM", "CHERRY"):
        make = arena_stat if mode == "CHERRY" else augment_stat
        stats = [make(a) for a in augment_ids]
        champion_augments = {}
        champ_builds = {}
        for cid in gd.champions:
            picks = rng.sample(augment_ids, min(6, len(augment_ids)))
            champion_augments[str(cid)] = sorted([make(a) for a in picks], key=lambda s: -s["winrate"])
            role = gd.main_roles(cid)[0][0]
            block = build_block(gd, cid, role, rng, strength[cid], int(rng.uniform(4000, 40000)))
            champ_builds[str(cid)] = {k: block[k] for k in ("games", "winrate", "coreBuild", "boots", "completedItems")}
        modes[mode] = {"augments": stats, "championAugments": champion_augments, "builds": champ_builds}
    write(out / "aram_augments.json", {"meta": meta(gd, 412_008, now_iso), "modes": modes})

    # ---------------- pro_spectate.json (fictional players)
    games = []
    tiers = ["CHALLENGER", "CHALLENGER", "CHALLENGER", "GRANDMASTER", "GRANDMASTER", "MASTER"]
    for g in range(10):
        platform = rng.choice(["KR", "KR", "EUW1", "EUW1", "NA1"])
        avg_tier = tiers[min(g // 2, len(tiers) - 1)]
        known_blue = rng.random() < 0.8
        known_red = rng.random() < 0.5
        participants = []
        for team in (100, 200):
            for role in ROLES:
                cid = rng.choice(by_role[role])
                known = known_blue if team == 100 else known_red
                name = fictional_name(rng)
                participants.append({
                    "teamId": team, "championId": cid, "role": role, "puuid": None,
                    "riotId": f"{name}#{rng.choice(['EUW', 'KR1', 'NA1', 'GG', 'PRO'])}",
                    "proName": name if known else None,
                    "proTeam": rng.choice(PRO_TEAMS) if known else None,
                    "tier": avg_tier, "lp": int(rng.uniform(300, 1600)), "isKnown": known,
                })
        start = now - dt.timedelta(minutes=rng.uniform(4, 36))
        games.append({"gameId": 7_100_000_000 + rng.randint(0, 99_999_999), "platformId": platform,
                      "gameStartTime": int(start.timestamp() * 1000), "queueId": 420, "averageTier": avg_tier,
                      "averageLp": int(rng.uniform(500, 1450)) if avg_tier == "CHALLENGER" else int(rng.uniform(150, 700)),
                      "knownPlayers": sum(p["isKnown"] for p in participants), "participants": participants})
    games.sort(key=lambda x: (-x["knownPlayers"], -x["averageLp"]))
    write(out / "pro_spectate.json", {"meta": meta(gd, 0, now_iso), "games": games})

    # ---------------- leaderboard.json (fictional players)
    platforms = {}
    for platform in ("EUW1", "KR", "NA1"):
        lp = 2200 + rng.randint(0, 400)
        rows = []
        for rank in range(1, 101):
            lp -= rng.randint(2, 18)
            wins = rng.randint(180, 520)
            rows.append({"rank": rank, "puuid": None, "riotId": f"{fictional_name(rng)}#{platform[:2]}{rng.randint(1, 9)}",
                         "tier": "CHALLENGER" if rank <= 50 else "GRANDMASTER", "lp": max(lp, 200), "wins": wins,
                         "losses": int(wins * rng.uniform(0.72, 0.95)),
                         "topChampionIds": rng.sample(list(gd.champions), 3)})
        platforms[platform] = rows
    write(out / "leaderboard.json", {"meta": meta(gd, 0, now_iso), "platforms": platforms})


def write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"  {path.name:<22} {path.stat().st_size / 1024:8.0f} KB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default_out = Path(__file__).resolve().parents[3] / "macOS-App" / "Resources" / "SampleData"
    parser.add_argument("--out", type=Path, default=default_out)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    generate(args.out, args.seed)
