// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ajax-unx: the Unix backend of lib-ajax -- an HTTP client on libcurl.
//
// The Windows lib-ajax.fun is COM-shaped (Msxml2.ServerXMLHTTP + ADODB.Stream),
// so like lib-proc / lib-unicode / lib-crypt the Windows file keeps the plain
// name and this backend carries the same public surface for Unix callers:
//
//     use 'lib-ajax-unx.fun';
//     var a = Ajax();
//     var html = a.go(url: 'http://example.com/');
//     ?. a.code, a.message, a.headers['content-type'];
//
// What is kept from lib-ajax: the Ajax class, go(args) / get(...) / post(...),
// the result fields .code / .message / .html / .headers / .last / .rc, the
// CorrectURL helper and the args set (url, body, method, headers, timeouts,
// saveas, no302, proxy, userAgent, referer, cookie).
//
// What is deliberately different:
//   * transports are SYNCHRONOUS. libcurl's easy interface has no COM-style
//     event pump, so go()/get()/post() return after the transfer completes and
//     the `async` flag is accepted for source compatibility but not honored.
//   * .headers is a set of the FINAL response block (lowercased keys); with
//     redirects the intermediate blocks are dropped.
//   * .html is the raw response body (bytes). There is no ADODB.Stream here, so
//     `charset` / `dontUseCodePage` decoding is not applied; use lib-unicode if
//     you need to transcode.
//   * .rc is the libcurl error code (0 = ok); .message is the HTTP status text
//     on success, or curl_easy_strerror(rc) on a transport error.
//
// Native handles are module-level getapi variables (the lib-crypt-unx pattern);
// on this Fun version a handle stored in a set member is not reliably callable
// from a function body, while a plain variable is.

//--------------------------------------------------------------
// libcurl
//--------------------------------------------------------------
use 'lib-host.fun';

var _curl = DyLib('libcurl.so.4', 'libcurl.4.dylib');
var _memcpy = LibC().getapi('memcpy', 'ppn:p');

var _curl_global_init  = _curl.getapi('curl_global_init',  'l:i');
var _curl_easy_init    = _curl.getapi('curl_easy_init',    ':p');
var _curl_easy_perform = _curl.getapi('curl_easy_perform', 'p:i');
var _curl_easy_cleanup = _curl.getapi('curl_easy_cleanup', 'p:v');
var _curl_easy_strerror = _curl.getapi('curl_easy_strerror', 'i:s');
// curl_easy_setopt is variadic. Declare the third slot once per kind of option;
// a string, a long / pointer and a callback all arrive in the same GPR on the
// System V ABI, so the callee reads them alike.
var _setopt_s = _curl.getapi('curl_easy_setopt', 'pis:i'); // string option
var _setopt_l = _curl.getapi('curl_easy_setopt', 'pin:i'); // long / pointer / callback address
var _setopt_c = _curl.getapi('curl_easy_setopt', 'pic:i'); // Fun callback option
var _slist_append = _curl.getapi('curl_slist_append', 'ps:p');
var _slist_free   = _curl.getapi('curl_slist_free_all', 'p:v');

var _curl_global = _curl_global_init(3); // CURL_GLOBAL_ALL; once per process

//--------------------------------------------------------------
// CURLOPT_* (the libcurl option numbers are ABI, stable for decades)
//--------------------------------------------------------------
var CURLOPT_WRITEDATA         = 10001;
var CURLOPT_URL               = 10002;
var CURLOPT_PROXY             = 10004;
var CURLOPT_PROXYUSERPWD      = 10006;
var CURLOPT_POSTFIELDS        = 10015;
var CURLOPT_REFER             = 10016;
var CURLOPT_USERAGENT         = 10018;
var CURLOPT_COOKIE            = 10022;
var CURLOPT_HTTPHEADER        = 10023;
var CURLOPT_CUSTOMREQUEST     = 10036;
var CURLOPT_POST              = 47;
var CURLOPT_FOLLOWLOCATION    = 52;
var CURLOPT_MAXREDIRS         = 68;
var CURLOPT_POSTFIELDSIZE     = 60;
var CURLOPT_SSL_VERIFYPEER    = 64;
var CURLOPT_SSL_VERIFYHOST    = 81;
var CURLOPT_NOSIGNAL          = 99;
var CURLOPT_TIMEOUT           = 13;
var CURLOPT_NOBODY            = 44;
var CURLOPT_WRITEFUNCTION     = 20011;
var CURLOPT_HEADERFUNCTION    = 20079;
var CURLOPT_ACCEPT_ENCODING   = 10102;
var CURLOPT_TIMEOUT_MS        = 155;
var CURLOPT_CONNECTTIMEOUT_MS = 156;

