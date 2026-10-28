// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// csv: streaming CSV reader and writer. The reader consumes any object with
// read(n); the writer accepts any object with write(s). Neither owns the
// underlying handle. Blank lines are records by default; skipEmptyLines
// ignores completely empty lines. Field counts are strict.
//
//     use 'csv.fun';
//
//     var f = fs.open('users.csv', 'r');
//     var r = csv.reader(f);
//     var row = r.read();          // nil at EOF
//     while row <> nil do ... row = r.read(); end do;
//     f.close();
//
//     var g = fs.open('out.csv', 'w');
//     var w = csv.writer(g);
//     w.write(['name', 'age']);
//     g.close();

var _CSV_CHUNK = 8192;

fun _csvOpt(opts, k)
  if opts = nil then result = nil; return; end if;
  result = opts[k];
end fun;

fun _csvCharOpt(opts, k, d)
  var v = _csvOpt(opts, k);
  var t = v.type();
  if t = 0 then
    if v = nil then result = d.toByte(0); return; end if;
    raise 'csv: ' & k & ' must be one character';
  end if;
  if t <> 8 or v.length() <> 1 then
    raise 'csv: ' & k & ' must be one character';
  end if;
  var b = v.toByte(0);
  if b = 0 or b > 127 then
    raise 'csv: ' & k & ' must be a single-byte ASCII character';
  end if;
  result = b;
end fun;

fun _csvBoolOpt(opts, k, d)
  var v = _csvOpt(opts, k);
  var t = v.type();
  if t = 0 then
    if v = nil then result = d; return; end if;
    raise 'csv: ' & k & ' must be a boolean';
  end if;
  if t <> 11 then raise 'csv: ' & k & ' must be a boolean'; end if;
  result = v;
end fun;

fun _csvReadOpts(opts)
  var d = _csvCharOpt(opts, 'delimiter', ',');
  var q = _csvCharOpt(opts, 'quote', '"');
  if d = q then raise 'csv: delimiter and quote must differ'; end if;
  if d = 10 or d = 13 then raise 'csv: invalid delimiter'; end if;
  if q = 10 or q = 13 then raise 'csv: invalid quote'; end if;
  var skip = _csvBoolOpt(opts, 'skipEmptyLines', false);
  result = new [];
  result.@add(d);
  result.@add(q);
  result.@add(skip);
end fun;

fun _csvWriteOpts(opts)
  var d = _csvCharOpt(opts, 'delimiter', ',');
  var q = _csvCharOpt(opts, 'quote', '"');
  if d = q then raise 'csv: delimiter and quote must differ'; end if;
  if d = 10 or d = 13 then raise 'csv: invalid delimiter'; end if;
  if q = 10 or q = 13 then raise 'csv: invalid quote'; end if;
  var crlf = _csvBoolOpt(opts, 'crlf', false);
  var eol = 10.toChar();
  if crlf then eol = 13.toChar() & 10.toChar(); end if;
  result = new [];
  result.@add(d);
  result.@add(q);
  result.@add(eol);
end fun;

fun _csvFieldText(v)
  var t = v.type();
  if t = 8 then result = v; return; end if;
  if t = 3 or t = 5 or t = 11 then result = '' & v; return; end if;
  if t = 0 and v = nil then result = ''; return; end if;
  raise 'csv: field must be a scalar';
end fun;

fun _csvNeedsQuote(s, delim, quote)
  if s = '' then result = false; return; end if;
  if s.toByte(0) = 32 or s.toByte(s.length() - 1) = 32 then
    result = true;
    return;
  end if;
  for i = 0 to s.length() - 1 do
    var c = s.toByte(i);
    if c = delim or c = quote or c = 10 or c = 13 then
      result = true;
      return;
    end if;
  end do;
  result = false;
end fun;

fun _csvQuoteField(s, quote)
  var q = quote.toChar();
  var out = new [];
  var start = 0;
  for i = 0 to s.length() - 1 do
    if s.toByte(i) = quote then
      if i > start then out.@add(s.substr(start, i - start)); end if;
      out.@add(q & q);
      start = i + 1;
    end if;
  end do;
  if start < s.length() then out.@add(s.substr(start)); end if;
  result = q & out.@toJson(-1) & q;
end fun;

