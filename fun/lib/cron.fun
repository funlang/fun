// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// cron: a small, single-threaded scheduler for cron expressions and fixed
// intervals.
//
//     use 'cron.fun';
//
//     cron.addJob('0 3 * * *', cleanup);
//     cron.addJob('0-30 * * * * *', cleanup, [withSeconds: true]);
//     cron.every('1s', refresh);
//
//     cron.run();   // blocking
//     cron.stop();  // stop after the current callback
//
// The cron expression is Vixie/POSIX-compatible: 5 fields, names, ranges,
// lists and steps, plus the usual @hourly/@daily descriptors. withSeconds:true
// means a 6-field expression whose first field is seconds. Quartz/AWS
// extensions (? L W #, year) are deliberately rejected rather than guessed.
use 'lib-os.fun';

var _cronJobs = new [];
var _cronRunning = false;
var _cronStop = false;

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
  j['lastKey'] = '';
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

fun _cronKey(j, n)
  if j['withSeconds'] then
    result = n['year'] & '-' & n['month'] & '-' & n['day'] & ' ' &
             n['hour'] & ':' & n['minute'] & ':' & n['second'];
  else
    result = n['year'] & '-' & n['month'] & '-' & n['day'] & ' ' &
             n['hour'] & ':' & n['minute'];
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

fun _cronTick(n, nowMs)
  var fired = 0;
  var i = 0;
  while i < _cronJobs.@count() and not _cronStop do
    var j = _cronJobs[i];
    if j['kind'] = 'cron' then
      if _cronMatch(j, n) then
        var key = _cronKey(j, n);
        if j['lastKey'] <> key then
          j['lastKey'] = key;
          fired += 1;
          try
            j['fn']();
          except
          end try;
        end if;
      end if;
    elsif nowMs >= j['next'] then
      fired += 1;
      var interval = j['interval'];
      // Missed runs are skipped; a long callback does not create a burst.
      var nextAt = nowMs + interval;
      try
        j['fn']();
      except
      end try;
      var after = _cronNowMs();
      if nextAt <= after then nextAt = after + interval; end if;
      j['next'] = nextAt;
    end if;
    i += 1;
  end do;
  result = fired;
end fun;

fun _cronReset()
  _cronJobs = new [];
  _cronRunning = false;
  _cronStop = false;
end fun;

class _CronApi()
  fun addJob(expr, fn, opts)
    var ws = false;
    if opts <> nil then
      if opts.type() = 11 then ws = opts;
      elsif opts.@has('withSeconds') then ws = opts['withSeconds'];
      end if;
    end if;
    var j = _cronParseExpr(expr, ws);
    j['kind'] = 'cron';
    j['fn'] = fn;
    _cronJobs.@add(j);
  end fun;

  fun every(interval, fn)
    var ms = _cronDurationMs(interval);
    var j = new [];
    j['kind'] = 'every';
    j['interval'] = ms;
    j['next'] = _cronNowMs() + ms;
    j['fn'] = fn;
    _cronJobs.@add(j);
  end fun;

  fun run()
    if _cronRunning then raise 'cron: already running'; end if;
    _cronRunning = true;
    _cronStop = false;
    try
      while not _cronStop do
        _cronTick(_cronNow(), _cronNowMs());
        if not _cronStop then sleep(50); end if;
      end do;
    finally
      _cronRunning = false;
    end try;
  end fun;

  fun stop()
    _cronStop = true;
  end fun;
end class;

var cron = _CronApi();
