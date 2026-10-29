"""YouTube Music engine, ported from the Bloomee webOS bridge (webos/bridge.py).

InnerTube page requests go through a fixed list of endpoints and fields; the
browser parses the answers (ui/src/lib/yt.js). Audio URLs are resolved here and
never leave the server: googlevideo binds them to the IP that asked for them.
"""
import gzip
import hashlib
import json
import re
import socket
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from . import db

# googlevideo answers with an IPv6 address first; on hosts without an IPv6
# route every connection would wait for the timeout before trying IPv4.
_getaddrinfo = getattr(socket.getaddrinfo, 'original', socket.getaddrinfo)


def _ipv4_first(*args, **kwargs):
    return sorted(_getaddrinfo(*args, **kwargs), key=lambda a: a[0] != socket.AF_INET)


_ipv4_first.original = _getaddrinfo
socket.getaddrinfo = _ipv4_first

ORIGIN = 'https://music.youtube.com'
VERSION = '1.20261020.10.00'
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
ENDPOINTS = ('search', 'browse', 'next', 'music/get_search_suggestions', 'account/account_menu')
FIELDS = ('query', 'input', 'params', 'continuation', 'browseId', 'videoId', 'playlistId')

# Clients whose player answers carry direct, unsigned audio URLs. VISIONOS,
# with an anonymous visitorData, serves URLs that play to the end; since
# October 2026 googlevideo refuses IOS and ANDROID_VR URLs after the first
# megabyte, so they are only a fallback.
VISIONOS_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'
PLAYERS = [
    ({'clientName': 'VISIONOS', 'clientVersion': '1.02', 'deviceMake': 'Apple', 'deviceModel': 'RealityDevice17,1',
      'userAgent': VISIONOS_UA, 'osName': 'visionOS', 'osVersion': '26.5.23O471'}, VISIONOS_UA, '101'),
    ({'clientName': 'IOS', 'clientVersion': '20.10.4', 'deviceMake': 'Apple', 'deviceModel': 'iPhone16,2',
      'osName': 'iPhone', 'osVersion': '18.3.2.22D82'},
     'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)', '5'),
    ({'clientName': 'ANDROID_VR', 'clientVersion': '1.65.10', 'deviceMake': 'Oculus', 'deviceModel': 'Quest 3',
      'androidSdkVersion': 32, 'osName': 'Android', 'osVersion': '12L'},
     'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip', '28'),
]
VISITOR_TTL = 6 * 3600
REFUSED_TTL = 600


class Unavailable(Exception):
    """YouTube refuses the video (region, age, bot check): the reason is shown to the user."""


def visitor_data(con):
    """Anonymous visitor id, read from the youtube.com page as a browser gets it.
    Without it VISIONOS answers "Accedi per confermare di non essere un bot"."""
    cached = db.kv_get(con, 'visitor', VISITOR_TTL)
    if cached:
        return cached
    try:
        with urlopen(Request('https://www.youtube.com/', headers={'User-Agent': UA, 'Accept-Language': 'it-IT'}), timeout=15) as r:
            page = r.read().decode('utf-8', 'replace')
        m = re.search(r'"VISITOR_DATA":"([^"]+)"', page)
    except Exception:
        m = None
    if m:
        db.kv_set(con, 'visitor', m.group(1))
        return m.group(1)
    return None


def sapisid(cookie):
    for part in (cookie or '').split(';'):
        kv = part.strip().split('=', 1)
        if len(kv) == 2 and kv[0] in ('SAPISID', '__Secure-3PAPISID'):
            return kv[1]
    return None


