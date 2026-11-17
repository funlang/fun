// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// cron: a small, single-threaded scheduler for cron expressions and fixed
// intervals. Each CronScheduler owns its jobs and run/stop state.
//
//     use 'cron.fun';
//
//     var s = CronScheduler();
//     s.addJob('0 3 * * *', cleanup);
//     s.addJob('0-30 * * * * *', cleanup, [withSeconds: true]);
//     s.every('1s', refresh);
//
//     s.run();   // blocking
//     s.stop();  // stop after the current callback
//
// addJob and every return a per-instance id; removeJob(id) removes one job
// and jobs() returns a snapshot. Ids start at 1 and are never reused.
//
// CronScheduler([onError: (job, err) { ... }]) reports callback exceptions with
// a job snapshot and runtime.lastError(); without it, they stay silent.
//
// Jobs are scheduled by next occurrence: nextRun(id) returns the next time and
// run() sleeps until the nearest one (capped at 1s); missed runs fire once.
//
// Create one scheduler per daemon or test; there is no process-global
// instance. The cron expression is Vixie/POSIX-compatible: 5 fields, names,
// ranges, lists and steps, plus the usual @hourly/@daily descriptors.
// withSeconds:true means a 6-field expression whose first field is seconds.
// Quartz/AWS extensions (? L W #, year) are deliberately rejected rather than
// guessed.
use 'lib-os.fun';
use 'runtime.fun';

fun _cronTrim(s)
  if s = nil then result = ''; return; end if;
  var a = 0;
  var b = s.length();
  while a < b and _cronSpace(s.substr(a, 1)) do a += 1; end do;
  while b > a and _cronSpace(s.substr(b - 1, 1)) do b -= 1; end do;
  result = s.substr(a, b - a);
end fun;

fun _cronSpace(c)
  result = c = ' ' or c = 9.toChar() or c = 13.toChar() or c = 10.toChar();
end fun;

fun _cronSplit(s)
  result = new [];
  var cur = '';
  var i = 0;
  while i <= s.length() do
    var ch = '';
    if i < s.length() then ch = s.substr(i, 1); end if;
    if i = s.length() or _cronSpace(ch) then
      if cur <> '' then result.@add(cur); cur = ''; end if;
    else
      cur &= ch;
    end if;
    i += 1;
  end do;
end fun;

fun _cronSplitComma(s)
  result = new [];
  var cur = '';
  var i = 0;
  while i <= s.length() do
    var ch = '';
    if i < s.length() then ch = s.substr(i, 1); end if;
    if i = s.length() or ch = ',' then
      result.@add(cur);
      cur = '';
    else
      cur &= ch;
    end if;
    i += 1;
  end do;
end fun;

fun _cronDigits(s)
  if s = '' then result = false; return; end if;
  for i = 0 to s.length() - 1 do
    var c = s.substr(i, 1);
    if c < '0' or c > '9' then result = false; return; end if;
  end do;
  result = true;
end fun;

fun _cronName(text, names)
  if names = nil then result = nil; return; end if;
  var key = text.lower();
  if names.@has(key) then result = names[key]; else result = nil; end if;
end fun;

fun _cronValue(text, names, label, lo, hi)
  var v = _cronName(text, names);
  if v.type() = 0 then
    if not _cronDigits(text) then
      raise 'cron: ' & label & ': invalid value "' & text & '"';
    end if;
    v = text.toNum();
  end if;
  if v < lo or v > hi then
    raise 'cron: ' & label & ': value out of range: ' & ('' & v);
  end if;
  result = v;
end fun;

fun _cronPut(vals, v, dow)
  if dow and v = 7 then v = 0; end if;
  vals[v] = true;
end fun;

fun _cronAdd(vals, lo, hi, stepv, minv, maxv, label, dow)
  if lo < minv or hi > maxv or lo > hi or stepv <= 0 then
    raise 'cron: ' & label & ': invalid range';
  end if;
  var v = lo;
  while v <= hi do
    _cronPut(vals, v, dow);
    v += stepv;
  end do;
end fun;

