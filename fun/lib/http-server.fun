// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// http-server: an HTTP server framework with a platform-neutral import
// path. The `use` below resolves 'lib-winsock.fun' to the host's backend
// (Linux/macOS poll loop; Windows drives from the user32 message pump).
// Routing with path parameters and wildcards, middleware (global /
// per-group / per-route), route groups, a request/response pair, static
// files and a built-in access logger.
//
//     use 'fun/lib/http-server.fun';
//
//     fun hello(req, res) res.html('<h1>Hello from Fun!</h1>'); end fun;
//
//     var s = HttpServer(8080);   // or an address string: '0.0.0.0:8080'
//     s.Use(HttpLogger());
//     s.get('/', hello);
//
// Handlers and middleware are plain named functions (this Fun version has no
// anonymous functions with parameters):
//
//     fun user(req, res)
//       res.json([id: req.param('id')]);
//     end fun;
//     s.get('/users/:id', user);
//
//     fun auth(req, res, nx)          // nx: call to continue the chain
//       if req.header('token') <> 'secret' then
//         res.status(401).text('unauthorized');
//       else
//         nx();                       // before: pre-phase; after: post-phase
//       end if;
//     end fun;
//
//     var api = s.group('/api');      // route group: shared prefix
//     api.Use(auth);                  // and shared middleware
//     api.get('/orders', orders);
//
//     s.static('/assets', './public');
//     s.run();                        // bind + listen + blocking poll loop
//     // or: var port = s.listen(); ... s.runOnce(200) to drive yourself
//
// Notes:
//   * middleware is a function (req, res, nx) or a stateful object with a
//     run(req, res, nx) method; Use accepts either form.
//   * the middleware continuation parameter is named `nx` because `next`
//     (like `step`) is reserved by the language.
//   * routing rules: literal segments beat `:name` parameters, which beat the
//     `*` wildcard tail; a path that matches under another method answers 405
//     with Allow; no match answers 404. (`*` captures the remaining path in
//     req.param('*').)
//   * single-threaded poll loop: handlers must not block. The base keeps the
//     HTTP framing and keep-alive (lib-winsock-base).
//   * Windows: the winsock backend has no RunOnce/Run and its Start takes
//     (hwnd, message), so listen()/runOnce()/run() here run on Linux and
//     macOS today; wiring the Windows message-pump driver is a follow-up.
//
// Request/response API:
//   * req.query(k) and req.form() are URL-decoded; req.form() parses
//     application/x-www-form-urlencoded bodies on demand.
//   * req.cookies / req.cookie(k) read the Cookie header.
//   * res.cookie(name, value, opts) / res.clearCookie(name, opts) write
//     Set-Cookie; res.addHeader(k, v) appends multi-value headers.

use 'lib-winsock.fun';
use 'lib-regex.fun';

var _HTTP_APP = nil;

//--------------------------------------------------------------
// helpers
//--------------------------------------------------------------
fun _isWs(c)
  result = c = 32 or c = 9 or c = 13 or c = 10;
end fun;

fun _trim(s)
  var n = s.length();
  var b = 0;
  while b < n and _isWs(s[b + 0.5]) do b += 1; end do;
  var e = n;
  while e > b and _isWs(s[e - 0.5]) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

fun _segments(p)
  result = new [];
  var cur = '';
  for i = 0 to p.length() - 1 do
    var c = p.substr(i, 1);
    if c = '/' then
      if cur <> '' then result.@add(cur); end if;
      cur = '';
    else
      cur &= c;
    end if;
  end do;
  if cur <> '' then result.@add(cur); end if;
end fun;

fun _hexVal(c)
  result = '0123456789abcdef'.subpos(c.lower());
end fun;

// %XX and '+' (form/query encoding); invalid escapes stay literal
fun _urlDecode(s)
  var out = '';
  var i = 0;
  while i < s.length() do
    var c = s.substr(i, 1);
    if c = '+' then
      out &= ' ';
      i += 1;
    elsif c = '%' and i + 2 < s.length() then
      var hi = _hexVal(s.substr(i + 1, 1));
      var lo = _hexVal(s.substr(i + 2, 1));
      if hi >= 0 and lo >= 0 then
        out &= (hi * 16 + lo).toChar();
        i += 3;
      else
        out &= c;
        i += 1;
      end if;
    else
      out &= c;
      i += 1;
    end if;
  end do;
  result = out;
