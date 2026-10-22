// fun/lib/http-bearer: self-driven checks. Raw requests go out over
// ConnectSocket and the server is pumped with runOnce, so every assertion is
// a stable boolean snapshot.
use 'fun/lib/http-server.fun';
use 'fun/lib/http-bearer.fun';

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

fun verifyBearer(req, c)
  if c['token'] = 'good-token' then
    var p = new [];
    p['sub'] = 'alice';
    p['roles'] = new [];
    p['roles']['admin'] = true;
    result = p;
  else
    result = false;
  end if;
end fun;

fun verifyTrue(req, c)
  result = true;
end fun;

fun verifyBlocked(req, c)
  if c['token'] = 'blocked' then
    var r = new [];
    r['status'] = 403;
    r['message'] = 'blocked by policy';
    var hs = new [];
    hs['X-Reason'] = 'policy';
    r['headers'] = hs;
    result = r;
  else
    result = verifyBearer(req, c);
  end if;
end fun;

fun verifyCustom(req, c)
  var r = new [];
  r['status'] = 401;
  r['message'] = 'custom unauthorized';
  var hs = new [];
  hs['WWW-Authenticate'] = 'Bearer realm="custom"';
  r['headers'] = hs;
  result = r;
end fun;

fun verifyLeak(req, c)
  var r = new [];
  r['sub'] = 'leak';
  r['token'] = 'secret';
  result = r;
end fun;

fun bearerWho(req, res)
  res.json([sub: req.auth['sub'], scheme: req.auth['scheme'], hasToken: req.auth['token'] <> nil, hasCred: req.credentials <> nil]);
end fun;

fun defaultWho(req, res)
  res.json([scheme: req.auth['scheme']]);
end fun;

fun optionalWho(req, res)
  if req.auth = nil then
    res.text('anonymous');
  else
    res.text('sub:' & req.auth['sub']);
  end if;
end fun;

fun rawWho(req, res)
  if req.credentials = nil then
    res.text('no-cred');
  else
    res.text('token:' & req.credentials['token']);
  end if;
end fun;

var s = HttpServer(0);
var api = s.group('/api');
api.Use(HttpBearerAuth(verifyBearer, [realm: 'api']));
api.get('/me', bearerWho);
var opt = s.group('/opt');
opt.Use(HttpBearerAuth(verifyBearer, [realm: 'opt', optional: true]));
opt.get('/who', optionalWho);
var raw = s.group('/raw');
raw.Use(HttpBearerAuth());
raw.get('/who', rawWho);
var dflt = s.group('/default');
dflt.Use(HttpBearerAuth(verifyTrue, [realm: 'def']));
dflt.get('/who', defaultWho);
var blocked = s.group('/blocked');
blocked.Use(HttpBearerAuth(verifyBlocked, [realm: 'blocked']));
blocked.get('/me', bearerWho);
var cust = s.group('/custom');
cust.Use(HttpBearerAuth(verifyCustom, [realm: 'ignored']));
cust.get('/me', bearerWho);
var leak = s.group('/leak');
leak.Use(HttpBearerAuth(verifyLeak, [realm: 'leak']));
leak.get('/me', bearerWho);
var p = s.listen();

var c1 = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer good-token\r\n\r\n');
pump(s, 5);
var r1 = RecvSome(c1, 4096);
?. 'bearer ok 200: ' & hasRe(r1, %^HTTP/1\.1\x20200%);
?. 'bearer sub: ' & hasRe(r1, %"sub":"alice"%);
?. 'bearer scheme: ' & hasRe(r1, %"scheme":"bearer"%);
?. 'bearer no token in auth: ' & hasRe(r1, %"hasToken":false%);
?. 'bearer credentials cleared: ' & hasRe(r1, %"hasCred":false%);
CloseSocket(c1);

var c2 = getReq(p, '/api/me');
pump(s, 5);
var r2 = RecvSome(c2, 4096);
?. 'bearer missing 401: ' & hasRe(r2, %^HTTP/1\.1\x20401%);
?. 'bearer missing challenge: ' & hasRe(r2, %WWW-Authenticate:\x20Bearer\x20realm="api"$%m);
?. 'bearer missing no error: ' & not hasRe(r2, %error=%);
CloseSocket(c2);

var c3 = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer nope\r\n\r\n');
pump(s, 5);
var r3 = RecvSome(c3, 4096);
?. 'bearer wrong 401: ' & hasRe(r3, %^HTTP/1\.1\x20401%);
?. 'bearer invalid token error: ' & hasRe(r3, %WWW-Authenticate:\x20Bearer\x20realm="api",\x20error="invalid_token"%);
CloseSocket(c3);

var c4 = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer\r\n\r\n');
pump(s, 5);
var r4 = RecvSome(c4, 4096);
?. 'bearer malformed 401: ' & hasRe(r4, %^HTTP/1\.1\x20401%);
?. 'bearer invalid request error: ' & hasRe(r4, %WWW-Authenticate:\x20Bearer\x20realm="api",\x20error="invalid_request"%);
CloseSocket(c4);

var c4b = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer abc=def\r\n\r\n');
pump(s, 5);
var r4b = RecvSome(c4b, 4096);
?. 'bearer bad padding 401: ' & hasRe(r4b, %^HTTP/1\.1\x20401%);
CloseSocket(c4b);

