// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-url: URL encoding helpers.
//
// PercentEncode follows RFC 3986's unreserved set (ALPHA / DIGIT / "-" / "."
// / "_" / "~"), which is what Aliyun and most signed APIs expect.
//
// UrlEncode follows PHP's urlencode(): space becomes '+', and '~' is escaped.
// Use it only where the PHP behaviour must be reproduced byte for byte.
//
//     use 'lib-url.fun';
//     PercentEncode('a b*~');   // a%20b%2A~
//     UrlEncode('a b~');        // a+b%7E
//
//     var u = UrlParse('https://user:pass@example.com:8080/a?x=1#f');
//     u['host'];                 // example.com
//     UrlBuild(u);               // the same URL

// Module globals are shared across `use`d files, so keep this name specific:
// uuid.fun also defines a module-level hex table.
var _urlHex = '0123456789ABCDEF';

fun _urlPct(s, spacePlus, tildeSafe)
  result = '';
  for i = 0 to s.length() - 1 do
    var b = s.toByte(i);
    if b >= 0x30 and b <= 0x39 or
       b >= 0x41 and b <= 0x5a or
       b >= 0x61 and b <= 0x7a or
       b = 0x2d or b = 0x2e or b = 0x5f or
       (tildeSafe and b = 0x7e) then
      result &= b.toChar();
    elsif b = 0x20 and spacePlus then
      result &= '+';
    else
      result &= '%' & _urlHex[b >> 4] & _urlHex[b bit and 0x0f];
    end if;
  end do;
end fun;

fun PercentEncode(s)
  result = _urlPct(s, false, true);
end fun;

fun UrlEncode(s)
  result = _urlPct(s, true, false);
end fun;

fun _urlIsAlpha(c)
  var b = c.toByte(0);
  result = b >= 65 and b <= 90 or b >= 97 and b <= 122;
end fun;

fun _urlIsDigit(c)
  var b = c.toByte(0);
  result = b >= 48 and b <= 57;
end fun;

fun _urlSchemeEnd(s)
  if s.length() = 0 or not _urlIsAlpha(s.substr(0, 1)) then result = -1; return; end if;
  var i = 1;
  while i < s.length() do
    var c = s.substr(i, 1);
    if _urlIsAlpha(c) or _urlIsDigit(c) or c = '+' or c = '-' or c = '.' then
      i += 1;
    elsif c = ':' then
      result = i;
      return;
    else
      result = -1;
      return;
    end if;
  end do;
  result = -1;
end fun;

fun _urlAuthorityEnd(s)
  var i = 0;
  while i < s.length() do
    var c = s.substr(i, 1);
    if c = '/' or c = '?' or c = '#' then result = i; return; end if;
    i += 1;
  end do;
  result = s.length();
end fun;

fun UrlParse(url)
  var u = new [];
  u['scheme'] = nil;
  u['user'] = nil;
  u['password'] = nil;
  u['host'] = nil;
  u['port'] = nil;
  u['path'] = '';
  u['query'] = nil;
  u['fragment'] = nil;
  if url = nil then result = u; return; end if;
  var s = '' & url;
  var se = _urlSchemeEnd(s);
  if se >= 0 then
    u['scheme'] = s.substr(0, se).lower();
    s = s.substr(se + 1);
  end if;
  if s.substr(0, 2) = '//' then
    s = s.substr(2);
    var ae = _urlAuthorityEnd(s);
    var auth = s.substr(0, ae);
    s = s.substr(ae);
    u['host'] = '';
    var at = -1;
    var i = 0;
    while i < auth.length() do
      if auth.substr(i, 1) = '@' then at = i; end if;
      i += 1;
    end do;
    var hostport = auth;
    if at >= 0 then
      var ui = auth.substr(0, at);
      hostport = auth.substr(at + 1);
      var co = ui.subpos(':');
      if co >= 0 then
        u['user'] = ui.substr(0, co);
        u['password'] = ui.substr(co + 1);
      else
        u['user'] = ui;
      end if;
    end if;
    if hostport.substr(0, 1) = '[' then
      var rb = hostport.subpos(']');
      if rb >= 0 then
        u['host'] = hostport.substr(1, rb - 1);
        var tail = hostport.substr(rb + 1);
        if tail.substr(0, 1) = ':' then u['port'] = tail.substr(1); end if;
      else
        u['host'] = hostport;
      end if;
    else
      var pc = -1;
      var j = 0;
      while j < hostport.length() do
        if hostport.substr(j, 1) = ':' then pc = j; end if;
        j += 1;
      end do;
      if pc >= 0 then
        u['host'] = hostport.substr(0, pc);
        u['port'] = hostport.substr(pc + 1);
      else
        u['host'] = hostport;
      end if;
    end if;
  end if;
  var hash = s.subpos('#');
  var before = s;
  if hash >= 0 then
    u['fragment'] = s.substr(hash + 1);
    before = s.substr(0, hash);
  end if;
  var q = before.subpos('?');
  if q >= 0 then
    u['query'] = before.substr(q + 1);
    before = before.substr(0, q);
  end if;
  u['path'] = before;
  result = u;
end fun;

fun UrlBuild(u)
  if u = nil then result = ''; return; end if;
  result = '';
  var scheme = u['scheme'];
  if scheme.type() <> 0 then result &= scheme & ':'; end if;
  var host = u['host'];
  if host.type() <> 0 then
    result &= '//';
    var user = u['user'];
    var pass = u['password'];
    if user.type() <> 0 or pass.type() <> 0 then
      if user.type() <> 0 then result &= user; end if;
      if pass.type() <> 0 then result &= ':' & pass; end if;
      result &= '@';
    end if;
    if host.subpos(':') >= 0 and host.substr(0, 1) <> '[' then
      result &= '[' & host & ']';
    else
      result &= host;
    end if;
    var port = u['port'];
    if port.type() <> 0 then result &= ':' & port; end if;
  end if;
  var path = u['path'];
  if path.type() <> 0 then
    if host.type() <> 0 and path <> '' and path.substr(0, 1) <> '/' then result &= '/'; end if;
    result &= path;
  end if;
  var query = u['query'];
  if query.type() <> 0 then result &= '?' & query; end if;
  var fragment = u['fragment'];
  if fragment.type() <> 0 then result &= '#' & fragment; end if;
end fun;
