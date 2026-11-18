# Recherche-Auftrag für Gemini: Datenpipeline für „Riftsight“ (League of Legends, macOS)

> **Kopiere dieses gesamte Dokument als Prompt in Gemini (Deep Research).**
> Stand: 18.11.2026 · aktueller Patch laut Data Dragon: **16.23**

---

## 0. Deine Rolle & das Ziel

Du bist Data Engineer und League-of-Legends-Statistikexperte. Recherchiere **gründlich und mit Quellen**,
wie wir die unten definierten JSON-Dateien **ausschließlich über die offizielle Riot Games API** (plus die
freien CDNs CommunityDragon, Data Dragon und Meraki) erzeugen. Ich brauche **konkrete Algorithmen,
exakte Endpunkte, Feldpfade und Mengengerüste**, keine allgemeinen Tipps.

**Kontext:**
- *Riftsight* ist eine native macOS-Companion-App (Swift). Sie darf **keinen Riot-API-Key enthalten** (Riot verbietet Keys in Client-Binaries).
- Deshalb läuft ein **Python-Aggregator (GitHub Actions, täglicher Cron)**, der die Riot API abfragt und **statische JSON-Dateien** erzeugt. Die App lädt diese Dateien von einer festen URL (z. B. GitHub Pages) und cacht sie lokal.
- **Harte Regel: kein Web-Scraping** (kein op.gg, u.gg, lolalytics, Mobalytics usw.), auch nicht als Fallback. Nur: Riot API, CommunityDragon, Data Dragon, Meraki Analytics, ggf. Leaguepedia-API (nur für Pro-Account-Listen, siehe §3.6).
- Champion-, Item-, Runen- und Spell-**Namen** kommen in der App aus CommunityDragon `de_de`. Die JSON-Dateien enthalten **nur IDs und Zahlen**.

---

## 1. Was bereits geklärt ist (nicht neu recherchieren)

| Quelle | URL | Nutzen in der App |
|---|---|---|
| CommunityDragon `de_de` | `https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/de_de/v1/` | `champion-summary.json`, `champions/{id}.json` (Spells mit `cooldownCoefficients`, `tacticalInfo.damageType`, `playstyleInfo.crowdControl`), `items.json` (`from`, `to`, `price`, `priceTotal`, `categories`), `perks.json`, `perkstyles.json`, `summoner-spells.json`, `skins.json`, `skinlines.json` |
| CommunityDragon Arena | `https://raw.communitydragon.org/latest/cdragon/arena/de_de.json` | Augments mit `id`, `apiName`, `name`, `rarity` (0/1/2…) |
| Data Dragon | `https://ddragon.leagueoflegends.com/api/versions.json`, `/cdn/{ver}/data/de_DE/champion.json` | Patch-Stand, Base-Stats (`attackrange` usw.), Tags |
| Meraki | `https://cdn.merakianalytics.com/riot/lol/resources/latest/en-US/championrates.json` | `data[championId][TOP\|JUNGLE\|MIDDLE\|BOTTOM\|UTILITY].playRate` für die Lane-Erkennung |
| LCU / Live Client API | lokal | Match-History, Mastery, Rang der Mitspieler, Live-Daten. **Nicht Teil der Pipeline.** |

---

## 2. Die Ziel-Schemas (verbindlich, so liest die App sie ein)

Alle Dateien haben denselben `meta`-Block:

```json
"meta": {
  "schemaVersion": 1,
  "patch": "16.23",
  "generatedAt": "2026-11-18T04:00:00Z",
  "sample": false,
  "platforms": ["EUW1", "KR", "NA1"],
  "rankFloor": "EMERALD",
  "matchesAnalyzed": 184233
}
```

Konventionen: Winrates/Pickrates als Anteil `0.0–1.0` (nicht Prozent). Rollen immer als
`TOP | JUNGLE | MIDDLE | BOTTOM | UTILITY` (wie Match-V5 `teamPosition`). Champion-IDs als String-Keys.

### 2.1 `counterpicks.json`: Wer kontert Champion X in Rolle Y?