end fun;

fun _querySet(q)
  result = new [];
  for pair in split(/&/, q) do
    if pair <> '' then
      var i = pair.subpos('=');
      if i < 0 then
        result[_urlDecode(pair)] = '';
      else
        result[_urlDecode(pair.substr(0, i))] = _urlDecode(pair.substr(i + 1));
      end if;
    end if;
  end do;
end fun;

// Cookie: a=1; b=2 (values may be quoted)
fun _cookieSet(h)
  result = new [];
  if h = nil or h = '' then return; end if;
  for part in split(/;/, h) do
    var p = _trim(part);
    if p <> '' then
      var i = p.subpos('=');
      if i > 0 then
        var k = _trim(p.substr(0, i));
        var v = _trim(p.substr(i + 1));
        if v.length() >= 2 and v.substr(0, 1) = '"' and v.substr(v.length() - 1, 1) = '"' then
          v = v.substr(1, v.length() - 2);
        end if;
        result[k] = v;
      end if;
    end if;
  end do;
end fun;

fun _hasCtl(s)
  result = s.subpos(13.toChar()) >= 0 or s.subpos(10.toChar()) >= 0;
end fun;

fun _checkHeader(k, v)
  var ks = '' & k;
  var vs = '' & v;
  if ks = '' or _hasCtl(ks) or ks.subpos(':') >= 0 then
    raise 'http-server: invalid header name or value';
  end if;
  if _hasCtl(vs) then
    raise 'http-server: invalid header name or value';
  end if;
end fun;

// names: RFC token-ish; values: no control/separator characters
fun _cookieOk(s, isName)
  result = false;
  if _hasCtl(s) then return; end if;
  if isName and s = '' then return; end if;
  if isName then
    if s.subpos('=') >= 0 or s.subpos(';') >= 0 or s.subpos(',') >= 0 or
       s.subpos(' ') >= 0 or s.subpos(9.toChar()) >= 0 then return; end if;
  else
    if s.subpos(';') >= 0 or s.subpos(',') >= 0 or s.subpos(' ') >= 0 or
       s.subpos(9.toChar()) >= 0 or s.subpos('"') >= 0 then return; end if;
  end if;
  result = true;
end fun;

fun _checkAttr(v)
  var s = '' & v;
  if _hasCtl(s) or s.subpos(';') >= 0 then
    raise 'http-server: invalid cookie attribute';
  end if;
end fun;

fun _cookieLine(name, value, opts, clear)
  var n = '' & name;
  var v = '' & value;
  if not _cookieOk(n, true) or not _cookieOk(v, false) then
    raise 'http-server: invalid cookie name or value';
  end if;
  var o = opts;
  if o = nil then o = new []; end if;
  var line = n & '=' & v;
  var path = o['path'];
  if path <> nil and path <> '' then
    _checkAttr(path);
    line &= '; Path=' & path;
  end if;
  var domain = o['domain'];
  if domain <> nil and domain <> '' then
    _checkAttr(domain);
    line &= '; Domain=' & domain;
  end if;
  if clear then
    line &= '; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT';
  else
    var ma = o['maxAge'];
    if ma <> nil then
      _checkAttr(ma);
      line &= '; Max-Age=' & ma;
    end if;
    var ex = o['expires'];
    if ex <> nil and ex <> '' then
      _checkAttr(ex);
      line &= '; Expires=' & ex;
    end if;
    if o['httpOnly'] then line &= '; HttpOnly'; end if;
    if o['secure'] then line &= '; Secure'; end if;
    var ss = o['sameSite'];
    if ss <> nil and ss <> '' then
      var sl = ss.lower();
      if sl = 'lax' then
        line &= '; SameSite=Lax';
      elsif sl = 'strict' then
        line &= '; SameSite=Strict';
      elsif sl = 'none' then
        line &= '; SameSite=None';
      else
        raise 'http-server: invalid SameSite value';
      end if;
    end if;
  end if;
  result = line;
end fun;

fun _joinList(a, b)
  var all = new [];
  if a <> nil then
    for m in a do all.@add(m); end do;
  end if;
  if b <> nil then
    for m in b do all.@add(m); end do;
  end if;
  result = all;
end fun;

