// fun/lib/http-session: self-driven checks. Raw requests go out over
// ConnectSocket and the server is pumped with runOnce, so every assertion is
// a stable boolean snapshot.
use 'fun/lib/http-server.fun';
use 'fun/lib/http-session.fun';

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

fun getSid(port, path, sid)
  result = rq(port, 'GET ' & path & ' HTTP/1.1\r\nHost: t\r\nCookie: sid=' & sid & '\r\n\r\n');
end fun;

// Set-Cookie: sid=<value>; ...
fun cookieSid(resp, name)
  result = '';
  var lines = split(/\r?\n/, resp);
  var key = 'Set-Cookie: ' & name & '=';
  for i = 0 to lines.@count() - 1 do
    var ln = lines[i];
    if ln.subpos(key) = 0 then
      var v = ln.substr(key.length());
      var e = v.subpos(';');
      if e >= 0 then v = v.substr(0, e); end if;
      result = v;
      return;
    end if;
  end do;
end fun;

fun readH(req, res)
  if req.session['user'] = nil then
    res.text('none');
  else
    res.text('user:' & req.session['user']);
  end if;
end fun;

fun writeH(req, res)
  req.session['user'] = 'alice';
  res.text('written');
end fun;

fun incH(req, res)
  req.session['count'] = (req.session['count'] or 0) + 1;
  res.text('count:' & req.session['count']);
end fun;

fun logoutH(req, res)
  req.session = nil;
  res.text('out');
end fun;

fun regenH(req, res)
  req.session['user'] = 'alice';
  SessionRegenerate(req);
  res.text('regen');
end fun;

class CTestStore()
  var map = new [];

  fun get(sid)
    result = map[sid];
  end fun;

  fun set(sid, data, ttl)
    map[sid] = data;
    result = true;
  end fun;

  fun destroy(sid)
    map[sid] = nil;
    result = true;
  end fun;
end class;

var s = HttpServer(0);
s.Use(HttpSession([name: 'sid', ttl: 60, maxAge: 0, sameSite: 'Lax']));
s.get('/read', readH);
s.get('/write', writeH);
s.get('/inc', incH);
s.get('/logout', logoutH);
s.get('/regen', regenH);
var p = s.listen();

// 1. read-only request: no session, no cookie
var c1 = getReq(p, '/read');
pump(s, 5);
var r1 = RecvSome(c1, 4096);
?. 'session read empty: ' & hasRe(r1, %\r\n\r\nnone$%);
?. 'session read no cookie: ' & not hasRe(r1, %Set-Cookie%);
CloseSocket(c1);

// 2. write creates a cookie with secure defaults
var c2 = getReq(p, '/write');
pump(s, 5);
var r2 = RecvSome(c2, 4096);
var sid1 = cookieSid(r2, 'sid');
?. 'session write cookie: ' & (sid1.length() = 36);
?. 'session cookie httponly: ' & hasRe(r2, %HttpOnly%);
?. 'session cookie samesite: ' & hasRe(r2, %SameSite=Lax%);
?. 'session cookie path: ' & hasRe(r2, %Path=/%);
CloseSocket(c2);

// 3. next request loads the session
var c3 = getSid(p, '/read', sid1);
pump(s, 5);
var r3 = RecvSome(c3, 4096);
?. 'session read user: ' & hasRe(r3, %\r\n\r\nuser:alice$%);
?. 'session read no resend: ' & not hasRe(r3, %Set-Cookie%);
CloseSocket(c3);

// 4. existing session mutation persists without a new cookie
var c4 = getSid(p, '/inc', sid1);
pump(s, 5);
var r4 = RecvSome(c4, 4096);
?. 'session inc 1: ' & hasRe(r4, %\r\n\r\ncount:1$%);
?. 'session inc no cookie: ' & not hasRe(r4, %Set-Cookie%);
CloseSocket(c4);

var c5 = getSid(p, '/inc', sid1);
pump(s, 5);
var r5 = RecvSome(c5, 4096);
?. 'session inc 2: ' & hasRe(r5, %\r\n\r\ncount:2$%);
CloseSocket(c5);

// 5. another client has no session
var c6 = getReq(p, '/read');
pump(s, 5);
var r6 = RecvSome(c6, 4096);
?. 'session isolated: ' & hasRe(r6, %\r\n\r\nnone$%);
CloseSocket(c6);