def body_for(endpoint, data, account):
    """Bounded InnerTube body: fixed endpoints and fields, context set here."""
    if endpoint not in ENDPOINTS:
        raise ValueError('Percorso non consentito')
    if not isinstance(data, dict):
        raise ValueError('Richiesta non valida')
    body = {}
    for k in FIELDS:
        v = data.get(k)
        if v is None:
            continue
        if not isinstance(v, str) or len(v) > 8000:
            raise ValueError('Richiesta non valida')
        body[k] = v
    client = {'clientName': 'WEB_REMIX', 'clientVersion': VERSION, 'hl': 'it', 'gl': 'IT'}
    account = account or {}
    if account.get('visitorData'):
        client['visitorData'] = account['visitorData']
    body['context'] = {'client': client}
    delegated = (account.get('dataSyncId') or '').split('||')[0]
    if delegated:
        body['context']['user'] = {'onBehalfOfUser': delegated}
    query = {'prettyPrint': 'false'}
    # Legacy "nextContinuationData" tokens travel in the query string.
    if data.get('legacy') and body.get('continuation'):
        tok = body.pop('continuation')
        query.update({'ctoken': tok, 'continuation': tok, 'type': 'next'})
    return body, query


def headers_for(account, now=None):
    h = {'Content-Type': 'application/json', 'User-Agent': UA, 'Origin': ORIGIN, 'X-Origin': ORIGIN, 'Referer': ORIGIN + '/',
         'X-Goog-AuthUser': '0', 'X-YouTube-Client-Name': '67', 'X-YouTube-Client-Version': VERSION,
         'Accept-Encoding': 'gzip'}
    account = account or {}
    if account.get('visitorData'):
        h['X-Goog-Visitor-Id'] = account['visitorData']
    token = account.get('oauth')
    if token:
        # Signed in with the device flow (oauth.py): bearer token, no cookie.
        h['Authorization'] = (token.get('token_type') or 'Bearer') + ' ' + token['access_token']
        h['X-Goog-Request-Time'] = str(int(now or time.time()))
        return h
    sap = sapisid(account.get('cookie'))
    if sap:
        ts = str(int(now or time.time()))
        h['Cookie'] = account['cookie']
        h['Authorization'] = 'SAPISIDHASH ' + ts + '_' + hashlib.sha1((ts + ' ' + sap + ' ' + ORIGIN).encode('utf-8')).hexdigest()
    return h


def api(endpoint, data, account=None):
    """Raw InnerTube answer, gzip-compressed (as Google sends it)."""
    body, query = body_for(endpoint, data, account)
    req = Request(ORIGIN + '/youtubei/v1/' + endpoint + '?' + urlencode(query),
                  data=json.dumps(body).encode('utf-8'), headers=headers_for(account))
    with urlopen(req, timeout=20) as r:
        raw = r.read()
        if r.headers.get('Content-Encoding') != 'gzip':
            raw = gzip.compress(raw, 5)
    return raw


def api_json(endpoint, data, account=None):
    return json.loads(gzip.decompress(api(endpoint, data, account)))


def account_name(data):
    """Name in the account menu, or None when the cookie is not signed in."""
    stack = [data]
    while stack:
        n = stack.pop()
        if isinstance(n, dict):
            h = n.get('activeAccountHeaderRenderer')
            if isinstance(h, dict):
                t = h.get('accountName') or {}
                return t.get('simpleText') or ''.join(r.get('text', '') for r in t.get('runs') or []) or None
            stack.extend(n.values())
        elif isinstance(n, list):
            stack.extend(n)
    return None


def pick_audio(player, alt=False):
    """Highest-bitrate audio stream in the browser's format: Opus (WebM) by
    default, AAC (MP4) for alt. DRC versions (compressed dynamics) only when
    nothing else exists; any audio as a last resort."""
    formats = [f for f in (player.get('streamingData') or {}).get('adaptiveFormats') or []
               if f.get('url') and str(f.get('mimeType', '')).startswith('audio/')]
    if not formats:
        return None
    family = 'audio/mp4' if alt else 'audio/webm'

    def rate(f):
        return (not f.get('isDrc'), int(f.get('averageBitrate') or f.get('bitrate') or 0))

    same = [f for f in formats if str(f['mimeType']).startswith(family)]
    return max(same or formats, key=rate)


