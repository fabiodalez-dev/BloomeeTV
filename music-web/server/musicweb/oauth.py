"""Google sign-in for YouTube Music with the device flow, as on a TV: the site
shows a code, the user approves it at google.com/device on any device.

The administrator creates once an OAuth client of type "TVs and Limited Input
devices" in Google Cloud Console; its id and secret live in
data/google-oauth.json (mode 0600). The device code never reaches the browser.
"""
import json
import os
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from . import config, db

PATH = os.path.join(config.DATA, 'google-oauth.json')
SCOPE = 'https://www.googleapis.com/auth/youtube'
DEVICE_URL = 'https://oauth2.googleapis.com/device/code'
TOKEN_URL = 'https://oauth2.googleapis.com/token'


class OAuthError(Exception):
    pass


ERRORS = {
    'invalid_client': 'Google non riconosce il client OAuth: l\'amministratore deve controllare ID e secret',
    'unauthorized_client': 'Il client OAuth non è del tipo «TV e dispositivi con input limitato»',
    'invalid_scope': 'Il progetto Google non consente l\'accesso a YouTube: attiva YouTube Data API v3',
    'access_denied': 'Accesso negato su Google',
    'org_internal': 'Il client OAuth accetta solo account della sua organizzazione',
}


def client():
    try:
        with open(PATH) as f:
            c = json.load(f)
        if c.get('client_id') and c.get('client_secret'):
            return c
    except (OSError, ValueError):
        pass
    return None


def save_client(client_id, client_secret):
    config.ensure_dirs()
    client_id, client_secret = client_id.strip(), client_secret.strip()
    if not client_id.endswith('.apps.googleusercontent.com') or len(client_id) > 200 or not 10 < len(client_secret) < 200:
        raise OAuthError('ID client o secret non validi: copiali dalla pagina del client OAuth in Google Cloud Console')
    fd = os.open(PATH + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump({'client_id': client_id, 'client_secret': client_secret}, f)
    os.replace(PATH + '.tmp', PATH)


def remove_client():
    try:
        os.remove(PATH)
    except FileNotFoundError:
        pass


def _post(url, data):
    req = Request(url, data=urlencode(data).encode(), headers={'Content-Type': 'application/x-www-form-urlencoded'})
    try:
        with urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode('utf-8'))
    except HTTPError as e:
        try:
            return json.loads(e.read().decode('utf-8'))
        except Exception:
            raise OAuthError('Google non risponde (%d)' % e.code)


def start(con, user_id):
    """New device code for this user; returns what the user needs to see."""
    c = client()
    if not c:
        raise OAuthError('L\'accesso con codice non è ancora configurato dall\'amministratore')
    d = _post(DEVICE_URL, {'client_id': c['client_id'], 'scope': SCOPE})
    if 'device_code' not in d:
        raise OAuthError(ERRORS.get(d.get('error'), 'Google ha rifiutato la richiesta (%s)' % (d.get('error') or 'errore sconosciuto')))
    t = db.now()
    pending = {'device_code': d['device_code'], 'interval': int(d.get('interval') or 5), 'expires': t + int(d.get('expires_in') or 1800)}
    db.kv_set(con, 'oauth-pending:%d' % user_id, json.dumps(pending))
    return {'userCode': d['user_code'], 'url': d.get('verification_url') or d.get('verification_uri') or 'https://www.google.com/device',
            'interval': pending['interval'], 'expires': pending['expires']}


def poll(con, user_id):
    """One check of the pending code: ('pending'|'slow'|'expired'|'denied', None) or ('ok', token)."""
    raw = db.kv_get(con, 'oauth-pending:%d' % user_id, 3600)
    if not raw:
        return 'expired', None
    pending = json.loads(raw)
    if pending['expires'] < db.now():
        con.execute('DELETE FROM kv WHERE key=?', ('oauth-pending:%d' % user_id,))
        return 'expired', None
    c = client()
    if not c:
        raise OAuthError('Accesso con codice non configurato')
    d = _post(TOKEN_URL, {'client_id': c['client_id'], 'client_secret': c['client_secret'], 'device_code': pending['device_code'],
                          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'})
    err = d.get('error')
    if err == 'authorization_pending':
        return 'pending', None
    if err == 'slow_down':
        return 'slow', None
    con.execute('DELETE FROM kv WHERE key=?', ('oauth-pending:%d' % user_id,))
    if err == 'access_denied':
        return 'denied', None
    if err or 'access_token' not in d:
        if err == 'expired_token':
            return 'expired', None
        raise OAuthError(ERRORS.get(err, 'Google non ha dato il token (%s)' % (err or 'errore sconosciuto')))
    return 'ok', {'access_token': d['access_token'], 'refresh_token': d.get('refresh_token'),
                  'token_type': d.get('token_type') or 'Bearer', 'expires_at': db.now() + int(d.get('expires_in') or 3600)}


def refresh(token):
    """Fresh copy of the token when it expires within two minutes; None if Google revoked it."""
    if token['expires_at'] - db.now() > 120:
        return token
    c = client()
    if not c or not token.get('refresh_token'):
        return None
    d = _post(TOKEN_URL, {'client_id': c['client_id'], 'client_secret': c['client_secret'],
                          'refresh_token': token['refresh_token'], 'grant_type': 'refresh_token'})
    if 'access_token' not in d:
        return None
    return dict(token, access_token=d['access_token'], expires_at=db.now() + int(d.get('expires_in') or 3600))


def wait_hint(status):
    return {'pending': 'In attesa che approvi il codice', 'slow': 'In attesa che approvi il codice',
            'expired': 'Il codice è scaduto: chiedine uno nuovo', 'denied': 'Accesso negato su Google'}.get(status, '')

