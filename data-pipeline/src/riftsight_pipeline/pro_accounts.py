"""Leaguepedia Cargo API sync: resolves pro players' Soloqueue Riot IDs to PUUIDs via Riot Account-V1
and writes ``pro_accounts.json`` (``[{puuid, platform, proName, proTeam, role}]``).
"""
from __future__ import annotations

import argparse
import asyncio
import html
import json
import logging
import re
from pathlib import Path
from typing import Any

import httpx

try:
    from .config import REGIONAL, Settings, load_settings
    from .riot_client import RiotAPIError, RiotClient
except ImportError:
    from riftsight_pipeline.config import REGIONAL, Settings, load_settings
    from riftsight_pipeline.riot_client import RiotAPIError, RiotClient

log = logging.getLogger("riftsight.pro_accounts")

LEAGUEPEDIA_API_URL = "https://lol.fandom.com/api.php"

ROLE_MAP: dict[str, str] = {
    "top": "TOP",
    "toplane": "TOP",
    "top laner": "TOP",
    "top lane": "TOP",
    "jungle": "JUNGLE",
    "jungler": "JUNGLE",
    "jgl": "JUNGLE",
    "jg": "JUNGLE",
    "mid": "MIDDLE",
    "middle": "MIDDLE",
    "midlane": "MIDDLE",
    "mid laner": "MIDDLE",
    "mid lane": "MIDDLE",
    "bot": "BOTTOM",
    "bottom": "BOTTOM",
    "adc": "BOTTOM",
    "ad carry": "BOTTOM",
    "ad": "BOTTOM",
    "bot laner": "BOTTOM",
    "support": "UTILITY",
    "utility": "UTILITY",
    "sup": "UTILITY",
    "supp": "UTILITY",
}

PLATFORM_ALIASES: dict[str, str] = {
    "EUW": "EUW1",
    "EUW1": "EUW1",
    "EU": "EUW1",
    "EUNE": "EUN1",
    "EUN": "EUN1",
    "EUN1": "EUN1",
    "TR": "TR1",
    "TR1": "TR1",
    "RU": "RU",
    "RU1": "RU",
    "ME": "ME1",
    "ME1": "ME1",
    "NA": "NA1",
    "NA1": "NA1",
    "BR": "BR1",
    "BR1": "BR1",
    "LAN": "LA1",
    "LA1": "LA1",
    "LAS": "LA2",
    "LA2": "LA2",
    "KR": "KR",
    "KR1": "KR",
    "KOR": "KR",
    "JP": "JP1",
    "JP1": "JP1",
    "OCE": "OC1",
    "OC": "OC1",
    "OC1": "OC1",
    "SG": "SG2",
    "SG2": "SG2",
    "SEA": "SG2",
    "PCS": "SG2",
    "TW": "TW2",
    "TW2": "TW2",
    "VN": "VN2",
    "VN2": "VN2",
}

UNSUPPORTED_REGIONS = {"CN", "CHINA", "IONIA", "PBE"}

# Trennt Einträge in SoloqueueIds an Zeilenumbrüchen, <br>-Tags, Semikolons oder Kommas
_SPLIT_RE = re.compile(r"(?:<br\s*/?>|[\r\n;,])+", re.IGNORECASE)
# Erkennt optionale Regions-Präfixe wie "[EUW] Name#Tag", "(KR) Name#Tag" oder "NA: Name#Tag"
_PREFIX_RE = re.compile(
    r"^\s*(?:\[\s*([A-Za-z0-9]+)\s*\]|\(\s*([A-Za-z0-9]+)\s*\)|([A-Za-z0-9]{2,4})\s*:\s*)\s*(.+)$"
)
# Entfernt Wiki-Verlinkungen oder Klammerzusätze im Spielernamen wie "Caps (Rasmus Winther)"
_PAREN_RE = re.compile(r"\s*\([^)]*\)\s*$")


def routing_for_platform(platform: str) -> str:
    """Account-V1 wird über europe / americas / asia bedient; SEA-Plattformen laufen über asia."""
    cluster = REGIONAL.get(platform.upper(), "europe")
    return "asia" if cluster == "sea" else cluster


def parse_role(raw: str | None) -> str | None:
    """Normalisiert Leaguepedia-Rollen ('Mid', 'ADC', 'Support', ...) auf Riftsight-Rollen."""
    if not raw:
        return None
    cleaned = html.unescape(raw).strip()
    for token in re.split(r"[,/;]+", cleaned):
        key = token.strip().lower()
        if key in ROLE_MAP:
            return ROLE_MAP[key]
    return None


