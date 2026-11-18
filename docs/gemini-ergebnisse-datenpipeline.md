Datenpipeline-Spezifikation für „Riftsight“ (LoL / macOS)

1. Datenerhebung, Rate-Limits & Routing (§3.1)

1.1 Seed- & Snowball-Strategie (Emerald+ Ranked Solo, Queue 420)

⚬ Apex-Seeds (League-V4):
  ⚬ GET https://{platform}[.api.riotgames.com/lol/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5](https://.api.riotgames.com/lol/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5)
  ⚬ GET https://{platform}[.api.riotgames.com/lol/league/v4/grandmasterleagues/by-queue/RANKED_SOLO_5x5](https://.api.riotgames.com/lol/league/v4/grandmasterleagues/by-queue/RANKED_SOLO_5x5)
  ⚬ GET https://{platform}[.api.riotgames.com/lol/league/v4/masterleagues/by-queue/RANKED_SOLO_5x5](https://.api.riotgames.com/lol/league/v4/masterleagues/by-queue/RANKED_SOLO_5x5)
⚬ Emerald- & Diamond-Seeds (League-V4):
  ⚬ GET https://{platform}[.api.riotgames.com/lol/league/v4/entries/RANKED_SOLO_5x5/](https://.api.riotgames.com/lol/league/v4/entries/RANKED_SOLO_5x5/){tier}/{division}?page={page} für tier ∈ ["DIAMOND", "EMERALD"], division ∈ ["I", "II", "III", "IV"], page ∈ 1..5.
⚬ Direkte puuid-Verfügbarkeit: Seit Riots PUUID-Migration liefern sowohl LeagueListDTO (entries[] der Apex-Ligen) als auch LeagueEntryDTO (/entries/...) das Feld puuid direkt aus. Ein vorgeschalteter Summoner-V4-Lookup entfällt komplett (UNSICHER, ob das veraltete Feld summonerId Ende 2026 vollständig aus den DTOs entfernt wurde; puuid ist der primäre Identifier).
⚬ Stratifiziertes Snowball-Sampling:
  1. Ziehe für Seed-PUUIDs die Match-IDs seit Patch-Release (startTime = Unix-Timestamp des Patch-Releases):
     GET https://{regional}[.api.riotgames.com/lol/match/v5/matches/by-puuid/](https://.api.riotgames.com/lol/match/v5/matches/by-puuid/){puuid}/ids?queue=420&startTime={patch_start_ts}&count=100
  2. Extrahiere aus jedem geladenen Match die 10 Teilnehmer-PUUIDs (metadata.participants[]) und reihe sie in die Seed-Queue ein.
  3. Anti-High-Elo-Bias: Da Snowball-Sampling aus Apex-Seeds überproportional viele Master+-Lobbys zieht, werden die PUUID-Queues in drei Buckets (EMERALD, DIAMOND, APEX) getrennt und im Verhältnis 60 % Emerald / 30 % Diamond / 10 % Apex abgearbeitet (entspricht der realen Emerald+-Populationsverteilung).

1.2 Plattform- zu Regional-Routing (Match-V5, Account-V1)

Regional-Cluster ({regional})	Zugehörige Plattform-IDs ({platform})
europe	EUW1, EUN1, TR1, RU, ME1
americas	NA1, BR1, LA1, LA2
asia	KR, JP1
sea	OC1, SG2, TW2, VN2 (PH2/TH2 wurden teils in SG2 konsolidiert – UNSICHER)

1.3 Patch-Erkennung, Stichprobentiefe & Vorpatch-Blending

⚬ Patch-Extraktion: patch = ".".join(match["info"]["gameVersion"].split(".")[:2]) (z. B. "16.23.634.1234" → "16.23").
⚬ Remake-Filter: Alle Matches mit info.gameDuration < 300 oder info.participants[0].gameEndedInEarlySurrender == True verwerfen.
⚬ Rollen-Zuordnung (teamPosition vs. individualPosition):
  ⚬ Immer participant["teamPosition"] verwenden (von Riot nach Minute 1–3 auf Lane-Swaps bereinigt, garantiert exakt 1× TOP, JUNGLE, MIDDLE, BOTTOM, UTILITY pro Team).
  ⚬ Fallback auf individualPosition nur, wenn teamPosition leer ("") oder "Invalid" ist.
  ⚬ Champions mit einem Rollenanteil (laneShare) von < 0.015 (1,5 %) im aktuellen Patch werden als Lane-Swap-Rauschen aus Tierlist und Matchups ausgeblendet.
⚬ Vorpatch-Blending (Tag 0–3 nach Patch-Release):
  ⚬ Ab ~80.000 Matches (ca. 36–48 h nach Patch-Release) ist die Tierlist stabil; ab ~160.000 Matches (Tag 3–4) sind auch spezifische Matchups belastbar.
  ⚬ Liegt die Stichprobe N_{\text{curr}} einer Entität unter dem Zielwert N_{\text{target}} (1.000 für Tierlist/Default-Builds, 300 für Matchups), wird der Vorpatch (16.22) als Prior eingemischt:
    
    $$w_{\text{curr}} = \min\left(1.0,\ \frac{N_{\text{curr}}}{N_{\text{target}}}\right), \quad p_{\text{blend}} = w_{\text{curr}} \cdot p_{\text{curr}} + (1 - w_{\text{curr}}) \cdot p_{\text{prev}}$$

1.4 Rate-Limit-Budget-Tabelle & Production-Key-Prozess

Key-Typ	App-Rate-Limit	Method-Limit (Match-V5 & Timeline)	Max. Requests / Stunde	Realistische Ausbeute (6 h GitHub Actions)	Eignung
Development Key	20 Req / 1s & 100 Req / 2m	2000 Req / 10s pro Cluster	3.000 Req/h	~8.500 Matches + 8.500 Timelines	Nur lokales Prototyping (läuft nach 24 h ab!)
Personal Key	20 Req / 1s & 100 Req / 2m	2000 Req / 10s pro Cluster	3.000 Req/h	~8.500 Matches + 8.500 Timelines	Nur private Dev-Tests (sample: true), verboten für öffentliche Apps
Production Key (Standard-Tier)	500 Req / 10s & 30.000 Req / 10m (UNSICHER exaktes 2026-Initial-Tier)	2000 Req / 10s pro Cluster (europe, asia, americas)	180.000 Req/h	~220.000 Matches + ~160.000 Timelines in ca. 2,2 Stunden	Zwingend erforderlich für Riftsight

⚬ Beantragung des Production Keys:
  1. App im Riot Developer Portal (developer.riotgames.com) anlegen und Architektur offenlegen (macOS-App ohne eingebetteten Key + GitHub-Actions/Cloudflare-Aggregator für aggregierte JSONs).
  2. Verifizierungs-Datei riot.txt auf der App-Domain/GitHub-Pages-URL hinterlegen.
  3. Funktionsfähigen Prototyp (mit Dev-Key-Sample-Daten) zur Prüfung einreichen.
  4. Review-Dauer: Typischerweise 2 bis 6 Wochen (UNSICHER über aktuelle Bearbeitungszeit Ende 2026).

2. Spezifikation der 7 Ziel-JSON-Dateien (§3.2 – §3.6)

2.1 counterpicks.json

Exakte Endpunkte & Feldpfade

⚬ GET /lol/match/v5/matches/{matchId}:
  ⚬ info.queueId (== 420), info.gameDuration (>= 300), info.gameVersion
  ⚬ info.participants[]: participantId (1..10), teamId (100 / 200), championId, teamPosition, win
⚬ GET /lol/match/v5/matches/{matchId}/timeline:
  ⚬ info.frames[15].participantFrames[str(participantId)]: totalGold, minionsKilled, jungleMinionsKilled
  ⚬ info.frames[1..15].events[] mit type == "CHAMPION_KILL": killerId, victimId