var c4c = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer =\r\n\r\n');
pump(s, 5);
var r4c = RecvSome(c4c, 4096);
?. 'bearer only padding 401: ' & hasRe(r4c, %^HTTP/1\.1\x20401%);
CloseSocket(c4c);

var c5 = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: bearer good-token\r\n\r\n');
pump(s, 5);
var r5 = RecvSome(c5, 4096);
?. 'bearer lower scheme 200: ' & hasRe(r5, %^HTTP/1\.1\x20200%);
CloseSocket(c5);

var c5b = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer    good-token\r\n\r\n');
pump(s, 5);
var r5b = RecvSome(c5b, 4096);
?. 'bearer multiple spaces 200: ' & hasRe(r5b, %^HTTP/1\.1\x20200%);
CloseSocket(c5b);

var c6 = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Basic YWxpY2U6c2VjcmV0\r\n\r\n');
pump(s, 5);
var r6 = RecvSome(c6, 4096);
?. 'bearer rejects basic: ' & hasRe(r6, %^HTTP/1\.1\x20401%);
CloseSocket(c6);

var c7 = getReq(p, '/opt/who');
pump(s, 5);
var r7 = RecvSome(c7, 4096);
?. 'bearer optional anonymous: ' & hasRe(r7, %\r\n\r\nanonymous$%);
CloseSocket(c7);

var c8 = rq(p, 'GET /opt/who HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer good-token\r\n\r\n');
pump(s, 5);
var r8 = RecvSome(c8, 4096);
?. 'bearer optional user: ' & hasRe(r8, %\r\n\r\nsub:alice$%);
CloseSocket(c8);

var c9 = rq(p, 'GET /opt/who HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer nope\r\n\r\n');
pump(s, 5);
var r9 = RecvSome(c9, 4096);
?. 'bearer optional bad 401: ' & hasRe(r9, %^HTTP/1\.1\x20401%);
CloseSocket(c9);

var c9b = rq(p, 'GET /opt/who HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer\r\n\r\n');
pump(s, 5);
var r9b = RecvSome(c9b, 4096);
?. 'bearer optional malformed 401: ' & hasRe(r9b, %^HTTP/1\.1\x20401%);
CloseSocket(c9b);

var c10 = getReq(p, '/raw/who');
pump(s, 5);
var r10 = RecvSome(c10, 4096);
?. 'bearer parse-only empty: ' & hasRe(r10, %\r\n\r\nno-cred$%);
CloseSocket(c10);

var c10b = rq(p, 'GET /raw/who HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer\r\n\r\n');
pump(s, 5);
var r10b = RecvSome(c10b, 4096);
?. 'bearer parse-only malformed: ' & hasRe(r10b, %\r\n\r\nno-cred$%);
CloseSocket(c10b);

var c11 = rq(p, 'GET /raw/who HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer abc-._~+/=\r\n\r\n');
pump(s, 5);
var r11 = RecvSome(c11, 4096);
?. 'bearer token68: ' & hasRe(r11, %\r\n\r\ntoken:abc-._~\+/=$%);
CloseSocket(c11);

var c12 = rq(p, 'GET /api/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer bad token\r\n\r\n');
pump(s, 5);
var r12 = RecvSome(c12, 4096);
?. 'bearer bad token68 401: ' & hasRe(r12, %^HTTP/1\.1\x20401%);
CloseSocket(c12);

var c13 = rq(p, 'GET /default/who HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer good-token\r\n\r\n');
pump(s, 5);
var r13 = RecvSome(c13, 4096);
?. 'bearer default true 200: ' & hasRe(r13, %^HTTP/1\.1\x20200%);
?. 'bearer default scheme: ' & hasRe(r13, %"scheme":"bearer"%);
CloseSocket(c13);

var c14 = rq(p, 'GET /blocked/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer blocked\r\n\r\n');
pump(s, 5);
var r14 = RecvSome(c14, 4096);
?. 'bearer blocked 403: ' & hasRe(r14, %^HTTP/1\.1\x20403%);
?. 'bearer blocked header: ' & hasRe(r14, %X-Reason:\x20policy%);
?. 'bearer blocked body: ' & hasRe(r14, %blocked\x20by\x20policy%);
?. 'bearer blocked no challenge: ' & not hasRe(r14, %WWW-Authenticate%);
CloseSocket(c14);

var c15 = rq(p, 'GET /custom/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer custom\r\n\r\n');
pump(s, 5);
var r15 = RecvSome(c15, 4096);
?. 'bearer custom 401: ' & hasRe(r15, %^HTTP/1\.1\x20401%);
?. 'bearer custom challenge: ' & hasRe(r15, %WWW-Authenticate:\x20Bearer\x20realm="custom"%);
?. 'bearer custom body: ' & hasRe(r15, %custom\x20unauthorized%);
CloseSocket(c15);

var c16 = rq(p, 'GET /leak/me HTTP/1.1\r\nHost: t\r\nAuthorization: Bearer good-token\r\n\r\n');
pump(s, 5);
var r16 = RecvSome(c16, 4096);
?. 'bearer strips verifier token: ' & (hasRe(r16, %"sub":"leak"%) and hasRe(r16, %"hasToken":false%));
CloseSocket(c16);

s.stop();
?. 'ok';