// Parse one field into [vals: set, wild: bool].
fun _cronField(text, minv, maxv, names, label, dow)
  var vals = new [];
  var wild = false;
  var parts = _cronSplitComma(text);
  if parts.@count() = 0 then raise 'cron: ' & label & ': empty field'; end if;

  for i = 0 to parts.@count() - 1 do
    var p = _cronTrim(parts[i]);
    if p = '' then raise 'cron: ' & label & ': empty list item'; end if;
    if p = '*' then wild = true; end if;

    var stepv = 1;
    var base = p;
    var slash = p.subpos('/');
    if slash >= 0 then
      var stepText = p.substr(slash + 1);
      if not _cronDigits(stepText) then
        raise 'cron: ' & label & ': invalid step "' & stepText & '"';
      end if;
      stepv = stepText.toNum();
      if stepv <= 0 then raise 'cron: ' & label & ': step must be > 0'; end if;
      base = p.substr(0, slash);
    end if;

    if base = '*' then
      _cronAdd(vals, minv, maxv, stepv, minv, maxv, label, dow);
    else
      var dash = base.subpos('-');
      if dash >= 0 then
        var lo = _cronValue(_cronTrim(base.substr(0, dash)), names, label, minv, maxv);
        var hi = _cronValue(_cronTrim(base.substr(dash + 1)), names, label, minv, maxv);
        _cronAdd(vals, lo, hi, stepv, minv, maxv, label, dow);
      else
        if slash >= 0 then
          raise 'cron: ' & label & ': step requires * or a range';
        end if;
        _cronPut(vals, _cronValue(base, names, label, minv, maxv), dow);
      end if;
    end if;
  end do;

  result = new [];
  result['vals'] = vals;
  result['wild'] = wild;
end fun;

fun _cronMonthNames()
  result = [jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
            jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12];
end fun;

fun _cronDowNames()
  result = [sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6];
end fun;

// Parse an expression into an internal job schedule. Kept internal so tests can
// exercise field matching without running a real minute clock.
fun _cronParseExpr(expr, withSeconds)
  if expr = nil or ('' & expr) = '' then raise 'cron: empty expression'; end if;
  var text = _cronTrim('' & expr);
  var low = text.lower();
  var mac = false;
  if low = '@hourly' then text = '0 * * * *'; mac = true;
  elsif low = '@daily' or low = '@midnight' then text = '0 0 * * *'; mac = true;
  elsif low = '@weekly' then text = '0 0 * * 0'; mac = true;
  elsif low = '@monthly' then text = '0 0 1 * *'; mac = true;
  elsif low = '@yearly' or low = '@annually' then text = '0 0 1 1 *'; mac = true;
  elsif low.substr(0, 1) = '@' then
    raise 'cron: unsupported descriptor "' & text & '"';
  end if;
  if withSeconds and mac then text = '0 ' & text; end if;

  var fs = _cronSplit(text);
  var want = 5;
  if withSeconds then want = 6; end if;
  if fs.@count() <> want then
    raise 'cron: expected ' & want & ' fields, got ' & fs.@count();
  end if;

  var j = new [];
  j['withSeconds'] = withSeconds;
  var off = 0;
  if withSeconds then
    var sec = _cronField(fs[0], 0, 59, nil, 'second', false);
    j['second'] = sec['vals'];
    off = 1;
  end if;

  var mon = _cronField(fs[off + 3], 1, 12, _cronMonthNames(), 'month', false);
  var dom = _cronField(fs[off + 2], 1, 31, nil, 'day-of-month', false);
  var dow = _cronField(fs[off + 4], 0, 7, _cronDowNames(), 'day-of-week', true);
  j['minute'] = _cronField(fs[off + 0], 0, 59, nil, 'minute', false)['vals'];
  j['hour']   = _cronField(fs[off + 1], 0, 23, nil, 'hour', false)['vals'];
  j['dom']    = dom['vals'];
  j['month']  = mon['vals'];
  j['dow']    = dow['vals'];
  j['domWild'] = dom['wild'];
  j['dowWild'] = dow['wild'];
  result = j;
end fun;

fun _cronDow(y, m, d)
  var t = new [];
  t.@add(0); t.@add(3); t.@add(2); t.@add(5); t.@add(0);
  t.@add(3); t.@add(5); t.@add(1); t.@add(4); t.@add(6);
  t.@add(2); t.@add(4);
  var yy = y;
  if m < 3 then yy -= 1; end if;
  result = (yy + yy div 4 - yy div 100 + yy div 400 + t[m - 1] + d) mod 7;
