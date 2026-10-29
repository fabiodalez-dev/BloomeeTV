"""Server tests without network: accounts, CSRF guard, library, lyrics parsing,
audio ranges against a fake googlevideo. LIVE=1 adds real YouTube calls."""
import gzip
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
TMP = tempfile.mkdtemp(prefix='musicweb-test-')
os.environ['MUSICWEB_HOME'] = TMP
os.environ['MUSICWEB_INSECURE'] = '1'

from musicweb import app, auth, db, library, lyrics, oauth, youtube  # noqa: E402

SONG = {'kind': 'song', 'title': 'Shape of You', 'videoId': 'JGwWNGJdvx8', 'subtitle': 'Ed Sheeran',
        'artists': [{'name': 'Ed Sheeran', 'id': 'UC0C-w0YjGpqDXGB8IHb662A'}],
        'album': {'name': 'Divide', 'id': 'MPREb_abc'}, 'thumbnail': 'https://lh3.googleusercontent.com/x=w120-h120',
        'duration': 234}


class Client:
    def __init__(self):
        self.cookies = {}

    def call(self, method, path, body=None, headers=None, csrf=True):
        raw = json.dumps(body).encode() if body is not None else b''
        env = {'REQUEST_METHOD': method, 'PATH_INFO': path.split('?')[0], 'QUERY_STRING': path.partition('?')[2],
               'CONTENT_LENGTH': str(len(raw)), 'wsgi.input': io.BytesIO(raw), 'REMOTE_ADDR': '10.0.0.1',
               'HTTP_COOKIE': '; '.join('%s=%s' % kv for kv in self.cookies.items())}
        if csrf:
            env['HTTP_X_REQUESTED_WITH'] = 'fabio-music'
        for k, v in (headers or {}).items():
            env['HTTP_' + k.upper().replace('-', '_')] = v
        out = {}

        def start(status, hdrs):
            out['status'] = int(status.split()[0])
            out['headers'] = hdrs
        data = b''.join(app.application(env, start))
        for k, v in out['headers']:
            if k == 'Set-Cookie':
                name, _, rest = v.partition('=')
                value = rest.split(';')[0]
                if 'Max-Age=0' in v:
                    self.cookies.pop(name, None)
                else:
                    self.cookies[name] = value
        h = dict(out['headers'])
        if h.get('Content-Type', '').startswith('application/json'):
            if h.get('Content-Encoding') == 'gzip':
                data = gzip.decompress(data)
            return out['status'], json.loads(data), h
        return out['status'], data, h


class Base(unittest.TestCase):
    def setUp(self):
        if os.path.exists(os.path.join(TMP, 'data')):
            shutil.rmtree(os.path.join(TMP, 'data'))
        self.admin = Client()
        s, d, _ = self.admin.call('POST', '/api/setup', {'username': 'fabio', 'password': 'password-lunga', 'displayName': 'Fabio'})
        self.assertEqual(s, 201, d)


