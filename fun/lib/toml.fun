// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// toml: TOML 1.0 document reader/writer. The reader consumes any object with
// read(n); the writer accepts any object with write(s). Neither owns the
// underlying handle. A document is read as one value and written as one value.
//
//     use 'toml.fun';
//
//     var f = fs.open('config.toml', 'r');
//     var doc = toml.reader(f).read();   // nil after the first read
//     f.close();
//
//     var out = io.buffer();
//     toml.writer(out).write(doc);

var _TOML_CHUNK = 8192;
var _TOML_NL = 10.toChar();
var _TOML_BS = 92.toChar();
var _TOML_DQ = 34.toChar();
var _TOML_SQ = 39.toChar();

// Dates, local times, inf and nan keep their source token. Fun has no date-only
// or NaN value, so a small typed wrapper avoids silently turning them into
// strings.
class TomlLiteral(kind, text)
  var kind = kind;
  var text = text;

  fun tomlKind()
    result = kind;
  end fun;

  fun tomlText()
    result = text;
  end fun;
end class;

fun _tomlLiteralKind(v)
  result = nil;
  try
    result = v.tomlKind();
  except
  end try;
end fun;

fun _tomlIsColl(v)
  if _tomlLiteralKind(v) <> nil then result = false; return; end if;
  result = false;
  try
    result = not v.eq(v);
  except
    result = true;
  end try;
end fun;

// A JSON/FD array starts with '[' and a table/set with '{'. Empty collections
// are ambiguous in Fun; the writer emits empty collections as arrays.
fun _tomlIsList(v)
  if not _tomlIsColl(v) then result = false; return; end if;
  var n = v.@count();
  if n = 0 then result = false; return; end if;
  result = v.@toJson(json: true).substr(0, 1) = '[';
end fun;

fun _tomlIsTableList(v)
  if not _tomlIsList(v) then result = false; return; end if;
  var n = v.@count();
  if n = 0 then result = false; return; end if;
  for i = 0 to n - 1 do
    if not _tomlIsColl(v[i]) or _tomlIsList(v[i]) then result = false; return; end if;
  end do;
  result = true;
end fun;