end fun;

fun _cronNow()
  var s = 1.time().format('yyyy-mm-dd hh:nn:ss');
  var n = new [];
  n['year']   = s.substr(0, 4).toNum();
  n['month']  = s.substr(5, 2).toNum();
  n['day']    = s.substr(8, 2).toNum();
  n['hour']   = s.substr(11, 2).toNum();
  n['minute'] = s.substr(14, 2).toNum();
  n['second'] = s.substr(17, 2).toNum();
  n['dow']    = _cronDow(n['year'], n['month'], n['day']);
  result = n;
end fun;

fun _cronNowMs()
  var p = -2;
  var f = -1;
  result = p.time() div (f.time() div 1000);
end fun;

fun _cronMatch(j, n)
  if not j['month'][n['month']] then result = false; return; end if;
  if not j['hour'][n['hour']] then result = false; return; end if;
  if not j['minute'][n['minute']] then result = false; return; end if;
  if j['withSeconds'] then
    if not j['second'][n['second']] then result = false; return; end if;
  elsif n['second'] <> 0 then
    result = false;
    return;
  end if;

  var dm = j['dom'][n['day']] <> nil;
  var dw = j['dow'][n['dow']] <> nil;
  if j['domWild'] then
    if j['dowWild'] then result = true; else result = dw; end if;
  elsif j['dowWild'] then
    result = dm;
  else
    result = dm or dw;
  end if;
end fun;

fun _cronDurationMs(v)
  if v.type() = 0 then raise 'cron: interval is required'; end if;
  if v.type() = 3 or v.type() = 5 then
    var n = v div 1;
    if n <= 0 then raise 'cron: interval must be > 0'; end if;
    result = n;
    return;
  end if;
  if v.type() <> 8 then raise 'cron: interval must be a number of milliseconds or a duration string'; end if;

  var s = _cronTrim('' & v).lower();
  if s = '' then raise 'cron: interval is empty'; end if;
  var total = 0;
  var num = '';
  var i = 0;
  while i < s.length() do
    var c = s.substr(i, 1);
    if c >= '0' and c <= '9' then
      num &= c;
    else
      if num = '' then raise 'cron: invalid interval "' & ('' & v) & '"'; end if;
      var unit = c;
      var mult = 0;
      if c = 'm' then
        if i + 1 < s.length() and s.substr(i + 1, 1) = 's' then
          unit = 'ms';
          i += 1;
        end if;
      end if;
      if unit = 'ms' then mult = 1;
      elsif unit = 's' then mult = 1000;
      elsif unit = 'm' then mult = 60 * 1000;
      elsif unit = 'h' then mult = 60 * 60 * 1000;
      elsif unit = 'd' then mult = 24 * 60 * 60 * 1000;
      else raise 'cron: unknown duration unit "' & unit & '"'; end if;
      total += num.toNum() * mult;
      num = '';
    end if;
    i += 1;
  end do;
  if num <> '' then raise 'cron: duration is missing a unit: "' & ('' & v) & '"'; end if;
  if total <= 0 then raise 'cron: interval must be > 0'; end if;
  result = total;
end fun;

fun _cronLeap(y)
  result = (y mod 4 = 0) and (y mod 100 <> 0 or y mod 400 = 0);
end fun;

fun _cronDaysInMonth(y, m)
  if m = 2 then
    if _cronLeap(y) then result = 29; else result = 28; end if;
  elsif m = 4 or m = 6 or m = 9 or m = 11 then
    result = 30;
  else
    result = 31;
  end if;
end fun;

fun _cronAt(y, mo, d, h, mi, s, dow)
  var n = new [];
  n['year'] = y;
  n['month'] = mo;
  n['day'] = d;
  n['hour'] = h;
  n['minute'] = mi;
  n['second'] = s;
  n['dow'] = dow;
  result = n;
end fun;

fun _cronDayNumber(y, m, d)
  var yy = y;
  var mm = m;
  if mm <= 2 then yy -= 1; mm += 12; end if;
  result = 365 * yy + yy div 4 - yy div 100 + yy div 400
         + (153 * (mm - 3) + 2) div 5 + d - 719469;
end fun;

