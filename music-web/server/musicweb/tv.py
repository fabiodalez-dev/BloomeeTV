"""Library pages of an account linked with a code, read through the YouTube TV client.

Since late 2024 music.youtube.com refuses device-flow tokens (HTTP 400), while
the TV client (TVHTML5 on www.youtube.com) still accepts them for the library:
saved playlists, albums, followed artists, liked songs and every playlist page.
Its answers are made of tileRenderer; here they become the WEB_REMIX shapes the
browser already reads (musicTwoRowItemRenderer, musicResponsiveListItemRenderer),
so ui/src/lib/yt.js needs no second parser. The personal Home has no TV
equivalent: it falls back to the anonymous one.
"""
import json
import re
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.request import Request, urlopen

from . import db

ORIGIN = 'https://www.youtube.com'
VERSION = '7.20250923.13.00'
UA = 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version'
# Pages the TV client serves for a signed-in account; anything else stays on WEB_REMIX.
BROWSE = re.compile(r'^(FEmusic_liked_playlists|FEmusic_liked_albums|FEmusic_library_corpus_artists|FEmusic_liked_videos|VL[\w-]{1,80})$')
# Continuation tokens handed out from here carry this prefix, so the next page goes back to TV.
PREFIX = 'tv:'
ARTIST_TTL = 30 * 86400
ARTIST_SEARCH = 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D'


def handles(endpoint, data):
    """True when this request belongs to the TV client for an account linked with a code."""
    if endpoint == 'account/account_menu':
        return True
    if endpoint != 'browse' or not isinstance(data, dict):
        return False
    cont = data.get('continuation')
    if isinstance(cont, str):
        return cont.startswith(PREFIX)
    return isinstance(data.get('browseId'), str) and bool(BROWSE.match(data['browseId']))


def call(endpoint, body, token, now=None):
    body = dict(body, context={'client': {'clientName': 'TVHTML5', 'clientVersion': VERSION, 'hl': 'it', 'gl': 'IT'}})
    headers = {'Content-Type': 'application/json', 'User-Agent': UA, 'X-YouTube-Client-Name': '7', 'X-YouTube-Client-Version': VERSION,
               'Authorization': (token.get('token_type') or 'Bearer') + ' ' + token['access_token'],
               'X-Goog-Request-Time': str(int(now or time.time()))}
    req = Request(ORIGIN + '/youtubei/v1/' + endpoint + '?prettyPrint=false', data=json.dumps(body).encode('utf-8'), headers=headers)
    with urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode('utf-8'))


def _walk(node):
    stack = [node]
    while stack:
        n = stack.pop()
        if isinstance(n, dict):
            yield n
            stack.extend(reversed(list(n.values())))
        elif isinstance(n, list):
            stack.extend(reversed(n))


def _text(t):
    if not isinstance(t, dict):
        return ''
    if isinstance(t.get('simpleText'), str):
        return t['simpleText']
    return ''.join(r.get('text', '') for r in t.get('runs') or [] if isinstance(r, dict))


def _lines(meta):
    out = []
    for line in meta.get('lines') or []:
        items = (line.get('lineRenderer') or {}).get('items') or []
        t = ' '.join(_text((i.get('lineItemRenderer') or {}).get('text')) for i in items).strip()
        if t:
            out.append(t)
    return out


def _thumb(header):
    thumbs = ((header.get('thumbnail') or {}).get('thumbnails')) or []
    return {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [t for t in thumbs if isinstance(t, dict) and t.get('url')]}}}


def _browse_id(tile):
    """Where the tile leads: the album (MPREb) before its OLAK playlist."""
    ids = [n['browseEndpoint']['browseId'] for n in _walk(tile.get('metadata'))
           if isinstance(n.get('browseEndpoint'), dict) and isinstance(n['browseEndpoint'].get('browseId'), str)]
    album = [i for i in ids if i.startswith('MPREb')]
    if album:
        return album[0]
    select = (tile.get('onSelectCommand') or {}).get('browseEndpoint') or {}
    return select.get('browseId') or (ids[0] if ids else None)


