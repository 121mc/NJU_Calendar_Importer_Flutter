"""Calendar holiday API. Run behind an HTTPS reverse proxy."""
import base64
import hmac
import json
import os
import re
import sqlite3
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

DB = os.environ.get('CALENDAR_DB', '/var/lib/nju-calendar/calendar.db')
PASSWORD_FILE = os.environ.get('CALENDAR_PASSWORD_FILE', '/etc/nju-calendar/admin-password')

def validate_semester(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{4}-[123]', value):
        raise ValueError('学期格式应为 2026-2027-1')
    if int(value[5:9]) != int(value[:4]) + 1:
        raise ValueError('学年必须连续')
    return value

def validate_rules(rows):
    if not isinstance(rows, list) or len(rows) > 100:
        raise ValueError('最多保存100条规则')
    seen = set()
    result = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('规则格式错误')
        label = row.get('label')
        if label is not None:
            if not isinstance(label, str) or not label.strip() or len(label) > 30:
                raise ValueError('放假模块名称无效')
            label = label.strip()
        values = []
        for key in ('holiday', 'makeup'):
            value = row.get(key)
            if key == 'makeup' and value in (None, ''):
                values.append(None)
                continue
            if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
                raise ValueError('日期格式错误')
            date.fromisoformat(value)
            if value in seen:
                raise ValueError('日期重复：放假日和补课日不能重叠或重复')
            seen.add(value)
            values.append(value)
        rule = dict(zip(('holiday', 'makeup'), values))
        if label is not None:
            rule['label'] = label
        result.append(rule)
    return result

def connect():
    return sqlite3.connect(DB, timeout=10)

def initialize():
    Path(DB).parent.mkdir(parents=True, exist_ok=True)
    with connect() as db:
        db.execute('CREATE TABLE IF NOT EXISTS semesters (id TEXT PRIMARY KEY, rules TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0)')

class Handler(BaseHTTPRequestHandler):
    def send(self, status, data, mime='application/json; charset=utf-8'):
        body = json.dumps(data, ensure_ascii=False).encode() if isinstance(data, dict) else data
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        if status == 401:
            self.send_header('WWW-Authenticate', 'Basic realm="Calendar admin", charset="UTF-8"')
        self.end_headers()
        self.wfile.write(body)

    def authenticated(self):
        expected = 'Basic ' + base64.b64encode(('admin:' + Path(PASSWORD_FILE).read_text().strip()).encode()).decode()
        return hmac.compare_digest(self.headers.get('Authorization', ''), expected)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path in ('/admin', '/admin/'):
            if not self.authenticated():
                return self.send(401, {'error': '请使用管理员账号登录'})
            return self.send(200, Path(__file__).with_name('admin.html').read_bytes(), 'text/html; charset=utf-8')
        if url.path == '/api/semesters':
            with connect() as db:
                ids = [row[0] for row in db.execute('SELECT id FROM semesters ORDER BY id DESC')]
            return self.send(200, {'semesters': ids})
        if url.path == '/api/holidays':
            try:
                semester = validate_semester(parse_qs(url.query).get('semester', [''])[0])
            except ValueError as e:
                return self.send(400, {'error': str(e)})
            with connect() as db:
                row = db.execute('SELECT rules, revision FROM semesters WHERE id=?', (semester,)).fetchone()
            return self.send(200, {'semester': semester, 'rules': json.loads(row[0]) if row else [], 'revision': row[1] if row else 0})
        if url.path == '/':
            return self.send(200, b'<!doctype html><meta charset="utf-8"><title>NJU Calendar</title><h1>NJU Calendar</h1><a href="/admin">Admin</a>', 'text/html; charset=utf-8')
        self.send(404, {'error': 'Not found'})

    def do_PUT(self):
        if self.path != '/api/holidays':
            return self.send(404, {'error': 'Not found'})
        if not self.authenticated():
            return self.send(401, {'error': '需要管理员登录'})
        # JSON plus an explicit custom header prevents cross-origin form writes.
        if self.headers.get('X-Calendar-Admin') != '1' or self.headers.get('Content-Type') != 'application/json':
            return self.send(403, {'error': '无效管理请求'})
        origin = self.headers.get('Origin')
        if origin and origin != 'https://calendar.121mc.net':
            return self.send(403, {'error': '来源不允许'})
        try:
            length = int(self.headers.get('Content-Length', 0))
            if not 0 < length <= 65536:
                raise ValueError('请求大小无效')
            data = json.loads(self.rfile.read(length))
            semester = validate_semester(data.get('semester'))
            rules = validate_rules(data.get('rules'))
            revision = data.get('revision')
            if type(revision) is not int or revision < 0:
                raise ValueError('版本无效，请重新加载')
            with connect() as db:
                db.execute('BEGIN IMMEDIATE')
                row = db.execute('SELECT revision FROM semesters WHERE id=?', (semester,)).fetchone()
                if (row[0] if row else 0) != revision:
                    return self.send(409, {'error': '其他管理员已修改，请重新加载后再编辑'})
                db.execute('INSERT INTO semesters(id,rules,revision) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET rules=excluded.rules,revision=excluded.revision',
                           (semester, json.dumps(rules), revision+1))
            self.send(200, {'semester': semester, 'rules': rules, 'revision': revision+1})
        except (ValueError, TypeError, AttributeError) as e:
            self.send(400, {'error': str(e)})

if __name__ == '__main__':
    initialize()
    ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('PORT', '8765'))), Handler).serve_forever()
