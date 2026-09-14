import base64
import json
import tempfile
import threading
import unittest
import urllib.request
import urllib.error
from pathlib import Path
import app

class ApiTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        app.DB=str(Path(self.tmp.name)/'test.db')
        app.PASSWORD_FILE=str(Path(self.tmp.name)/'password')
        Path(app.PASSWORD_FILE).write_text('test-only-password')
        app.initialize()
        self.server=app.ThreadingHTTPServer(('127.0.0.1',0),app.Handler)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.base='http://127.0.0.1:'+str(self.server.server_port)
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
    def request(self,path,body=None,auth=False,origin=None):
        headers={}
        if auth: headers['Authorization']='Basic '+base64.b64encode(b'admin:test-only-password').decode()
        if body is not None: headers.update({'Content-Type':'application/json','X-Calendar-Admin':'1'})
        if origin: headers['Origin']=origin
        req=urllib.request.Request(self.base+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method='PUT' if body is not None else 'GET')
        try:r=urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:r=e
        with r:return r.status,r.read()
    def test_authorization_and_roundtrip(self):
        payload={'semester':'2026-2027-1','revision':0,'rules':[{'label':'国庆节','holiday':'2026-10-01','makeup':'2026-10-10'}]}
        self.assertEqual(self.request('/admin')[0],401)
        self.assertEqual(self.request('/admin',auth=True)[0],200)
        self.assertEqual(self.request('/api/holidays',payload)[0],401)
        self.assertEqual(self.request('/api/holidays',payload,True,'https://evil.example')[0],403)
        self.assertEqual(self.request('/api/holidays',payload,True)[0],200)
        status,body=self.request('/api/holidays?semester=2026-2027-1')
        self.assertEqual(json.loads(body)['rules'],payload['rules'])
        self.assertEqual(self.request('/api/holidays',payload,True)[0],409)
        self.assertEqual(json.loads(self.request('/api/holidays?semester=2025-2026-2')[1])['rules'],[])
        payload.update(revision=1,rules=[])
        self.assertEqual(self.request('/api/holidays',payload,True)[0],200)
    def test_bad_dates_and_conflicts(self):
        for rules in [[{'holiday':'2026-02-30'}],[{'holiday':'2026-10-01','makeup':'2026-10-01'}],[{'holiday':'2026-10-01'},{'holiday':'2026-10-01'}]]:
            self.assertEqual(self.request('/api/holidays',{'semester':'2026-2027-1','revision':0,'rules':rules},True)[0],400)
        self.assertEqual(self.request('/api/holidays?semester=invalid')[0],400)

    def test_optional_module_labels_are_validated_and_kept_in_order(self):
        payload={'semester':'2026-2027-1','revision':0,'rules':[
            {'label':'国庆节','holiday':'2026-10-02'},
            {'label':'国庆节','holiday':'2026-10-01', 'makeup': None},
        ]}
        status, body = self.request('/api/holidays', payload, True)
        self.assertEqual(status, 200)
        saved = json.loads(body)['rules']
        self.assertEqual([rule['label'] for rule in saved], ['国庆节', '国庆节'])
        self.assertIsNone(saved[1]['makeup'])
        payload.update(revision=1, rules=[{'label':' '*31, 'holiday':'2026-10-01'}])
        self.assertEqual(self.request('/api/holidays', payload, True)[0], 400)

if __name__=='__main__':unittest.main()
