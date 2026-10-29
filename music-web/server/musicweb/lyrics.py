"""Synced lyrics, from the same sources Mochy Music reads.

Order: BetterLyrics (word-by-word TTML), LRCLIB (line-synced LRC, then plain).
Every answer becomes {source, synced, words, lines:[{t, end, text, words?}]},
times in seconds.
"""
import json
import re
import xml.etree.ElementTree as ET
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from . import db

UA = 'FabioMusic/1.0 (+https://music.fabiodalez.it)'
TTL_FOUND = 30 * 86400
TTL_MISSING = 86400
TTML = '{http://www.w3.org/ns/ttml}'


def _get(url, timeout=12):
    with urlopen(Request(url, headers={'User-Agent': UA, 'Accept': 'application/json'}), timeout=timeout) as r:
        return json.loads(r.read().decode('utf-8'))


def ttml_time(value):
    """TTML clock values: "9.731", "1:02.5", "1:02:03.25", "12.3s"."""
    if not value:
        return None
    value = value.strip().rstrip('s')
    try:
        parts = [float(p) for p in value.split(':')]
    except ValueError:
        return None
    seconds = 0.0
    for p in parts:
        seconds = seconds * 60 + p
    return round(seconds, 3)


def parse_ttml(text):
    # Remote XML: no DTD at all (so no entity expansion), and a size bound.
    if not text or len(text) > 2_000_000 or '<!DOCTYPE' in text or '<!ENTITY' in text:
        return []
    root = ET.fromstring(text)
    lines = []
    for p in root.iter(TTML + 'p'):
        words = []
        for span in p.iter(TTML + 'span'):
            # Background vocals ride in nested spans with their own words: keep
            # only spans that carry text directly.
            if span.text and span.get('begin'):
                tail = ' ' if (span.tail or '').startswith(' ') else ''
                words.append({'t': ttml_time(span.get('begin')), 'end': ttml_time(span.get('end')), 'text': span.text + tail})
        line_text = ''.join(w['text'] for w in words).strip() if words else ''.join(p.itertext()).strip()
        if not line_text:
            continue
        line = {'t': ttml_time(p.get('begin')), 'end': ttml_time(p.get('end')), 'text': line_text}
        if words:
            line['words'] = words
        lines.append(line)
    lines.sort(key=lambda l: l['t'] or 0)
    return lines


LRC_LINE = re.compile(r'^((?:\[\d+:\d+(?:[.:]\d+)?\])+)(.*)$')
LRC_STAMP = re.compile(r'\[(\d+):(\d+)(?:[.:](\d+))?\]')


def parse_lrc(text):
    lines = []
    for raw in text.splitlines():
        m = LRC_LINE.match(raw.strip())
        if not m:
            continue
        body = m.group(2).strip()
        for mm, ss, frac in LRC_STAMP.findall(m.group(1)):
            t = int(mm) * 60 + int(ss) + (int(frac) / (10 ** len(frac)) if frac else 0)
            lines.append({'t': round(t, 3), 'end': None, 'text': body})
    lines.sort(key=lambda l: l['t'])
    for a, b in zip(lines, lines[1:]):
        a['end'] = b['t']
    return [l for l in lines if l['text']] if any(l['text'] for l in lines) else []


def better_lyrics(title, artist, duration, album):
    q = {'s': title, 'a': artist}
    if duration:
        q['d'] = int(duration)
    if album:
        q['al'] = album
    try:
        data = _get('https://lyrics-api.boidu.dev/getLyrics?' + urlencode(q))
        lines = parse_ttml(data.get('ttml') or '')
    except Exception:
        return None
    if not lines:
        return None
    return {'source': 'BetterLyrics', 'synced': True, 'words': any('words' in l for l in lines), 'lines': lines}


def lrclib(title, artist, duration, album):
    q = {'track_name': title, 'artist_name': artist}
    if duration:
        q['duration'] = int(duration)
    if album:
        q['album_name'] = album
    data = None
    try:
        data = _get('https://lrclib.net/api/get?' + urlencode(q))
    except Exception:
        try:
            found = _get('https://lrclib.net/api/search?' + urlencode({'track_name': title, 'artist_name': artist}))
            if duration:
                found = [f for f in found if abs((f.get('duration') or 0) - duration) <= 5]
            data = found[0] if found else None
        except Exception:
            data = None
    if not data:
        return None
    if data.get('syncedLyrics'):
        lines = parse_lrc(data['syncedLyrics'])
        if lines:
            return {'source': 'LRCLIB', 'synced': True, 'words': False, 'lines': lines}
    if data.get('plainLyrics'):
        lines = [{'t': None, 'end': None, 'text': l} for l in data['plainLyrics'].splitlines()]
        return {'source': 'LRCLIB', 'synced': False, 'words': False, 'lines': lines}
    return None


def clean_title(title):
    """"Song (feat. X) [Official Video]" → "Song": the sources match on the bare title."""
    t = re.sub(r'\s*[\(\[][^)\]]*(official|video|audio|lyric|visualizer|remaster|feat\.|ft\.)[^)\]]*[\)\]]', '', title, flags=re.I)
    return t.strip() or title


def find(con, video, title, artist, duration=None, album=None):
    key = 'v:' + video if video else 'q:%s|%s|%s' % (title.lower(), artist.lower(), duration or '')
    row = con.execute('SELECT data, at FROM lyrics_cache WHERE key=?', (key,)).fetchone()
    if row:
        data = json.loads(row['data'])
        if db.now() - row['at'] < (TTL_FOUND if data else TTL_MISSING):
            return data
    title = clean_title(title)
    artist = artist.split(',')[0].split(' & ')[0].strip()
    result = better_lyrics(title, artist, duration, album) or lrclib(title, artist, duration, album)
    con.execute('INSERT OR REPLACE INTO lyrics_cache(key, data, at) VALUES(?,?,?)', (key, db.dumps(result), db.now()))
    return result
