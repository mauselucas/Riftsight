# Riftsight Daten-Pipeline

Erzeugt täglich die 7 JSON-Dateien der App (counterpicks, matchup_runes, item_stats, tierlist, aram_augments, pro_spectate, leaderboard) aus der offiziellen Riot API. Der API-Key liegt **nur** im GitHub-Secret `RIOT_API_KEY`, nie in der App.

```bash
uv sync && uv run pytest            # Tests (synthetische Matches, kein Key nötig)
RIOT_API_KEY=… SAMPLE_MODE=1 uv run riftsight run   # lokal, kleine Schwellen für Dev-Key
uv run python -m riftsight_pipeline.sample           # Beispieldaten für die App neu erzeugen
```

Ablauf: `collect` (League-V4-Seeds 60/30/10 Emerald/Diamond/Apex → Match-V5, 50 % Timelines, SQLite+zstd in `state/`) → `aggregate` (ein Durchlauf, Methodik laut `docs/gemini-ergebnisse-datenpipeline.md`) → Schema-Gate → `dist/` (JSON + gzip + manifest) → GitHub Pages. In der App unter Einstellungen → Daten-Pipeline die Pages-URL eintragen.

Offen: Cloudflare-Worker für Live-`pro_spectate` (aktuell leere Liste) und Leaguepedia-Pro-Accounts.
