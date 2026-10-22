// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// http-auth: HTTP Basic authentication middleware (RFC 7617). Other schemes
// can reuse the credential and principal shapes.
//
//     use 'http-auth.fun';
//
//     fun verifyBasic(req, c)
//       var u = Users.find(c['user']);          // DB / cache / external
//       if u = nil then return false; end if
//       if not checkPassword(u, c['pass']) then return false; end if
//       result = [id: u.id, user: u.name, roles: u.roles];
//     end fun;
//
//     app.Use(HttpBasicAuth(verifyBasic, [realm: 'api']));
//
// Options: realm (default 'Restricted'), optional (true allows a missing
// Authorization header; invalid credentials still fail).
//
// `verify(req, credentials)` is the application hook: it receives the request
// and the parsed credentials, and returns:
//   * false / nil                         -> 401 (default challenge)
//   * true                                -> success, default principal
//   * a principal set                     -> success, stored in req.auth
//   * a set with status >= 400            -> custom failure (status/message/headers)
//
// status, message and headers are reserved on the verifier result; use other
// keys for business claims. Basic sends credentials as base64, not encryption,
// so use HTTPS. Authentication only: role/policy checks stay in the handler.
//
// credentials is scheme-specific: Basic is
//   [scheme: 'basic', user: '...', pass: '...'].
// In verifier mode the password is cleared after verification; req.auth holds
// the principal only. With no verifier, HttpBasicAuth() is parse-only: it sets
// req.credentials and calls nx(), and the application owns the policy.
use 'lib-base64.fun';

fun _authWs(c)
  result = c = ' ' or c = 9.toChar();
end fun;

fun _authTrim(s)
  var b = 0;
  var e = s.length();
  while b < e and _authWs(s.substr(b, 1)) do b += 1; end do;
  while e > b and _authWs(s.substr(e - 1, 1)) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

fun _authB64Ok(s)
  result = true;
  var i = 0;
  while i < s.length() do
    if 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/='.subpos(s.substr(i, 1)) < 0 then
      result = false;
      return;
    end if;
    i += 1;
  end do;
end fun;

// Basic payload -> credentials set, or nil when malformed
fun _authBasic(h)
  result = nil;
  if h = nil or h = '' then return; end if;
  var sp = h.subpos(' ');
  if sp <= 0 then return; end if;
  if h.substr(0, sp).lower() <> 'basic' then return; end if;
  var b = _authTrim(h.substr(sp + 1));
  if b = '' or not _authB64Ok(b) then return; end if;
  var raw = fromBase64(b);
  var c = raw.subpos(':');
  if c <= 0 then return; end if;
  var u = raw.substr(0, c);
  var p = raw.substr(c + 1);
  var r = new [];
  r['scheme'] = 'basic';
  r['user'] = u;
  r['pass'] = p;
  result = r;
end fun;

fun _authRealm(opts)
  result = 'Restricted';
  if opts <> nil then
    var r = opts['realm'];
    if r <> nil and r <> '' then
      var s = '' & r;
      s = s.replace(13.toChar(), '').replace(10.toChar(), '');
      s = s.replace('"', "'").replace(92.toChar(), '');   // backslash would escape the closing quote
      result = s;
    end if;
  end if;
end fun;

fun _authFail(res, code, message, headers, realm)
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
    res.header('WWW-Authenticate', 'Basic realm="' & realm & '"');
  end if;
  if message = nil or message = '' then message = 'unauthorized'; end if;
  res.send(message);
end fun;

class CBasicAuth(v, r, o)
  var verify = v;
  var realm = r;
  var optional = o;

  fun run(req, res, nx)
    var h = req.header('authorization');
    var cred = _authBasic(h);
    if verify = nil then
      req.credentials = cred;
      nx();
    elsif cred = nil then
      if optional and (h = nil or h = '') then
        req.auth = nil;
        nx();
      else
        _authFail(res, 401, 'unauthorized', nil, realm);
      end if;
    else
      req.credentials = cred;
      var r = verify(req, cred);
      req.credentials = nil;
      if r = false or r = nil then
        _authFail(res, 401, 'unauthorized', nil, realm);
      elsif r = true then
        var p = new [];
        p['scheme'] = 'basic';
        p['user'] = cred['user'];
        req.auth = p;
        nx();
      else
        var st = r['status'];
        if st <> nil and st >= 400 then
          _authFail(res, st, r['message'], r['headers'], realm);
        else
          var p = new [];
          for k: v in r do p[k] = v; end do;
          if p['scheme'] = nil then p['scheme'] = 'basic'; end if;
          if p['user'] = nil then p['user'] = cred['user']; end if;
          req.auth = p;
          nx();
        end if;
      end if;
    end if;
  end fun;
end class;

fun HttpBasicAuth(verify, opts)
  var realm = _authRealm(opts);
  var optional = false;
  if opts <> nil and opts['optional'] = true then optional = true; end if;
  result = CBasicAuth(verify, realm, optional);
end fun;