class _TomlParser(s)
  var text = s;
  var pos = 0;
  var n = s.length();
  var line = 1;
  var col = 1;
  var root = new [];
  var cur = root;
  var defs = new [];
  var arrayGen = new [];

  fun _err(msg)
    raise 'toml: ' & msg & ' at ' & line & ':' & col;
  end fun;

  fun _eof()
    result = pos >= n;
  end fun;

  fun _peek(k)
    if k = nil then k = 0; end if;
    var i = pos + k;
    if i < 0 or i >= n then result = ''; else result = text.substr(i, 1); end if;
  end fun;

  fun _next()
    if pos >= n then result = ''; return; end if;
    var c = text.substr(pos, 1);
    pos += 1;
    if c = _TOML_NL then line += 1; col = 1; else col += 1; end if;
    result = c;
  end fun;

  fun _expect(c, what)
    if _peek() <> c then _err('expected ' & what); end if;
    _next();
  end fun;

  fun _skipSpace()
    while not _eof() do
      var c = _peek();
      if c = ' ' or c = 9.toChar() then _next(); else exit; end if;
    end do;
  end fun;

  fun _skipComment()
    if _peek() = '#' then
      while not _eof() and _peek() <> _TOML_NL do _next(); end do;
    end if;
  end fun;

  fun _skipBlank()
    loop
      _skipSpace();
      if _peek() = '#' then _skipComment(); end if;
      if _peek() = _TOML_NL then _next(); else exit; end if;
    end loop;
  end fun;

  fun _skipValueWs()
    loop
      _skipSpace();
      if _peek() = '#' then _skipComment(); end if;
      if _peek() = _TOML_NL then _next(); else exit; end if;
    end loop;
  end fun;

  fun _consumeEol()
    _skipSpace();
    if _peek() = '#' then _skipComment(); end if;
    if _eof() then return; end if;
    if _peek() <> _TOML_NL then _err('expected newline'); end if;
    _next();
  end fun;

  fun parse()
    _skipBlank();
    while not _eof() do
      if _peek() = '[' then _parseHeader(); else _parseKeyValue(cur); end if;
      _consumeEol();
      _skipBlank();
    end do;
    result = root;
  end fun;

  fun _parseHeader()
    _expect('[', '[');
    var arr = false;
    if _peek() = '[' then _next(); arr = true; end if;
    var keys = _parseKeyPath();
    _skipSpace();
    _expect(']', ']');
    if arr then _expect(']', ']'); end if;
    if arr then _bindArray(keys); else _bindTable(keys); end if;
  end fun;

  fun _parseKeyPath()
    var parts = new [];
    loop
      _skipSpace();
      parts.@add(_parseKey());
      _skipSpace();
      if _peek() = '.' then _next(); else exit; end if;
    end loop;
    result = parts;
  end fun;

  fun _parseKey()
    var c = _peek();
    if c = _TOML_DQ then result = _parseBasicString(true); return; end if;
    if c = _TOML_SQ then result = _parseLiteralString(true); return; end if;
    var out = new [];
    while not _eof() do
      c = _peek();
      var b = c.toByte(0);
      if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or
         (b >= 97 and b <= 122) or b = 95 or b = 45 then
        out.@add(_next());
      else
        exit;
      end if;
    end do;
    if out.@count() = 0 then _err('expected key'); end if;
    result = out.@toJson(-1);
  end fun;

  fun _parseKeyValue(t)
    var keys = _parseKeyPath();
    _skipSpace();
    _expect('=', '=');
    _skipSpace();
    var v = _parseValue();
    _setPath(t, keys, v);
  end fun;

  fun _nav(t, k)
    if not t.@has(k) then t[k] = new []; end if;
    var v = t[k];
    if _tomlIsList(v) then
      if v.@count() = 0 then _err('empty table array'); end if;
      v = v[v.@count() - 1];
    end if;
    if not _tomlIsColl(v) then _err('key conflicts with a value'); end if;
    result = v;
  end fun;

  fun _pathId(keys)
    result = keys.@toJson(json: true);
  end fun;

  fun _tableId(keys)
    var out = new [];
    for i = 0 to keys.@count() - 1 do
      var p = new [];
      for j = 0 to i do p.@add(keys[j]); end do;
      var pid = _pathId(p);
      out.@add(pid);
      var g = arrayGen[pid];
      if g <> nil then out.@add('#' & g); end if;
    end do;
    result = out.@toJson(-1);
  end fun;

  fun _bumpArrayGen(keys)
    var id = _pathId(keys);
    var g = arrayGen[id];
    if g = nil then g = 0; end if;
    arrayGen[id] = g + 1;
  end fun;

  fun _bindTable(keys)
    var id = _tableId(keys);
    if defs[id] <> nil then _err('duplicate table ' & _pathId(keys)); end if;
    defs[id] = true;
    var t = root;
    for i = 0 to keys.@count() - 2 do t = _nav(t, keys[i]); end do;
    var k = keys[keys.@count() - 1];
    if t.@has(k) then
      var v = t[k];
      if _tomlIsList(v) then _err('table conflicts with an array table'); end if;
      if not _tomlIsColl(v) then _err('key conflicts with a value'); end if;
      cur = v;
      return;
    end if;
    cur = new [];
    t[k] = cur;
  end fun;

  fun _bindArray(keys)
    var t = root;
    for i = 0 to keys.@count() - 2 do t = _nav(t, keys[i]); end do;
    var k = keys[keys.@count() - 1];
    if not t.@has(k) then
      var l = new [];
      var e = new [];
      l.@add(e);
      t[k] = l;
      _bumpArrayGen(keys);
      cur = e;
      return;
    end if;
    var v = t[k];
    if not _tomlIsList(v) then _err('table array conflicts with a table'); end if;
    var e = new [];
    v.@add(e);
    _bumpArrayGen(keys);
    cur = e;
  end fun;

  fun _setPath(t, keys, v)
    for i = 0 to keys.@count() - 2 do t = _nav(t, keys[i]); end do;
    var k = keys[keys.@count() - 1];
    if t.@has(k) then _err('duplicate key ' & k); end if;
    t[k] = v;
  end fun;

  fun _parseValue()
    _skipSpace();
    var c = _peek();
    if c = _TOML_DQ then result = _parseBasicString(false); return; end if;
    if c = _TOML_SQ then result = _parseLiteralString(false); return; end if;
    if c = '[' then result = _parseArray(); return; end if;
    if c = '{' then result = _parseInline(); return; end if;
    result = _parseScalar();
  end fun;

  fun _parseArray()
    _expect('[', '[');
    var out = new [];
    _skipValueWs();
    if _peek() = ']' then _next(); result = out; return; end if;
    loop
      out.@add(_parseValue());
      _skipValueWs();
      if _peek() = ',' then
        _next();
        _skipValueWs();
        if _peek() = ']' then _next(); exit; end if;
      elsif _peek() = ']' then
        _next();
        exit;
      else
        _err('expected , or ]');
      end if;
    end loop;
    result = out;
  end fun;

  fun _parseInline()
    _expect('{', '{');
    var t = new [];
    _skipSpace();
    if _peek() = '}' then _next(); result = t; return; end if;
    loop
      _skipSpace();
      if _peek() = _TOML_NL then _err('newline in inline table'); end if;
      var keys = _parseKeyPath();
      _skipSpace();
      _expect('=', '=');
      _skipSpace();
      _setPath(t, keys, _parseValue());
      _skipSpace();
      if _peek() = ',' then
        _next();
      elsif _peek() = '}' then
        _next();
        exit;
      else
        _err('expected , or }');
      end if;
    end loop;
    result = t;
  end fun;

  fun _parseScalar()
    var out = new [];
    while not _eof() do
      var c = _peek();
      if c = ' ' or c = 9.toChar() or c = _TOML_NL or c = ',' or
         c = ']' or c = '}' or c = '#' then
        exit;
      end if;
      out.@add(_next());
    end do;
    var tok = out.@toJson(-1);
    if tok = '' then _err('expected value'); end if;

    if tok = 'true' then result = true; return; end if;
    if tok = 'false' then result = false; return; end if;

    var dk = _dateKind(tok);
    if dk = 'date' and _peek() = ' ' then
      var savePos = pos;
      var saveLine = line;
      var saveCol = col;
      _next();
      var more = new [];
      while not _eof() do
        var c = _peek();
        if c = ' ' or c = 9.toChar() or c = _TOML_NL or c = ',' or
           c = ']' or c = '}' or c = '#' then
          exit;
        end if;
        more.@add(_next());
      end do;
      var rest = more.@toJson(-1);
      if rest <> '' and (rest.substr(2, 1) = ':' or rest.substr(1, 1) = ':') then
        tok &= ' ' & rest;
      else
        pos = savePos; line = saveLine; col = saveCol;
      end if;
      dk = _dateKind(tok);
    end if;
    if dk <> nil then result = TomlLiteral(dk, tok); return; end if;
    if _looksDate(tok) then _err('invalid date/time ' & tok); end if;

    if tok = 'inf' or tok = '+inf' or tok = '-inf' or
       tok = 'nan' or tok = '+nan' or tok = '-nan' then
      result = TomlLiteral('float', tok);
      return;
    end if;

    var body = _signless(tok);
    var isBase = body.substr(0, 2) = '0x' or body.substr(0, 2) = '0X' or
                 body.substr(0, 2) = '0o' or body.substr(0, 2) = '0O' or
                 body.substr(0, 2) = '0b' or body.substr(0, 2) = '0B';
    if isBase then
      var base = 10;
      if body.substr(0, 2) = '0x' or body.substr(0, 2) = '0X' then base = 16;
      elsif body.substr(0, 2) = '0o' or body.substr(0, 2) = '0O' then base = 8;
      else base = 2;
      end if;
      _checkUnderscores(tok, base);
      result = _integer(tok, tok);
      return;
    end if;
    _checkUnderscores(tok, 10);
    var s = tok.replace('_', '');
    var isFloat = false;
    if s.subpos('.') >= 0 or s.subpos('e') >= 0 or s.subpos('E') >= 0 then isFloat = true; end if;
    if isFloat then
      if not (s =~ /^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) then
        _err('invalid float ' & tok);
      end if;
      if not _leadingZeroOk(s) then _err('leading zero in number ' & tok); end if;
      var v = s.toNum();
      if v.type() <> 5 then _err('invalid float ' & tok); end if;
      result = v;
      return;
    end if;
    if not (s =~ /^[+-]?[0-9]+$/) then _err('invalid integer ' & tok); end if;
    if not _leadingZeroOk(s) then _err('leading zero in number ' & tok); end if;
    result = _integer(s, tok);
  end fun;

  fun _signless(s)
    if s.substr(0, 1) = '-' or s.substr(0, 1) = '+' then result = s.substr(1);
    else result = s;
    end if;
  end fun;

  fun _digitBase(c, base)
    var b = c.toByte(0);
    var d = -1;
    if b >= 48 and b <= 57 then d = b - 48;
    elsif b >= 65 and b <= 70 then d = b - 55;
    elsif b >= 97 and b <= 102 then d = b - 87;
    end if;
    result = d >= 0 and d < base;
  end fun;

  fun _checkUnderscores(tok, base)
    for i = 0 to tok.length() - 1 do
      if tok.substr(i, 1) = '_' then
        if i = 0 or i = tok.length() - 1 then _err('misplaced underscore'); end if;
        if not _digitBase(tok.substr(i - 1, 1), base) or
           not _digitBase(tok.substr(i + 1, 1), base) then
          _err('misplaced underscore');
        end if;
      end if;
    end do;
  end fun;

  fun _leadingZeroOk(s)
    var b = _signless(s);
    var cut = b.length();
    var d = b.subpos('.');
    if d >= 0 and d < cut then cut = d; end if;
    var e = b.subpos('e');
    if e >= 0 and e < cut then cut = e; end if;
    e = b.subpos('E');
    if e >= 0 and e < cut then cut = e; end if;
    var ip = b.substr(0, cut);
    result = not (ip.length() > 1 and ip.substr(0, 1) = '0');
  end fun;

  fun _integer(s, tok)
    var sign = 1;
    var body = s.replace('_', '');
    if body.substr(0, 1) = '-' then sign = -1; body = body.substr(1);
    elsif body.substr(0, 1) = '+' then body = body.substr(1);
    end if;
    if body = '' then _err('invalid number ' & tok); end if;
    if body.substr(0, 2) = '0x' or body.substr(0, 2) = '0X' then
      result = sign * _baseNum(body.substr(2), 16, tok); return;
    end if;
    if body.substr(0, 2) = '0o' or body.substr(0, 2) = '0O' then
      result = sign * _baseNum(body.substr(2), 8, tok); return;
    end if;
    if body.substr(0, 2) = '0b' or body.substr(0, 2) = '0B' then
      result = sign * _baseNum(body.substr(2), 2, tok); return;
    end if;
    var v = s.toNum();
    if v.type() <> 3 then _err('invalid integer ' & tok); end if;
    result = v;
  end fun;

  fun _baseNum(body, base, tok)
    if body = '' then _err('invalid number ' & tok); end if;
    var v = 0;
    for i = 0 to body.length() - 1 do
      var c = body.substr(i, 1);
      var b = c.toByte(0);
      var d = -1;
      if b >= 48 and b <= 57 then d = b - 48;
      elsif b >= 65 and b <= 70 then d = b - 55;
      elsif b >= 97 and b <= 102 then d = b - 87;
      end if;
      if d < 0 or d >= base then _err('invalid number ' & tok); end if;
      v = v * base + d;
    end do;
    result = v;
  end fun;

  fun _dateKind(tok)
    var l = tok.length();
    if l >= 10 and tok.substr(4, 1) = '-' and tok.substr(7, 1) = '-' and
       _digits(tok.substr(0, 4)) and _digits(tok.substr(5, 2)) and
       _digits(tok.substr(8, 2)) then
      if not _validDate(tok.substr(0, 4).toNum(), tok.substr(5, 2).toNum(),
                        tok.substr(8, 2).toNum()) then
        result = nil;
        return;
      end if;
      if l = 10 then result = 'date'; return; end if;
      var sep = tok.substr(10, 1);
      if (sep = 'T' or sep = 't' or sep = ' ') and l >= 19 and
         _digits(tok.substr(11, 2)) and tok.substr(13, 1) = ':' and
         _digits(tok.substr(14, 2)) and tok.substr(16, 1) = ':' and
         _digits(tok.substr(17, 2)) then
        if not _validTime(tok.substr(11, 2).toNum(), tok.substr(14, 2).toNum(),
                          tok.substr(17, 2).toNum()) then
          result = nil;
          return;
        end if;
        var p = 19;
        if p < l and tok.substr(p, 1) = '.' then
          p += 1;
          var fs = p;
          while p < l and _isDigit(tok.substr(p, 1)) do p += 1; end do;
          if p = fs then result = nil; return; end if;
        end if;
        if p = l then result = 'local-datetime'; return; end if;
        if p + 1 = l and (tok.substr(p, 1) = 'Z' or tok.substr(p, 1) = 'z') then
          result = 'offset-datetime'; return;
        end if;
        if p + 6 = l and (tok.substr(p, 1) = '+' or tok.substr(p, 1) = '-') and
           _digits(tok.substr(p + 1, 2)) and tok.substr(p + 3, 1) = ':' and
           _digits(tok.substr(p + 4, 2)) then
          if not _validTime(tok.substr(p + 1, 2).toNum(), tok.substr(p + 4, 2).toNum(), 0) then
            result = nil;
            return;
          end if;
          result = 'offset-datetime'; return;
        end if;
        result = nil;
        return;
      end if;
      result = nil;
      return;
    end if;
    if l >= 8 and tok.substr(2, 1) = ':' and tok.substr(5, 1) = ':' and
       _digits(tok.substr(0, 2)) and _digits(tok.substr(3, 2)) and
       _digits(tok.substr(6, 2)) then
      if not _validTime(tok.substr(0, 2).toNum(), tok.substr(3, 2).toNum(),
                        tok.substr(6, 2).toNum()) then
        result = nil;
        return;
      end if;
      var p = 8;
      if p < l and tok.substr(p, 1) = '.' then
        p += 1;
        var fs = p;
        while p < l and _isDigit(tok.substr(p, 1)) do p += 1; end do;
        if p = fs then result = nil; return; end if;
      end if;
      if p = l then result = 'time'; return; end if;
    end if;
    result = nil;
  end fun;

  fun _validDate(y, m, d)
    if y < 1 or y > 9999 or m < 1 or m > 12 or d < 1 then result = false; return; end if;
    var max = 31;
    if m = 2 then
      max = 28;
      if y mod 4 = 0 and (y mod 100 <> 0 or y mod 400 = 0) then max = 29; end if;
    elsif m = 4 or m = 6 or m = 9 or m = 11 then
      max = 30;
    end if;
    result = d <= max;
  end fun;

  fun _validTime(h, m, s)
    result = h >= 0 and h <= 23 and m >= 0 and m <= 59 and s >= 0 and s <= 59;
  end fun;

  fun _looksDate(tok)
    var l = tok.length();
    if l >= 5 and tok.substr(4, 1) = '-' and
       _digits(tok.substr(0, 4)) then
      result = true;
      return;
    end if;
    if l >= 3 and tok.substr(2, 1) = ':' and
       _digits(tok.substr(0, 2)) then
      result = true;
      return;
    end if;
    result = false;
  end fun;

  fun _isDigit(c)
    if c = '' then result = false; else
      var b = c.toByte(0);
      result = b >= 48 and b <= 57;
    end if;
  end fun;

  fun _digits(s)
    if s = '' then result = false; return; end if;
    for i = 0 to s.length() - 1 do
      if not _isDigit(s.substr(i, 1)) then result = false; return; end if;
    end do;
    result = true;
  end fun;

  fun _parseBasicString(keyOnly)
    if _peek() = _TOML_DQ and _peek(1) = _TOML_DQ and _peek(2) = _TOML_DQ then
      if keyOnly then _err('multiline key'); end if;
      _next(); _next(); _next();
      result = _parseMultiBasic();
      return;
    end if;
    _expect('"', '"');
    var out = new [];
    loop
      if _eof() then _err('unterminated string'); end if;
      var c = _peek();
      if c = _TOML_DQ then _next(); exit; end if;
      if c = _TOML_NL then _err('newline in string'); end if;
      if c = _TOML_BS then
        _next();
        out.@add(_parseEscape());
      else
        out.@add(_next());
      end if;
    end loop;
    result = out.@toJson(-1);
  end fun;

  fun _parseLiteralString(keyOnly)
    if _peek() = _TOML_SQ and _peek(1) = _TOML_SQ and _peek(2) = _TOML_SQ then
      if keyOnly then _err('multiline key'); end if;
      _next(); _next(); _next();
      result = _parseMultiLiteral();
      return;
    end if;
    _expect(_TOML_SQ, "'");
    var out = new [];
    loop
      if _eof() then _err('unterminated string'); end if;
      var c = _peek();
      if c = _TOML_SQ then _next(); exit; end if;
      if c = _TOML_NL then _err('newline in string'); end if;
      out.@add(_next());
    end loop;
    result = out.@toJson(-1);
  end fun;

  fun _parseMultiBasic()
    var out = new [];
    if _peek() = _TOML_NL then _next(); end if;
    loop
      if _eof() then _err('unterminated multiline string'); end if;
      if _peek() = _TOML_DQ and _peek(1) = _TOML_DQ and _peek(2) = _TOML_DQ then
        _next(); _next(); _next();
        exit;
      end if;
      var c = _peek();
      if c = _TOML_BS then
        _next();
        var spaced = false;
        while not _eof() and (_peek() = ' ' or _peek() = 9.toChar()) do
          _next();
          spaced = true;
        end do;
        if _peek() = _TOML_NL then
          _next();
          while not _eof() and (_peek() = ' ' or _peek() = 9.toChar() or _peek() = _TOML_NL) do
            _next();
          end do;
        elsif spaced then
          _err('invalid escape');
        else
          out.@add(_parseEscape());
        end if;
      else
        out.@add(_next());
      end if;
    end loop;
    result = out.@toJson(-1);
  end fun;

  fun _parseMultiLiteral()
    var out = new [];
    if _peek() = _TOML_NL then _next(); end if;
    loop
      if _eof() then _err('unterminated multiline string'); end if;
      if _peek() = _TOML_SQ and _peek(1) = _TOML_SQ and _peek(2) = _TOML_SQ then
        _next(); _next(); _next();
        exit;
      end if;
      out.@add(_next());
    end loop;
    result = out.@toJson(-1);
  end fun;

  fun _hexVal(c)
    var s = c.lower();
    result = '0123456789abcdef'.subpos(s);
  end fun;

  fun _parseEscape()
    if _eof() then _err('bad escape'); end if;
    var c = _next();
    if c = 'b' then result = 8.toChar(); return; end if;
    if c = 't' then result = 9.toChar(); return; end if;
    if c = 'n' then result = _TOML_NL; return; end if;
    if c = 'f' then result = 12.toChar(); return; end if;
    if c = 'r' then result = 13.toChar(); return; end if;
    if c = '"' then result = _TOML_DQ; return; end if;
    if c = _TOML_BS then result = _TOML_BS; return; end if;
    if c = 'u' then
      var v = _parseHex(4);
      if v > 65535 then _err('unicode escape too large'); end if;
      result = v.toChar();
      return;
    end if;
    if c = 'U' then
      var v = _parseHex(8);
      if v > 65535 then _err('unicode escape too large'); end if;
      result = v.toChar();
      return;
    end if;
    _err('invalid escape');
  end fun;

  fun _parseHex(n)
    var v = 0;
    for i = 1 to n do
      if _eof() then _err('bad unicode escape'); end if;
      var h = _hexVal(_next());
      if h < 0 then _err('bad unicode escape'); end if;
      v = v * 16 + h;
    end do;
    result = v;
  end fun;
