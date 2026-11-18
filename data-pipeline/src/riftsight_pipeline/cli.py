"""Entry point: ``riftsight collect | aggregate | run``.

aggregate: one pass over the stored matches → 7 JSONs in ``out/`` → schema gate → ``dist/`` (gzip + manifest).
"""
from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import gzip
import hashlib
import json
import logging
import math
from collections import Counter
from pathlib import Path
from typing import Any

from . import SCHEMA_VERSION
from .augments import AugmentAccumulator
from .builds import BuildAccumulator
from .config import Settings, load_settings
from .counters import CounterAccumulator
from .static_data import StaticData, load_static
from .store import Store
from .tierlist import TierlistAccumulator

log = logging.getLogger("riftsight")
FILES = ("counterpicks", "matchup_runes", "item_stats", "tierlist", "aram_augments", "pro_spectate", "leaderboard")


def _meta(patch: str, s: Settings, matches: int) -> dict[str, Any]:
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {"schemaVersion": SCHEMA_VERSION, "patch": patch, "generatedAt": now, "sample": s.sample_mode,
            "platforms": list(s.platforms), "rankFloor": "EMERALD", "matchesAnalyzed": matches}


def _strip(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: _strip(v) for k, v in obj.items() if v is not None}
    if isinstance(obj, list):
        return [_strip(v) for v in obj]
    return obj


def target_patch(store: Store, static: StaticData) -> str:
    if store.count(static.patch, "ranked") >= 1000 or not store.patches():
        return static.patch
    return store.patches()[-1]


def leaderboard(store: Store, s: Settings, patch: str) -> dict[str, list]:
    tops: dict[str, Counter] = {}
    for m in store.matches(patch, "ranked", with_timelines=False):
        for p in m["p"]:
            if p["puuid"]:
                tops.setdefault(p["puuid"], Counter())[p["champ"]] += 1
    out = {}
    for platform in s.platforms:
        rows = []
        for e in json.loads(store.get(f"apex:{platform}") or "[]")[: s.leaderboard_size]:
            riot_id = store.riot_id(e["puuid"], max_age_s=30 * 86400)
            if not riot_id:
                continue
            rows.append({"rank": len(rows) + 1, "puuid": e["puuid"], "riotId": riot_id, "tier": e["tier"], "lp": e["lp"],
                         "wins": e["wins"], "losses": e["losses"],
                         "topChampionIds": [c for c, _ in tops.get(e["puuid"], Counter()).most_common(3)]})
        out[platform] = rows
    return out


def aggregate(store: Store, static: StaticData, s: Settings) -> dict[str, dict]:
    patch = target_patch(store, static)
    prev_file = s.state_dir / f"summary-{_previous(patch)}.json"
    prev = json.loads(prev_file.read_text()) if prev_file.exists() else {"tier": {}, "matchups": {}}
    counters, builds = CounterAccumulator(), BuildAccumulator(static.items)
    tiers, augs = TierlistAccumulator(s.platforms), AugmentAccumulator(static.items, static.augment_rarity)
    ranked = 0
    for m in store.matches(patch):
        if m["mode"] == "ranked":
            ranked += 1
            counters.add(m)
            builds.add(m)
        tiers.add(m)
        augs.add(m)
    log.info("Patch %s: %d Ranked-Matches", patch, ranked)
    champions, matchup_summary = counters.finish(s, prev.get("matchups", {}))
    brackets, tier_summary = tiers.finish(s, prev.get("tier", {}))
    s.state_dir.mkdir(parents=True, exist_ok=True)
    (s.state_dir / f"summary-{patch}.json").write_text(json.dumps({"tier": tier_summary, "matchups": matchup_summary}))
    meta = _meta(patch, s, ranked)
    return {
        "counterpicks": {"meta": meta, "champions": champions},
        "matchup_runes": {"meta": meta, "builds": builds.finish_builds(s)},
        "item_stats": {"meta": meta, "items": builds.finish_items(s)},
        "tierlist": {"meta": meta, "brackets": brackets},
        "aram_augments": {"meta": meta, "modes": augs.finish(s)},
        "pro_spectate": {"meta": {**meta, "matchesAnalyzed": 0}, "games": []},  # live data comes from the Worker
        "leaderboard": {"meta": {**meta, "matchesAnalyzed": 0}, "platforms": leaderboard(store, s, patch)},
    }


def _previous(patch: str) -> str:
    major, minor = (int(x) for x in patch.split("."))
    return f"{major}.{minor - 1}" if minor > 1 else f"{major - 1}.24"


def validate(files: dict[str, dict], s: Settings) -> list[str]:
    """Schema gate: no NaN/inf, rates in [0,1], enough champions. Returns a list of problems."""
    problems: list[str] = []

    def walk(obj: Any, path: str) -> None:
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k in ("winrate", "pickrate", "banrate", "laneShare", "top4Rate", "laneKillRate") and isinstance(v, (int, float)) \
                        and not 0 <= v <= 1:
                    problems.append(f"{path}.{k}={v}")
                walk(v, f"{path}.{k}")
        elif isinstance(obj, list):
            for i, v in enumerate(obj[:5000]):
                walk(v, f"{path}[{i}]")
        elif isinstance(obj, float) and (math.isnan(obj) or math.isinf(obj)):
            problems.append(f"{path}=NaN")

    for name in FILES:
        if name not in files or "meta" not in files[name]:
            problems.append(f"{name}: fehlt")
            continue
        walk(files[name], name)
    if len(files.get("counterpicks", {}).get("champions", {})) < s.min_champions_published:
        problems.append("counterpicks: zu wenige Champions")
    return problems[:50]


def publish(files: dict[str, dict], s: Settings) -> None:
    for d in (s.out_dir, s.dist_dir):
        d.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, payload in files.items():
        data = json.dumps(_strip(payload), ensure_ascii=False, separators=(",", ":")).encode()
        (s.out_dir / f"{name}.json").write_bytes(data)
        (s.dist_dir / f"{name}.json").write_bytes(data)
        (s.dist_dir / f"{name}.json.gz").write_bytes(gzip.compress(data, 9))
        manifest[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    (s.dist_dir / "manifest.json").write_text(json.dumps({"meta": files["tierlist"]["meta"], "files": manifest}, indent=1))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="riftsight")
    parser.add_argument("command", choices=("collect", "aggregate", "run"))
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    s = load_settings()
    static = load_static(s.state_dir / "static")
    store = Store(s.db_path)
    try:
        if args.command in ("collect", "run"):
            from .collect import collect
            log.info("Neue Matches: %s", asyncio.run(collect(store, static, s)))
        if args.command in ("aggregate", "run"):
            files = aggregate(store, static, s)
            if problems := validate(files, s):
                for p in problems:
                    log.error("Schema-Gate: %s", p)
                return 2
            publish(files, s)
            log.info("Veröffentlicht nach %s", s.dist_dir)
    finally:
        store.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
