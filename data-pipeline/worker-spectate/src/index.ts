/**
 * Cloudflare Worker: Riftsight Live Pro Spectator Poller
 *
 * Cron: every 2 minutes
 * 1. Liest `pro_accounts.json`, `leaderboard.json` und den Vorzustand `pro_spectate.json` aus R2.
 * 2. Prüft zuerst bereits laufende Spiele aus dem Vorlauf (1 Request pro Spiel), damit aktive
 *    Spiele während der Rotation nicht aus der Liste fallen.
 * 3. Fragt anschließend rotierend ab dem gespeicherten Cursor `pro_accounts` (und optional Top-Challenger
 *    aus `leaderboard.json`) gegen Spectator-V5 `/lol/spectator/v5/active-games/by-summoner/{puuid}` ab.
 * 4. Beachtet Riot Rate-Limits (`X-App-Rate-Limit-Count`, `X-Method-Rate-Limit-Count`, HTTP 429 -> `Retry-After`).
 * 5. Schreibt `pro_spectate.json` exakt im Schema `ProSpectateFile` (`PipelineModels.swift`) mit
 *    `Cache-Control: max-age=60` nach R2.
 */

export interface Env {
  DATA_BUCKET: R2Bucket;
  RIOT_API_KEY: string;
  DEFAULT_PATCH?: string;
  MAX_REQUESTS_PER_RUN?: string;
  MAX_GAME_AGE_MINUTES?: string;
}

// --- Input-Schemas (R2) ---

export interface ProAccount {
  puuid: string;
  platform: string;
  proName: string;
  proTeam: string | null;
  role: string | null;
}

export interface LeaderboardEntry {
  rank: number;
  puuid: string | null;
  riotId: string;
  tier: string;
  lp: number;
  wins: number;
  losses: number;
  topChampionIds: number[];
}

export interface LeaderboardFile {
  meta: DataMeta;
  platforms: Record<string, LeaderboardEntry[]>;
}

// --- Output-Schema (`ProSpectateFile` aus `PipelineModels.swift`) ---

export interface DataMeta {
  schemaVersion: number;
  patch: string;
  generatedAt: string;
  sample: boolean;
  platforms: string[];
  rankFloor: string;
  matchesAnalyzed: number;
}

export interface ProParticipant {
  teamId: number;
  championId: number;
  role: string | null;
  puuid: string | null;
  riotId: string | null;
  proName: string | null;
  proTeam: string | null;
  tier: string | null;
  lp: number | null;
  isKnown: boolean;
}

export interface ProGame {
  gameId: number;
  platformId: string;
  gameStartTime: number;
  queueId: number;
  averageTier: string;
  averageLp: number;
  knownPlayers: number;
  participants: ProParticipant[];
}

export interface ProSpectateFile {
  meta: DataMeta;
  games: ProGame[];
}

// --- Riot Spectator-V5 Payload ---

interface RiotSpectatorParticipant {
  teamId: number;
  spell1Id?: number;
  spell2Id?: number;
  championId: number;
  puuid?: string | null;
  riotId?: string | null;
  summonerName?: string | null;
}

interface RiotCurrentGameInfo {
  gameId: number;
  gameType?: string;
  gameStartTime: number;
  mapId?: number;
  gameLength?: number;
  platformId: string;
  gameMode?: string;
  gameQueueConfigId?: number;
  participants: RiotSpectatorParticipant[];
}

interface RankSnapshot {
  tier: string;
  lp: number;
  riotId?: string;
  platform: string;
}

const VALID_PLATFORMS = new Set([
  "EUW1", "EUN1", "TR1", "RU", "ME1",
  "NA1", "BR1", "LA1", "LA2",
  "KR", "JP1",
  "OC1", "SG2", "TW2", "VN2",
]);

const ROLE_ALIASES: Record<string, string> = {
  TOP: "TOP",
  TOPLANE: "TOP",
  JUNGLE: "JUNGLE",
  JGL: "JUNGLE",
  JG: "JUNGLE",
  MIDDLE: "MIDDLE",
  MID: "MIDDLE",
  MIDLANE: "MIDDLE",
  BOTTOM: "BOTTOM",
  BOT: "BOTTOM",
  ADC: "BOTTOM",
  AD: "BOTTOM",
  UTILITY: "UTILITY",
  SUPPORT: "UTILITY",
  SUP: "UTILITY",
  SUPP: "UTILITY",
};

