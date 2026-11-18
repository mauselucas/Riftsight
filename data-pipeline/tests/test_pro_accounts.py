"""Tests für pro_accounts.py mit Fake-Antworten (kein Netzwerk, kein echter Riot-API-Key)."""
from __future__ import annotations

import asyncio
import json
from dataclasses import replace
from pathlib import Path
from urllib.parse import unquote

import httpx

from riftsight_pipeline.config import Settings
try:
    from riftsight_pipeline.pro_accounts import (
        clean_pro_name,
        fetch_leaguepedia_players,
        parse_role,
        parse_soloqueue_ids,
        resolve_pro_accounts,
        routing_for_platform,
        sync_pro_accounts,
    )
except ModuleNotFoundError:
    from pro_accounts import (  # type: ignore[no-redef]
        clean_pro_name,
        fetch_leaguepedia_players,
        parse_role,
        parse_soloqueue_ids,
        resolve_pro_accounts,
        routing_for_platform,
        sync_pro_accounts,
    )
from riftsight_pipeline.riot_client import RiotClient

FAKE_CARGO_PAYLOAD = {
    "cargoquery": [
        {
            "title": {
                "Player": "Caps (Rasmus Winther)",
                "ID": "Caps",
                "Team": "G2 Esports",
                "Role": "Mid",
                "SoloqueueIds": "[EUW] G2 Caps#1323, [KR] Caps#KR1",
            }
        },
        {
            "title": {
                "Player": "Faker",
                "ID": "Faker",
                "Team": "T1",
                "Role": "Middle",
                "SoloqueueIds": "Hide on bush&#35;KR1<br />[CN] Faker#CN1",
            }
        },
        {
            "title": {
                "Player": "Keria",
                "ID": "Keria",
                "Team": "T1",
                "Role": "Support",
                "SoloqueueIds": "[KR] T1 Keria#KR1; [KR] MissingAccount#404",
            }
        },
        {
            "title": {
                "Player": "Hans sama",
                "ID": "Hans sama",
                "Team": "G2 Esports",
                "Role": "ADC",
                "SoloqueueIds": "(EUW) Hans sama#EUW\nLegacySummonerWithoutTag",
            }
        },
    ]
}

FAKE_RIOT_ACCOUNTS: dict[tuple[str, str, str], str] = {
    ("europe", "g2 caps", "1323"): "puuid-caps-euw",
    ("asia", "caps", "kr1"): "puuid-caps-kr",
    ("asia", "hide on bush", "kr1"): "puuid-faker-kr",
    ("asia", "t1 keria", "kr1"): "puuid-keria-kr",
    ("europe", "hans sama", "euw"): "puuid-hans-euw",
}


def _make_leaguepedia_transport() -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "lol.fandom.com"
        assert request.url.params.get("action") == "cargoquery"
        assert request.url.params.get("tables") == "Players"
        assert "SoloqueueIds" in (request.url.params.get("fields") or "")
        return httpx.Response(200, json=FAKE_CARGO_PAYLOAD)

    return httpx.MockTransport(handler)


def _make_riot_transport() -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers.get("X-Riot-Token") == "fake-test-key"
        routing = request.url.host.split(".")[0]
        parts = request.url.path.split("/")
        # Pfad: /riot/account/v1/accounts/by-riot-id/{gameName}/{tagLine}
        assert parts[:6] == ["", "riot", "account", "v1", "accounts", "by-riot-id"]
        game_name = unquote(parts[6]).lower()
        tag_line = unquote(parts[7]).lower()
        puuid = FAKE_RIOT_ACCOUNTS.get((routing, game_name, tag_line))
        if puuid is None:
            return httpx.Response(404, json={"status": {"message": "Data not found", "status_code": 404}})
        return httpx.Response(
            200,
            headers={"X-App-Rate-Limit": "500:10,30000:600", "X-Method-Rate-Limit": "1000:10"},
            json={"puuid": puuid, "gameName": parts[6], "tagLine": parts[7]},
        )

    return httpx.MockTransport(handler)


def test_parse_role_and_name() -> None:
    assert parse_role("Mid") == "MIDDLE"
    assert parse_role("ADC") == "BOTTOM"
    assert parse_role("Support") == "UTILITY"
    assert parse_role("Jungle / Top") == "JUNGLE"
    assert parse_role("Coach") is None
    assert parse_role(None) is None
    assert clean_pro_name("Caps (Rasmus Winther)", "Caps") == "Caps"
    assert clean_pro_name("Caps (Rasmus Winther)", None) == "Caps"


def test_parse_soloqueue_ids() -> None:
    raw = "[EUW] G2 Caps#1323, [KR] Hide on bush&#35;KR1<br/>(NA) Blaber#NA1; [CN] Knight#CN1; LegacyNoTag"
    parsed = parse_soloqueue_ids(raw)
    assert parsed == [
        ("EUW1", "G2 Caps", "1323"),
        ("KR", "Hide on bush", "KR1"),
        ("NA1", "Blaber", "NA1"),
    ]


def test_routing_for_platform() -> None:
    assert routing_for_platform("EUW1") == "europe"
    assert routing_for_platform("NA1") == "americas"
    assert routing_for_platform("KR") == "asia"
    assert routing_for_platform("SG2") == "asia"


def test_end_to_end_sync_with_fake_responses(tmp_path: Path) -> None:
    async def run() -> list[dict]:
        settings = replace(
            Settings().sampled(),
            out_dir=tmp_path / "out",
            dist_dir=tmp_path / "dist",
        )
        async with (
            httpx.AsyncClient(transport=_make_leaguepedia_transport()) as lp_client,
            RiotClient(api_key="fake-test-key", transport=_make_riot_transport()) as riot_client,
        ):
            players = await fetch_leaguepedia_players(lp_client)
            assert len(players) == 4
            resolved = await resolve_pro_accounts(players, riot_client)
            assert len(resolved) == 5

            # Voller Sync inkl. Dateischreiben nach out/ und dist/
            written = await sync_pro_accounts(
                settings,
                riot_client=riot_client,
                leaguepedia_client=lp_client,
            )
            return written

    accounts = asyncio.run(run())
    assert accounts == [
        {
            "puuid": "puuid-caps-euw",
            "platform": "EUW1",
            "proName": "Caps",
            "proTeam": "G2 Esports",
            "role": "MIDDLE",
        },
        {
            "puuid": "puuid-caps-kr",
            "platform": "KR",
            "proName": "Caps",
            "proTeam": "G2 Esports",
            "role": "MIDDLE",
        },
        {
            "puuid": "puuid-faker-kr",
            "platform": "KR",
            "proName": "Faker",
            "proTeam": "T1",
            "role": "MIDDLE",
        },
        {
            "puuid": "puuid-keria-kr",
            "platform": "KR",
            "proName": "Keria",
            "proTeam": "T1",
            "role": "UTILITY",
        },
        {
            "puuid": "puuid-hans-euw",
            "platform": "EUW1",
            "proName": "Hans sama",
            "proTeam": "G2 Esports",
            "role": "BOTTOM",
        },
    ]

    out_file = tmp_path / "out" / "pro_accounts.json"
    dist_file = tmp_path / "dist" / "pro_accounts.json"
    assert out_file.exists() and dist_file.exists()
    loaded = json.loads(out_file.read_text(encoding="utf-8"))
    assert loaded == accounts