class AuthTests(Base):
    def test_setup_once_and_session(self):
        s, d, _ = self.admin.call('GET', '/api/session')
        self.assertEqual((s, d['user']['admin']), (200, True))
        s, d, _ = Client().call('POST', '/api/setup', {'username': 'altro', 'password': 'password-lunga'})
        self.assertEqual(s, 403)

    def test_csrf_header_required(self):
        s, d, _ = self.admin.call('POST', '/api/logout', {}, csrf=False)
        self.assertEqual(s, 403)

    def test_invite_registration_single_use(self):
        s, d, _ = self.admin.call('POST', '/api/admin/invites', {'days': 3})
        code = d['code']
        guest = Client()
        s, d, _ = guest.call('POST', '/api/register', {'invite': code.replace('-', '').lower(), 'username': 'giulia', 'password': 'segreta123'})
        self.assertEqual(s, 201, d)
        s, d, _ = Client().call('POST', '/api/register', {'invite': code, 'username': 'marco', 'password': 'segreta123'})
        self.assertEqual(s, 400)
        s, d, _ = guest.call('GET', '/api/admin/users')
        self.assertEqual(s, 403)

    def test_login_logout_and_wrong_password(self):
        c = Client()
        s, d, _ = c.call('POST', '/api/login', {'username': 'FABIO', 'password': 'sbagliata'})
        self.assertEqual(s, 401)
        s, d, _ = c.call('POST', '/api/login', {'username': 'fabio', 'password': 'password-lunga'})
        self.assertEqual(s, 200)
        s, d, _ = c.call('POST', '/api/logout', {})
        s, d, _ = c.call('GET', '/api/session')
        self.assertEqual(s, 401)

    def test_login_rate_limit(self):
        c = Client()
        for _ in range(10):
            c.call('POST', '/api/login', {'username': 'fabio', 'password': 'x'})
        s, d, _ = c.call('POST', '/api/login', {'username': 'fabio', 'password': 'password-lunga'})
        self.assertEqual(s, 429)

    def test_disabled_user_loses_sessions(self):
        s, d, _ = self.admin.call('POST', '/api/admin/invites', {})
        g = Client()
        g.call('POST', '/api/register', {'invite': d['code'], 'username': 'ospite', 'password': 'segreta123'})
        uid = [u for u in self.admin.call('GET', '/api/admin/users')[1]['users'] if u['username'] == 'ospite'][0]['id']
        self.admin.call('PATCH', '/api/admin/users/%d' % uid, {'disabled': True})
        self.assertEqual(g.call('GET', '/api/session')[0], 401)

    def test_yt_cookie_encrypted_at_rest(self):
        con = db.connect()
        auth.save_yt_account(con, 1, {'cookie': 'SAPISID=segreto; X=1'}, 'Fabio')
        raw = con.execute('SELECT secret FROM yt_accounts').fetchone()[0]
        self.assertNotIn(b'segreto', raw)
        self.assertEqual(auth.yt_account(con, 1)['cookie'], 'SAPISID=segreto; X=1')


class LibraryTests(Base):
    def test_favorites_roundtrip_and_sanitizing(self):
        evil = dict(SONG, thumbnail='javascript:alert(1)', extra='x')
        s, d, _ = self.admin.call('PUT', '/api/favorites', {'item': evil})
        self.assertEqual(s, 200)
        self.assertIsNone(d['item']['thumbnail'])
        self.assertNotIn('extra', d['item'])
        favs = self.admin.call('GET', '/api/library')[1]['favorites']
        self.assertEqual(favs[0]['videoId'], SONG['videoId'])
        self.admin.call('DELETE', '/api/favorites/' + SONG['videoId'])
        self.assertEqual(self.admin.call('GET', '/api/library')[1]['favorites'], [])

    def test_bad_item_rejected(self):
        s, d, _ = self.admin.call('PUT', '/api/favorites', {'item': dict(SONG, videoId='../../etc')})
        self.assertEqual(s, 400)

    def test_playlists_are_private(self):
        s, d, _ = self.admin.call('POST', '/api/playlists', {'name': 'Estate', 'items': [SONG, SONG]})
        pid = d['id']
        self.assertEqual(self.admin.call('GET', '/api/playlists/%d' % pid)[1]['items'][1]['title'], 'Shape of You')
        s, d, _ = self.admin.call('POST', '/api/admin/invites', {})
        other = Client()
        other.call('POST', '/api/register', {'invite': d['code'], 'username': 'altro', 'password': 'segreta123'})
        self.assertEqual(other.call('GET', '/api/playlists/%d' % pid)[0], 404)
        self.assertEqual(other.call('DELETE', '/api/playlists/%d' % pid)[0], 404)
        self.admin.call('PUT', '/api/playlists/%d/items' % pid, {'items': [SONG]})
        self.assertEqual(self.admin.call('GET', '/api/playlists')[1]['playlists'][0]['count'], 1)

    def test_history_merges_one_listen_and_stats(self):
        self.admin.call('POST', '/api/history', {'item': SONG, 'seconds': 20})
        self.admin.call('POST', '/api/history', {'item': SONG, 'seconds': 200})
        items = self.admin.call('GET', '/api/history')[1]['items']
        self.assertEqual((len(items), items[0]['seconds']), (1, 200))
        st = self.admin.call('GET', '/api/stats?since=0')[1]
        self.assertEqual((st['plays'], st['artists'][0]['name'], st['minutes']), (1, 'Ed Sheeran', 3))

    def test_state_size_bound(self):
        s, d, _ = self.admin.call('PUT', '/api/state/settings', {'data': {'theme': 'light'}})
        self.assertEqual(s, 200)
        self.assertEqual(self.admin.call('GET', '/api/state/settings')[1]['data'], {'theme': 'light'})
        s, d, _ = self.admin.call('PUT', '/api/state/queue', {'data': 'x' * 600000})
        self.assertEqual(s, 400)