Methodik, Glättung & Stichproben

⚬ Normalisiertes Matchup-Delta (Log-Odds / Bradley-Terry-Modell):
  Rohes Delta (WR_{A \text{ vs } B} - 0.50) bevorzugt fälschlich generell überstarke Champions. Stattdessen berechnen wir die erwartete Winrate \mu_0 = E[WR_{A \text{ vs } B}] aus den Basis-Winrates WR_A (Counter) und WR_B (Ziel-Champion) in derselben Rolle:
  
  $$\text{logit}(p) = \ln\left(\frac{p}{1 - p}\right), \quad \mu_0 = \sigma\Big(\text{logit}(WR_A) - \text{logit}(WR_B)\Big), \quad \sigma(x) = \frac{1}{1 + e^{-x}}$$
⚬ Empirical-Bayes-Glättung: Mit Prior-Gewicht m = 50 Pseudo-Spielen und Mindest-Stichprobe N_{\min} = 50:
  
  $$\widehat{WR}_{A \text{ vs } B} = \frac{W_{A \text{ vs } B} + 50 \cdot \mu_0}{N_{A \text{ vs } B} + 50}, \quad \text{delta} = \widehat{WR}_{A \text{ vs } B} - \mu_0$$
⚬ Timeline-Effizienz (goldDiff15, csDiff15, laneKillRate): Da Timelines auch für Builds/Items benötigt werden, reichen bei knappen Rate-Limits 50 % Timeline-Sampling (nur Matches mit gameDuration >= 900). laneKillRate ist der Anteil der Spiele, in denen Counter A den Lane-Gegner B bis Minute 15 mindestens einmal solo/assistiert tötet (killerId == pid_A and victimId == pid_B).

Python-Pseudocode

import math
from collections import defaultdict

def logit(p: float) -> float:
    p = min(max(p, 1e-4), 1 - 1e-4)
    return math.log(p / (1.0 - p))

def sigmoid(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-x))

def extract_lane_timeline_metrics(timeline: dict, pid_a: int, pid_b: int) -> tuple[float, float, int]:
    frames = timeline["info"]["frames"]
    if len(frames) <= 15:
        return None
    pf = frames[15]["participantFrames"]
    pa, pb = pf[str(pid_a)], pf[str(pid_b)]
    gold_diff = pa["totalGold"] - pb["totalGold"]
    cs_a = pa["minionsKilled"] + pa["jungleMinionsKilled"]
    cs_b = pb["minionsKilled"] + pb["jungleMinionsKilled"]
    cs_diff = cs_a - cs_b
    killed_opponent = 0
    for f in frames[1:16]:
        for ev in f.get("events", []):
            if ev.get("type") == "CHAMPION_KILL" and ev.get("killerId") == pid_a and ev.get("victimId") == pid_b:
                killed_opponent = 1
                break
        if killed_opponent:
            break
    return gold_diff, cs_diff, killed_opponent

def build_counterpicks(base_wr: dict, matchup_stats: dict, min_games: int = 50, prior_m: int = 50) -> dict:
    # matchup_stats[(champ_b, role, champ_a)] = {"games": int, "wins_a": int, "gd15_sum": float, "csd15_sum": float, "lk_sum": int, "tl_games": int}
    result = defaultdict(lambda: defaultdict(dict))
    for (champ_b, role), b_info in base_wr.items():
        if b_info["games"] < 200:
            continue
        wr_b = b_info["winrate"]
        counters = []
        for (cb, r, champ_a), m in matchup_stats.items():
            if cb != champ_b or r != role or m["games"] < min_games:
                continue
            wr_a = base_wr[(champ_a, role)]["winrate"]
            expected_wr = sigmoid(logit(wr_a) - logit(wr_b))
            smoothed_wr = (m["wins_a"] + prior_m * expected_wr) / (m["games"] + prior_m)
            delta = smoothed_wr - expected_wr
            tl_n = max(m["tl_games"], 1)
            counters.append({
                "championId": champ_a,
                "games": m["games"],
                "winrate": round(smoothed_wr, 4),
                "delta": round(delta, 4),
                "goldDiff15": round(m["gd15_sum"] / tl_n),
                "csDiff15": round(m["csd15_sum"] / tl_n, 1),
                "laneKillRate": round(m["lk_sum"] / tl_n, 3),
            })
        counters.sort(key=lambda x: x["delta"], reverse=True)
        result[str(champ_b)][role] = {
            "games": b_info["games"],
            "winrate": round(wr_b, 4),
            "counters": counters[:15],
        }
    return result


Beispiel-Eintrag (counterpicks.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T04:00:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "EMERALD",
    "matchesAnalyzed": 184233
  },
  "champions": {
    "103": {
      "MIDDLE": {
        "games": 41233,
        "winrate": 0.512,
        "counters": [
          {
            "championId": 61,
            "games": 1830,
            "winrate": 0.538,
            "delta": 0.026,
            "goldDiff15": 212,
            "csDiff15": 4.1,
            "laneKillRate": 0.31
          },
          {
            "championId": 134,
            "games": 1640,
            "winrate": 0.531,
            "delta": 0.021,
            "goldDiff15": 185,
            "csDiff15": 3.4,
            "laneKillRate": 0.28
          }
        ]
      }
    }
  }
}


2.2 matchup_runes.json

Exakte Endpunkte & Feldpfade

⚬ GET /lol/match/v5/matches/{matchId}:
  ⚬ info.participants[].perks.styles[0].style (primaryStyleId), styles[0].selections[0..3].perk
  ⚬ info.participants[].perks.styles[1].style (subStyleId), styles[1].selections[0..1].perk
  ⚬ info.participants[].perks.statPerks.{offense, flex, defense}
  ⚬ info.participants[].summoner1Id, summoner2Id
⚬ GET /lol/match/v5/matches/{matchId}/timeline:
  ⚬ SKILL_LEVEL_UP: event.type == "SKILL_LEVEL_UP", event.levelUpType == "NORMAL", event.skillSlot (1="Q", 2="W", 3="E", 4="R")
  ⚬ Items: ITEM_PURCHASED (itemId, timestamp), ITEM_UNDO (beforeId, afterId), ITEM_SOLD (itemId), ITEM_DESTROYED (itemId)

Algorithmen & Schwellenwerte

⚬ Runen (Komplette Seite statt Pro-Slot): Runen besitzen interne Synergien und Slot-Restriktionen (Sekundärbaum erlaubt maximal 1 Rune pro Reihe). Daher wird nach dem kanonischen Tuple (primaryStyleId, subStyleId, 4_primary_perks, sorted(2_sub_perks)) gruppiert (Auswahl nach Wilson-Lower-Bound bei mindestens 10 % Pickrate) und dazu das häufigste Shard-Triple [offense, flex, defense] bestimmt. Unbekannte Perk-IDs (nach Mid-Season-Rune-Reworks) werden gegen CDragon perks.json gefiltert.
⚬ Skill-Order: Nur SKILL_LEVEL_UP mit levelUpType == "NORMAL" (filtert Kha'Zix/Viktor/Kai'Sa-Evolutionen und Level-1-Formwechsel heraus). maxOrder ergibt sich aus der Reihenfolge, in der Q, W, E jeweils Rang 5 erreichen. 200 Timelines pro Champion/Rolle genügen.
⚬ Starting Items, Core Build & Boots:
  ⚬ Starting Items: ITEM_PURCHASED mit timestamp <= 65000, bereinigt um ITEM_UNDO (Stack-Pop) und Trinkets (3340, 3363, 3364).
  ⚬ Legendäres Item (CDragon items.json): inStore == True (schließt Ornn-Masterwork-Items aus), len(to) == 0, priceTotal >= 2000, "Boots" not in categories, requiredChampion == "".
  ⚬ Core Build: Chronologisch die ersten 3 fertiggestellten Legendaries als geordnetes Triple.
  ⚬ Boots: Erstes aufgewertetes Boot-Item ("Boots" in categories und priceTotal >= 900).
