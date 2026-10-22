// fun/lib/http-server: self-driven checks. Raw requests go out over
// ConnectSocket and the server is pumped with runOnce (single-threaded), so
// every assertion prints a boolean -- a stable snapshot with no external
// client.
use 'fun/lib/http-server.fun';
use 'fun/lib/http-auth.fun';
use 'fun/lib/lib-base64.fun';

fun hasRe(s, re)
  result = false;
  if s =~ re then result = true; end if;
end fun;

fun pump(s, n)
  for i = 1 to n loop
    exit when s.runOnce(300) = 0;
  end loop;
end fun;

fun rq(port, raw)
  var c = ConnectSocket('127.0.0.1', port);
  SendAll(c, raw.escape());
  result = c;
end fun;

fun getReq(port, path)
  result = rq(port, 'GET ' & path & ' HTTP/1.1\r\nHost: t\r\n\r\n');
end fun;

//--------------------------------------------------------------
// handlers and middleware
//--------------------------------------------------------------
var order = '';

fun mwA(req, res, nx)
  order &= 'A>';
  nx();
  order &= '<A';
end fun;

fun authMw(req, res, nx)
  order &= 'a>';
  if req.header('token') <> 'secret' then
    res.status(401).text('unauthorized');
  else
    nx();
    order &= '<a';
  end if;
end fun;

fun hello(req, res)
  res.text('hello');
end fun;

fun ordersH(req, res)
  res.text('orders');
end fun;

fun userH(req, res)
  res.json([id: req.param('id')]);
end fun;

fun echoH(req, res)
  res.text('echo:' & req.body);
end fun;

fun queryH(req, res)
  res.text('q=' & req.query('q') & ';z=' & req.query('z'));
end fun;

fun formH(req, res)
  var f = req.form();
  res.text('a=' & f['a'] & ';b=' & f['b']);
end fun;

fun cookiesH(req, res)
  res.text(req.cookie('a') & ':' & req.cookie('b'));
end fun;

fun setCookiesH(req, res)
  res.cookie('sid', 'abc', [path: '/', httpOnly: true, sameSite: 'Lax']);
  res.cookie('theme', 'dark', [path: '/']);
  res.text('cookies');
end fun;

fun clearCookieH(req, res)
  res.clearCookie('sid', [path: '/']);
  res.text('cleared');
end fun;

fun multiH(req, res)
  res.addHeader('X-Multi', 'one').addHeader('X-Multi', 'two').text('multi');
end fun;

fun badHeaderH(req, res)
  res.header('X-Bad', 'a' & 13.toChar() & 10.toChar() & 'X-Injected: b');
  res.text('bad');
end fun;

var users = new [];
var ua = new [];
ua['pass'] = 'secret';
ua['name'] = 'alice';
ua['roles'] = new [];
ua['roles']['admin'] = true;
users['alice'] = ua;

var ub = new [];
ub['pass'] = 'p:a';
ub['name'] = 'bob';
ub['roles'] = new [];
users['bob'] = ub;

fun verifyBasic(req, c)
  var u = users[c['user']];
  if u = nil or u['pass'] <> c['pass'] then
    result = false;
    return;
  end if;
  var p = new [];
  p['ok'] = true;
  p['user'] = u['name'];
  p['roles'] = u['roles'];
  result = p;
end fun;

fun verifyBlocked(req, c)
  if c['user'] = 'blocked' then
    var r = new [];
    r['status'] = 403;
    r['message'] = 'blocked by policy';
    var hs = new [];
    hs['X-Reason'] = 'policy';
    r['headers'] = hs;
    result = r;
  else
    result = verifyBasic(req, c);
  end if;
end fun;

fun verifyTrue(req, c)
  result = true;
end fun;

fun verifyCustom(req, c)
  var r = new [];
  r['status'] = 401;
  r['message'] = 'custom unauthorized';
  var hs = new [];
  hs['WWW-Authenticate'] = 'Basic realm="custom"';
  r['headers'] = hs;
  result = r;
