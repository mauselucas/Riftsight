"""SQLite store for compact matches + timeline features (idempotent, resumable between CI runs)."""
from __future__ import annotations

import json
import sqlite3
import time
import zlib
from pathlib import Path
from typing import Any, Iterator

try:  # zstd keeps the GitHub Actions cache small; zlib keeps tests dependency-free.
    import zstandard as _zstd

    _C = _zstd.ZstdCompressor(level=9)
    _D = _zstd.ZstdDecompressor()

    def _pack(obj: Any) -> bytes:
        return b"Z" + _C.compress(json.dumps(obj, separators=(",", ":")).encode())

    def _unpack(blob: bytes) -> Any:
        if blob[:1] == b"Z":
            return json.loads(_D.decompress(blob[1:]))
        return json.loads(zlib.decompress(blob[1:]))
except ImportError:  # pragma: no cover
    def _pack(obj: Any) -> bytes:
        return b"L" + zlib.compress(json.dumps(obj, separators=(",", ":")).encode(), 9)

    def _unpack(blob: bytes) -> Any:
        return json.loads(zlib.decompress(blob[1:]))


SCHEMA = """
CREATE TABLE IF NOT EXISTS matches (
    match_id TEXT PRIMARY KEY,
    platform TEXT NOT NULL,
    patch TEXT NOT NULL,
    mode TEXT NOT NULL,
    bucket TEXT NOT NULL,
    creation INTEGER NOT NULL,
    payload BLOB NOT NULL
);
CREATE INDEX IF NOT EXISTS matches_patch_mode ON matches(patch, mode);
CREATE TABLE IF NOT EXISTS timelines (match_id TEXT PRIMARY KEY, payload BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS skipped (match_id TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS seeds (
    puuid TEXT PRIMARY KEY, platform TEXT NOT NULL, bucket TEXT NOT NULL, crawled_at INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS riot_ids (puuid TEXT PRIMARY KEY, riot_id TEXT NOT NULL, fetched_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


class Store:
    def __init__(self, path: Path | str):
        if str(path) != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path))
        self.db.executescript(SCHEMA)
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(seeds)")}
        if "priority" not in columns:
            self.db.execute("ALTER TABLE seeds ADD COLUMN priority INTEGER DEFAULT 0")

    def close(self) -> None:
        self.db.commit()
        self.db.close()

    # Matches -----------------------------------------------------------------------------

    def has_match(self, match_id: str) -> bool:
        row = self.db.execute(
            "SELECT 1 FROM matches WHERE match_id = ? UNION SELECT 1 FROM skipped WHERE match_id = ?", (match_id, match_id)
        ).fetchone()
        return row is not None

    def put_match(self, record: dict[str, Any]) -> None:
        self.db.execute(
            "INSERT OR REPLACE INTO matches VALUES (?, ?, ?, ?, ?, ?, ?)",
            (record["id"], record["platform"], record["patch"], record["mode"], record["bucket"], record["creation"], _pack(record)),
        )

    def skip_match(self, match_id: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO skipped VALUES (?)", (match_id,))

    def put_timeline(self, match_id: str, features: dict[str, Any]) -> None:
        self.db.execute("INSERT OR REPLACE INTO timelines VALUES (?, ?)", (match_id, _pack(features)))

    def commit(self) -> None:
        self.db.commit()

    def matches(self, patch: str, mode: str | None = None, with_timelines: bool = True) -> Iterator[dict[str, Any]]:
        """Yields compact matches; ``m['tl']`` holds timeline features when available."""
        sql = "SELECT m.payload, t.payload FROM matches m LEFT JOIN timelines t ON t.match_id = m.match_id WHERE m.patch = ?"
        args: list[Any] = [patch]
        if mode:
            sql += " AND m.mode = ?"
            args.append(mode)
        for payload, timeline in self.db.execute(sql, args):
            record = _unpack(payload)
            record["tl"] = _unpack(timeline) if (timeline and with_timelines) else None
            yield record

    def recent_matches(self, since_ms: int, mode: str = "ranked") -> Iterator[dict[str, Any]]:
        for (payload,) in self.db.execute("SELECT payload FROM matches WHERE creation >= ? AND mode = ?", (since_ms, mode)):
            yield _unpack(payload)

    def count(self, patch: str, mode: str | None = None) -> int:
        if mode:
            return self.db.execute("SELECT COUNT(*) FROM matches WHERE patch = ? AND mode = ?", (patch, mode)).fetchone()[0]
        return self.db.execute("SELECT COUNT(*) FROM matches WHERE patch = ?", (patch,)).fetchone()[0]

    def patches(self) -> list[str]:
        rows = self.db.execute("SELECT DISTINCT patch FROM matches").fetchall()
        return sorted((r[0] for r in rows), key=lambda p: tuple(int(x) for x in p.split(".") if x.isdigit()))

    # Seeds -------------------------------------------------------------------------------

    def add_seed(self, puuid: str, platform: str, bucket: str, priority: int = 0) -> None:
        self.db.execute("INSERT OR IGNORE INTO seeds (puuid, platform, bucket) VALUES (?, ?, ?)", (puuid, platform, bucket))
        if priority:
            self.db.execute("UPDATE seeds SET priority = MAX(COALESCE(priority, 0), ?) WHERE puuid = ?", (priority, puuid))

    def next_focus_seeds(self, platform: str, limit: int, older_than_s: int = 6 * 3600) -> list[tuple[str, str]]:
        """Priority seeds (players seen on a focus champion), least recently crawled first."""
        cutoff = int(time.time()) - older_than_s
        rows = self.db.execute(
            "SELECT puuid, bucket FROM seeds WHERE platform = ? AND priority > 0 AND crawled_at < ? "
            "ORDER BY priority DESC, crawled_at, RANDOM() LIMIT ?",
            (platform, cutoff, limit),
        ).fetchall()
        return [(r[0], r[1]) for r in rows]

    def next_seeds(self, platform: str, bucket: str, limit: int, older_than_s: int = 6 * 3600) -> list[str]:
        cutoff = int(time.time()) - older_than_s
        rows = self.db.execute(
            "SELECT puuid FROM seeds WHERE platform = ? AND bucket = ? AND crawled_at < ? ORDER BY crawled_at, RANDOM() LIMIT ?",
            (platform, bucket, cutoff, limit),
        ).fetchall()
        return [r[0] for r in rows]

    def mark_crawled(self, puuid: str) -> None:
        self.db.execute("UPDATE seeds SET crawled_at = ? WHERE puuid = ?", (int(time.time()), puuid))

    # Riot ID cache (7 days) ----------------------------------------------------------------

    def riot_id(self, puuid: str, max_age_s: int = 7 * 86400) -> str | None:
        row = self.db.execute("SELECT riot_id, fetched_at FROM riot_ids WHERE puuid = ?", (puuid,)).fetchone()
        if row and row[1] >= time.time() - max_age_s:
            return row[0]
        return None

    def put_riot_id(self, puuid: str, riot_id: str) -> None:
        self.db.execute("INSERT OR REPLACE INTO riot_ids VALUES (?, ?, ?)", (puuid, riot_id, int(time.time())))

    # Key/value -------------------------------------------------------------------------------

    def get(self, key: str) -> str | None:
        row = self.db.execute("SELECT value FROM kv WHERE key = ?", (key,)).fetchone()
        return row[0] if row else None

    def set(self, key: str, value: str) -> None:
        self.db.execute("INSERT OR REPLACE INTO kv VALUES (?, ?)", (key, value))