```json
{
  "meta": { "...": "..." },
  "champions": {
    "103": {
      "MIDDLE": {
        "games": 41233,
        "winrate": 0.512,
        "counters": [
          { "championId": 61, "games": 1830, "winrate": 0.538, "delta": 0.026,
            "goldDiff15": 212, "csDiff15": 4.1, "laneKillRate": 0.31 }
        ]
      }
    }
  }
}
```

`counters` = Champions, die **gegen** Champion 103 auf derselben Lane gewinnen, absteigend nach `delta` sortiert, Top 15.
In der App: Klick auf einen Gegner im Champ Select → Top 5 Counter, abgeglichen mit der eigenen Mastery.

### 2.2 `matchup_runes.json`: Builds & Runen pro Champion/Rolle, optional pro Gegner

```json
{
  "meta": { "...": "..." },
  "builds": {
    "103": {
      "MIDDLE": {
        "default": "<BuildBlock>",
        "vs": { "61": "<BuildBlock, nur Felder mit genug Daten>" }
      }
    }
  }
}
```

`BuildBlock`:

```json
{
  "games": 37897, "winrate": 0.49,
  "runes": { "primaryStyleId": 8100, "subStyleId": 8000,
             "perkIds": [8112, 8139, 8138, 8135, 9111, 8014, 5008, 5008, 5011],
             "games": 21000, "winrate": 0.52 },
  "summonerSpells": { "ids": [4, 14], "games": 30000, "winrate": 0.51 },
  "skillOrder": { "maxOrder": ["Q", "W", "E"],
                  "sequence": ["Q","W","E","Q","Q","R","Q","W","Q","W","R","W","W","E","E","R","E","E"],
                  "games": 9000, "winrate": 0.52 },
  "startingItems": { "itemIds": [1056, 2003, 2003], "games": 25000, "winrate": 0.50 },
  "coreBuild": { "itemIds": [6655, 3020, 4645], "games": 8000, "winrate": 0.54 },
  "archetypes": [ { "name": "Crit", "itemIds": [3031, 3046, 3036], "games": 6204, "winrate": 0.51 } ],
  "boots": [ { "itemId": 3020, "pickrate": 0.81, "winrate": 0.51 } ],
  "completedItems": [ { "itemId": 3089, "pickrate": 0.71, "winrate": 0.53 } ],
  "situational": [ { "itemId": 3157, "pickrate": 0.38, "winrate": 0.55 } ]
}
```

`perkIds` = 4 Primär-Runen (inkl. Keystone) + 2 Sekundär-Runen + 3 Stat-Shards (offense, flex, defense), genau 9 IDs in dieser Reihenfolge (so will es `POST /lol-perks/v1/pages`).

### 2.3 `item_stats.json`: globale Item-Statistik + Kontext-Deltas für situative Items

```json
{
  "meta": { "...": "..." },
  "items": {
    "3033": { "games": 52000, "pickrate": 0.09, "winrate": 0.51, "avgCompletionMinute": 19.6,
              "contextDeltas": { "vsHeavyHealing": 0.031, "vsShields": 0.004, "vsHeavyAP": -0.002,
                                 "vsHeavyAD": 0.001, "vsTanks": 0.006, "vsFedCrit": 0.0 } }
  }
}
```

`contextDeltas` = Winrate des Items **wenn** die Gegner-Comp das Merkmal hat, minus Winrate ohne das Merkmal (gleicher Champion-Pool). Das treibt in der App die Gruppen *Anti-Heal / Anti-Shield*, *Defensive*, *Tank-Shred*.

### 2.4 `tierlist.json`