⚬ Archetypen (Crit, On-Hit, Lethality, AP, Tank, Bruiser, Enchanter): Regelbasierte Zuordnung der 3-Item-Cores über CDragon-Item-Kategorien (CriticalStrike, OnHit, ArmorPenetration, SpellDamage, Armor/SpellBlock/Health, AttackDamage+Health, HealAndShieldPower). Es werden nur sekundäre Archetypen mit \ge 12\ \% Pickrate ausgegeben.
⚬ Schwellenwerte für vs[enemyId]:
  ⚬ N \ge 150 Spiele: runes, summonerSpells, startingItems, boots werden in vs[enemyId] ausgegeben.
  ⚬ N \ge 400 Spiele: zusätzlich coreBuild (darunter wird coreBuild weggelassen, sodass die App auf default.coreBuild zurückfällt). skillOrder wird im vs-Block weggelassen, wenn N_{\text{timelines}} < 150.

Python-Pseudocode

from collections import Counter

SLOT_MAP = {1: "Q", 2: "W", 3: "E", 4: "R"}
TRINKETS = {3340, 3363, 3364, 3513}

def is_legendary(item_id: int, cdragon_items: dict) -> bool:
    meta = cdragon_items.get(item_id)
    if not meta:
        return False
    return (
        meta.get("inStore", False) is True
        and len(meta.get("to", [])) == 0
        and meta.get("priceTotal", 0) >= 2000
        and "Boots" not in meta.get("categories", [])
        and not meta.get("requiredChampion")
    )

def extract_timeline_build_and_skills(timeline: dict, pid: int, cdragon_items: dict) -> dict:
    skills = []
    purchase_stack = []  # (item_id, timestamp)
    for frame in timeline["info"]["frames"]:
        for ev in frame.get("events", []):
            if ev.get("participantId") != pid:
                continue
            etype = ev.get("type")
            if etype == "SKILL_LEVEL_UP" and ev.get("levelUpType") == "NORMAL":
                skills.append(SLOT_MAP[ev["skillSlot"]])
            elif etype == "ITEM_PURCHASED":
                purchase_stack.append((ev["itemId"], ev["timestamp"]))
            elif etype == "ITEM_UNDO":
                # Entfernt den zuletzt gekauften Gegenstand (beforeId)
                target = ev.get("beforeId")
                for idx in range(len(purchase_stack) - 1, -1, -1):
                    if purchase_stack[idx][0] == target:
                        purchase_stack.pop(idx)
                        break

    starters = sorted([iid for iid, ts in purchase_stack if ts <= 65000 and iid not in TRINKETS])
    legendaries = []
    boots = None
    for iid, _ in purchase_stack:
        meta = cdragon_items.get(iid, {})
        if "Boots" in meta.get("categories", []) and meta.get("priceTotal", 0) >= 900 and boots is None:
            boots = iid
        elif is_legendary(iid, cdragon_items) and iid not in legendaries:
            legendaries.append(iid)

    # Max-Order aus Skill-Sequenz
    counts = Counter()
    max_order = []
    for s in skills:
        if s in ("Q", "W", "E"):
            counts[s] += 1
            if counts[s] == 5 and s not in max_order:
                max_order.append(s)

    return {
        "starters": tuple(starters),
        "core": tuple(legendaries[:3]) if len(legendaries) >= 3 else None,
        "all_legendaries": legendaries,
        "boots": boots,
        "skills": tuple(skills[:18]) if len(skills) >= 15 and len(max_order) == 3 else None,
        "max_order": max_order,
    }


Beispiel-Eintrag (matchup_runes.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T04:00:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "EMERALD",
    "matchesAnalyzed": 184233
  },
  "builds": {
    "103": {
      "MIDDLE": {
        "default": {
          "games": 37897,
          "winrate": 0.512,
          "runes": {
            "primaryStyleId": 8100,
            "subStyleId": 8000,
            "perkIds": [8112, 8139, 8140, 8135, 8009, 8014, 5008, 5008, 5011],
            "games": 21410,
            "winrate": 0.521
          },
          "summonerSpells": {
            "ids": [4, 14],
            "games": 28900,
            "winrate": 0.515
          },
          "skillOrder": {
            "maxOrder": ["Q", "W", "E"],
            "sequence": ["Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"],
            "games": 14200,
            "winrate": 0.524
          },
          "startingItems": {
            "itemIds": [1056, 2003, 2003],
            "games": 31200,
            "winrate": 0.514
          },
          "coreBuild": {
            "itemIds": [3118, 3020, 4645],
            "games": 11400,
            "winrate": 0.542
          },
          "archetypes": [
            {
              "name": "AP Burst",
              "itemIds": [3118, 4645, 3089],
              "games": 19800,
              "winrate": 0.538
            }
          ],
          "boots": [
            { "itemId": 3020, "pickrate": 0.84, "winrate": 0.516 },
            { "itemId": 3158, "pickrate": 0.11, "winrate": 0.502 }
          ],
          "completedItems": [
            { "itemId": 3118, "pickrate": 0.78, "winrate": 0.529 },
            { "itemId": 4645, "pickrate": 0.64, "winrate": 0.541 },
            { "itemId": 3089, "pickrate": 0.52, "winrate": 0.568 }
          ],
          "situational": [
            { "itemId": 3157, "pickrate": 0.34, "winrate": 0.548 },
            { "itemId": 3102, "pickrate": 0.14, "winrate": 0.553 }
          ]
        },
        "vs": {
          "61": {
            "games": 1830,
            "winrate": 0.462,
            "runes": {
              "primaryStyleId": 8100,
              "subStyleId": 8300,
              "perkIds": [8112, 8139, 8140, 8135, 8345, 8347, 5008, 5008, 5011],
              "games": 620,
              "winrate": 0.479
            },
            "summonerSpells": {
              "ids": [4, 12],
              "games": 1120,
              "winrate": 0.474
            },
            "startingItems": {
              "itemIds": [1056, 2003, 2003],
              "games": 1590,
              "winrate": 0.465
            },
            "boots": [
              { "itemId": 3020, "pickrate": 0.76, "winrate": 0.468 },
              { "itemId": 3111, "pickrate": 0.19, "winrate": 0.481 }
            ]
          }
        }
      }
    }
  }
}


2.3 item_stats.json

Exakte Endpunkte & Feldpfade

⚬ GET /lol/match/v5/matches/{matchId}:
  ⚬ info.participants[].{teamId, championId, item0..item6, win, totalHeal, totalDamageShieldedOnTeammates, magicDamageDealtToChampions, physicalDamageDealtToChampions, totalDamageDealtToChampions, damageSelfMitigated, kills}
⚬ GET /lol/match/v5/matches/{matchId}/timeline:
  ⚬ ITEM_PURCHASED (timestamp / 60000.0 für avgCompletionMinute)

Datengetriebene Kontext-Merkmale & Anti-Confounding

⚬ Definition der 6 Gegner-Comp-Merkmale (pro Gegner-Team aus Match-V5):
  1. vsHeavyHealing: Summe totalHeal der 5 Gegner > 32.000 (oder \ge 2 Gegner mit totalHeal / (gameDuration / 60) > 350).
  2. vsShields: Summe totalDamageShieldedOnTeammates der Gegner > 7.500 oder \ge 2 Gegner mit Shield-Abilities laut CDragon.
  3. vsHeavyAP: \frac{\sum \text{magicDamageDealtToChampions}}{\sum \text{totalDamageDealtToChampions}} \ge 0.55.
  4. vsHeavyAD: \frac{\sum \text{physicalDamageDealtToChampions}}{\sum \text{totalDamageDealtToChampions}} \ge 0.65.
  5. vsTanks: \ge 2 Gegner mit damageSelfMitigated > 26.000 (und CDragon-Tag "Tank" oder "Fighter").
  6. vsFedCrit: Mindestens 1 Gegner hat \ge 2 Crit-Items ("CriticalStrike" in categories) und kills >= 6.
