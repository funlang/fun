// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// mcp-server: a Model Context Protocol server over stdio (newline-delimited
// JSON-RPC 2.0). It exposes the ontology to any MCP-capable agent.
//
//   fun ontology/tools/mcp-server.fun
//
// Add to an MCP client, for example:
//   { "command": "fun", "args": ["ontology/tools/mcp-server.fun"] }
//
// Tools:
//   ontology_search  {query, limit}          ranked concepts
//   ontology_get     {id}                    one full concept
//   fun_context      {task, budget, detail}  task-specific prompt pack
//   fun_run          {code, stdin, timeoutMs} run a script in a child process
//   fun_check        {code}                  parse without executing top level
//
// This server never writes to stdout except JSON-RPC responses. Keep stderr
// for diagnostics.

use 'ontology.fun';
use 'lib-path.fun';
use 'lib-set.fun';
use 'process.fun';
use 'fs.fun';

var TOOL_DIR = PathDir(1.arg());
var ROOT     = PathDir(TOOL_DIR);
var REPO     = PathDir(ROOT);
var DATA     = PathJoin([ROOT, 'data', 'fun.ontology.fd']);
var O        = load(DATA);

fun send(obj)
  ?. obj.@toJson(json: true);
end fun;

fun reply(id, result)
  send(new [jsonrpc: '2.0', id: id, result: result]);
end fun;

fun replyError(id, code, message)
  send(new [jsonrpc: '2.0', id: id, error: new [code: code, message: message]]);
end fun;

fun textResult(text)
  result = new [content: [new [type: 'text', text: text]]];
end fun;

fun cardOf(c)
  result = c.card or c.syntax or c.name;
end fun;

fun toolList()
  var searchSchema = new [
    type: 'object',
    properties: new [
      query: new [type: 'string', description: 'Natural language or identifier search terms'],
      limit: new [type: 'integer', description: 'Maximum results, default 10']
    ],
    required: ['query']
  ];
  var getSchema = new [
    type: 'object',
    properties: new [id: new [type: 'string', description: 'Concept id, e.g. syntax.json']],
    required: ['id']
  ];
  var contextSchema = new [
    type: 'object',
    properties: new [
      task: new [type: 'string', description: 'What the agent is trying to write'],
      budget: new [type: 'integer', description: 'Character budget, default 4000 (~1000 tokens)'],
      detail: new [type: 'integer', description: '0 card, 1 syntax, 2 examples']
    ],
    required: ['task']
  ];
  var runSchema = new [
    type: 'object',
    properties: new [
      code: new [type: 'string', description: 'Fun source to execute'],
      stdin: new [type: 'string', description: 'Optional standard input'],
      timeoutMs: new [type: 'integer', description: 'Default 8000']
    ],
    required: ['code']
  ];
  var checkSchema = new [
    type: 'object',
    properties: new [code: new [type: 'string', description: 'Fun source to parse']],
    required: ['code']
  ];
  result = new [tools: [
    new [name: 'ontology_search', description: 'Search the Fun language ontology by intent, identifier or keyword.', inputSchema: searchSchema],
    new [name: 'ontology_get', description: 'Return one concept with summary, syntax, transfer notes and runnable examples.', inputSchema: getSchema],
    new [name: 'fun_context', description: 'Compile a token-budgeted Fun context pack for a task.', inputSchema: contextSchema],
    new [name: 'fun_run', description: 'Run Fun code in a child process and return exitCode, stdout and stderr.', inputSchema: runSchema],
    new [name: 'fun_check', description: 'Parse Fun code without running its top-level statements.', inputSchema: checkSchema]
  ]];
end fun;

fun doSearch(a)
  var hits = search(O, a.query or '', a.limit or 10);
  var arr = [];
  for c in hits do
    var n = new [id: c.id, name: c.name, level: c.level, card: cardOf(c), summary: c.summary];
    if c.tags <> nil then n.tags = c.tags; end if;
    arr.@add(n);
  end do;
  result = textResult(arr.@toJson(json: true));
