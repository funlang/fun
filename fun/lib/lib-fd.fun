// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-bnf.fun';
use ':fd.bnf.fd' as rules;
rules = rules.getJson(fd: true); //?. rules.@toJson(fd: true);

fun kvdChar(s)
  var m = s.match(/^[\t\x20]*#!kvd:(.)/m);
  if m = nil then result = ''; else result = m.@(1); end if;
end fun;

fun parse(s)
  var ch = kvdChar(s);
  var cb = cbcb;
  var tab = 9.toChar();
  if ch <> '' and ch <> ' ' and ch <> tab then
    var r = rules.@clone();
    var e = ch;
    var sl = 92.toChar();
    if ch = sl or ch = ']' or ch = '^' or ch = '-' then e = sl & ch; end if;
    r['Unqkey'] = '[^' & sl & 's' & e & ']++';
    r['Ws'] = '[' & sl & 't' & sl & 'x20' & e & ']++';
    cb = CBNF(r, dup: 0);
  end if;
  root = new [];
  stak = Stack();
  stak.push([ind: -1, node: root]);
  result = cb.parse(s, actions);
end fun;

var root;
var stak;
var cbcb = CBNF(rules, dup: 0); //?. cb.regex.replace(/\x20/g, '');
fun fdNum(s)
  # Same number policy as the Pascal and JS readers: integers outside the
  # cross-language safe range, and floats that overflow a double, stay strings.
  var isInt = not (s =~ /[.eE]/);
  try
    var n = s.toNum();
    if isInt then
      if n <= 9007199254740991 and n >= -9007199254740991 then
        result = n;
      else
        result = s;
      end if;
    else
      result = n;
    end if;
  except
    result = s;
  end try;
end fun;
var actions = [
      Comment: (o,r) {
        var rt = getRet(r);
        rt.comment = o.t;
      },
      Key: (o,r) {
        var rt = getRet(r);
        rt.key = o.val or o.t;
        rt.ind = rt.ind or 0;
        while stak.peek().ind >= rt.ind do
         stak.pop();
        end do;
        var pp = stak.peek().node;
        if rt.key = '-' then
          var nd = new [];
          pp.@add(nd);
          rt.node = nd;
        else
          var nd = new [];
          pp[rt.key] = nd;
          rt.node = nd;
        end if;
        stak.push(rt);
        r.done = root;
      },
      Val: (o,r,p) {
        if p?.n? <> 'Unqkey' then
          var rt = getRet(r);
          rt.val = o.val;
          stak.pop();
          if rt.key = '-' then
            stak.peek().node[-1] = rt.val;
          else
            stak.peek().node[rt.key] = rt.val;
          end if;
        end if;
      },
      Ind: (o,r) {
        if o.@ then
          o.val = o.t.replace(/\t/g, '  ').length() div 2;
          o.@ = nil;
        end if;
        var rt = getRet(r);
        rt.ind = o.val;
      },
      Indx: (o,p) {
        if o.t =~ /^\d++/ then
          p.val = o.t.match(/^\d++/).@@() * 1;
        else
          p.val = o.t.length();
        end if;
        p.@ = nil;
      },
      Length: (o,m,p) {
        p.val = m.@(o.t.toNum(), 2);
        p.@ = nil;
      },
      Qstring: (o,p) {
        p.val = unq(o.t);
        p.@ = nil;
      },
      Number: (o,p) {
        p.val = fdNum(o.t);
        p.@ = nil;
      },
      Const: (o,p) {
        p.val = [
                  'true' : true,
                  'false': false,
                  'null' : null,
                  '[]'   : [],
                  '{}'   : '{}'.getJson(),
                ][o.t];
        p.@ = nil;
      },
      Unqkey: (p) {p.val = p.t; p.@ = nil},
      Unqstr: (p) {p.val = p.t; p.@ = nil},
    ];

fun getRet(r)     # *
  r.ret = r.ret or new [];
  result = r.ret; # result = [];
end fun;

fun unq(s)
  var esc = false;
  if s =~ /^\\/ then
    esc = true;
    s = s.substr(1);
  end if;
  var c = s.substr(0, 1);
  s = s.substr(1, -2).replace(c.x(2), c);
  if esc then
    s = s.escape();
  end if;
  result = s;
end fun;
