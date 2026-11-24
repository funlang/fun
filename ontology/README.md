# Fun AI ontology layer

An executable, versioned knowledge graph that teaches an AI how to write Fun.
It is not a second manual. It is the machine-facing projection of the manual,
the grammar, the standard library, the regression suite and the pitfalls that
models actually hit.

Status: **seed (v0.1.0)**. 78 concepts, 93 executed examples, 119 indexed
stdlib modules, zero stale relations. The design rationale is in
[`docs/ai-ontology.md`](../docs/ai-ontology.md) and
[`docs/ai-ontology.zh.md`](../docs/ai-ontology.zh.md).

## Why

LLMs write a language well when four things line up: prior exposure, relevant
context, a tool that answers grounded questions, and a fast verification loop.
Fun has a small pretraining footprint, and its Pascal-family syntax invites
negative transfer from JavaScript, Python and C. The ontology compensates by
making the language small, explicit and checkable:

- every concept has a stable id (`syntax.json`, `pitfall.optional-chain`);
- every concept has a one-line card usable in a token budget;
- every concept has cross-language anchors (`from.js`, `from.py`, `from.c`);
- every claim points at a runnable example with expected output;
- the build fails on stale relations.

## Layout

```text
ontology/
  schema/ontology.schema.json     JSON Schema for the graph
  data/fun.ontology.fd            source of truth (FD, commented)
  tools/ontology.fun              loader, search, context compiler
  tools/build.fun                 validate + project + execute examples
  tools/explain.fun               symbol/topic lookup (ontology + stdlib)
  tools/mcp-server.fun            MCP stdio server
  bench/                          FunBench seed (5 tasks, 10 tests)
  dist/                           generated, safe to delete
    fun.ontology.json
    fun.ontology.jsonld
    index.json
    stdlib.json
    llms.txt
    llms-full.txt
    AGENTS.md
    cards/level0.md
    cards/level1.md
    cards/level2.md
    cards/pitfalls.md
```

## Commands

From the repository root:

```text
fun ontology/tools/build.fun              # validate and write dist/
fun ontology/tools/build.fun --check      # execute every example
fun ontology/tools/explain.fun json       # one symbol or topic
fun ontology/tools/mcp-server.fun         # MCP server over stdio
fun ontology/bench/run.fun --all          # reference solutions: 10/10
```

Typical output:

```text
ontology: 78 concepts, v0.1.0
ontology: relations OK
ontology: wrote ontology/dist
examples: 93 run, 0 failed
```

`fun explain <symbol-or-topic>` is the same lookup at the binary level. It
prints ranked concepts with runnable cards, then matching stdlib modules and
exports; the wrapper forwards to `ontology/tools/explain.fun` in the source
tree.

## Using the projections

`dist/cards/level0.md` is the irreducible language card: about 8 KB, suitable
for a system prompt or an `AGENTS.md` block.

`dist/cards/level1.md` adds idioms, pitfalls, modules and tooling, with one
example per concept.

`dist/cards/level2.md` is the full reference. `dist/llms.txt` is the discovery
file for crawlers; `dist/llms-full.txt` is the full text.

`dist/AGENTS.md` contains a ready-to-paste instruction block and a task pack.

## MCP tools

The server speaks newline-delimited JSON-RPC 2.0. It exposes:

| Tool | Arguments | Returns |
| ---- | --------- | ------- |
| `ontology_search` | `query`, `limit` | ranked concept summaries |
| `ontology_get` | `id` | one full concept with examples |
| `fun_context` | `task`, `budget`, `detail` | a budgeted prompt pack |
| `fun_run` | `code`, `stdin`, `timeoutMs` | exit code, stdout, stderr |
| `fun_check` | `code` | parses code without running top-level statements |
| `stdlib_search` | `query`, `limit` | modules and exported signatures |

Register it with an MCP client as `fun ontology/tools/mcp-server.fun`.

`fun_run` executes code in a child process. For untrusted input, wrap the
interpreter with `fun-safe` and a container or OS sandbox.

## Data model

A concept is a small record:

```fd
-
  id syntax.json
  type construct
  name JSON
  summary The built-in `value.@toJson()` emits JSON; ...
  level 0
  tags
    - core
    - data
  card `s.getJson(json: true); v.@toJson(json: true);`
  intent
    - json parse
    - 解析JSON
  from
    js `JSON.parse(s); JSON.stringify(v)`
    py `json.loads(s); json.dumps(v)`
  relations
    seeAlso
      - syntax.fd
      - module.lib-json
  examples
    -
      code `var m = '{"a": 1}'.getJson(json: true);
?. m.a;
`
      expect `1
`
```

Types: `construct`, `semantic`, `type`, `builtin`, `module`, `symbol`,
`idiom`, `pitfall`, `error`, `tool`, `platform`, `capability`, `task`.

Levels: `0` must know, `1` common, `2` specialist. The level is the primary
token-budget knob.

Relations: `partOf`, `requires`, `seeAlso`, `replaces`, `conflictsWith`,
`hasExample`, `failsWhen`, `fixedBy`, `teaches`.

## Adding a concept

1. Add the record to `data/fun.ontology.fd`.
2. Give it at least one runnable example with exact expected output.
3. Run `fun ontology/tools/build.fun --check`.
4. Keep ids lowercase and stable. Never reuse an id for a new meaning.
5. Prefer a card that fits on one line. Prose belongs in `summary`.

The build treats a missing relation target as a failure, so a concept cannot
silently rot.

## Growth path

- M1 (in progress): the stdlib index and `stdlib_search` are in place; next
  are richer signatures, doctests and the `fun check` / `fun explain` CLI.
- M2: `FunBench`, a hidden-test benchmark with first-shot pass rate, repair
  turns and token cost.
- M3: ingest failed generations (opt-in) as `pitfall` proposals.
- M4: publish `llms.txt` and the cards on funlang.org, and ship editor rules.