```json
{
  "meta": { "...": "..." },
  "brackets": [
    { "rank": "EMERALD_PLUS", "platform": "ALL",
      "modes": {
        "ranked": [ { "championId": 103, "role": "MIDDLE", "laneShare": 0.978, "rank": 1, "tier": "S+",
                      "score": 71.2, "winrate": 0.526, "winrateDelta": 0.008, "pickrate": 0.112,
                      "banrate": 0.07, "games": 412884,
                      "powerCurve": { "early": 0.49, "mid": 0.53, "late": 0.52 } } ],
        "aram":  [ { "championId": 103, "role": "ALL", "...": "..." } ],
        "arena": [ { "championId": 103, "role": "ALL", "avgPlacement": 3.9, "top4Rate": 0.56, "...": "..." } ],
        "duo":   [ { "championId": 222, "role": "BOTTOM", "partnerChampionId": 412, "partnerRole": "UTILITY",
                     "games": 9120, "winrate": 0.537, "tier": "S" } ]
      } }
  ]
}
```

- `tier` ∈ `S+ | S | A | B | C | D`
- `winrateDelta` = Veränderung zum Vorpatch
- `powerCurve` = Winrate nach Spiellänge (Buckets z. B. < 25 / 25–32 / > 32 Min.). Daraus berechnet die App das 6-Achsen-Draft-Radar (Early/Mid/Late).

### 2.5 `aram_augments.json` (ARAM Mayhem + Arena)

```json
{
  "meta": { "...": "..." },
  "modes": {
    "ARAM_MAYHEM": {
      "augments": [ { "id": 93, "rarity": "silver", "tier": "A", "winrate": 0.52, "pickrate": 0.04, "games": 8100 } ],
      "championAugments": { "103": [ { "id": 93, "tier": "S", "winrate": 0.57, "games": 410 } ] },
      "builds": { "103": "<BuildBlock ohne skillOrder>" }
    },
    "CHERRY": { "augments": [], "championAugments": {}, "builds": {} }
  }
}
```

`rarity` ∈ `silver | gold | prismatic`.

### 2.6 `pro_spectate.json`: laufende High-Elo-/Pro-Partien

```json
{
  "meta": { "...": "..." },
  "games": [
    { "gameId": 7012345678, "platformId": "KR", "gameStartTime": 1763440000000, "queueId": 420,
      "averageTier": "CHALLENGER", "averageLp": 1412, "knownPlayers": 10,
      "participants": [
        { "teamId": 100, "championId": 92, "role": "TOP", "puuid": "…", "riotId": "Name#TAG",
          "proName": "…", "proTeam": "…", "tier": "CHALLENGER", "lp": 1500, "isKnown": true }
      ] }
  ]
}
```

### 2.7 `leaderboard.json`

```json
{
  "meta": { "...": "..." },
  "platforms": {
    "EUW1": [ { "rank": 1, "puuid": "…", "riotId": "Name#TAG", "tier": "CHALLENGER", "lp": 2104,
                "wins": 412, "losses": 330, "topChampionIds": [103, 61, 4] } ]
  }
}
```

---

## 3. Recherche-Fragen (bitte alle beantworten)

### 3.1 Datenerhebung & Rate-Limits
1. Beste Seed-Strategie für Emerald+ Ranked-Solo (Queue 420): `League-V4` (`/lol/league/v4/entries/...`, `challengerleagues`, `grandmasterleagues`, `masterleagues`) → PUUIDs → `Match-V5` `/lol/match/v5/matches/by-puuid/{puuid}/ids?queue=420&startTime=…`. Gibt League-V4 inzwischen direkt `puuid` zurück? Welche Regional-Routings (`europe`, `americas`, `asia`, `sea`) gehören zu welchen Plattformen?
2. **Rate-Limit-Budget als Tabelle:** Development Key vs. Personal Key vs. Production Key (aktuelle Limits pro Sekunde/2 Min., Method-Limits von Match-V5 und Timeline). Wie viele Matches **plus** Timelines schafft ein täglicher GitHub-Actions-Lauf (max. 6 h Jobdauer) realistisch?
3. Welcher Key-Typ ist für eine **öffentlich verteilte** App mit eigenem Backend nötig? Ablauf der Registrierung im Riot Developer Portal, Review-Dauer, Auflagen.
4. Wie erkennt man zuverlässig den Patch eines Matches (`info.gameVersion` → „16.23“) und wie viele Tage nach Patch-Release reicht die Stichprobe? Empfehlung zum Blending mit dem Vorpatch.
5. Wie zuverlässig ist `teamPosition` vs. `individualPosition` für die Rollen-Zuordnung? Was tun bei Swaps?