⚬ Anti-Confounding (Eliminierung des Snowball-/Gold-Bias):
  Fertige Legendaries haben generell eine höhere Winrate (~53–56 %), weil verlierende Spieler oft bei 2 Items feststecken. Zudem wird Anti-Heal häufig gekauft, wenn ein Gegner bereits snowballt. Um den reinen situativen Mehrwert von Item I unter Kontext C \in \{0, 1\} zu messen, berechnen wir den Champion-stratifizierten Difference-in-Differences-Uplift gegenüber Spielern desselben Champions, die im selben Slot ein anderes Legendary \neg I fertiggestellt haben:
  
  $$\text{contextDelta}(I, C) = \sum_{k \in \text{Champs}(I)} w_k \cdot \Big[ \big(WR_k(I \mid C=1) - WR_k(\neg I \mid C=1)\big) - \big(WR_k(I \mid C=0) - WR_k(\neg I \mid C=0)\big) \Big]$$
  
  wobei w_k der Anteil von Champion k an den Käufen von Item I ist. Mindest-Stichprobe: N \ge 200 Käufe mit C=1 und N \ge 200 mit C=0.

Python-Pseudocode

def classify_enemy_comp(enemies: list[dict], game_duration: int, cdragon_items: dict) -> dict[str, bool]:
    total_heal = sum(e.get("totalHeal", 0) for e in enemies)
    total_shield = sum(e.get("totalDamageShieldedOnTeammates", 0) for e in enemies)
    ap_dmg = sum(e.get("magicDamageDealtToChampions", 0) for e in enemies)
    ad_dmg = sum(e.get("physicalDamageDealtToChampions", 0) for e in enemies)
    all_dmg = max(sum(e.get("totalDamageDealtToChampions", 1) for e in enemies), 1)
    tanks = sum(1 for e in enemies if e.get("damageSelfMitigated", 0) > 26000)

    fed_crit = False
    for e in enemies:
        if e.get("kills", 0) >= 6:
            crit_items = sum(
                1 for slot in range(6)
                if "CriticalStrike" in cdragon_items.get(e.get(f"item{slot}", 0), {}).get("categories", [])
            )
            if crit_items >= 2:
                fed_crit = True
                break

    return {
        "vsHeavyHealing": total_heal > 32000,
        "vsShields": total_shield > 7500,
        "vsHeavyAP": (ap_dmg / all_dmg) >= 0.55,
        "vsHeavyAD": (ad_dmg / all_dmg) >= 0.65,
        "vsTanks": tanks >= 2,
        "vsFedCrit": fed_crit,
    }


Beispiel-Eintrag (item_stats.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T04:00:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "EMERALD",
    "matchesAnalyzed": 184233
  },
  "items": {
    "3033": {
      "games": 52140,
      "pickrate": 0.088,
      "winrate": 0.514,
      "avgCompletionMinute": 21.4,
      "contextDeltas": {
        "vsHeavyHealing": 0.031,
        "vsShields": 0.004,
        "vsHeavyAP": -0.002,
        "vsHeavyAD": 0.001,
        "vsTanks": 0.012,
        "vsFedCrit": 0.0
      }
    },
    "6695": {
      "games": 14820,
      "pickrate": 0.025,
      "winrate": 0.521,
      "avgCompletionMinute": 18.9,
      "contextDeltas": {
        "vsHeavyHealing": 0.001,
        "vsShields": 0.038,
        "vsHeavyAP": -0.003,
        "vsHeavyAD": 0.002,
        "vsTanks": -0.004,
        "vsFedCrit": 0.001
      }
    }
  }
}


2.4 tierlist.json

Exakte Endpunkte & Feldpfade

⚬ GET /lol/match/v5/matches/{matchId}:
  ⚬ info.queueId (420 Ranked, 450 ARAM, 1700 Arena)
  ⚬ info.gameDuration (Sekunden)
  ⚬ info.teams[].bans[].championId
  ⚬ info.participants[].{championId, teamPosition, win, placement}

Formeln: Composite z-Score, Power-Curve & Duo-Synergie

⚬ Tierlist-Score (score & tier):
  1. Glätte Winrate via Empirical Bayes (m = 100, Prior 0.50): \widehat{WR}_i = \frac{W_i + 50}{N_i + 100}.
  2. Berechne z-Scores über alle (championId, role) mit laneShare >= 0.015 (Pickrate und Banrate log-transformiert wegen Rechtsschiefe):
     
     $$S_{\text{raw}, i} = 0.65 \cdot z(\widehat{WR}_i) + 0.20 \cdot z\big(\ln(PR_i + 10^{-4})\big) + 0.15 \cdot z\big(\ln(BR_i + 10^{-4})\big)$$
     $$\text{score}_i = \text{clamp}\big(50.0 + 10.0 \cdot S_{\text{raw}, i},\ 0.0,\ 100.0\big)$$
  3. Tier-Grenzen: S+ (\ge 65.0), S (57.5\text{–}64.9), A (50.0\text{–}57.4), B (42.5\text{–}49.9), C (35.0\text{–}42.4), D (< 35.0).
⚬ powerCurve:
  ⚬ Buckets: early (300 <= gameDuration < 1500, < 25 Min.), mid (1500 <= gameDuration < 1920, 25–32 Min.), late (gameDuration >= 1920, > 32 Min.).
  ⚬ Glättung pro Bucket: \widehat{WR}_{i, b} = \frac{W_{i, b} + 50 \cdot \widehat{WR}_i}{N_{i, b} + 50} (Prior = Gesamt-Winrate des Champions; Mindest-Stichprobe N_{\text{total}} \ge 300).
⚬ duo (ADC + Support Synergie):
  ⚬ Erwartete Duo-Winrate aus Einzel-Winrates: \mu_{\text{duo}} = \sigma\big(\text{logit}(WR_{\text{BOTTOM}}) + \text{logit}(WR_{\text{UTILITY}})\big).
  ⚬ Geglättete Paar-Winrate (m = 80, N_{\min} = 100): \widehat{WR}_{\text{duo}} = \frac{W_{\text{duo}} + 80 \cdot \mu_{\text{duo}}}{N_{\text{duo}} + 80}. Der Tier-Rank kombiniert \widehat{WR}_{\text{duo}} und das Synergie-Delta \widehat{WR}_{\text{duo}} - \mu_{\text{duo}}.

Python-Pseudocode

import numpy as np

def assign_tier(score: float) -> str:
    if score >= 65.0: return "S+"
    if score >= 57.5: return "S"
    if score >= 50.0: return "A"
    if score >= 42.5: return "B"
    if score >= 35.0: return "C"
    return "D"