end class;

fun _tomlNormalize(s)
  var t = s;
  if t.length() >= 3 and t.substr(0, 1) = 239.toChar() and
     t.substr(1, 1) = 187.toChar() and t.substr(2, 1) = 191.toChar() then
    t = t.substr(3);
  end if;
  t = t.replace(13.toChar() & _TOML_NL, _TOML_NL);
  t = t.replace(13.toChar(), _TOML_NL);
  result = t;
end fun;

class _TomlReader(src, opts)
  var s = src;
  var done = false;

  fun read()
    if done then result = nil; return; end if;
    done = true;
    var parts = new [];
    loop
      var chunk = s.read(_TOML_CHUNK);
      if chunk = nil or chunk = '' then exit; end if;
      parts.@add(chunk);
    end loop;
    var text = '';
    if parts.@count() > 0 then text = parts.@toJson(-1); end if;
    text = _tomlNormalize(text);
    if text = '' then result = new []; return; end if;
    result = _TomlParser(text).parse();
  end fun;
end class;

fun _tomlOptBool(opts, k, d)
  if opts = nil then result = d; return; end if;
  var v = opts[k];
  if v = nil then result = d; return; end if;
  if v.type() <> 11 then raise 'toml: ' & k & ' must be a boolean'; end if;
  result = v;