def convert_tile(tile, artists=None):
    """One tileRenderer as the WEB_REMIX item the browser reads, or None."""
    meta = (tile.get('metadata') or {}).get('tileMetadataRenderer') or {}
    header = (tile.get('header') or {}).get('tileHeaderRenderer') or {}
    title = _text(meta.get('title')).strip()
    if not title:
        return None
    lines = _lines(meta)
    watch = (tile.get('onSelectCommand') or {}).get('watchEndpoint') or {}
    if tile.get('contentType') == 'TILE_CONTENT_TYPE_VIDEO' and watch.get('videoId'):
        duration = ''
        for o in header.get('thumbnailOverlays') or []:
            duration = duration or _text((o.get('thumbnailOverlayTimeStatusRenderer') or {}).get('text'))
        cols = [{'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': title}]}}}]
        if lines:
            cols.append({'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [{'text': lines[0]}]}}})
        item = {'flexColumns': cols, 'playlistItemData': {'videoId': watch['videoId']}, 'thumbnail': _thumb(header)}
        if re.match(r'^\d+(:\d+)+$', duration):
            item['fixedColumns'] = [{'musicResponsiveListItemFixedColumnRenderer': {'text': {'simpleText': duration}}}]
        return {'musicResponsiveListItemRenderer': item}
    if tile.get('contentType') == 'TILE_CONTENT_TYPE_CHANNEL':
        browse_id = (artists or {}).get(title)
    else:
        browse_id = _browse_id(tile)
    if not browse_id:
        return None
    return {'musicTwoRowItemRenderer': {
        'title': {'runs': [{'text': title}]},
        'subtitle': {'runs': [{'text': ' • '.join(lines)}]},
        'navigationEndpoint': {'browseEndpoint': {'browseId': browse_id}},
        'thumbnailRenderer': _thumb(header)}}


def tiles(data):
    return [n['tileRenderer'] for n in _walk(data) if isinstance(n.get('tileRenderer'), dict)]


def next_token(data):
    """Next page of a long list (playlists, liked songs); tab reloads are not pages."""
    for n in _walk(data):
        c = n.get('nextContinuationData')
        if isinstance(c, dict) and isinstance(c.get('continuation'), str):
            return c['continuation']
    return None


def convert(data, continued=False, artists=None):
    items = [i for i in (convert_tile(t, artists) for t in tiles(data)) if i]
    rows = [i for i in items if 'musicResponsiveListItemRenderer' in i]
    cards = [i for i in items if 'musicTwoRowItemRenderer' in i]
    token = next_token(data)
    more = [{'nextContinuationData': {'continuation': PREFIX + token}}] if token else []
    if continued:
        return {'continuationContents': {'musicShelfContinuation': {'contents': rows + cards, 'continuations': more}}}
    sections = []
    if cards:
        sections.append({'gridRenderer': {'items': cards}})
    if rows or more:
        sections.append({'musicShelfRenderer': {'contents': rows, 'continuations': more}})
    return {'contents': {'singleColumnBrowseResultsRenderer': {'tabs': [{'tabRenderer': {'content': {'sectionListRenderer': {'contents': sections}}}}]}}}


def account_menu(data):
    """accounts_list answer as the account menu youtube.account_name() reads."""
    for n in _walk(data):
        if isinstance(n.get('accountName'), dict) and n.get('isSelected') is not False:
            return {'actions': [{'openPopupAction': {'popup': {'multiPageMenuRenderer': {'header': {'activeAccountHeaderRenderer': {
                'accountName': {'simpleText': _text(n['accountName'])}, 'accountPhoto': n.get('accountPhoto') or {}}}}}}}]}
    return {}


def find_artist(name, search):
    """Channel id of an artist by name, through a WEB_REMIX artist search; None when not found."""
    d = search({'query': name, 'params': ARTIST_SEARCH})
    first = None
    for n in _walk(d):
        r = n.get('musicResponsiveListItemRenderer')
        if not isinstance(r, dict):
            continue
        b = ((r.get('navigationEndpoint') or {}).get('browseEndpoint') or {}).get('browseId') or ''
        if not b.startswith('UC'):
            continue
        cols = r.get('flexColumns') or []
        label = _text(((cols[0] if cols else {}).get('musicResponsiveListItemFlexColumnRenderer') or {}).get('text')).strip()
        if label.lower() == name.lower():
            return b
        first = first or b
    return first


def artist_ids(con, names, search):
    """Followed artists come as names with a mix: their channels are looked up once and kept."""
    out, todo = {}, []
    for name in names:
        hit = db.kv_get(con, 'tv-artist:' + name.lower(), ARTIST_TTL)
        if hit is not None:
            if hit:
                out[name] = hit
        else:
            todo.append(name)

    def look(name):
        try:
            return name, find_artist(name, search)
        except Exception:
            return name, False

    with ThreadPoolExecutor(6) as pool:
        for name, found in pool.map(look, todo[:60]):
            if found is False:
                continue
            db.kv_set(con, 'tv-artist:' + name.lower(), found or '')
            if found:
                out[name] = found
    return out


def api(con, endpoint, data, token, search):
    """A library request for an account linked with a code, answered in WEB_REMIX shapes."""
    if endpoint == 'account/account_menu':
        return account_menu(call('account/accounts_list', {}, token))
    cont = data.get('continuation')
    if isinstance(cont, str):
        tok = cont[len(PREFIX):]
        if not tok or len(tok) > 8000:
            raise ValueError('Richiesta non valida')
        return convert(call('browse', {'continuation': tok}, token), continued=True)
    raw = call('browse', {'browseId': data['browseId']}, token)
    names = [_text(((t.get('metadata') or {}).get('tileMetadataRenderer') or {}).get('title')).strip()
             for t in tiles(raw) if t.get('contentType') == 'TILE_CONTENT_TYPE_CHANNEL']
    artists = artist_ids(con, [n for n in names if n], search) if names else None
    return convert(raw, artists=artists)
