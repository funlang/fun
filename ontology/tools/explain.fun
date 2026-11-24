// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// explain: one symbol or topic, from the ontology and the stdlib index.
//
//   fun ontology/tools/explain.fun json
//   fun ontology/tools/explain.fun "for loop"
//   fun ontology/tools/explain.fun csv.reader
//
// Prints ranked ontology concepts with their runnable cards, then matching
// pure-Fun standard library exports. The data is the generated dist, so this
// is a fast read-only view; edit ontology/data/fun.ontology.fd and rebuild to
// change it.

use 'ontology.fun';
use 'lib-path.fun';
use 'fs.fun';

var TOOL_DIR = PathDir(1.arg());
var ROOT     = PathDir(TOOL_DIR);
var REPO     = PathDir(ROOT);
var DATA     = PathJoin([ROOT, 'data', 'fun.ontology.fd']);
var STD_JSON = PathJoin([ROOT, 'dist', 'stdlib.json']);
var O        = load(DATA);

fun usage()
  ?. 'usage: fun ontology/tools/explain.fun <symbol-or-topic>';
  ?. '';
  ?. '  explain.fun json';
  ?. '  explain.fun "for loop"';
  ?. '  explain.fun csv.reader';
  ?. '';
  ?. 'Data: ontology/data/fun.ontology.fd + ontology/dist/stdlib.json';
end fun;

fun exactConcept(q)
  var ql = q.lower();
  result = nil;
  for c in O.concepts do
    if c.id.lower() = ql or c.name.lower() = ql then
      result = c;
      return;
    end if;
  end do;
end fun;

fun mentions(c, q)
  var hay = haystack(c);
  for w in words(q) do
    if w <> '' and hay.subpos(w) >= 0 then result = true; return; end if;
  end do;
end fun;

fun printConcepts(q)
  var exact = exactConcept(q);
  var hits = search(O, q, 12);
  var shown = new [];
  if exact <> nil then shown.@add(exact); end if;
  for c in hits do
    if shown.@count() >= 6 then exit; end if;
    var dup = false;
    for s in shown do
      if s.id = c.id then dup = true; end if;
    end do;
    if not dup and mentions(c, q) then shown.@add(c); end if;
  end do;
  if shown.@count() = 0 then
    ?. 'No ontology concept matched.';
    ?. '';
    return;
  end if;
  ?. '== Ontology ==';
  ?. '';
  for c in shown do
    var detail = 1;
    if exact <> nil and c.id = exact.id then detail = 2; end if;
    ?. render(c, detail);
  end do;
end fun;

fun printStdlib(q)
  if not fs.exists(STD_JSON) then
    ?. 'stdlib index not built: ' & STD_JSON;
    return;
  end if;
  var std = STD_JSON.load().getJson(json: true);
  var ql = q.lower();
  var shown = 0;
  var out = new [];
  for m in std.modules do
    var ml = m.name.lower();
    var hits = new [];
    for e in m.exports do
      if e.name.lower().subpos(ql) >= 0 then hits.@add(e); end if;
    end do;
    if ml.subpos(ql) >= 0 or hits.@count() > 0 then
      out.@add(new [m: m, hits: hits]);
    end if;
  end do;
  if out.@count() = 0 then
    ?. 'No stdlib module or export matched.';
    return;
  end if;
  ?. '== Standard library ==';
  ?. '';
  for r in out do
    if shown >= 8 then
      ?. '... ' & (out.@count() - shown) & ' more module(s); narrow the query.';
      return;
    end if;
    var m = r.m;
    ?. m.name & '  (' & m.file & ')';
    if m.summary <> nil and m.summary <> '' then ?. '  ' & m.summary; end if;
    for e in r.hits do
      ?. '  ' & e.kind & '  ' & e.name & '   ' & (e.signature or '');
    end do;
    ?. '';
    shown += 1;
  end do;
end fun;

var q = 2.arg() or '';
if q = '' then
  usage();
  exit;
end if;

?. 'explain: ' & q;
?. '';
printConcepts(q);
printStdlib(q);