end fun;

fun defaultWho(req, res)
  res.json([user: req.auth['user'], scheme: req.auth['scheme']]);
end fun;

fun secureMe(req, res)
  res.json([user: req.auth['user'], admin: req.auth['roles']['admin']]);
end fun;

fun optionalWho(req, res)
  if req.auth = nil then
    res.text('anonymous');
  else
    res.text('user:' & req.auth['user']);
  end if;
end fun;

fun rawWho(req, res)
  if req.credentials = nil then
    res.text('no-cred');
  else
    res.text('user:' & req.credentials['user']);
  end if;
end fun;

fun boom(req, res)
  raise 'kaboom';
end fun;

var fixture = '/tmp/fun-http-fixture.txt';
fixture.save('static file');

var s = HttpServer(0);
s.Use(mwA);
s.get('/', hello);
s.get('/users/:id', userH);
s.post('/echo', echoH);
s.get('/query', queryH);
s.post('/form', formH);
s.get('/cookies', cookiesH);
s.get('/setcookies', setCookiesH);
s.get('/clearcookie', clearCookieH);
s.get('/multi', multiH);
s.get('/badheader', badHeaderH);
s.get('/boom', boom);
var secure = s.group('/secure');
secure.Use(HttpBasicAuth(verifyBasic, [realm: 'api']));
secure.get('/me', secureMe);
var opt = s.group('/opt');
opt.Use(HttpBasicAuth(verifyBasic, [realm: 'opt', optional: true]));
opt.get('/who', optionalWho);
var raw = s.group('/raw');
raw.Use(HttpBasicAuth());
raw.get('/who', rawWho);
var blocked = s.group('/blocked');
blocked.Use(HttpBasicAuth(verifyBlocked, [realm: 'blocked']));
blocked.get('/me', secureMe);
var dflt = s.group('/default');
dflt.Use(HttpBasicAuth(verifyTrue, [realm: 'def']));
dflt.get('/who', defaultWho);
var cust = s.group('/custom');
cust.Use(HttpBasicAuth(verifyCustom, [realm: 'ignored']));
cust.get('/me', hello);
var api = s.group('/api');
api.Use(authMw);
api.get('/orders', ordersH);
s.static('/assets', '/tmp');

var p = s.listen();
?. 'port > 0: ' & (p > 0);

//--------------------------------------------------------------
// 1. plain GET + middleware order
//--------------------------------------------------------------
var c1 = getReq(p, '/');
pump(s, 5);
var r1 = RecvSome(c1, 4096);
?. 'get 200: ' & hasRe(r1, %^HTTP/1\.1\x20200%);
?. 'get body: ' & hasRe(r1, %\r\n\r\nhello$%);
?. 'order1: ' & order;
CloseSocket(c1);

//--------------------------------------------------------------
// 2. path parameter
//--------------------------------------------------------------
var c2 = getReq(p, '/users/42');
pump(s, 5);
var r2 = RecvSome(c2, 4096);
?. 'param 200: ' & hasRe(r2, %^HTTP/1\.1\x20200%);
?. 'param json: ' & hasRe(r2, %"id":"42"%);
CloseSocket(c2);

//--------------------------------------------------------------
// 3. no route -> 404, extra segment -> 404, HEAD -> 405 (no fallback)
//--------------------------------------------------------------
var c3 = getReq(p, '/missing');
pump(s, 5);
var r3 = RecvSome(c3, 4096);
?. 'missing 404: ' & hasRe(r3, %^HTTP/1\.1\x20404%);
CloseSocket(c3);

var c4 = getReq(p, '/users/42/extra');
pump(s, 5);
var r4 = RecvSome(c4, 4096);
?. 'extra-seg 404: ' & hasRe(r4, %^HTTP/1\.1\x20404%);
CloseSocket(c4);

