"""Bloomee Remote protocol v1, compatible with the LG Python 2.7 runtime.
Only sanitized playback metadata and a bounded command mailbox cross the LAN.
"""
from __future__ import print_function
import json, time, threading, random, binascii, os, hmac, math, re
try:
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from socketserver import ThreadingMixIn
except ImportError:
    from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer
    from SocketServer import ThreadingMixIn
try:
    string_types = (basestring,)
    integer_types = (int, long)
except NameError:
    string_types = (str,)
    integer_types = (int,)

def remote_id(value): return isinstance(value,string_types) and len(value)<80 and re.match(r'^[0-9]+-[0-9]+$',value) is not None
def valid_browse(body):
    if not isinstance(body,dict) or set(body)-set(['kind','query','filter','source','id','cursor']):return False
    if body.get('cursor') is not None:return len(body)==1 and remote_id(body['cursor'])
    if body.get('kind') not in ('search','playlists','collection'):return False
    if body['kind']=='search' and (not isinstance(body.get('query'),string_types) or not body['query'].strip() or len(body['query'])>160):return False
    if body.get('filter') is not None and body['filter'] not in ('songs','playlists'):return False
    if body.get('source') is not None and body['source'] not in ('all','local','youtube','jellyfin'):return False
    return body['kind']!='collection' or remote_id(body.get('id'))

def catalog_metadata(value):
    if not isinstance(value,dict):return {}
    def text(v):return v[:500] if isinstance(v,string_types) else ''
    rows=value.get('items',[])
    if not isinstance(rows,list):rows=[]
    items=[]
    for row in rows[:2000]:
        if not isinstance(row,dict) or not remote_id(row.get('id')) or row.get('kind') not in ('song','playlist'):continue
        item=dict(id=row['id'],kind=row['kind'],title=text(row.get('title')),artist=text(row.get('artist')),source=text(row.get('source')),editable=False)
        if remote_id(row.get('owner')):item['owner']=row['owner']
        items.append(item)
    errors=value.get('errors',[])
    return dict(items=items,title=text(value.get('title')),editable=False,
        total=value.get('total') if isinstance(value.get('total'),integer_types) else len(items),
        next=value.get('next') if remote_id(value.get('next')) else None,
        errors=[text(e) for e in errors[:10]] if isinstance(errors,list) else [])

def valid_command(body):
    if not isinstance(body, dict) or set(body) - set(['action', 'value']): return False
    action, value = body.get('action'), body.get('value')
    if action in ('play', 'pause', 'next', 'previous'): return len(body) == 1
    if action == 'browse':return valid_browse(value)
    if action in ('playItem','enqueueItem','shuffleItem'):return remote_id(value)
    if action == 'shuffle': return isinstance(value, bool)
    if action == 'repeat': return value in ('off', 'all')
    if isinstance(value, bool): return False
    if action == 'volume': return isinstance(value, (int, float)) and 0 <= value <= 1
    if action == 'seek': return isinstance(value, integer_types) and 0 <= value <= 604800000
    if action == 'queue': return isinstance(value, integer_types) and 0 <= value < 100000
    return False

def metadata(state):
    def number(key, maximum, default=0):
        value = state.get(key, default)
        return max(0, min(maximum, value)) if isinstance(value, (int, float)) and not math.isnan(value) and not math.isinf(value) else default
    def text(value): return value[:500] if isinstance(value, string_types) else ''
    queue = state.get('queue', [])
    if not isinstance(queue, list): queue = []
    return dict(name='Bloomee LG webOS', title=text(state.get('title')), artist=text(state.get('artist')),
        playing=state.get('playing') is True, positionMs=number('positionMs', 604800000),
        durationMs=number('durationMs', 604800000), volume=number('volume', 1, 1),
        shuffle=state.get('shuffle') is True, repeat='all' if state.get('repeat') == 'all' else 'off',
        index=state.get('index') if isinstance(state.get('index'), integer_types) else -1,
        queueTotal=int(number('queueTotal', 100000)),
        queue=[dict(title=text(q.get('title')), artist=text(q.get('artist'))) for q in queue[:500] if isinstance(q, dict)])

