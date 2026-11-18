"""Crawl: League-V4 seeds (60 % Emerald / 30 % Diamond / 10 % Apex) → Match-V5 ids → matches (+ sampled timelines).
Participants of crawled matches are added as seeds of the same bucket (stratified snowball)."""
from __future__ import annotations

import asyncio
import json
import logging
import time
import zlib

from .config import BUCKET_QUOTAS, QUEUE_ARAM, QUEUE_ARAM_MAYHEM, QUEUE_ARENA, QUEUE_RANKED_SOLO, Settings
from .features import compact_match, timeline_features
from .riot_client import RiotAPIError, RiotClient
from .static_data import StaticData
from .store import Store

log = logging.getLogger("riftsight.collect")
DIVISIONS = ("I", "II", "III", "IV")


async def seed_platform(client: RiotClient, store: Store, platform: str, s: Settings) -> None:
    if time.time() - float(store.get(f"seeded:{platform}") or 0) < 20 * 3600:
        return
    apex = []
    for tier in ("CHALLENGER", "GRANDMASTER", "MASTER"):
        league = await client.league_apex(platform, tier) or {}
        for e in league.get("entries") or []:
            if e.get("puuid"):
                store.add_seed(e["puuid"], platform, "APEX")
                if tier != "MASTER":
                    apex.append({"puuid": e["puuid"], "tier": tier, "lp": e.get("leaguePoints", 0),
                                 "wins": e.get("wins", 0), "losses": e.get("losses", 0)})
    store.set(f"apex:{platform}", json.dumps(sorted(apex, key=lambda e: -e["lp"])[:300]))
    for tier in ("DIAMOND", "EMERALD"):
        for division in DIVISIONS:
            for page in range(1, s.league_pages + 1):
                for e in await client.league_entries(platform, tier, division, page):
                    if e.get("puuid"):
                        store.add_seed(e["puuid"], platform, tier)
    store.set(f"seeded:{platform}", str(time.time()))
    store.commit()


async def crawl_platform(client: RiotClient, store: Store, static: StaticData, platform: str, s: Settings, deadline: float) -> int:
    start_time = int(time.time()) - 14 * 86400
    new = 0

    async def fetch(match_id: str, bucket: str) -> None:
        nonlocal new
        raw = await client.match(platform, match_id)
        record = compact_match(raw, platform, bucket) if raw else None
        if record is None:
            store.skip_match(match_id)
            return
        store.put_match(record)
        new += 1
        if record["mode"] == "ranked" and record["duration"] >= 900 and zlib.crc32(match_id.encode()) % 1000 < s.timeline_ratio * 1000:
            if tl := await client.timeline(platform, match_id):
                store.put_timeline(match_id, timeline_features(tl, static.items))
        if record["mode"] == "ranked":
            for p in record["p"]:
                if p["puuid"]:
                    store.add_seed(p["puuid"], platform, bucket)

    async def crawl_seed(puuid: str, bucket: str, queue: int, count: int) -> None:
        ids = await client.match_ids(platform, puuid, queue=queue, start_time=start_time, count=count)
        for match_id in ids:
            if time.monotonic() > deadline or new >= s.matches_per_platform:
                return
            if not store.has_match(match_id):
                await fetch(match_id, bucket)
        store.mark_crawled(puuid)

    for bucket, share in BUCKET_QUOTAS.items():
        target = new + int(s.matches_per_platform * share)
        while new < target and time.monotonic() < deadline:
            seeds = store.next_seeds(platform, bucket, 8)
            if not seeds:
                break
            await asyncio.gather(*(crawl_seed(p, bucket, QUEUE_RANKED_SOLO, 20) for p in seeds), return_exceptions=False)
            store.commit()
    for queue in (QUEUE_ARAM, QUEUE_ARENA, QUEUE_ARAM_MAYHEM):
        for puuid in store.next_seeds(platform, "EMERALD", s.side_queue_seeds, older_than_s=0):
            if time.monotonic() > deadline:
                break
            await crawl_seed(puuid, "EMERALD", queue, 10)
        store.commit()
    return new


async def resolve_riot_ids(client: RiotClient, store: Store, platform: str, limit: int) -> None:
    for e in json.loads(store.get(f"apex:{platform}") or "[]")[:limit]:
        if store.riot_id(e["puuid"]) is None:
            acc = await client.account(platform, e["puuid"])
            if acc and acc.get("gameName"):
                store.put_riot_id(e["puuid"], f"{acc['gameName']}#{acc.get('tagLine', '')}")
    store.commit()


async def collect(store: Store, static: StaticData, s: Settings) -> dict[str, int]:
    deadline = time.monotonic() + s.max_minutes * 60
    async with RiotClient() as client:
        async def one(platform: str) -> int:
            try:
                await seed_platform(client, store, platform, s)
                await resolve_riot_ids(client, store, platform, s.leaderboard_size)
                return await crawl_platform(client, store, static, platform, s, deadline)
            except RiotAPIError as err:
                if err.status in (401, 403):
                    raise RuntimeError("Riot API-Key ungültig oder abgelaufen (401/403).") from err
                log.error("%s: %s", platform, err)
                return 0
        counts = await asyncio.gather(*(one(p) for p in s.platforms))
        log.info("Requests: %d", client.requests)
    return dict(zip(s.platforms, counts))
