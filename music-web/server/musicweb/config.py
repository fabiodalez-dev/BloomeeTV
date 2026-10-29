"""Paths and secrets. Everything lives under MUSICWEB_HOME, outside the web root."""
import os
import secrets

HOME = os.environ.get('MUSICWEB_HOME') or os.path.join(os.path.expanduser('~'), 'music-app')
DATA = os.path.join(HOME, 'data')
DB_PATH = os.path.join(DATA, 'music.db')
KEY_PATH = os.path.join(DATA, 'secret.key')

APP_NAME = 'Fabio Music'
SESSION_COOKIE = 'fm_session'
SESSION_DAYS = 60
# Secure cookies need HTTPS; the local test server sets MUSICWEB_INSECURE=1.
SECURE_COOKIES = os.environ.get('MUSICWEB_INSECURE') != '1'


def ensure_dirs():
    os.makedirs(DATA, mode=0o700, exist_ok=True)


def secret_key():
    """32-byte key for cookie encryption, created on first use with mode 0600."""
    ensure_dirs()
    try:
        with open(KEY_PATH, 'rb') as f:
            key = f.read()
        if len(key) == 44:
            return key
    except FileNotFoundError:
        pass
    from cryptography.fernet import Fernet
    key = Fernet.generate_key()
    fd = os.open(KEY_PATH + '.tmp', os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(key)
    os.replace(KEY_PATH + '.tmp', KEY_PATH)
    return key


def token(n=32):
    return secrets.token_urlsafe(n)