fun _cronDiffSec(a, b)
  var days = _cronDayNumber(b['year'], b['month'], b['day'])
           - _cronDayNumber(a['year'], a['month'], a['day']);
  result = days * 86400
         + (b['hour'] - a['hour']) * 3600
         + (b['minute'] - a['minute']) * 60
         + (b['second'] - a['second']);
end fun;

fun _cronNext(j, from)
  var y  = from['year'];
  var mo = from['month'];
  var d  = from['day'];
  var h  = from['hour'];
  var mi = from['minute'];
  var s  = from['second'];
  var dow = from['dow'];

  if j['withSeconds'] then
    s += 1;
  else
    mi += 1;
    s = 0;
  end if;
  if s > 59 then s = 0; mi += 1; end if;
  if mi > 59 then mi = 0; h += 1; end if;
  if h > 23 then h = 0; d += 1; dow = (dow + 1) mod 7; end if;
  if d > _cronDaysInMonth(y, mo) then
    d = 1;
    mo += 1;
    if mo > 12 then mo = 1; y += 1; end if;
  end if;

  var guard = 0;
  while guard < 366 * 8 do
    if j['month'][mo] then
      var dm = j['dom'][d] <> nil;
      var dw = j['dow'][dow] <> nil;
      var dayOk = false;
      if j['domWild'] then
        if j['dowWild'] then dayOk = true; else dayOk = dw; end if;
      elsif j['dowWild'] then
        dayOk = dm;
      else
        dayOk = dm or dw;
      end if;
      if dayOk then
        var hh = h;
        while hh <= 23 do
          if j['hour'][hh] then
            var mstart = 0;
            if hh = h then mstart = mi; end if;
            var mm = mstart;
            while mm <= 59 do
              if j['minute'][mm] then
                var sstart = 0;
                if hh = h and mm = mi then sstart = s; end if;
                if j['withSeconds'] then
                  var ss = sstart;
                  while ss <= 59 do
                    if j['second'][ss] then
                      result = _cronAt(y, mo, d, hh, mm, ss, dow);
                      return;
                    end if;
                    ss += 1;
                  end do;
                elsif sstart = 0 then
                  result = _cronAt(y, mo, d, hh, mm, 0, dow);
                  return;
                end if;
              end if;
              mm += 1;
            end do;
          end if;
          hh += 1;
        end do;
      end if;
    end if;

    d += 1;
    dow = (dow + 1) mod 7;
    h = 0; mi = 0; s = 0;
    if d > _cronDaysInMonth(y, mo) then
      d = 1;
      mo += 1;
      if mo > 12 then mo = 1; y += 1; end if;
    end if;
    guard += 1;
  end do;
  result = nil;
end fun;

fun _cronJobView(j)
  var item = new [];
  item['id'] = j['id'];
  item['kind'] = j['kind'];
  if j['kind'] = 'cron' then
    item['expr'] = j['expr'];
    item['withSeconds'] = j['withSeconds'];
  else
    item['intervalMs'] = j['intervalMs'];
  end if;
  result = item;
end fun;