var c5 = rq(p, 'HEAD / HTTP/1.1\r\nHost: t\r\n\r\n');
pump(s, 5);
var r5 = RecvSome(c5, 4096);
?. 'head 405: ' & hasRe(r5, %^HTTP/1\.1\x20405%);
?. 'head allow: ' & hasRe(r5, %Allow:\x20GET%);
CloseSocket(c5);

//--------------------------------------------------------------
// 4. POST body
//--------------------------------------------------------------
var c6 = rq(p, 'POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 4\r\n\r\nping');
pump(s, 5);
var r6 = RecvSome(c6, 4096);
?. 'post echo: ' & hasRe(r6, %echo:ping%);
CloseSocket(c6);

//--------------------------------------------------------------
// 5. method not allowed (only GET on /)
//--------------------------------------------------------------
var c7 = rq(p, 'DELETE / HTTP/1.1\r\nHost: t\r\n\r\n');
pump(s, 5);
var r7 = RecvSome(c7, 4096);
?. 'del 405: ' & hasRe(r7, %^HTTP/1\.1\x20405%);
?. 'order untouched: ' & order;
CloseSocket(c7);

//--------------------------------------------------------------
// 6. group: prefix + group middleware, short-circuit and pass-through
//--------------------------------------------------------------
var c8 = getReq(p, '/api/orders');
pump(s, 5);
var r8 = RecvSome(c8, 4096);
?. 'api no-token 401: ' & hasRe(r8, %^HTTP/1\.1\x20401%);
?. 'order after 401: ' & order;
CloseSocket(c8);

var c9 = rq(p, 'GET /api/orders HTTP/1.1\r\nHost: t\r\ntoken: secret\r\n\r\n');
pump(s, 5);
var r9 = RecvSome(c9, 4096);
?. 'api token 200: ' & hasRe(r9, %^HTTP/1\.1\x20200%);
?. 'api body: ' & hasRe(r9, %\r\n\r\norders$%);
?. 'order after 200: ' & order;
CloseSocket(c9);

//--------------------------------------------------------------
// 7. static files: hit, content-type, miss, traversal
//--------------------------------------------------------------
var c10 = getReq(p, '/assets/fun-http-fixture.txt');
pump(s, 5);
var r10 = RecvSome(c10, 4096);
?. 'static 200: ' & hasRe(r10, %^HTTP/1\.1\x20200%);
?. 'static ctype: ' & hasRe(r10, %Content-Type:\x20text/plain%);
?. 'static body: ' & hasRe(r10, %\r\n\r\nstatic\x20file$%);
CloseSocket(c10);

var c11 = getReq(p, '/assets/nope.txt');
pump(s, 5);
var r11 = RecvSome(c11, 4096);
?. 'static miss 404: ' & hasRe(r11, %^HTTP/1\.1\x20404%);
CloseSocket(c11);

var c12 = getReq(p, '/assets/../etc/hosts');
pump(s, 5);
var r12 = RecvSome(c12, 4096);
?. 'traversal 404: ' & hasRe(r12, %^HTTP/1\.1\x20404%);
CloseSocket(c12);

//--------------------------------------------------------------
// 8. handler error -> 500
//--------------------------------------------------------------
var c13 = getReq(p, '/boom');
pump(s, 5);
var r13 = RecvSome(c13, 4096);
?. 'boom 500: ' & hasRe(r13, %^HTTP/1\.1\x20500%);
?. 'boom message: ' & hasRe(r13, %kaboom%);
CloseSocket(c13);

//--------------------------------------------------------------
// 9. URL/form decoding, cookies and multi-value headers
//--------------------------------------------------------------
var c14 = getReq(p, '/query?q=hello%20world&z=a+b');
pump(s, 5);
var r14 = RecvSome(c14, 4096);
?. 'query decoded: ' & hasRe(r14, %\r\n\r\nq=hello\x20world;z=a\x20b$%);
CloseSocket(c14);