end fun;

fun _tomlBare(k)
  if k = '' then result = false; return; end if;
  for i = 0 to k.length() - 1 do
    var b = k.toByte(i);
    if not ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or
            (b >= 97 and b <= 122) or b = 95 or b = 45) then
      result = false;
      return;
    end if;
  end do;
  result = true;
end fun;

fun _tomlHex2(c)
  var h = '0123456789abcdef';
  result = _TOML_BS & 'u00' & h.substr((c >> 4) bit and 15, 1) & h.substr(c bit and 15, 1);
end fun;

fun _tomlQuote(s)
  var out = new [];
  out.@add(_TOML_DQ);
  for i = 0 to s.length() - 1 do
    var c = s.toByte(i);
    if c = 34 then out.@add(_TOML_BS & _TOML_DQ);
    elsif c = 92 then out.@add(_TOML_BS & _TOML_BS);
    elsif c = 8 then out.@add(_TOML_BS & 'b');
    elsif c = 9 then out.@add(_TOML_BS & 't');
    elsif c = 10 then out.@add(_TOML_BS & 'n');
    elsif c = 12 then out.@add(_TOML_BS & 'f');
    elsif c = 13 then out.@add(_TOML_BS & 'r');
    elsif c < 32 or c = 127 then out.@add(_tomlHex2(c));
    else out.@add(s.substr(i, 1));
    end if;
  end do;
  out.@add(_TOML_DQ);
  result = out.@toJson(-1);
