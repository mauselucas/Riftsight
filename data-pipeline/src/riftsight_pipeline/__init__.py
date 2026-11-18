"""Riftsight data pipeline.

Collects Emerald+ matches through the official Riot API (Match-V5, League-V4, Account-V1,
Spectator-V5) and aggregates them into the seven JSON files the macOS app reads.
The Riot API key only ever lives in the CI secret ``RIOT_API_KEY`` – never in the app.
"""

SCHEMA_VERSION = 1
