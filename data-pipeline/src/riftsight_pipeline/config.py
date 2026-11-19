"""Platforms, routing, thresholds and paths. Production values follow the Gemini research brief
(docs/gemini-ergebnisse-datenpipeline.md); ``SAMPLE_MODE=1`` lowers every threshold so a Dev/Personal key
(or the test suite) produces non-empty files from a few hundred matches."""
from __future__ import annotations

import os
from dataclasses import dataclass, field, replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

REGIONAL = {
    "EUW1": "europe", "EUN1": "europe", "TR1": "europe", "RU": "europe", "ME1": "europe",
    "NA1": "americas", "BR1": "americas", "LA1": "americas", "LA2": "americas",
    "KR": "asia", "JP1": "asia",
    "OC1": "sea", "SG2": "sea", "TW2": "sea", "VN2": "sea",
}

ROLES = ("TOP", "JUNGLE", "MIDDLE", "BOTTOM", "UTILITY")

QUEUE_RANKED_SOLO = 420
QUEUE_ARAM = 450
QUEUE_ARENA = 1700
QUEUE_ARAM_MAYHEM = 2400  # UNSICHER laut Recherche – zusätzlich über gameMode erkannt.
ARAM_MAYHEM_GAME_MODES = {"ARAM_MAYHEM", "KIWI"}
ARENA_GAME_MODES = {"CHERRY"}

# Seed buckets and the share of crawl budget each one gets (anti high-elo bias).
BUCKET_QUOTAS = {"EMERALD": 0.60, "DIAMOND": 0.30, "APEX": 0.10}

# Tier list rank brackets: which seed buckets feed which bracket.
RANK_BRACKETS = {
    "EMERALD_PLUS": {"EMERALD", "DIAMOND", "APEX"},
    "DIAMOND_PLUS": {"DIAMOND", "APEX"},
    "MASTER_PLUS": {"APEX"},
}

TRINKETS = {3340, 3363, 3364, 3513}


@dataclass(frozen=True)
class Settings:
    platforms: tuple[str, ...] = ("EUW1", "KR", "NA1")
    sample_mode: bool = False

    # Collection budget
    max_minutes: float = 300.0
    matches_per_platform: int = 75_000
    timeline_ratio: float = 0.5           # share of eligible matches (>= 15 min) that also get a timeline
    side_queue_seeds: int = 400           # seeds per platform whose ARAM/Arena/Mayhem games are crawled
    league_pages: int = 5                 # League-V4 entry pages per tier/division

    # Aggregation thresholds
    min_lane_share: float = 0.015
    tier_min_games: int = 100
    counter_base_min_games: int = 200
    counter_min_games: int = 50
    counter_prior: float = 50.0
    counters_per_side: int = 20
    blend_target_tier: int = 1_000
    blend_target_matchup: int = 300
    build_min_games: int = 200
    vs_min_games: int = 150
    vs_core_min_games: int = 400
    vs_skill_min_timelines: int = 150
    rune_min_pickrate: float = 0.10
    archetype_min_pickrate: float = 0.12
    item_context_min: int = 200
    duo_min_games: int = 100
    duo_prior: float = 80.0
    augment_min_games: int = 50
    augment_prior: float = 40.0
    champion_augment_min_games: int = 30
    min_champions_published: int = 150
    leaderboard_size: int = 100

    # Focus mode: champions whose games get extra crawl budget and always a timeline (builds need timelines).
    # Players seen on a focus champion become priority seeds, so one-tricks are revisited every run.
    focus_champions: tuple[int, ...] = ()
    focus_share: float = 0.6

    state_dir: Path = field(default_factory=lambda: ROOT / "state")
    out_dir: Path = field(default_factory=lambda: ROOT / "out")
    dist_dir: Path = field(default_factory=lambda: ROOT / "dist")

    @property
    def db_path(self) -> Path:
        return self.state_dir / "matches.sqlite"

    def sampled(self) -> "Settings":
        """Thresholds small enough for a Dev key (~8k matches/day) or for tests."""
        return replace(
            self,
            sample_mode=True,
            max_minutes=20.0,
            matches_per_platform=400,
            side_queue_seeds=20,
            league_pages=1,
            tier_min_games=5,
            counter_base_min_games=10,
            counter_min_games=3,
            build_min_games=5,
            vs_min_games=30,
            vs_core_min_games=30,
            vs_skill_min_timelines=3,
            item_context_min=5,
            duo_min_games=3,
            augment_min_games=3,
            champion_augment_min_games=2,
            min_champions_published=1,
            leaderboard_size=50,
        )


def load_settings() -> Settings:
    settings = Settings()
    if raw := os.environ.get("RIFTSIGHT_PLATFORMS"):
        settings = replace(settings, platforms=tuple(p.strip().upper() for p in raw.split(",") if p.strip()))
    if raw := os.environ.get("RIFTSIGHT_STATE_DIR"):
        settings = replace(settings, state_dir=Path(raw))
    if raw := os.environ.get("RIFTSIGHT_OUT_DIR"):
        settings = replace(settings, out_dir=Path(raw))
    if os.environ.get("SAMPLE_MODE", "").lower() in {"1", "true", "yes"}:
        settings = settings.sampled()
    if raw := os.environ.get("RIFTSIGHT_FOCUS_CHAMPIONS"):
        settings = replace(settings, focus_champions=tuple(int(x) for x in raw.replace(" ", "").split(",") if x.isdigit()))
    if raw := os.environ.get("MATCHES_PER_PLATFORM"):
        settings = replace(settings, matches_per_platform=int(raw))
    if raw := os.environ.get("COLLECT_MAX_MINUTES"):
        settings = replace(settings, max_minutes=float(raw))
    return settings