const TIER_WEIGHT: Record<string, number> = {
  MASTER: 1,
  GRANDMASTER: 2,
  CHALLENGER: 3,
};

function normalizeRole(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const key = raw.trim().toUpperCase();
  return ROLE_ALIASES[key] ?? null;
}

function normalizePlatform(raw: string | null | undefined): string {
  const upper = (raw ?? "EUW1").trim().toUpperCase();
  return VALID_PLATFORMS.has(upper) ? upper : "EUW1";
}

function isoUtcNow(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Prüft Riot Rate-Limit-Header (`X-App-Rate-Limit` / `X-App-Rate-Limit-Count`)
 * und gibt eine kurze Pause (in ms) zurück, falls ein kurzes Fenster fast ausgeschöpft ist.
 */
function computeHeaderThrottleMs(headers: Headers): number {
  const pairs: Array<[string | null, string | null]> = [
    [headers.get("X-App-Rate-Limit"), headers.get("X-App-Rate-Limit-Count")],
    [headers.get("X-Method-Rate-Limit"), headers.get("X-Method-Rate-Limit-Count")],
  ];

  let maxWaitMs = 0;
  for (const [limitHeader, countHeader] of pairs) {
    if (!limitHeader || !countHeader) continue;
    const limits = parseRateHeader(limitHeader);
    const counts = parseRateHeader(countHeader);
    for (const [windowSec, limitCount] of limits.entries()) {
      const currentCount = counts.get(windowSec) ?? 0;
      if (limitCount > 0 && currentCount >= Math.max(1, Math.floor(limitCount * 0.92))) {
        // Sicherheitsabstand bei >92 % Auslastung im jeweiligen Zeitfenster
        const pauseMs = Math.min(windowSec * 1000, 1200);
        if (pauseMs > maxWaitMs) {
          maxWaitMs = pauseMs;
        }
      }
    }
  }
  return maxWaitMs;
}

function parseRateHeader(header: string): Map<number, number> {
  const result = new Map<number, number>();
  for (const part of header.split(",")) {
    const [countStr, secStr] = part.trim().split(":");
    const count = Number.parseInt(countStr, 10);
    const sec = Number.parseInt(secStr, 10);
    if (Number.isFinite(count) && Number.isFinite(sec) && sec > 0) {
      result.set(sec, count);
    }
  }
  return result;
}

class SpectatorPoller {
  private readonly apiKey: string;
  private readonly hostCooldownUntil = new Map<string, number>();
  public requestsMade = 0;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  async getActiveGame(platform: string, puuid: string, maxRetries = 3): Promise<RiotCurrentGameInfo | null> {
    const host = `${platform.toLowerCase()}.api.riotgames.com`;
    const url = `https://${host}/lol/spectator/v5/active-games/by-summoner/${encodeURIComponent(puuid)}`;

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      const cooldownUntil = this.hostCooldownUntil.get(host) ?? 0;
      const now = Date.now();
      if (cooldownUntil > now) {
        await sleep(cooldownUntil - now);
      }

      let response: Response;
      try {
        this.requestsMade += 1;
        response = await fetch(url, {
          method: "GET",
          headers: {
            "X-Riot-Token": this.apiKey,
            "User-Agent": "riftsight-worker-spectate/1.0",
            "Accept": "application/json",
          },
        });
      } catch {
        if (attempt === maxRetries) return null;
        await sleep(Math.min(5000, 400 * 2 ** attempt + Math.random() * 250));
        continue;
      }

      const throttleMs = computeHeaderThrottleMs(response.headers);
      if (throttleMs > 0) {
        this.hostCooldownUntil.set(host, Date.now() + throttleMs);
      }

      if (response.status === 200) {
        return (await response.json()) as RiotCurrentGameInfo;
      }
      if (response.status === 404) {
        return null;
      }
      if (response.status === 429) {
        const retryHeader = response.headers.get("Retry-After");
        const retrySeconds = Math.max(1, Number.parseFloat(retryHeader ?? "1") || 1);
        const waitMs = Math.ceil((retrySeconds + 0.5) * 1000);
        this.hostCooldownUntil.set(host, Date.now() + waitMs);
        if (attempt === maxRetries) return null;
        await sleep(waitMs);
        continue;
      }
      if (response.status >= 500) {
        if (attempt === maxRetries) return null;
        await sleep(Math.min(5000, 400 * 2 ** attempt + Math.random() * 250));
        continue;
      }
      // 400 / 401 / 403 -> nicht wiederholen
      if (response.status === 401 || response.status === 403) {
        throw new Error(`Riot API Auth-Fehler (${response.status}) auf ${host}`);
      }
      return null;
    }
    return null;
  }
}