class Server(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

class PhoneRemote(object):
    def __init__(self):
        self.lock = threading.RLock()
        self.server = None
        self.timer = None
        self.token = ''
        self.code = ''
        self.failures = 0
        self.pair_until = self.until = self.updated = 0
        self.state = metadata({})
        self.pending = None
        self.catalog_pending = None
        self.sequence = 0

    def active(self): return self.server is not None and time.time() < self.until

    def start(self, host, port=18794, bind='0.0.0.0'):
        self.close()
        owner = self
        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.0'
            def log_message(self, *args): pass
            def reply(self, status, data):
                raw = json.dumps(data).encode('utf-8')
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(raw)))
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                try: self.wfile.write(raw)
                except IOError: pass
            def do_GET(self): self.handle_request(False)
            def do_POST(self): self.handle_request(True)
            def handle_request(self, post):
                self.connection.settimeout(5)
                body = None
                try:
                    if post:
                        size = int(self.headers.get('Content-Length') or -1)
                        if size < 0 or size > 2048: return self.reply(400, {'error':'Richiesta non valida'})
                        body = json.loads(self.rfile.read(size).decode('utf-8'))
                    status, result = owner.request(self.path, post, body, self.headers.get('Authorization'), self.headers.get('Origin'))
                    self.reply(status, result)
                except Exception: self.reply(400, {'error':'Richiesta non valida'})
        with self.lock:
            self.server = Server((bind, port), Handler)
            self.token = binascii.hexlify(os.urandom(32)).decode('ascii')
            self.code = '%06d' % random.SystemRandom().randint(100000, 999999)
            self.failures = 0
            self.pair_until = time.time() + 300
            self.until = time.time() + 43200
            thread = threading.Thread(target=self.server.serve_forever)
            thread.daemon = True
            thread.start()
            self.timer = threading.Timer(43200, self.close)
            self.timer.daemon = True
            self.timer.start()
            return {'url':'http://%s:%d' % (host, self.server.server_port), 'code':self.code, 'seconds':300}

    def request(self, path, post, body, authorization, origin=None):
        with self.lock:
            if origin is not None or not self.active(): return 403, {'error':'Accesso negato'}
            if path == '/pair' and post:
                code = body.get('code') if isinstance(body, dict) else None
                if self.failures >= 5 or time.time() >= self.pair_until or not isinstance(code, string_types) or not hmac.compare_digest(code.encode('utf-8'), self.code.encode('utf-8')):
                    self.failures += 1
                    return 403, {'error':'Codice errato o scaduto'}
                return 200, {'session':self.token, 'protocol':1, 'capabilities':['catalog'], 'platform':'webos', 'name':'Bloomee LG webOS'}
            if authorization != 'Bearer ' + self.token: return 401, {'error':'Abbina nuovamente la TV'}
            if time.time() - self.updated > 5: return 503, {'error':'Apri Bloomee sulla TV'}
            if path == '/state' and not post: return 200, self.state
            if path == '/browse' and post: body={'action':'browse','value':body}
            elif path != '/command' or not post: return 404, {'error':'Percorso non disponibile'}
            if not valid_command(body): return 400, {'error':'Comando non valido'}
            slot='catalog_pending' if body['action']=='browse' else 'pending'
            if getattr(self,slot): return 409, {'error':'Attendi la richiesta precedente'}
            if body['action'] == 'queue' and body['value'] >= self.state['queueTotal']: return 400, {'error':'Brano non disponibile'}
            self.sequence += 1
            pending = {'id':self.sequence, 'command':body, 'event':threading.Event(), 'error':None,'result':None}
            setattr(self,slot,pending)
        completed = pending['event'].wait(40 if body['action'] in ('browse','playItem','enqueueItem','shuffleItem','playlistAdd') else 8)
        with self.lock:
            if getattr(self,slot) is pending: setattr(self,slot,None)
            if not completed:return 503, {'error':'La TV non ha risposto in tempo. Riprova.'}
            if pending['error']:return 400, {'error':pending['error'][:240]}
            return 200, pending['result'] if body['action']=='browse' else {'ok':True}

    def tick(self, body):
        with self.lock:
            self.state = metadata(body.get('state', {}))
            self.updated = time.time()
            acks=body.get('acks',[])
            if not isinstance(acks,list):acks=[]
            acks=acks[:10]+[{'id':body.get('ack'),'error':body.get('error'),'response':body.get('response')}]
            for slot in ('pending','catalog_pending'):
                pending=getattr(self,slot)
                if not pending:continue
                for ack in acks:
                    if not isinstance(ack,dict) or ack.get('id')!=pending['id']:continue
                    pending['error']=ack.get('error') if isinstance(ack.get('error'),string_types) else None
                    pending['result']=catalog_metadata(ack.get('response'))
                    setattr(self,slot,None);pending['event'].set();break
            commands=[dict(id=p['id'],**p['command']) for p in (self.pending,self.catalog_pending) if p]
            return {'active':self.active(),'command':commands[0] if commands else None,'commands':commands}

    def close(self):
        with self.lock:
            server, self.server = self.server, None
            if self.timer: self.timer.cancel(); self.timer = None
            self.until = 0
            self.code = self.token = ''
            for slot in ('pending','catalog_pending'):
                pending=getattr(self,slot)
                if pending:
                    pending['error']='closed';pending['event'].set();setattr(self,slot,None)
        if server: server.shutdown(); server.server_close()