### 3.2 `counterpicks.json`
6. Die beste Definition von `delta`: rohe Matchup-Winrate − 50 %, **oder** normalisiert (Matchup-WR minus erwartete WR aus den Grundwinrates beider Champions)? Wie machen es seriöse Statistikseiten methodisch (nur Methodik zitieren, nicht scrapen)?
7. Mindest-Stichprobe pro Matchup, Bayes'sche Glättung (z. B. Beta-Prior) bzw. Wilson-Intervall, konkrete Formel + Zahlen.
8. Wie berechnet man `goldDiff15` / `csDiff15` (Timeline `participantFrames` bei Frame 15) effizient? Lohnt sich dafür der Timeline-Request, oder Sampling?

### 3.3 `matchup_runes.json`
9. Runen-Extraktion aus Match-V5: `perks.styles[].selections[].perk`, `perks.statPerks.{offense,flex,defense}`. Besser die **häufigste komplette Seite** oder **pro Slot** die beste Rune? Wie mit Rune-Reworks während der Season umgehen?
10. Skill-Order: nur über Timeline-Events `SKILL_LEVEL_UP` (`levelUpType: NORMAL`)? Kosten & Sampling-Strategie.
11. Items: Timeline-Events `ITEM_PURCHASED`, `ITEM_UNDO`, `ITEM_SOLD`, `ITEM_DESTROYED`. Algorithmus für **Starting Items** (Käufe vor ~1:00), **Core Build** (erste 3 fertige Legendaries inkl. Reihenfolge) und **Boots**. Wie definiert man „legendäres Item“ robust über CommunityDragon `items.json` (`priceTotal`, `to: []`, `categories`, Ausschluss von Ornn-/Champion-spezifischen Items)?
12. **Archetypen** (`Crit`, `On-Hit`, `Lethality`, `AP`, `Tank`, `Bruiser` …): regelbasiert über CDragon-`categories` oder Clustering (k-means/Jaccard)? Wie benennt man Cluster automatisch?
13. Ab wie vielen Spielen lohnt ein eigener `vs`-Block pro Gegner?

### 3.4 `tierlist.json` & `item_stats.json`
14. Formel für `score` und Tier-Grenzen (Perzentile oder z-Score über Winrate, Pickrate, Banrate, mit Shrinkage). Welche Formel ist statistisch am saubersten?
15. `powerCurve`: sinnvolle Spiellängen-Buckets, nötige Stichprobe.
16. `duo`: Synergie von ADC+Support. Wie berechnet man „Synergie“ statt nur Paar-Winrate (z. B. Paar-WR minus erwartete WR aus Einzel-WRs)?
17. `contextDeltas`: wie definiert man „Heavy Healing“, „Shields“, „Heavy AP/AD“, „Tanks“, „Fed Crit Carry“ datengetrieben aus Match-V5 (z. B. `totalHeal`, `totalDamageShieldedOnTeammates`, `magicDamageDealtToChampions`)? Sauberes Vorgehen gegen Confounding (z. B. Anti-Heal wird eher gekauft, wenn man ohnehin vorne liegt)?

### 3.5 `aram_augments.json`
18. Queue-IDs verifizieren: ARAM (450), **ARAM Mayhem** (2400?), Arena/CHERRY (1700/1710?).
19. Enthält Match-V5 für ARAM Mayhem die Felder `playerAugment1…6` wie für Arena? Falls nicht: welche Alternative gibt es?
20. Mapping von CDragon `arena/de_de.json` `rarity` (0/1/2/…) → silver/gold/prismatic. Gibt es ein eigenes Mayhem-Augment-JSON in CommunityDragon?
21. Arena-Metrik: Winrate oder lieber `avgPlacement` / Top-4-Rate je Augment und Champion?

