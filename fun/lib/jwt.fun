// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// jwt: HS256/HS384/HS512 JSON Web Tokens (RFC 7519 / RFC 7515).
//
//     use 'jwt.fun';
//     var token = jwt.sign([sub: 'u1', exp: jwt.now() + 3600], key);
//     var r = jwt.verify(token, key, [issuer: 'app']);
//     if r.ok then ?. r.claims['sub']; end if;
//
// verify returns [ok, error, header, claims]; malformed tokens and claim
// failures are normal results, not exceptions. Algorithm none is rejected.

use 'auth/util.fun';

var _JWT_SIGN_OPTS = '|alg|headers|expiresIn|notBefore|now|';
var _JWT_VERIFY_OPTS = '|algorithms|issuer|audience|subject|jwtid|leeway|requireExp|now|';

fun _jwtKey(key)
  if key = nil or key.type() <> 8 or key.length() = 0 then
    raise 'jwt: key must be a non-empty string';
  end if;
  result = true;
end fun;

fun _jwtHas(opts, name)
  if opts = nil then result = false; return; end if;
  result = opts.@has(name);
end fun;

fun _jwtCheckOpts(opts, allowed)
  if opts = nil then result = true; return; end if;
  var bad = '';
  var listish = false;
  try
    opts.@each((v, k){
      if k = nil or k = '' then
        listish = true;
      elsif allowed.subpos('|' & k & '|') < 0 then
        bad = k;
      end if;
    });
  except
    raise 'jwt: opts must be a set';
  end try;
  if listish then raise 'jwt: opts must be a set'; end if;
  if bad <> '' then raise 'jwt: unknown option: ' & bad; end if;
  result = true;
end fun;

fun _jwtIsNum(v)
  result = v.type() = 3 or v.type() = 5;
end fun;

fun _jwtOptNum(opts, name, def)
  if not _jwtHas(opts, name) then result = def; return; end if;
  var v = opts[name];
  if not _jwtIsNum(v) or v < 0 then
    raise 'jwt: ' & name & ' must be a non-negative number';
  end if;
  result = v;
end fun;

fun _jwtAlg(a)
  if a = nil or a.type() <> 8 then raise 'jwt: alg must be a string'; end if;
  if not a.eq('HS256') and not a.eq('HS384') and not a.eq('HS512') then
    raise 'jwt: unsupported alg: ' & a;
  end if;
  result = a;
end fun;

fun _jwtHeaderCheck(h)
  if h.@has('crit') then raise 'jwt: unsupported header: crit'; end if;
  if h.@has('b64') then raise 'jwt: unsupported header: b64'; end if;
  if h.@has('zip') then raise 'jwt: unsupported header: zip'; end if;
  result = true;
end fun;

fun _jwtHashName(alg)
  if alg.eq('HS256') then result = 'sha256';
  elsif alg.eq('HS384') then result = 'sha384';
  else result = 'sha512'; end if;
end fun;

fun _jwtObj(v, label)
  var j = '';
  try
    j = v.@toJson(json: true);
  except
    raise 'jwt: ' & label & ' must be an object';
  end try;
  if j = '' or j.substr(0, 1) <> '{' then
    raise 'jwt: ' & label & ' must be an object';
  end if;
  result = true;
end fun;

fun _jwtCopySet(s)
  var out = new [];
  s.@each((v, k){ if k.type() = 8 then out[k] = v; end if; });
  result = out;
end fun;

fun _jwtHeader(alg, headers)
  var h = new [];
  h['alg'] = alg;
  h['typ'] = 'JWT';
  if headers <> nil then
    var bad = false;
    try
      headers.@each((v, k){
        if k = nil then
          bad = true;
        elsif k <> 'alg' and k <> 'typ' then
          h[k] = v;
        end if;
      });
    except
      bad = true;
    end try;
    if bad then raise 'jwt: headers must be a set'; end if;
    _jwtHeaderCheck(h);
  end if;
  result = h;
end fun;

fun _jwtSplit(token)
  var r = new [];
  r.ok = false;
  r.error = 'jwt: token must have three parts';
  r.a = '';
  r.b = '';
  r.c = '';
  var p1 = token.subpos('.');
  if p1 <= 0 then result = r; return; end if;
  var rest = token.substr(p1 + 1);
  var p2 = rest.subpos('.');
  if p2 <= 0 then result = r; return; end if;
  var sig = rest.substr(p2 + 1);
  if sig = '' or sig.subpos('.') >= 0 then result = r; return; end if;
  r.a = token.substr(0, p1);
  r.b = rest.substr(0, p2);
  r.c = sig;
  r.ok = true;
  r.error = nil;
  result = r;