//--------------------------------------------------------------
// routing
//--------------------------------------------------------------
class HttpRoute()
  var method = '';
  var segs   = nil;    // pattern segments; ':name' parameter, '*' wildcard tail
  var handler = nil;
  var mws    = nil;    // group middleware captured at registration
  var arg    = nil;    // per-route configuration (static files use it)
end class;

// pattern vs request segments: a params set on match (possibly empty), nil on no match
fun _matchPath(segs, pat)
  var n = pat.@count();
  var wild = n > 0 and pat[n - 1] = '*';
  if wild then n -= 1; end if;
  if segs.@count() < n or (not wild and segs.@count() > n) then
    result = nil;
    return;
  end if;
  var ps = new [];
  for i = 0 to n - 1 do
    var p = pat[i];
    if p.substr(0, 1) = ':' then
      ps[p.substr(1)] = segs[i];
    elsif p <> segs[i] then
      result = nil;
      return;
    end if;
  end do;
  if wild then
    var rest = '';
    for i = n to segs.@count() - 1 do
      if i > n then rest &= '/'; end if;
      rest &= segs[i];
    end do;
    ps['*'] = rest;
  end if;
  result = ps;
end fun;

// specificity: literal segments beat parameters, parameters beat wildcards;
// earlier segments weigh more.
fun _scorePath(pat)
  var sc = 0;
  for i = 0 to pat.@count() - 1 do
    var p = pat[i];
    sc *= 3;
    if p = '*' then
      sc += 0;
    elsif p.substr(0, 1) = ':' then
      sc += 1;
    else
      sc += 2;
    end if;
  end do;
  result = sc;
end fun;

// run the middleware chain, then the handler; nx is a zero-argument thunk.
// A middleware is a function (req, res, nx) or an object with a run method
// (stateful middleware such as auth options).
fun _runChain(mws, i, req, res, h)
  if mws = nil or i >= mws.@count() then
    h(req, res);
  else
    var m = mws[i];
    if m.run <> nil then
      m.run(req, res, -> _runChain(mws, i + 1, req, res, h));
    else
      m(req, res, -> _runChain(mws, i + 1, req, res, h));
    end if;
  end if;
end fun;

//--------------------------------------------------------------
// request / response
//--------------------------------------------------------------
class HttpReq()
  var method = 'GET';
  var path   = '/';      // target path, without the query string
  var raw    = '';       // the request target as sent (with query)
  var body   = '';
  var sock   = nil;
  var route  = nil;      // the HttpRoute that matched
  var params = nil;      // :name matches (filled by the router)
  var queryS = nil;      // set: query parameters
  var headS  = nil;      // set: lowercased header names
  var cookies = nil;     // set: request cookies
  var formS  = nil;      // set: urlencoded form, parsed on demand

  fun header(k)
    result = headS[k.lower()];
  end fun;

  fun query(k)
    result = queryS[k];
  end fun;

  fun cookie(k)
    result = cookies[k];
  end fun;

  fun form()
    if formS = nil then
      formS = new [];
      var ct = header('content-type') or '';
      if ct.lower().subpos('application/x-www-form-urlencoded') = 0 then
        formS = _querySet(body);
      end if;
    end if;
    result = formS;
  end fun;

  fun param(k)
    result = params[k];
  end fun;

  fun json()
    result = body.getJson(json: true);
  end fun;
end class;

class HttpRes()
  var sock   = nil;
  var server = nil;      // the Server.HTTP instance
  var code   = 0;
  var hdrs   = nil;
  var sent   = false;

  fun status(c)
    code = c;
    result = this;
  end fun;

  fun header(k, v)
    _checkHeader(k, v);
    hdrs[k] = v;
    result = this;
  end fun;

  // Append another line for the same header name (Set-Cookie, Vary, ...).
  // Values are validated, so the embedded CRLF cannot come from input.
  fun addHeader(k, v)
    _checkHeader(k, v);
    if hdrs[k] = nil then
      hdrs[k] = v;
    else
      hdrs[k] = hdrs[k] & 13.toChar() & 10.toChar() & k & ': ' & v;
    end if;
    result = this;
  end fun;

  fun cookie(name, value, opts)
    addHeader('Set-Cookie', _cookieLine(name, value, opts, false));
    result = this;
  end fun;

  fun clearCookie(name, opts)
    addHeader('Set-Cookie', _cookieLine(name, '', opts, true));
    result = this;
  end fun;

  fun send(s)
    if sent then
      raise 'http-server: response already sent';
    end if;
    sent = true;
    if code <= 0 then
      code = 200;
    end if;
    server.ReplyWithCode(s, code, sock, hdrs);
    result = true;
  end fun;

  fun text(s)
    hdrs['Content-Type'] = 'text/plain; charset=utf-8';
    result = this.send(s);
  end fun;

  fun html(s)
    hdrs['Content-Type'] = 'text/html; charset=utf-8';
    result = this.send(s);
  end fun;

  fun json(v)
    hdrs['Content-Type'] = 'application/json; charset=utf-8';
    result = this.send(v.@toJson(json: true));
  end fun;

  fun redirect(url, c)
    code = c or 302;
    header('Location', url);
    result = this.send('');
  end fun;
