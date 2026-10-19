// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// make-asm-list: rebuild the derived assembler-table files from the editable
// asm-list.fd.
//
// lib-asm-pro embeds ':asm-list.fd2.gz' at parse time; at run time it
// inflates the blob (raw deflate) and feeds SseDecompress + getJson(fd: true,
// sse: true) (core: lib/libase.pas). The on-disk chain is:
//
//   asm-list.fd              fd text: "#!kvd:=" then one "key=value" per line
//     -- sort by line, prefix dedup --> asm-list.fd2
//        "N)rest" = first N characters of the previous line, then rest
//     -- raw deflate (windowBits -15) --> asm-list.fd2.gz
//
// Sorting by line first is the point of the .2 form: "N)rest" only records how
// much of the previous line is reused, so neighbouring keys sharing a long
// prefix ("mov rax," / "mov rbx," / "mov rcx,") is what shrinks the file.
// Unsorted input still round-trips, it just compresses poorly.
//
// Uses lib-tree's sortList (it picks qsort above 10k) and lib-stream's Stream
// for the output, which grows one buffer instead of re-copying an accumulator
// on every append.
//
// Usage, from the repository root:
//   src/prj/fun/funcmd fun/lib/tools/make-asm-list.fun [src.fd [dst]]
// Defaults: src = fun/lib/asm-list.fd, dst = src & '2'. The sorted fd is
// written back to src (so the next run is a no-op) and dst / dst & '.gz' are
// written beside it.

use 'fun/lib/lib-zlib.fun';
use 'fun/lib/lib-regex.fun';
use 'fun/lib/lib-tree.fun';
use 'fun/lib/lib-stream.fun';

// Prefix dedup: each line becomes "<n>)<rest>" where <n> is the number of
// leading characters shared with the previous line. SseDecompress splits at
// the FIRST ')', so a ')' may not hide inside the reused prefix.
fun pack2(lines)
  result = Stream();
  var prev = '';
  var nl = 10.toChar();
  for cur in lines do
    var k = 0;
    var m = prev.length();
    if cur.length() < m then m = cur.length(); end if;
    while k < m and prev.toByte(k) = cur.toByte(k) do k += 1; end do;
    while k > 0 and cur.substr(0, k).subpos(')') >= 0 do k -= 1; end do;
    result.Write(k & ')' & cur.substr(k) & nl);
    prev = cur;
  end do;
  result = result.Get();
end fun;

fun joinLines(lines)
  result = Stream();
  var nl = 10.toChar();
  for l in lines do
    result.Write(l);
    result.Write(nl);
  end do;
  result = result.Get();
end fun;

//--------------------------------------------------------------
var src = 2.arg();
if src = nil or src = '' then src = 'fun/lib/asm-list.fd'; end if;
var dst = 3.arg();
if dst = nil or dst = '' then dst = src & '2'; end if;

var text = src.load();
if text = nil then raise '$src not found.'.eval(); end if;

var heads = []; // '#...' lines, kept in order, first
var ents  = []; // key=value lines, sorted
for l in split(/\r?\n/, text) do
  if l <> '' then
    if l.substr(0, 1) = '#' then heads.@add(l); else ents.@add(l); end if;
  end if;
end do;
sortList(ents);

var all = heads;
for l in ents do all.@add(l); end do;

var two = pack2(all);
var gz  = deflate(two, 9);

src.save(joinLines(all));
dst.save(two);
(dst & '.gz').save(gz);

?. 'asm-list: ' & ents.@count() & ' entries; ' &
   src & ' -> ' & two.length() & ' fd2 -> ' & gz.length() & ' fd2.gz';
