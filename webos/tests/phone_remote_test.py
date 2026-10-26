import sys, os, unittest, threading, time, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from phone_remote import PhoneRemote, metadata, valid_command
try:
    from urllib.request import Request, urlopen
    from urllib.error import HTTPError
except ImportError:
    from urllib2 import Request, urlopen, HTTPError

class RemoteTest(unittest.TestCase):
    def setUp(self):
        self.remote=PhoneRemote()
        self.pair=self.remote.start('127.0.0.1',port=0,bind='127.0.0.1')
        self.remote.tick({'state':{'title':'Song','queueTotal':2,'queue':[{'title':'Song'}]}})
    def tearDown(self): self.remote.close()
    def request(self,path,body=None,token=None,origin=None):
        headers={'Content-Type':'application/json'}
        if token: headers['Authorization']='Bearer '+token
        if origin: headers['Origin']=origin
        req=Request(self.pair['url']+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
        try:
            r=urlopen(req,timeout=10)
            return r.getcode(),json.loads(r.read().decode())
        except HTTPError as e:return e.code,json.loads(e.read().decode())
    def token(self):
        code,data=self.request('/pair',{'code':self.pair['code']})
        self.assertEqual(code,200);self.assertEqual(data['protocol'],1)
        return data['session']
    def test_real_http_pairing_auth_expiry_and_sanitization(self):
        self.assertEqual(self.request('/state')[0],401)
        self.assertEqual(self.request('/pair',{'code':'000000'})[0],403)
        token=self.token()
        self.assertEqual(self.request('/state',token=token)[1]['title'],'Song')
        self.assertEqual(self.request('/state',token=token,origin='http://evil.test')[0],403)
        self.remote.pair_until=0
        self.assertEqual(self.request('/pair',{'code':self.pair['code']})[0],403)
        self.assertEqual(self.request('/state',token=token)[0],200)
        self.remote.updated=0
        self.assertEqual(self.request('/state',token=token)[0],503)
    def test_command_waits_for_tv_ack_and_close_revokes(self):
        token=self.token();result=[]
        t=threading.Thread(target=lambda:result.append(self.request('/command',{'action':'next'},token)))
        t.start()
        for _ in range(100):
            if self.remote.pending:break
            time.sleep(.01)
        command=self.remote.tick({'state':{}})['command']
        self.assertEqual(command['action'],'next')
        self.assertEqual(self.request('/command',{'action':'next'},token)[0],409)
        self.remote.tick({'state':{},'ack':command['id']})
        t.join(2);self.assertEqual(result[0][0],200)
        self.remote.close()
        self.assertEqual(self.remote.token,'')
    def test_authenticated_browse_returns_only_sanitized_metadata(self):
        token=self.token();result=[]
        self.assertEqual(self.request('/browse',{'kind':'search','query':'song'})[0],401)
        self.assertEqual(self.request('/browse',{'kind':'collection','id':'http://evil'},token)[0],400)
        t=threading.Thread(target=lambda:result.append(self.request('/browse',{'kind':'search','query':'song'},token)))
        t.start()
        for _ in range(100):
            if self.remote.catalog_pending:break
            time.sleep(.01)
        command=self.remote.tick({'state':{}})['command']
        self.assertEqual(command['action'],'browse')
        self.assertEqual(self.request('/state',token=token)[0],200)
        self.remote.tick({'state':{},'ack':command['id'],'response':{'items':[{'id':'0-1','kind':'song','title':'Song','url':'SECRET','token':'SECRET'}],'cookie':'SECRET'}})
        t.join(2);self.assertEqual(result[0][0],200)
        self.assertNotIn('SECRET',json.dumps(result[0][1]))
        self.assertEqual(result[0][1]['items'][0]['title'],'Song')
    def test_pause_is_not_blocked_by_a_pending_search(self):
        token=self.token();search_result=[];control_result=[]
        search=threading.Thread(target=lambda:search_result.append(self.request('/browse',{'kind':'search','query':'song'},token)))
        search.start()
        for _ in range(100):
            if self.remote.catalog_pending:break
            time.sleep(.01)
        control=threading.Thread(target=lambda:control_result.append(self.request('/command',{'action':'pause'},token)))
        control.start()
        for _ in range(100):
            if self.remote.pending:break
            time.sleep(.01)
        commands=self.remote.tick({'state':{}})['commands']
        self.assertEqual(len(commands),2)
        pause=next(c for c in commands if c['action']=='pause')
        browse=next(c for c in commands if c['action']=='browse')
        self.remote.tick({'state':{},'acks':[{'id':pause['id'],'response':{}}]})
        control.join(2);self.assertEqual(control_result[0][0],200);self.assertFalse(search_result)
        self.remote.tick({'state':{},'acks':[{'id':browse['id'],'response':{'items':[]}}]})
        search.join(2);self.assertEqual(search_result[0][0],200)
    def test_playlist_writes_are_not_supported(self):
        token=self.token()
        for action in ('createPlaylist','saveQueue','playlistAdd','playlistRemove','playlistRename'):
            self.assertEqual(self.request('/command',{'action':action,'value':'0-1'},token)[0],400)
    def test_validation_and_credentials_are_never_exposed(self):
        for body in [{'action':'shell'}, {'action':'volume','value':2}, {'action':'seek','value':1.5}, {'action':'queue','value':True}]:
            self.assertFalse(valid_command(body))
        data=metadata({'title':'Song','cookie':'SECRET','queue':[{'title':'S','url':'SECRET','token':'SECRET'}]})
        self.assertNotIn('SECRET',json.dumps(data))
    def test_wrong_codes_lock_pairing(self):
        for _ in range(5): self.request('/pair',{'code':'000000'})
        self.assertEqual(self.request('/pair',{'code':self.pair['code']})[0],403)

if __name__=='__main__':unittest.main()
