// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// build.fun: validate the Fun AI ontology and project it into model-facing
// artifacts.
//
//   fun ontology/tools/build.fun                 # validate + write dist/
//   fun ontology/tools/build.fun --check         # also execute every example
//   fun ontology/tools/build.fun --out build/ai  # write somewhere else
//
// Outputs under ontology/dist/:
//   fun.ontology.json      normalized graph
//   fun.ontology.jsonld    JSON-LD projection
//   index.json             compact id -> card index
//   llms.txt               discovery file for AI crawlers
//   llms-full.txt          full text projection
//   AGENTS.md              copy-paste instructions for coding agents
//   cards/level0.md        irreducible language card
//   cards/level1.md        language + idioms + pitfalls
//   cards/level2.md        everything, with examples
//   cards/pitfalls.md      the anti-pattern sheet

use 'ontology.fun';
use 'lib-path.fun';
use 'lib-set.fun';
use 'process.fun';
use 'fs.fun';

var TOOL_DIR = PathDir(1.arg());
var ROOT     = PathDir(TOOL_DIR);
var REPO     = PathDir(ROOT);
var DATA     = PathJoin([ROOT, 'data', 'fun.ontology.fd']);
var DIST     = PathJoin([ROOT, 'dist']);
var CHECK    = false;
var i = 2;
while i.arg() <> '' do
  if i.arg() = '--check' then CHECK = true; end if;
  if i.arg() = '--out' then
    i += 1;
    if i.arg() <> '' then DIST = i.arg(); end if;
  end if;
  i += 1;
end do;

var TYPES = new [
  construct: 1, semantic: 1, type: 1, builtin: 1, module: 1, symbol: 1,
  idiom: 1, pitfall: 1, error: 1, tool: 1, platform: 1, capability: 1, task: 1
];

fun abort(msg)
  ?. 'ontology: FAIL ' & msg;
  raise msg;
end fun;

fun note(msg)
  ?. 'ontology: warn ' & msg;
end fun;

var TYPE_TITLES = new [
  construct: 'Syntax', semantic: 'Semantics', type: 'Types', builtin: 'Built-ins',
  module: 'Modules', symbol: 'Symbols', idiom: 'Idioms', pitfall: 'Pitfalls',
  error: 'Errors', tool: 'Tooling', platform: 'Platforms',
  capability: 'Capabilities', task: 'Tasks'
];

fun typeTitle(t)
  result = TYPE_TITLES[t] or t;
end fun;

fun orderedTypes()
  result = ['construct', 'semantic', 'type', 'builtin', 'syntax', 'module',
            'symbol', 'idiom', 'pitfall', 'error', 'tool', 'platform',
            'capability', 'task'];
end fun;

fun cardOf(c)
  result = c.card or c.syntax or c.name;
end fun;

fun validate(o)
  var ids = new [];
  var bad = 0;
  var idRe = /^[a-z][a-z0-9]*(\.[a-z0-9][a-z0-9-]*)+$/;
  for c in o.concepts do
    var where = c.id or '(no id)';
    if c.id = nil then
      ?. 'ontology: FAIL concept without id';
      bad += 1;
    elsif c.id !~ idRe then
      ?. 'ontology: FAIL bad id: ' & c.id;
      bad += 1;
    elsif ids[c.id] <> nil then
      ?. 'ontology: FAIL duplicate id: ' & c.id;
      bad += 1;
    else
      ids[c.id] = c;
    end if;
    if TYPES[c.type] = nil then
      ?. 'ontology: FAIL bad type on ' & where & ': ' & (c.type or 'nil');
      bad += 1;
    end if;
    if c.level.type() = 0 or c.level < 0 or c.level > 2 then
      ?. 'ontology: FAIL bad level on ' & where;
      bad += 1;
    end if;
    if c.summary = nil or c.summary = '' then
      ?. 'ontology: FAIL missing summary on ' & where;
      bad += 1;
    end if;
    if c.card = nil and c.syntax = nil then
      note('no card/syntax on ' & where);
    end if;
    if c.examples = nil or c.examples.@count() = 0 then
      note('no example on ' & where);
    end if;
  end do;

  // Edges must resolve. A missing target is an error: stale edges are worse
  // than missing ones in a graph that agents trust.
  for c in o.concepts do
    if c.relations <> nil then
      for edge: targets in c.relations do
        for t in targets do
          if ids[t] = nil then
            ?. 'ontology: FAIL ' & c.id & '.' & edge & ' -> ' & t & ' (missing concept)';
            bad += 1;
          end if;
        end do;
      end do;
    end if;
  end do;

  if bad > 0 then abort(('' & bad) & ' validation error(s)'); end if;
  result = ids;