end class;

//--------------------------------------------------------------
// built-in middleware
//--------------------------------------------------------------
fun _loggerMw(req, res, nx)
  var t0 = NowMs();
  nx();
  ?. req.method & ' ' & req.path & ' ' & (res.code or 0) & ' ' & int2str(NowMs() - t0) & 'ms';
end fun;

fun HttpLogger()
  result = _loggerMw;
end fun;

//--------------------------------------------------------------
// static files
//--------------------------------------------------------------
fun _mimeOf(fn)
  var e = fn.lower();
  if e =~ /\.html?$/ then
    result = 'text/html; charset=utf-8';
  elsif e =~ /\.css$/ then
    result = 'text/css';
  elsif e =~ /\.js$/ then
    result = 'application/javascript';
  elsif e =~ /\.json$/ then
    result = 'application/json';
  elsif e =~ /\.png$/ then
    result = 'image/png';
  elsif e =~ /\.jpe?g$/ then
    result = 'image/jpeg';
  elsif e =~ /\.gif$/ then
    result = 'image/gif';
  elsif e =~ /\.svg$/ then
    result = 'image/svg+xml';
  elsif e =~ /\.txt$/ then
    result = 'text/plain; charset=utf-8';
  else
    result = 'application/octet-stream';
  end if;
end fun;

fun _staticHandler(req, res)
  var dir = req.route.arg.dir;
  var rel = req.param('*');
  if rel.subpos('..') >= 0 then
    res.status(404).text('not found');
    return;
  end if;
  var fn = dir & '/' & rel;
  if rel = '' then
    fn = dir & '/index.html';
  end if;
  var s = nil;
  try
    s = fn.load();
  except
    s = nil;
  end try;
  if s = nil then
    res.status(404).text('not found');
    return;
  end if;
  res.header('Content-Type', _mimeOf(fn));
  res.send(s);
end fun;

//--------------------------------------------------------------
// route groups
//--------------------------------------------------------------
class HttpGroup(app, prefix, pmws)
  var mws = new [];

  fun Use(mw)
    mws.@add(mw);
    result = this;
  end fun;

  fun route(method, p, h)
    result = app.route(method, prefix & p, h, _joinList(pmws, mws));
  end fun;

  fun get(p, h)     result = this.route('GET', p, h);     end fun;
  fun post(p, h)    result = this.route('POST', p, h);    end fun;
  fun put(p, h)     result = this.route('PUT', p, h);     end fun;
  fun delete(p, h)  result = this.route('DELETE', p, h);  end fun;
  fun patch(p, h)   result = this.route('PATCH', p, h);   end fun;
  fun options(p, h) result = this.route('OPTIONS', p, h); end fun;

  fun group(p)
    result = HttpGroup(app, prefix & p, _joinList(pmws, mws));
  end fun;
end class;

