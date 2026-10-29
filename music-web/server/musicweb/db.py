"""SQLite storage. One connection per request; WAL lets the LiteSpeed worker
processes read while another one writes."""
import json
import sqlite3
import time

from . import config

SCHEMA = [
    # 1: accounts, library, caches
    """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        display_name TEXT NOT NULL,
        pw_hash TEXT NOT NULL,
        is_admin INTEGER NOT NULL DEFAULT 0,
        disabled INTEGER NOT NULL DEFAULT 0,
        created INTEGER NOT NULL
    );
    CREATE TABLE invites (
        code TEXT PRIMARY KEY,
        created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
        created INTEGER NOT NULL,
        expires INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        used_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
        used_at INTEGER
    );
    CREATE TABLE sessions (
        token_hash TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        agent TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX sessions_user ON sessions(user_id);
    CREATE TABLE favorites (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        key TEXT NOT NULL,
        kind TEXT NOT NULL,
        data TEXT NOT NULL,
        added INTEGER NOT NULL,
        PRIMARY KEY (user_id, key)
    );
    CREATE TABLE playlists (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
    );
    CREATE INDEX playlists_user ON playlists(user_id);
    CREATE TABLE playlist_items (
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        pos INTEGER NOT NULL,
        video_id TEXT NOT NULL,
        data TEXT NOT NULL,
        PRIMARY KEY (playlist_id, pos)
    );
    CREATE TABLE history (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        video_id TEXT NOT NULL,
        data TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        seconds INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX history_user_time ON history(user_id, played_at);
    CREATE TABLE user_state (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        data TEXT NOT NULL,
        updated INTEGER NOT NULL,
        PRIMARY KEY (user_id, name)
    );
    CREATE TABLE yt_accounts (
        user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
        secret BLOB NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        updated INTEGER NOT NULL
    );
    CREATE TABLE streams (
        video TEXT NOT NULL,
        alt INTEGER NOT NULL,
        url TEXT NOT NULL,
        ua TEXT NOT NULL,
        client TEXT NOT NULL,
        mime TEXT NOT NULL,
        size INTEGER NOT NULL,
        expire INTEGER NOT NULL,
        PRIMARY KEY (video, alt)
    );
    CREATE TABLE refused (
        video TEXT PRIMARY KEY,
        until INTEGER NOT NULL,
        reason TEXT NOT NULL
    );
    CREATE TABLE kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        at INTEGER NOT NULL
    );
    CREATE TABLE rate (
        key TEXT PRIMARY KEY,
        window INTEGER NOT NULL,
        count INTEGER NOT NULL
    );
    CREATE TABLE lyrics_cache (
        key TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        at INTEGER NOT NULL
    );
    """,
]


def connect(path=None):
    config.ensure_dirs()
    con = sqlite3.connect(path or config.DB_PATH, timeout=15, isolation_level=None)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA journal_mode=WAL')
    con.execute('PRAGMA foreign_keys=ON')
    con.execute('PRAGMA busy_timeout=15000')
    migrate(con)
    return con


def migrate(con):
    version = con.execute('PRAGMA user_version').fetchone()[0]
    if version >= len(SCHEMA):
        return
    con.execute('BEGIN IMMEDIATE')
    try:
        # Another worker may have migrated while this one waited for the lock.
        version = con.execute('PRAGMA user_version').fetchone()[0]
        for i in range(version, len(SCHEMA)):
            for stmt in SCHEMA[i].split(';'):
                if stmt.strip():
                    con.execute(stmt)
            con.execute('PRAGMA user_version=%d' % (i + 1))
        con.execute('COMMIT')
    except Exception:
        con.execute('ROLLBACK')
        raise


def now():
    return int(time.time())


def dumps(obj):
    return json.dumps(obj, separators=(',', ':'), ensure_ascii=False)


def kv_get(con, key, ttl):
    row = con.execute('SELECT value, at FROM kv WHERE key=?', (key,)).fetchone()
    if row and now() - row['at'] < ttl:
        return row['value']
    return None


def kv_set(con, key, value):
    con.execute('INSERT INTO kv(key, value, at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, at=excluded.at',
                (key, value, now()))


def hit_rate(con, key, limit, window):
    """Count one event in a fixed window; True while the count stays within limit."""
    start = now() // window * window
    con.execute('INSERT INTO rate(key, window, count) VALUES(?,?,1) '
                'ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window=excluded.window THEN count+1 ELSE 1 END, window=excluded.window',
                (key, start))
    count = con.execute('SELECT count FROM rate WHERE key=?', (key,)).fetchone()[0]
    return count <= limit
