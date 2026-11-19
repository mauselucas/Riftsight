"""End-to-end test on synthetic Match-V5 payloads (no network, no API key)."""
from __future__ import annotations

import json
import random
from dataclasses import replace
from pathlib import Path

from riftsight_pipeline.cli import aggregate, publish, validate
from riftsight_pipeline.config import Settings
from riftsight_pipeline.features import compact_match, timeline_features
from riftsight_pipeline.static_data import StaticData
from riftsight_pipeline.stats import assign_tier, smoothed, wilson_lower
from riftsight_pipeline.store import Store

ROLES = ["TOP", "JUNGLE", "MIDDLE", "BOTTOM", "UTILITY"]
CHAMPS = {r: [i * 10 + k for k in range(1, 5)] for i, r in enumerate(ROLES, start=1)}
ITEMS = {
    3031: {"inStore": True, "to": [], "priceTotal": 3400, "categories": ["CriticalStrike", "Damage"]},
    3072: {"inStore": True, "to": [], "priceTotal": 3400, "categories": ["CriticalStrike", "Damage", "LifeSteal"]},
    3089: {"inStore": True, "to": [], "priceTotal": 3600, "categories": ["SpellDamage"]},
    3068: {"inStore": True, "to": [], "priceTotal": 2900, "categories": ["Health", "Armor"]},
    3006: {"inStore": True, "to": [], "priceTotal": 1100, "categories": ["Boots", "AttackSpeed"]},
    1055: {"inStore": True, "to": [], "priceTotal": 450, "categories": ["Damage"]},
}
STATIC = StaticData(version="16.23.1", patch="16.23", champions={}, items=ITEMS, augment_rarity={1205: "silver"})


def participant(pid: int, team: int, role: str, champ: int, win: bool, mode: str) -> dict:
    return {
        "participantId": pid, "puuid": f"p{champ}-{pid}", "teamId": team, "championId": champ, "teamPosition": role,
        "win": win, "placement": (1 if win else 6) if mode == "CHERRY" else 0, "summoner1Id": 4, "summoner2Id": 14,
        "perks": {"statPerks": {"offense": 5005, "flex": 5008, "defense": 5011},
                  "styles": [{"style": 8000, "selections": [{"perk": x} for x in (8008, 9111, 9104, 8014)]},
                             {"style": 8300, "selections": [{"perk": x} for x in (8304, 8345)]}]},
        **{f"item{i}": v for i, v in enumerate([3031, 3072, 3089, 3006, 0, 0, 3340])},
        "playerAugment1": 1205 if mode != "CLASSIC" else 0,
        "totalHeal": 9000, "magicDamageDealtToChampions": 9000, "physicalDamageDealtToChampions": 12000,
        "totalDamageDealtToChampions": 22000, "damageSelfMitigated": 30000 if role == "TOP" else 9000, "kills": 3,
    }


def make_match(i: int, rng: random.Random, queue: int = 420) -> dict:
    mode = {420: "CLASSIC", 450: "ARAM", 1700: "CHERRY"}[queue]
    blue_win = rng.random() < 0.5
    ps = []
    for team in (100, 200):
        for k, role in enumerate(ROLES):
            champ = rng.choice(CHAMPS[role])
            ps.append(participant(len(ps) + 1, team, role, champ, blue_win == (team == 100), mode))
    return {"metadata": {"matchId": f"EUW1_{i}"},
            "info": {"queueId": queue, "gameMode": mode, "gameDuration": rng.randint(1200, 2200), "gameVersion": "16.23.1.1",
                     "gameCreation": 1_700_000_000_000 + i, "teams": [{"bans": [{"championId": 11}]}], "participants": ps}}


def make_timeline() -> dict:
    events = [{"type": "ITEM_PURCHASED", "participantId": p, "itemId": 1055, "timestamp": 20_000} for p in range(1, 11)]
    events += [{"type": "SKILL_LEVEL_UP", "levelUpType": "NORMAL", "participantId": p, "skillSlot": s}
               for p in range(1, 11) for s in [1, 2, 3, 1, 1, 4, 1, 1, 3, 3, 4, 3, 3, 2, 2, 4, 2, 2]]
    events += [{"type": "ITEM_PURCHASED", "participantId": p, "itemId": it, "timestamp": 600_000 + n * 300_000}
               for p in range(1, 11) for n, it in enumerate((3031, 3072, 3089))]
    frames = [{"events": events if f == 1 else [], "participantFrames": {str(p): {"totalGold": 5000 + p * 10, "minionsKilled": 100,
               "jungleMinionsKilled": 0} for p in range(1, 11)}} for f in range(20)]
    return {"info": {"frames": frames}}