// 6. regenerate rotates the SID, old SID dies, data survives
var c7 = getSid(p, '/regen', sid1);
pump(s, 5);
var r7 = RecvSome(c7, 4096);
var sid2 = cookieSid(r7, 'sid');
?. 'session regen cookie: ' & (sid2.length() = 36 and sid2 <> sid1);
CloseSocket(c7);

var c8 = getSid(p, '/read', sid1);
pump(s, 5);
var r8 = RecvSome(c8, 4096);
?. 'session old sid dead: ' & hasRe(r8, %\r\n\r\nnone$%);
CloseSocket(c8);

var c9 = getSid(p, '/read', sid2);
pump(s, 5);
var r9 = RecvSome(c9, 4096);
?. 'session new sid alive: ' & hasRe(r9, %\r\n\r\nuser:alice$%);
CloseSocket(c9);

// 7. logout clears the cookie and the store
var c10 = getSid(p, '/logout', sid2);
pump(s, 5);
var r10 = RecvSome(c10, 4096);
?. 'session logout clears: ' & hasRe(r10, %Set-Cookie:\x20sid=;\x20Path=/;\x20Max-Age=0%);
CloseSocket(c10);

var c11 = getSid(p, '/read', sid2);
pump(s, 5);
var r11 = RecvSome(c11, 4096);
?. 'session logout dead: ' & hasRe(r11, %\r\n\r\nnone$%);
CloseSocket(c11);

// 8. unknown SID is treated as stale and cleared
var c12 = getSid(p, '/read', 'bogus');
pump(s, 5);
var r12 = RecvSome(c12, 4096);
?. 'session stale clear: ' & hasRe(r12, %Set-Cookie:\x20sid=;\x20Path=/;\x20Max-Age=0%);
CloseSocket(c12);

s.stop();

// 9. secure + sameSite Strict + cookie maxAge
var s2 = HttpServer(0);
s2.Use(HttpSession([secure: true, sameSite: 'Strict', maxAge: 120]));
s2.get('/write', writeH);
var p2 = s2.listen();
var c13 = getReq(p2, '/write');
pump(s2, 5);
var r13 = RecvSome(c13, 4096);
?. 'session secure: ' & hasRe(r13, %Secure%);
?. 'session strict: ' & hasRe(r13, %SameSite=Strict%);
?. 'session maxage: ' & hasRe(r13, %Max-Age=120%);
CloseSocket(c13);
s2.stop();

// 10. TTL expiry
var s3 = HttpServer(0);
s3.Use(HttpSession([ttl: 0]));
s3.get('/write', writeH);
s3.get('/read', readH);
var p3 = s3.listen();
var c14 = getReq(p3, '/write');
pump(s3, 5);
var r14 = RecvSome(c14, 4096);
var sid3 = cookieSid(r14, 'sid');
CloseSocket(c14);
var c15 = getSid(p3, '/read', sid3);
pump(s3, 5);
var r15 = RecvSome(c15, 4096);
?. 'session ttl expired: ' & hasRe(r15, %\r\n\r\nnone$%);
?. 'session ttl stale clear: ' & hasRe(r15, %Set-Cookie:\x20sid=;%);
CloseSocket(c15);
s3.stop();

// 11. custom store interface
var st = CTestStore();
var s4 = HttpServer(0);
s4.Use(HttpSession([store: st]));
s4.get('/write', writeH);
s4.get('/read', readH);
var p4 = s4.listen();
var c16 = getReq(p4, '/write');
pump(s4, 5);
var r16 = RecvSome(c16, 4096);
var sid4 = cookieSid(r16, 'sid');
CloseSocket(c16);
var c17 = getSid(p4, '/read', sid4);
pump(s4, 5);
var r17 = RecvSome(c17, 4096);
?. 'session custom store: ' & hasRe(r17, %\r\n\r\nuser:alice$%);
CloseSocket(c17);
s4.stop();

// 12. SameSite=None requires Secure
var bad = false;
try
  var x = HttpSession([sameSite: 'None']);
except
  bad = true;
end try;
?. 'session none requires secure: ' & bad;

?. 'ok';
