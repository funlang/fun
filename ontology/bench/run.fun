// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// FunBench seed runner.
//
//   fun ontology/bench/run.fun solutions/hello.fun   # one task by file name
//   fun ontology/bench/run.fun --all                 # all reference solutions
//   fun ontology/bench/run.fun candidate.fun         # all tasks against one file
//
// A candidate may define all task functions in one file, or be a single-task
// solution whose file name matches the task id.

use 'lib-path.fun';
use 'lib-set.fun';
use 'process.fun';
use 'fs.fun';

var TOOL_DIR = PathDir(1.arg());
var BENCH    = TOOL_DIR;
var ROOT     = PathDir(BENCH);
var REPO     = PathDir(ROOT);
var TASKS    = PathJoin([BENCH, 'tasks.fd']);
var SOLS     = PathJoin([BENCH, 'solutions']);

var ALL = false;
var CAND = nil;
var i = 2;
while i.arg() <> '' do
  if i.arg() = '--all' then
    ALL = true;
  elsif CAND = nil then
    CAND = i.arg();
  end if;
  i += 1;
end do;

var data = TASKS.load().getJson(fd: true);
var total = 0;
var passed = 0;
var failed = 0;

for t in data.tasks do
  var sol = CAND;
  if ALL then
    var name = t.id & '.fun';
    sol = PathJoin([SOLS, name]);
  end if;
  if sol = nil then
    ?. 'usage: fun ontology/bench/run.fun <solution.fun> | --all';
    raise 'no solution';
  end if;
  var code = sol.load();
  var n = 0;
  for test in t.tests do
    n += 1;
    total += 1;
    var d = fs.tempDir('funbench-');
    var f = PathJoin([d, 'case.fun']);
    f.save(code & 10.toChar() & 10.toChar() & test.code);
    var r = process.run(0.arg(), [f], [timeout: 8000, cwd: REPO]);
    fs.removeAll(d);
    if r.exitCode = 0 and r.stdout = test.expect then
      passed += 1;
      ?. 'PASS ' & t.id & ' #' & n;
    else
      failed += 1;
      ?. 'FAIL ' & t.id & ' #' & n & ' (exit ' & r.exitCode & ')';
      ?. '  expected: ' & (test.expect or '');
      ?. '  actual  : ' & (r.stdout or '');
      if r.stderr <> '' then ?. '  stderr  : ' & r.stderr; end if;
    end if;
  end do;
end do;

?. 'score: ' & passed & '/' & total & ' (' & (passed * 100 div total) & '%)';
if failed > 0 then raise 'FunBench failed'; end if;
