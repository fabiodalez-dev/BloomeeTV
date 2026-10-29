"""Per-user library: favorites, playlists, history, stats, saved state.
Items arriving from the browser are rebuilt field by field, never stored as sent."""
import json
import re

from . import db

VIDEO = re.compile(r'^[A-Za-z0-9_-]{11}$')
BROWSE = re.compile(r'^[A-Za-z0-9_-]{2,80}$')
IMAGE = re.compile(r'^https://([a-z0-9-]+\.)*(googleusercontent\.com|ytimg\.com|ggpht\.com)/[^\s"<>]{1,600}$')
KINDS = ('song', 'album', 'artist', 'playlist')
STATE_NAMES = ('settings', 'queue', 'home')
MAX_PLAYLIST = 5000


class Invalid(ValueError):
    pass


def _str(v, n=300):
    return v.strip()[:n] if isinstance(v, str) else ''


def _ref(v):
    if not isinstance(v, dict):
        return None
    name = _str(v.get('name'), 200)
    if not name:
        return None
    i = v.get('id')
    return {'name': name, 'id': i if isinstance(i, str) and BROWSE.match(i) else None}


def clean_item(it):
    """A song, album, artist or playlist as the UI shows it."""
    if not isinstance(it, dict):
        raise Invalid('Elemento non valido')
    kind = it.get('kind')
    if kind not in KINDS:
        raise Invalid('Tipo non valido')
    out = {'kind': kind, 'title': _str(it.get('title'))}
    if not out['title']:
        raise Invalid('Titolo mancante')
    if kind == 'song':
        if not isinstance(it.get('videoId'), str) or not VIDEO.match(it['videoId']):
            raise Invalid('Brano non valido')
        out['videoId'] = it['videoId']
    else:
        if not isinstance(it.get('browseId'), str) or not BROWSE.match(it['browseId']):
            raise Invalid('Elemento non valido')
        out['browseId'] = it['browseId']
    out['subtitle'] = _str(it.get('subtitle'))
    out['artists'] = [a for a in (_ref(a) for a in (it.get('artists') or [])[:10]) if a]
    out['album'] = _ref(it.get('album'))
    thumb = it.get('thumbnail')
    out['thumbnail'] = thumb if isinstance(thumb, str) and IMAGE.match(thumb) else None
    d = it.get('duration')
    out['duration'] = int(d) if isinstance(d, (int, float)) and 0 < d < 86400 else None
    return out


def item_key(it):
    return it['videoId'] if it['kind'] == 'song' else it['browseId']


# Favorites

def favorites(con, uid):
    return [dict(json.loads(r['data']), addedAt=r['added'])
            for r in con.execute('SELECT data, added FROM favorites WHERE user_id=? ORDER BY added DESC', (uid,))]


def add_favorite(con, uid, item):
    it = clean_item(item)
    con.execute('INSERT OR REPLACE INTO favorites(user_id, key, kind, data, added) VALUES(?,?,?,?,?)',
                (uid, item_key(it), it['kind'], db.dumps(it), db.now()))
    return it


def add_favorites(con, uid, items):
    """Many favorites at once (import): invalid items are skipped, existing ones
    keep their date. The first item ends up newest, as in the source list."""
    clean = []
    for it in items:
        try:
            clean.append(clean_item(it))
        except Invalid:
            continue
    t = db.now()
    con.execute('BEGIN IMMEDIATE')
    try:
        before = con.total_changes
        con.executemany('INSERT OR IGNORE INTO favorites(user_id, key, kind, data, added) VALUES(?,?,?,?,?)',
                        [(uid, item_key(it), it['kind'], db.dumps(it), t - n) for n, it in enumerate(clean)])
        added = con.total_changes - before
        con.execute('COMMIT')
    except Exception:
        con.execute('ROLLBACK')
        raise
    return added


def remove_favorite(con, uid, key):
    con.execute('DELETE FROM favorites WHERE user_id=? AND key=?', (uid, key))


# Playlists

def _playlist_row(con, uid, pid):
    row = con.execute('SELECT * FROM playlists WHERE id=? AND user_id=?', (pid, uid)).fetchone()
    if not row:
        raise LookupError('Playlist non trovata')
    return row


