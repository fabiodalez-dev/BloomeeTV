#!/usr/bin/env python3
"""Administration from the shell.

  manage.py create-admin USER [NAME]   first administrator, random password printed once
  manage.py invite [days] [note]       new invite code
  manage.py users                      list accounts
  manage.py set-password USER          reset a password (asks for it)
  manage.py admin USER on|off          grant or revoke administration
  manage.py disable USER on|off        block or unblock an account
"""
import getpass
import secrets
import sys

from musicweb import auth, db


def user_id(con, name):
    row = con.execute('SELECT id FROM users WHERE username=?', (name,)).fetchone()
    if not row:
        sys.exit('Utente sconosciuto: %s' % name)
    return row['id']


def main(argv):
    con = db.connect()
    cmd = argv[1] if len(argv) > 1 else ''
    if cmd == 'create-admin' and len(argv) >= 3:
        pw = secrets.token_urlsafe(15)
        auth.create_user(con, argv[2], pw, ' '.join(argv[3:]) or argv[2], admin=True)
        print('Amministratore %s creato. Password: %s' % (argv[2], pw))
    elif cmd == 'invite':
        days = int(argv[2]) if len(argv) > 2 else 7
        print(auth.new_invite(con, None, days, ' '.join(argv[3:])))
    elif cmd == 'users':
        for r in con.execute('SELECT * FROM users ORDER BY id'):
            flags = ('admin ' if r['is_admin'] else '') + ('disattivato' if r['disabled'] else '')
            print('%4d  %-24s %s' % (r['id'], r['username'], flags))
    elif cmd == 'set-password' and len(argv) == 3:
        uid = user_id(con, argv[2])
        pw = getpass.getpass('Nuova password: ')
        auth.validate_password(pw)
        con.execute('UPDATE users SET pw_hash=? WHERE id=?', (auth.hash_password(pw), uid))
        con.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
        print('Password aggiornata, sessioni chiuse.')
    elif cmd in ('admin', 'disable') and len(argv) == 4 and argv[3] in ('on', 'off'):
        uid = user_id(con, argv[2])
        on = int(argv[3] == 'on')
        if cmd == 'admin':
            con.execute('UPDATE users SET is_admin=? WHERE id=?', (on, uid))
        else:
            con.execute('UPDATE users SET disabled=? WHERE id=?', (on, uid))
        if cmd == 'disable' and argv[3] == 'on':
            con.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
        print('Fatto.')
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
