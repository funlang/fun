// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// http-cors: CORS middleware following the Fetch Living Standard.
//
//     s.Use(HttpCors([
//       origins: ['https://app.example.com', 'http://localhost:5173'],
//       methods: ['GET', 'POST', 'PUT', 'DELETE'],
//       headers: ['Content-Type', 'Authorization'],   // nil = reflect request
//       exposeHeaders: ['X-Request-Id'],
//       credentials: true,
//       maxAge: 600
//     ]));
//
// origins defaults to ['*']; credentials: true requires explicit origins and
// never uses the '*' response value. originCheck(origin) can replace origins
// for dynamic policies. Register it before authentication: preflight (OPTIONS
// with Access-Control-Request-Method) is answered here. CORS controls browser
// reads only; CSRF protection is a separate concern.
use 'lib-regex.fun';

fun _corsTrim(s)
  var b = 0;
  var e = s.length();
  while b < e and (s.substr(b, 1) = ' ' or s.substr(b, 1) = 9.toChar()) do b += 1; end do;
  while e > b and (s.substr(e - 1, 1) = ' ' or s.substr(e - 1, 1) = 9.toChar()) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

// comma-separated string or list -> list, trimmed, empty entries dropped
fun _corsList(v)
  var out = new [];
  if v = nil then result = out; return; end if;
  if v.type() = 8 then
    var s = _corsTrim('' & v);
    if s <> '' then
      var ps = split(/,/, s);
      for i = 0 to ps.@count() - 1 do
        var x = _corsTrim(ps[i]);
        if x <> '' then out.@add(x); end if;
      end do;
    end if;
  else
    for i = 0 to v.@count() - 1 do
      var x = _corsTrim('' & v[i]);
      if x <> '' then out.@add(x); end if;
    end do;
  end if;
  result = out;
end fun;

fun _corsJoin(xs)
  var s = '';
  for i = 0 to xs.@count() - 1 do
    if s <> '' then s &= ', '; end if;
    s &= xs[i];
  end do;
  result = s;
end fun;