end fun;

fun renderIndex(o)
  var arr = new [];
  for c in o.concepts do
    var n = new [id: c.id, type: c.type, name: c.name, level: c.level, card: cardOf(c), summary: c.summary];
    if c.tags <> nil then n.tags = c.tags; end if;
    if c.intent <> nil then n.intent = c.intent; end if;
    arr.@add(n);
  end do;
  result = arr;
end fun;

fun renderJsonLd(o)
  var graph = new [];
  for c in o.concepts do
    var n = new [
      '@id': 'fun:' & c.id,
      '@type': 'fun:' & c.type,
      name: c.name,
      description: c.summary,
      level: c.level
    ];
    if c.card <> nil then n['card'] = c.card; end if;
    if c.syntax <> nil then n['syntax'] = c.syntax; end if;
    if c.tags <> nil then n['tags'] = c.tags; end if;
    if c['from'] <> nil then n['transfer'] = c['from']; end if;
    if c.intent <> nil then n['intent'] = c.intent; end if;
    if c.relations <> nil then
      var rel = new [];
      for k: vs in c.relations do
        var arr = new [];
        for v in vs do arr.@add('fun:' & v); end do;
        rel[k] = arr;
      end do;
      n['relations'] = rel;
    end if;
    if c.examples <> nil then
      var ex = new [];
      for e in c.examples do
        var x = new [code: e.code];
        if e.expect <> nil then x['expect'] = e.expect; end if;
        if e.expectError = true then x['expectError'] = true; end if;
        if e.runnable.type() = 11 and not e.runnable then x['runnable'] = false; end if;
        ex.@add(x);
      end do;
      n['examples'] = ex;
    end if;
    graph.@add(n);
  end do;
  var ctx = new [
    name: 'https://schema.org/name',
    description: 'https://schema.org/description',
    level: 'fun:level',
    card: 'fun:card',
    syntax: 'fun:syntax',
    tags: 'fun:tags',
    transfer: 'fun:transfer',
    relations: 'fun:relations',
    examples: 'fun:examples'
  ];
  var ld = new ['@context': ctx, '@id': 'fun:ontology', '@graph': graph];
  result = ld;
end fun;

fun renderLlms(o)
  var out = '# Fun Language' & 10.toChar() & 10.toChar();
  out &= '> Fun is a ~0.3 MB, zero-dependency scripting language that spans JSON and FD data, ' &
    'daily glue code, FFI, runtime C, JIT and raw machine code. This file is the AI entry point.' & 10.toChar() & 10.toChar();
  out &= 'Ontology v' & o.meta.version & ' for Fun ' & o.meta.funVersion & '.' & 10.toChar() & 10.toChar();
  out &= '## Start here' & 10.toChar() & 10.toChar();
  out &= '- [Language tutorial](https://funlang.org/docs/tutorial.md): task-oriented walkthrough' & 10.toChar();
  out &= '- [Standard library](https://funlang.org/docs/standard-library.md): module map and edge cases' & 10.toChar();
  out &= '- [Full manual](https://funlang.org/man.htm): chapter-by-chapter reference' & 10.toChar();
  out &= '- [Full ontology text](https://funlang.org/ontology/llms-full.txt): every concept and example' & 10.toChar() & 10.toChar();
  out &= '## Core concepts' & 10.toChar() & 10.toChar();
  for c in o.concepts do
    if c.level = 0 then
      out &= '- [' & c.id & '](https://funlang.org/ontology/#' & c.id & '): ' & c.name & '. ' & c.summary & 10.toChar();
    end if;
  end do;
  out &= 10.toChar() & 'The full index is in llms-full.txt.' & 10.toChar();
  result = out;