class FakeResponse(io.BytesIO):
    def __init__(self, data, headers=None):
        super().__init__(data)
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


class AudioTests(Base):
    FILE = bytes(range(256)) * 12000  # ~3 MB

    def fake_urlopen(self, req, timeout=None):
        url = req.full_url
        if url == 'https://www.youtube.com/':
            return FakeResponse(b'..."VISITOR_DATA":"vis123"...')
        if 'youtubei/v1/player' in url:
            body = json.loads(req.data)
            self.clients.append(body['context']['client']['clientName'])
            return FakeResponse(json.dumps({'playabilityStatus': {'status': 'OK'}, 'streamingData': {'adaptiveFormats': [
                {'itag': 251, 'url': 'https://rr.googlevideo.com/v?expire=9999999999&c=' + body['context']['client']['clientName'],
                 'mimeType': 'audio/webm; codecs="opus"', 'contentLength': str(len(self.FILE))}]}}).encode())
        if 'googlevideo' in url:
            if self.refuse and 'c=VISIONOS' in url:
                from urllib.error import HTTPError
                raise HTTPError(url, 403, 'Forbidden', {}, None)
            a, b = map(int, req.headers['Range'].split('=')[1].split('-'))
            return FakeResponse(self.FILE[a:b + 1])
        raise AssertionError(url)

    def setUp(self):
        super().setUp()
        self.clients, self.refuse = [], False
        p = mock.patch.object(youtube, 'urlopen', side_effect=self.fake_urlopen)
        p.start()
        self.addCleanup(p.stop)

    def test_needs_login(self):
        self.assertEqual(Client().call('GET', '/api/audio/JGwWNGJdvx8')[0], 401)

    def test_pieces_and_shared_cache(self):
        s, data, h = self.admin.call('GET', '/api/audio/JGwWNGJdvx8', headers={'Range': 'bytes=0-'})
        self.assertEqual((s, len(data), h['Content-Range']), (206, 512 * 1024, 'bytes 0-524287/%d' % len(self.FILE)))
        s, data, h = self.admin.call('GET', '/api/audio/JGwWNGJdvx8', headers={'Range': 'bytes=3000000-'})
        self.assertEqual(data, self.FILE[3000000:3072000])
        self.assertEqual(self.clients, ['VISIONOS'])  # resolved once, cached in SQLite
        s, data, h = self.admin.call('GET', '/api/audio/JGwWNGJdvx8', headers={'Range': 'bytes=5000000-'})
        self.assertEqual((s, h['Content-Range']), (416, 'bytes */%d' % len(self.FILE)))

    def test_refused_url_falls_back_to_next_client(self):
        self.refuse = True
        s, data, h = self.admin.call('GET', '/api/audio/JGwWNGJdvx8', headers={'Range': 'bytes=100-199'})
        self.assertEqual((s, data), (206, self.FILE[100:200]))
        self.assertEqual(self.clients, ['VISIONOS', 'IOS'])


