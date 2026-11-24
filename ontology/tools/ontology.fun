// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// ontology: shared reader / search / context compiler for the Fun AI ontology.
//
//   use 'ontology.fun';
//   var o = load('ontology/data/fun.ontology.fd');
//   var hits = search(o, 'parse json', 5);
//   var pack = context(o, 'write a CLI that reads JSON', 4000);
//
// The graph is authored in FD and projected to JSON by tools/build.fun. This
// module keeps no global state so the build tool and the MCP server can share
// exactly the same selection logic.

use 'lib-set.fun';

fun load(path)
  result = path.load().getJson(fd: true);
end fun;

fun index(o)
  var m = new [];
  for c in o.concepts do
    m[c.id] = c;
  end do;
  result = m;
end fun;

fun join(xs, sep)
  result = '';
  if xs = nil then return; end if;
  var first = true;
  for x in xs do
    if not first then result &= sep; end if;
    result &= '' & x;
    first = false;
  end do;
end fun;

fun words(q)
  result = new [];
  var s = q.lower().replace(%[,;:/\\|()\[\]{}"'`]+%g, ' ');
  var ws = s.match(/\S+/g);
  if ws <> nil then
    for w in ws do
      if w <> '' then result.@add(w); end if;
    end do;
  end if;
end fun;

fun haystack(c)
  result = c.id & ' ' & c.name & ' ' & c.summary;
  if c.card <> nil then result &= ' ' & c.card; end if;
  if c.aliases <> nil then result &= ' ' & join(c.aliases, ' '); end if;
  if c.tags <> nil then result &= ' ' & join(c.tags, ' '); end if;
  if c.intent <> nil then result &= ' ' & join(c.intent, ' '); end if;
  if c['from'] <> nil then
    for k: v in c['from'] do
      result &= ' ' & k & ' ' & ('' & v);
    end do;
  end if;
  result = result.lower();
end fun;

fun score(c, q, ws)
  result = 0;
  if c.level = 0 then result += 2; end if;
  if c.type = 'pitfall' then result += 1; end if;
  if q = '' then return; end if;
  var id = c.id.lower();
  var hay = haystack(c);
  if id.subpos(q) >= 0 then result += 12; end if;
  if hay.subpos(q) >= 0 then result += 6; end if;
  for w in ws do
    if w <> '' then
      if id.subpos(w) >= 0 then result += 6; end if;
      if hay.subpos(w) >= 0 then result += 2; end if;
    end if;
  end do;
end fun;

// Ranked concepts. Ties keep ontology order. Empty query returns the level-0
// spine first, then level 1, then the rest.
fun search(o, q, limit)
  var ws = words(q);
  var used = new [];
  var out = new [];
  var n = 0;
  if limit = nil or limit < 1 then limit = 12; end if;
  while n < limit and n < o.concepts.@count() do
    var best = nil;
    var bestScore = -1;
    for c in o.concepts do
      if used[c.id] = nil then
        var s = score(c, q, ws);
        if s > bestScore then
          bestScore = s;
          best = c;
        end if;
      end if;
    end do;
    if best = nil then exit; end if;
    if q <> '' and bestScore <= 0 then exit; end if;
    used[best.id] = true;
    out.@add(best);
    n += 1;
  end do;
  result = out;
end fun;

fun codeBlock(lang, code)
  result = '```' & lang & 10.toChar() & code & '```';
end fun;

fun render(c, detail)
  var out = '### ' & c.name & ' (`' & c.id & '`)' & 10.toChar() & 10.toChar();
  out &= c.summary & 10.toChar() & 10.toChar();
  if c.card <> nil and detail < 2 then
    out &= codeBlock('fun', c.card) & 10.toChar() & 10.toChar();
  end if;
  if detail >= 1 and c.syntax <> nil then
    out &= 'Syntax: ' & codeBlock('fun', c.syntax) & 10.toChar() & 10.toChar();
  end if;
  if detail >= 1 and c['from'] <> nil then
    out &= 'Transfer:';
    for k: v in c['from'] do out &= ' ' & k & ' `' & v & '`;'; end do;
    out &= 10.toChar() & 10.toChar();
  end if;
  if detail >= 2 and c.examples <> nil then
    for ex in c.examples do
      if ex.runnable.type() = 11 and not ex.runnable then next; end if;
      if ex.kind = 'bad' then out &= 'Do not:' & 10.toChar(); end if;
      out &= codeBlock('fun', ex.code);
      if ex.expect <> nil then
        out &= 10.toChar() & 'Expected output:' & 10.toChar() & codeBlock('text', ex.expect);
      end if;
      out &= 10.toChar();
    end do;
  end if;
  result = out;
end fun;

fun header(o)
  result = '# Fun language context' & 10.toChar() & 10.toChar();
  result &= '> ' & o.meta.name & ' v' & o.meta.version & ' for Fun ' & o.meta.funVersion & 10.toChar() & 10.toChar();
  result &= 'Fun is a ~0.3 MB, zero-dependency scripting language. Statements end with `;`. ' &
    'Blocks end with `end if`, `end fun`, `end class`, `end do`; the `;` after a block closer is optional. ' &
    '`?.` prints. `fun f(a) result = a; end fun;` returns. ' &
    '`[1,2]` is a list; `new [k: v]` is a map. ' &
    'Missing values compare equal to nil and to 0, so use `m.@has(k)` when presence matters.' & 10.toChar() & 10.toChar();
end fun;

// Assemble a task-specific pack under `budget` characters (~4 chars/token).
// detail: 0 card only, 1 summary + syntax, 2 summary + syntax + examples.
fun context(o, task, budget, detail)
  if budget = nil then budget = 4000; end if;
  if detail = nil then detail = 1; end if;
  var out = header(o);
  if task <> nil and task <> '' then
    out &= '## Task' & 10.toChar() & 10.toChar() & task & 10.toChar() & 10.toChar();
  end if;
  out &= '## Concepts' & 10.toChar() & 10.toChar();
  var limit = 40;
  var picked = search(o, task or '', limit);
  var included = new [];
  for c in picked do
    var block = render(c, detail);
    if out.length() + block.length() > budget then
      if detail > 0 then
        block = '- `' & (c.card or c.name) & '` (' & c.id & ')' & 10.toChar();
      else
        next;
      end if;
    end if;
    if out.length() + block.length() > budget then next; end if;
    out &= block & 10.toChar();
    included[c.id] = true;
  end do;
  // Always surface the highest-value pitfalls if there is room.
  if budget >= 2000 then
    out &= '## Pitfalls' & 10.toChar() & 10.toChar();
    for c in o.concepts do
      if c.type = 'pitfall' and included[c.id] = nil then
        var line = '- `' & (c.card or c.name) & '` (' & c.id & '): ' & c.summary & 10.toChar();
        if out.length() + line.length() <= budget then out &= line; end if;
      end if;
    end do;
  end if;
  result = out;
end fun;