end fun;

fun renderFull(o)
  var out = '# Fun language, full AI context' & 10.toChar() & 10.toChar();
  out &= 'Ontology v' & o.meta.version & ' for Fun ' & o.meta.funVersion & '. ' &
    'Every example below is executed by `fun ontology/tools/build.fun --check`.' & 10.toChar() & 10.toChar();
  for t in orderedTypes() do
    var any = false;
    for c in o.concepts do
      if c.type = t then
        if not any then out &= '## ' & typeTitle(t) & 10.toChar() & 10.toChar(); any = true; end if;
        out &= render(c, 2) & 10.toChar();
      end if;
    end do;
  end do;
  result = out;
end fun;

fun renderCard(o, maxLevel, withExamples)
  var out = '# Fun language card' & 10.toChar() & 10.toChar();
  out &= 'Fun ' & o.meta.funVersion & ', ontology v' & o.meta.version & '.' & 10.toChar() & 10.toChar();
  for t in orderedTypes() do
    var any = false;
    for c in o.concepts do
      if c.type = t and c.level <= maxLevel then
        if not any then out &= '## ' & typeTitle(t) & 10.toChar() & 10.toChar(); any = true; end if;
        out &= '- `' & cardOf(c) & '` (' & c.id & '): ' & c.summary & 10.toChar();
        if withExamples and c.examples <> nil then
          for e in c.examples do
            if e.runnable.type() = 11 and not e.runnable then next; end if;
            out &= 10.toChar() & '```fun' & 10.toChar() & e.code & '```' & 10.toChar();
            exit;
          end do;
        end if;
      end if;
    end do;
    if any then out &= 10.toChar(); end if;
  end do;
  result = out;
end fun;

fun renderPitfalls(o)
  var out = '# Fun pitfalls' & 10.toChar() & 10.toChar();
  out &= 'Habits imported from other languages that break Fun. Each item is executable evidence.' & 10.toChar() & 10.toChar();
  for c in o.concepts do
    if c.type = 'pitfall' then
      out &= '## ' & c.name & ' (' & c.id & ')' & 10.toChar() & 10.toChar();
      out &= c.summary & 10.toChar() & 10.toChar();
      out &= '- Do not: `' & cardOf(c) & '`' & 10.toChar();
      if c.examples <> nil then
        for e in c.examples do
          if e.runnable.type() = 11 and not e.runnable then next; end if;
          out &= 10.toChar() & '```fun' & 10.toChar() & e.code & '```' & 10.toChar();
          if e.expect <> nil then
            out &= 'Output:' & 10.toChar() & 10.toChar() & '```text' & 10.toChar() & e.expect & '```' & 10.toChar();
          end if;
        end do;
      end if;
      out &= 10.toChar();
    end if;
  end do;
  result = out;
end fun;