def compute_ranked_tierlist(entries: list[dict], prev_patch_wr: dict) -> list[dict]:
    # entries: [{"championId", "role", "games", "wins", "picks", "bans", "total_matches", "laneShare", "buckets"}]
    valid = [e for e in entries if e["laneShare"] >= 0.015 and e["games"] >= 100]
    wrs = np.array([(e["wins"] + 50.0) / (e["games"] + 100.0) for e in valid])
    lprs = np.array([np.log(e["games"] / e["total_matches"] + 1e-4) for e in valid])
    lbrs = np.array([np.log(e["bans"] / e["total_matches"] + 1e-4) for e in valid])

    z_wr = (wrs - wrs.mean()) / max(wrs.std(), 1e-6)
    z_pr = (lprs - lprs.mean()) / max(lprs.std(), 1e-6)
    z_br = (lbrs - lbrs.mean()) / max(lbrs.std(), 1e-6)
    raw_scores = 0.65 * z_wr + 0.20 * z_pr + 0.15 * z_br
    scores = np.clip(50.0 + 10.0 * raw_scores, 0.0, 100.0)

    out = []
    for i, e in enumerate(valid):
        wr = float(wrs[i])
        sc = round(float(scores[i]), 1)
        prev = prev_patch_wr.get((e["championId"], e["role"]), wr)
        b = e["buckets"]
        pc = {
            k: round((b[k]["wins"] + 50.0 * wr) / (b[k]["games"] + 50.0), 3)
            for k in ("early", "mid", "late")
        }
        out.append({
            "championId": e["championId"],
            "role": e["role"],
            "laneShare": round(e["laneShare"], 3),
            "tier": assign_tier(sc),
            "score": sc,
            "winrate": round(wr, 4),
            "winrateDelta": round(wr - prev, 4),
            "pickrate": round(e["games"] / e["total_matches"], 4),
            "banrate": round(e["bans"] / e["total_matches"], 4),
            "games": e["games"],
            "powerCurve": pc,
        })
    out.sort(key=lambda x: x["score"], reverse=True)
    for idx, item in enumerate(out, start=1):
        item["rank"] = idx
    return out


Beispiel-Eintrag (tierlist.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T04:00:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "EMERALD",
    "matchesAnalyzed": 184233
  },
  "brackets": [
    {
      "rank": "EMERALD_PLUS",
      "platform": "ALL",
      "modes": {
        "ranked": [
          {
            "championId": 103,
            "role": "MIDDLE",
            "laneShare": 0.978,
            "rank": 1,
            "tier": "S+",
            "score": 71.2,
            "winrate": 0.526,
            "winrateDelta": 0.008,
            "pickrate": 0.112,
            "banrate": 0.07,
            "games": 41288,
            "powerCurve": { "early": 0.495, "mid": 0.534, "late": 0.521 }
          }
        ],
        "aram": [
          {
            "championId": 103,
            "role": "ALL",
            "laneShare": 1.0,
            "rank": 14,
            "tier": "S",
            "score": 61.4,
            "winrate": 0.531,
            "winrateDelta": 0.003,
            "pickrate": 0.068,
            "banrate": 0.0,
            "games": 14210,
            "powerCurve": { "early": 0.528, "mid": 0.535, "late": 0.524 }
          }
        ],
        "arena": [
          {
            "championId": 103,
            "role": "ALL",
            "laneShare": 1.0,
            "rank": 22,
            "tier": "A",
            "score": 55.8,
            "winrate": 0.542,
            "winrateDelta": -0.004,
            "pickrate": 0.051,
            "banrate": 0.042,
            "games": 9840,
            "avgPlacement": 4.18,
            "top4Rate": 0.542,
            "powerCurve": { "early": 0.542, "mid": 0.542, "late": 0.542 }
          }
        ],
        "duo": [
          {
            "championId": 222,
            "role": "BOTTOM",
            "partnerChampionId": 412,
            "partnerRole": "UTILITY",
            "games": 9120,
            "winrate": 0.537,
            "tier": "S"
          }
        ]
      }
    }
  ]
}


2.5 aram_augments.json

Exakte Endpunkte, Queue-IDs & Feldpfade

⚬ Queue-IDs & gameMode-Erkennung:
  ⚬ Arena (CHERRY): queueId == 1700 (bzw. info.gameMode == "CHERRY").
  ⚬ ARAM Mayhem (ARAM_MAYHEM): queueId == 2400 (UNSICHER über den exakten temporären Queue-Slot Ende 2026; der Aggregator prüft zusätzlich info.gameMode / info.gameType gegen die statische queues.json von Riot!).
⚬ Feldpfade in Match-V5 (info.participants[]):
  ⚬ playerAugment1, playerAugment2, playerAugment3, playerAugment4, playerAugment5, playerAugment6 (Integer-IDs; 0 = leerer Slot).
  ⚬ placement (1..8 in Arena) und win (bool; in Arena ist win == True äquivalent zu placement <= 4).
⚬ CDragon-Rarity-Mapping:
  ⚬ Quelle: [https://raw.communitydragon.org/latest/cdragon/arena/de_de.json](https://raw.communitydragon.org/latest/cdragon/arena/de_de.json) (augments[].{id, rarity}) sowie cherry-augments.json (UNSICHER, ob für ARAM Mayhem 2026 ein separates CDragon-JSON unter cdragon/mayhem/ existiert; unbekannte IDs außerhalb von arena/de_de.json erhalten den Fallback "silver").
  ⚬ Mapping: 0 -> "silver", 1 -> "gold", 2 -> "prismatic" (Werte >= 3 ebenfalls "prismatic").
⚬ Arena-Metrik: In Arena ist win == (placement <= 4) (top4Rate). Da ein Champion/Augment in Arena viele verschiedene Builds/Partner hat, wird die Augment-Winrate mit Empirical Bayes (m = 40, Prior 0.50) geglättet; die Tier-Vergabe (S+ bis D) erfolgt über z-Scores der geglätteten Top-4-Rate.

Python-Pseudocode

RARITY_MAP = {0: "silver", 1: "gold", 2: "prismatic"}

def parse_participant_augments(participant: dict) -> list[int]:
    augs = []
    for idx in range(1, 7):
        aid = participant.get(f"playerAugment{idx}", 0)
        if aid and aid > 0:
            augs.append(aid)
    return augs

def build_augment_stats(participants_records: list[dict], cdragon_augments: dict) -> dict:
    # participants_records: [{"championId": int, "augments": list[int], "win": bool}]
    total_picks = len(participants_records)
    global_counts = {}
    champ_counts = {}

    for rec in participants_records:
        win = 1 if rec["win"] else 0
        cid = rec["championId"]
        for aid in rec["augments"]:
            g = global_counts.setdefault(aid, [0, 0])
            g[0] += 1
            g[1] += win
            c = champ_counts.setdefault((cid, aid), [0, 0])
            c[0] += 1
            c[1] += win

    augments_out = []
    for aid, (games, wins) in global_counts.items():
        if games < 50:
            continue
        wr = (wins + 20.0) / (games + 40.0)
        raw_rarity = cdragon_augments.get(aid, {}).get("rarity", 0)
        augments_out.append({
            "id": aid,
            "rarity": RARITY_MAP.get(raw_rarity, "prismatic"),
            "tier": "S" if wr >= 0.54 else ("A" if wr >= 0.515 else ("B" if wr >= 0.49 else "C")),
            "winrate": round(wr, 4),
            "pickrate": round(games / max(total_picks, 1), 4),
            "games": games,
        })
    augments_out.sort(key=lambda x: x["winrate"], reverse=True)
    return {"augments": augments_out}


Beispiel-Eintrag (aram_augments.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T04:00:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "EMERALD",
    "matchesAnalyzed": 184233
  },
  "modes": {
    "ARAM_MAYHEM": {
      "augments": [
        {
          "id": 93,
          "rarity": "silver",
          "tier": "A",
          "winrate": 0.524,
          "pickrate": 0.041,
          "games": 8120
        }
      ],
      "championAugments": {
        "103": [
          { "id": 93, "tier": "S", "winrate": 0.568, "games": 410 }
        ]
      },
      "builds": {
        "103": {
          "games": 6420,
          "winrate": 0.519,
          "runes": {
            "primaryStyleId": 8100,
            "subStyleId": 8000,
            "perkIds": [8112, 8139, 8140, 8135, 8009, 8014, 5008, 5008, 5011],
            "games": 3910,
            "winrate": 0.527
          },
          "summonerSpells": { "ids": [4, 32], "games": 5100, "winrate": 0.522 },
          "startingItems": { "itemIds": [3802, 2003, 2003], "games": 4800, "winrate": 0.521 },
          "coreBuild": { "itemIds": [3118, 3020, 4645], "games": 2190, "winrate": 0.548 },
          "archetypes": [],
          "boots": [{ "itemId": 3020, "pickrate": 0.89, "winrate": 0.521 }],
          "completedItems": [{ "itemId": 3089, "pickrate": 0.67, "winrate": 0.562 }],
          "situational": [{ "itemId": 3157, "pickrate": 0.31, "winrate": 0.541 }]
        }
      }
    },
    "CHERRY": {
      "augments": [
        {
          "id": 142,
          "rarity": "prismatic",
          "tier": "S+",
          "winrate": 0.581,
          "pickrate": 0.029,
          "games": 5430
        }
      ],
      "championAugments": {
        "103": [
          { "id": 142, "tier": "S+", "winrate": 0.612, "games": 318 }
        ]
      },
      "builds": {}
    }
  }
}