end fun;

fun doGet(a)
  var idx = index(O);
  var c = idx[a.id];
  if c = nil then
    result = new [isError: true, content: [new [type: 'text', text: 'Unknown concept: ' & (a.id or '')]]];
  else
    result = textResult(c.@toJson(json: true));
  end if;
end fun;

fun doContext(a)
  var detail = a.detail;
  if detail.type() = 0 then detail = 1; end if;
  result = textResult(context(O, a.task or '', a.budget or 4000, detail));
end fun;

fun runSource(code, stdin, timeoutMs, wrap)
  var d = fs.tempDir('fun-mcp-');
  var f = PathJoin([d, 'case.fun']);
  var src = code;
  if wrap then
    src = 'fun __mcp_check__()' & 10.toChar() & code & 10.toChar() & 'end fun;' & 10.toChar();
  end if;
  f.save(src);
  var r = process.run(0.arg(), [f], [timeout: timeoutMs or 8000, cwd: REPO, stdin: stdin or '']);
  fs.removeAll(d);
  result = r;
end fun;

fun doRun(a)
  var r = runSource(a.code or '', a.stdin, a.timeoutMs, false);
  var out = 'exitCode: ' & r.exitCode & 10.toChar() & 10.toChar() & 'stdout:' & 10.toChar() & r.stdout;
  if r.stderr <> '' then out &= 10.toChar() & 'stderr:' & 10.toChar() & r.stderr; end if;
  result = new [isError: r.exitCode <> 0, content: [new [type: 'text', text: out]]];
end fun;

fun doCheck(a)
  var r = runSource(a.code or '', '', 8000, true);
  if r.exitCode = 0 then
    result = textResult('ok');
  else
    result = new [isError: true, content: [new [type: 'text', text: (r.stderr or 'syntax error')]]];
  end if;
end fun;

fun callTool(name, a)
  if name = 'ontology_search' then result = doSearch(a); return; end if;
  if name = 'ontology_get' then result = doGet(a); return; end if;
  if name = 'fun_context' then result = doContext(a); return; end if;
  if name = 'fun_run' then result = doRun(a); return; end if;
  if name = 'fun_check' then result = doCheck(a); return; end if;
  result = new [isError: true, content: [new [type: 'text', text: 'Unknown tool: ' & name]]];
end fun;

fun handle(msg)
  var id = msg.id;
  var method = msg.method or '';
  if method = 'initialize' then
    var r = new [
      protocolVersion: '2024-11-05',
      capabilities: new [tools: new [listChanged: false]],
      serverInfo: new [name: 'fun-ontology', version: O.meta.version],
      instructions: 'Fun is a small Pascal-family scripting language. Call fun_context before writing code, then fun_check or fun_run.'
    ];
    reply(id, r);
  elsif method = 'notifications/initialized' then
    // notification: no response
  elsif method = 'ping' then
    reply(id, new [ok: true]);
  elsif method = 'tools/list' then
    reply(id, toolList());
  elsif method = 'tools/call' then
    var p = msg.params or new [];
    var a = p.arguments or new [];
    reply(id, callTool(p.name or '', a));
  elsif method = 'resources/list' then
    reply(id, new [resources: []]);
  elsif method = 'prompts/list' then
    reply(id, new [prompts: []]);
  else
    if id <> nil then replyError(id, -32601, 'Method not found: ' & method); end if;
  end if;
end fun;

// ---------------------------------------------------------------------------
// stdio loop

var ok = true;
var line = 'line'.input(ok: ok);
while ok do
  if line <> '' then
    try
      var msg = line.getJson(json: true);
      if msg <> nil then handle(msg); end if;
    except
      var e = 'lastError'.reflect();
      var m = '';
      if e <> nil then m = e.message or ''; end if;
      replyError(nil, -32700, 'Parse error: ' & m);
    end try;
  end if;
  line = 'line'.input(ok: ok);
end do;
