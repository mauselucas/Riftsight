"""Public static game data: Data Dragon (patch, champions) and CommunityDragon (items, augments).

No API key needed. Cached per patch under ``state/static`` so CI reruns don't re-download.
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx

log = logging.getLogger("riftsight.static")

DDRAGON = "https://ddragon.leagueoflegends.com"
CDRAGON = "https://raw.communitydragon.org/latest"
GAME_DATA = f"{CDRAGON}/plugins/rcp-be-lol-game-data/global/default/v1"

RARITY = {"kSilver": "silver", "kGold": "gold", "kPrismatic": "prismatic", 0: "silver", 1: "gold", 2: "prismatic"}


@dataclass
class StaticData:
    version: str
    patch: str
    champions: dict[int, dict[str, Any]]
    items: dict[int, dict[str, Any]]
    augment_rarity: dict[int, str] = field(default_factory=dict)

    @property
    def previous_patch(self) -> str:
        major, minor = (int(x) for x in self.patch.split("."))
        return f"{major}.{minor - 1}" if minor > 1 else f"{major - 1}.24"


def _get(client: httpx.Client, url: str) -> Any:
    resp = client.get(url, timeout=60)
    resp.raise_for_status()
    return resp.json()


def load_static(cache_dir: Path, client: httpx.Client | None = None) -> StaticData:
    own = client is None
    client = client or httpx.Client(headers={"User-Agent": "riftsight-pipeline/1.0"}, follow_redirects=True)
    try:
        version = _get(client, f"{DDRAGON}/api/versions.json")[0]
        cache = cache_dir / f"static-{version}.json"
        if cache.exists():
            raw = json.loads(cache.read_text())
        else:
            champions = _get(client, f"{DDRAGON}/cdn/{version}/data/en_US/champion.json")["data"]
            items = _get(client, f"{GAME_DATA}/items.json")
            try:
                augments = _get(client, f"{GAME_DATA}/cherry-augments.json")
            except httpx.HTTPError:
                augments = []
            raw = {"version": version, "champions": champions, "items": items, "augments": augments}
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(raw))
    finally:
        if own:
            client.close()
    return from_raw(raw)


def from_raw(raw: dict[str, Any]) -> StaticData:
    version = raw["version"]
    champions = {int(c["key"]): c for c in raw["champions"].values()}
    items = {int(i["id"]): i for i in raw["items"]}
    rarity = {int(a["id"]): RARITY.get(a.get("rarity"), "silver") for a in raw.get("augments") or [] if a.get("id") is not None}
    return StaticData(version=version, patch=".".join(version.split(".")[:2]), champions=champions, items=items,
                      augment_rarity=rarity)
