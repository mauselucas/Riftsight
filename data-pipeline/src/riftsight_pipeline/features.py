"""Turns raw Match-V5 / timeline payloads into compact records (~1 KB per match instead of ~150 KB).

Raw timelines are never stored – only the extracted feature vectors (risk #2 of the research brief).
"""
from __future__ import annotations

from collections import Counter
from typing import Any

from .config import (ARAM_MAYHEM_GAME_MODES, ARENA_GAME_MODES, QUEUE_ARAM, QUEUE_ARAM_MAYHEM, QUEUE_ARENA,
                     QUEUE_RANKED_SOLO, ROLES, TRINKETS)

SLOT_MAP = {1: "Q", 2: "W", 3: "E", 4: "R"}


def patch_of(game_version: str) -> str:
    """'16.23.634.1234' → '16.23'."""
    return ".".join(game_version.split(".")[:2])


def mode_of(info: dict[str, Any]) -> str | None:
    """Maps a match to the aggregation mode it feeds."""
    queue = info.get("queueId")
    game_mode = (info.get("gameMode") or "").upper()
    if queue == QUEUE_RANKED_SOLO:
        return "ranked"
    if queue == QUEUE_ARENA or game_mode in ARENA_GAME_MODES:
        return "arena"
    if queue == QUEUE_ARAM_MAYHEM or game_mode in ARAM_MAYHEM_GAME_MODES:
        return "mayhem"
    if queue == QUEUE_ARAM:
        return "aram"
    return None


def is_valid_match(info: dict[str, Any]) -> bool:
    """Drops remakes and early surrenders."""
    if info.get("gameDuration", 0) < 300:
        return False
    participants = info.get("participants") or []
    if not participants or participants[0].get("gameEndedInEarlySurrender"):
        return False
    return True


def role_of(participant: dict[str, Any]) -> str | None:
    role = participant.get("teamPosition") or ""
    if role in ("", "Invalid"):
        role = participant.get("individualPosition") or ""
    return role if role in ROLES else None


def compact_participant(p: dict[str, Any]) -> dict[str, Any]:
    perks = p.get("perks") or {}
    styles = perks.get("styles") or []
    primary = styles[0] if styles else {}
    secondary = styles[1] if len(styles) > 1 else {}
    stat = perks.get("statPerks") or {}
    augments = [p.get(f"playerAugment{i}", 0) for i in range(1, 7)]
    return {
        "pid": p.get("participantId"),
        "puuid": p.get("puuid"),
        "team": p.get("teamId"),
        "sub": p.get("playerSubteamId"),
        "champ": p.get("championId"),
        "role": role_of(p),
        "win": bool(p.get("win")),
        "placement": p.get("placement") or None,
        "spells": [p.get("summoner1Id", 0), p.get("summoner2Id", 0)],
        "primary": primary.get("style"),
        "secondary": secondary.get("style"),
        "perks": [s.get("perk") for s in (primary.get("selections") or [])[:4]]
        + [s.get("perk") for s in (secondary.get("selections") or [])[:2]],
        "shards": [stat.get("offense"), stat.get("flex"), stat.get("defense")],
        "items": [p.get(f"item{i}", 0) for i in range(7)],
        "augments": [a for a in augments if a],
        "heal": p.get("totalHeal", 0),
        "shield": p.get("totalDamageShieldedOnTeammates", 0),
        "magic": p.get("magicDamageDealtToChampions", 0),
        "physical": p.get("physicalDamageDealtToChampions", 0),
        "damage": p.get("totalDamageDealtToChampions", 0),
        "mitigated": p.get("damageSelfMitigated", 0),
        "kills": p.get("kills", 0),
        "deaths": p.get("deaths", 0),
        "assists": p.get("assists", 0),
    }


def compact_match(match: dict[str, Any], platform: str, bucket: str) -> dict[str, Any] | None:
    info = match.get("info") or {}
    mode = mode_of(info)
    if mode is None or not is_valid_match(info):
        return None
    bans = [b.get("championId") for t in info.get("teams") or [] for b in t.get("bans") or [] if b.get("championId", -1) > 0]
    return {
        "id": (match.get("metadata") or {}).get("matchId"),
        "platform": platform,
        "bucket": bucket,
        "patch": patch_of(info.get("gameVersion", "0.0")),
        "queue": info.get("queueId"),
        "mode": mode,
        "duration": info.get("gameDuration", 0),
        "creation": info.get("gameCreation", 0),
        "bans": bans,
        "p": [compact_participant(p) for p in info.get("participants") or []],
    }


# --------------------------------------------------------------------------------------
# Item knowledge (CommunityDragon items.json, keyed by id)
# --------------------------------------------------------------------------------------

def is_legendary(item_id: int, items: dict[int, dict[str, Any]]) -> bool:
    meta = items.get(item_id)
    if not meta:
        return False
    return (
        meta.get("inStore", True) is True
        and len(meta.get("to") or []) == 0
        and (meta.get("priceTotal") or 0) >= 2000
        and "Boots" not in (meta.get("categories") or [])
        and not meta.get("requiredChampion")
    )


