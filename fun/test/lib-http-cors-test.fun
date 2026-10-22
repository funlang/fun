// fun/lib/http-cors: self-driven checks. Raw requests go out over
// ConnectSocket and the server is pumped with runOnce, so every assertion is
// a stable boolean snapshot.
use 'fun/lib/http-server.fun';
use 'fun/lib/http-cors.fun';

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

fun helloH(req, res)
  res.json([ok: true]);
end fun;

fun boomH(req, res)
  raise 'kaboom';
end fun;

fun authMw(req, res, nx)
  if req.header('authorization') = nil then
    res.status(401).text('unauthorized');
  else
    nx();
  end if;
end fun;

fun checkOrigin(origin)
  result = origin = 'https://sub.example.com';
end fun;

fun varyH(req, res)
  res.addHeader('Vary', 'Accept-Encoding');
  res.text('vary');
end fun;

var s1 = HttpServer(0);
s1.Use(HttpCors([
  origins: ['https://app.example', 'https://second.example', 'null'],
  methods: ['GET', 'POST'],
  headers: ['Content-Type', 'Authorization'],
  exposeHeaders: ['X-Request-Id'],
  maxAge: 30
]));
s1.get('/hello', helloH);
s1.get('/vary', varyH);
s1.get('/boom', boomH);
var api = s1.group('/api');
api.Use(authMw);
api.get('/me', helloH);
var p1 = s1.listen();