async function readProAccounts(bucket: R2Bucket): Promise<ProAccount[]> {
  const obj = await bucket.get("pro_accounts.json");
  if (!obj) return [];
  try {
    const raw = (await obj.json()) as unknown;
    const list: unknown[] = Array.isArray(raw)
      ? raw
      : raw && typeof raw === "object" && Array.isArray((raw as { accounts?: unknown[] }).accounts)
        ? (raw as { accounts: unknown[] }).accounts
        : [];
    const accounts: ProAccount[] = [];
    for (const item of list) {
      if (!item || typeof item !== "object") continue;
      const rec = item as Record<string, unknown>;
      const puuid = typeof rec.puuid === "string" ? rec.puuid.trim() : "";
      const proName = typeof rec.proName === "string" ? rec.proName.trim() : "";
      if (!puuid || !proName) continue;
      accounts.push({
        puuid,
        platform: normalizePlatform(typeof rec.platform === "string" ? rec.platform : "EUW1"),
        proName,
        proTeam: typeof rec.proTeam === "string" && rec.proTeam.trim() ? rec.proTeam.trim() : null,
        role: normalizeRole(typeof rec.role === "string" ? rec.role : null),
      });
    }
    return accounts;
  } catch {
    return [];
  }
}

async function readLeaderboard(bucket: R2Bucket): Promise<LeaderboardFile | null> {
  const obj = await bucket.get("leaderboard.json");
  if (!obj) return null;
  try {
    return (await obj.json()) as LeaderboardFile;
  } catch {
    return null;
  }
}

async function readPreviousSpectate(
  bucket: R2Bucket
): Promise<{ file: ProSpectateFile | null; cursor: number }> {
  const obj = await bucket.get("pro_spectate.json");
  if (!obj) return { file: null, cursor: 0 };
  const rawCursor = Number.parseInt(obj.customMetadata?.cursor ?? "0", 10);
  const cursor = Number.isFinite(rawCursor) && rawCursor >= 0 ? rawCursor : 0;
  try {
    const file = (await obj.json()) as ProSpectateFile;
    return { file, cursor };
  } catch {
    return { file: null, cursor };
  }
}

function buildProGame(
  raw: RiotCurrentGameInfo,
  fallbackPlatform: string,
  proByPuuid: Map<string, ProAccount>,
  rankByPuuid: Map<string, RankSnapshot>,
  rankByRiotId: Map<string, RankSnapshot>
): ProGame {
  const platformId = normalizePlatform(raw.platformId || fallbackPlatform);
  const queueId = raw.gameQueueConfigId ?? 420;
  const gameStartTime = raw.gameStartTime && raw.gameStartTime > 0 ? raw.gameStartTime : Date.now();

  let knownPlayers = 0;
  const lps: number[] = [];
  const tiers: string[] = [];
  const participants: ProParticipant[] = [];

  for (const p of raw.participants ?? []) {
    const puuid = p.puuid && p.puuid.trim() ? p.puuid.trim() : null;
    const pro = puuid ? proByPuuid.get(puuid) : undefined;
    const rawRiotId = p.riotId && p.riotId.trim() ? p.riotId.trim() : p.summonerName?.trim() || null;

    const rankInfo =
      (puuid ? rankByPuuid.get(puuid) : undefined) ??
      (rawRiotId ? rankByRiotId.get(rawRiotId.toLowerCase()) : undefined);

    const tier = rankInfo?.tier ?? "CHALLENGER";
    const lp = rankInfo?.lp ?? 1000;
    const riotId = rawRiotId ?? rankInfo?.riotId ?? null;
    const isKnown = Boolean(pro);

    if (isKnown) {
      knownPlayers += 1;
    }
    lps.push(lp);
    tiers.push(tier);

    let role = pro?.role ?? null;
    if (!role && (p.spell1Id === 11 || p.spell2Id === 11)) {
      role = "JUNGLE";
    }

    participants.push({
      teamId: p.teamId,
      championId: p.championId,
      role,
      puuid,
      riotId,
      proName: pro?.proName ?? null,
      proTeam: pro?.proTeam ?? null,
      tier,
      lp,
      isKnown,
    });
  }

  const averageLp = lps.length > 0 ? Math.round(lps.reduce((a, b) => a + b, 0) / lps.length) : 1000;
  const avgWeight =
    tiers.length > 0
      ? tiers.reduce((acc, t) => acc + (TIER_WEIGHT[t] ?? 3), 0) / tiers.length
      : 3;
  const averageTier = avgWeight >= 2.5 ? "CHALLENGER" : avgWeight >= 1.5 ? "GRANDMASTER" : "MASTER";

  return {
    gameId: raw.gameId,
    platformId,
    gameStartTime,
    queueId,
    averageTier,
    averageLp,
    knownPlayers,
    participants,
  };
}