fun renderAgents(o)
  var out = '# AGENTS.md snippet' & 10.toChar() & 10.toChar();
  out &= 'Use this block in an agent instruction file, a system prompt, or a tool description.' & 10.toChar() & 10.toChar();
  out &= '```text' & 10.toChar();
  out &= 'When writing Fun (files end in .fun, .foo or .fxx):' & 10.toChar();
  out &= '- Statements end with `;`. Blocks end with `end if;`, `end fun;`, `end class;`, `end do;`, `end loop;`, `end try;`.' & 10.toChar();
  out &= '- `?.` prints a line; `var x = 1;` declares; `fun f(a) result = a; end fun;` returns.' & 10.toChar();
  out &= '- `[1,2]` is a list; `new [k: v]` is a string-keyed map; missing keys compare equal to nil.' & 10.toChar();
  out &= '- Nil enters arithmetic as 0, and a missing value also compares equal to 0. Use `m.@has(k)` when presence matters.' & 10.toChar();
  out &= '- Built-in methods use `@`: `x.@toJson()`, `s.@count()`, `m.@(0)`.' & 10.toChar();
  out &= '- `=` is equality inside expressions, `<>` is not-equal; there is no `==`.' & 10.toChar();
  out &= '- Always initialize `result` at function entry; it is not cleared between calls.' & 10.toChar();
  out &= '- Verify with `fun check` (MCP) or `fun ontology/tools/build.fun --check`.' & 10.toChar();
  out &= '```' & 10.toChar() & 10.toChar();
  out &= '## Task pack' & 10.toChar() & 10.toChar() & codeBlock('text', context(o, 'general Fun development', 2400, 1));
  result = out;
end fun;

fun runExamples(o, ids)
  var total = 0;
  var failed = 0;
  for c in o.concepts do
    if c.examples = nil then next; end if;
    var n = 0;
    for e in c.examples do
      if e.runnable.type() = 11 and not e.runnable then next; end if;
      n += 1;
      total += 1;
      var d = fs.tempDir('fun-ont-');
      var f = PathJoin([d, 'case.fun']);
      f.save(e.code);
      var r = process.run(0.arg(), [f], [timeout: 8000, cwd: REPO]);
      fs.removeAll(d);
      var ok = false;
      if e.expectError = true then
        ok = r.exitCode <> 0;
      else
        ok = (r.exitCode = 0) and (r.stdout = e.expect);
      end if;
      if not ok then
        failed += 1;
        ?. 'FAIL ' & c.id & ' #' & n;
        ?. '  exit ' & r.exitCode;
        if e.expectError = true then
          ?. '  expected a non-zero exit';
        else
          ?. '  expected: ' & (e.expect or '') & '';
          ?. '  actual  : ' & (r.stdout or '') & '';
          if r.stderr <> '' then ?. '  stderr  : ' & r.stderr; end if;
        end if;
      end if;
    end do;
  end do;
  ?. 'examples: ' & total & ' run, ' & failed & ' failed';
  if failed > 0 then abort('examples failed'); end if;
end fun;

// ---------------------------------------------------------------------------
// main

fs.mkdirAll(DIST);
fs.mkdirAll(PathJoin([DIST, 'cards']));

var o = load(DATA);
?. 'ontology: ' & o.concepts.@count() & ' concepts, v' & o.meta.version;
var ids = validate(o);
?. 'ontology: relations OK';

PathJoin([DIST, 'fun.ontology.json']).save(o.@toJson(json: true));
PathJoin([DIST, 'fun.ontology.jsonld']).save(renderJsonLd(o).@toJson(json: true));
PathJoin([DIST, 'index.json']).save(renderIndex(o).@toJson(json: true));
PathJoin([DIST, 'llms.txt']).save(renderLlms(o));
PathJoin([DIST, 'llms-full.txt']).save(renderFull(o));
PathJoin([DIST, 'AGENTS.md']).save(renderAgents(o));
PathJoin([DIST, 'cards', 'level0.md']).save(renderCard(o, 0, false));
PathJoin([DIST, 'cards', 'level1.md']).save(renderCard(o, 1, true));
PathJoin([DIST, 'cards', 'level2.md']).save(renderCard(o, 2, true));
PathJoin([DIST, 'cards', 'pitfalls.md']).save(renderPitfalls(o));
?. 'ontology: wrote ' & DIST;

if CHECK then runExamples(o, ids); end if;
