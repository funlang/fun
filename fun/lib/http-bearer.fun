// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// http-bearer: HTTP Bearer authentication middleware (RFC 6750).
//
//     use 'http-bearer.fun';
//
//     fun verifyBearer(req, c)
//       var claims = Jwt.verify(c['token']);      // app code
//       if claims = nil then return false; end if
//       result = [sub: claims.sub, roles: claims.roles];
//     end fun;
//
//     api.Use(HttpBearerAuth(verifyBearer, [realm: 'api']));
//
// Options: realm (default 'Restricted'), optional (true allows a missing
// Authorization header; invalid tokens still fail).
//
// verify(req, credentials) returns:
//   * false / nil -> 401 (invalid_token challenge)
//   * true -> success, default principal [scheme:'bearer']
//   * a principal set -> success, stored in req.auth
//   * a set with status >= 400 -> custom failure (status/message/headers)
//
// status, message and headers are reserved on the verifier result; use other
// keys for business claims. credentials is [scheme:'bearer', token:'...']; the
// token is cleared after verification and is never stored in req.auth. Only the
// Authorization header is read; query/form tokens are not accepted. Bearer
// tokens are secrets: use HTTPS. Parse-only mode keeps the token in
// req.credentials for explicit forwarding; the application must clear it.
// Authentication only: scope/role checks stay in the handler.
fun _bearerWs(c)
  result = c = ' ' or c = 9.toChar();
end fun;

fun _bearerTrim(s)
  var b = 0;
  var e = s.length();
  while b < e and _bearerWs(s.substr(b, 1)) do b += 1; end do;
  while e > b and _bearerWs(s.substr(e - 1, 1)) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

// RFC 7235 token68: ALPHA / DIGIT / - . _ ~ + /, then optional '=' padding.
fun _bearerTokenOk(s)
  result = false;
  if s = '' then return; end if;
  var pad = false;
  var base = 0;
  var i = 0;
  while i < s.length() do
    var c = s.substr(i, 1);
    if c = '=' then
      pad = true;
    elsif pad then
      return;
    elsif 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/'.subpos(c) < 0 then
      return;
    else
      base += 1;
    end if;
    i += 1;
  end do;
  result = base > 0;
end fun;

// Authorization header -> credentials set, or nil when malformed
fun _bearerParse(h)
  result = nil;
  if h = nil or h = '' then return; end if;
  var sp = h.subpos(' ');
  if sp <= 0 then return; end if;
  if h.substr(0, sp).lower() <> 'bearer' then return; end if;
  var t = _bearerTrim(h.substr(sp + 1));
  if not _bearerTokenOk(t) then return; end if;
  var r = new [];
  r['scheme'] = 'bearer';
  r['token'] = t;
  result = r;
end fun;

fun _bearerRealm(opts)
  result = 'Restricted';
  if opts <> nil then
    var r = opts['realm'];
    if r <> nil and r <> '' then
      var s = '' & r;
      s = s.replace(13.toChar(), '').replace(10.toChar(), '');
      s = s.replace('"', "'").replace(92.toChar(), '');
      result = s;
    end if;
  end if;
end fun;

fun _bearerFail(res, code, message, headers, realm, err)
  if code = nil or code < 400 then code = 401; end if;
  res.status(code);
  var hasCt = false;
  var hasWa = false;
  if headers <> nil then
    for k: v in headers do
      if k.lower() = 'content-type' then hasCt = true; end if;
      if code = 401 and k.lower() = 'www-authenticate' then hasWa = true; end if;
      res.header(k, v);
    end do;
  end if;
  if not hasCt then
    res.header('Content-Type', 'text/plain; charset=utf-8');
  end if;
  if code = 401 and not hasWa then
    var ch = 'Bearer realm="' & realm & '"';
    if err <> nil and err <> '' then ch &= ', error="' & err & '"'; end if;
    res.header('WWW-Authenticate', ch);
  end if;
  if message = nil or message = '' then message = 'unauthorized'; end if;
  res.send(message);
end fun;

class CBearerAuth(v, r, o)
  var verify = v;
  var realm = r;
  var optional = o;

  fun run(req, res, nx)
    var h = req.header('authorization');
    var cred = _bearerParse(h);
    if verify = nil then
      req.credentials = cred;
      nx();
    elsif cred = nil then
      if optional and (h = nil or h = '') then
        req.auth = nil;
        nx();
      elsif h = nil or h = '' then
        _bearerFail(res, 401, 'unauthorized', nil, realm, nil);
      else
        _bearerFail(res, 401, 'unauthorized', nil, realm, 'invalid_request');
      end if;
    else
      req.credentials = cred;
      var r = verify(req, cred);
      req.credentials = nil;
      if r = false or r = nil then
        _bearerFail(res, 401, 'unauthorized', nil, realm, 'invalid_token');
      elsif r = true then
        var p = new [];
        p['scheme'] = 'bearer';
        req.auth = p;
        nx();
      else
        var st = r['status'];
        if st <> nil and st >= 400 then
          _bearerFail(res, st, r['message'], r['headers'], realm, 'invalid_token');
        else
          var p = new [];
          for k: v in r do p[k] = v; end do;
          if p['scheme'] = nil then p['scheme'] = 'bearer'; end if;
          if p.@has('token') then p['token'] = nil; end if;
          req.auth = p;
          nx();
        end if;
      end if;
    end if;
  end fun;
end class;

fun HttpBearerAuth(verify, opts)
  var realm = _bearerRealm(opts);
  var optional = false;
  if opts <> nil and opts['optional'] = true then optional = true; end if;
  result = CBearerAuth(verify, realm, optional);
end fun;