def is_upgraded_boots(item_id: int, items: dict[int, dict[str, Any]]) -> bool:
    meta = items.get(item_id) or {}
    return "Boots" in (meta.get("categories") or []) and (meta.get("priceTotal") or 0) >= 900


def timeline_features(timeline: dict[str, Any], items: dict[int, dict[str, Any]]) -> dict[str, Any]:
    """Per participant: skills, starters, legendaries (with completion minute), boots, frame-15 numbers;
    plus all champion kills before minute 15 (for lane kill rates)."""
    frames = (timeline.get("info") or {}).get("frames") or []
    skills: dict[int, list[str]] = {}
    purchases: dict[int, list[tuple[int, int]]] = {}
    kills15: list[list[int]] = []
    for index, frame in enumerate(frames):
        for ev in frame.get("events") or []:
            etype = ev.get("type")
            pid = ev.get("participantId")
            if etype == "SKILL_LEVEL_UP" and ev.get("levelUpType") == "NORMAL" and ev.get("skillSlot") in SLOT_MAP:
                skills.setdefault(pid, []).append(SLOT_MAP[ev["skillSlot"]])
            elif etype == "ITEM_PURCHASED":
                purchases.setdefault(pid, []).append((ev.get("itemId", 0), ev.get("timestamp", 0)))
            elif etype == "ITEM_UNDO":
                stack = purchases.get(pid, [])
                target = ev.get("beforeId")
                for idx in range(len(stack) - 1, -1, -1):
                    if stack[idx][0] == target:
                        stack.pop(idx)
                        break
            elif etype == "CHAMPION_KILL" and index <= 15:
                kills15.append([ev.get("killerId", 0), ev.get("victimId", 0)])

    frame15 = (frames[15].get("participantFrames") or {}) if len(frames) > 15 else {}
    result: dict[str, Any] = {"kills15": kills15, "p": {}}
    pids = set(skills) | set(purchases) | {int(k) for k in frame15}
    for pid in sorted(p for p in pids if p):
        stack = purchases.get(pid, [])
        starters = sorted(iid for iid, ts in stack if ts <= 65_000 and iid not in TRINKETS)
        legendaries: list[list[float]] = []
        boots = None
        for iid, ts in stack:
            if boots is None and is_upgraded_boots(iid, items):
                boots = iid
            elif is_legendary(iid, items) and all(l[0] != iid for l in legendaries):
                legendaries.append([iid, round(ts / 60_000.0, 1)])
        sequence = skills.get(pid, [])
        counts: Counter[str] = Counter()
        max_order: list[str] = []
        for s in sequence:
            if s in ("Q", "W", "E"):
                counts[s] += 1
                if counts[s] == 5 and s not in max_order:
                    max_order.append(s)
        pf = frame15.get(str(pid)) or {}
        result["p"][str(pid)] = {
            "starters": starters,
            "legendaries": legendaries,
            "boots": boots,
            "skills": sequence[:18] if len(sequence) >= 15 and len(max_order) == 3 else None,
            "maxOrder": max_order if len(max_order) == 3 else None,
            "gold15": pf.get("totalGold") if pf else None,
            "cs15": (pf.get("minionsKilled", 0) + pf.get("jungleMinionsKilled", 0)) if pf else None,
        }
    return result


def lane_metrics(features: dict[str, Any], pid_a: int, pid_b: int) -> tuple[float, float, int] | None:
    """(goldDiff15, csDiff15, killedOpponent) from A's perspective; None without frame 15."""
    pa = features["p"].get(str(pid_a)) or {}
    pb = features["p"].get(str(pid_b)) or {}
    if pa.get("gold15") is None or pb.get("gold15") is None:
        return None
    killed = int(any(k == pid_a and v == pid_b for k, v in features.get("kills15") or []))
    return pa["gold15"] - pb["gold15"], (pa.get("cs15") or 0) - (pb.get("cs15") or 0), killed


def enemy_context(enemies: list[dict[str, Any]], items: dict[int, dict[str, Any]]) -> dict[str, bool]:
    """The six enemy-composition features used for situational item deltas."""
    total_heal = sum(e.get("heal", 0) for e in enemies)
    total_shield = sum(e.get("shield", 0) for e in enemies)
    ap = sum(e.get("magic", 0) for e in enemies)
    ad = sum(e.get("physical", 0) for e in enemies)
    all_damage = max(sum(e.get("damage", 0) for e in enemies), 1)
    tanks = sum(1 for e in enemies if e.get("mitigated", 0) > 26_000)
    fed_crit = any(
        e.get("kills", 0) >= 6
        and sum(1 for i in e.get("items", [])[:6] if "CriticalStrike" in ((items.get(i) or {}).get("categories") or [])) >= 2
        for e in enemies
    )
    return {
        "vsHeavyHealing": total_heal > 32_000,
        "vsShields": total_shield > 7_500,
        "vsHeavyAP": ap / all_damage >= 0.55,
        "vsHeavyAD": ad / all_damage >= 0.65,
        "vsTanks": tanks >= 2,
        "vsFedCrit": fed_crit,
    }
