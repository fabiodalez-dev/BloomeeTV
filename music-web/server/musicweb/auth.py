"""Accounts: scrypt passwords, opaque session tokens (only their hash is
stored), invite codes, and the per-user YouTube cookie encrypted at rest."""
import base64
import hashlib
import hmac
import json
import re
import secrets

from . import config, db

SCRYPT = {'n': 2 ** 14, 'r': 8, 'p': 1}
USERNAME = re.compile(r'^[A-Za-z0-9._-]{3,32}$')
INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'


class AuthError(Exception):
    pass


def hash_password(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode('utf-8'), salt=salt, dklen=32, maxmem=64 * 1024 * 1024, **SCRYPT)
    return 'scrypt$%d$%d$%d$%s$%s' % (SCRYPT['n'], SCRYPT['r'], SCRYPT['p'],
                                      base64.b64encode(salt).decode(), base64.b64encode(dk).decode())


def check_password(password, stored):
    try:
        _, n, r, p, salt, dk = stored.split('$')
        got = hashlib.scrypt(password.encode('utf-8'), salt=base64.b64decode(salt), n=int(n), r=int(r), p=int(p),
                             dklen=32, maxmem=64 * 1024 * 1024)
        return hmac.compare_digest(got, base64.b64decode(dk))
    except Exception:
        return False


# Spent on unknown usernames too, so timing does not reveal which accounts exist.
_DUMMY = None


def _dummy():
    global _DUMMY
    if _DUMMY is None:
        _DUMMY = hash_password(secrets.token_hex(8))
    return _DUMMY


def validate_password(password):
    if not isinstance(password, str) or len(password) < 8:
        raise AuthError('La password deve avere almeno 8 caratteri')
    if len(password) > 256:
        raise AuthError('Password troppo lunga')


def validate_username(username):
    if not isinstance(username, str) or not USERNAME.match(username):
        raise AuthError('Nome utente: 3–32 caratteri tra lettere, numeri, punto, trattino e trattino basso')


def create_user(con, username, password, display_name=None, admin=False):
    validate_username(username)
    validate_password(password)
    if con.execute('SELECT 1 FROM users WHERE username=?', (username,)).fetchone():
        raise AuthError('Nome utente già in uso')
    cur = con.execute('INSERT INTO users(username, display_name, pw_hash, is_admin, created) VALUES(?,?,?,?,?)',
                      (username, (display_name or username).strip()[:64] or username, hash_password(password), int(admin), db.now()))
    return cur.lastrowid


def login(con, username, password):
    row = con.execute('SELECT * FROM users WHERE username=?', (username or '',)).fetchone()
    if not row:
        check_password(password or '', _dummy())
        raise AuthError('Nome utente o password errati')
    if not check_password(password or '', row['pw_hash']):
        raise AuthError('Nome utente o password errati')
    if row['disabled']:
        raise AuthError('Account disattivato')
    return row


def _token_hash(tok):
    return hashlib.sha256(tok.encode('utf-8')).hexdigest()


def new_session(con, user_id, agent=''):
    tok = config.token(32)
    t = db.now()
    con.execute('INSERT INTO sessions(token_hash, user_id, created, last_seen, agent) VALUES(?,?,?,?,?)',
                (_token_hash(tok), user_id, t, t, (agent or '')[:200]))
    return tok


def session_user(con, tok):
    if not tok or len(tok) > 100:
        return None
    h = _token_hash(tok)
    row = con.execute('SELECT u.*, s.last_seen FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=?', (h,)).fetchone()
    if not row:
        return None
    t = db.now()
    if row['disabled'] or t - row['last_seen'] > config.SESSION_DAYS * 86400:
        con.execute('DELETE FROM sessions WHERE token_hash=?', (h,))
        return None
    # Sliding expiry, written at most once an hour.
    if t - row['last_seen'] > 3600:
        con.execute('UPDATE sessions SET last_seen=? WHERE token_hash=?', (t, h))
    return row


def end_session(con, tok):
    if tok:
        con.execute('DELETE FROM sessions WHERE token_hash=?', (_token_hash(tok),))


def end_other_sessions(con, user_id, keep_tok):
    con.execute('DELETE FROM sessions WHERE user_id=? AND token_hash<>?', (user_id, _token_hash(keep_tok or '')))


def new_invite(con, created_by, days=7, note=''):
    code = ''.join(secrets.choice(INVITE_ALPHABET) for _ in range(10))
    code = code[:5] + '-' + code[5:]
    t = db.now()
    con.execute('INSERT INTO invites(code, created_by, created, expires, note) VALUES(?,?,?,?,?)',
                (code, created_by, t, t + max(1, min(int(days), 90)) * 86400, (note or '')[:120]))
    return code


def register(con, invite, username, password, display_name=None):
    code = (invite or '').strip().upper()
    if len(code) == 10 and '-' not in code:
        code = code[:5] + '-' + code[5:]
    con.execute('BEGIN IMMEDIATE')
    try:
        row = con.execute('SELECT * FROM invites WHERE code=?', (code,)).fetchone()
        if not row or row['used_by'] is not None or row['expires'] < db.now():
            raise AuthError('Codice d\'invito non valido o scaduto')
        uid = create_user(con, username, password, display_name)
        con.execute('UPDATE invites SET used_by=?, used_at=? WHERE code=?', (uid, db.now(), code))
        con.execute('COMMIT')
    except Exception:
        con.execute('ROLLBACK')
        raise
    return uid


def change_password(con, user_id, old, new):
    row = con.execute('SELECT pw_hash FROM users WHERE id=?', (user_id,)).fetchone()
    if not row or not check_password(old or '', row['pw_hash']):
        raise AuthError('Password attuale errata')
    validate_password(new)
    con.execute('UPDATE users SET pw_hash=? WHERE id=?', (hash_password(new), user_id))


def _fernet():
    from cryptography.fernet import Fernet
    return Fernet(config.secret_key())


def save_yt_account(con, user_id, account, name):
    secret = _fernet().encrypt(json.dumps(account).encode('utf-8'))
    con.execute('INSERT OR REPLACE INTO yt_accounts(user_id, secret, name, updated) VALUES(?,?,?,?)',
                (user_id, secret, name or '', db.now()))


def yt_account_fresh(con, user_id):
    """The user's YouTube account, with the OAuth token renewed when it is about
    to expire. A token Google revoked unlinks the account."""
    from . import oauth
    a = yt_account(con, user_id)
    if not a or not a.get('oauth'):
        return a
    fresh = oauth.refresh(a['oauth'])
    if fresh is None:
        con.execute('DELETE FROM yt_accounts WHERE user_id=?', (user_id,))
        return None
    if fresh is not a['oauth']:
        name = a.pop('name', '')
        a['oauth'] = fresh
        save_yt_account(con, user_id, a, name)
        a['name'] = name
    return a


def yt_account(con, user_id):
    row = con.execute('SELECT secret, name FROM yt_accounts WHERE user_id=?', (user_id,)).fetchone()
    if not row:
        return None
    try:
        data = json.loads(_fernet().decrypt(row['secret']).decode('utf-8'))
    except Exception:
        return None
    data['name'] = row['name']
    return data
