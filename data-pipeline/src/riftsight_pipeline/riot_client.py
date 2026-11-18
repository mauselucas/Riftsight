"""Async Riot API client with per-host app + method rate limiting.

* The key comes only from the environment variable ``RIOT_API_KEY`` (GitHub Actions secret) and is sent in the
  ``X-Riot-Token`` header – it is never logged, never written to disk and never part of a URL.
* Limits start from conservative defaults (Development key: 20/1s, 100/120s) and adapt to the
  ``X-App-Rate-Limit`` / ``X-Method-Rate-Limit`` headers Riot returns.
* 429 → wait ``Retry-After`` + 0.5 s; 5xx / network errors → exponential backoff, at most 5 retries.
"""
from __future__ import annotations

import asyncio
import logging
import os
import random
import time
from collections import deque
from typing import Any
from urllib.parse import quote

import httpx

from .config import REGIONAL

log = logging.getLogger("riftsight.riot")

DEFAULT_APP_LIMITS = [(20, 1.0), (100, 120.0)]
MAX_RETRIES = 5


class RiotAPIError(RuntimeError):
    def __init__(self, status: int, path: str):
        super().__init__(f"Riot API {status} for {path}")
        self.status = status


class SlidingWindowLimiter:
    """Several (count, seconds) windows; ``acquire`` waits until every window has room."""

    def __init__(self, limits: list[tuple[int, float]], safety: float = 0.9):
        self.safety = safety
        self._lock = asyncio.Lock()
        self.set_limits(limits)

    def set_limits(self, limits: list[tuple[int, float]]) -> None:
        self.limits = [(max(1, int(count * self.safety)), seconds) for count, seconds in limits]
        self.history: deque[float] = getattr(self, "history", deque())

    async def acquire(self) -> None:
        async with self._lock:
            while True:
                now = time.monotonic()
                longest = max(s for _, s in self.limits)
                while self.history and now - self.history[0] > longest:
                    self.history.popleft()
                wait = 0.0
                for count, seconds in self.limits:
                    recent = [t for t in self.history if now - t < seconds]
                    if len(recent) >= count:
                        wait = max(wait, seconds - (now - recent[-count]) + 0.01)
                if wait <= 0:
                    self.history.append(now)
                    return
                await asyncio.sleep(wait)

    async def pause(self, seconds: float) -> None:
        async with self._lock:
            await asyncio.sleep(seconds)


def parse_limits(header: str | None) -> list[tuple[int, float]] | None:
    """'20:1,100:120' → [(20, 1.0), (100, 120.0)]."""
    if not header:
        return None
    try:
        return [(int(c), float(s)) for c, s in (part.split(":") for part in header.split(",") if part)]
    except ValueError:
        return None