class OAuthTests(Base):
    def setUp(self):
        super().setUp()
        self.calls = []
        self.state = 'pending'
        p = mock.patch.object(oauth, '_post', side_effect=self.fake_post)
        p.start()
        self.addCleanup(p.stop)
        q = mock.patch.object(youtube, 'api_json', side_effect=self.fake_menu)
        q.start()
        self.addCleanup(q.stop)

    def fake_post(self, url, data):
        self.calls.append((url, data))
        if url == oauth.DEVICE_URL:
            return {'device_code': 'DEV', 'user_code': 'ABCD-EFGH', 'verification_url': 'https://www.google.com/device', 'interval': 5, 'expires_in': 1800}
        if data.get('grant_type') == 'refresh_token':
            return {'access_token': 'tok2', 'expires_in': 3600}
        if self.state == 'pending':
            return {'error': 'authorization_pending'}
        return {'access_token': 'tok1', 'refresh_token': 'ref1', 'expires_in': 3600, 'token_type': 'Bearer'}

    def fake_menu(self, endpoint, data, account):
        assert account['oauth']['access_token'] in ('tok1', 'tok2')
        return {'x': {'activeAccountHeaderRenderer': {'accountName': {'simpleText': 'Fabio YT'}}}}

    def test_not_configured(self):
        s, d, _ = self.admin.call('POST', '/api/youtube-account/code', {})
        self.assertEqual(s, 400)
        self.assertFalse(self.admin.call('GET', '/api/session')[1]['youtubeCode'])

    def test_admin_config_validated(self):
        s, d, _ = self.admin.call('PUT', '/api/admin/google-oauth', {'clientId': 'nope', 'clientSecret': 'x'})
        self.assertEqual(s, 400)
        s, d, _ = self.admin.call('PUT', '/api/admin/google-oauth', {'clientId': '123-abc.apps.googleusercontent.com', 'clientSecret': 'GOCSPX-secretvalue'})
        self.assertEqual(s, 200)
        self.assertTrue(self.admin.call('GET', '/api/session')[1]['youtubeCode'])
        self.assertEqual(oct(os.stat(oauth.PATH).st_mode & 0o777), '0o600')

    def test_device_flow_links_account_and_refreshes(self):
        self.admin.call('PUT', '/api/admin/google-oauth', {'clientId': '123-abc.apps.googleusercontent.com', 'clientSecret': 'GOCSPX-secretvalue'})
        s, d, _ = self.admin.call('POST', '/api/youtube-account/code', {})
        self.assertEqual((s, d['userCode']), (200, 'ABCD-EFGH'))
        self.assertNotIn('DEV', json.dumps(d))  # il device code resta sul server
        self.assertEqual(self.admin.call('POST', '/api/youtube-account/code/check', {})[1]['status'], 'pending')
        self.state = 'ok'
        s, d, _ = self.admin.call('POST', '/api/youtube-account/code/check', {})
        self.assertEqual((d['status'], d['account']), ('ok', {'name': 'Fabio YT', 'method': 'code'}))
        con = db.connect()
        a = auth.yt_account(con, 1)
        a['oauth']['expires_at'] = db.now() + 10
        auth.save_yt_account(con, 1, {'oauth': a['oauth']}, 'Fabio YT')
        self.assertEqual(auth.yt_account_fresh(con, 1)['oauth']['access_token'], 'tok2')
        h = youtube.headers_for(auth.yt_account(con, 1))
        self.assertEqual(h['Authorization'], 'Bearer tok2')
        self.assertNotIn('Cookie', h)


class BatchTests(Base):
    def test_batch_favorites_skips_invalid_and_duplicates(self):
        other = dict(SONG, videoId='AAAAAAAAAAA', title='Altro')
        s, d, _ = self.admin.call('POST', '/api/favorites/batch', {'items': [SONG, other, {'kind': 'song'}, SONG]})
        self.assertEqual((s, d['added']), (200, 2))
        favs = self.admin.call('GET', '/api/library')[1]['favorites']
        self.assertEqual([f['videoId'] for f in favs], [SONG['videoId'], 'AAAAAAAAAAA'])