end fun;

fun _jwtDecodePart(seg, label)
  try
    var text = AuthB64UrlDecode(seg);
    var v = text.getJson(json: true);
    _jwtObj(v, label);
    result = v;
  except
    raise 'jwt: invalid ' & label;
  end try;
end fun;

fun _jwtValues(v)
  var out = new [];
  if v.type() = 8 then
    out.@add(v);
    result = out;
    return;
  end if;
  if v = nil then result = out; return; end if;
  var n = 0;
  try
    n = v.@count();
  except
    result = out;
    return;
  end try;
  var i = 0;
  while i < n do
    var x = v[i];
    if x <> nil and x.type() = 8 then out.@add(x); end if;
    i += 1;
  end do;
  result = out;
end fun;

fun _jwtAudMatch(got, want)
  var g = _jwtValues(got);
  var w = _jwtValues(want);
  var i = 0;
  while i < g.@count() do
    var j = 0;
    while j < w.@count() do
      if g[i].eq(w[j]) then result = true; return; end if;
      j += 1;
    end do;
    i += 1;
  end do;
  result = false;
end fun;

fun _jwtCheckClaims(claims, opts, now)
  var leeway = _jwtOptNum(opts, 'leeway', 0);
  if claims.@has('exp') then
    var e = claims['exp'];
    if not _jwtIsNum(e) then result = 'jwt: invalid exp'; return; end if;
    if now >= e + leeway then result = 'jwt: token expired'; return; end if;
  elsif _jwtHas(opts, 'requireExp') and opts['requireExp'] = true then
    result = 'jwt: missing exp';
    return;
  end if;
  if claims.@has('nbf') then
    var n = claims['nbf'];
    if not _jwtIsNum(n) then result = 'jwt: invalid nbf'; return; end if;
    if now + leeway < n then result = 'jwt: token not yet valid'; return; end if;
  end if;
  if claims.@has('iat') then
    var i = claims['iat'];
    if not _jwtIsNum(i) then result = 'jwt: invalid iat'; return; end if;
    if i > now + leeway then result = 'jwt: token issued in the future'; return; end if;
  end if;
  if _jwtHas(opts, 'issuer') then
    var iss = claims['iss'];
    var wantIss = opts['issuer'];
    if iss.type() <> 8 or wantIss.type() <> 8 or not iss.eq(wantIss) then
      result = 'jwt: issuer mismatch';
      return;
    end if;
  end if;
  if _jwtHas(opts, 'audience') then
    if not _jwtAudMatch(claims['aud'], opts['audience']) then
      result = 'jwt: audience mismatch';
      return;
    end if;
  end if;
  if _jwtHas(opts, 'subject') then
    var sub = claims['sub'];
    var wantSub = opts['subject'];
    if sub.type() <> 8 or wantSub.type() <> 8 or not sub.eq(wantSub) then
      result = 'jwt: subject mismatch';
      return;
    end if;
  end if;
  if _jwtHas(opts, 'jwtid') then
    var jti = claims['jti'];
    var wantJti = opts['jwtid'];
    if jti.type() <> 8 or wantJti.type() <> 8 or not jti.eq(wantJti) then
      result = 'jwt: jwtid mismatch';
      return;
    end if;
  end if;
  result = '';
end fun;

fun _jwtAlgorithms(opts)
  var out = new [];
  if _jwtHas(opts, 'algorithms') then
    var vs = _jwtValues(opts['algorithms']);
    var i = 0;
    while i < vs.@count() do
      out.@add(_jwtAlg(vs[i]));
      i += 1;
    end do;
  else
    out.@add('HS256');
    out.@add('HS384');
    out.@add('HS512');
  end if;
  result = out;
end fun;

fun _jwtAlgAllowed(list, alg)
  var i = 0;
  while i < list.@count() do
    if list[i].eq(alg) then result = true; return; end if;
    i += 1;
  end do;
  result = false;
end fun;

