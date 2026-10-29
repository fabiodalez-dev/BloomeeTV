#!/usr/bin/env python3
"""Local server for development: the API plus the built UI (../ui/dist), with
the same single-page fallback the .htaccess applies in production."""
import mimetypes
import os
import sys
from socketserver import ThreadingMixIn
from wsgiref.simple_server import WSGIRequestHandler, WSGIServer, make_server

os.environ.setdefault('MUSICWEB_INSECURE', '1')
os.environ.setdefault('MUSICWEB_HOME', os.path.join(os.path.dirname(os.path.abspath(__file__)), '.dev'))

from musicweb.app import application as api  # noqa: E402

DIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ui', 'dist')


def app(env, start):
    path = env.get('PATH_INFO', '/')
    if path.startswith('/api/'):
        return api(env, start)
    file = os.path.normpath(os.path.join(DIST, path.lstrip('/')))
    if not file.startswith(os.path.normpath(DIST)) or not os.path.isfile(file):
        file = os.path.join(DIST, 'index.html')
    with open(file, 'rb') as f:
        data = f.read()
    start('200 OK', [('Content-Type', mimetypes.guess_type(file)[0] or 'application/octet-stream'), ('Content-Length', str(len(data)))])
    return [data]


class Server(ThreadingMixIn, WSGIServer):
    daemon_threads = True


class Quiet(WSGIRequestHandler):
    def log_message(self, *a):
        pass


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8799
    print('http://127.0.0.1:%d' % port)
    make_server('127.0.0.1', port, app, server_class=Server, handler_class=Quiet).serve_forever()