end fun;

fun _tomlKey(k)
  if _tomlBare(k) then result = k; else result = _tomlQuote(k); end if;
end fun;

fun _tomlPath(path)
  var out = new [];
  for i = 0 to path.@count() - 1 do
    out.@add(_tomlKey(path[i]));
    if i < path.@count() - 1 then out.@add('.'); end if;
  end do;
  result = out.@toJson(-1);
end fun;

fun _tomlScalar(v)
  var t = v.type();
  if t = 8 then result = _tomlQuote(v); return; end if;
  if t = 3 then result = '' & v; return; end if;
  if t = 5 then
    var s = '' & v;
    if s = '+Inf' then result = 'inf'; return; end if;
    if s = '-Inf' then result = '-inf'; return; end if;
    if s = 'NaN' or s = '+NaN' or s = '-NaN' then result = 'nan'; return; end if;
    if s.subpos('.') < 0 and s.subpos('e') < 0 and s.subpos('E') < 0 then s &= '.0'; end if;
    result = s;
    return;
  end if;
  if t = 11 then
    if v then result = 'true'; else result = 'false'; end if;
    return;
  end if;
  raise 'toml: value is not a scalar';
end fun;

fun _tomlValue(v)
  var lit = _tomlLiteralKind(v);
  if lit <> nil then result = v.tomlText(); return; end if;
  if _tomlIsColl(v) then
    if v.@count() = 0 then result = '[]'; return; end if;
    if _tomlIsList(v) then
      var out = new [];
      out.@add('[');
      for i = 0 to v.@count() - 1 do
        if i > 0 then out.@add(', '); end if;
        out.@add(_tomlValue(v[i]));
      end do;
      out.@add(']');
      result = out.@toJson(-1);
      return;
    end if;
    result = _tomlInline(v);
    return;
  end if;
  result = _tomlScalar(v);
