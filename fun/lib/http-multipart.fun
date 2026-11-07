// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// http-multipart: parse multipart/form-data bodies (RFC 7578 / RFC 2046).
//
//     var m = HttpMultipartParse(req.body, req.header('content-type'));
//     if not m.ok then raise m.error; end if;
//     var name = m.fields['name'][0];
//     var file = m.files['avatar'][0];
//
// The body must already be in memory. Fields are strings; files are part
// objects with filename/contentType/headers/data. Duplicate names stay as
// arrays. Invalid input returns ok:false/error; it does not raise.

var _MP_CRLF = 13.toChar() & 10.toChar();
var _MP_CRLF2 = _MP_CRLF & _MP_CRLF;

fun _mpFindDelim(s, delim, from, allowStart)
  var d = delim.length();
  var p = from;
  while p <= s.length() do
    var i = -1;
    if allowStart and p = from and s.length() >= p + d and s.substr(p, d) = delim then
      i = p;
    elsif p + _MP_CRLF.length() <= s.length() then
      var j = s.substr(p).subpos(_MP_CRLF & delim);
      if j >= 0 then i = p + j + _MP_CRLF.length(); end if;
    end if;
    if i < 0 then result = -1; return; end if;
    var q = _mpSkipHws(s, i + d);
    var m = '';
    if q + 2 <= s.length() then m = s.substr(q, 2); end if;
    var ok = m = _MP_CRLF;
    if m = '--' then
      var tail = _mpSkipHws(s, q + 2);
      ok = tail >= s.length() or (tail + 2 <= s.length() and s.substr(tail, 2) = _MP_CRLF);
    end if;
    if ok then result = i; return; end if;
    p = i + 1;
  end do;
  result = -1;
end fun;

fun _mpWs(c)
  result = c = ' ' or c = 9.toChar() or c = 13.toChar() or c = 10.toChar();
end fun;

fun _mpTrim(s)
  var n = s.length();
  var b = 0;
  while b < n and _mpWs(s[b]) do b += 1; end do;
  var e = n;
  while e > b and _mpWs(s[e - 1]) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

fun _mpHws(c)
  result = c = ' ' or c = 9.toChar();
end fun;

fun _mpSkipHws(s, pos)
  var p = pos;
  while p < s.length() and _mpHws(s[p]) do p += 1; end do;
  result = p;
end fun;

fun _mpFail(msg)
  result = new [ok: false, error: 'http-multipart: ' & msg, parts: new [], fields: new [], files: new []];
end fun;

fun _mpUnquote(s)
  var t = _mpTrim(s);
  var n = t.length();
  if n < 2 then result = t; return; end if;
  if t[0] <> 34.toChar() or t[n - 1] <> 34.toChar() then result = t; return; end if;
  var out = '';
  var i = 1;
  while i < n - 1 do
    var c = t[i];
    if c = 92.toChar() and i + 1 < n - 1 then
      i += 1;
      out &= t[i];
    else
      out &= c;
    end if;
    i += 1;
  end do;
  result = out;
end fun;

fun _mpSplitParams(s)
  var out = new [];
  var cur = '';
  var q = false;
  var esc = false;
  var i = 0;
  while i < s.length() do
    var c = s[i];
    if esc then
      cur &= c;
      esc = false;
    elsif c = 92.toChar() then
      cur &= c;
      esc = true;
    elsif c = 34.toChar() then
      q = not q;
      cur &= c;
    elsif c = ';' and not q then
      out.@add(cur);
      cur = '';
    else
      cur &= c;
    end if;
    i += 1;
  end do;
  out.@add(cur);
  result = out;
end fun;

fun _mpParams(s)
  var out = new [];
  var segs = _mpSplitParams(s);
  var i = 0;
  while i < segs.@count() do
    var seg = _mpTrim(segs[i]);
    if seg <> '' then
      var eq = seg.subpos('=');
      if eq >= 0 then
        var k = _mpTrim(seg.substr(0, eq)).lower();
        var v = _mpUnquote(seg.substr(eq + 1));
        if k <> '' then out[k] = v; end if;
      end if;
    end if;
    i += 1;
  end do;
  result = out;
end fun;

fun _mpContentType(ct)
  if ct = nil then result = new [ok: false, error: 'Content-Type is required']; return; end if;
  if ct.type() <> 8 then result = new [ok: false, error: 'Content-Type must be a string']; return; end if;
  var semi = ct.subpos(';');
  var mt = ct;
  var rest = '';
  if semi >= 0 then
    mt = ct.substr(0, semi);
    rest = ct.substr(semi + 1);
  end if;
  if _mpTrim(mt).lower() <> 'multipart/form-data' then
    result = new [ok: false, error: 'expected multipart/form-data'];
    return;
  end if;
  var ps = _mpParams(rest);
  var b = ps['boundary'];
  if b = nil or b = '' then result = new [ok: false, error: 'missing boundary']; return; end if;
  if b.subpos(13.toChar()) >= 0 or b.subpos(10.toChar()) >= 0 then result = new [ok: false, error: 'invalid boundary']; return; end if;
  result = new [ok: true, boundary: b];