def _length(url, ua):
    req = Request(url, headers={'User-Agent': ua, 'Range': 'bytes=0-0'})
    with urlopen(req, timeout=15) as r:
        m = re.search(r'/(\d+)$', r.headers.get('Content-Range') or '')
    if not m:
        raise LookupError('Lunghezza del brano sconosciuta')
    return int(m.group(1))


def resolve(con, video, skip=(), alt=False):
    """Direct audio URL for a video, shared by every worker until shortly before it expires."""
    t = db.now()
    row = con.execute('SELECT * FROM streams WHERE video=? AND alt=?', (video, int(alt))).fetchone()
    if row and row['expire'] > t and row['client'] not in skip:
        return dict(row)
    no = con.execute('SELECT until, reason FROM refused WHERE video=?', (video,)).fetchone()
    if no and no['until'] > t and not skip:
        raise Unavailable(no['reason'])
    reason = None
    # Remembered as refused only when every client said no: a timeout or an
    # answer without a usable stream says nothing about the video itself.
    certain = True
    vd = visitor_data(con)
    for client, ua, number in PLAYERS:
        if client['clientName'] in skip:
            continue
        c = dict(client, hl='it', gl='IT')
        h = {'Content-Type': 'application/json', 'User-Agent': ua, 'X-YouTube-Client-Name': number,
             'X-YouTube-Client-Version': client['clientVersion']}
        if vd:
            c['visitorData'] = vd
            h['X-Goog-Visitor-Id'] = vd
        body = {'context': {'client': c}, 'videoId': video, 'contentCheckOk': True, 'racyCheckOk': True}
        try:
            req = Request('https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
                          data=json.dumps(body).encode('utf-8'), headers=h)
            with urlopen(req, timeout=15) as r:
                player = json.loads(r.read().decode('utf-8'))
        except Exception:
            certain = False
            continue
        status = player.get('playabilityStatus') or {}
        if status.get('status') != 'OK':
            reason = status.get('reason') or reason
            continue
        f = pick_audio(player, alt)
        if not f:
            certain = False
            continue
        try:
            size = int(f.get('contentLength') or 0) or _length(f['url'], ua)
        except Exception:
            certain = False
            continue
        m = re.search(r'[?&]expire=(\d+)', f['url'])
        hit = {'video': video, 'alt': int(alt), 'url': f['url'], 'ua': ua, 'client': client['clientName'],
               'mime': str(f.get('mimeType', 'audio/webm')).split(';')[0], 'size': size,
               'expire': (int(m.group(1)) if m else t + 3600) - 300}
        con.execute('INSERT OR REPLACE INTO streams(video, alt, url, ua, client, mime, size, expire) '
                    'VALUES(:video,:alt,:url,:ua,:client,:mime,:size,:expire)', hit)
        con.execute('DELETE FROM streams WHERE expire<?', (t,))
        return hit
    if reason and certain and not skip:
        con.execute('INSERT OR REPLACE INTO refused(video, until, reason) VALUES(?,?,?)', (video, t + REFUSED_TTL, reason))
    if reason:
        raise Unavailable(reason)
    raise LookupError('YouTube non risponde')


def forget(con, video, alt=False):
    con.execute('DELETE FROM streams WHERE video=? AND alt=?', (video, int(alt)))


def fetch_range(con, video, start, end, alt=False):
    """Bytes start..end (inclusive, clamped to the file) and the stream they came from.
    A URL Google refuses (403/410) is resolved again with the next client."""
    tried = []
    while True:
        hit = resolve(con, video, tried, alt)
        if start >= hit['size']:
            return hit, None
        last = min(end, hit['size'] - 1)
        try:
            req = Request(hit['url'], headers={'User-Agent': hit['ua'], 'Range': 'bytes=%d-%d' % (start, last)})
            with urlopen(req, timeout=20) as r:
                return hit, r.read()
        except HTTPError as e:
            if e.code in (403, 410) and len(tried) < len(PLAYERS):
                forget(con, video, alt)
                tried.append(hit['client'])
                continue
            raise