def test_stats_helpers() -> None:
    assert assign_tier(70) == "S+" and assign_tier(30) == "D"
    assert abs(smoothed(0, 0, 0.5, 50) - 0.5) < 1e-9
    assert 0 < wilson_lower(60, 100) < 0.6


def test_timeline_features() -> None:
    f = timeline_features(make_timeline(), ITEMS)
    p1 = f["p"]["1"]
    assert p1["maxOrder"] == ["Q", "E", "W"]
    assert p1["starters"] == [1055]
    assert [x[0] for x in p1["legendaries"]] == [3031, 3072, 3089]


def test_end_to_end(tmp_path: Path) -> None:
    rng = random.Random(3)
    s = replace(Settings().sampled(), platforms=("EUW1",), state_dir=tmp_path / "state", out_dir=tmp_path / "out",
                dist_dir=tmp_path / "dist")
    store = Store(":memory:")
    tl = timeline_features(make_timeline(), ITEMS)
    for i in range(400):
        queue = 420 if i < 300 else (450 if i < 350 else 1700)
        record = compact_match(make_match(i, rng, queue), "EUW1", "EMERALD")
        assert record is not None
        store.put_match(record)
        if queue == 420 and i % 2 == 0:
            store.put_timeline(record["id"], tl)
    files = aggregate(store, STATIC, s)
    assert validate(files, s) == []
    publish(files, s)
    tier = json.loads((s.out_dir / "tierlist.json").read_text())
    modes = tier["brackets"][0]["modes"]
    assert modes["ranked"] and modes["aram"] and modes["arena"] and modes["duo"]
    assert modes["ranked"][0]["rank"] == 1 and "pickrate" in modes["ranked"][0]
    runes = json.loads((s.out_dir / "matchup_runes.json").read_text())
    block = runes["builds"]["41"]["BOTTOM"]["default"]
    assert len(block["runes"]["perkIds"]) == 9
    assert block["skillOrder"]["maxOrder"] == ["Q", "E", "W"] and len(block["skillOrder"]["sequence"]) == 18
    assert block["archetypes"][0]["name"] == "Krit"
    counters = json.loads((s.out_dir / "counterpicks.json").read_text())
    entry = counters["champions"]["41"]["BOTTOM"]["counters"][0]
    assert {"championId", "games", "winrate", "delta"} <= set(entry)
    aug = json.loads((s.out_dir / "aram_augments.json").read_text())
    assert aug["modes"]["CHERRY"]["augments"][0]["id"] == 1205
    assert (s.dist_dir / "manifest.json").exists()


def test_sample_data_contract() -> None:
    sample_dir = Path(__file__).resolve().parents[2] / "macOS-App" / "Resources" / "SampleData"
    files = {p.stem: json.loads(p.read_text()) for p in sample_dir.glob("*.json")}
    assert validate(files, Settings().sampled()) == []


def test_focus_seeds_and_settings(monkeypatch) -> None:
    from riftsight_pipeline.config import load_settings
    store = Store(":memory:")
    store.add_seed("a", "EUW1", "EMERALD")
    store.add_seed("b", "EUW1", "DIAMOND", priority=1)
    store.add_seed("a", "EUW1", "EMERALD", priority=1)
    assert sorted(p for p, _ in store.next_focus_seeds("EUW1", 10)) == ["a", "b"]
    store.mark_crawled("b")
    assert [p for p, _ in store.next_focus_seeds("EUW1", 10)] == ["a"]
    monkeypatch.setenv("SAMPLE_MODE", "1")
    monkeypatch.setenv("RIFTSIGHT_FOCUS_CHAMPIONS", "901, 29")
    monkeypatch.setenv("MATCHES_PER_PLATFORM", "2000")
    s = load_settings()
    assert s.focus_champions == (901, 29) and s.matches_per_platform == 2000