var fbody = 'a=1&b=hello%20world';
var c15 = rq(p, 'POST /form HTTP/1.1\r\nHost: t\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: ' & fbody.length() & '\r\n\r\n' & fbody);
pump(s, 5);
var r15 = RecvSome(c15, 4096);
?. 'form decoded: ' & hasRe(r15, %\r\n\r\na=1;b=hello\x20world$%);
CloseSocket(c15);

var c16 = rq(p, 'GET /cookies HTTP/1.1\r\nHost: t\r\nCookie: a=1; b=two\r\n\r\n');
pump(s, 5);
var r16 = RecvSome(c16, 4096);
?. 'cookies parsed: ' & hasRe(r16, %\r\n\r\n1:two$%);
CloseSocket(c16);

var c17 = getReq(p, '/setcookies');
pump(s, 5);
var r17 = RecvSome(c17, 4096);
?. 'cookie set sid: ' & hasRe(r17, %Set-Cookie:\x20sid=abc;\x20Path=/;\x20HttpOnly;\x20SameSite=Lax%);
?. 'cookie set theme: ' & hasRe(r17, %Set-Cookie:\x20theme=dark;\x20Path=/%);
CloseSocket(c17);

var c18 = getReq(p, '/clearcookie');
pump(s, 5);
var r18 = RecvSome(c18, 4096);
?. 'cookie cleared: ' & hasRe(r18, %Set-Cookie:\x20sid=;\x20Path=/;\x20Max-Age=0%);
CloseSocket(c18);

var c19 = getReq(p, '/multi');
pump(s, 5);
var r19 = RecvSome(c19, 4096);
?. 'multi header: ' & hasRe(r19, %X-Multi:\x20one\r\nX-Multi:\x20two%);
CloseSocket(c19);

var c20 = getReq(p, '/badheader');
pump(s, 5);
var r20 = RecvSome(c20, 4096);
?. 'bad header 500: ' & hasRe(r20, %^HTTP/1\.1\x20500%);
?. 'bad header message: ' & hasRe(r20, %invalid\x20header%);
CloseSocket(c20);