def playlists(con, uid):
    rows = con.execute(
        'SELECT p.*, (SELECT COUNT(*) FROM playlist_items i WHERE i.playlist_id=p.id) AS count, '
        '(SELECT data FROM playlist_items i WHERE i.playlist_id=p.id ORDER BY pos LIMIT 1) AS first '
        'FROM playlists p WHERE user_id=? ORDER BY updated DESC', (uid,))
    out = []
    for r in rows:
        first = json.loads(r['first']) if r['first'] else None
        out.append({'id': r['id'], 'name': r['name'], 'description': r['description'], 'count': r['count'],
                    'thumbnail': first and first.get('thumbnail'), 'updated': r['updated']})
    return out


def playlist(con, uid, pid):
    row = _playlist_row(con, uid, pid)
    items = [json.loads(r['data']) for r in con.execute('SELECT data FROM playlist_items WHERE playlist_id=? ORDER BY pos', (pid,))]
    return {'id': row['id'], 'name': row['name'], 'description': row['description'], 'updated': row['updated'], 'items': items}


def create_playlist(con, uid, name, description='', items=()):
    name = _str(name, 120)
    if not name:
        raise Invalid('Dai un nome alla playlist')
    t = db.now()
    pid = con.execute('INSERT INTO playlists(user_id, name, description, created, updated) VALUES(?,?,?,?,?)',
                      (uid, name, _str(description, 1000), t, t)).lastrowid
    if items:
        set_items(con, uid, pid, items)
    return pid


def update_playlist(con, uid, pid, name=None, description=None):
    row = _playlist_row(con, uid, pid)
    name = _str(name, 120) if name is not None else row['name']
    if not name:
        raise Invalid('Dai un nome alla playlist')
    desc = _str(description, 1000) if description is not None else row['description']
    con.execute('UPDATE playlists SET name=?, description=?, updated=? WHERE id=?', (name, desc, db.now(), pid))


def delete_playlist(con, uid, pid):
    _playlist_row(con, uid, pid)
    con.execute('DELETE FROM playlists WHERE id=?', (pid,))


def set_items(con, uid, pid, items):
    """Replace the whole track list: covers reorder, removal and duplicates in one call."""
    _playlist_row(con, uid, pid)
    if not isinstance(items, list) or len(items) > MAX_PLAYLIST:
        raise Invalid('Al massimo %d brani per playlist' % MAX_PLAYLIST)
    clean = [clean_item(i) for i in items]
    if any(i['kind'] != 'song' for i in clean):
        raise Invalid('Una playlist contiene solo brani')
    con.execute('BEGIN IMMEDIATE')
    try:
        con.execute('DELETE FROM playlist_items WHERE playlist_id=?', (pid,))
        con.executemany('INSERT INTO playlist_items(playlist_id, pos, video_id, data) VALUES(?,?,?,?)',
                        [(pid, n, i['videoId'], db.dumps(i)) for n, i in enumerate(clean)])
        con.execute('UPDATE playlists SET updated=? WHERE id=?', (db.now(), pid))
        con.execute('COMMIT')
    except Exception:
        con.execute('ROLLBACK')
        raise


def append_items(con, uid, pid, items):
    _playlist_row(con, uid, pid)
    if not isinstance(items, list) or not items:
        raise Invalid('Nessun brano')
    clean = [clean_item(i) for i in items]
    if any(i['kind'] != 'song' for i in clean):
        raise Invalid('Una playlist contiene solo brani')
    start = con.execute('SELECT COALESCE(MAX(pos)+1, 0) FROM playlist_items WHERE playlist_id=?', (pid,)).fetchone()[0]
    if start + len(clean) > MAX_PLAYLIST:
        raise Invalid('Al massimo %d brani per playlist' % MAX_PLAYLIST)
    con.executemany('INSERT INTO playlist_items(playlist_id, pos, video_id, data) VALUES(?,?,?,?)',
                    [(pid, start + n, i['videoId'], db.dumps(i)) for n, i in enumerate(clean)])
    con.execute('UPDATE playlists SET updated=? WHERE id=?', (db.now(), pid))
    return start + len(clean)


# History and stats