def clean_pro_name(player: str | None, player_id: str | None) -> str:
    """Extrahiert den kanonischen Pro-Namen aus ``ID`` oder ``Player``."""
    candidate = (player_id or player or "").strip()
    candidate = html.unescape(candidate)
    candidate = _PAREN_RE.sub("", candidate).strip()
    return candidate


def _infer_platform(prefix: str | None, tag_line: str, default_platform: str) -> str | None:
    if prefix:
        upper_prefix = prefix.strip().upper()
        if upper_prefix in UNSUPPORTED_REGIONS:
            return None
        if mapped := PLATFORM_ALIASES.get(upper_prefix):
            return mapped
    upper_tag = tag_line.strip().upper()
    if upper_tag in UNSUPPORTED_REGIONS:
        return None
    if mapped := PLATFORM_ALIASES.get(upper_tag):
        return mapped
    # Tags wie "EU1".."EU9", "KR1".."KR9", "NA1".."NA9"
    for code, target in (("EUW", "EUW1"), ("EUN", "EUN1"), ("KR", "KR"), ("NA", "NA1")):
        if upper_tag.startswith(code):
            return target
    return PLATFORM_ALIASES.get(default_platform.upper(), default_platform.upper())


def parse_soloqueue_ids(raw: str | None, *, default_platform: str = "EUW1") -> list[tuple[str, str, str]]:
    """Parst das Leaguepedia-Feld ``SoloqueueIds`` in ``[(platform, game_name, tag_line), ...]``.

    Unterstützt Formate wie:
    - ``[EUW] G2 Caps#1323, [KR] Caps#KR1``
    - ``(NA) Blaber#NA1; Chovy#KR1``
    - ``Faker#KR1<br />Hide on bush#KR1``
    - HTML-Entities wie ``G2 Caps&#35;1323``
    """
    if not raw:
        return []
    unescaped = html.unescape(raw).replace("\u00a0", " ")
    results: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()

    for chunk in _SPLIT_RE.split(unescaped):
        entry = chunk.strip()
        if not entry or "#" not in entry:
            continue

        prefix: str | None = None
        if m := _PREFIX_RE.match(entry):
            prefix = m.group(1) or m.group(2) or m.group(3)
            entry = m.group(4).strip()

        # Manche Einträge haben nach dem Tag noch Klammerkommentare wie "Name#TAG ( Main )"
        entry = _PAREN_RE.sub("", entry).strip()
        if "#" not in entry:
            continue

        game_name, tag_line = entry.split("#", 1)
        game_name = game_name.strip()
        tag_line = tag_line.strip()
        if not game_name or not tag_line:
            continue
        # Ungültige Riot-IDs (z. B. URLs oder kaputte Wiki-Fragmente) ausschließen
        if any(ch in game_name or ch in tag_line for ch in ("/", "[", "]", "<", ">")):
            continue

        platform = _infer_platform(prefix, tag_line, default_platform)
        if not platform or platform not in REGIONAL:
            continue

        key = (platform, game_name.lower(), tag_line.lower())
        if key not in seen:
            seen.add(key)
            results.append((platform, game_name, tag_line))

    return results


async def fetch_leaguepedia_players(
    http_client: httpx.AsyncClient | None = None,
    *,
    limit: int = 500,
    max_pages: int = 5,
    where: str = "SoloqueueIds IS NOT NULL",
) -> list[dict[str, Any]]:
    """Lädt Spieler mit bekannten ``SoloqueueIds`` über die Leaguepedia Cargo API."""
    owns_client = http_client is None
    client = http_client or httpx.AsyncClient(
        headers={"User-Agent": "riftsight-pipeline/1.0 (https://github.com/riftsight; CC-BY-SA-3.0)"},
        timeout=25.0,
    )
    players: list[dict[str, Any]] = []
    try:
        for page in range(max_pages):
            params = {
                "action": "cargoquery",
                "format": "json",
                "tables": "Players",
                "fields": "Player,ID,Team,Role,SoloqueueIds",
                "where": where,
                "limit": str(limit),
                "offset": str(page * limit),
            }
            resp = await client.get(LEAGUEPEDIA_API_URL, params=params)
            resp.raise_for_status()
            payload = resp.json()
            rows = payload.get("cargoquery") or []
            if not rows:
                break
            for item in rows:
                title = item.get("title") if isinstance(item, dict) else None
                if isinstance(title, dict):
                    players.append(title)
            if len(rows) < limit:
                break
    finally:
        if owns_client:
            await client.aclose()
    return players