var defaultProxy    = nil;
var defaultCodePage = 0;

//--------------------------------------------------------------
// response state shared with the libcurl callbacks
//
// libcurl calls the write/header callbacks while CURLOPT_* is unchanged, and a
// single thread runs one transfer at a time, so module-level accumulators are
// enough (and simpler than binding a Fun object to C's void* userdata).
//--------------------------------------------------------------
var _rbody = '';
var _rhead = nil;
var _rcode = 0;
var _rmsg  = '';

fun _ws(c)
  result = c = 32 or c = 9 or c = 13 or c = 10;
end fun;

fun _trim(s)
  var n = s.length();
  var b = 0;
  while b < n and _ws(s[b + 0.5]) do b += 1; end do;
  var e = n;
  while e > b and _ws(s[e - 0.5]) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

fun _trimnl(s)
  var n = s.length();
  while n > 0 and (s[n - 0.5] = 13 or s[n - 0.5] = 10) do n -= 1; end do;
  result = s.substr(0, n);
end fun;

// size_t write_cb(char* ptr, size_t size, size_t nmemb, void* userdata)
fun _onWrite(ptr, size, nmemb, ud)
  var n = size * nmemb;
  if n > 0 then
    var buf = 0.toChar().x(n);
    _memcpy(buf.toNum(-1), ptr, n);
    _rbody &= buf;
  end if;
  result = n;
end fun;

// size_t header_cb(char* ptr, size_t size, size_t nmemb, void* userdata)
// One call per response line, including the status line and the blank line.
// A new status line starts a new header block, so redirects keep only the
// headers of the final response.
fun _onHeader(ptr, size, nmemb, ud)
  var n = size * nmemb;
  var buf = 0.toChar().x(n);
  _memcpy(buf.toNum(-1), ptr, n);
  var line = _trimnl(buf);
  if line.substr(0, 5) = 'HTTP/' then
    _rhead = new [];
    var sp = line.subpos(' ');
    if sp >= 0 then
      _rcode = line.substr(sp + 1, 3).toNum();
      _rmsg  = _trim(line.substr(sp + 5));
    end if;
  else
    var c = line.subpos(':');
    if c > 0 then
      _rhead[_trim(line.substr(0, c)).lower()] = _trim(line.substr(c + 1));
    end if;
  end if;
  result = n;
end fun;

// scheme://host of an absolute URL
fun _origin(url)
  var sp = url.subpos('://');
  if sp < 0 then result = ''; return; end if;
  var rest = url.substr(sp + 3);
  var sl = rest.subpos('/');
  if sl < 0 then result = url; else result = url.substr(0, sp + 3 + sl); end if;
end fun;

// lib-ajax's relative-URL fixup, without the regex dependency (a core library
// stays usable on a build without -dRegex).
fun CorrectURL(url, last)
  if url = '' then result = ''; return; end if;
  if url.subpos('://') >= 0 then result = url; return; end if;
  if last = '' then result = 'http://' & url; return; end if;
  if url.substr(0, 1) = '/' then result = _origin(last) & url; return; end if;
  var dir = last;
  if last.substr(-1) <> '/' then
    var i = last.length() - 1;
    var cut = -1;
    while i >= 0 and cut < 0 do
      if last[i + 0.5] = 47 then cut = i; else i -= 1; end if;
    end do;
    if cut >= 0 then dir = last.substr(0, cut + 1); end if;
  end if;
  result = dir & url;
end fun;