class PickAudioTests(unittest.TestCase):
    def fmt(self, itag, mime, avg, drc=False):
        f = {'itag': itag, 'mimeType': mime + '; codecs="x"', 'averageBitrate': avg, 'url': 'https://x/%d' % itag}
        if drc:
            f['isDrc'] = True
        return f

    def test_highest_bitrate_per_family(self):
        player = {'streamingData': {'adaptiveFormats': [
            self.fmt(249, 'audio/webm', 48000), self.fmt(251, 'audio/webm', 130000), self.fmt(774, 'audio/webm', 250000),
            self.fmt(774, 'audio/webm', 260000, drc=True), self.fmt(140, 'audio/mp4', 129000), self.fmt(141, 'audio/mp4', 255000),
            {'itag': 137, 'mimeType': 'video/mp4', 'averageBitrate': 4000000, 'url': 'https://x/v'}]}}
        self.assertEqual(youtube.pick_audio(player)['itag'], 774)
        self.assertFalse(youtube.pick_audio(player).get('isDrc'))
        self.assertEqual(youtube.pick_audio(player, alt=True)['itag'], 141)

    def test_falls_back_to_other_family(self):
        player = {'streamingData': {'adaptiveFormats': [self.fmt(140, 'audio/mp4', 129000)]}}
        self.assertEqual(youtube.pick_audio(player)['itag'], 140)
        self.assertIsNone(youtube.pick_audio({'streamingData': {}}))


class ThumbTests(Base):
    def test_only_google_image_hosts(self):
        for bad in ('http://lh3.googleusercontent.com/x', 'https://evil.com/a.png', 'https://googleusercontent.com.evil.com/x',
                    'https://127.0.0.1/x', 'file:///etc/passwd'):
            self.assertEqual(self.admin.call('GET', '/api/thumb?url=' + bad)[0], 400, bad)

    def test_needs_login(self):
        self.assertEqual(Client().call('GET', '/api/thumb?url=https://lh3.googleusercontent.com/x=w60-h60')[0], 401)


class LyricsTests(unittest.TestCase):
    def test_ttml_words(self):
        t = ('<tt xmlns="http://www.w3.org/ns/ttml"><body><div><p begin="9.731" end="12.105"><span begin="9.731" end="9.927">The</span> '
             '<span begin="9.927" end="10.284">club</span></p><p begin="1:02.5" end="1:04"><span begin="1:02.5" end="1:04">Ok</span></p></div></body></tt>')
        lines = lyrics.parse_ttml(t)
        self.assertEqual(lines[0]['text'], 'The club')
        self.assertEqual(lines[0]['words'][1]['t'], 9.927)
        self.assertEqual(lines[1]['t'], 62.5)

    def test_ttml_rejects_dtd(self):
        self.assertEqual(lyrics.parse_ttml('<!DOCTYPE x [<!ENTITY a "b">]><tt/>'), [])

    def test_lrc(self):
        lines = lyrics.parse_lrc('[00:01.50]Uno\n[00:03.00][00:10.00]Due\n[ar:Nome]\n[00:05.25]Tre')
        self.assertEqual([(l['t'], l['text']) for l in lines], [(1.5, 'Uno'), (3.0, 'Due'), (5.25, 'Tre'), (10.0, 'Due')])
        self.assertEqual(lines[0]['end'], 3.0)

    def test_clean_title(self):
        self.assertEqual(lyrics.clean_title('Song (Official Video) [feat. X]'), 'Song')


@unittest.skipUnless(os.environ.get('LIVE') == '1', 'LIVE=1 per le chiamate reali a YouTube')
class LiveTests(Base):
    def test_search_and_audio(self):
        s, d, _ = self.admin.call('POST', '/api/yt/search', {'query': 'Ed Sheeran Shape of You'})
        self.assertEqual(s, 200)
        self.assertIn('contents', d)
        s, data, h = self.admin.call('GET', '/api/audio/JGwWNGJdvx8', headers={'Range': 'bytes=0-'})
        self.assertEqual(s, 206, data)
        self.assertEqual(len(data), 512 * 1024)

    def test_lyrics(self):
        s, d, _ = self.admin.call('GET', '/api/lyrics?videoId=JGwWNGJdvx8&title=Shape%20of%20You&artist=Ed%20Sheeran&duration=234')
        self.assertEqual(s, 200)
        self.assertTrue(d['lyrics']['synced'])


if __name__ == '__main__':
    unittest.main()