def log_play(con, uid, item, seconds):
    it = clean_item(item)
    if it['kind'] != 'song':
        raise Invalid('Solo brani')
    seconds = max(0, min(int(seconds or 0), 86400))
    t = db.now()
    # One entry per listen: a later report for the same track within its
    # duration extends the open entry instead of adding a new one.
    last = con.execute('SELECT id, video_id, played_at FROM history WHERE user_id=? ORDER BY played_at DESC, id DESC LIMIT 1', (uid,)).fetchone()
    span = (it['duration'] or 600) + 120
    if last and last['video_id'] == it['videoId'] and t - last['played_at'] < span:
        con.execute('UPDATE history SET seconds=MAX(seconds, ?) WHERE id=?', (seconds, last['id']))
    else:
        con.execute('INSERT INTO history(user_id, video_id, data, played_at, seconds) VALUES(?,?,?,?,?)',
                    (uid, it['videoId'], db.dumps(it), t, seconds))


def history(con, uid, limit=100, before=None):
    limit = max(1, min(int(limit), 500))
    q = 'SELECT data, played_at, seconds FROM history WHERE user_id=?'
    args = [uid]
    if before:
        q += ' AND played_at<?'
        args.append(int(before))
    q += ' ORDER BY played_at DESC, id DESC LIMIT ?'
    args.append(limit)
    return [dict(json.loads(r['data']), playedAt=r['played_at'], seconds=r['seconds']) for r in con.execute(q, args)]


def stats(con, uid, since):
    """Listening recap since a timestamp: minutes, top tracks, artists, albums, hours."""
    rows = con.execute('SELECT video_id, data, played_at, seconds FROM history WHERE user_id=? AND played_at>=? AND seconds>=30',
                       (uid, int(since))).fetchall()
    tracks, artists, albums, hours, days = {}, {}, {}, [0] * 24, {}
    total = 0
    import time as _t
    for r in rows:
        it = json.loads(r['data'])
        s = r['seconds']
        total += s
        t = tracks.setdefault(r['video_id'], {'item': it, 'plays': 0, 'seconds': 0})
        t['plays'] += 1
        t['seconds'] += s
        for a in it.get('artists') or []:
            k = a.get('id') or a['name'].lower()
            e = artists.setdefault(k, {'name': a['name'], 'id': a.get('id'), 'thumbnail': it.get('thumbnail'), 'plays': 0, 'seconds': 0})
            e['plays'] += 1
            e['seconds'] += s
        if it.get('album'):
            al = it['album']
            k = al.get('id') or al['name'].lower()
            e = albums.setdefault(k, {'name': al['name'], 'id': al.get('id'), 'thumbnail': it.get('thumbnail'),
                                      'artist': (it.get('artists') or [{}])[0].get('name'), 'plays': 0, 'seconds': 0})
            e['plays'] += 1
            e['seconds'] += s
        lt = _t.localtime(r['played_at'])
        hours[lt.tm_hour] += s
        day = _t.strftime('%Y-%m-%d', lt)
        days[day] = days.get(day, 0) + s

    def top(d, n):
        return sorted(d.values(), key=lambda e: (e['seconds'], e['plays']), reverse=True)[:n]

    return {'since': int(since), 'plays': len(rows), 'minutes': total // 60, 'tracks': top(tracks, 50),
            'artists': top(artists, 30), 'albums': top(albums, 30), 'hours': [h // 60 for h in hours],
            'days': [{'day': k, 'minutes': v // 60} for k, v in sorted(days.items())],
            'uniqueTracks': len(tracks), 'uniqueArtists': len(artists)}


# Free-form per-user state (settings, queue, home layout), bounded in size.

def get_state(con, uid, name):
    row = con.execute('SELECT data, updated FROM user_state WHERE user_id=? AND name=?', (uid, name)).fetchone()
    return (json.loads(row['data']), row['updated']) if row else (None, None)


def set_state(con, uid, name, data):
    if name not in STATE_NAMES:
        raise Invalid('Stato sconosciuto')
    raw = db.dumps(data)
    if len(raw) > 512 * 1024:
        raise Invalid('Dati troppo grandi')
    t = db.now()
    con.execute('INSERT OR REPLACE INTO user_state(user_id, name, data, updated) VALUES(?,?,?,?)', (uid, name, raw, t))
    return t