export async function runSpectatePoll(env: Env): Promise<{
  output: ProSpectateFile;
  nextCursor: number;
  requestsMade: number;
}> {
  if (!env.RIOT_API_KEY) {
    throw new Error("RIOT_API_KEY Secret ist im Cloudflare Worker nicht konfiguriert.");
  }

  const maxRequests = Math.max(
    1,
    Number.parseInt(env.MAX_REQUESTS_PER_RUN ?? "40", 10) || 40
  );
  const maxGameAgeMs =
    Math.max(15, Number.parseInt(env.MAX_GAME_AGE_MINUTES ?? "50", 10) || 50) * 60 * 1000;

  const [proAccounts, leaderboard, previous] = await Promise.all([
    readProAccounts(env.DATA_BUCKET),
    readLeaderboard(env.DATA_BUCKET),
    readPreviousSpectate(env.DATA_BUCKET),
  ]);

  const proByPuuid = new Map<string, ProAccount>();
  for (const acc of proAccounts) {
    proByPuuid.set(acc.puuid, acc);
  }

  const rankByPuuid = new Map<string, RankSnapshot>();
  const rankByRiotId = new Map<string, RankSnapshot>();
  const leaderboardCandidates: Array<{ puuid: string; platform: string }> = [];

  if (leaderboard?.platforms) {
    for (const [platformKey, entries] of Object.entries(leaderboard.platforms)) {
      const platform = normalizePlatform(platformKey);
      for (const entry of entries ?? []) {
        const snap: RankSnapshot = {
          tier: entry.tier || "CHALLENGER",
          lp: typeof entry.lp === "number" ? entry.lp : 1000,
          riotId: entry.riotId || undefined,
          platform,
        };
        if (entry.puuid) {
          rankByPuuid.set(entry.puuid, snap);
          if (!proByPuuid.has(entry.puuid) && entry.tier === "CHALLENGER") {
            leaderboardCandidates.push({ puuid: entry.puuid, platform });
          }
        }
        if (entry.riotId) {
          rankByRiotId.set(entry.riotId.toLowerCase(), snap);
        }
      }
    }
  }

  // Rotations-Pool: Primär alle Pro-Accounts, ergänzt um Challenger-PUUIDs aus leaderboard.json
  const pollPool: Array<{ puuid: string; platform: string }> = [
    ...proAccounts.map((a) => ({ puuid: a.puuid, platform: a.platform })),
    ...leaderboardCandidates,
  ];

  const poller = new SpectatorPoller(env.RIOT_API_KEY);
  const seenGameIds = new Set<number>();
  const checkedPuuids = new Set<string>();
  const activeGames: ProGame[] = [];
  const now = Date.now();

  // 1. Laufende Spiele aus dem vorherigen Zyklus re-validieren (kostet nur 1 Call pro Spiel)
  const prevGames = previous.file?.games ?? [];
  for (const oldGame of prevGames) {
    if (poller.requestsMade >= maxRequests) break;
    if (seenGameIds.has(oldGame.gameId)) continue;
    if (oldGame.gameStartTime > 0 && now - oldGame.gameStartTime > maxGameAgeMs) continue;

    const anchor =
      oldGame.participants.find((p) => p.isKnown && p.puuid) ??
      oldGame.participants.find((p) => Boolean(p.puuid));
    if (!anchor?.puuid) continue;

    checkedPuuids.add(anchor.puuid);
    const live = await poller.getActiveGame(oldGame.platformId, anchor.puuid);
    if (!live || (live.gameQueueConfigId ?? 420) !== 420) continue;

    seenGameIds.add(live.gameId);
    for (const part of live.participants ?? []) {
      if (part.puuid) checkedPuuids.add(part.puuid);
    }
    activeGames.push(
      buildProGame(live, oldGame.platformId, proByPuuid, rankByPuuid, rankByRiotId)
    );
  }

  // 2. Rotierende Abfrage über den Poll-Pool mit dem verbleibenden Subrequest-Budget
  let nextCursor = pollPool.length > 0 ? previous.cursor % pollPool.length : 0;
  let inspected = 0;

  while (
    inspected < pollPool.length &&
    poller.requestsMade < maxRequests
  ) {
    const idx = (nextCursor + inspected) % pollPool.length;
    inspected += 1;
    const candidate = pollPool[idx];

    if (!candidate.puuid || checkedPuuids.has(candidate.puuid)) {
      continue;
    }
    checkedPuuids.add(candidate.puuid);

    const live = await poller.getActiveGame(candidate.platform, candidate.puuid);
    if (!live || (live.gameQueueConfigId ?? 420) !== 420) {
      continue;
    }
    if (seenGameIds.has(live.gameId)) {
      continue;
    }
    seenGameIds.add(live.gameId);

    for (const part of live.participants ?? []) {
      if (part.puuid) {
        checkedPuuids.add(part.puuid);
      }
    }

    activeGames.push(
      buildProGame(live, candidate.platform, proByPuuid, rankByPuuid, rankByRiotId)
    );
  }

  if (pollPool.length > 0) {
    nextCursor = (nextCursor + inspected) % pollPool.length;
  }

  // Sortierung laut Methodik (§2.6): meiste bekannte Pros zuerst, danach höchster LP-Schnitt
  activeGames.sort(
    (a, b) => b.knownPlayers - a.knownPlayers || b.averageLp - a.averageLp
  );

  const platforms =
    leaderboard?.meta?.platforms && leaderboard.meta.platforms.length > 0
      ? leaderboard.meta.platforms
      : Array.from(
          new Set([
            ...proAccounts.map((a) => a.platform),
            ...activeGames.map((g) => g.platformId),
          ])
        ).sort();

  const patch = leaderboard?.meta?.patch || env.DEFAULT_PATCH || "16.23";

  const output: ProSpectateFile = {
    meta: {
      schemaVersion: 1,
      patch,
      generatedAt: isoUtcNow(),
      sample: false,
      platforms: platforms.length > 0 ? platforms : ["EUW1", "KR", "NA1"],
      rankFloor: "CHALLENGER",
      matchesAnalyzed: activeGames.length,
    },
    games: activeGames,
  };

  await env.DATA_BUCKET.put("pro_spectate.json", JSON.stringify(output), {
    httpMetadata: {
      contentType: "application/json; charset=utf-8",
      cacheControl: "max-age=60",
    },
    customMetadata: {
      cursor: String(nextCursor),
      updatedAt: output.meta.generatedAt,
    },
  });

  return {
    output,
    nextCursor,
    requestsMade: poller.requestsMade,
  };
}

export default {
  async scheduled(
    _controller: ScheduledController,
    env: Env,
    ctx: ExecutionContext
  ): Promise<void> {
    ctx.waitUntil(
      runSpectatePoll(env).then((res) => {
        console.log(
          `pro_spectate.json aktualisiert: ${res.output.games.length} Spiele, ${res.requestsMade} Riot-Requests, nextCursor=${res.nextCursor}`
        );
      })
    );
  },

  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/pro_spectate.json" || url.pathname === "/") {
      const obj = await env.DATA_BUCKET.get("pro_spectate.json");
      if (!obj) {
        return new Response(JSON.stringify({ error: "pro_spectate.json noch nicht vorhanden" }), {
          status: 404,
          headers: { "Content-Type": "application/json; charset=utf-8" },
        });
      }
      const headers = new Headers();
      obj.writeHttpMetadata(headers);
      headers.set("Content-Type", "application/json; charset=utf-8");
      headers.set("Cache-Control", "max-age=60");
      headers.set("ETag", obj.httpEtag);
      return new Response(obj.body, { status: 200, headers });
    }
    return new Response("Not Found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;