//--------------------------------------------------------------
// the app
//--------------------------------------------------------------
class HttpServer(addr)
  _HTTP_APP = this;
  var ip     = '127.0.0.1';
  var port   = addr;   // number, or 'ip:port' / ':port' (':' = all interfaces)
  var http   = nil;
  var routes = new [];
  var mws    = new [];

  // address string? (numbers return -1 from subpos too, like a missing colon)
  var at = addr.subpos(':');
  if at >= 0 then
    if at > 0 then ip = addr.substr(0, at); else ip = '0.0.0.0'; end if;
    port = addr.substr(at + 1, addr.length()).toNum();
  end if;

  fun Use(mw)
    mws.@add(mw);
    result = this;
  end fun;

  fun route(method, path, h, gmws)
    var r = HttpRoute();
    r.method  = method.upper();
    r.segs    = _segments(path);
    r.handler = h;
    r.mws     = gmws;
    routes.@add(r);
    result = this;
  end fun;

  fun get(p, h)     result = this.route('GET', p, h, nil);     end fun;
  fun post(p, h)    result = this.route('POST', p, h, nil);    end fun;
  fun put(p, h)     result = this.route('PUT', p, h, nil);     end fun;
  fun delete(p, h)  result = this.route('DELETE', p, h, nil);  end fun;
  fun patch(p, h)   result = this.route('PATCH', p, h, nil);   end fun;
  fun options(p, h) result = this.route('OPTIONS', p, h, nil); end fun;

  fun group(prefix)
    result = HttpGroup(this, prefix, nil);
  end fun;

  fun static(prefix, dir)
    var p = prefix;
    if p.length() > 0 and p.substr(-1) = '/' then
      p = p.substr(0, p.length() - 1);
    end if;
    var d = dir;
    if d.length() > 0 and d.substr(-1) = '/' then
      d = d.substr(0, d.length() - 1);
    end if;
    var r = HttpRoute();
    r.method  = 'GET';
    r.segs    = _segments(p & '/*');
    r.handler = _staticHandler;
    r.arg     = new [dir: d];
    routes.@add(r);
    result = this;
  end fun;

  // server lifecycle -------------------------------------------------
  fun listen()
    if http = nil then
      http = Server.HTTP(ip, port, onGet);
    end if;
    http.Start();
    result = http.LocalPort();
  end fun;

  fun runOnce(t)
    result = http.RunOnce(t or 200);
  end fun;

  fun run(t)
    this.listen();
    http.Run(t or 100);
  end fun;

  fun stop()
    if http <> nil then
      http.Stop();
    end if;
  end fun;

  // dispatch ---------------------------------------------------------
  fun onGet(req, header, body, sock)
    var app = _HTTP_APP;
    var r = HttpReq();
    r.sock   = sock;
    r.raw    = req;
    r.body   = body;
    r.headS  = new [];
    r.queryS = new [];
    r.params = new [];
    r.cookies = new [];

    var lines = split(/\r?\n/, header);
    if lines.@count() > 0 then
      var rl = split(/\s+/, lines[0]);
      if rl.@count() >= 1 and rl[0] <> '' then
        r.method = rl[0].upper();
      end if;
    end if;
    for i = 1 to lines.@count() - 1 do
      var ln = lines[i];
      if ln <> '' then
        var c = ln.subpos(':');
        if c > 0 then
          r.headS[_trim(ln.substr(0, c)).lower()] = _trim(ln.substr(c + 1));
        end if;
      end if;
    end do;
    r.cookies = _cookieSet(r.headS['cookie']);

    var qi = req.subpos('?');
    if qi >= 0 then
      r.path   = req.substr(0, qi);
      r.queryS = _querySet(req.substr(qi + 1));
    else
      r.path = req;
    end if;

    // pick the most specific route under this method
    var segs = _segments(r.path);
    var best = nil;
    var bestSc = -1;
    var allow = new [];
    for rt in app.routes do
      var ps = _matchPath(segs, rt.segs);
      if ps <> nil then
        if rt.method = r.method then
          var sc = _scorePath(rt.segs);
          if sc > bestSc then
            best   = rt;
            bestSc = sc;
            r.params = ps;
          end if;
        else
          allow.@add(rt.method);
        end if;
      end if;
    end do;

    var res = HttpRes();
    res.sock   = sock;
    res.server = app.http;
    res.hdrs   = new [];

    if best = nil then
      if allow.@count() > 0 then
        var av = '';
        for m in allow do
          if av <> '' then av &= ', '; end if;
          av &= m;
        end do;
        res.status(405).header('Allow', av).text('method not allowed');
      else
        res.status(404).text('not found');
      end if;
      return;
    end if;

    r.route = best;
    try
      _runChain(_joinList(app.mws, best.mws), 0, r, res, best.handler);
    except
      if not res.sent then
        res.status(500).header('Content-Type', 'text/plain; charset=utf-8').send('Internal Error: ' & @);
      end if;
    end try;
  end fun;
end class;
