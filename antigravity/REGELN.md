# Regeln für Gemini (Antigravity) – UNBEDINGT LESEN

Du arbeitest im Projekt **Riftsight** (macOS-LoL-App in Swift + Python-Datenpipeline). Claude Code ist für den Code verantwortlich.

## Absolut verboten
- **Keine Datei außerhalb von `antigravity/inbox/` anlegen, ändern, verschieben oder löschen.** Auch nicht `macOS-App/`, `data-pipeline/`, `docs/`, `.github/`.
- Kein `git commit`, `git push`, keine Formatierer/Refactorings über das Projekt laufen lassen, keine Abhängigkeiten installieren.
- Keine API-Keys, Passwörter oder Tokens in Dateien schreiben.

## So lieferst du ab
Für jede Aufgabe einen Ordner `antigravity/inbox/<nr>-<kurzname>/` mit:
1. `NOTIZ.md` – was du gebaut hast, Zieldatei (wo es hin soll), offene Fragen, Quellen.
2. Die fertigen Dateien bzw. Codeschnipsel, vollständig und lauffähig (keine `...`-Platzhalter).

Lesen darfst du alles im Projekt. Halte dich an bestehende Schemas:
- JSON-Vertrag: `macOS-App/Sources/RiftsightCore/Models/PipelineModels.swift`
- Pipeline-Code: `data-pipeline/src/riftsight_pipeline/` (Python 3.12, httpx, kein numpy)
- Methodik: `docs/gemini-ergebnisse-datenpipeline.md`

Nur offizielle Riot-APIs (kein Scraping von op.gg/u.gg etc.). Riot-Key immer nur aus der Umgebungsvariable `RIOT_API_KEY` / Worker-Secret.

## Aufgaben (der Reihe nach)
1. **`1-worker-spectate`** – Cloudflare Worker (TypeScript, `wrangler.toml`, `package.json`, `src/index.ts`): Cron `*/2 * * * *`, liest `pro_accounts.json` + `leaderboard.json` aus R2, fragt rotierend Spectator-V5 `active-games/by-summoner/{puuid}` ab (Rate-Limit beachten, 429 → Retry-After), schreibt `pro_spectate.json` exakt im Schema `ProSpectateFile` nach R2 (`Cache-Control: max-age=60`).
2. **`2-pro-accounts`** – Python-Modul `pro_accounts.py` (Ziel: `data-pipeline/src/riftsight_pipeline/`): Leaguepedia Cargo API (`lol.fandom.com/api.php?action=cargoquery`, Tabelle Players: Player, ID, Team, Role, SoloqueueIds), Riot-IDs parsen, über Account-V1 zu PUUID auflösen (nutze `RiotClient.account_by_riot_id`), Ausgabe `pro_accounts.json` `[{puuid, platform, proName, proTeam, role}]`. Dazu ein pytest mit Fake-Antworten.
3. **`3-build-app`** – `Scripts/build-app.sh` für `macOS-App/` (SwiftPM, nur Command Line Tools, kein Xcode): `swift build -c release`, `.app`-Bundle bauen, Info.plist (Bundle-ID `de.riftsight.app`, `NSScreenCaptureUsageDescription` auf Deutsch, LSMinimumSystemVersion 14.0), `Resources/SampleData` nach `Contents/Resources/SampleData` kopieren, ad-hoc `codesign`.
4. **`4-workflow-r2`** – optionaler Upload-Schritt für `.github/workflows/daily-pipeline.yml` nach Cloudflare R2 (nur als Snippet in NOTIZ.md, Secrets `R2_*`).