### 3.6 `pro_spectate.json` & `leaderboard.json`
22. Spectator-V5: `/lol/spectator/v5/active-games/by-summoner/{puuid}`. Polling-Kosten für ~500 bekannte Accounts, Aktualität.
23. **GitHub Actions taugt nur bedingt** (Cron min. 5 Min., oft verzögert). Für Live-Spectate besser ein Cloudflare Worker mit Cron Trigger + KV/R2? Bitte vergleichen (Kosten, Limits, Secrets-Handling).
24. Woher kommt eine **legale, gepflegte Liste von Pro-/Streamer-Accounts** (PUUID/Riot ID ↔ Spielername ↔ Team)? Z. B. Leaguepedia-Cargo-API (welche Tabelle/Felder, Lizenz CC BY-SA, Attribution).
25. Wie startet der **macOS**-League-Client eine Spectate-Partie per LCU? Endpunkt `POST /lol-spectator/v1/spectate/launch`: exakter Payload (`puuid`, `dropInSpectateGameId`, `gameQueueType`, `allowObserveMode`) und Einschränkungen (gleiche Region? Delay?).
26. `leaderboard.json`: `League-V4`-Apex-Ligen + `Account-V1` (`/riot/account/v1/accounts/by-puuid/{puuid}`) für Riot IDs. Kostenbudget pro Region.

### 3.7 Hosting, Policy, Betrieb
27. Hosting der JSONs: GitHub Pages vs. `raw.githubusercontent.com` vs. Release-Assets vs. Cloudflare R2. Caching-Header, ETag/`If-None-Match`, gzip, Dateigrößen-Schätzung pro Datei.
28. **Riot Developer Policies**: Was ist für eine öffentliche Companion-App erlaubt bzw. verboten (z. B. keine De-Anonymisierung im Champ Select, Regeln zu Gegner-Cooldown-Timern, Siegwahrscheinlichkeit im Spiel, Gegner-Item-Alerts, Overlays)? Bitte mit Link zur aktuellen Policy-Seite und Datum.
29. Pflicht-Disclaimer („Riftsight isn't endorsed by Riot Games …“) und Nutzungsbedingungen für CommunityDragon-/Meraki-Daten.
30. Fehlerbehandlung im Cron-Job: Teil-Ausfälle (429/5xx), Idempotenz, Resume nach Abbruch, Validierung gegen das Schema vor dem Publish.

---

## 4. Was ich von dir zurück will (Format)

1. **Pro JSON-Datei ein Abschnitt** mit:
   - exakten Endpunkten + Feldpfaden (z. B. `info.participants[].perks.styles[0].selections[0].perk`)
   - Algorithmus als **Python-Pseudocode**
   - Mindest-Stichproben und Glättungsformeln mit konkreten Zahlen
   - einem **realistischen Beispiel-Eintrag**, der exakt dem Schema aus §2 entspricht (echte IDs)
2. Eine **Rate-Limit-Budget-Tabelle** (Requests pro Lauf, Dauer, benötigter Key-Typ).
3. Einen **Modul-Vorschlag** für `data-pipeline/` (z. B. `riot_client.py`, `collect.py`, `aggregate_counters.py`, `aggregate_builds.py`, `tierlist.py`, `augments.py`, `spectate.py`, `publish.py`) + GitHub-Actions-Workflow-Skizze.
4. **Schema-Änderungsvorschläge** nur, wenn ein Feld nicht sauber berechenbar ist, mit Begründung.
5. **Quellen mit Links** (bevorzugt offizielle Riot-Docs, Riot-Dev-Relations-Posts, Developer-Portal, GitHub-Issues von `RiotGames/developer-relations`). Markiere alles Unverifizierte ausdrücklich mit **„UNSICHER“**.
6. Am Ende eine **Top-5-Risikoliste** (z. B. Key-Freigabe, Datenmenge, Policy) mit Gegenmaßnahmen.

**Nicht gewünscht:** Scraping-Lösungen, Overwolf, Windows-spezifische Tools, Memory-Reading, Marketing-Vergleiche.