class RiotClient:
    def __init__(self, api_key: str | None = None, *, timeout: float = 20.0, transport: httpx.AsyncBaseTransport | None = None):
        key = (api_key or os.environ.get("RIOT_API_KEY") or "").strip().strip("'\"").strip()
        if key.startswith("RIOT_API_KEY="):
            key = key.split("=", 1)[1].strip().strip("'\"")
        if not key:
            raise RuntimeError("RIOT_API_KEY ist nicht gesetzt (GitHub-Secret oder lokale Umgebungsvariable).")
        if not key.startswith("RGAPI-") or len(key) != 42:
            log.warning("RIOT_API_KEY sieht ungewöhnlich aus (Länge %d, beginnt mit RGAPI-: %s).", len(key), key.startswith("RGAPI-"))
        self._client = httpx.AsyncClient(headers={"X-Riot-Token": key, "User-Agent": "riftsight-pipeline/1.0"},
                                         timeout=timeout, transport=transport)
        self._app: dict[str, SlidingWindowLimiter] = {}
        self._method: dict[tuple[str, str], SlidingWindowLimiter] = {}
        self.requests = 0

    async def aclose(self) -> None:
        await self._client.aclose()

    async def __aenter__(self) -> "RiotClient":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        await self.aclose()

    # ------------------------------------------------------------------------------------

    def _limiter(self, host: str, method: str) -> tuple[SlidingWindowLimiter, SlidingWindowLimiter]:
        app = self._app.setdefault(host, SlidingWindowLimiter(DEFAULT_APP_LIMITS))
        meth = self._method.setdefault((host, method), SlidingWindowLimiter([(1_000, 10.0)]))
        return app, meth

    async def get(self, host: str, path: str, method: str, params: dict[str, Any] | None = None) -> Any:
        """Returns parsed JSON, or ``None`` for 404. Raises RiotAPIError for 400/401/403."""
        app, meth = self._limiter(host, method)
        url = f"https://{host}.api.riotgames.com{path}"
        for attempt in range(MAX_RETRIES + 1):
            await app.acquire()
            await meth.acquire()
            try:
                resp = await self._client.get(url, params=params)
            except (httpx.TransportError, httpx.TimeoutException):
                await asyncio.sleep(min(30.0, 2 ** attempt + random.random()))
                continue
            self.requests += 1
            if limits := parse_limits(resp.headers.get("X-App-Rate-Limit")):
                if limits != [(int(c / app.safety), s) for c, s in app.limits]:
                    app.set_limits(limits)
            if limits := parse_limits(resp.headers.get("X-Method-Rate-Limit")):
                meth.set_limits(limits)
            if resp.status_code == 200:
                return resp.json()
            if resp.status_code == 404:
                return None
            if resp.status_code == 429:
                retry = float(resp.headers.get("Retry-After", "1") or 1) + 0.5
                log.warning("429 (%s) auf %s – warte %.1fs", resp.headers.get("X-Rate-Limit-Type", "?"), method, retry)
                await (app if resp.headers.get("X-Rate-Limit-Type") == "application" else meth).pause(retry)
                continue
            if resp.status_code >= 500:
                await asyncio.sleep(min(30.0, 2 ** attempt + random.random()))
                continue
            raise RiotAPIError(resp.status_code, path)
        raise RiotAPIError(599, path)

    # Endpoints -----------------------------------------------------------------------------

    async def league_apex(self, platform: str, tier: str) -> dict[str, Any] | None:
        name = {"CHALLENGER": "challengerleagues", "GRANDMASTER": "grandmasterleagues", "MASTER": "masterleagues"}[tier]
        return await self.get(platform.lower(), f"/lol/league/v4/{name}/by-queue/RANKED_SOLO_5x5", f"league-{name}")

    async def league_entries(self, platform: str, tier: str, division: str, page: int) -> list[dict[str, Any]]:
        data = await self.get(platform.lower(), f"/lol/league/v4/entries/RANKED_SOLO_5x5/{tier}/{division}",
                              "league-entries", {"page": page})
        return data or []

    async def match_ids(self, platform: str, puuid: str, *, queue: int, start_time: int | None = None,
                        count: int = 20) -> list[str]:
        params: dict[str, Any] = {"queue": queue, "start": 0, "count": count}
        if start_time:
            params["startTime"] = start_time
        data = await self.get(REGIONAL[platform], f"/lol/match/v5/matches/by-puuid/{quote(puuid)}/ids", "match-ids", params)
        return data or []

    async def match(self, platform: str, match_id: str) -> dict[str, Any] | None:
        return await self.get(REGIONAL[platform], f"/lol/match/v5/matches/{match_id}", "match")

    async def timeline(self, platform: str, match_id: str) -> dict[str, Any] | None:
        return await self.get(REGIONAL[platform], f"/lol/match/v5/matches/{match_id}/timeline", "timeline")

    async def account(self, platform: str, puuid: str) -> dict[str, Any] | None:
        # Account-V1 is served from americas/europe/asia; SEA accounts resolve via asia.
        routing = {"sea": "asia"}.get(REGIONAL[platform], REGIONAL[platform])
        return await self.get(routing, f"/riot/account/v1/accounts/by-puuid/{quote(puuid)}", "account-by-puuid")

    async def account_by_riot_id(self, routing: str, game_name: str, tag_line: str) -> dict[str, Any] | None:
        return await self.get(routing, f"/riot/account/v1/accounts/by-riot-id/{quote(game_name)}/{quote(tag_line)}",
                              "account-by-riot-id")

    async def active_game(self, platform: str, puuid: str) -> dict[str, Any] | None:
        return await self.get(platform.lower(), f"/lol/spectator/v5/active-games/by-summoner/{quote(puuid)}", "spectator")
