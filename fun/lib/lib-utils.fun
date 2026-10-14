// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

fun isUnicode()
  result = 0x1234.toChar().toByte() > 0xff;
end fun;

fun charSize()
  if isUnicode() then
    result = 2;
  else
    result = 1;
  end if;
end fun;

fun goBytes(buf, size, f)
  var i = 0.1;
  for j = 0 to size-1 loop
    exit when f(buf, i, j);
    i += 1 / charSize();
  end loop;
end fun;

fun fixHalfHanz(s)
  result = s;
  if result.match(/[\x80-\xff]++$/).@@().length() mod 2 = 1 then
    result = result.substr(len: -1);
  end if;
end fun;

var Hexs = [0,1,2,3,4,5,6,7,8,9,'a','b','c','d','e','f'];
fun str2hex(s)
  if isUnicode() then
    result = ' '.x(s.length() * 4);
    var p = result.toNum(-1);
    for i = 0 to s.length() -1 do
      var b = s.toByte(i);
      (Hexs[b >> 4 bit and 0x0f] & Hexs[b      bit and 0x0f] &
       Hexs[b >> 12]             & Hexs[b >> 8 bit and 0x0f]).move(p + i * 8);
    end do;
  else
    result = ' '.x(s.length() * 2);
    var p = result.toNum(-1);
    for i = 0 to s.length() - 1 do
      var b = s.toByte(i);
      (Hexs[b >> 4] & Hexs[b bit and 0x0f]).move(p + i * 2);
    end do;
  end if;
end fun;

fun hex2str(s)
  result = '';
  if isUnicode() then
    if s.length() mod 4 <> 0 then
      s &= '00';
    end if;
    for i = 0 to s.length() -1 step 4 do
      result &= ('x' & s.substr(i+2, 2) & s.substr(i, 2)).toChar();
    end do;
  else
    for i = 0 to s.length() - 1 step 2 do
      result &= ('x' & s.substr(i, 2)).toChar();
    end do;
  end if;
end fun;

fun byte2hex(byte)
  var b = byte mod 256;
  result = Hexs[b >> 4] & Hexs[b bit and 0x0f];
end fun;

fun num2hex(num)
  result = '';
  for i = 3 to 0 step -1 do
    var b = (num >> i*8) mod 256;
    result &= Hexs[b >> 4] & Hexs[b bit and 0x0f];
  end do;
end fun;

fun int2hex(int)
  result = '';
  for i = 0 to 3 do
    var b = (int >> i*8) mod 256;
    result &= Hexs[b >> 4] & Hexs[b bit and 0x0f];
  end do;
  result = result.upper();
end fun;

fun toSigned(v, size, sign)
  if sign and v >> (size*8-1) bit and 1 then
    v -= 256 ^ size;
  end if;
  result = v;
end fun;

fun str2int(str, start, sign, packed)
  if packed and isUnicode() then
    start = start / (packed = true and 1 or 2);
    result = str.toByte(1+start) << 16 +
             str.toByte(  start);
  else
    result = str.toByte(3+start) << 24 +
             str.toByte(2+start) << 16 +
             str.toByte(1+start) << 8  +
             str.toByte(  start);
  end if;
  if sign and result bit and 0x80000000 then
    result = (bit not result + 1) * -1;
  end if;
end fun;

fun int2str(int, packed)
  if packed and isUnicode() then
    result  = (int bit and 0xffff).toChar() & (int >> 16).toChar();
  else
    result = '';
    for i = 0 to 3*8 step 8 do
      var b = int >> i;
      result &= (b mod 256).toChar();
    end do;
  end if;
end fun;

fun ip2int(ip)
  if ip.subpos('.') > 0 then
    var m = ip.match(/(\d++)\.(\d++)\.(\d++)\.(\d++)/);
    return m.@(4).toNum() << 24 + m.@(3).toNum() << 16 + m.@(2).toNum() << 8 + m.@(1).toNum();
  else
    return ip.toNum();
  end if;
end fun;

fun int2ip(int)
  result = int mod 256;
  for i = 1 to 3 do
    int = int div 256;
    result &= '.' & int mod 256;
  end do;
end fun;

fun json2tab(rs)
  var ret = '';

  var fs = new [];
  for r in rs do
    for k: v in r do
      if fs[k] = nil then
        fs[k] = new [];
        fs[k].size = k.length();
      end if;
      var f = fs[k];
      f.size = f.size < v.length() and v.length() or f.size;
      f.str = f.str or not v.match(/^(-?\d++(\.\d++)?)?$/) and true or false;
    end do;
  end do;
  for k: f in fs do
    f.size = f.str and f.size * -1 or f.size;
    ret &= ('%' & f.size & 's ').format(k);
  end do;
  ret &= '\n'.escape();

  for r in rs do
    for k: v in r do
      ret &= ('%' & fs[k].size & 's ').format(v);
    end do;
    ret &= '\n'.escape();
  end do;

  return ret;
end fun;
