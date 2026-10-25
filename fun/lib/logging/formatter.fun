// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/formatter: turn a LogRecord into one line of text or JSON.
use 'levels.fun';

var _formatterDefaultShow = ['time', 'level', 'name', 'message', 'fields'];
var _formatterDefaultTime = 'yyyy-mm-dd hh:nn:ss:zzz';

fun _fmtShow(show)
  result = new [];
  var xs = show;
  if xs = nil then xs = _formatterDefaultShow; end if;
  for i = 0 to xs.@count() - 1 do
    result.@add(xs[i]);
  end do;
end fun;

fun _fmtWant(show)
  var w = new [];
  for i = 0 to show.@count() - 1 do
    w[show[i]] = true;
  end do;
  result = w;
end fun;

fun _fmtTime(rec, format)
  if rec.time = nil then result = ''; else result = rec.time.format(format); end if;
end fun;

fun _fmtSource(src)
  if src = nil then result = ''; return; end if;
  if src.type() = 8 then result = '' & src; return; end if;
  result = (src['file'] or '') & ':' & (src['line'] or '');
end fun;

fun _fmtOneLine(s)
  result = ('' & s).replace(13.toChar(), 92.toChar() & 'n')
                   .replace(10.toChar(), 92.toChar() & 'n');
end fun;

fun _fmtValue(v)
  if v = nil then result = 'nil'; return; end if;
  if v.type() = 8 then
    var s = ('' & v).replace(13.toChar(), 92.toChar() & 'n')
                    .replace(10.toChar(), 92.toChar() & 'n');
    if s = '' or s.subpos(' ') >= 0 or s.subpos('=') >= 0 or
       s.subpos(34.toChar()) >= 0 or s.subpos(92.toChar()) >= 0 or
       s.subpos(13.toChar()) >= 0 or s.subpos(10.toChar()) >= 0 then
      result = 34.toChar() & s.replace(92.toChar(), 92.toChar() & 92.toChar())
                            .replace(34.toChar(), 92.toChar() & 34.toChar()) & 34.toChar();
    else
      result = s;
    end if;
    return;
  end if;
  if v.type() = 3 or v.type() = 5 or v.type() = 11 then
    result = '' & v;
    return;
  end if;
  try
    result = v.@toJson(json: true);
  except
    result = '' & v;
  end try;
end fun;

fun _fmtKeys(fields)
  var ks = new [];
  if fields <> nil then
    for k: v in fields do ks.@add(k); end do;
  end if;
  // insertion sort keeps the formatter dependency-free and deterministic
  for i = 1 to ks.@count() - 1 do
    var x = ks[i];
    var j = i - 1;
    while j >= 0 and ks[j] > x do
      ks[j + 1] = ks[j];
      j -= 1;
    end do;
    ks[j + 1] = x;
  end do;
  result = ks;
end fun;

fun _fmtFieldsText(fields)
  result = '';
  var ks = _fmtKeys(fields);
  for i = 0 to ks.@count() - 1 do
    if result <> '' then result &= ' '; end if;
    result &= ks[i] & '=' & _fmtValue(fields[ks[i]]);
  end do;
end fun;

class _TextFormatter(opts)
  var show = _formatterDefaultShow;
  var timeFormat = _formatterDefaultTime;

  if opts <> nil then
    if opts.@has('show') then show = _fmtShow(opts['show']); end if;
    if opts.@has('timeFormat') and opts['timeFormat'] <> nil then
      timeFormat = opts['timeFormat'];
    end if;
  end if;

  fun format(rec)
    result = '';
    for i = 0 to show.@count() - 1 do
      var part = show[i];
      var s = '';
      if part = 'time' then
        s = _fmtTime(rec, timeFormat);
      elsif part = 'level' then
        s = rec.levelName;
      elsif part = 'name' then
        if rec.name = '' then s = 'root'; else s = rec.name; end if;
      elsif part = 'source' then
        s = _fmtSource(rec.source);
      elsif part = 'message' then
        s = _fmtOneLine(rec.message);
      elsif part = 'fields' then
        s = _fmtFieldsText(rec.fields);
      end if;
      if s <> '' then
        if result <> '' then result &= ' '; end if;
        result &= s;
      end if;
    end do;
  end fun;
end class;

class _JsonFormatter(opts)
  var show = _formatterDefaultShow;
  var timeFormat = _formatterDefaultTime;

  if opts <> nil then
    if opts.@has('show') then show = _fmtShow(opts['show']); end if;
    if opts.@has('timeFormat') and opts['timeFormat'] <> nil then
      timeFormat = opts['timeFormat'];
    end if;
  end if;

  fun format(rec)
    var want = _fmtWant(show);
    var obj = new [];
    if want['time'] then obj['time'] = _fmtTime(rec, timeFormat); end if;
    if want['level'] then obj['level'] = rec.levelName; end if;
    if want['name'] then
      if rec.name = '' then obj['name'] = 'root'; else obj['name'] = rec.name; end if;
    end if;
    if want['source'] then
      var src = _fmtSource(rec.source);
      if src <> '' then obj['source'] = src; end if;
    end if;
    if want['message'] then obj['message'] = rec.message; end if;
    if want['fields'] and rec.fields <> nil then
      for k: v in rec.fields do obj[k] = v; end do;
    end if;
    try
      result = obj.@toJson(json: true);
    except
      var fallback = new [];
      fallback['level'] = rec.levelName;
      fallback['message'] = rec.message;
      try
        result = fallback.@toJson(json: true);
      except
        result = '{}';
      end try;
    end try;
  end fun;
end class;