2.6 pro_spectate.json

Exakte Endpunkte, Infrastruktur & LCU-Launch

⚬ Spectator-V5 Endpoint:
  ⚬ GET https://{platform}[.api.riotgames.com/lol/spectator/v5/active-games/by-summoner/](https://.api.riotgames.com/lol/spectator/v5/active-games/by-summoner/){puuid}
  ⚬ Wichtig: Trotz des Pfadsegments by-summoner verlangt Spectator-V5 zwingend die puuid.
  ⚬ Feldpfade: gameId, platformId, gameStartTime (Epoch ms), gameQueueConfigId (== 420), participants[].{teamId, championId, puuid, riotId}.
⚬ Pro-Account-Quelle (Leaguepedia Cargo API):
  ⚬ GET [https://lol.fandom.com/api.php?action=cargoquery&format=json&tables=Players&fields=Player,ID,Team,Role,SoloqueueIds&where=SoloqueueIds%20IS%20NOT%20NULL&limit=500](https://lol.fandom.com/api.php?action=cargoquery&format=json&tables=Players&fields=Player,ID,Team,Role,SoloqueueIds&where=SoloqueueIds%20IS%20NOT%20NULL&limit=500)
  ⚬ Ein wöchentlicher GitHub-Actions-Sync löst die Riot IDs (GameName#TAG) via GET https://{regional}[.api.riotgames.com/riot/account/v1/accounts/by-riot-id/](https://.api.riotgames.com/riot/account/v1/accounts/by-riot-id/){gameName}/{tagLine} in puuids auf.
  ⚬ Lizenz: CC BY-SA 3.0 (erfordert Namensnennung von Leaguepedia in den App-Credits).
⚬ Cloudflare Worker vs. GitHub Actions:
  ⚬ GitHub Actions hat eine Mindest-Cron-Frequenz von 5 Minuten plus 5–20 Minuten Queue-Jitter → ungeeignet für Live-Spectate.
  ⚬ Cloudflare Worker (*/2 * * * * Cron Trigger) + Cloudflare R2:
    ⚬ Subrequest-Limit beachten: Der kostenlose Workers-Plan erlaubt maximal 50 Subrequests pro Cron-Aufruf (zu wenig für 500 Accounts!). Der Workers Paid Plan ($5/Monat) erhöht das Limit auf 1.000 Subrequests pro Invocation bei 10 Mio. Requests/Monat.
    ⚬ Polling-Kosten: ~500 Pro-/Challenger-PUUIDs dauern beim Production Key (500 Req/10s) nur 10 Sekunden. Bereits gefundene Mitspieler im selben Match werden im aktuellen Zyklus übersprungen (~18 % Ersparnis).
⚬ macOS LCU-Spectate-Launch (POST /lol-spectator/v1/spectate/launch):
  ⚬ Lokale LCU-URL aus /Applications/League of Legends.app/Contents/LoL/lockfile ([https://127.0.0.1](https://127.0.0.1):{port}, Basic Auth riot:{password}).
  ⚬ Exakter Payload:
    {
      "allowObserveMode": "ALL",
      "dropInSpectateGameId": "7012345678",
      "gameQueueType": "RANKED_SOLO_5x5",
      "puuid": "01234567-89ab-cdef-0123-456789abcdef"
    }
    
  ⚬ Einschränkungen:
    1. Same-Region-Zwang: Der LCU-Observer funktioniert zuverlässig nur für Spiele auf derselben Plattform wie der eingeloggte LoL-Client (z. B. EUW-Client → EUW1-Spiel). Bei Cross-Region-Spielen (z. B. KR-Spiel auf EUW-Client) schlägt der Observer-Handshake fehl; Riftsight sollte solche Spiele im UI als „Andere Region (nur Info)“ kennzeichnen.
    2. 3-Minuten-Delay: Riot gibt den Spectator-Stream erst 180 Sekunden nach gameStartTime frei.

Python-/Worker-Pseudocode (Polling-Logik)

async def poll_live_games(pro_accounts: dict[str, dict], challenger_ranks: dict[str, dict], riot_client) -> list[dict]:
    # pro_accounts[puuid] = {"proName": "Caps", "proTeam": "G2", "platform": "EUW1", "role": "MIDDLE"}
    seen_game_ids = set()
    checked_puuids = set()
    active_games = []

    for puuid, info in pro_accounts.items():
        if puuid in checked_puuids:
            continue
        checked_puuids.add(puuid)
        game = await riot_client.get_active_game(info["platform"], puuid)  # None bei 404
        if not game or game.get("gameQueueConfigId") != 420:
            continue
        gid = game["gameId"]
        if gid in seen_game_ids:
            continue
        seen_game_ids.add(gid)

        participants_out = []
        known_count = 0
        lps = []
        for p in game["participants"]:
            p_puuid = p.get("puuid", "")
            checked_puuids.add(p_puuid)
            pro = pro_accounts.get(p_puuid)
            rank_info = challenger_ranks.get(p_puuid, {"tier": "CHALLENGER", "lp": 1000})
            if pro:
                known_count += 1
            lps.append(rank_info["lp"])
            participants_out.append({
                "teamId": p["teamId"],
                "championId": p["championId"],
                "role": pro["role"] if pro else "UNKNOWN",
                "puuid": p_puuid,
                "riotId": p.get("riotId", "Unknown#000"),
                "proName": pro["proName"] if pro else None,
                "proTeam": pro["proTeam"] if pro else None,
                "tier": rank_info["tier"],
                "lp": rank_info["lp"],
                "isKnown": pro is not None,
            })

        active_games.append({
            "gameId": gid,
            "platformId": game["platformId"],
            "gameStartTime": game["gameStartTime"],
            "queueId": 420,
            "averageTier": "CHALLENGER",
            "averageLp": round(sum(lps) / max(len(lps), 1)),
            "knownPlayers": known_count,
            "participants": participants_out,
        })
    active_games.sort(key=lambda g: (g["knownPlayers"], g["averageLp"]), reverse=True)
    return active_games


Beispiel-Eintrag (pro_spectate.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T18:50:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "CHALLENGER",
    "matchesAnalyzed": 18
  },
  "games": [
    {
      "gameId": 7012345678,
      "platformId": "EUW1",
      "gameStartTime": 1763487900000,
      "queueId": 420,
      "averageTier": "CHALLENGER",
      "averageLp": 1485,
      "knownPlayers": 4,
      "participants": [
        {
          "teamId": 100,
          "championId": 103,
          "role": "MIDDLE",
          "puuid": "8f2a1b3c-4d5e-6f70-8192-a1b2c3d4e5f6",
          "riotId": "G2 Caps#1323",
          "proName": "Caps",
          "proTeam": "G2 Esports",
          "tier": "CHALLENGER",
          "lp": 1640,
          "isKnown": true
        }
      ]
    }
  ]
}


2.7 leaderboard.json

Exakte Endpunkte, Kostenbudget & Aggregation

⚬ Endpunkte pro Plattform (EUW1, KR, NA1):
  1. GET https://{platform}[.api.riotgames.com/lol/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5](https://.api.riotgames.com/lol/league/v4/challengerleagues/by-queue/RANKED_SOLO_5x5)
  2. GET https://{platform}[.api.riotgames.com/lol/league/v4/grandmasterleagues/by-queue/RANKED_SOLO_5x5](https://.api.riotgames.com/lol/league/v4/grandmasterleagues/by-queue/RANKED_SOLO_5x5)
  3. GET https://{regional}[.api.riotgames.com/riot/account/v1/accounts/by-puuid/](https://.api.riotgames.com/riot/account/v1/accounts/by-puuid/){puuid} (nur für PUUIDs, die nicht im 7-Tage-Cache puuid_riotid_cache.json liegen → reduziert 300 Calls/Tag auf ~20 Calls/Tag).
⚬ topChampionIds ohne Zusatz-Calls: Wird direkt aus den lokal gecachten Match-V5-Matches der letzten 14 Tage für jede Top-100-PUUID gezählt (Top 3 gespielte Champions nach Games; Fallback GET /lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}/top?count=3 nur bei < 5 gecachten Matches).

Python-Pseudocode

from collections import Counter

def build_platform_leaderboard(
    challenger_entries: list[dict],
    gm_entries: list[dict],
    riotid_map: dict[str, str],
    recent_matches_by_puuid: dict[str, list[int]],
    top_n: int = 100,
) -> list[dict]:
    combined = [dict(e, tier="CHALLENGER") for e in challenger_entries] + [
        dict(e, tier="GRANDMASTER") for e in gm_entries
    ]
    combined.sort(key=lambda x: x["leaguePoints"], reverse=True)

    board = []
    for rank_idx, entry in enumerate(combined[:top_n], start=1):
        puuid = entry["puuid"]
        champ_counts = Counter(recent_matches_by_puuid.get(puuid, []))
        top_champs = [cid for cid, _ in champ_counts.most_common(3)]
        board.append({
            "rank": rank_idx,
            "puuid": puuid,
            "riotId": riotid_map.get(puuid, "Summoner#000"),
            "tier": entry["tier"],
            "lp": entry["leaguePoints"],
            "wins": entry["wins"],
            "losses": entry["losses"],
            "topChampionIds": top_champs,
        })
    return board


Beispiel-Eintrag (leaderboard.json)

{
  "meta": {
    "schemaVersion": 1,
    "patch": "16.23",
    "generatedAt": "2026-11-18T04:00:00Z",
    "sample": false,
    "platforms": ["EUW1", "KR", "NA1"],
    "rankFloor": "GRANDMASTER",
    "matchesAnalyzed": 184233
  },
  "platforms": {
    "EUW1": [
      {
        "rank": 1,
        "puuid": "8f2a1b3c-4d5e-6f70-8192-a1b2c3d4e5f6",
        "riotId": "G2 Caps#1323",
        "tier": "CHALLENGER",
        "lp": 2104,
        "wins": 412,
        "losses": 330,
        "topChampionIds": [103, 61, 4]
      }
    ]
  }
}


3. Hosting, Caching, Riot Policies & Betrieb (§3.7)

3.1 Hosting-Vergleich & Dateigrößen

Hosting-Option	Rate-Limits & Egress	Caching / ETag / Gzip	Eignung
raw.githubusercontent.com	Strenge IP-Limits, keine Kontroll-Header	Schlecht (kein CDN-Purge, kein Custom-Domain-SSL)	Ungeeignet
GitHub Pages	100 GB Bandbreite/Monat (Soft Limit)	Automatisch Fastly-CDN, gzip/brotli, ETag, max-age=600	Sehr gut für die 6 täglichen JSONs
Cloudflare R2 (Custom Domain)	0 € Egress, unbegrenzte Requests	Volle Cache-Control-, ETag- & If-None-Match-Kontrolle	Optimal als einheitliches Ziel (inkl. 2-Min.-pro_spectate.json)

⚬ Geschätzte Dateigrößen (unkomprimiert / gzipped):
  ⚬ counterpicks.json: ~450 KB / ~85 KB gzip
  ⚬ matchup_runes.json: ~3,2 MB / ~420 KB gzip
  ⚬ item_stats.json: ~35 KB / ~8 KB gzip
  ⚬ tierlist.json: ~420 KB / ~75 KB gzip
  ⚬ aram_augments.json: ~380 KB / ~65 KB gzip
  ⚬ pro_spectate.json: ~45 KB / ~9 KB gzip
  ⚬ leaderboard.json: ~60 KB / ~14 KB gzip
  ⚬ Gesamtvolumen pro täglichem App-Sync: ~680 KB gzipped. Swift URLSession nutzt ETag / If-None-Match automatisch, sodass bei unverändertem Patch 304 Not Modified (0 KB Payload) zurückkommt.

3.2 Riot Developer Policies & Pflicht-Disclaimer

⚬ Verboten in Riftsight:
  1. Keine De-Anonymisierung im Ranked Champ Select: Mitspieler (Summoner 1–5) dürfen in Solo/Duo nicht über Logs, LCU-Workarounds oder APIs identifiziert werden.
  2. Keine Live-Gegner-Cooldown-Timer: Kein Herunterzählen gegnerischer Ultimates/Summoner-Spells im Spiel (statische Base-Cooldowns aus CommunityDragon im Nachschlagewerk sind erlaubt, laufende Countdown-Timer sind verboten).
  3. Keine Live-Siegwahrscheinlichkeit / Echtzeit-Alerts: Keine In-Game-Win-Probability und keine Popups für gegnerische Item-Käufe oder Ward-Timer.
  4. Kein Key im Binary: Der Riot API Key darf niemals im Swift-Client oder in Public-Repos auftauchen.
⚬ Pflicht-Disclaimer (im About-/Settings-Screen von Riftsight):
  "Riftsight isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc."

3.3 Fehlerbehandlung, Resume & Validierung

⚬ Rate-Limiter: Asynchroner Token-Bucket pro Cluster/App. Bei HTTP 429 wird der Retry-After-Header ausgelesen und exakt int(Retry-After) + 0.5 Sekunden gewartet; bei 500/502/503/504 exponentielles Backoff mit Jitter (max. 5 Retries).
⚬ Idempotenz & Resume: Alle geladenen Roh-Matches und Timelines werden in state/matches_{patch}.sqlite (zstd-komprimiert) gespeichert und über actions/cache@v4 zwischen den Runs persistiert. Nach einem Timeout/Abbruch setzt der Job nahtlos bei den noch fehlenden matchIds auf.
⚬ Schema-Gate vor Publish: publish.py validiert jede JSON-Datei mit pydantic (keine NaN/Infinity, alle winrate ∈ [0.0, 1.0], len(champions) >= 150). Bei Validierungsfehlern bricht der Job mit Exit-Code 1 ab, ohne bestehende Live-Dateien zu überschreiben.

4. Modul-Architektur (data-pipeline/) & GitHub Actions (§4.3)

4.1 Verzeichnisstruktur

data-pipeline/
├── pyproject.toml
├── src/riftsight_pipeline/
│   ├── config.py               # Plattformen, Cluster, Thresholds, R2/Pages-Targets
│   ├── riot_client.py          # Async httpx-Client mit Token-Bucket, 429-Retry & Caching
│   ├── static_data.py          # Loader für Data Dragon, CommunityDragon (de_de + arena) & Meraki
│   ├── store.py                # SQLite + zstd Rohdaten-Store (Idempotenz & Resume)
│   ├── collect.py              # League-V4 Seeding + stratifiziertes Match-V5 & Timeline Crawling
│   ├── aggregate_counters.py   # Berechnet counterpicks.json (Log-Odds + Frame-15-Diffs)
│   ├── aggregate_builds.py     # Berechnet matchup_runes.json & item_stats.json
│   ├── tierlist.py             # Berechnet tierlist.json (Ranked, ARAM, Arena, Duo)
│   ├── augments.py             # Berechnet aram_augments.json (ARAM Mayhem & CHERRY)
│   ├── leaderboard.py          # Berechnet leaderboard.json inkl. Riot-ID-7d-Cache
│   ├── schemas.py              # Pydantic-v2-Validatoren für alle Ziel-JSONs
│   └── publish.py              # Gzip-Komprimierung, Schema-Check & Upload auf R2 / GitHub Pages
└── worker-spectate/            # Separater Cloudflare Worker (Cron */2 * * * *)
    ├── wrangler.toml
    └── src/index.ts            # Leaguepedia-Sync + Spectator-V5 Poller -> R2 pro_spectate.json


4.2 GitHub-Actions-Workflow (.github/workflows/daily-pipeline.yml)

name: Riftsight Daily Data Pipeline
on:
  schedule:
    - cron: "0 2 * * *"   # Täglich 02:00 UTC (03:00/04:00 CET)
  workflow_dispatch:
    inputs:
      sample_mode:
        description: "Run small sample (Dev/Personal Key)"
        type: boolean
        default: false

concurrency:
  group: riftsight-pipeline
  cancel-in-progress: false

jobs:
  aggregate-and-publish:
    runs-on: ubuntu-latest
    timeout-minutes: 330
    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v4
        with:
          python-version: "3.12"

      - name: Restore Match SQLite & Riot-ID Cache
        uses: actions/cache@v4
        with:
          path: data-pipeline/state
          key: riftsight-state-${{ github.run_id }}
          restore-keys: |
            riftsight-state-

      - name: Install Dependencies
        working-directory: data-pipeline
        run: uv sync --frozen

      - name: Collect Matches & Timelines
        working-directory: data-pipeline
        env:
          RIOT_API_KEY: ${{ secrets.RIOT_API_KEY }}
          SAMPLE_MODE: ${{ inputs.sample_mode }}
        run: uv run python -m riftsight_pipeline.collect

      - name: Aggregate, Validate & Publish JSONs
        working-directory: data-pipeline
        env:
          R2_ENDPOINT_URL: ${{ secrets.R2_ENDPOINT_URL }}
          R2_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}
          R2_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
          R2_BUCKET: riftsight-data
        run: |
          uv run python -m riftsight_pipeline.aggregate_counters
          uv run python -m riftsight_pipeline.aggregate_builds
          uv run python -m riftsight_pipeline.tierlist
          uv run python -m riftsight_pipeline.augments
          uv run python -m riftsight_pipeline.leaderboard
          uv run python -m riftsight_pipeline.publish


5. Schema-Änderungsvorschläge (§4.4)

1. aram_augments.json (modes.CHERRY):
  ⚬ Vorschlag: Im Augment-Objekt und championAugments-Objekt für CHERRY (Arena) die optionalen Felder "avgPlacement": 3.82 und "top4Rate": 0.56 ergänzen (analog zu tierlist.json -> arena).
  ⚬ Begründung: Arena hat 8 Teams; winrate allein bildet nur Top-4 ab (placement <= 4), während avgPlacement (1.0–8.0) zwischen konstanten Top-2-Augments und knappen 4.-Platz-Augments unterscheidet.
2. pro_spectate.json (participants[]):
  ⚬ Vorschlag: role auf "UNKNOWN" erlauben (bzw. String? in Swift), wenn ein Nicht-Pro-Spieler in einer High-Elo-Lobby mitspielt.
  ⚬ Begründung: Spectator-V5 liefert im Gegensatz zu Match-V5 kein teamPosition-Feld. Für gelistete Pros kommt die Rolle aus Leaguepedia (Role), für unbekannte Challenger-Mitspieler müsste die Rolle sonst fehleranfällig aus championId + summoner1Id/summoner2Id (Smite = Jungle) erraten werden.

6. Quellen & Dokumentation (§4.5)

⚬ Riot Games API Dokumentation & Endpunkte (League-V4, Match-V5, Account-V1, Spectator-V5):
  [https://developer.riotgames.com/apis](https://developer.riotgames.com/apis)
⚬ Riot Games Developer Policies (General & League of Legends):
  [https://developer.riotgames.com/policies/general](https://developer.riotgames.com/policies/general)
  [https://developer.riotgames.com/policies/lol](https://developer.riotgames.com/policies/lol)
⚬ Riot Developer Relations GitHub (PUUID-Migration, Rate-Limits, Bugtracker):
  [https://github.com/RiotGames/developer-relations](https://github.com/RiotGames/developer-relations)
⚬ Riot Static Game Constants (queues.json, seasons.json, maps.json):
  [https://static.developer.riotgames.com/docs/lol/queues.json](https://static.developer.riotgames.com/docs/lol/queues.json)
⚬ Leaguepedia Cargo API (Players-Tabelle, CC BY-SA 3.0):
  [https://lol.fandom.com/wiki/Special:CargoTables/Players](https://lol.fandom.com/wiki/Special:CargoTables/Players)
⚬ CommunityDragon & Meraki Analytics:
  [https://raw.communitydragon.org/latest/cdragon/arena/de_de.json](https://raw.communitydragon.org/latest/cdragon/arena/de_de.json)
  [https://cdn.merakianalytics.com/riot/lol/resources/latest/en-US/championrates.json](https://cdn.merakianalytics.com/riot/lol/resources/latest/en-US/championrates.json)

(Alle mit „UNSICHER“ markierten Punkte – insbesondere die exakte ARAM-Mayhem-Queue-ID 2400, der CDragon-Pfad für Mayhem-Augments, das exakte Initial-Rate-Limit-Tier neuer Production Keys Ende 2026 sowie der Wegfall von summonerId in League-V4 – sollten vor dem Produktivstart einmalig gegen die Live-Payloads von queues.json und League-V4 verifiziert werden.)

7. Top-5-Risikoliste & Gegenmaßnahmen (§4.6)

#	Risiko	Auswirkung	Gegenmaßnahme
1	Lange Wartezeit / Rückfragen beim Production-Key-Review	Verzögerung des öffentlichen Releases von Riftsight (2–6 Wochen Review-Zeit).	Sofort nach Fertigstellung des Prototyps mit sample: true beantragen; in der Bewerbung explizit betonen, dass kein Key im macOS-Binary liegt und alle Policy-Regeln (Champ-Select-Anonymität, keine Live-Timer) eingehalten werden.
2	GitHub-Actions-Cache-Limit (10 GB) durch rohe Timelines	Roh-Timelines sind 10–15× größer als Match-JSONs (~150 KB/Match → 200k Timelines = ~30 GB).	Timelines niemals unkomprimiert speichern: Direkt beim Download in-memory parsen (extract_lane_timeline_metrics + extract_timeline_build_and_skills) und nur die kompakten extrahierten Feature-Vektoren (~300 Bytes/Match) in SQLite ablegen.
3	High-Elo-Bias durch Apex-Snowballing	Verzerrte Winrates/Tierlists für Emerald/Diamond (z. B. mechanisch schwere Champions wie Nidalee/Lee Sin).	Strikte Quoten-Steuerung im Collector (60 % Emerald / 30 % Diamond / 10 % Apex) anhand des Rang-Tiers der Seed-PUUIDs.
4	Ausfall externer CDNs (CommunityDragon / Meraki)	Pipeline bricht ab, wenn merakianalytics.com temporär nicht erreichbar ist.	Letzte valide CDragon-/Meraki-JSONs im Repository/R2-Fallback-Bucket cachen; laneShare primär direkt aus den eigenen Match-V5-Daten berechnen und Meraki nur als Ergänzung nutzen.
5	Cloudflare Workers Subrequest-Limit (50 Subrequests im Free Tier)	pro_spectate.json-Cron bricht nach dem 50. Pro-Account mit Too many subrequests ab.	Cloudflare Workers Paid Plan ($5/Monat, 1.000 Subrequests/Invocation) nutzen oder den Worker per Queue/Self-Chaining in 40er-Batches aufteilen.