end fun;

fun _mpHeaders(text)
  var rows = new [];
  var pos = 0;
  while pos < text.length() do
    var e = text.substr(pos).subpos(_MP_CRLF);
    var line = '';
    if e >= 0 then
      line = text.substr(pos, e);
      pos += e + _MP_CRLF.length();
    else
      line = text.substr(pos);
      pos = text.length();
    end if;
    if line <> '' then
      if line[0] = ' ' or line[0] = 9.toChar() then
        if rows.@count() = 0 then result = new [ok: false, error: 'folded header without a header']; return; end if;
        var last = rows[rows.@count() - 1];
        last[1] &= ' ' & _mpTrim(line);
      else
        var c = line.subpos(':');
        if c < 0 then result = new [ok: false, error: 'invalid header line']; return; end if;
        var k = _mpTrim(line.substr(0, c)).lower();
        if k = '' then result = new [ok: false, error: 'empty header name']; return; end if;
        var row = new [];
        row.@add(k);
        row.@add(_mpTrim(line.substr(c + 1)));
        rows.@add(row);
      end if;
    end if;
  end do;
  var hdrs = new [];
  var i = 0;
  while i < rows.@count() do
    var row = rows[i];
    hdrs[row[0]] = row[1];
    i += 1;
  end do;
  result = new [ok: true, headers: hdrs];
end fun;

fun _mpDisposition(cd)
  var semi = cd.subpos(';');
  var typ = cd;
  var rest = '';
  if semi >= 0 then
    typ = cd.substr(0, semi);
    rest = cd.substr(semi + 1);
  end if;
  if _mpTrim(typ).lower() <> 'form-data' then result = new [ok: false, error: 'Content-Disposition must be form-data']; return; end if;
  var ps = _mpParams(rest);
  var name = ps['name'];
  if name = nil then result = new [ok: false, error: 'missing form-data name']; return; end if;
  // '' equals nil in Fun, so key presence tells a field from an empty filename.
  result = new [ok: true, name: name, filename: ps['filename'], isFile: ps.@has('filename')];
end fun;

fun _mpAddField(fields, name, data)
  if not fields.@has(name) then fields[name] = new []; end if;
  fields[name].@add(data);
end fun;

fun _mpAddFile(files, name, part)
  if not files.@has(name) then files[name] = new []; end if;
  files[name].@add(part);
end fun;

fun HttpMultipartParse(body, ct, opts)
  if body = nil then body = ''; end if;
  if body.type() <> 8 then return _mpFail('body must be a string'); end if;
  var c = _mpContentType(ct);
  if not c['ok'] then return _mpFail(c['error']); end if;
  var delim = '--' & c['boundary'];
  var pos = _mpFindDelim(body, delim, 0, true);
  if pos < 0 then return _mpFail('boundary not found'); end if;

  var parts = new [];
  var fields = new [];
  var files = new [];
  var done = false;
  while not done do
    var q = _mpSkipHws(body, pos + delim.length());
    var mark = '';
    if q + 2 <= body.length() then mark = body.substr(q, 2); end if;
    if mark = '--' then
      done = true;
    else
      if mark <> _MP_CRLF then return _mpFail('invalid boundary line'); end if;
      var hs = q + _MP_CRLF.length();
      if hs > body.length() then return _mpFail('missing part headers'); end if;
      var sep = body.substr(hs).subpos(_MP_CRLF2);
      if sep < 0 then return _mpFail('missing part header terminator'); end if;
      var headersText = body.substr(hs, sep);
      var dataStart = hs + sep + _MP_CRLF2.length();
      var nextPos = _mpFindDelim(body, delim, dataStart, true);
      if nextPos < 0 then return _mpFail('missing closing boundary'); end if;
      var data = '';
      if nextPos > dataStart then data = body.substr(dataStart, nextPos - _MP_CRLF.length() - dataStart); end if;
      var h = _mpHeaders(headersText);
      if not h['ok'] then return _mpFail(h['error']); end if;
      var hdrs = h['headers'];
      var cd = hdrs['content-disposition'];
      if cd = nil then return _mpFail('missing Content-Disposition'); end if;
      var d = _mpDisposition(cd);
      if not d['ok'] then return _mpFail(d['error']); end if;
      var pct = hdrs['content-type'];
      if pct = nil or pct = '' then pct = 'text/plain'; end if;
      var part = new [name: d['name'], filename: d['filename'], contentType: pct, headers: hdrs, data: data];
      parts.@add(part);
      if d['isFile'] then
        _mpAddFile(files, d['name'], part);
      else
        _mpAddField(fields, d['name'], data);
      end if;
      pos = nextPos;
    end if;
  end do;
  result = new [ok: true, error: nil, parts: parts, fields: fields, files: files];
end fun;
