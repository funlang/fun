// fun/lib/http-server: self-driven checks. Raw requests go out over
// ConnectSocket and the server is pumped with runOnce (single-threaded), so
// every assertion prints a boolean -- a stable snapshot with no external
// client.
use 'fun/lib/http-server.fun';

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
s.get('/boom', boom);
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
// 9. address strings: 'ip:port' and ':port' (all interfaces)
//--------------------------------------------------------------
var s2 = HttpServer('127.0.0.1:0');
?. 'addr ip:port: ' & (s2.listen() > 0);
s2.stop();

var s3 = HttpServer(':0');
?. 'addr :port: ' & (s3.listen() > 0);
s3.stop();

s.stop();
?. 'ok';