class CCors(o)
  var allowAny = false;
  var origins = new [];
  var originCheck = nil;
  var methods = new [];
  var methodsLine = '';
  var reflectHeaders = true;
  var headers = new [];
  var headersLine = '';
  var exposeLine = '';
  var credentials = false;
  var maxAge = 600;
  var optionsStatus = 204;

  if o <> nil then
    if o.@has('credentials') and o['credentials'] = true then credentials = true; end if;
    if o.@has('originCheck') then originCheck = o['originCheck']; end if;
    if o.@has('maxAge') then
      maxAge = o['maxAge'];
      if maxAge < 0 then raise 'http-cors: maxAge must be >= 0'; end if;
    end if;
    if o.@has('optionsStatus') then
      optionsStatus = o['optionsStatus'];
      if optionsStatus <> 200 and optionsStatus <> 204 then
        raise 'http-cors: optionsStatus must be 200 or 204';
      end if;
    end if;
  end if;

  var os = nil;
  if o <> nil and o.@has('origins') then
    os = o['origins'];
  elsif originCheck <> nil then
    os = new [];
  else
    os = '*';
  end if;
  if os = nil then
    if originCheck <> nil then os = new []; else os = '*'; end if;
  end if;
  var ol = _corsList(os);
  if os.type() = 8 and _corsTrim('' & os) = '*' then
    allowAny = true;
  else
    for i = 0 to ol.@count() - 1 do
      var x = ol[i];
      if x = '*' then allowAny = true; else origins[x] = true; end if;
    end do;
  end if;
  if allowAny and credentials then
    raise 'http-cors: credentials requires explicit origins';
  end if;

  var ms = nil;
  if o <> nil and o.@has('methods') then ms = o['methods']; else ms = 'GET,HEAD,POST,PUT,PATCH,DELETE'; end if;
  var ml = _corsList(ms);
  var mseen = new [];
  for i = 0 to ml.@count() - 1 do
    var m = ml[i].upper();
    if m <> '' and mseen[m] = nil then
      mseen[m] = true;
      methods[m] = true;
      if methodsLine <> '' then methodsLine &= ', '; end if;
      methodsLine &= m;
    end if;
  end do;

  if o <> nil and o.@has('headers') and o['headers'] <> nil then
    reflectHeaders = false;
    var hl = _corsList(o['headers']);
    var hseen = new [];
    for i = 0 to hl.@count() - 1 do
      var h = hl[i];
      var hk = h.lower();
      if hk <> '' and hseen[hk] = nil then
        hseen[hk] = true;
        headers[hk] = true;
        if headersLine <> '' then headersLine &= ', '; end if;
        headersLine &= h;
      end if;
    end do;
  end if;

  if o <> nil and o.@has('exposeHeaders') then
    var el = _corsList(o['exposeHeaders']);
    exposeLine = _corsJoin(el);
  end if;

  fun originOk(origin)
    if allowAny then result = true; return; end if;
    if origins[origin] <> nil then result = true; return; end if;
    if originCheck <> nil then result = originCheck(origin); return; end if;
    result = false;
  end fun;

  fun headersOk(ph)
    if reflectHeaders then result = true; return; end if;
    result = true;
    if ph = '' then return; end if;
    var hs = split(/,/, ph);
    for i = 0 to hs.@count() - 1 do
      var h = _corsTrim(hs[i]).lower();
      if h <> '' and headers[h] = nil then result = false; return; end if;
    end do;
  end fun;

  fun apply(res, origin)
    var acao = '*';
    if credentials or not allowAny then acao = origin; end if;
    res.header('Access-Control-Allow-Origin', acao);
    if credentials then res.header('Access-Control-Allow-Credentials', 'true'); end if;
    if exposeLine <> '' then res.header('Access-Control-Expose-Headers', exposeLine); end if;
    if credentials or not allowAny then res.addHeader('Vary', 'Origin'); end if;
  end fun;

  fun preflight(res, origin, ph)
    res.status(optionsStatus);
    var acao = '*';
    if credentials or not allowAny then acao = origin; end if;
    res.header('Access-Control-Allow-Origin', acao);
    if credentials then res.header('Access-Control-Allow-Credentials', 'true'); end if;
    if methodsLine <> '' then res.header('Access-Control-Allow-Methods', methodsLine); end if;
    if reflectHeaders then
      if ph <> '' then res.header('Access-Control-Allow-Headers', ph); end if;
    elsif headersLine <> '' then
      res.header('Access-Control-Allow-Headers', headersLine);
    end if;
    if maxAge > 0 then res.header('Access-Control-Max-Age', '' & maxAge); end if;
    res.addHeader('Vary', 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers');
    res.send('');
  end fun;

  fun deny(res, why)
    res.header('Vary', 'Origin');
    res.status(403).text('cors: ' & why);
  end fun;

  fun run(req, res, nx)
    var origin = _corsTrim(req.header('origin') or '');
    if origin = '' then
      if allowAny and not credentials then
        apply(res, '');
      else
        res.addHeader('Vary', 'Origin');
      end if;
      nx();
      return;
    end if;
    var pm = req.header('access-control-request-method') or '';
    if req.method = 'OPTIONS' and pm <> '' then
      if not originOk(origin) then deny(res, 'origin not allowed'); return; end if;
      if methods[pm.upper()] = nil then deny(res, 'method not allowed'); return; end if;
      var ph = req.header('access-control-request-headers') or '';
      if not headersOk(ph) then deny(res, 'header not allowed'); return; end if;
      preflight(res, origin, ph);
    else
      if originOk(origin) then
        apply(res, origin);
      else
        res.addHeader('Vary', 'Origin');
      end if;
      nx();
    end if;
  end fun;
end class;

fun HttpCors(opts)
  result = CCors(opts);
end fun;
