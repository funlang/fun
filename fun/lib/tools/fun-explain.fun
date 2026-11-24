// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-explain: run the repository's ontology explain tool.
//
//   fun explain json
//   fun explain "for loop"
//   fun explain csv.reader
//
// The ontology and its generated stdlib index live in <repo>/ontology, which
// is not installed next to the binary. This wrapper finds the source tree
// (from its own path, the executable's path, or the current directory) and
// forwards every argument to ontology/tools/explain.fun.

use '../lib-path.fun';
use 'fun-tool-util.fun';

var _self = 1.arg();
var _toolDir = PathDir(_self);
var _exeDir = PathDir(0.arg());

fun candidate(base)
  result = PathJoin([base, 'ontology', 'tools', 'explain.fun']);
end fun;

fun findExplain()
  // development tree: <repo>/fun/lib/tools/fun-explain.fun
  var p = candidate(PathDir(PathDir(PathDir(_toolDir))));
  if UtilExists(p) then result = p; return; end if;
  // installed binary with the source tree beside it
  p = candidate(PathDir(PathDir(PathDir(_exeDir))));
  if UtilExists(p) then result = p; return; end if;
  // current directory, then its ancestors
  var d = '.';
  var i = 0;
  while i < 6 do
    p = candidate(d);
    if UtilExists(p) then result = p; return; end if;
    d = PathJoin([d, '..']);
    i += 1;
  end do;
  result = '';
end fun;

var _script = findExplain();
if _script = '' then
  ?. 'fun explain: ontology not found.';
  ?. 'Run from the Fun source tree, or call ontology/tools/explain.fun directly.';
  UtilExit(1);
end if;

var _cmd = UtilQuote(0.arg()) & ' ' & UtilQuote(_script);
var _i = 2;
while _i.arg() <> '' do
  _cmd &= ' ' & UtilQuote(_i.arg());
  _i += 1;
end do;

var _rc = UtilExitCode(UtilSystem(_cmd));
if _rc <> 0 then UtilExit(_rc); end if;
