// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// io: generic stream helpers. A reader has read(n) -> string; short reads are
// allowed and '' means EOF. A writer has write(s) and must write all of s.
// Helpers never own, close or flush the underlying handle. io.buffer is the
// in-memory implementation; fs.open handles work directly.
//
//     use 'io.fun';
//
//     var b = io.buffer('abc');
//     var all = io.readAll(b);
//     io.copy(out, b);
//     io.writeString(out, 'done');

var _IO_CHUNK = 8192;

class _IoBuffer(s)
  var data = '';
  var pos = 0;
  var t = s.type();
  if t = 0 then
    if s <> nil then raise 'io: buffer text must be a string'; end if;
  elsif t = 8 then
    data = s;
  else
    raise 'io: buffer text must be a string';
  end if;

  fun read(n)
    var t = n.type();
    if t = 0 then raise 'io: read size required'; end if;
    if t <> 3 then raise 'io: read size must be an integer'; end if;
    if n < 0 then raise 'io: read size must be >= 0'; end if;
    if n > 0x7fffffff then raise 'io: read size too large'; end if;
    var left = data.length() - pos;
    if n > left then n = left; end if;
    if n = 0 then result = ''; return; end if;
    result = data.substr(pos, n);
    pos += n;
  end fun;

  fun write(v)
    var t = v.type();
    if t = 0 then
      if v <> nil then raise 'io: write data must be a string'; end if;
    elsif t <> 8 then
      raise 'io: write data must be a string';
    end if;
    var s = v;
    if s = nil then s = ''; end if;
    data &= s;
    result = s.length();
  end fun;

  fun text()
    result = data.substr(pos);
  end fun;

  fun length()
    result = data.length() - pos;
  end fun;

  fun reset()
    data = '';
    pos = 0;
    result = true;
  end fun;
end class;

class _IoApi()
  fun buffer(text)
    result = _IoBuffer(text);
  end fun;

  fun readAll(r)
    var out = new [];
    loop
      var s = r.read(_IO_CHUNK);
      if s = nil or s = '' then exit; end if;
      out.@add(s);
    end loop;
    if out.@count() = 0 then result = ''; return; end if;
    result = out.@toJson(-1);
  end fun;

  fun copy(dst, src)
    var n = 0;
    loop
      var s = src.read(_IO_CHUNK);
      if s = nil or s = '' then exit; end if;
      dst.write(s);
      n += s.length();
    end loop;
    result = n;
  end fun;

  fun writeString(w, s)
    var t = s.type();
    if t = 0 then
      if s <> nil then raise 'io: write data must be a string'; end if;
      s = '';
    elsif t <> 8 then
      raise 'io: write data must be a string';
    end if;
    w.write(s);
    result = s.length();
  end fun;
end class;

var io = _IoApi();
