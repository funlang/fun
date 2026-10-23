// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// http-session: cookie-backed server-side sessions (RFC 6265).
//
//     s.Use(HttpSession([
//       name: 'sid',       // cookie name
//       ttl: 86400,        // server-side seconds
//       maxAge: 0,         // cookie seconds; 0 = browser session cookie
//       secure: true,      // HTTPS only
//       sameSite: 'Lax'
//     ]));
//
//     req.session['user'] = 'alice';
//     SessionRegenerate(req);   // after login (new SID)
//     req.session = nil;        // logout
//
// Options: name, ttl, maxAge, secure, sameSite, domain, path, httpOnly, and
// store (get(sid), set(sid, data, ttl), destroy(sid)).
// The cookie carries only a random SID; data stays in the store. Session data
// must be JSON-serializable (it is compared before/after the handler). TTL is
// refreshed when the session is saved. CSRF is not included: SameSite helps,
// but state-changing routes still need a CSRF token.
use 'uuid.fun';

fun _sessNow()
  var p = -2; // QPC counter
  var f = -1; // QPC frequency
  result = p.time() div (f.time() div 1000);
end fun;

class CMemStore()
  var map = new [];
  var lastGc = 0;

  fun gc()
    var now = _sessNow();
    var m = new [];
    for k: v in map do
      if v['expires'] > now then m[k] = v; end if;
    end do;
    map = m;
    lastGc = now;
  end fun;

  fun drop(sid)
    var m = new [];
    for k: v in map do
      if k <> sid then m[k] = v; end if;
    end do;
    map = m;
  end fun;

  fun get(sid)
    var e = map[sid];
    if e = nil then result = nil; return; end if;
    if e['expires'] <= _sessNow() then
      this.drop(sid);
      result = nil;
      return;
    end if;
    result = e['data'];
  end fun;

  fun set(sid, data, ttl)
    var now = _sessNow();
    if map.@count() > 128 and now - lastGc > 60000 then this.gc(); end if;
    var e = new [];
    e['data'] = data;
    e['expires'] = now + ttl * 1000;
    map[sid] = e;
    result = true;
  end fun;

  fun destroy(sid)
    if map[sid] <> nil then this.drop(sid); end if;
    result = true;
  end fun;
end class;

fun _sessionFlush(res, body)
  var ctx = res.sessionCtx;
  if ctx = nil then return; end if;
  res.sessionCtx = nil;

  var req = ctx['req'];
  var store = ctx['store'];
  var name = ctx['name'];
  var cookieOpts = ctx['cookieOpts'];
  var clearOpts = ctx['clearOpts'];
  var ttl = ctx['ttl'];
  var sid = ctx['sid'];
  var stale = ctx['stale'];
  var had = ctx['had'];
  var sess = req.session;
  var regen = req.sessionRegen = true;
  req.sessionRegen = false;

  if sess = nil then
    if sid <> nil then store.destroy(sid); end if;
    if had then res.clearCookie(name, clearOpts); end if;
    return;
  end if;

  var after = sess.@toJson(json: true);
  if regen then
    if sid <> nil then store.destroy(sid); end if;
    sid = UUID();
    store.set(sid, sess, ttl);
    res.cookie(name, sid, cookieOpts);
  elsif after <> ctx['before'] then
    if sid = nil then
      sid = UUID();
      store.set(sid, sess, ttl);
      res.cookie(name, sid, cookieOpts);
    else
      store.set(sid, sess, ttl);
    end if;
  elsif stale and had then
    res.clearCookie(name, clearOpts);
  end if;
end fun;

class CSession(o)
  var name = 'sid';
  var ttl = 86400;
  var maxAge = 0;
  var secure = false;
  var sameSite = 'Lax';
  var domain = nil;
  var path = '/';
  var httpOnly = true;
  var store = nil;
  var cookieOpts = new [];
  var clearOpts = new [];

  if o <> nil then
    if o.@has('name') and o['name'] <> nil and o['name'] <> '' then name = '' & o['name']; end if;
    if o.@has('ttl') then
      ttl = o['ttl'];
      if ttl < 0 then raise 'http-session: ttl must be >= 0'; end if;
    end if;
    if o.@has('maxAge') then
      maxAge = o['maxAge'];
      if maxAge < 0 then raise 'http-session: maxAge must be >= 0'; end if;
    end if;
    if o.@has('secure') and o['secure'] = true then secure = true; end if;
    if o.@has('httpOnly') then httpOnly = (o['httpOnly'] = true); end if;
    if o.@has('domain') and o['domain'] <> nil and o['domain'] <> '' then domain = '' & o['domain']; end if;
    if o.@has('path') and o['path'] <> nil and o['path'] <> '' then path = '' & o['path']; end if;
    if o.@has('sameSite') and o['sameSite'] <> nil then
      var ss = ('' & o['sameSite']).upper();
      if ss = 'LAX' then sameSite = 'Lax';
      elsif ss = 'STRICT' then sameSite = 'Strict';
      elsif ss = 'NONE' then sameSite = 'None';
      else raise 'http-session: sameSite must be Lax, Strict or None'; end if;
    end if;
    if o.@has('store') then store = o['store']; end if;
  end if;
  if sameSite = 'None' and not secure then
    raise 'http-session: sameSite None requires secure';
  end if;
  if store = nil then store = CMemStore(); end if;

  var co = new [];
  co['path'] = path;
  co['httpOnly'] = httpOnly;
  co['sameSite'] = sameSite;
  if secure then co['secure'] = true; end if;
  if domain <> nil then co['domain'] = domain; end if;
  if maxAge > 0 then co['maxAge'] = maxAge; end if;
  cookieOpts = co;

  var cl = new [];
  cl['path'] = path;
  cl['httpOnly'] = httpOnly;
  cl['sameSite'] = sameSite;
  if secure then cl['secure'] = true; end if;
  if domain <> nil then cl['domain'] = domain; end if;
  clearOpts = cl;

  fun run(req, res, nx)
    var h = req.cookie(name);
    var sid = nil;
    var data = nil;
    var stale = false;
    var had = false;
    if h <> nil and h <> '' then
      had = true;
      sid = h;
      data = store.get(sid);
      if data = nil then
        sid = nil;
        stale = true;
      else
        data = data.@toJson(json: true).getJson(json: true);
      end if;
    end if;
    if data = nil then data = new []; end if;
    req.session = data;
    req.sessionRegen = false;

    var ctx = new [];
    ctx['req'] = req;
    ctx['store'] = store;
    ctx['name'] = name;
    ctx['cookieOpts'] = cookieOpts;
    ctx['clearOpts'] = clearOpts;
    ctx['ttl'] = ttl;
    ctx['sid'] = sid;
    ctx['stale'] = stale;
    ctx['had'] = had;
    ctx['before'] = data.@toJson(json: true);
    res.sessionCtx = ctx;
    res.beforeSend(_sessionFlush);
    nx();
  end fun;
end class;

fun HttpSession(opts)
  result = CSession(opts);
end fun;

fun SessionRegenerate(req)
  req.sessionRegen = true;
  result = true;
end fun;
