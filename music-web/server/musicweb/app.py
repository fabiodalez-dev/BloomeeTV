"""WSGI application: JSON API under /api, audio under /api/audio.

LiteSpeed delivers a WSGI response only once it is complete, so audio is
served in bounded Range pieces that the media element requests on its own.
"""
import gzip
import json
import re
import traceback
from http.cookies import SimpleCookie
from urllib.error import HTTPError
from urllib.parse import parse_qs

from . import auth, config, db, library, lyrics, oauth, youtube

FIRST_CHUNK = 512 * 1024
CHUNK = 1024 * 1024
MAX_BODY = 4 * 1024 * 1024
ROUTES = []


class HTTPErr(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def route(method, pattern, login=True, admin=False):
    def deco(f):
        ROUTES.append((method, re.compile('^' + pattern + '$'), f, login, admin))
        return f
    return deco


class Request:
    def __init__(self, env, con):
        self.env = env
        self.con = con
        self.method = env.get('REQUEST_METHOD', 'GET')
        # Passenger montato su /api può spostare il prefisso in SCRIPT_NAME.
        path = env.get('PATH_INFO', '') or '/'
        if not path.startswith('/api'):
            path = (env.get('SCRIPT_NAME') or '').rstrip('/') + path
        self.path = path
        self.query = {k: v[0] for k, v in parse_qs(env.get('QUERY_STRING', '')).items()}
        self.user = None
        self.set_cookies = []
        c = SimpleCookie()
        try:
            c.load(env.get('HTTP_COOKIE', ''))
        except Exception:
            pass
        self.cookies = {k: v.value for k, v in c.items()}
        self._json = None

    @property
    def ip(self):
        return self.env.get('REMOTE_ADDR', '')

    def json(self):
        if self._json is None:
            try:
                size = int(self.env.get('CONTENT_LENGTH') or 0)
            except ValueError:
                size = 0
            if size > MAX_BODY:
                raise HTTPErr(413, 'Richiesta troppo grande')
            raw = self.env['wsgi.input'].read(size) if size > 0 else b''
            try:
                self._json = json.loads(raw.decode('utf-8')) if raw else {}
            except ValueError:
                raise HTTPErr(400, 'Richiesta non valida')
            if not isinstance(self._json, dict):
                raise HTTPErr(400, 'Richiesta non valida')
        return self._json

    def session_cookie(self, value, max_age):
        parts = ['%s=%s' % (config.SESSION_COOKIE, value), 'Path=/', 'HttpOnly', 'SameSite=Lax', 'Max-Age=%d' % max_age]
        if config.SECURE_COOKIES:
            parts.append('Secure')
        self.set_cookies.append('; '.join(parts))


def gzip_ok(env):
    return 'gzip' in env.get('HTTP_ACCEPT_ENCODING', '')


def json_reply(req, start, status, data):
    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    return bytes_reply(req, start, status, raw, gz=False)


def bytes_reply(req, start, status, raw, gz):
    """JSON bytes; gz says they are already gzip-compressed."""
    headers = [('Content-Type', 'application/json; charset=utf-8'), ('Cache-Control', 'no-store'),
               ('X-Content-Type-Options', 'nosniff'), ('Vary', 'Accept-Encoding')]
    if gzip_ok(req.env):
        if not gz and len(raw) > 1400:
            raw, gz = gzip.compress(raw, 5), True
        if gz:
            headers.append(('Content-Encoding', 'gzip'))
    elif gz:
        raw = gzip.decompress(raw)
    headers.append(('Content-Length', str(len(raw))))
    headers += [('Set-Cookie', c) for c in req.set_cookies]
    start(STATUS.get(status, '%d Error' % status), headers)
    return [raw]


STATUS = {200: '200 OK', 201: '201 Created', 204: '204 No Content', 206: '206 Partial Content', 400: '400 Bad Request',
          401: '401 Unauthorized', 403: '403 Forbidden', 404: '404 Not Found', 409: '409 Conflict',
          413: '413 Payload Too Large', 416: '416 Range Not Satisfiable', 429: '429 Too Many Requests',
          500: '500 Internal Server Error', 502: '502 Bad Gateway', 503: '503 Service Unavailable'}


def user_json(u):
    return {'id': u['id'], 'username': u['username'], 'displayName': u['display_name'], 'admin': bool(u['is_admin'])}


def limit(req, key, n, window, message='Troppe richieste, riprova tra poco'):
    if not db.hit_rate(req.con, key, n, window):
        raise HTTPErr(429, message)


# Accounts

@route('GET', '/api/session', login=False)
def get_session(req):
    if not req.user:
        setup = req.con.execute('SELECT COUNT(*) FROM users').fetchone()[0] == 0
        return 401, {'error': 'Accesso richiesto', 'setup': setup}
    yt = auth.yt_account(req.con, req.user['id'])
    return 200, {'user': user_json(req.user), 'youtube': yt_json(yt), 'youtubeCode': oauth.client() is not None}


def yt_json(a):
    return {'name': a['name'], 'method': 'code' if a.get('oauth') else 'cookie'} if a else None


@route('POST', '/api/login', login=False)
def post_login(req):
    body = req.json()
    username = str(body.get('username') or '')[:64]
    limit(req, 'login-ip:' + req.ip, 20, 900, 'Troppi tentativi, riprova tra qualche minuto')
    limit(req, 'login-user:' + username.lower(), 10, 900, 'Troppi tentativi, riprova tra qualche minuto')
    try:
        u = auth.login(req.con, username, str(body.get('password') or ''))
    except auth.AuthError as e:
        raise HTTPErr(401, str(e))
    tok = auth.new_session(req.con, u['id'], req.env.get('HTTP_USER_AGENT', ''))
    req.session_cookie(tok, config.SESSION_DAYS * 86400)
    return 200, {'user': user_json(u)}


@route('POST', '/api/setup', login=False)
def post_setup(req):
    """First account, only while the database has no users: it becomes the administrator."""
    body = req.json()
    limit(req, 'setup:' + req.ip, 10, 900)
    req.con.execute('BEGIN IMMEDIATE')
    try:
        if req.con.execute('SELECT COUNT(*) FROM users').fetchone()[0]:
            raise HTTPErr(403, 'Configurazione già completata')
        uid = auth.create_user(req.con, str(body.get('username') or ''), str(body.get('password') or ''),
                               str(body.get('displayName') or ''), admin=True)
        req.con.execute('COMMIT')
    except auth.AuthError as e:
        req.con.execute('ROLLBACK')
        raise HTTPErr(400, str(e))
    except Exception:
        req.con.execute('ROLLBACK')
        raise
    u = req.con.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
    req.session_cookie(auth.new_session(req.con, uid, req.env.get('HTTP_USER_AGENT', '')), config.SESSION_DAYS * 86400)
    return 201, {'user': user_json(u)}


@route('POST', '/api/register', login=False)
def post_register(req):
    body = req.json()
    limit(req, 'register:' + req.ip, 10, 3600, 'Troppi tentativi, riprova più tardi')
    try:
        uid = auth.register(req.con, str(body.get('invite') or ''), str(body.get('username') or ''),
                            str(body.get('password') or ''), str(body.get('displayName') or ''))
    except auth.AuthError as e:
        raise HTTPErr(400, str(e))
    u = req.con.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
    req.session_cookie(auth.new_session(req.con, uid, req.env.get('HTTP_USER_AGENT', '')), config.SESSION_DAYS * 86400)
    return 201, {'user': user_json(u)}


@route('POST', '/api/logout', login=False)
def post_logout(req):
    auth.end_session(req.con, req.cookies.get(config.SESSION_COOKIE))
    req.session_cookie('', 0)
    return 200, {'ok': True}


@route('POST', '/api/password')
def post_password(req):
    body = req.json()
    limit(req, 'password:%d' % req.user['id'], 10, 900)
    try:
        auth.change_password(req.con, req.user['id'], str(body.get('old') or ''), str(body.get('new') or ''))
    except auth.AuthError as e:
        raise HTTPErr(400, str(e))
    auth.end_other_sessions(req.con, req.user['id'], req.cookies.get(config.SESSION_COOKIE))
    return 200, {'ok': True}


@route('PATCH', '/api/profile')
def patch_profile(req):
    name = str(req.json().get('displayName') or '').strip()[:64]
    if not name:
        raise HTTPErr(400, 'Il nome non può essere vuoto')
    req.con.execute('UPDATE users SET display_name=? WHERE id=?', (name, req.user['id']))
    return 200, {'ok': True}


# Administration

@route('GET', '/api/admin/invites', admin=True)
def get_invites(req):
    rows = req.con.execute('SELECT i.*, u.username AS used_name FROM invites i LEFT JOIN users u ON u.id=i.used_by '
                           'ORDER BY i.created DESC LIMIT 200').fetchall()
    return 200, {'invites': [{'code': r['code'], 'created': r['created'], 'expires': r['expires'], 'note': r['note'],
                              'usedBy': r['used_name'], 'usedAt': r['used_at']} for r in rows]}


@route('POST', '/api/admin/invites', admin=True)
def post_invite(req):
    body = req.json()
    try:
        days = int(body.get('days') or 7)
    except (TypeError, ValueError):
        days = 7
    return 201, {'code': auth.new_invite(req.con, req.user['id'], days, str(body.get('note') or ''))}


@route('DELETE', r'/api/admin/invites/([A-Z0-9-]{11})', admin=True)
def delete_invite(req, code):
    req.con.execute('DELETE FROM invites WHERE code=? AND used_by IS NULL', (code,))
    return 200, {'ok': True}


@route('GET', '/api/admin/users', admin=True)
def get_users(req):
    rows = req.con.execute('SELECT u.*, (SELECT MAX(played_at) FROM history h WHERE h.user_id=u.id) AS last_play, '
                           '(SELECT COUNT(*) FROM history h WHERE h.user_id=u.id) AS plays FROM users u ORDER BY u.created').fetchall()
    return 200, {'users': [dict(user_json(r), disabled=bool(r['disabled']), created=r['created'], lastPlay=r['last_play'],
                                plays=r['plays']) for r in rows]}


@route('PATCH', r'/api/admin/users/(\d+)', admin=True)
def patch_user(req, uid):
    uid = int(uid)
    if uid == req.user['id']:
        raise HTTPErr(400, 'Non puoi modificare il tuo stesso account da qui')
    body = req.json()
    if 'disabled' in body:
        req.con.execute('UPDATE users SET disabled=? WHERE id=?', (int(bool(body['disabled'])), uid))
        if body['disabled']:
            req.con.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
    if 'admin' in body:
        req.con.execute('UPDATE users SET is_admin=? WHERE id=?', (int(bool(body['admin'])), uid))
    return 200, {'ok': True}


# YouTube Music

@route('POST', r'/api/yt/(search|browse|next|music/get_search_suggestions|account/account_menu)')
def post_yt(req, endpoint):
    limit(req, 'yt:%d' % req.user['id'], 240, 60)
    body = req.json()
    personal = body.get('personal') is True or endpoint == 'account/account_menu'
    account = auth.yt_account_fresh(req.con, req.user['id']) if personal else None
    body.pop('personal', None)
    # Personal pages only when asked: shared pages stay anonymous.
    if not personal:
        account = {'visitorData': youtube.visitor_data(req.con)} if endpoint == 'browse' else None
    try:
        return 'gz', youtube.api(endpoint, body, account)
    except ValueError:
        raise HTTPErr(400, 'Richiesta non valida')
    except HTTPError as e:
        if e.code in (401, 403) and account and (account.get('cookie') or account.get('oauth')):
            raise HTTPErr(409, 'Sessione YouTube scaduta: ricollega il tuo account')
        raise HTTPErr(502, 'YouTube Music non risponde')
    except Exception:
        raise HTTPErr(502, 'YouTube Music non risponde')


@route('GET', '/api/youtube-account')
def get_yt_account(req):
    return 200, {'account': yt_json(auth.yt_account(req.con, req.user['id'])), 'code': oauth.client() is not None}


@route('POST', '/api/youtube-account/code')
def post_yt_code(req):
    limit(req, 'ytcode:%d' % req.user['id'], 10, 900)
    try:
        return 200, oauth.start(req.con, req.user['id'])
    except oauth.OAuthError as e:
        raise HTTPErr(400, str(e))


@route('POST', '/api/youtube-account/code/check')
def post_yt_code_check(req):
    limit(req, 'ytcheck:%d' % req.user['id'], 400, 900)
    try:
        status, token = oauth.poll(req.con, req.user['id'])
    except oauth.OAuthError as e:
        raise HTTPErr(400, str(e))
    if status != 'ok':
        return 200, {'status': status, 'message': oauth.wait_hint(status)}
    account = {'oauth': token}
    try:
        name = youtube.account_name(youtube.api_json('account/account_menu', {}, account))
    except HTTPError as e:
        raise HTTPErr(400, 'Google ha dato l\'accesso ma YouTube Music rifiuta il token (%d). Usa il collegamento con il cookie.' % e.code)
    except Exception:
        name = None
    if not name:
        raise HTTPErr(400, 'Google ha dato l\'accesso ma YouTube Music non riconosce l\'account. Usa il collegamento con il cookie.')
    auth.save_yt_account(req.con, req.user['id'], account, name)
    return 200, {'status': 'ok', 'account': yt_json(dict(account, name=name))}


@route('GET', '/api/admin/google-oauth', admin=True)
def get_google_oauth(req):
    c = oauth.client()
    return 200, {'configured': bool(c), 'clientId': c['client_id'] if c else None}


@route('PUT', '/api/admin/google-oauth', admin=True)
def put_google_oauth(req):
    body = req.json()
    try:
        oauth.save_client(str(body.get('clientId') or ''), str(body.get('clientSecret') or ''))
    except oauth.OAuthError as e:
        raise HTTPErr(400, str(e))
    return 200, {'configured': True}


@route('DELETE', '/api/admin/google-oauth', admin=True)
def delete_google_oauth(req):
    oauth.remove_client()
    return 200, {'configured': False}


@route('PUT', '/api/youtube-account')
def put_yt_account(req):
    body = req.json()
    limit(req, 'ytlink:%d' % req.user['id'], 10, 900)
    cookie = str(body.get('cookie') or '').strip()
    if cookie.lower().startswith('cookie:'):
        cookie = cookie[7:].strip()
    if not youtube.sapisid(cookie) or len(cookie) > 16000:
        raise HTTPErr(400, 'Il cookie non contiene SAPISID: copia l\'intera intestazione "cookie" da music.youtube.com')
    account = {'cookie': cookie}
    sync = str(body.get('dataSyncId') or '').strip()
    if sync:
        account['dataSyncId'] = sync[:200]
    try:
        name = youtube.account_name(youtube.api_json('account/account_menu', {}, account))
    except Exception:
        name = None
    if not name:
        raise HTTPErr(400, 'Google non riconosce questo cookie: rifai l\'accesso a music.youtube.com e copialo di nuovo')
    auth.save_yt_account(req.con, req.user['id'], account, name)
    return 200, {'account': yt_json(dict(account, name=name))}


@route('DELETE', '/api/youtube-account')
def delete_yt_account(req):
    req.con.execute('DELETE FROM yt_accounts WHERE user_id=?', (req.user['id'],))
    return 200, {'ok': True}


@route('GET', r'/api/stream/([A-Za-z0-9_-]{11})')
def get_stream(req, video):
    """Why a stream fails: the media element cannot read error bodies."""
    try:
        hit = youtube.resolve(req.con, video, (), req.query.get('alt') == '1')
    except youtube.Unavailable as e:
        raise HTTPErr(404, str(e))
    except Exception:
        raise HTTPErr(502, 'YouTube non risponde')
    return 200, {'ok': True, 'mime': hit['mime'], 'size': hit['size']}


def audio(req, start, video):
    limit(req, 'audio:%d' % req.user['id'], 1200, 3600)
    alt = req.query.get('alt') == '1'
    m = re.match(r'bytes=(\d+)-(\d*)$', (req.env.get('HTTP_RANGE') or 'bytes=0-').strip())
    if not m:
        raise HTTPErr(416, 'Intervallo non valido')
    a = int(m.group(1))
    b = int(m.group(2)) if m.group(2) else None
    # Bounded piece: the browser asks for the rest when it needs it.
    cap = a + (FIRST_CHUNK if a == 0 else CHUNK) - 1
    b = cap if b is None else min(b, cap)
    if b < a:
        raise HTTPErr(416, 'Intervallo non valido')
    try:
        hit, data = youtube.fetch_range(req.con, video, a, b, alt)
    except youtube.Unavailable as e:
        raise HTTPErr(404, str(e))
    except Exception:
        raise HTTPErr(502, 'YouTube non riesce a riprodurre questo brano')
    if data is None:
        start('416 Range Not Satisfiable', [('Content-Range', 'bytes */%d' % hit['size']), ('Content-Length', '0')])
        return [b'']
    start('206 Partial Content', [
        ('Content-Type', hit['mime']), ('Accept-Ranges', 'bytes'),
        ('Content-Range', 'bytes %d-%d/%d' % (a, a + len(data) - 1, hit['size'])),
        ('Content-Length', str(len(data))), ('Cache-Control', 'private, max-age=3600'),
        ('X-Content-Type-Options', 'nosniff')])
    return [data]


THUMB_HOST = re.compile(r'^https://([a-z0-9-]+\.)*(googleusercontent\.com|ytimg\.com|ggpht\.com)/[^\s"<>]{1,600}$')


def thumb(req, start):
    """Tiny cover (60 px) from the same origin: the browser reads its colors in a
    canvas, which Google's image hosts refuse to CORS requests (429)."""
    url = req.query.get('url') or ''
    if not THUMB_HOST.match(url):
        raise HTTPErr(400, 'Immagine non consentita')
    url = re.sub(r'=w\d+-h\d+', '=w60-h60', url, count=1)
    url = re.sub(r'=s\d+(?=[-&?]|$)', '=s60', url, count=1)
    limit(req, 'thumb:%d' % req.user['id'], 600, 3600)
    try:
        with youtube.urlopen(youtube.Request(url, headers={'User-Agent': youtube.UA}), timeout=10) as r:
            ctype = r.headers.get('Content-Type') or ''
            data = r.read(512 * 1024 + 1)
    except Exception:
        raise HTTPErr(502, 'Immagine non disponibile')
    if not ctype.startswith('image/') or len(data) > 512 * 1024:
        raise HTTPErr(502, 'Immagine non valida')
    start('200 OK', [('Content-Type', ctype), ('Content-Length', str(len(data))), ('Cache-Control', 'private, max-age=86400'),
                     ('X-Content-Type-Options', 'nosniff')])
    return [data]


@route('GET', '/api/lyrics')
def get_lyrics(req):
    q = req.query
    video = q.get('videoId') or ''
    if video and not library.VIDEO.match(video):
        raise HTTPErr(400, 'Brano non valido')
    title, artist = (q.get('title') or '')[:300], (q.get('artist') or '')[:300]
    if not title or not artist:
        raise HTTPErr(400, 'Titolo e artista richiesti')
    try:
        duration = float(q.get('duration') or 0) or None
    except ValueError:
        duration = None
    limit(req, 'lyrics:%d' % req.user['id'], 120, 60)
    return 200, {'lyrics': lyrics.find(req.con, video, title, artist, duration, (q.get('album') or '')[:300] or None)}


# Library

@route('GET', '/api/library')
def get_library(req):
    uid = req.user['id']
    settings, _ = library.get_state(req.con, uid, 'settings')
    home, _ = library.get_state(req.con, uid, 'home')
    return 200, {'favorites': library.favorites(req.con, uid), 'playlists': library.playlists(req.con, uid),
                 'settings': settings or {}, 'home': home or {}}


@route('PUT', '/api/favorites')
def put_favorite(req):
    return 200, {'item': library.add_favorite(req.con, req.user['id'], req.json().get('item'))}


@route('POST', '/api/favorites/batch')
def post_favorites_batch(req):
    items = req.json().get('items')
    if not isinstance(items, list) or len(items) > 5000:
        raise HTTPErr(400, 'Al massimo 5000 elementi')
    return 200, {'added': library.add_favorites(req.con, req.user['id'], items)}


@route('DELETE', r'/api/favorites/([A-Za-z0-9_-]{2,80})')
def delete_favorite(req, key):
    library.remove_favorite(req.con, req.user['id'], key)
    return 200, {'ok': True}


@route('GET', '/api/playlists')
def get_playlists(req):
    return 200, {'playlists': library.playlists(req.con, req.user['id'])}


@route('POST', '/api/playlists')
def post_playlist(req):
    body = req.json()
    pid = library.create_playlist(req.con, req.user['id'], body.get('name'), body.get('description') or '', body.get('items') or [])
    return 201, {'id': pid}


@route('GET', r'/api/playlists/(\d+)')
def get_playlist(req, pid):
    return 200, library.playlist(req.con, req.user['id'], int(pid))


@route('PATCH', r'/api/playlists/(\d+)')
def patch_playlist(req, pid):
    body = req.json()
    library.update_playlist(req.con, req.user['id'], int(pid), body.get('name'), body.get('description'))
    return 200, {'ok': True}


@route('DELETE', r'/api/playlists/(\d+)')
def delete_playlist(req, pid):
    library.delete_playlist(req.con, req.user['id'], int(pid))
    return 200, {'ok': True}


@route('PUT', r'/api/playlists/(\d+)/items')
def put_items(req, pid):
    library.set_items(req.con, req.user['id'], int(pid), req.json().get('items'))
    return 200, {'ok': True}


@route('POST', r'/api/playlists/(\d+)/items')
def post_items(req, pid):
    return 200, {'count': library.append_items(req.con, req.user['id'], int(pid), req.json().get('items'))}


@route('POST', '/api/history')
def post_history(req):
    body = req.json()
    limit(req, 'history:%d' % req.user['id'], 120, 60)
    library.log_play(req.con, req.user['id'], body.get('item'), body.get('seconds'))
    return 200, {'ok': True}


@route('GET', '/api/history')
def get_history(req):
    try:
        lim = int(req.query.get('limit') or 100)
        before = int(req.query['before']) if req.query.get('before') else None
    except ValueError:
        raise HTTPErr(400, 'Parametri non validi')
    return 200, {'items': library.history(req.con, req.user['id'], lim, before)}


@route('DELETE', '/api/history')
def delete_history(req):
    req.con.execute('DELETE FROM history WHERE user_id=?', (req.user['id'],))
    return 200, {'ok': True}


@route('GET', '/api/stats')
def get_stats(req):
    try:
        since = int(req.query.get('since') or 0)
    except ValueError:
        raise HTTPErr(400, 'Parametri non validi')
    return 200, library.stats(req.con, req.user['id'], since)


@route('GET', r'/api/state/(settings|queue|home)')
def get_state(req, name):
    data, updated = library.get_state(req.con, req.user['id'], name)
    return 200, {'data': data, 'updated': updated}


@route('PUT', r'/api/state/(settings|queue|home)')
def put_state(req, name):
    return 200, {'updated': library.set_state(req.con, req.user['id'], name, req.json().get('data'))}


AUDIO = re.compile(r'^/api/audio/([A-Za-z0-9_-]{11})$')
UNSAFE = ('POST', 'PUT', 'PATCH', 'DELETE')


def application(env, start):
    con = None
    req = None
    try:
        con = db.connect()
        req = Request(env, con)
        if req.method in UNSAFE and env.get('HTTP_X_REQUESTED_WITH') != 'fabio-music':
            # A custom header cannot be sent cross-site without a CORS preflight,
            # which this server never grants: it blocks CSRF on cookie sessions.
            raise HTTPErr(403, 'Richiesta non consentita')
        req.user = auth.session_user(con, req.cookies.get(config.SESSION_COOKIE))
        m = AUDIO.match(req.path)
        if m:
            if not req.user:
                raise HTTPErr(401, 'Accesso richiesto')
            if req.method not in ('GET', 'HEAD'):
                raise HTTPErr(404, 'Percorso non valido')
            return audio(req, start, m.group(1))
        if req.path == '/api/thumb' and req.method == 'GET':
            if not req.user:
                raise HTTPErr(401, 'Accesso richiesto')
            return thumb(req, start)
        for method, pattern, f, login, admin in ROUTES:
            m = pattern.match(req.path)
            if not m or method != req.method:
                continue
            if login and not req.user:
                raise HTTPErr(401, 'Accesso richiesto')
            if admin and not req.user['is_admin']:
                raise HTTPErr(403, 'Solo per amministratori')
            status, data = f(req, *m.groups())
            if status == 'gz':
                return bytes_reply(req, start, 200, data, gz=True)
            return json_reply(req, start, status, data)
        raise HTTPErr(404, 'Percorso non valido')
    except HTTPErr as e:
        return json_reply(req or Request(env, None), start, e.status, {'error': e.message})
    except (library.Invalid, auth.AuthError) as e:
        return json_reply(req or Request(env, None), start, 400, {'error': str(e)})
    except (LookupError, youtube.Unavailable) as e:
        if isinstance(e, KeyError):
            traceback.print_exc()
            return json_reply(req or Request(env, None), start, 500, {'error': 'Errore interno'})
        return json_reply(req or Request(env, None), start, 404, {'error': str(e) or 'Non trovato'})
    except Exception:
        traceback.print_exc()
        return json_reply(req or Request(env, None), start, 500, {'error': 'Errore interno'})
    finally:
        if con is not None:
            con.close()