end fun;

fun _tomlInline(v)
  var keys = new [];
  v.@each((x, k){ keys.@add(k); });
  var out = new [];
  out.@add('{ ');
  for i = 0 to keys.@count() - 1 do
    if i > 0 then out.@add(', '); end if;
    out.@add(_tomlKey(keys[i]) & ' = ' & _tomlValue(v[keys[i]]));
  end do;
  out.@add(' }');
  result = out.@toJson(-1);
end fun;

class _TomlWriter(dst, opts)
  var w = dst;
  var nl = _TOML_NL;
  var done = false;
  var lines = new [];

  if _tomlOptBool(opts, 'crlf', false) then nl = 13.toChar() & _TOML_NL; end if;

  fun _line(s)
    lines.@add(s & nl);
  end fun;

  fun _blank()
    if lines.@count() > 0 then lines.@add(nl); end if;
  end fun;

  fun _writeTable(t, path, root)
    var keys = new [];
    t.@each((x, k){ keys.@add(k); });
    for i = 0 to keys.@count() - 1 do
      var k = keys[i];
      var v = t[k];
      if _tomlIsColl(v) and v.@count() = 0 then
        _line(_tomlKey(k) & ' = []');
      elsif _tomlIsColl(v) then
        if _tomlIsList(v) then
          if not _tomlIsTableList(v) then
            _line(_tomlKey(k) & ' = ' & _tomlValue(v));
          end if;
        end if;
      else
        _line(_tomlKey(k) & ' = ' & _tomlValue(v));
      end if;
    end do;
    for i = 0 to keys.@count() - 1 do
      var k = keys[i];
      var v = t[k];
      if _tomlIsColl(v) and v.@count() > 0 then
        if _tomlIsList(v) and _tomlIsTableList(v) then
          for j = 0 to v.@count() - 1 do
            _blank();
            var p = new [];
            for x = 0 to path.@count() - 1 do p.@add(path[x]); end do;
            p.@add(k);
            _line('[[' & _tomlPath(p) & ']]');
            _writeTable(v[j], p, false);
          end do;
        elsif not _tomlIsList(v) then
          _blank();
          var p = new [];
          for x = 0 to path.@count() - 1 do p.@add(path[x]); end do;
          p.@add(k);
          _line('[' & _tomlPath(p) & ']');
          _writeTable(v, p, false);
        end if;
      end if;
    end do;
  end fun;

  fun write(doc)
    if done then raise 'toml: writer already used'; end if;
    done = true;
    if not _tomlIsColl(doc) or _tomlIsList(doc) then raise 'toml: document must be a table'; end if;
    _writeTable(doc, new [], true);
    var out = '';
    if lines.@count() > 0 then out = lines.@toJson(-1); end if;
    w.write(out);
    result = true;
  end fun;
end class;

class _TomlApi()
  fun reader(r, opts)
    result = _TomlReader(r, opts);
  end fun;

  fun writer(w, opts)
    result = _TomlWriter(w, opts);
  end fun;
end class;

var toml = _TomlApi();