async def resolve_pro_accounts(
    players: list[dict[str, Any]],
    riot_client: RiotClient,
    *,
    allowed_platforms: set[str] | None = None,
    default_platform: str = "EUW1",
    max_accounts_per_player: int = 3,
) -> list[dict[str, Any]]:
    """Löst die Soloqueue-Riot-IDs aus Leaguepedia via ``RiotClient.account_by_riot_id`` zu PUUIDs auf.

    Rückgabeformat: ``[{puuid, platform, proName, proTeam, role}]``
    """
    resolved: list[dict[str, Any]] = []
    seen_puuids: set[str] = set()
    seen_queries: set[tuple[str, str, str]] = set()

    for row in players:
        pro_name = clean_pro_name(row.get("Player"), row.get("ID"))
        if not pro_name:
            continue
        team_raw = html.unescape(str(row.get("Team") or "")).strip()
        pro_team: str | None = team_raw if team_raw else None
        role = parse_role(row.get("Role"))

        candidates = parse_soloqueue_ids(row.get("SoloqueueIds"), default_platform=default_platform)
        added_for_player = 0

        for platform, game_name, tag_line in candidates:
            if added_for_player >= max_accounts_per_player:
                break
            if allowed_platforms and platform not in allowed_platforms:
                continue

            routing = routing_for_platform(platform)
            query_key = (routing, game_name.lower(), tag_line.lower())
            if query_key in seen_queries:
                continue
            seen_queries.add(query_key)

            try:
                account = await riot_client.account_by_riot_id(routing, game_name, tag_line)
            except RiotAPIError as err:
                if err.status in (401, 403):
                    raise
                log.warning("Account-V1 Fehler (%s) für %s#%s: %s", err.status, game_name, tag_line, err)
                continue

            if not account or not account.get("puuid"):
                continue

            puuid = str(account["puuid"]).strip()
            if not puuid or puuid in seen_puuids:
                continue

            seen_puuids.add(puuid)
            added_for_player += 1
            resolved.append(
                {
                    "puuid": puuid,
                    "platform": platform,
                    "proName": pro_name,
                    "proTeam": pro_team,
                    "role": role,
                }
            )

    return resolved


def write_pro_accounts(accounts: list[dict[str, Any]], *target_dirs: Path) -> list[Path]:
    """Schreibt ``pro_accounts.json`` in alle angegebenen Zielordner (z. B. ``out/`` und ``dist/``)."""
    payload = json.dumps(accounts, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    written: list[Path] = []
    for directory in target_dirs:
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / "pro_accounts.json"
        path.write_bytes(payload)
        written.append(path)
    return written


async def sync_pro_accounts(
    settings: Settings | None = None,
    *,
    riot_client: RiotClient | None = None,
    leaguepedia_client: httpx.AsyncClient | None = None,
    filter_to_configured_platforms: bool = False,
) -> list[dict[str, Any]]:
    """Kompletter Sync-Lauf: Leaguepedia Cargo API -> Account-V1 -> ``pro_accounts.json``."""
    s = settings or load_settings()
    players = await fetch_leaguepedia_players(leaguepedia_client)
    allowed = set(s.platforms) if filter_to_configured_platforms else None

    if riot_client is not None:
        accounts = await resolve_pro_accounts(players, riot_client, allowed_platforms=allowed)
    else:
        async with RiotClient() as client:
            accounts = await resolve_pro_accounts(players, client, allowed_platforms=allowed)

    write_pro_accounts(accounts, s.out_dir, s.dist_dir)
    log.info("pro_accounts.json geschrieben: %d Pro-Accounts aufgelöst (aus %d Spielern)", len(accounts), len(players))
    return accounts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="riftsight-pro-accounts", description="Sync pro_accounts.json from Leaguepedia + Account-V1")
    parser.add_argument(
        "--only-configured-platforms",
        action="store_true",
        help="Nur Accounts behalten, deren Plattform in RIFTSIGHT_PLATFORMS enthalten ist.",
    )
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    s = load_settings()
    asyncio.run(sync_pro_accounts(s, filter_to_configured_platforms=args.only_configured_platforms))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