class _JwtApi()
  fun now()
    result = AuthUnixNow();
  end fun;

  fun sign(claims, key, opts)
    _jwtKey(key);
    _jwtCheckOpts(opts, _JWT_SIGN_OPTS);
    _jwtObj(claims, 'claims');
    var alg = 'HS256';
    if _jwtHas(opts, 'alg') then alg = _jwtAlg(opts['alg']); end if;
    var now = 0;
    if _jwtHas(opts, 'expiresIn') or _jwtHas(opts, 'notBefore') then
      if _jwtHas(opts, 'now') then
        now = _jwtOptNum(opts, 'now', 0);
      else
        now = AuthUnixNow();
      end if;
    end if;
    var c = _jwtCopySet(claims);
    if _jwtHas(opts, 'expiresIn') and not c.@has('exp') then
      c['exp'] = now + _jwtOptNum(opts, 'expiresIn', 0);
    end if;
    if _jwtHas(opts, 'notBefore') and not c.@has('nbf') then
      c['nbf'] = now + _jwtOptNum(opts, 'notBefore', 0);
    end if;
    var h = _jwtHeader(alg, _jwtGetHeaders(opts));
    var hb = AuthB64UrlEncode(h.@toJson(json: true));
    var pb = AuthB64UrlEncode(c.@toJson(json: true));
    var input = hb & '.' & pb;
    var sig = AuthB64UrlEncode(AuthHmacRaw(key, input, _jwtHashName(alg)));
    result = input & '.' & sig;
  end fun;

  fun decode(token)
    var r = new [];
    r.ok = false;
    r.error = '';
    r.header = nil;
    r.claims = nil;
    if token.type() <> 8 then
      r.error = 'jwt: token must be a string';
      result = r;
      return;
    end if;
    var sp = _jwtSplit(token);
    if not sp['ok'] then
      r.error = sp['error'];
      result = r;
      return;
    end if;
    try
      r.header = _jwtDecodePart(sp['a'], 'header');
    except
      r.error = 'jwt: invalid header';
      result = r;
      return;
    end try;
    try
      r.claims = _jwtDecodePart(sp['b'], 'claims');
    except
      r.error = 'jwt: invalid claims';
      result = r;
      return;
    end try;
    r.ok = true;
    r.error = nil;
    result = r;
  end fun;

  fun verify(token, key, opts)
    _jwtKey(key);
    _jwtCheckOpts(opts, _JWT_VERIFY_OPTS);
    var r = new [];
    r.ok = false;
    r.error = '';
    r.header = nil;
    r.claims = nil;
    if token.type() <> 8 then
      r.error = 'jwt: token must be a string';
      result = r;
      return;
    end if;
    var sp = _jwtSplit(token);
    if not sp['ok'] then
      r.error = sp['error'];
      result = r;
      return;
    end if;
    var hdr = nil;
    try
      hdr = _jwtDecodePart(sp['a'], 'header');
    except
      r.error = 'jwt: invalid header';
      result = r;
      return;
    end try;
    try
      _jwtHeaderCheck(hdr);
    except
      r.error = 'jwt: unsupported header';
      result = r;
      return;
    end try;
    var alg = '';
    try
      alg = _jwtAlg(hdr['alg']);
    except
      r.error = 'jwt: unsupported alg';
      result = r;
      return;
    end try;
    if not _jwtAlgAllowed(_jwtAlgorithms(opts), alg) then
      r.error = 'jwt: alg not allowed';
      result = r;
      return;
    end if;
    var want = AuthHmacRaw(key, sp['a'] & '.' & sp['b'], _jwtHashName(alg));
    var got = '';
    try
      got = AuthB64UrlDecode(sp['c']);
    except
      r.error = 'jwt: invalid signature';
      result = r;
      return;
    end try;
    if not AuthBytesEqual(want, got) then
      r.error = 'jwt: signature mismatch';
      result = r;
      return;
    end if;
    r.header = hdr;
    try
      r.claims = _jwtDecodePart(sp['b'], 'claims');
    except
      r.error = 'jwt: invalid claims';
      result = r;
      return;
    end try;
    var needNow = r.claims.@has('exp') or r.claims.@has('nbf') or r.claims.@has('iat') or
      (_jwtHas(opts, 'requireExp') and opts['requireExp'] = true);
    var now = 0;
    if needNow then
      if _jwtHas(opts, 'now') then
        now = _jwtOptNum(opts, 'now', 0);
      else
        now = AuthUnixNow();
      end if;
    end if;
    var err = _jwtCheckClaims(r.claims, opts, now);
    if err <> '' then
      r.error = err;
      result = r;
      return;
    end if;
    r.ok = true;
    r.error = nil;
    result = r;
  end fun;
end class;

fun _jwtGetHeaders(opts)
  if _jwtHas(opts, 'headers') then result = opts['headers']; else result = nil; end if;
end fun;

var jwt = _JwtApi();