class _CsvReader(f, opts)
  var src = f;
  var o = _csvReadOpts(opts);
  var delim = o[0];
  var quote = o[1];
  var skipEmpty = o[2];
  var buf = '';
  var bp = 0;
  var blen = 0;
  var atEnd = false;
  var line = 1;
  var recLine = 1;
  var fields = new [];
  var parts = new [];
  var st = 0;          // 0 field start, 1 unquoted, 2 quoted, 3 after quote
  var touched = false;
  var expected = 0;
  var bomChecked = false;

  fun _fill()
    if atEnd then result = false; return; end if;
    var s = src.read(_CSV_CHUNK);
    if s = nil or s = '' then atEnd = true; result = false; return; end if;
    buf = s;
    bp = 0;
    blen = s.length();
    result = true;
  end fun;

  fun _peek()
    if bp >= blen and not atEnd and not this._fill() then
      result = -1;
      return;
    end if;
    if bp < blen then result = buf.toByte(bp); else result = -1; end if;
  end fun;

  fun _next()
    var c = this._peek();
    if c >= 0 then bp += 1; end if;
    result = c;
  end fun;

  fun _ensure(n)
    while blen - bp < n and not atEnd do
      var s = src.read(_CSV_CHUNK);
      if s = nil or s = '' then
        atEnd = true;
      else
        buf = buf.substr(bp) & s;
        blen = buf.length();
        bp = 0;
      end if;
    end do;
  end fun;

  fun _peekAt(k)
    this._ensure(k + 1);
    if bp + k < blen then result = buf.toByte(bp + k); else result = -1; end if;
  end fun;

  fun _skipBom()
    bomChecked = true;
    if this._peekAt(0) = 239 and this._peekAt(1) = 187 and this._peekAt(2) = 191 then
      bp += 3;
    end if;
  end fun;

  fun _resetRecord()
    fields = new [];
    parts = new [];
    st = 0;
    touched = false;
    recLine = line;
  end fun;

  fun _endField()
    fields.@add(parts.@toJson(-1));
    parts = new [];
    st = 0;
  end fun;

  fun _finishRecord()
    if not touched and fields.@count() = 0 and parts.@count() = 0 then
      if skipEmpty then result = nil; return; end if;
      fields.@add('');
    else
      this._endField();
    end if;
    var row = fields;
    if expected = 0 then
      expected = row.@count();
    elsif row.@count() <> expected then
      raise 'csv: line ' & recLine & ': expected ' & expected & ' fields, got ' & row.@count();
    end if;
    result = row;
  end fun;

  fun _lineEnd()
    var row = this._finishRecord();
    line += 1;
    result = row;
  end fun;

  fun read()
    if not bomChecked then this._skipBom(); end if;
    this._resetRecord();
    loop
      var c = this._peek();
      if c < 0 then
        if st = 2 then raise 'csv: line ' & line & ': unterminated quoted field'; end if;
        if not touched and fields.@count() = 0 and parts.@count() = 0 then
          result = nil;
          return;
        end if;
        var last = this._finishRecord();
        this._resetRecord();
        result = last;
        return;
      end if;
      if st = 2 then
        var start = bp;
        var scanning = true;
        while bp < blen and scanning do
          var ch = buf.toByte(bp);
          if ch = quote or ch = 10 then
            scanning = false;
          else
            bp += 1;
          end if;
        end do;
        if bp > start then
          parts.@add(buf.substr(start, bp - start));
          touched = true;
        end if;
        if bp < blen then
          c = buf.toByte(bp);
          bp += 1;
          touched = true;
          if c = quote then
            if this._peek() = quote then
              this._next();
              parts.@add(quote.toChar());
            else
              st = 3;
            end if;
          else
            parts.@add(10.toChar());
            line += 1;
          end if;
        end if;
      elsif st = 3 then
        c = this._next();
        if c = delim then
          this._endField();
        elsif c = 10 then
          var row = this._lineEnd();
          if row <> nil then result = row; this._resetRecord(); return; end if;
          this._resetRecord();
        elsif c = 13 then
          if this._peek() = 10 then
            this._next();
            var row = this._lineEnd();
            if row <> nil then result = row; this._resetRecord(); return; end if;
            this._resetRecord();
          else
            raise 'csv: line ' & line & ': bare CR';
          end if;
        else
          raise 'csv: line ' & line & ': unexpected character after closing quote';
        end if;
      else
        var start = bp;
        var scanning = true;
        while bp < blen and scanning do
          var ch = buf.toByte(bp);
          if ch = delim or ch = quote or ch = 10 or ch = 13 then
            scanning = false;
          else
            bp += 1;
          end if;
        end do;
        if bp > start then
          parts.@add(buf.substr(start, bp - start));
          touched = true;
          st = 1;
        end if;
        if bp < blen then
          c = buf.toByte(bp);
          bp += 1;
          if c = delim then
            touched = true;
            this._endField();
          elsif c = 10 then
            var row = this._lineEnd();
            if row <> nil then result = row; this._resetRecord(); return; end if;
            this._resetRecord();
          elsif c = 13 then
            if this._peek() = 10 then
              this._next();
              var row = this._lineEnd();
              if row <> nil then result = row; this._resetRecord(); return; end if;
              this._resetRecord();
            else
              raise 'csv: line ' & line & ': bare CR';
            end if;
          elsif c = quote then
            touched = true;
            if st = 0 then st = 2; else raise 'csv: line ' & line & ': bare quote'; end if;
          end if;
        end if;
      end if;
    end loop;
  end fun;
end class;

class _CsvWriter(w, opts)
  var dst = w;
  var o = _csvWriteOpts(opts);
  var delim = o[0];
  var quote = o[1];
  var eol = o[2];

  fun write(row)
    var n;
    var ok = false;
    try
      n = row.@count();
      ok = true;
    except
      ok = false;
    end try;
    if not ok then raise 'csv: row must be a list'; end if;
    var out = new [];
    for i = 0 to n - 1 do
      if i > 0 then out.@add(delim.toChar()); end if;
      var s = _csvFieldText(row[i]);
      if _csvNeedsQuote(s, delim, quote) then
        out.@add(_csvQuoteField(s, quote));
      else
        out.@add(s);
      end if;
    end do;
    dst.write(out.@toJson(-1) & eol);
    result = true;
  end fun;
end class;

class _CsvApi()
  fun reader(f, opts)
    result = _CsvReader(f, opts);
  end fun;

  fun writer(w, opts)
    result = _CsvWriter(w, opts);
  end fun;
end class;

var csv = _CsvApi();