//--------------------------------------------------------------
// 10. Basic auth middleware
//--------------------------------------------------------------
var goodB64 = Str2Base64('alice:secret');
var c21 = rq(p, 'GET /secure/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & goodB64 & '\r\n\r\n');
pump(s, 5);
var r21 = RecvSome(c21, 4096);
?. 'auth ok 200: ' & hasRe(r21, %^HTTP/1\.1\x20200%);
?. 'auth user: ' & hasRe(r21, %"user":"alice"%);
?. 'auth role: ' & hasRe(r21, %"admin":true%);
CloseSocket(c21);

var c22 = getReq(p, '/secure/me');
pump(s, 5);
var r22 = RecvSome(c22, 4096);
?. 'auth missing 401: ' & hasRe(r22, %^HTTP/1\.1\x20401%);
?. 'auth challenge: ' & hasRe(r22, %WWW-Authenticate:\x20Basic\x20realm="api"%);
CloseSocket(c22);

var badB64 = Str2Base64('alice:wrong');
var c23 = rq(p, 'GET /secure/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & badB64 & '\r\n\r\n');
pump(s, 5);
var r23 = RecvSome(c23, 4096);
?. 'auth wrong 401: ' & hasRe(r23, %^HTTP/1\.1\x20401%);
CloseSocket(c23);

var blockB64 = Str2Base64('blocked:x');
var c24 = rq(p, 'GET /blocked/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & blockB64 & '\r\n\r\n');
pump(s, 5);
var r24 = RecvSome(c24, 4096);
?. 'auth blocked 403: ' & hasRe(r24, %^HTTP/1\.1\x20403%);
?. 'auth blocked header: ' & hasRe(r24, %X-Reason:\x20policy%);
?. 'auth blocked body: ' & hasRe(r24, %blocked\x20by\x20policy%);
CloseSocket(c24);

var c25 = getReq(p, '/opt/who');
pump(s, 5);
var r25 = RecvSome(c25, 4096);
?. 'auth optional anonymous: ' & hasRe(r25, %\r\n\r\nanonymous$%);
CloseSocket(c25);

var c26 = rq(p, 'GET /opt/who HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & goodB64 & '\r\n\r\n');
pump(s, 5);
var r26 = RecvSome(c26, 4096);
?. 'auth optional user: ' & hasRe(r26, %\r\n\r\nuser:alice$%);
CloseSocket(c26);

var c26b = rq(p, 'GET /opt/who HTTP/1.1\r\nHost: t\r\nAuthorization: Basic !!!\r\n\r\n');
pump(s, 5);
var r26b = RecvSome(c26b, 4096);
?. 'auth optional bad 401: ' & hasRe(r26b, %^HTTP/1\.1\x20401%);
CloseSocket(c26b);

var c27 = getReq(p, '/raw/who');
pump(s, 5);
var r27 = RecvSome(c27, 4096);
?. 'auth parse-only empty: ' & hasRe(r27, %\r\n\r\nno-cred$%);
CloseSocket(c27);

var c28 = rq(p, 'GET /raw/who HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & goodB64 & '\r\n\r\n');
pump(s, 5);
var r28 = RecvSome(c28, 4096);
?. 'auth parse-only user: ' & hasRe(r28, %\r\n\r\nuser:alice$%);
CloseSocket(c28);

var c29 = rq(p, 'GET /secure/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic !!!\r\n\r\n');
pump(s, 5);
var r29 = RecvSome(c29, 4096);
?. 'auth malformed 401: ' & hasRe(r29, %^HTTP/1\.1\x20401%);
CloseSocket(c29);

var c30 = rq(p, 'GET /secure/me HTTP/1.1\r\nHost: t\r\nAuthorization: basic ' & goodB64 & '\r\n\r\n');
pump(s, 5);
var r30 = RecvSome(c30, 4096);
?. 'auth lower scheme 200: ' & hasRe(r30, %^HTTP/1\.1\x20200%);
CloseSocket(c30);

var bobB64 = Str2Base64('bob:p:a');
var c31 = rq(p, 'GET /secure/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & bobB64 & '\r\n\r\n');
pump(s, 5);
var r31 = RecvSome(c31, 4096);
?. 'auth colon pass 200: ' & hasRe(r31, %^HTTP/1\.1\x20200%);
?. 'auth colon user: ' & hasRe(r31, %"user":"bob"%);
CloseSocket(c31);

var c32 = rq(p, 'GET /default/who HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & goodB64 & '\r\n\r\n');
pump(s, 5);
var r32 = RecvSome(c32, 4096);
?. 'auth default true 200: ' & hasRe(r32, %^HTTP/1\.1\x20200%);
?. 'auth default user: ' & hasRe(r32, %"user":"alice"%);
?. 'auth default scheme: ' & hasRe(r32, %"scheme":"basic"%);
CloseSocket(c32);

var customB64 = Str2Base64('custom:x');
var c33 = rq(p, 'GET /custom/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic ' & customB64 & '\r\n\r\n');
pump(s, 5);
var r33 = RecvSome(c33, 4096);
?. 'auth custom 401: ' & hasRe(r33, %^HTTP/1\.1\x20401%);
?. 'auth custom challenge: ' & hasRe(r33, %WWW-Authenticate:\x20Basic\x20realm="custom"%);
?. 'auth custom body: ' & hasRe(r33, %custom\x20unauthorized%);
CloseSocket(c33);

//--------------------------------------------------------------
// 11. address strings: 'ip:port' and ':port' (all interfaces)
//--------------------------------------------------------------
var s2 = HttpServer('127.0.0.1:0');
?. 'addr ip:port: ' & (s2.listen() > 0);
s2.stop();

var s3 = HttpServer(':0');
?. 'addr :port: ' & (s3.listen() > 0);
s3.stop();

s.stop();
?. 'ok';