var c1 = rq(p1, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: Authorization\r\n\r\n');
pump(s1, 5);
var r1 = RecvSome(c1, 4096);
?. 'cors preflight 204: ' & hasRe(r1, %^HTTP/1\.1\x20204%);
?. 'cors allow origin: ' & hasRe(r1, %Access-Control-Allow-Origin:\x20https://app.example%);
?. 'cors allow methods: ' & hasRe(r1, %Access-Control-Allow-Methods:\x20GET,\x20POST%);
?. 'cors allow headers: ' & hasRe(r1, %Access-Control-Allow-Headers:\x20Content-Type,\x20Authorization%);
?. 'cors max age: ' & hasRe(r1, %Access-Control-Max-Age:\x2030%);
?. 'cors preflight vary: ' & hasRe(r1, %Vary:\x20Origin,\x20Access-Control-Request-Method,\x20Access-Control-Request-Headers%);
CloseSocket(c1);

var c1b = rq(p1, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\naccess-control-request-method: post\r\naccess-control-request-headers: authorization\r\n\r\n');
pump(s1, 5);
var r1b = RecvSome(c1b, 4096);
?. 'cors lowercase preflight: ' & hasRe(r1b, %^HTTP/1\.1\x20204%);
CloseSocket(c1b);

var c2 = rq(p1, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://evil.example\r\nAccess-Control-Request-Method: POST\r\n\r\n');
pump(s1, 5);
var r2 = RecvSome(c2, 4096);
?. 'cors bad origin 403: ' & hasRe(r2, %^HTTP/1\.1\x20403%);
?. 'cors bad origin no acao: ' & not hasRe(r2, %Access-Control-Allow-Origin%);
CloseSocket(c2);

var c3 = rq(p1, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: PATCH\r\n\r\n');
pump(s1, 5);
var r3 = RecvSome(c3, 4096);
?. 'cors bad method 403: ' & hasRe(r3, %^HTTP/1\.1\x20403%);
CloseSocket(c3);

var c4 = rq(p1, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: X-Other\r\n\r\n');
pump(s1, 5);
var r4 = RecvSome(c4, 4096);
?. 'cors bad header 403: ' & hasRe(r4, %^HTTP/1\.1\x20403%);
CloseSocket(c4);

var c5 = rq(p1, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\n\r\n');
pump(s1, 5);
var r5 = RecvSome(c5, 4096);
?. 'cors actual 200: ' & hasRe(r5, %^HTTP/1\.1\x20200%);
?. 'cors actual acao: ' & hasRe(r5, %Access-Control-Allow-Origin:\x20https://app.example%);
?. 'cors actual expose: ' & hasRe(r5, %Access-Control-Expose-Headers:\x20X-Request-Id%);
?. 'cors actual vary: ' & hasRe(r5, %Vary:\x20Origin%);
CloseSocket(c5);

var c5b = rq(p1, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://second.example\r\n\r\n');
pump(s1, 5);
var r5b = RecvSome(c5b, 4096);
?. 'cors second origin: ' & hasRe(r5b, %Access-Control-Allow-Origin:\x20https://second.example%);
CloseSocket(c5b);

var c5c = rq(p1, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://evil.example\r\n\r\n');
pump(s1, 5);
var r5c = RecvSome(c5c, 4096);
?. 'cors actual bad origin no acao: ' & not hasRe(r5c, %Access-Control-Allow-Origin%);
CloseSocket(c5c);

var c5d = rq(p1, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: null\r\n\r\n');
pump(s1, 5);
var r5d = RecvSome(c5d, 4096);
?. 'cors explicit null origin: ' & hasRe(r5d, %Access-Control-Allow-Origin:\x20null%);
CloseSocket(c5d);

var c5e = rq(p1, 'GET /vary HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\n\r\n');
pump(s1, 5);
var r5e = RecvSome(c5e, 4096);
?. 'cors vary merge: ' & (hasRe(r5e, %Vary:\x20Origin%) and hasRe(r5e, %Vary:\x20Accept-Encoding%));
CloseSocket(c5e);

var c6 = getReq(p1, '/hello');
pump(s1, 5);
var r6 = RecvSome(c6, 4096);
?. 'cors no origin no acao: ' & not hasRe(r6, %Access-Control-Allow-Origin%);
CloseSocket(c6);

var c7 = rq(p1, 'GET /missing HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\n\r\n');
pump(s1, 5);
var r7 = RecvSome(c7, 4096);
?. 'cors 404 keeps acao: ' & (hasRe(r7, %^HTTP/1\.1\x20404%) and hasRe(r7, %Access-Control-Allow-Origin:\x20https://app.example%));
CloseSocket(c7);

var c8 = rq(p1, 'GET /boom HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\n\r\n');
pump(s1, 5);
var r8 = RecvSome(c8, 4096);
?. 'cors 500 keeps acao: ' & (hasRe(r8, %^HTTP/1\.1\x20500%) and hasRe(r8, %Access-Control-Allow-Origin:\x20https://app.example%));
CloseSocket(c8);

var c8b = rq(p1, 'POST /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nContent-Length: 0\r\n\r\n');
pump(s1, 5);
var r8b = RecvSome(c8b, 4096);
?. 'cors 405 keeps acao: ' & (hasRe(r8b, %^HTTP/1\.1\x20405%) and hasRe(r8b, %Access-Control-Allow-Origin:\x20https://app.example%));
CloseSocket(c8b);

var c9 = rq(p1, 'OPTIONS /api/me HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: GET\r\n\r\n');
pump(s1, 5);
var r9 = RecvSome(c9, 4096);
?. 'cors preflight bypass auth: ' & hasRe(r9, %^HTTP/1\.1\x20204%);
?. 'cors preflight not 401: ' & not hasRe(r9, %^HTTP/1\.1\x20401%);
CloseSocket(c9);

var c10 = rq(p1, 'GET /api/me HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\n\r\n');
pump(s1, 5);
var r10 = RecvSome(c10, 4096);
?. 'cors 401 keeps acao: ' & (hasRe(r10, %^HTTP/1\.1\x20401%) and hasRe(r10, %Access-Control-Allow-Origin:\x20https://app.example%));
CloseSocket(c10);

var c11 = rq(p1, 'OPTIONS /nope HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: GET\r\n\r\n');
pump(s1, 5);
var r11 = RecvSome(c11, 4096);
?. 'cors preflight unknown path: ' & hasRe(r11, %^HTTP/1\.1\x20204%);
CloseSocket(c11);

s1.stop();

var s2 = HttpServer(0);
s2.Use(HttpCors([origins: ['https://app.example'], credentials: true]));
s2.get('/hello', helloH);
var p2 = s2.listen();

var c12 = rq(p2, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\n\r\n');
pump(s2, 5);
var r12 = RecvSome(c12, 4096);
?. 'cors credentials acao: ' & hasRe(r12, %Access-Control-Allow-Origin:\x20https://app.example%);
?. 'cors credentials acac: ' & hasRe(r12, %Access-Control-Allow-Credentials:\x20true%);
CloseSocket(c12);

var c13 = rq(p2, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://app.example\r\nAccess-Control-Request-Method: GET\r\n\r\n');
pump(s2, 5);
var r13 = RecvSome(c13, 4096);
?. 'cors credentials preflight: ' & (hasRe(r13, %^HTTP/1\.1\x20204%) and hasRe(r13, %Access-Control-Allow-Credentials:\x20true%));
CloseSocket(c13);

s2.stop();

var s3 = HttpServer(0);
s3.Use(HttpCors());
s3.get('/hello', helloH);
var p3 = s3.listen();

var c14 = rq(p3, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://any.example\r\n\r\n');
pump(s3, 5);
var r14 = RecvSome(c14, 4096);
?. 'cors default wildcard: ' & hasRe(r14, %Access-Control-Allow-Origin:\x20\*%);
?. 'cors default no credentials: ' & not hasRe(r14, %Access-Control-Allow-Credentials%);
CloseSocket(c14);

var c15 = rq(p3, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: null\r\nAccess-Control-Request-Method: GET\r\nAccess-Control-Request-Headers: X-Any\r\n\r\n');
pump(s3, 5);
var r15 = RecvSome(c15, 4096);
?. 'cors default preflight: ' & hasRe(r15, %^HTTP/1\.1\x20204%);
?. 'cors default reflect header: ' & hasRe(r15, %Access-Control-Allow-Headers:\x20X-Any%);
CloseSocket(c15);

s3.stop();

var s4 = HttpServer(0);
s4.Use(HttpCors([originCheck: checkOrigin]));
s4.get('/hello', helloH);
var p4 = s4.listen();

var c16 = rq(p4, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://sub.example.com\r\n\r\n');
pump(s4, 5);
var r16 = RecvSome(c16, 4096);
?. 'cors origincheck allow: ' & (hasRe(r16, %^HTTP/1\.1\x20200%) and hasRe(r16, %Access-Control-Allow-Origin:\x20https://sub.example.com%));
CloseSocket(c16);

var c17 = rq(p4, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://other.example\r\n\r\n');
pump(s4, 5);
var r17 = RecvSome(c17, 4096);
?. 'cors origincheck deny: ' & not hasRe(r17, %Access-Control-Allow-Origin%);
CloseSocket(c17);

var c18 = rq(p4, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://sub.example.com\r\nAccess-Control-Request-Method: GET\r\n\r\n');
pump(s4, 5);
var r18 = RecvSome(c18, 4096);
?. 'cors origincheck preflight: ' & hasRe(r18, %^HTTP/1\.1\x20204%);
CloseSocket(c18);

s4.stop();

var s5 = HttpServer(0);
s5.Use(HttpCors([origins: 'https://single.example', optionsStatus: 200, maxAge: 0]));
s5.get('/hello', helloH);
var p5 = s5.listen();

var c19 = rq(p5, 'GET /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://single.example\r\n\r\n');
pump(s5, 5);
var r19 = RecvSome(c19, 4096);
?. 'cors string origin: ' & hasRe(r19, %Access-Control-Allow-Origin:\x20https://single.example%);
CloseSocket(c19);

var c20 = rq(p5, 'OPTIONS /hello HTTP/1.1\r\nHost: t\r\nOrigin: https://single.example\r\nAccess-Control-Request-Method: GET\r\n\r\n');
pump(s5, 5);
var r20 = RecvSome(c20, 4096);
?. 'cors options status 200: ' & hasRe(r20, %^HTTP/1\.1\x20200%);
?. 'cors max age zero: ' & not hasRe(r20, %Access-Control-Max-Age%);
CloseSocket(c20);

s5.stop();

var bad = false;
try
  var x = HttpCors([origins: ['*'], credentials: true]);
except
  bad = true;
end try;
?. 'cors wildcard credentials rejected: ' & bad;

?. 'ok';