class CronScheduler(opts)
  var _jobs = new [];
  var _running = false;
  var _stopped = false;
  var _nextId = 1;
  var _onError = nil;

  if opts <> nil and opts.@has('onError') then
    _onError = opts['onError'];
  end if;

  fun addJob(expr, fn, opts)
    var ws = false;
    if opts <> nil then
      if opts.type() = 11 then ws = opts;
      elsif opts.@has('withSeconds') then
        if opts['withSeconds'] then ws = true; end if;
      end if;
    end if;
    var j = _cronParseExpr(expr, ws);
    var n = _cronNow();
    var nx = _cronNext(j, n);
    if nx = nil then raise 'cron: no occurrence in the next 8 years'; end if;
    j['id'] = _nextId;
    _nextId += 1;
    j['kind'] = 'cron';
    j['expr'] = _cronTrim('' & expr);
    j['fn'] = fn;
    j['nextWall'] = nx;
    j['removed'] = false;
    _jobs.@add(j);
    result = j['id'];
  end fun;

  fun every(interval, fn)
    var ms = _cronDurationMs(interval);
    var j = new [];
    j['id'] = _nextId;
    _nextId += 1;
    j['kind'] = 'every';
    j['intervalMs'] = ms;
    j['nextMs'] = _cronNowMs() + ms;
    j['fn'] = fn;
    j['removed'] = false;
    _jobs.@add(j);
    result = j['id'];
  end fun;

  fun run()
    if _running then raise 'cron: already running'; end if;
    _running = true;
    _stopped = false;
    try
      while not _stopped do
        var n = _cronNow();
        var nowMs = _cronNowMs();
        this._tick(n, nowMs);
        if not _stopped then
          var wait = this._waitMs(_cronNow(), _cronNowMs());
          if wait < 10 then wait = 10; end if;
          sleep(wait);
        end if;
      end do;
    finally
      _running = false;
    end try;
  end fun;

  fun _waitMs(n, nowMs)
    var wait = 1000;
    for j in _jobs do
      if not j['removed'] then
        if j['kind'] = 'cron' then
          if j['nextWall'] <> nil then
            var d = _cronDiffSec(n, j['nextWall']) * 1000;
            if d < 0 then d = 0; end if;
            if d < wait then wait = d; end if;
          end if;
        else
          var d = j['nextMs'] - nowMs;
          if d < 0 then d = 0; end if;
          if d < wait then wait = d; end if;
        end if;
      end if;
    end do;
    result = wait;
  end fun;

  fun stop()
    _stopped = true;
  end fun;

  fun removeJob(id)
    if id = nil then result = false; return; end if;
    if id.type() <> 3 and id.type() <> 5 then result = false; return; end if;
    var keep = new [];
    var found = false;
    for j in _jobs do
      if not found and j['id'] = id then
        found = true;
        j['removed'] = true;
      else
        keep.@add(j);
      end if;
    end do;
    if found then _jobs = keep; end if;
    result = found;
  end fun;

  fun jobs()
    result = new [];
    for j in _jobs do
      result.@add(_cronJobView(j));
    end do;
  end fun;

  fun _findJob(id)
    for j in _jobs do
      if j['id'] = id then result = j; return; end if;
    end do;
    result = nil;
  end fun;

  fun nextRun(id)
    if id = nil then result = nil; return; end if;
    if id.type() <> 3 and id.type() <> 5 then result = nil; return; end if;
    var j = this._findJob(id);
    if j = nil then result = nil; return; end if;
    if j['kind'] = 'cron' then
      var n = _cronNow();
      var nx = _cronNext(j, n);
      if nx = nil then result = nil; return; end if;
      result = 1.time() + _cronDiffSec(n, nx) / 86400;
    else
      var nowMs = _cronNowMs();
      var nextAt = j['nextMs'];
      var interval = j['intervalMs'];
      if nextAt <= nowMs then
        var k = (nowMs - nextAt) div interval + 1;
        nextAt += k * interval;
      end if;
      result = 1.time() + (nextAt - nowMs) / 86400000;
    end if;
  end fun;

  fun _reportError(j)
    if _onError = nil then return; end if;
    var e = nil;
    try
      e = runtime.lastError();
    except
    end try;
    try
      _onError(_cronJobView(j), e);
    except
    end try;
  end fun;

  fun _tick(n, nowMs)
    var fired = 0;
    var list = new [];
    for j in _jobs do list.@add(j); end do;
    var i = 0;
    while i < list.@count() and not _stopped do
      var j = list[i];
      if not j['removed'] then
        if j['kind'] = 'cron' then
          if j['nextWall'] <> nil and _cronDiffSec(j['nextWall'], n) >= 0 then
            fired += 1;
            try
              j['fn']();
            except
              this._reportError(j);
            end try;
            var after = _cronNow();
            var nx = _cronNext(j, after);
            if nx = nil then
              this.removeJob(j['id']);
            else
              j['nextWall'] = nx;
            end if;
          end if;
        elsif nowMs >= j['nextMs'] then
          fired += 1;
          var interval = j['intervalMs'];
          // Missed runs are skipped; a long callback does not create a burst.
          var nextAt = nowMs + interval;
          try
            j['fn']();
          except
            this._reportError(j);
          end try;
          var afterMs = _cronNowMs();
          if nextAt <= afterMs then nextAt = afterMs + interval; end if;
          j['nextMs'] = nextAt;
        end if;
      end if;
      i += 1;
    end do;
    result = fired;
  end fun;
end class;