//--------------------------------------------------------------
// one synchronous transfer. req is a set with:
//   url, body, method, headers, timeouts, userAgent, referer, cookie,
//   proxy, proxyUser, proxyPass, insecure, no302
// Returns the libcurl code (0 = ok) and leaves the result in the module
// accumulators (_rcode / _rmsg / _rhead / _rbody).
//--------------------------------------------------------------
fun _request(req)
  _rbody = ''; _rhead = new []; _rcode = 0; _rmsg = '';
  var h = _curl_easy_init();
  if h = nil then raise 'lib-ajax-unx: curl_easy_init failed'; end if;
  var slist = nil;
  var rc  = 0;
  var err = nil;
  try
    _setopt_s(h, CURLOPT_URL, req.url);
    // Keep the closures alive for the whole transfer: freeing a @toCallback
    // closure would leave curl holding a dangling function pointer.
    var cbw = _onWrite.@toCallback(nil, 'pnnp:n');
    var cbh = _onHeader.@toCallback(nil, 'pnnp:n');
    _setopt_c(h, CURLOPT_WRITEFUNCTION,  cbw);
    _setopt_c(h, CURLOPT_HEADERFUNCTION, cbh);
    _setopt_s(h, CURLOPT_ACCEPT_ENCODING, 'gzip, deflate'); // curl decodes for us
    _setopt_l(h, CURLOPT_NOSIGNAL, 1);

    if req.userAgent <> nil and req.userAgent <> '' then _setopt_s(h, CURLOPT_USERAGENT, req.userAgent); end if;
    if req.referer   <> nil and req.referer   <> '' then _setopt_s(h, CURLOPT_REFER,     req.referer);   end if;
    if req.cookie    <> nil and req.cookie    <> '' then _setopt_s(h, CURLOPT_COOKIE,    req.cookie);    end if;
    if req.proxy     <> nil and req.proxy     <> '' then
      _setopt_s(h, CURLOPT_PROXY, req.proxy);
      if req.proxyUser <> nil then
        _setopt_s(h, CURLOPT_PROXYUSERPWD, req.proxyUser & ':' & (req.proxyPass or ''));
      end if;
    end if;
    if req.insecure then
      _setopt_l(h, CURLOPT_SSL_VERIFYPEER, 0);
      _setopt_l(h, CURLOPT_SSL_VERIFYHOST, 0);
    end if;

    if req.no302 then
      _setopt_l(h, CURLOPT_FOLLOWLOCATION, 0);
    else
      _setopt_l(h, CURLOPT_FOLLOWLOCATION, 1);
      _setopt_l(h, CURLOPT_MAXREDIRS, 8);
    end if;

    var tmo = req.timeouts;
    if tmo then
      if tmo.connectTimeout then _setopt_l(h, CURLOPT_CONNECTTIMEOUT_MS, tmo.connectTimeout); end if;
      var total = 0;
      if tmo.resolveTimeout then total += tmo.resolveTimeout; end if;
      if tmo.sendTimeout    then total += tmo.sendTimeout;    end if;
      if tmo.receiveTimeout then total += tmo.receiveTimeout; end if;
      if total > 0 then _setopt_l(h, CURLOPT_TIMEOUT_MS, total); end if;
    end if;

    if req.headers then
      for k: v in req.headers do
        slist = _slist_append(slist, k & ': ' & v);
      end do;
      _setopt_l(h, CURLOPT_HTTPHEADER, slist);
    end if;

    var m = req.method;
    if m = nil then
      if req.body <> nil then m = 'POST'; else m = 'GET'; end if;
    end if;
    m = m.upper();
    if req.body <> nil and req.body.length() > 0 then
      // curl stores this pointer, it does not copy: hand it the Fun string's
      // real address (the 'p'/'s' path can pass a temporary copy on Linux).
      _setopt_l(h, CURLOPT_POSTFIELDS,    req.body.toNum(-1));
      _setopt_l(h, CURLOPT_POSTFIELDSIZE, req.body.length());
    end if;
    if m = 'HEAD' then
      _setopt_l(h, CURLOPT_NOBODY, 1);
    elsif m = 'GET' then
      // nothing: the URL carries any query string
    elsif m = 'POST' then
      if req.body = nil then _setopt_l(h, CURLOPT_POST, 1); end if;
    else
      _setopt_s(h, CURLOPT_CUSTOMREQUEST, m);
    end if;

    rc = _curl_easy_perform(h);
  except
    err = @;
  end try;
  if slist <> nil then _slist_free(slist); end if;
  _curl_easy_cleanup(h);
  if err <> nil then raise err; end if;
  result = rc;
end fun;

