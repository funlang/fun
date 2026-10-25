// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/levels: numeric order and the canonical level names.
var _LOG_TRACE    = 10;
var _LOG_DEBUG    = 20;
var _LOG_INFO     = 30;
var _LOG_WARNING  = 40;
var _LOG_ERROR    = 50;
var _LOG_CRITICAL = 60;
var _LOG_OFF      = 100;

var _levelByName = [
  trace: _LOG_TRACE, debug: _LOG_DEBUG, info: _LOG_INFO,
  warn: _LOG_WARNING, warning: _LOG_WARNING,
  error: _LOG_ERROR, fatal: _LOG_CRITICAL, critical: _LOG_CRITICAL,
  off: _LOG_OFF
];

fun _levelValue(v)
  if v = nil then result = _LOG_INFO; return; end if;
  if v.type() = 8 then
    var n = _levelByName[('' & v).lower()];
    if n = nil then raise 'logging: unknown level ' & v; end if;
    result = n;
    return;
  end if;
  result = v * 1;
end fun;

fun _levelName(n)
  if n = _LOG_TRACE then result = 'TRACE'; return; end if;
  if n = _LOG_DEBUG then result = 'DEBUG'; return; end if;
  if n = _LOG_INFO then result = 'INFO'; return; end if;
  if n = _LOG_WARNING then result = 'WARNING'; return; end if;
  if n = _LOG_ERROR then result = 'ERROR'; return; end if;
  if n = _LOG_CRITICAL then result = 'CRITICAL'; return; end if;
  if n = _LOG_OFF then result = 'OFF'; return; end if;
  result = 'LEVEL' & n;
end fun;