//--------------------------------------------------------------
// Http(args): thin, Ajax-free request helper.
//   args: url, body, method, headers, timeouts, userAgent, referer, cookie,
//         proxy, proxyUser, proxyPass, insecure, no302, saveas
// Returns a set: [rc, code, message, headers, body].
//--------------------------------------------------------------
fun Http(args)
  if args.url = nil or args.url = '' then raise 'lib-ajax-unx: url required'; end if;
  var req = new [];
  req.url       = args.url;
  req.body      = args.body;
  req.method    = args.method;
  req.headers   = args.headers;
  req.timeouts  = args.timeouts;
  req.userAgent = args.userAgent;
  req.referer   = args.referer;
  req.cookie    = args.cookie;
  req.proxy     = args.proxy;
  req.proxyUser = args.proxyUser;
  req.proxyPass = args.proxyPass;
  req.insecure  = args.insecure;
  req.no302     = args.no302;
  var rc = _request(req);
  var res = new [];
  res.rc      = rc;
  res.code    = _rcode;
  res.headers = _rhead or new [];
  res.body    = _rbody;
  if rc = 0 then
    res.message = _rmsg;
    if args.saveas <> nil then args.saveas.save(_rbody, cp: 0xffff); end if;
  else
    res.message = _curl_easy_strerror(rc);
  end if;
  result = res;
end fun;

//==============================================================
// Ajax: the lib-ajax-compatible class
//==============================================================
class Ajax(container)
  var html    = '';
  var code    = 0;
  var message = '';
  var headers = nil;
  var last    = '';
  var async   = true;   // parity only: transfers are synchronous here
  var rc      = 0;      // libcurl result code of the last request
  var body    = '';     // raw response bytes (same as html)

  fun reset()
    html = ''; code = 0; message = ''; headers = nil; rc = 0; body = '';
  end fun;

  fun go(args)
    result = _go(args);
  end fun;

  // Same positional shape as lib-ajax.fun's get(); only the portable arguments
  // are honored (no_ui / charset / fnHeader / dontUseCodePage / check are
  // accepted for source compatibility and ignored).
  fun get(url, no_ui, referer, cookie, post, charset, userAgent, fnHeader, body, timeouts, headers, method, proxy, dontUseCodePage, check, saveas, args)
    var a = args or new [];
    a.url = CorrectURL(url, last);
    if referer   <> nil then a.referer   = referer;   end if;
    if cookie    <> nil then a.cookie    = cookie;    end if;
    if post              then a.method   = a.method or 'POST'; end if;
    if userAgent <> nil then a.userAgent = userAgent; end if;
    if body      <> nil then a.body      = body;      end if;
    if timeouts  <> nil then a.timeouts  = timeouts;  end if;
    if headers   <> nil then a.headers   = headers;   end if;
    if method    <> nil then a.method    = method;    end if;
    if proxy     <> nil then
      // lib-ajax's proxy set: [mode, server, user, password, basic]
      if proxy.server   <> nil then a.proxy     = proxy.server;   end if;
      if proxy.user     <> nil then a.proxyUser = proxy.user;     end if;
      if proxy.password <> nil then a.proxyPass = proxy.password; end if;
    end if;
    if saveas <> nil then a.saveas = saveas; end if;
    result = _go(a);
  end fun;

  var post(url, no_ui, referer, cookie, charset, userAgent, fnHeader, body, timeouts, headers, method, proxy, dontUseCodePage, check, saveas, args)
     = get(url, no_ui, referer, cookie, true, charset, userAgent, fnHeader, body, timeouts, headers, method, proxy, dontUseCodePage, check, saveas, args);

  fun _go(args)
    reset();
    var a = args or new [];
    if a.url = nil or a.url = '' then raise 'lib-ajax-unx: url required'; end if;
    var u = CorrectURL(a.url, last);
    last = u;
    var req = new [];
    req.url       = u;
    req.body      = a.body;
    req.method    = a.method;
    req.headers   = a.headers;
    req.timeouts  = a.timeouts;
    req.userAgent = a.userAgent;
    req.referer   = a.referer;
    req.cookie    = a.cookie;
    req.proxy     = a.proxy or defaultProxy;
    req.proxyUser = a.proxyUser;
    req.proxyPass = a.proxyPass;
    req.insecure  = a.insecure;
    req.no302     = a.no302;

    rc      = _request(req);
    code    = _rcode;
    headers = _rhead or new [];
    body    = _rbody;
    if rc = 0 then
      message = _rmsg;
      html    = _rbody;
      if a.saveas <> nil then a.saveas.save(_rbody, cp: 0xffff); end if;
      result  = html;
    else
      message = _curl_easy_strerror(rc);
      result  = nil;
    end if;

    if container <> nil then
      try container.innerHTML = html; except ?. @; end try;
    end if;
  end fun;
end class;
